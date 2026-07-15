class_name GrassRenderPageManagerEntry
extends RefCounted

## Pure fixed-width entry state and request-policy helpers. This class owns no
## Nodes, GPU resources, backend references or packed payload contents.

const SLOT_COUNT: int = 4


static func create(page_coord: Vector2i) -> Dictionary:
	return {
		"page_coord": page_coord,
		"contributors": [null, null, null, null],
		"contributor_revisions": PackedInt64Array([-1, -1, -1, -1]),
		"required_revisions": PackedInt64Array([-1, -1, -1, -1]),
		"active_priorities": PackedInt32Array([0, 0, 0, 0]),
		"source_priorities": PackedInt32Array([0, 0, 0, 0]),
		"active_mask": 0,
		"prestage_mask": 0,
		"source_mask": 0,
		"committed_mask": 0,
		"committed_revisions": PackedInt64Array([-1, -1, -1, -1]),
		"dirty": false,
		"desired_page_revision": -1,
		"requested_revision": -1,
		"ready_result": { },
		"upload_result": { },
		"page": null,
		"resident": false,
		"lru_stamp": 0,
		"last_priority": 0,
		"eviction_pending": false,
		"eviction_token": 0,
		"retry_parked": false,
	}


static func reveal_mask(entry: Dictionary) -> int:
	return int(entry.active_mask) | int(entry.prestage_mask)


static func demand_mask(entry: Dictionary) -> int:
	return reveal_mask(entry) | int(entry.source_mask)


## Visible/prestage slots must make bounded progress even when an outer warm
## source slot lacks halo data. A source-only page remains all-or-nothing.
static func request_mask(entry: Dictionary) -> int:
	var visible_mask: int = reveal_mask(entry)
	return visible_mask if visible_mask != 0 else int(entry.source_mask)


static func can_request(entry: Dictionary) -> bool:
	var required_mask: int = request_mask(entry)
	if required_mask == 0 or int(entry.desired_page_revision) < 0:
		return false
	var contributors: Array = entry.contributors as Array
	var contributor_revisions: PackedInt64Array = \
			entry.contributor_revisions as PackedInt64Array
	var required: PackedInt64Array = entry.required_revisions as PackedInt64Array
	for slot: int in range(SLOT_COUNT):
		if (required_mask & (1 << slot)) == 0:
			continue
		if contributors[slot] == null or required[slot] < 0 \
				or contributor_revisions[slot] != required[slot]:
			return false
	return true


## Envelopes are copied shallowly; nested Arrays/PackedArrays remain immutable
## shared handles. Ready optional contributors join the same atomic page merge.
static func build_request_contributors(entry: Dictionary) -> Array:
	var result: Array = []
	var contributors: Array = entry.contributors as Array
	var revisions: PackedInt64Array = entry.contributor_revisions as PackedInt64Array
	for slot: int in range(SLOT_COUNT):
		if contributors[slot] == null or revisions[slot] < 0:
			continue
		var contributor: Dictionary = (contributors[slot] as Dictionary).duplicate(false)
		contributor["slot"] = slot
		contributor["revision"] = revisions[slot]
		result.append(contributor)
	return result


static func request_priority(entry: Dictionary) -> int:
	var demand: int = demand_mask(entry)
	var active_priorities: PackedInt32Array = entry.active_priorities as PackedInt32Array
	var source_priorities: PackedInt32Array = entry.source_priorities as PackedInt32Array
	var best: int = 2147483647
	for slot: int in range(SLOT_COUNT):
		var bit: int = 1 << slot
		if (int(entry.active_mask) & bit) != 0:
			best = mini(best, active_priorities[slot])
		if (int(entry.source_mask) & bit) != 0:
			best = mini(best, source_priorities[slot])
		elif (int(entry.prestage_mask) & bit) != 0:
			best = mini(best, int(entry.last_priority))
	return int(entry.last_priority) if demand == 0 or best == 2147483647 else best


static func coord_before(a: Vector2i, b: Vector2i, invalid_coord: Vector2i) -> bool:
	return b == invalid_coord or a.y < b.y or (a.y == b.y and a.x < b.x)
