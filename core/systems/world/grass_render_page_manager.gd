class_name GrassRenderPageManager
extends RefCounted

const GrassRenderPage = preload("res://core/systems/world/grass_render_page.gd")
const EntryState = preload("res://core/systems/world/grass_render_page_manager_entry.gd")
const ResidencyState = preload(
	"res://core/systems/world/grass_render_page_manager_residency.gd"
)
const PAGE_SLOT_COUNT: int = GrassRenderPage.PAGE_SLOT_COUNT
const PAGE_WIDTH_CHUNKS: int = GrassRenderPage.PAGE_WIDTH_CHUNKS
const CHUNK_SIZE_PX: int = GrassRenderPage.CHUNK_SIZE_PX
const PRIORITY_CLASS_REVEAL: int = 1
const PRIORITY_CLASS_STREAMING: int = 2
const INVALID_PAGE_COORD := Vector2i(1 << 29, 1 << 29)

var _owner_root: Node = null
var _backend: Object = null
var _grass_atlas: Texture2D = null
var _grass_material: ShaderMaterial = null
var _grass_shadow_atlas: Texture2D = null
var _grass_shadow_material: ShaderMaterial = null
var _shadow_material: ShaderMaterial = null
var _spore_material: ShaderMaterial = null
var _max_resident_pages: int = 1
var _epoch: int = 0
var _anchor: int = 0
var _entries: Dictionary = { }
var _source_chunks: Dictionary = { }
var _prestage_chunks: Dictionary = { }
var _ready_visual_pages: Array[Vector2i] = []
var _ready_visual_set: Dictionary = { }
var _residency: ResidencyState = ResidencyState.new()
var _focused_page: Vector2i = INVALID_PAGE_COORD
var _backend_demand_dirty: bool = false
var _next_page_revision: int = 0
var _next_lru_stamp: int = 0
var _resident_page_count: int = 0
var _active_slot_count: int = 0
var _prestage_slot_count: int = 0
var _inflight_page_count: int = 0
var _ready_visual_page_count: int = 0
var _retry_parked_page_count: int = 0
var _native_request_count_total: int = 0
var _native_merge_complete_count_total: int = 0
var _raw_upload_count_total: int = 0
var _commit_count_total: int = 0
var _cache_hit_count_total: int = 0
var _eviction_count_total: int = 0
var _stale_completion_reject_count_total: int = 0
var _failure_count_total: int = 0
var _shell_canvas_item_allocation_count_total: int = 0
var _last_visual_callback_canvas_item_allocation_count: int = 0
var _worker_elapsed_ms_last: float = 0.0
var _request_to_complete_ms_last: float = 0.0

func configure(
		owner_root: Node, backend: Object,
		grass_atlas: Texture2D, grass_material: ShaderMaterial,
		grass_shadow_atlas: Texture2D = null, grass_shadow_material: ShaderMaterial = null,
		shadow_material: ShaderMaterial = null, spore_material: ShaderMaterial = null,
		max_resident_pages: int = 64,
) -> bool:
	clear()
	if owner_root == null or backend == null or grass_atlas == null or grass_material == null:
		push_error("GrassRenderPageManager: owner, backend, atlas and material are required")
		return false
	if not backend.has_method("queue_grass_render_page_request") \
			or not backend.has_method("sync_grass_render_page_requests") \
			or not backend.has_method("drain_completed_grass_render_pages"):
		push_error("GrassRenderPageManager: backend does not implement the page API")
		return false
	_owner_root = owner_root
	_backend = backend
	_grass_atlas = grass_atlas
	_grass_material = grass_material
	_grass_shadow_atlas = grass_shadow_atlas
	_grass_shadow_material = grass_shadow_material
	_shadow_material = shadow_material
	_spore_material = spore_material
	_max_resident_pages = maxi(1, max_resident_pages)
	_residency.configure(_max_resident_pages)
	return true

func set_epoch(epoch: int) -> void:
	if epoch == _epoch:
		return
	_clear_runtime_state(true)
	_epoch = epoch

