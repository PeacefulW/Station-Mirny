#ifndef STATION_MIRNY_WORLD_CORE_H
#define STATION_MIRNY_WORLD_CORE_H

#include "lake_field.h"
#include "world_prepass.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>

namespace mountain_field {
class Evaluator;
struct HierarchicalMacroSolve;
struct Settings;
} // namespace mountain_field

namespace godot {

class WorldCore : public RefCounted {
	GDCLASS(WorldCore, RefCounted)

protected:
	static void _bind_methods();

public:
	WorldCore();
	~WorldCore() override;

	Array generate_chunk_packets_batch(int64_t p_seed, PackedVector2Array p_coords, int64_t p_world_version, PackedFloat32Array p_settings_packed);
	Ref<Image> make_world_preview_patch_image(Dictionary p_packet, StringName p_render_mode);
	Dictionary build_mountain_contour_debug(PackedByteArray p_solid_halo, int64_t p_chunk_size, int64_t p_tile_size_px);
	Dictionary build_mountain_halo_mask(PackedByteArray p_solid_halo, int64_t p_chunk_size, int64_t p_tile_size_px, int64_t p_pixels_per_tile, double p_origin_world_x, double p_origin_world_y, PackedByteArray p_dug_halo);
	Dictionary build_grass_scatter_buffer(int64_t p_seed, Vector2i p_chunk_coord, PackedInt32Array p_terrain_ids, PackedByteArray p_lake_flags, PackedByteArray p_mountain_halo, int64_t p_mountain_halo_radius_tiles, PackedFloat32Array p_params);
	Dictionary build_mountain_plateau_raster_image(Array p_packets, Vector2i p_target_chunk, Dictionary p_preset, Ref<Image> p_top_image, Ref<Image> p_face_image);
	Dictionary resolve_world_foundation_spawn_tile(int64_t p_seed, int64_t p_world_version, PackedFloat32Array p_settings_packed);
#ifdef DEBUG_ENABLED
	Dictionary get_world_foundation_snapshot(int64_t p_layer_mask, int64_t p_downscale_factor);
	Ref<Image> get_world_foundation_overview(int64_t p_layer_mask, int64_t p_pixels_per_cell);
#endif

private:
	struct HierarchicalMacroCache;
	Dictionary _generate_chunk_packet(
		int64_t p_seed,
		Vector2i p_coord,
		int64_t p_world_version,
		const mountain_field::Evaluator &p_mountain_evaluator,
		const mountain_field::Settings &p_effective_mountain_settings,
		const ::FoundationSettings &p_foundation_settings,
		const ::LakeSettings &p_lake_settings,
		const PackedFloat32Array &p_settings_packed
	);
	const mountain_field::HierarchicalMacroSolve &_get_or_build_hierarchical_macro_solve(
		int64_t p_seed,
		int64_t p_world_version,
		const mountain_field::Settings &p_settings,
		const ::FoundationSettings &p_foundation_settings,
		int64_t p_macro_cell_x,
		int64_t p_macro_cell_y
	);
	const world_prepass::Snapshot &_get_or_build_world_prepass(
		int64_t p_seed,
		int64_t p_world_version,
		const mountain_field::Evaluator &p_mountain_evaluator,
		const mountain_field::Settings &p_effective_mountain_settings,
		const ::FoundationSettings &p_foundation_settings,
		const ::LakeSettings &p_lake_settings
	);
	std::unique_ptr<HierarchicalMacroCache> hierarchical_macro_cache_;
	std::unique_ptr<world_prepass::Snapshot> world_prepass_snapshot_;
	::lake_field::BasinMinElevationLookup world_prepass_lake_basin_min_elevation_;
	mountain_field::Settings world_prepass_effective_mountain_settings_;
	::FoundationSettings world_prepass_foundation_settings_;
	::LakeSettings world_prepass_lake_settings_;
};

} // namespace godot

#endif
