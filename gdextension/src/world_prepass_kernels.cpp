#include "world_prepass_kernels.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {
constexpr int NEIGHBOR_COUNT = 8;
constexpr int DX[NEIGHBOR_COUNT] = {-1, 0, 1, -1, 1, -1, 0, 1};
constexpr int DY[NEIGHBOR_COUNT] = {-1, -1, -1, 0, 0, 1, 1, 1};
}

WorldPrePassKernels::WorldPrePassKernels() {}
WorldPrePassKernels::~WorldPrePassKernels() {}

void WorldPrePassKernels::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("compute_wrapped_distance_field", "grid_width", "grid_height", "source_indices", "neighbor_distances", "max_distance"),
        &WorldPrePassKernels::compute_wrapped_distance_field
    );
    ClassDB::bind_method(
        D_METHOD("compute_priority_flood", "grid_width", "grid_height", "height_grid"),
        &WorldPrePassKernels::compute_priority_flood
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_ridge_strength_grid",
            "grid_width",
            "grid_height",
            "path_offsets",
            "path_counts",
            "spline_samples",
            "spline_half_widths"
        ),
        &WorldPrePassKernels::compute_ridge_strength_grid
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_river_extraction",
            "grid_width",
            "grid_height",
            "accumulation_grid",
            "lake_mask",
            "flow_dir_grid",
            "river_threshold",
            "river_base_width",
            "river_width_scale",
            "neighbor_distances",
            "max_distance"
        ),
        &WorldPrePassKernels::compute_river_extraction
    );
}

bool WorldPrePassKernels::MinHeapCompare::operator()(const HeapEntry &left, const HeapEntry &right) const {
    if (left.priority > right.priority + FLOAT_EPSILON) {
        return true;
    }
    if (left.priority + FLOAT_EPSILON < right.priority) {
        return false;
    }
    return left.index > right.index;
}

int WorldPrePassKernels::wrap_x(int grid_x, int grid_width) {
    if (grid_width <= 0) {
        return 0;
    }
    int wrapped = grid_x % grid_width;
    if (wrapped < 0) {
        wrapped += grid_width;
    }
    return wrapped;
}

void WorldPrePassKernels::decode_index(int cell_index, int grid_width, int &out_x, int &out_y) {
    out_x = 0;
    out_y = 0;
    if (grid_width <= 0 || cell_index < 0) {
        return;
    }
    out_x = cell_index % grid_width;
    out_y = cell_index / grid_width;
}

int WorldPrePassKernels::get_neighbor_index(int cell_index, int direction_index, int grid_width, int grid_height) {
    if (cell_index < 0 || direction_index < 0 || direction_index >= NEIGHBOR_COUNT || grid_width <= 0 || grid_height <= 0) {
        return -1;
    }
    int grid_x = 0;
    int grid_y = 0;
    decode_index(cell_index, grid_width, grid_x, grid_y);
    const int neighbor_y = grid_y + DY[direction_index];
    if (neighbor_y < 0 || neighbor_y >= grid_height) {
        return -1;
    }
    const int neighbor_x = wrap_x(grid_x + DX[direction_index], grid_width);
    return neighbor_y * grid_width + neighbor_x;
}

bool WorldPrePassKernels::is_y_edge_cell(int cell_index, int grid_width, int grid_height) {
    if (grid_width <= 0 || grid_height <= 0) {
        return true;
    }
    const int grid_y = cell_index / grid_width;
    return grid_y <= 0 || grid_y >= grid_height - 1;
}

int WorldPrePassKernels::get_flow_target_index(int cell_index, uint8_t direction_index, int grid_width, int grid_height) {
    if (direction_index == 255) {
        return -1;
    }
    return get_neighbor_index(cell_index, static_cast<int>(direction_index), grid_width, grid_height);
}