func accept_chunk_result(chunk_coord: Vector2i, result: Dictionary, priority: int) -> bool:
	if result.is_empty() or not bool(result.get("success", true)) \
			or result.has("error"):
		return false
	if int(result.get("epoch", _epoch)) != _epoch:
		_stale_completion_reject_count_total += 1
		return false
	var revision: int = int(result.get("revision", -1))
	if revision < 0:
		return false
	var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
	var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
	var entry: Dictionary = _entries.get(page_coord, { }) as Dictionary
	if entry.is_empty() or _entry_demand_mask(entry) == 0:
		_stale_completion_reject_count_total += 1
		return false
	var required: PackedInt64Array = entry.required_revisions as PackedInt64Array
	if required[slot] < 0:
		required[slot] = revision
		entry.required_revisions = required
	elif required[slot] != revision:
		_stale_completion_reject_count_total += 1
		return false
	var contributors: Array = entry.contributors as Array
	var contributor_revisions: PackedInt64Array = \
			entry.contributor_revisions as PackedInt64Array
	var previous_revision: int = contributor_revisions[slot]
	contributors[slot] = result.duplicate(false)
	contributor_revisions[slot] = revision
	entry.contributor_revisions = contributor_revisions
	entry.last_priority = priority
	_reset_retry(entry)
	_ensure_resident(entry)
	_touch_entry(entry)
	if previous_revision != revision or not _entry_slot_has_exact_front(entry, slot, revision):
		if (_entry_request_mask(entry) & (1 << slot)) != 0:
			_mark_entry_dirty(entry)
	_schedule_lru_evictions()
	return true

func invalidate_chunk(chunk_coord: Vector2i, required_revision: int) -> void:
	var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
	var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
	var entry: Dictionary = _entries.get(page_coord, { }) as Dictionary
	if entry.is_empty():
		return
	var required: PackedInt64Array = entry.required_revisions as PackedInt64Array
	if required[slot] == required_revision:
		return
	required[slot] = required_revision
	entry.required_revisions = required
	var contributor_revisions: PackedInt64Array = \
			entry.contributor_revisions as PackedInt64Array
	if contributor_revisions[slot] != required_revision:
		(entry.contributors as Array)[slot] = null
		contributor_revisions[slot] = -1
		entry.contributor_revisions = contributor_revisions
	var page: GrassRenderPage = _entry_page(entry)
	if page != null and (int(entry.active_mask) & (1 << slot)) != 0:
		page.set_slot_active(slot, true, required_revision)
	_reset_retry(entry)
	if (_entry_request_mask(entry) & (1 << slot)) != 0:
		_mark_entry_dirty(entry)
	if _entry_demand_mask(entry) == 0:
		_retire_zero_demand_entry(page_coord, entry)

func set_chunk_active(
		chunk_coord: Vector2i, active: bool,
		required_revision: int, priority: int,
) -> void:
	var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
	var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
	var bit: int = 1 << slot
	var entry: Dictionary = _entries.get(page_coord, { }) as Dictionary
	if entry.is_empty():
		if not active:
			return
		entry = _get_or_create_entry(page_coord)
	var had_slot_reveal_demand: bool = (_entry_reveal_mask(entry) & bit) != 0
	var was_active: bool = (int(entry.active_mask) & bit) != 0
	var required: PackedInt64Array = entry.required_revisions as PackedInt64Array
	var revision_changed: bool = required[slot] != required_revision
	if revision_changed:
		required[slot] = required_revision
		entry.required_revisions = required
		var contributor_revisions: PackedInt64Array = \
				entry.contributor_revisions as PackedInt64Array
		if contributor_revisions[slot] != required_revision:
			(entry.contributors as Array)[slot] = null
			contributor_revisions[slot] = -1
			entry.contributor_revisions = contributor_revisions
	var active_priorities: PackedInt32Array = entry.active_priorities as PackedInt32Array
	var priority_changed: bool = active_priorities[slot] != priority
	active_priorities[slot] = priority
	entry.active_priorities = active_priorities
	if active and not was_active:
		entry.active_mask = int(entry.active_mask) | bit
		_active_slot_count += 1
	elif not active and was_active:
		entry.active_mask = int(entry.active_mask) & ~bit
		_active_slot_count = maxi(0, _active_slot_count - 1)
	var page: GrassRenderPage = _entry_page(entry)
	if page != null and (was_active != active or revision_changed):
		page.set_slot_active(slot, active, required_revision)
	if active:
		_cancel_scheduled_eviction(entry)
		_touch_entry(entry)
		if not had_slot_reveal_demand and _entry_slot_has_exact_front(entry, slot, required_revision):
			_cache_hit_count_total += 1
		elif revision_changed or not _entry_slot_has_exact_front(
				entry,
				slot,
				required_revision,
		):
			_mark_entry_dirty(entry)
	elif not active and was_active and _entry_reveal_mask(entry) == 0 \
			and int(entry.source_mask) != 0 \
			and not _entry_mask_has_exact_front(entry, int(entry.source_mask)):
		_mark_entry_dirty(entry)
	if was_active != active or revision_changed:
		_reset_retry(entry)
	if _entry_demand_mask(entry) == 0:
		_retire_zero_demand_entry(page_coord, entry)
	if was_active != active or revision_changed or priority_changed:
		_backend_demand_dirty = true
	_schedule_lru_evictions()

