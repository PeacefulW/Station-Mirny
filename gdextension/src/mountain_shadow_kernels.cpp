#include "mountain_shadow_kernels.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {
constexpr int EDGE_NEIGHBOR_COUNT = 8;
constexpr int EDGE_OFFSETS[EDGE_NEIGHBOR_COUNT][2] = {
    {-1, 0},
    {1, 0},
    {0, -1},
    {0, 1},
    {-1, -1},
    {1, -1},
    {-1, 1},
    {1, 1},
};
}

void MountainShadowKernels::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("compute_edge_cache", "chunk_size", "base_x", "base_y", "terrain_snapshot"),
        &MountainShadowKernels::compute_edge_cache
    );
    ClassDB::bind_method(
        D_METHOD(
            "rasterize_shadow_image",
            "chunk_size",
            "base_x",
            "base_y",
            "shadow_color",
            "max_intensity",
            "terrain_bytes",
            "edges",
            "shadow_points"
        ),
        &MountainShadowKernels::rasterize_shadow_image
    );
}

bool MountainShadowKernels::_is_shadow_open_terrain(uint8_t p_terrain) {
    return p_terrain == TERRAIN_GROUND
        || p_terrain == TERRAIN_WATER
        || p_terrain == TERRAIN_SAND
        || p_terrain == TERRAIN_GRASS;
}

bool MountainShadowKernels::_is_external_edge_in_snapshot(
    const PackedByteArray &p_terrain_snapshot,
    int32_t p_stride,
    int32_t p_local_x,
    int32_t p_local_y
) {
    const int32_t center_x = p_local_x + 1;
    const int32_t center_y = p_local_y + 1;
    const uint8_t *snapshot_read = p_terrain_snapshot.ptr();
    for (int offset_index = 0; offset_index < EDGE_NEIGHBOR_COUNT; ++offset_index) {
        const int32_t sample_x = center_x + EDGE_OFFSETS[offset_index][0];
        const int32_t sample_y = center_y + EDGE_OFFSETS[offset_index][1];
        const int32_t sample_index = sample_y * p_stride + sample_x;
        if (_is_shadow_open_terrain(snapshot_read[sample_index])) {
            return true;
        }
    }
    return false;
}

Array MountainShadowKernels::compute_edge_cache(
    int32_t p_chunk_size,
    int32_t p_base_x,
    int32_t p_base_y,
    const PackedByteArray &p_terrain_snapshot
) const {
    Array edges;
    if (p_chunk_size <= 0) {
        return edges;
    }

    const int32_t stride = p_chunk_size + 2;
    if (p_terrain_snapshot.size() < stride * stride) {
        return edges;
    }

    const uint8_t *snapshot_read = p_terrain_snapshot.ptr();
    const int32_t tile_count = p_chunk_size * p_chunk_size;
    for (int32_t tile_index = 0; tile_index < tile_count; ++tile_index) {
        const int32_t local_x = tile_index % p_chunk_size;
        const int32_t local_y = tile_index / p_chunk_size;
        const int32_t center_index = (local_y + 1) * stride + (local_x + 1);
        if (snapshot_read[center_index] != TERRAIN_ROCK) {
            continue;
        }
        if (_is_external_edge_in_snapshot(p_terrain_snapshot, stride, local_x, local_y)) {
            edges.append(Vector2i(p_base_x + local_x, p_base_y + local_y));
        }
    }

    return edges;
}

Dictionary MountainShadowKernels::rasterize_shadow_image(
    int32_t p_chunk_size,
    int32_t p_base_x,
    int32_t p_base_y,
    const Color &p_shadow_color,
    float p_max_intensity,
    const PackedByteArray &p_terrain_bytes,
    const Array &p_edges,
    const Array &p_shadow_points
) const {
    Dictionary result;
    result["has_pixels"] = false;
    if (p_chunk_size <= 0 || p_terrain_bytes.size() < p_chunk_size * p_chunk_size) {
        return result;
    }
    if (p_edges.is_empty() || p_shadow_points.is_empty()) {
        return result;
    }

    PackedByteArray pixel_data;
    pixel_data.resize(p_chunk_size * p_chunk_size * 4);
    uint8_t *pixel_write = pixel_data.ptrw();
    std::fill(pixel_write, pixel_write + pixel_data.size(), static_cast<uint8_t>(0));
    const uint8_t *terrain_read = p_terrain_bytes.ptr();
    const uint8_t red = static_cast<uint8_t>(std::clamp(std::lround(p_shadow_color.r * 255.0f), 0l, 255l));
    const uint8_t green = static_cast<uint8_t>(std::clamp(std::lround(p_shadow_color.g * 255.0f), 0l, 255l));
    const uint8_t blue = static_cast<uint8_t>(std::clamp(std::lround(p_shadow_color.b * 255.0f), 0l, 255l));
    const float clamped_max_intensity = std::clamp(p_max_intensity, 0.0f, 1.0f);
    const int32_t shadow_point_count = p_shadow_points.size();
    bool has_pixels = false;

    for (int edge_index = 0; edge_index < p_edges.size(); ++edge_index) {
        const Vector2i edge_global = p_edges[edge_index];
        for (int32_t point_index = 0; point_index < shadow_point_count; ++point_index) {
            const Vector2i shadow_point = p_shadow_points[point_index];
            const int32_t px = edge_global.x + shadow_point.x - p_base_x;
            const int32_t py = edge_global.y + shadow_point.y - p_base_y;
            if (px < 0 || py < 0 || px >= p_chunk_size || py >= p_chunk_size) {
                continue;
            }

            const int32_t terrain_index = py * p_chunk_size + px;
            if (terrain_read[terrain_index] == TERRAIN_ROCK) {
                continue;
            }

            const float fade = 1.0f - (static_cast<float>(point_index + 1) / static_cast<float>(shadow_point_count + 1));
            const float alpha = std::clamp(clamped_max_intensity * fade, 0.0f, 1.0f);
            const uint8_t alpha_byte = static_cast<uint8_t>(std::clamp(std::lround(alpha * 255.0f), 0l, 255l));
            if (alpha_byte == 0) {
                continue;
            }

            const int32_t pixel_index = (terrain_index * 4);
            if (alpha_byte <= pixel_write[pixel_index + 3]) {
                continue;
            }

            pixel_write[pixel_index] = red;
            pixel_write[pixel_index + 1] = green;
            pixel_write[pixel_index + 2] = blue;
            pixel_write[pixel_index + 3] = alpha_byte;
            has_pixels = true;
        }
    }

    result["has_pixels"] = has_pixels;
    if (!has_pixels) {
        return result;
    }

    result["img"] = Image::create_from_data(
        p_chunk_size,
        p_chunk_size,
        false,
        Image::FORMAT_RGBA8,
        pixel_data
    );
    return result;
}