float WorldPrePassKernels::resolve_ridge_strength(float distance_to_ridge, float ridge_half_width) {
    if (ridge_half_width <= FLOAT_EPSILON) {
        return 0.0f;
    }
    const float t = std::clamp(1.0f - distance_to_ridge / ridge_half_width, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

float WorldPrePassKernels::resolve_river_width(
    float accumulation,
    float river_threshold,
    float river_base_width,
    float river_width_scale
) {
    if (accumulation + FLOAT_EPSILON < river_threshold) {
        return 0.0f;
    }
    float river_width = river_base_width;
    const float safe_threshold = std::max(1.0f, river_threshold);
    const float ratio = std::max(1.0f, accumulation / safe_threshold);
    if (ratio > 1.0f + FLOAT_EPSILON) {
        river_width += river_width_scale * static_cast<float>(std::log(ratio) / std::log(2.0f));
    }
    return std::max(0.0f, river_width);
}

PackedFloat32Array WorldPrePassKernels::compute_wrapped_distance_field(
    int grid_width,
    int grid_height,
    PackedInt32Array source_indices,
    PackedFloat32Array neighbor_distances,
    float max_distance
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array result;
    if (grid_width <= 0 || grid_height <= 0 || cell_count <= 0 || neighbor_distances.size() < NEIGHBOR_COUNT) {
        return result;
    }
    result.resize(cell_count);
    float *distances = result.ptrw();
    for (int i = 0; i < cell_count; ++i) {
        distances[i] = max_distance;
    }

    const float *neighbor_costs = neighbor_distances.ptr();
    const int32_t *source_read = source_indices.ptr();
    std::priority_queue<HeapEntry, std::vector<HeapEntry>, MinHeapCompare> heap;

    for (int i = 0; i < source_indices.size(); ++i) {
        const int cell_index = source_read[i];
        if (cell_index < 0 || cell_index >= cell_count) {
            continue;
        }
        if (distances[cell_index] <= 0.0f) {
            continue;
        }
        distances[cell_index] = 0.0f;
        heap.push({0.0f, cell_index});
    }

    while (!heap.empty()) {
        const HeapEntry current = heap.top();
        heap.pop();
        if (current.index < 0 || current.index >= cell_count) {
            continue;
        }
        if (current.priority > distances[current.index] + FLOAT_EPSILON) {
            continue;
        }

        int grid_x = 0;
        int grid_y = 0;
        decode_index(current.index, grid_width, grid_x, grid_y);

        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_y = grid_y + DY[direction_index];
            if (neighbor_y < 0 || neighbor_y >= grid_height) {
                continue;
            }
            const int neighbor_x = wrap_x(grid_x + DX[direction_index], grid_width);
            const int neighbor_index = neighbor_y * grid_width + neighbor_x;
            const float next_distance = current.priority + neighbor_costs[direction_index];
            if (next_distance + FLOAT_EPSILON >= distances[neighbor_index]) {
                continue;
            }
            distances[neighbor_index] = next_distance;
            heap.push({next_distance, neighbor_index});
        }
    }

    return result;
}

PackedFloat32Array WorldPrePassKernels::compute_priority_flood(
    int grid_width,
    int grid_height,
    PackedFloat32Array height_grid
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array filled_grid;
    if (grid_width <= 0 || grid_height <= 0 || cell_count <= 0 || height_grid.size() != cell_count) {
        return filled_grid;
    }

    filled_grid = height_grid;
    const float *height_read = height_grid.ptr();
    float *filled_write = filled_grid.ptrw();
    std::vector<uint8_t> visited(static_cast<size_t>(cell_count), 0);
    std::priority_queue<HeapEntry, std::vector<HeapEntry>, MinHeapCompare> heap;

    auto seed_boundary = [&](int grid_x, int grid_y) {
        const int cell_index = grid_y * grid_width + grid_x;
        if (cell_index < 0 || cell_index >= cell_count || visited[static_cast<size_t>(cell_index)] != 0) {
            return;
        }
        visited[static_cast<size_t>(cell_index)] = 1;
        heap.push({height_read[cell_index], cell_index});
    };

    for (int grid_x = 0; grid_x < grid_width; ++grid_x) {
        seed_boundary(grid_x, 0);
        if (grid_height > 1) {
            seed_boundary(grid_x, grid_height - 1);
        }
    }

    while (!heap.empty()) {
        const HeapEntry current = heap.top();
        heap.pop();
        if (current.index < 0 || current.index >= cell_count) {
            continue;
        }
        if (current.priority > filled_write[current.index] + FLOAT_EPSILON) {
            continue;
        }

        int grid_x = 0;
        int grid_y = 0;
        decode_index(current.index, grid_width, grid_x, grid_y);
        const float current_level = filled_write[current.index];

        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_y = grid_y + DY[direction_index];
            if (neighbor_y < 0 || neighbor_y >= grid_height) {
                continue;
            }
            const int neighbor_x = wrap_x(grid_x + DX[direction_index], grid_width);
            const int neighbor_index = neighbor_y * grid_width + neighbor_x;
            if (visited[static_cast<size_t>(neighbor_index)] != 0) {
                continue;
            }
            visited[static_cast<size_t>(neighbor_index)] = 1;
            const float raw_height = height_read[neighbor_index];
            const float filled_height = std::max(raw_height, current_level);
            filled_write[neighbor_index] = filled_height;
            heap.push({filled_height, neighbor_index});
        }
    }

    return filled_grid;
}