func set_prestage_demand(desired_chunks: Array[Vector2i]) -> void:
	var next_chunks: Dictionary = { }
	var demand_changed: bool = false
	for chunk_coord: Vector2i in desired_chunks:
		next_chunks[chunk_coord] = true
	for old_variant: Variant in _prestage_chunks.keys():
		var chunk_coord: Vector2i = old_variant as Vector2i
		if next_chunks.has(chunk_coord):
			continue
		var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
		var entry: Dictionary = _entries.get(page_coord, { }) as Dictionary
		if entry.is_empty():
			continue
		var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
		entry.prestage_mask = int(entry.prestage_mask) & ~(1 << slot)
		_prestage_slot_count = maxi(0, _prestage_slot_count - 1)
		demand_changed = true
		_reset_retry(entry)
		if _entry_reveal_mask(entry) == 0 and int(entry.source_mask) != 0 \
				and not _entry_mask_has_exact_front(entry, int(entry.source_mask)):
			_mark_entry_dirty(entry)
		if _entry_demand_mask(entry) == 0:
			_retire_zero_demand_entry(page_coord, entry)
	for chunk_coord: Vector2i in desired_chunks:
		var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
		var entry: Dictionary = _get_or_create_entry(page_coord)
		var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
		var bit: int = 1 << slot
		if (int(entry.prestage_mask) & bit) != 0:
			continue
		entry.prestage_mask = int(entry.prestage_mask) | bit
		_prestage_slot_count += 1
		demand_changed = true
		_reset_retry(entry)
		_cancel_scheduled_eviction(entry)
		_touch_entry(entry)
		var required: int = int((entry.required_revisions as PackedInt64Array)[slot])
		if (int(entry.active_mask) & bit) == 0 and _entry_slot_has_exact_front(entry, slot, required):
			_cache_hit_count_total += 1
		if required < 0 or not _entry_slot_has_exact_front(entry, slot, required):
			_mark_entry_dirty(entry)
	_prestage_chunks = next_chunks
	if demand_changed:
		_backend_demand_dirty = true
	_schedule_lru_evictions()

func set_source_demand(desired_chunks: Array[Vector2i], priority_by_chunk: Dictionary) -> void:
	var next_source_chunks: Dictionary = { }
	var demand_changed: bool = false
	for chunk_coord: Vector2i in desired_chunks:
		next_source_chunks[chunk_coord] = true
	for old_variant: Variant in _source_chunks.keys():
		var old_coord: Vector2i = old_variant as Vector2i
		if next_source_chunks.has(old_coord):
			continue
		var old_page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(old_coord)
		if not _entries.has(old_page_coord):
			continue
		var old_entry: Dictionary = _entries[old_page_coord] as Dictionary
		var old_slot: int = GrassRenderPage.page_slot_for_chunk(old_coord)
		old_entry.source_mask = int(old_entry.source_mask) & ~(1 << old_slot)
		demand_changed = true
		_reset_retry(old_entry)
		if _entry_demand_mask(old_entry) == 0:
			_retire_zero_demand_entry(old_page_coord, old_entry)
	for chunk_coord: Vector2i in desired_chunks:
		var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
		var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
		var bit: int = 1 << slot
		var entry: Dictionary = _get_or_create_entry(page_coord)
		var was_source: bool = (int(entry.source_mask) & bit) != 0
		entry.source_mask = int(entry.source_mask) | bit
		var source_priorities: PackedInt32Array = \
				entry.source_priorities as PackedInt32Array
		var next_priority: int = int(
			priority_by_chunk.get(chunk_coord, int(entry.last_priority)),
		)
		if not was_source or source_priorities[slot] != next_priority:
			demand_changed = true
		source_priorities[slot] = next_priority
		entry.source_priorities = source_priorities
		_cancel_scheduled_eviction(entry)
		_touch_entry(entry)
		if not was_source:
			_reset_retry(entry)
			var required: int = int((entry.required_revisions as PackedInt64Array)[slot])
			if _entry_reveal_mask(entry) == 0 \
					and (required < 0 or not _entry_slot_has_exact_front(entry, slot, required)):
				_mark_entry_dirty(entry)
	_source_chunks = next_source_chunks
	if demand_changed:
		_backend_demand_dirty = true
	_schedule_lru_evictions()

