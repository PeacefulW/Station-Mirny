class_name Mountain2DDevInfoText
extends RefCounted

static func build(
	debug_snapshot: Dictionary,
	show_raster_layer: bool,
	show_raster_light_preview: bool,
	show_plateau_layer: bool,
	show_tilemap_baseline: bool,
	show_plateau_edge_debug: bool,
	preset_path: String
) -> String:
	return "\n".join([
		"2D mountain dev scene",
		"seed=%d world_version=%d" % [
			int(debug_snapshot.get("seed", 0)),
			int(debug_snapshot.get("world_version", 0)),
		],
		"target_chunk=%s target_local=%s radius=%d" % [
			str(debug_snapshot.get("target_chunk", Vector2i.ZERO)),
			str(debug_snapshot.get("target_local", Vector2i.ZERO)),
			int(debug_snapshot.get("target_search_radius", -1)),
		],
		"target mountain cells=%d wall=%d foot=%d" % [
			int(debug_snapshot.get("target_mountain_cells", 0)),
			int(debug_snapshot.get("target_wall_cells", 0)),
			int(debug_snapshot.get("target_foot_cells", 0)),
		],
		"displayed chunks=%d mountain_chunks=%d mountain_cells=%d" % [
			int(debug_snapshot.get("displayed_chunk_count", 0)),
			int(debug_snapshot.get("displayed_chunks_with_mountain", 0)),
			int(debug_snapshot.get("displayed_mountain_cells", 0)),
		],
		"plateau ready=%s tiles=%d edge=%d facade=%d rim=%d" % [
			str(bool(debug_snapshot.get("plateau_ready", false))),
			int(debug_snapshot.get("plateau_mountain_tiles", 0)),
			int(debug_snapshot.get("plateau_edge_tiles", 0)),
			int(debug_snapshot.get("plateau_facade_edges", 0)),
			int(debug_snapshot.get("plateau_rim_edges", 0)),
		],
		"textures top=%s face=%s | connectors=%d" % [
			str(bool(debug_snapshot.get("plateau_top_texture_loaded", false))),
			str(bool(debug_snapshot.get("plateau_face_texture_loaded", false))),
			int(debug_snapshot.get("plateau_connector_count", 0)),
		],
		"raster ready=%s visible=%s image=%dx%d top=%d face=%d rim=%d" % [
			str(bool(debug_snapshot.get("raster_ready", false))),
			str(bool(debug_snapshot.get("raster_visible", false))),
			int(debug_snapshot.get("raster_image_width", 0)),
			int(debug_snapshot.get("raster_image_height", 0)),
			int(debug_snapshot.get("raster_top_pixels", 0)),
			int(debug_snapshot.get("raster_face_pixels", 0)),
			int(debug_snapshot.get("raster_rim_pixels", 0)),
		],
		"normal ready=%s preview=%s image=%dx%d pixels=%d" % [
			str(bool(debug_snapshot.get("raster_normal_ready", false))),
			str(bool(debug_snapshot.get("raster_normal_preview", false))),
			int(debug_snapshot.get("raster_normal_image_width", 0)),
			int(debug_snapshot.get("raster_normal_image_height", 0)),
			int(debug_snapshot.get("raster_normal_pixel_count", 0)),
		],
		"R raster=%s | L light=%s | P vector=%s | T baseline=%s | E edge_debug=%s" % [
			str(show_raster_layer),
			str(show_raster_light_preview),
			str(show_plateau_layer),
			str(show_tilemap_baseline),
			str(show_plateau_edge_debug),
		],
		"preset: %s" % preset_path,
	])
