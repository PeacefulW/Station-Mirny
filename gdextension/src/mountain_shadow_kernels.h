#ifndef MOUNTAIN_SHADOW_KERNELS_H
#define MOUNTAIN_SHADOW_KERNELS_H

#include <cstdint>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class MountainShadowKernels : public RefCounted {
    GDCLASS(MountainShadowKernels, RefCounted)

public:
    MountainShadowKernels() = default;
    ~MountainShadowKernels() = default;

    Array compute_edge_cache(
        int32_t p_chunk_size,
        int32_t p_base_x,
        int32_t p_base_y,
        const PackedByteArray &p_terrain_snapshot
    ) const;

    Dictionary rasterize_shadow_image(
        int32_t p_chunk_size,
        int32_t p_base_x,
        int32_t p_base_y,
        const Color &p_shadow_color,
        float p_max_intensity,
        const PackedByteArray &p_terrain_bytes,
        const Array &p_edges,
        const Array &p_shadow_points
    ) const;

protected:
    static void _bind_methods();

private:
    static constexpr uint8_t TERRAIN_GROUND = 0;
    static constexpr uint8_t TERRAIN_ROCK = 1;
    static constexpr uint8_t TERRAIN_WATER = 2;
    static constexpr uint8_t TERRAIN_SAND = 3;
    static constexpr uint8_t TERRAIN_GRASS = 4;

    static bool _is_shadow_open_terrain(uint8_t p_terrain);
    static bool _is_external_edge_in_snapshot(
        const PackedByteArray &p_terrain_snapshot,
        int32_t p_stride,
        int32_t p_local_x,
        int32_t p_local_y
    );
};

} // namespace godot

#endif // MOUNTAIN_SHADOW_KERNELS_H