func flush_dirty_requests() -> int:
	if _backend == null:
		return 0
	var queued_count: int = 0
	for page_variant: Variant in _entries.keys():
		var page_coord: Vector2i = page_variant as Vector2i
		var entry: Dictionary = _entries[page_coord] as Dictionary
		# Reconcile transient source-first dirty against the batch's final reveal mask.
		if bool(entry.dirty) and _entry_mask_has_exact_front(entry, _entry_request_mask(entry)):
			entry.dirty = false
			_reset_retry(entry)
			continue
		if not bool(entry.dirty) or int(entry.requested_revision) >= 0 \
				or bool(entry.retry_parked) \
				or not _entry_can_request(entry):
			continue
		var contributors: Array = _build_request_contributors(entry)
		_backend.call(
			"queue_grass_render_page_request",
			page_coord,
			contributors,
			PAGE_WIDTH_CHUNKS,
			float(CHUNK_SIZE_PX),
			_epoch,
			int(entry.desired_page_revision),
			_entry_priority(entry),
			PRIORITY_CLASS_REVEAL if _entry_reveal_mask(entry) != 0 \
					else PRIORITY_CLASS_STREAMING,
		)
		entry.requested_revision = int(entry.desired_page_revision)
		entry.dirty = false
		_inflight_page_count += 1
		_native_request_count_total += 1
		queued_count += 1
	if _backend_demand_dirty or queued_count > 0:
		_sync_backend_requests()
	for page_variant: Variant in _entries.keys():
		var page_coord: Vector2i = page_variant as Vector2i
		var entry: Dictionary = _entries.get(page_coord, { }) as Dictionary
		if not entry.is_empty():
			_retire_zero_demand_entry(page_coord, entry)
	return queued_count

func drain_completed(max_count: int) -> int:
	if _backend == null or max_count <= 0:
		return 0
	var drained_variant: Variant = _backend.call("drain_completed_grass_render_pages", max_count)
	var drained: Array = drained_variant as Array
	var accepted_count: int = 0
	for result_variant: Variant in drained:
		if not (result_variant is Dictionary):
			continue
		var result: Dictionary = result_variant as Dictionary
		var page_coord: Vector2i = result.get("page_coord", INVALID_PAGE_COORD) as Vector2i
		var result_revision: int = int(result.get("page_revision", -1))
		if int(result.get("epoch", -1)) != _epoch or not _entries.has(page_coord):
			_stale_completion_reject_count_total += 1
			continue
		var entry: Dictionary = _entries[page_coord] as Dictionary
		if result_revision != int(entry.requested_revision) \
				or result_revision != int(entry.desired_page_revision) \
				or bool(entry.dirty) or _entry_demand_mask(entry) == 0:
			_stale_completion_reject_count_total += 1
			continue
		_worker_elapsed_ms_last = float(result.get("worker_elapsed_ms", 0.0))
		_request_to_complete_ms_last = float(result.get("request_to_complete_ms", 0.0))
		_cancel_entry_request(entry, false)
		if not bool(result.get("success", not result.has("error"))) or result.has("error"):
			_park_failure(entry)
			continue
		_reset_retry(entry)
		_native_merge_complete_count_total += 1
		_set_ready_result(entry, result)
		_ensure_resident(entry)
		_touch_entry(entry)
		accepted_count += 1
	_schedule_lru_evictions()
	return accepted_count

