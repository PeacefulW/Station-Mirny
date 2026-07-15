class_name GrassRenderPageManagerResidency
extends RefCounted

## Bounded residency mechanics for GrassRenderPageManager. World demand and
## revision truth stay in the manager; this helper owns only eviction tickets,
## the cursor queue and detached reusable presentation shells.

const GrassRenderPage = preload("res://core/systems/world/grass_render_page.gd")
const EntryState = preload("res://core/systems/world/grass_render_page_manager_entry.gd")

const SHELL_POOL_LIMIT: int = 4
const EVICTION_SCAN_LIMIT: int = 8
const EVICTION_COMPACT_CURSOR_MIN: int = 16
const EVICTION_QUEUE_MIN_CAPACITY: int = 16
const EVICTION_QUEUE_SLACK: int = 16
const EVICTION_QUEUE_HARD_CAP: int = 256

var _eviction_queue: Array[Dictionary] = []
var _eviction_cursor: int = 0
var _eviction_queue_capacity: int = EVICTION_QUEUE_MIN_CAPACITY
var _next_eviction_token: int = 0
var _eviction_pending_count: int = 0
var _shell_pool: Array[GrassRenderPage] = []


func configure(max_resident_pages: int) -> void:
	clear()
	_eviction_queue_capacity = clampi(
		maxi(1, max_resident_pages) + EVICTION_QUEUE_SLACK,
		EVICTION_QUEUE_MIN_CAPACITY,
		EVICTION_QUEUE_HARD_CAP,
	)


## One entry owns at most one physical token. Cancel keeps that token available
## for an O(1) reschedule until the bounded cursor consumes or compacts it.
func schedule_eviction(entry: Dictionary, entries: Dictionary) -> bool:
	if bool(entry.eviction_pending):
		return false
	if int(entry.eviction_token) > 0:
		entry.eviction_pending = true
		_eviction_pending_count += 1
		return true
	if _eviction_queue.size() >= _eviction_queue_capacity:
		_compact_queue(entries)
	if _eviction_queue.size() >= _eviction_queue_capacity:
		return false
	_next_eviction_token += 1
	entry.eviction_token = _next_eviction_token
	entry.eviction_pending = true
	_eviction_pending_count += 1
	_eviction_queue.append({
		"page_coord": entry.page_coord as Vector2i,
		"token": _next_eviction_token,
	})
	return true


func cancel_eviction(entry: Dictionary) -> bool:
	if not bool(entry.eviction_pending):
		return false
	entry.eviction_pending = false
	_eviction_pending_count = maxi(0, _eviction_pending_count - 1)
	return true


## Admits one oldest candidate per call. Repeated full scans inside a while loop
## are forbidden; a completed eviction calls this again for bounded progress.
func schedule_lru_eviction(
		entries: Dictionary,
		resident_page_count: int,
		max_resident_pages: int,
		focused_page: Vector2i,
) -> bool:
	if resident_page_count - _eviction_pending_count <= max_resident_pages:
		return false
	var candidate: Dictionary = { }
	var oldest_stamp: int = 9223372036854775807
	for entry_variant: Variant in entries.values():
		var entry: Dictionary = entry_variant as Dictionary
		if not bool(entry.resident) or bool(entry.eviction_pending) \
				or entry_is_protected(entry, focused_page):
			continue
		if int(entry.lru_stamp) < oldest_stamp:
			candidate = entry
			oldest_stamp = int(entry.lru_stamp)
	return not candidate.is_empty() and schedule_eviction(candidate, entries)


func entry_is_protected(entry: Dictionary, focused_page: Vector2i) -> bool:
	if EntryState.demand_mask(entry) != 0 or int(entry.requested_revision) >= 0 \
			or not (entry.ready_result as Dictionary).is_empty() \
			or (entry.page_coord as Vector2i) == focused_page:
		return true
	var page: GrassRenderPage = entry_page(entry)
	return page != null and page.has_pending_upload()


func entry_page(entry: Dictionary) -> GrassRenderPage:
	var page: GrassRenderPage = entry.get("page", null) as GrassRenderPage
	if page == null or not is_instance_valid(page):
		entry.page = null
		return null
	return page


## Returns at most one live entry and consumes at most EVICTION_SCAN_LIMIT
## physical records. `worked` lets the caller charge a callback that only
## retired stale tickets without slipping more scene work into the same frame.
func take_next_eviction(entries: Dictionary) -> Dictionary:
	var scanned: int = 0
	while _eviction_cursor < _eviction_queue.size() \
			and scanned < EVICTION_SCAN_LIMIT:
		var record: Dictionary = _eviction_queue[_eviction_cursor] as Dictionary
		_eviction_cursor += 1
		scanned += 1
		var page_coord: Vector2i = record.page_coord as Vector2i
		var token: int = int(record.token)
		var entry: Dictionary = entries.get(page_coord, { }) as Dictionary
		if entry.is_empty() or int(entry.eviction_token) != token:
			continue
		entry.eviction_token = 0
		if not bool(entry.eviction_pending):
			continue
		entry.eviction_pending = false
		_eviction_pending_count = maxi(0, _eviction_pending_count - 1)
		_maybe_compact_queue(entries)
		return {"worked": true, "entry": entry}
	_maybe_compact_queue(entries)
	return {"worked": scanned > 0, "entry": { }}


