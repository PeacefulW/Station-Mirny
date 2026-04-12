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
        PackedByteArray lake_mask,
        float frozen_threshold,
        float glacial_melt_temperature,
        float glacial_melt_bonus,
        float evaporation_rate
    ) const;

    Dictionary compute_river_extraction(
        int grid_width,
        int grid_height,
        PackedFloat32Array accumulation_grid,
        PackedByteArray lake_mask,
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
};

} // namespace godot

#endif // WORLD_PREPASS_KERNELS_H