func apply_next_visual_phase() -> bool:
	_last_visual_callback_canvas_item_allocation_count = 0
	while true:
		if _focused_page == INVALID_PAGE_COORD:
			_focused_page = _select_next_ready_page()
		if _focused_page != INVALID_PAGE_COORD:
			if not _entries.has(_focused_page):
				_focused_page = INVALID_PAGE_COORD
				continue
			var entry: Dictionary = _entries[_focused_page] as Dictionary
			var page: GrassRenderPage = _entry_page(entry)
			var ready_result: Dictionary = entry.ready_result as Dictionary
			if page == null and not ready_result.is_empty():
				if _resident_page_count > _max_resident_pages \
						and _residency.pool_is_empty() \
						and _residency.has_pending_eviction():
					if _apply_one_eviction():
						return true
				return _configure_page_shell(entry)
			if page != null and not ready_result.is_empty():
				return _stage_ready_result(entry, page)
			if page != null and page.has_pending_upload():
				return _advance_focused_upload(entry, page)
			_focused_page = INVALID_PAGE_COORD
			continue
		return _apply_one_eviction()
	return false

func update_anchor(anchor: int) -> void:
	if anchor == _anchor:
		return
	_anchor = anchor
	for entry_variant: Variant in _entries.values():
		var entry: Dictionary = entry_variant as Dictionary
		var page: GrassRenderPage = _entry_page(entry)
		if page != null:
			page.update_anchor(anchor)

## Reports exact front-buffer residency independently from shader visibility.
## Active masking is a separate reveal concern owned by set_chunk_active().
func is_chunk_committed(chunk_coord: Vector2i, required_revision: int) -> bool:
	var page_coord: Vector2i = GrassRenderPage.page_coord_for_chunk(chunk_coord)
	if not _entries.has(page_coord):
		return false
	var entry: Dictionary = _entries[page_coord] as Dictionary
	var slot: int = GrassRenderPage.page_slot_for_chunk(chunk_coord)
	if int((entry.required_revisions as PackedInt64Array)[slot]) != required_revision:
		return false
	return _entry_slot_has_exact_front(entry, slot, required_revision)


func has_pending_visual_upload() -> bool:
	return _ready_visual_page_count > 0 or _focused_page != INVALID_PAGE_COORD \
			or _residency.has_pending_eviction()

func get_debug_state() -> Dictionary:
	var residency_state: Dictionary = _residency.get_debug_state()
	var focused_extra: int = 0
	if _focused_page != INVALID_PAGE_COORD and _entries.has(_focused_page):
		var focused_entry: Dictionary = _entries[_focused_page] as Dictionary
		if (focused_entry.ready_result as Dictionary).is_empty():
			focused_extra = 1
	return {
		"resident_pages": _resident_page_count, "active_slots": _active_slot_count,
		"prestage_slots": _prestage_slot_count,
		"inflight_pages": _inflight_page_count, "ready_visual_pages": _ready_visual_page_count,
		"visual_upload_queue": _ready_visual_page_count + focused_extra,
		"native_request_count_total": _native_request_count_total,
		"native_merge_complete_count_total": _native_merge_complete_count_total,
		"raw_upload_count_total": _raw_upload_count_total, "commit_count_total": _commit_count_total,
		"cache_hit_count_total": _cache_hit_count_total, "eviction_count_total": _eviction_count_total,
		"stale_completion_reject_count_total": _stale_completion_reject_count_total,
		"failure_count_total": _failure_count_total, "retry_parked_pages": _retry_parked_page_count,
		"worker_elapsed_ms_last": _worker_elapsed_ms_last,
		"request_to_complete_ms_last": _request_to_complete_ms_last,
		"entry_count": _entries.size(),
		"eviction_queue": int(residency_state.eviction_pending),
		"eviction_queue_physical": int(residency_state.eviction_queue_physical),
		"eviction_queue_cursor": int(residency_state.eviction_queue_cursor),
		"eviction_queue_capacity": int(residency_state.eviction_queue_capacity),
		"shell_pool_size": int(residency_state.shell_pool_size),
		"shell_pool_capacity": int(residency_state.shell_pool_capacity),
		"focused_page": _focused_page,
		"shell_canvas_item_allocation_count_total": _shell_canvas_item_allocation_count_total,
		"last_visual_callback_canvas_item_allocation_count": \
				_last_visual_callback_canvas_item_allocation_count,
	}

func clear() -> void:
	_clear_runtime_state(true)
	_owner_root = null
	_backend = null
	_grass_atlas = null
	_grass_material = null
	_grass_shadow_atlas = null
	_grass_shadow_material = null
	_shadow_material = null
	_spore_material = null
