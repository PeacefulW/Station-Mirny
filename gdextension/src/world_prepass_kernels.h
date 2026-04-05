#ifndef WORLD_PREPASS_KERNELS_H
#define WORLD_PREPASS_KERNELS_H

#include <vector>
#include <queue>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

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
};

} // namespace godot

#endif // WORLD_PREPASS_KERNELS_H