func acquire_page(owner_root: Node) -> Dictionary:
	while not _shell_pool.is_empty():
		var pooled: GrassRenderPage = _shell_pool.pop_back()
		if pooled == null or not is_instance_valid(pooled):
			continue
		owner_root.add_child(pooled)
		return {"page": pooled, "created": false}
	var page := GrassRenderPage.new()
	owner_root.add_child(page)
	return {"page": page, "created": true}


## clear() keeps the fixed CanvasItem graph but releases every front/back GPU
## resource. Detached shells cannot draw and have no entry alias.
func release_page(page: GrassRenderPage) -> bool:
	if page == null or not is_instance_valid(page):
		return false
	page.clear()
	var parent: Node = page.get_parent()
	if parent != null:
		parent.remove_child(page)
	if _shell_pool.size() < SHELL_POOL_LIMIT:
		_shell_pool.append(page)
		return true
	page.free()
	return false


## Releases derived presentation payload while leaving demand/revision truth in
## the entry for the manager to retain or prune.
func release_entry_payload(entry: Dictionary) -> bool:
	var page: GrassRenderPage = entry_page(entry)
	if page != null:
		release_page(page)
	entry.page = null
	entry.upload_result = { }
	(entry.contributors as Array).fill(null)
	var contributor_revisions: PackedInt64Array = \
			entry.contributor_revisions as PackedInt64Array
	contributor_revisions.fill(-1)
	entry.contributor_revisions = contributor_revisions
	entry.committed_mask = 0
	var committed_revisions: PackedInt64Array = \
			entry.committed_revisions as PackedInt64Array
	committed_revisions.fill(-1)
	entry.committed_revisions = committed_revisions
	entry.dirty = false
	entry.desired_page_revision = -1
	var was_resident: bool = bool(entry.resident)
	entry.resident = false
	return was_resident


## Drops an unpublished page candidate while retaining an exact committed
## front for hot-cache/LRU semantics. Returns true only when residency was
## released because no reusable committed value survived.
func cancel_unpublished_candidate(entry: Dictionary) -> bool:
	var page: GrassRenderPage = entry_page(entry)
	if page != null:
		page.cancel_pending_upload()
	entry.upload_result = { }
	if _has_exact_committed_front(entry, page):
		return false
	return release_entry_payload(entry)


func _has_exact_committed_front(
		entry: Dictionary,
		page: GrassRenderPage,
) -> bool:
	if page == null or int(entry.committed_mask) == 0:
		return false
	var required: PackedInt64Array = entry.required_revisions as PackedInt64Array
	var committed: PackedInt64Array = entry.committed_revisions as PackedInt64Array
	for slot: int in range(EntryState.SLOT_COUNT):
		var bit: int = 1 << slot
		if (int(entry.committed_mask) & bit) != 0 and required[slot] >= 0 \
				and committed[slot] == required[slot]:
			return true
	return false


func free_page(page: GrassRenderPage) -> void:
	if page == null or not is_instance_valid(page):
		return
	page.clear()
	page.free()


func clear() -> void:
	for page: GrassRenderPage in _shell_pool:
		free_page(page)
	_shell_pool.clear()
	_eviction_queue.clear()
	_eviction_cursor = 0
	_next_eviction_token = 0
	_eviction_pending_count = 0


func eviction_pending_count() -> int:
	return _eviction_pending_count


func has_pending_eviction() -> bool:
	return _eviction_pending_count > 0


func pool_is_empty() -> bool:
	return _shell_pool.is_empty()


func get_debug_state() -> Dictionary:
	return {
		"eviction_pending": _eviction_pending_count,
		"eviction_queue_physical": _eviction_queue.size(),
		"eviction_queue_cursor": _eviction_cursor,
		"eviction_queue_capacity": _eviction_queue_capacity,
		"shell_pool_size": _shell_pool.size(),
		"shell_pool_capacity": SHELL_POOL_LIMIT,
	}


func _maybe_compact_queue(entries: Dictionary) -> void:
	if _eviction_cursor < EVICTION_COMPACT_CURSOR_MIN:
		return
	if _eviction_cursor * 2 < _eviction_queue.size() \
			and _eviction_queue.size() < _eviction_queue_capacity:
		return
	_compact_queue(entries)


## The physical queue is hard-capped, so this periodic copy has a strict upper
## bound independent from traversal distance or world extent.
func _compact_queue(entries: Dictionary) -> void:
	var compacted: Array[Dictionary] = []
	for index: int in range(_eviction_cursor, _eviction_queue.size()):
		var record: Dictionary = _eviction_queue[index] as Dictionary
		var page_coord: Vector2i = record.page_coord as Vector2i
		var token: int = int(record.token)
		var entry: Dictionary = entries.get(page_coord, { }) as Dictionary
		if entry.is_empty() or int(entry.eviction_token) != token:
			continue
		if not bool(entry.eviction_pending):
			entry.eviction_token = 0
			continue
		compacted.append(record)
	_eviction_queue = compacted
	_eviction_cursor = 0