func _get_or_create_entry(page_coord: Vector2i) -> Dictionary:
	if _entries.has(page_coord):
		return _entries[page_coord] as Dictionary
	var entry: Dictionary = EntryState.create(page_coord)
	_entries[page_coord] = entry
	return entry
## Demand zero is a cancellation barrier for every unpublished candidate.
func _retire_zero_demand_entry(page_coord: Vector2i, entry: Dictionary) -> bool:
	if entry.is_empty() or _entry_demand_mask(entry) != 0:
		return false
	_cancel_entry_request(entry, false)
	_drop_ready_result(entry)
	_reset_retry(entry)
	_cancel_scheduled_eviction(entry)
	if _residency.cancel_unpublished_candidate(entry):
		_resident_page_count = maxi(0, _resident_page_count - 1)
	if _focused_page == page_coord:
		_focused_page = INVALID_PAGE_COORD
	entry.dirty = false
	entry.desired_page_revision = -1
	_backend_demand_dirty = true
	if bool(entry.resident):
		_schedule_lru_evictions()
		return false
	_entries.erase(page_coord)
	return true
func _entry_page(entry: Dictionary) -> GrassRenderPage:
	return _residency.entry_page(entry)
func _entry_demand_mask(entry: Dictionary) -> int:
	return EntryState.demand_mask(entry)
func _entry_reveal_mask(entry: Dictionary) -> int:
	return EntryState.reveal_mask(entry)
func _entry_request_mask(entry: Dictionary) -> int:
	return EntryState.request_mask(entry)
func _entry_slot_has_exact_front(entry: Dictionary, slot: int, revision: int) -> bool:
	var bit: int = 1 << slot
	return revision >= 0 and (int(entry.committed_mask) & bit) != 0 \
			and int((entry.committed_revisions as PackedInt64Array)[slot]) == revision \
			and _entry_page(entry) != null
func _entry_can_request(entry: Dictionary) -> bool:
	return EntryState.can_request(entry)
func _entry_mask_has_exact_front(entry: Dictionary, mask: int) -> bool:
	if mask == 0:
		return true
	for slot: int in range(PAGE_SLOT_COUNT):
		if (mask & (1 << slot)) != 0 and not _entry_slot_has_exact_front(
				entry, slot, int((entry.required_revisions as PackedInt64Array)[slot])):
			return false
	return true

func _build_request_contributors(entry: Dictionary) -> Array:
	return EntryState.build_request_contributors(entry)

func _entry_priority(entry: Dictionary) -> int:
	return EntryState.request_priority(entry)

func _mark_entry_dirty(entry: Dictionary) -> void:
	if bool(entry.dirty):
		return
	_cancel_entry_request(entry, false)
	_drop_ready_result(entry)
	_next_page_revision += 1
	entry.desired_page_revision = _next_page_revision
	entry.dirty = true
	_backend_demand_dirty = true

func _cancel_entry_request(entry: Dictionary, keep_dirty: bool) -> bool:
	if int(entry.requested_revision) < 0:
		return false
	entry.requested_revision = -1
	_inflight_page_count = maxi(0, _inflight_page_count - 1)
	if keep_dirty:
		entry.dirty = true
	return true

func _sync_backend_requests() -> void:
	if _backend == null:
		return
	var desired: Dictionary = { }
	for page_variant: Variant in _entries.keys():
		var page_coord: Vector2i = page_variant as Vector2i
		var entry: Dictionary = _entries[page_coord] as Dictionary
		var requested_revision: int = int(entry.requested_revision)
		if requested_revision < 0:
			continue
		if bool(entry.dirty) or _entry_demand_mask(entry) == 0 \
				or requested_revision != int(entry.desired_page_revision):
			_cancel_entry_request(entry, true)
			continue
		desired[page_coord] = {
			"page_revision": requested_revision,
			"priority": _entry_priority(entry),
			"priority_class": PRIORITY_CLASS_REVEAL if _entry_reveal_mask(entry) != 0 \
					else PRIORITY_CLASS_STREAMING,
		}
	var removed_variant: Variant = _backend.call(
		"sync_grass_render_page_requests",
		_epoch,
		desired,
	)
	_backend_demand_dirty = false
	if not (removed_variant is Array):
		return
	for page_variant: Variant in removed_variant as Array:
		var page_coord: Vector2i = page_variant as Vector2i
		if _entries.has(page_coord):
			_cancel_entry_request(_entries[page_coord] as Dictionary, true)