PackedFloat32Array WorldPrePassKernels::compute_ridge_strength_grid(
    int grid_width,
    int grid_height,
    PackedInt32Array path_offsets,
    PackedInt32Array path_counts,
    PackedVector2Array spline_samples,
    PackedFloat32Array spline_half_widths
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array ridge_strength_grid;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        path_offsets.size() != path_counts.size() ||
        spline_half_widths.size() != spline_samples.size()
    ) {
        return ridge_strength_grid;
    }

    ridge_strength_grid.resize(cell_count);
    float *ridge_write = ridge_strength_grid.ptrw();
    for (int i = 0; i < cell_count; ++i) {
        ridge_write[i] = 0.0f;
    }

    const int32_t *offset_read = path_offsets.ptr();
    const int32_t *count_read = path_counts.ptr();
    const Vector2 *sample_read = spline_samples.ptr();
    const float *half_width_read = spline_half_widths.ptr();
    const int sample_count = spline_samples.size();

    auto stamp_point = [&](const Vector2 &point, float ridge_half_width) {
        if (ridge_half_width <= FLOAT_EPSILON || grid_width <= 0 || grid_height <= 0) {
            return;
        }
        const double point_x = point.x;
        const double point_y = point.y;
        const double half_width_sq = static_cast<double>(ridge_half_width) * static_cast<double>(ridge_half_width);
        const int min_x = static_cast<int>(std::floor(point_x - ridge_half_width));
        const int max_x = static_cast<int>(std::ceil(point_x + ridge_half_width));
        const int min_y = std::max(0, static_cast<int>(std::floor(point_y - ridge_half_width)));
        const int max_y = std::min(grid_height - 1, static_cast<int>(std::ceil(point_y + ridge_half_width)));
        const int x_span = max_x - min_x + 1;
        for (int grid_y = min_y; grid_y <= max_y; ++grid_y) {
            const int row_base = grid_y * grid_width;
            const double delta_y = static_cast<double>(grid_y) - point_y;
            const double delta_y_sq = delta_y * delta_y;
            int wrapped_x = wrap_x(min_x, grid_width);
            double query_x = static_cast<double>(min_x);
            for (int x_offset = 0; x_offset < x_span; ++x_offset) {
                const double delta_x = query_x - point_x;
                const double distance_sq = delta_x * delta_x + delta_y_sq;
                if (distance_sq < half_width_sq) {
                    const float strength = resolve_ridge_strength(
                        static_cast<float>(std::sqrt(distance_sq)),
                        ridge_half_width
                    );
                    const int cell_index = row_base + wrapped_x;
                    if (strength > ridge_write[cell_index]) {
                        ridge_write[cell_index] = strength;
                    }
                }
                query_x += 1.0;
                wrapped_x += 1;
                if (wrapped_x >= grid_width) {
                    wrapped_x = 0;
                }
            }
        }
    };

    auto stamp_segment = [&](const Vector2 &segment_start, const Vector2 &segment_end, float start_half_width, float end_half_width) {
        if (grid_width <= 0 || grid_height <= 0) {
            return;
        }
        const float max_half_width = std::max(start_half_width, end_half_width);
        if (max_half_width <= FLOAT_EPSILON) {
            return;
        }
        const double start_x = segment_start.x;
        const double start_y = segment_start.y;
        const int min_x = static_cast<int>(std::floor(std::min(start_x, static_cast<double>(segment_end.x)) - max_half_width));
        const int max_x = static_cast<int>(std::ceil(std::max(start_x, static_cast<double>(segment_end.x)) + max_half_width));
        const int min_y = std::max(
            0,
            static_cast<int>(std::floor(std::min(start_y, static_cast<double>(segment_end.y)) - max_half_width))
        );
        const int max_y = std::min(
            grid_height - 1,
            static_cast<int>(std::ceil(std::max(start_y, static_cast<double>(segment_end.y)) + max_half_width))
        );
        const double segment_delta_x = static_cast<double>(segment_end.x) - start_x;
        const double segment_delta_y = static_cast<double>(segment_end.y) - start_y;
        const double segment_length_sq = segment_delta_x * segment_delta_x + segment_delta_y * segment_delta_y;
        double inverse_length_sq = 0.0;
        if (segment_length_sq > FLOAT_EPSILON) {
            inverse_length_sq = 1.0 / segment_length_sq;
        }
        const double width_delta = static_cast<double>(end_half_width) - static_cast<double>(start_half_width);
        const int x_span = max_x - min_x + 1;
        for (int grid_y = min_y; grid_y <= max_y; ++grid_y) {
            const int row_base = grid_y * grid_width;
            const double query_y = static_cast<double>(grid_y);
            const double offset_y = query_y - start_y;
            int wrapped_x = wrap_x(min_x, grid_width);
            double query_x = static_cast<double>(min_x);
            for (int x_offset = 0; x_offset < x_span; ++x_offset) {
                const double offset_x = query_x - start_x;
                double t = 0.0;
                if (inverse_length_sq > 0.0) {
                    t = std::clamp((offset_x * segment_delta_x + offset_y * segment_delta_y) * inverse_length_sq, 0.0, 1.0);
                }
                const double ridge_half_width = static_cast<double>(start_half_width) + width_delta * t;
                if (ridge_half_width > FLOAT_EPSILON) {
                    const double nearest_x = start_x + segment_delta_x * t;
                    const double nearest_y = start_y + segment_delta_y * t;
                    const double delta_x = query_x - nearest_x;
                    const double delta_y = query_y - nearest_y;
                    const double distance_sq = delta_x * delta_x + delta_y * delta_y;
                    const double half_width_sq = ridge_half_width * ridge_half_width;
                    if (distance_sq < half_width_sq) {
                        const float strength = resolve_ridge_strength(
                            static_cast<float>(std::sqrt(distance_sq)),
                            static_cast<float>(ridge_half_width)
                        );
                        const int cell_index = row_base + wrapped_x;
                        if (strength > ridge_write[cell_index]) {
                            ridge_write[cell_index] = strength;
                        }
                    }
                }
                query_x += 1.0;
                wrapped_x += 1;
                if (wrapped_x >= grid_width) {
                    wrapped_x = 0;
                }
            }
        }
    };

    for (int path_index = 0; path_index < path_offsets.size(); ++path_index) {
        const int start = offset_read[path_index];
        const int count = count_read[path_index];
        if (start < 0 || count <= 0 || start >= sample_count || start + count > sample_count) {
            continue;
        }
        if (count == 1) {
            stamp_point(sample_read[start], half_width_read[start]);
            continue;
        }
        for (int segment_index = start; segment_index < start + count - 1; ++segment_index) {
            stamp_segment(
                sample_read[segment_index],
                sample_read[segment_index + 1],
                half_width_read[segment_index],
                half_width_read[segment_index + 1]
            );
        }
    }

    return ridge_strength_grid;
}

