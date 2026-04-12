#ifndef WORLD_PREPASS_KERNELS_H
#define WORLD_PREPASS_KERNELS_H

#include <vector>
#include <queue>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class WorldPrePassKernels : public RefCounted {
    GDCLASS(WorldPrePassKernels, RefCounted)

public:
    WorldPrePassKernels();
    ~WorldPrePassKernels();

    PackedFloat32Array compute_wrapped_distance_field(
        int grid_width,
        int grid_height,
        PackedInt32Array source_indices,
        PackedFloat32Array neighbor_distances,
        float max_distance
    ) const;

    PackedFloat32Array compute_priority_flood(
        int grid_width,
        int grid_height,
        PackedFloat32Array height_grid
    ) const;

    PackedFloat32Array compute_ridge_strength_grid(
        int grid_width,
        int grid_height,
        PackedInt32Array path_offsets,
        PackedInt32Array path_counts,
        PackedVector2Array spline_samples,
        PackedFloat32Array spline_half_widths
    ) const;

    PackedByteArray compute_flow_directions(
        int grid_width,
        int grid_height,
        PackedFloat32Array filled_height_grid
    ) const;

    Dictionary compute_flow_accumulation(
        int grid_width,
        int grid_height,
        PackedByteArray flow_dir_grid,
        PackedFloat32Array temperature_grid,
        PackedInt32Array lake_mask,
        float frozen_threshold,
        float glacial_melt_temperature,
        float glacial_melt_bonus,
        float evaporation_rate
    ) const;

    Dictionary compute_lake_records(
        int grid_width,
        int grid_height,
        PackedFloat32Array height_grid,
        PackedFloat32Array filled_height_grid,
        PackedFloat32Array temperature_grid,
        PackedFloat32Array ruggedness_grid,
        int max_lake_id,
        int min_area,
        float min_depth,
        float frozen_lake_temperature,
        int max_classify_samples
    ) const;

    PackedFloat32Array compute_floodplain_strength(
        int grid_width,
        int grid_height,
        PackedByteArray river_mask_grid,
        PackedInt32Array lake_mask,
        PackedFloat32Array floodplain_source_widths,
        PackedFloat32Array neighbor_distances,
        float floodplain_multiplier
    ) const;

    PackedFloat32Array compute_floodplain_deposition(
        int grid_width,
        int grid_height,
        PackedFloat32Array eroded_height_grid,
        PackedByteArray river_mask_grid,
        PackedInt32Array lake_mask,
        PackedFloat32Array deposition_source_widths,
        PackedFloat32Array neighbor_distances,
        float floodplain_multiplier,
        float deposit_rate
    ) const;

    PackedFloat32Array compute_slope_grid(
        int grid_width,
        int grid_height,
        PackedFloat32Array eroded_height_grid,
        PackedFloat32Array neighbor_distances,
        float max_possible_gradient
    ) const;

    PackedFloat32Array compute_rain_shadow(
        int grid_width,
        int grid_height,
        PackedFloat32Array eroded_height_grid,
        PackedFloat32Array moisture_grid,
        PackedInt32Array grid_world_x,
        PackedInt32Array grid_world_y,
        float grid_span_x,
        float grid_span_y,
        int wrap_width_tiles,
        Vector2 wind_direction,
        float max_possible_gradient,
        float precipitation_rate,
        float lift_factor,
        float evaporation_rate,
        float column_scale
    ) const;

    Dictionary compute_river_extraction(
        int grid_width,
        int grid_height,
        PackedFloat32Array accumulation_grid,
        PackedInt32Array lake_mask,
        PackedByteArray flow_dir_grid,
        float river_threshold,
        float river_base_width,
        float river_width_scale,
        PackedFloat32Array neighbor_distances,
        float max_distance
    ) const;

protected:
    static void _bind_methods();

private:
    struct HeapEntry {
        float priority = 0.0f;
        int index = -1;
    };

    struct MinHeapCompare {
        bool operator()(const HeapEntry &left, const HeapEntry &right) const;
    };

    static constexpr float FLOAT_EPSILON = 0.00001f;

    static int wrap_x(int grid_x, int grid_width);
    static void decode_index(int cell_index, int grid_width, int &out_x, int &out_y);
    static int get_neighbor_index(int cell_index, int direction_index, int grid_width, int grid_height);
    static bool is_y_edge_cell(int cell_index, int grid_width, int grid_height);
    static int get_flow_target_index(int cell_index, uint8_t direction_index, int grid_width, int grid_height);
    static float resolve_ridge_strength(float distance_to_ridge, float ridge_half_width);
    static float resolve_river_width(
        float accumulation,
        float river_threshold,
        float river_base_width,
        float river_width_scale
    );
    static float resolve_floodplain_strength(float distance_to_river, float floodplain_width);
};

} // namespace godot

#endif // WORLD_PREPASS_KERNELS_H