func _set_ready_result(entry: Dictionary, result: Dictionary) -> void:
	_drop_ready_result(entry)
	entry.ready_result = result.duplicate(false)
	var page_coord: Vector2i = entry.page_coord as Vector2i
	_ready_visual_set[page_coord] = true
	_ready_visual_pages.append(page_coord)
	_ready_visual_page_count += 1
	_cancel_scheduled_eviction(entry)

func _drop_ready_result(entry: Dictionary) -> void:
	if (entry.ready_result as Dictionary).is_empty():
		return
	var page_coord: Vector2i = entry.page_coord as Vector2i
	entry.ready_result = { }
	if _ready_visual_set.erase(page_coord):
		_ready_visual_pages.erase(page_coord)
		_ready_visual_page_count = maxi(0, _ready_visual_page_count - 1)
	var page: GrassRenderPage = _entry_page(entry)
	if _focused_page == page_coord and (page == null or not page.has_pending_upload()):
		_focused_page = INVALID_PAGE_COORD

func _select_next_ready_page() -> Vector2i:
	var selected: Vector2i = INVALID_PAGE_COORD
	var best_class: int = 99
	var best_priority: int = 2147483647
	for page_coord: Vector2i in _ready_visual_pages:
		if not _ready_visual_set.has(page_coord) or not _entries.has(page_coord):
			continue
		var entry: Dictionary = _entries[page_coord] as Dictionary
		var priority_class: int = PRIORITY_CLASS_REVEAL if _entry_reveal_mask(entry) != 0 \
				else PRIORITY_CLASS_STREAMING
		var priority: int = _entry_priority(entry)
		if priority_class < best_class or (
			priority_class == best_class and (
				priority < best_priority or (
					priority == best_priority \
							and EntryState.coord_before(page_coord, selected, INVALID_PAGE_COORD)
				)
			)
		):
			selected = page_coord
			best_class = priority_class
			best_priority = priority
	return selected

func _configure_page_shell(entry: Dictionary) -> bool:
	if _owner_root == null or not is_instance_valid(_owner_root):
		_park_failure(entry, true)
		return false
	var acquisition: Dictionary = _residency.acquire_page(_owner_root)
	var page: GrassRenderPage = acquisition.page as GrassRenderPage
	var shell_items_before: int = page.get_shell_canvas_item_count()
	var callback_allocations: int = 1 if bool(acquisition.created) else 0
	if not page.configure(
		entry.page_coord as Vector2i,
		_grass_atlas,
		_grass_material,
		_grass_shadow_atlas,
		_grass_shadow_material,
		_shadow_material,
		_spore_material,
	):
		_residency.free_page(page)
		_last_visual_callback_canvas_item_allocation_count = callback_allocations
		_shell_canvas_item_allocation_count_total += callback_allocations
		_park_failure(entry, true)
		return true
	callback_allocations += maxi(
		0,
		page.get_shell_canvas_item_count() - shell_items_before,
	)
	_last_visual_callback_canvas_item_allocation_count = callback_allocations
	_shell_canvas_item_allocation_count_total += callback_allocations
	entry.page = page
	for slot: int in range(PAGE_SLOT_COUNT):
		page.set_slot_active(
			slot,
			(int(entry.active_mask) & (1 << slot)) != 0,
			int((entry.required_revisions as PackedInt64Array)[slot]),
		)
	page.update_anchor(_anchor)
	_ensure_resident(entry)
	_touch_entry(entry)
	return true

func _stage_ready_result(entry: Dictionary, page: GrassRenderPage) -> bool:
	var ready_result: Dictionary = entry.ready_result as Dictionary
	if not page.stage_result(ready_result):
		_drop_ready_result(entry)
		_park_failure(entry, true)
		return true
	entry.upload_result = ready_result
	_drop_ready_result(entry)
	return true