Dictionary WorldPrePassKernels::compute_river_extraction(
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
) const {
    Dictionary result;
    const int cell_count = grid_width * grid_height;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        accumulation_grid.size() != cell_count ||
        lake_mask.size() != cell_count ||
        flow_dir_grid.size() != cell_count ||
        neighbor_distances.size() < NEIGHBOR_COUNT
    ) {
        return result;
    }

    PackedByteArray river_mask_grid;
    PackedFloat32Array river_width_grid;
    PackedFloat32Array river_distance_grid;
    river_mask_grid.resize(cell_count);
    river_width_grid.resize(cell_count);
    river_distance_grid.resize(cell_count);

    const float *accumulation_read = accumulation_grid.ptr();
    const uint8_t *lake_mask_read = lake_mask.ptr();
    const uint8_t *flow_dir_read = flow_dir_grid.ptr();
    const float *neighbor_costs = neighbor_distances.ptr();
    uint8_t *river_mask_write = river_mask_grid.ptrw();
    float *river_width_write = river_width_grid.ptrw();
    float *river_distance_write = river_distance_grid.ptrw();
    std::priority_queue<HeapEntry, std::vector<HeapEntry>, MinHeapCompare> heap;

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        river_mask_write[cell_index] = 0;
        river_width_write[cell_index] = 0.0f;
        river_distance_write[cell_index] = max_distance;

        if (lake_mask_read[cell_index] != 0) {
            continue;
        }
        if (accumulation_read[cell_index] + FLOAT_EPSILON < river_threshold) {
            continue;
        }
        const int target_index = get_flow_target_index(cell_index, flow_dir_read[cell_index], grid_width, grid_height);
        if (target_index < 0 && !is_y_edge_cell(cell_index, grid_width, grid_height)) {
            continue;
        }

        river_mask_write[cell_index] = 1;
        river_width_write[cell_index] = resolve_river_width(
            accumulation_read[cell_index],
            river_threshold,
            river_base_width,
            river_width_scale
        );
        river_distance_write[cell_index] = 0.0f;
        heap.push({0.0f, cell_index});
    }

    while (!heap.empty()) {
        const HeapEntry current = heap.top();
        heap.pop();
        if (current.index < 0 || current.index >= cell_count) {
            continue;
        }
        if (current.priority > river_distance_write[current.index] + FLOAT_EPSILON) {
            continue;
        }

        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_index = get_neighbor_index(current.index, direction_index, grid_width, grid_height);
            if (neighbor_index < 0) {
                continue;
            }
            const float next_distance = current.priority + neighbor_costs[direction_index];
            if (next_distance + FLOAT_EPSILON >= river_distance_write[neighbor_index]) {
                continue;
            }
            river_distance_write[neighbor_index] = next_distance;
            heap.push({next_distance, neighbor_index});
        }
    }

    result["river_mask_grid"] = river_mask_grid;
    result["river_width_grid"] = river_width_grid;
    result["river_distance_grid"] = river_distance_grid;
    return result;
}