func _advance_focused_upload(entry: Dictionary, page: GrassRenderPage) -> bool:
	var raw_uploads_before: int = page.get_raw_upload_count_total()
	var commits_before: int = page.get_commit_count_total()
	var advanced: bool = page.apply_next_upload_phase()
	_raw_upload_count_total += maxi(0, page.get_raw_upload_count_total() - raw_uploads_before)
	var commit_delta: int = maxi(0, page.get_commit_count_total() - commits_before)
	_commit_count_total += commit_delta
	if commit_delta > 0:
		var upload_result: Dictionary = entry.upload_result as Dictionary
		entry.committed_mask = int(upload_result.get("contributor_mask", 0))
		entry.committed_revisions = (
			upload_result.get("contributor_revisions", PackedInt64Array()) \
					as PackedInt64Array
		).duplicate()
		entry.upload_result = { }
		_focused_page = INVALID_PAGE_COORD
		_touch_entry(entry)
		_schedule_lru_evictions()
	elif not advanced:
		_park_failure(entry, true)
	return advanced

func _park_failure(entry: Dictionary, visual_failure: bool = false) -> void:
	_failure_count_total += 1
	if visual_failure:
		_drop_ready_result(entry)
		entry.upload_result = { }
		_focused_page = INVALID_PAGE_COORD
	entry.dirty = true
	if not bool(entry.retry_parked):
		entry.retry_parked = true
		_retry_parked_page_count += 1

func _reset_retry(entry: Dictionary) -> void:
	if bool(entry.retry_parked):
		_retry_parked_page_count = maxi(0, _retry_parked_page_count - 1)
	entry.retry_parked = false
func _ensure_resident(entry: Dictionary) -> void:
	if bool(entry.resident):
		return
	entry.resident = true
	_resident_page_count += 1
func _touch_entry(entry: Dictionary) -> void:
	_next_lru_stamp += 1
	entry.lru_stamp = _next_lru_stamp
func _schedule_lru_evictions() -> void:
	_residency.schedule_lru_eviction(
		_entries, _resident_page_count, _max_resident_pages, _focused_page,
	)
func _entry_is_protected(entry: Dictionary) -> bool:
	return _residency.entry_is_protected(entry, _focused_page)
func _cancel_scheduled_eviction(entry: Dictionary) -> void:
	_residency.cancel_eviction(entry)
func _apply_one_eviction() -> bool:
	var next: Dictionary = _residency.take_next_eviction(_entries)
	var entry: Dictionary = next.entry as Dictionary
	if entry.is_empty():
		return bool(next.worked)
	if _entry_is_protected(entry):
		_schedule_lru_evictions()
		return true
	var page_coord: Vector2i = entry.page_coord as Vector2i
	_release_entry_residency(entry)
	_eviction_count_total += 1
	_retire_zero_demand_entry(page_coord, entry)
	_schedule_lru_evictions()
	return true
func _release_entry_residency(entry: Dictionary) -> void:
	_drop_ready_result(entry)
	if _residency.release_entry_payload(entry):
		_resident_page_count = maxi(0, _resident_page_count - 1)
func _clear_runtime_state(reset_totals: bool) -> void:
	if _backend != null and _backend.has_method("sync_grass_render_page_requests"):
		_backend.call("sync_grass_render_page_requests", _epoch, { })
	for entry_variant: Variant in _entries.values():
		var entry: Dictionary = entry_variant as Dictionary
		var page: GrassRenderPage = _entry_page(entry)
		if page != null:
			_residency.free_page(page)
	_residency.clear()
	_entries.clear()
	_source_chunks.clear()
	_prestage_chunks.clear()
	_ready_visual_pages.clear()
	_ready_visual_set.clear()
	_focused_page = INVALID_PAGE_COORD
	_backend_demand_dirty = false
	_next_page_revision = 0
	_next_lru_stamp = 0
	_resident_page_count = 0
	_active_slot_count = 0
	_prestage_slot_count = 0
	_inflight_page_count = 0
	_ready_visual_page_count = 0
	_retry_parked_page_count = 0
	_worker_elapsed_ms_last = 0.0
	_request_to_complete_ms_last = 0.0
	if not reset_totals:
		return
	_native_request_count_total = 0
	_native_merge_complete_count_total = 0
	_raw_upload_count_total = 0
	_commit_count_total = 0
	_cache_hit_count_total = 0
	_eviction_count_total = 0
	_stale_completion_reject_count_total = 0
	_failure_count_total = 0
	_shell_canvas_item_allocation_count_total = 0
	_last_visual_callback_canvas_item_allocation_count = 0

