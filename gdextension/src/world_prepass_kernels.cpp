#include "world_prepass_kernels.h"

#include <algorithm>
#include <cmath>
#include <map>

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
            "compute_flow_directions",
            "grid_width",
            "grid_height",
            "filled_height_grid"
        ),
        &WorldPrePassKernels::compute_flow_directions
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_flow_accumulation",
            "grid_width",
            "grid_height",
            "flow_dir_grid",
            "temperature_grid",
            "lake_mask",
            "frozen_threshold",
            "glacial_melt_temperature",
            "glacial_melt_bonus",
            "evaporation_rate"
        ),
        &WorldPrePassKernels::compute_flow_accumulation
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_lake_records",
            "grid_width",
            "grid_height",
            "height_grid",
            "filled_height_grid",
            "temperature_grid",
            "ruggedness_grid",
            "max_lake_id",
            "min_area",
            "min_depth",
            "frozen_lake_temperature",
            "max_classify_samples"
        ),
        &WorldPrePassKernels::compute_lake_records
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_floodplain_strength",
            "grid_width",
            "grid_height",
            "river_mask_grid",
            "lake_mask",
            "floodplain_source_widths",
            "neighbor_distances",
            "floodplain_multiplier"
        ),
        &WorldPrePassKernels::compute_floodplain_strength
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_floodplain_deposition",
            "grid_width",
            "grid_height",
            "eroded_height_grid",
            "river_mask_grid",
            "lake_mask",
            "deposition_source_widths",
            "neighbor_distances",
            "floodplain_multiplier",
            "deposit_rate"
        ),
        &WorldPrePassKernels::compute_floodplain_deposition
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_slope_grid",
            "grid_width",
            "grid_height",
            "eroded_height_grid",
            "neighbor_distances",
            "max_possible_gradient"
        ),
        &WorldPrePassKernels::compute_slope_grid
    );
    ClassDB::bind_method(
        D_METHOD(
            "compute_rain_shadow",
            "grid_width",
            "grid_height",
            "eroded_height_grid",
            "moisture_grid",
            "grid_world_x",
            "grid_world_y",
            "grid_span_x",
            "grid_span_y",
            "wrap_width_tiles",
            "wind_direction",
            "max_possible_gradient",
            "precipitation_rate",
            "lift_factor",
            "evaporation_rate",
            "column_scale"
        ),
        &WorldPrePassKernels::compute_rain_shadow
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

float WorldPrePassKernels::resolve_floodplain_strength(float distance_to_river, float floodplain_width) {
    if (floodplain_width <= FLOAT_EPSILON) {
        return 0.0f;
    }
    const float t = std::clamp(1.0f - distance_to_river / floodplain_width, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
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

PackedByteArray WorldPrePassKernels::compute_flow_directions(
    int grid_width,
    int grid_height,
    PackedFloat32Array filled_height_grid
) const {
    const int cell_count = grid_width * grid_height;
    PackedByteArray flow_dir_grid;
    if (grid_width <= 0 || grid_height <= 0 || cell_count <= 0 || filled_height_grid.size() != cell_count) {
        return flow_dir_grid;
    }

    flow_dir_grid.resize(cell_count);
    const float *filled_height_read = filled_height_grid.ptr();
    uint8_t *flow_dir_write = flow_dir_grid.ptrw();
    std::vector<uint8_t> unresolved_plateau_cells(static_cast<size_t>(cell_count), 0);
    constexpr uint8_t FLOW_DIRECTION_NONE = 255;
    constexpr float DIAGONAL_DIRECTION_DISTANCE = 1.41421356237f;
    const float neighbor_distances[NEIGHBOR_COUNT] = {
        DIAGONAL_DIRECTION_DISTANCE,
        1.0f,
        DIAGONAL_DIRECTION_DISTANCE,
        1.0f,
        1.0f,
        DIAGONAL_DIRECTION_DISTANCE,
        1.0f,
        DIAGONAL_DIRECTION_DISTANCE
    };

    auto heights_match = [&](float left_height, float right_height) -> bool {
        return std::abs(left_height - right_height) <= FLOAT_EPSILON;
    };
    auto is_index_lexicographically_less = [&](int left_index, int right_index) -> bool {
        if (right_index < 0) {
            return true;
        }
        int left_x = 0;
        int left_y = 0;
        int right_x = 0;
        int right_y = 0;
        decode_index(left_index, grid_width, left_x, left_y);
        decode_index(right_index, grid_width, right_x, right_y);
        if (left_y != right_y) {
            return left_y < right_y;
        }
        return left_x < right_x;
    };
    auto get_direction_between_indices = [&](int from_index, int to_index) -> int {
        if (from_index < 0 || to_index < 0) {
            return -1;
        }
        int from_x = 0;
        int from_y = 0;
        int to_x = 0;
        int to_y = 0;
        decode_index(from_index, grid_width, from_x, from_y);
        decode_index(to_index, grid_width, to_x, to_y);
        int delta_x = to_x - from_x;
        if (delta_x > 1) {
            delta_x -= grid_width;
        } else if (delta_x < -1) {
            delta_x += grid_width;
        }
        const int delta_y = to_y - from_y;
        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            if (DX[direction_index] == delta_x && DY[direction_index] == delta_y) {
                return direction_index;
            }
        }
        return -1;
    };
    auto find_direct_flow_direction = [&](int cell_index) -> int {
        const float current_height = filled_height_read[cell_index];
        int best_direction = -1;
        float best_gradient = 0.0f;
        int best_neighbor_index = -1;
        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_index = get_neighbor_index(cell_index, direction_index, grid_width, grid_height);
            if (neighbor_index < 0) {
                continue;
            }
            const float height_drop = current_height - filled_height_read[neighbor_index];
            if (height_drop <= FLOAT_EPSILON) {
                continue;
            }
            const float gradient = height_drop / neighbor_distances[direction_index];
            if (gradient > best_gradient + FLOAT_EPSILON) {
                best_direction = direction_index;
                best_gradient = gradient;
                best_neighbor_index = neighbor_index;
                continue;
            }
            if (std::abs(gradient - best_gradient) <= FLOAT_EPSILON &&
                is_index_lexicographically_less(neighbor_index, best_neighbor_index)) {
                best_direction = direction_index;
                best_neighbor_index = neighbor_index;
            }
        }
        return best_direction;
    };
    auto find_flat_exit_direction = [&](int cell_index, float plateau_height) -> int {
        int best_direction = -1;
        int best_neighbor_index = -1;
        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_index = get_neighbor_index(cell_index, direction_index, grid_width, grid_height);
            if (neighbor_index < 0) {
                continue;
            }
            if (!heights_match(filled_height_read[neighbor_index], plateau_height)) {
                continue;
            }
            if (unresolved_plateau_cells[static_cast<size_t>(neighbor_index)] == 2) {
                continue;
            }
            if (!is_y_edge_cell(neighbor_index, grid_width, grid_height) && flow_dir_write[neighbor_index] == FLOW_DIRECTION_NONE) {
                continue;
            }
            if (best_direction < 0 || is_index_lexicographically_less(neighbor_index, best_neighbor_index)) {
                best_direction = direction_index;
                best_neighbor_index = neighbor_index;
            }
        }
        return best_direction;
    };
    auto resolve_flat_plateau_flow = [&](int start_index) -> void {
        const float plateau_height = filled_height_read[start_index];
        std::vector<int> plateau_cells;
        std::vector<int> queue;
        queue.push_back(start_index);
        size_t queue_index = 0;
        unresolved_plateau_cells[static_cast<size_t>(start_index)] = 2;
        while (queue_index < queue.size()) {
            const int current_index = queue[queue_index++];
            plateau_cells.push_back(current_index);
            for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
                const int neighbor_index = get_neighbor_index(current_index, direction_index, grid_width, grid_height);
                if (neighbor_index < 0) {
                    continue;
                }
                if (unresolved_plateau_cells[static_cast<size_t>(neighbor_index)] != 1) {
                    continue;
                }
                if (!heights_match(filled_height_read[neighbor_index], plateau_height)) {
                    continue;
                }
                unresolved_plateau_cells[static_cast<size_t>(neighbor_index)] = 2;
                queue.push_back(neighbor_index);
            }
        }

        std::sort(plateau_cells.begin(), plateau_cells.end());
        std::vector<int> propagation_queue;
        for (int cell_index : plateau_cells) {
            const int exit_direction = find_flat_exit_direction(cell_index, plateau_height);
            if (exit_direction < 0) {
                continue;
            }
            flow_dir_write[cell_index] = static_cast<uint8_t>(exit_direction);
            unresolved_plateau_cells[static_cast<size_t>(cell_index)] = 0;
            propagation_queue.push_back(cell_index);
        }

        size_t propagation_index = 0;
        while (propagation_index < propagation_queue.size()) {
            const int resolved_index = propagation_queue[propagation_index++];
            for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
                const int neighbor_index = get_neighbor_index(resolved_index, direction_index, grid_width, grid_height);
                if (neighbor_index < 0) {
                    continue;
                }
                if (unresolved_plateau_cells[static_cast<size_t>(neighbor_index)] != 2) {
                    continue;
                }
                if (!heights_match(filled_height_read[neighbor_index], plateau_height)) {
                    continue;
                }
                const int toward_resolved_direction = get_direction_between_indices(neighbor_index, resolved_index);
                if (toward_resolved_direction < 0) {
                    continue;
                }
                flow_dir_write[neighbor_index] = static_cast<uint8_t>(toward_resolved_direction);
                unresolved_plateau_cells[static_cast<size_t>(neighbor_index)] = 0;
                propagation_queue.push_back(neighbor_index);
            }
        }

        for (int cell_index : plateau_cells) {
            if (unresolved_plateau_cells[static_cast<size_t>(cell_index)] != 0) {
                unresolved_plateau_cells[static_cast<size_t>(cell_index)] = 0;
            }
        }
    };

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        flow_dir_write[cell_index] = FLOW_DIRECTION_NONE;
        if (is_y_edge_cell(cell_index, grid_width, grid_height)) {
            continue;
        }
        const int direct_direction = find_direct_flow_direction(cell_index);
        if (direct_direction >= 0) {
            flow_dir_write[cell_index] = static_cast<uint8_t>(direct_direction);
            continue;
        }
        unresolved_plateau_cells[static_cast<size_t>(cell_index)] = 1;
    }

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        if (unresolved_plateau_cells[static_cast<size_t>(cell_index)] != 1) {
            continue;
        }
        resolve_flat_plateau_flow(cell_index);
    }

    return flow_dir_grid;
}

Dictionary WorldPrePassKernels::compute_flow_accumulation(
    int grid_width,
    int grid_height,
    PackedByteArray flow_dir_grid,
    PackedFloat32Array temperature_grid,
    PackedInt32Array lake_mask,
    float frozen_threshold,
    float glacial_melt_temperature,
    float glacial_melt_bonus,
    float evaporation_rate
) const {
    Dictionary result;
    const int cell_count = grid_width * grid_height;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        flow_dir_grid.size() != cell_count ||
        temperature_grid.size() != cell_count ||
        lake_mask.size() != cell_count
    ) {
        return result;
    }

    PackedFloat32Array accumulation_grid;
    PackedFloat32Array drainage_grid;
    PackedFloat32Array lake_inflow_totals;
    PackedInt32Array indegree;
    accumulation_grid.resize(cell_count);
    drainage_grid.resize(cell_count);
    indegree.resize(cell_count);

    const uint8_t *flow_dir_read = flow_dir_grid.ptr();
    const float *temperature_read = temperature_grid.ptr();
    const int32_t *lake_mask_read = lake_mask.ptr();
    float *accumulation_write = accumulation_grid.ptrw();
    float *drainage_write = drainage_grid.ptrw();
    int32_t *indegree_write = indegree.ptrw();
    int max_lake_id = 0;
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        max_lake_id = std::max(max_lake_id, static_cast<int>(lake_mask_read[cell_index]));
    }
    if (max_lake_id > 0) {
        lake_inflow_totals.resize(max_lake_id + 1);
        float *lake_inflow_write = lake_inflow_totals.ptrw();
        for (int lake_index = 0; lake_index < max_lake_id + 1; ++lake_index) {
            lake_inflow_write[lake_index] = 0.0f;
        }
    }

    auto resolve_base_accumulation = [&](float temperature) -> float {
        if (temperature >= glacial_melt_temperature) {
            return 1.0f;
        }
        const float thaw_span = std::max(0.05f, glacial_melt_temperature);
        const float thaw_t = std::clamp(temperature / thaw_span, 0.0f, 1.0f);
        const float glacial_melt_strength = 0.18f + (1.0f - 0.18f) * thaw_t;
        return 1.0f + std::max(0.0f, glacial_melt_bonus) * glacial_melt_strength;
    };
    auto resolve_downstream_transfer = [&](float accumulation, float temperature) -> float {
        const float heat_span = std::max(0.12f, 1.0f - frozen_threshold);
        const float heat_t = std::clamp((temperature - frozen_threshold) / heat_span, 0.0f, 1.0f);
        const float evaporation_factor = 1.0f - heat_t;
        const float evaporation_loss = accumulation * std::max(0.0f, evaporation_rate) * evaporation_factor;
        return std::max(0.0f, accumulation - evaporation_loss);
    };

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        accumulation_write[cell_index] = resolve_base_accumulation(temperature_read[cell_index]);
        drainage_write[cell_index] = 0.0f;
        indegree_write[cell_index] = 0;
    }

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        const int target_index = get_flow_target_index(cell_index, flow_dir_read[cell_index], grid_width, grid_height);
        if (target_index >= 0) {
            indegree_write[target_index] += 1;
        }
    }

    std::vector<int> queue;
    queue.reserve(static_cast<size_t>(cell_count));
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        if (indegree_write[cell_index] == 0) {
            queue.push_back(cell_index);
        }
    }

    int processed_count = 0;
    size_t queue_index = 0;
    while (queue_index < queue.size()) {
        const int cell_index = queue[queue_index++];
        processed_count += 1;
        const int target_index = get_flow_target_index(cell_index, flow_dir_read[cell_index], grid_width, grid_height);
        if (target_index >= 0) {
            const float transfer = resolve_downstream_transfer(accumulation_write[cell_index], temperature_read[cell_index]);
            accumulation_write[target_index] += transfer;
            if (transfer > 0.0f && max_lake_id > 0) {
                const int target_lake_id = static_cast<int>(lake_mask_read[target_index]);
                const int source_lake_id = static_cast<int>(lake_mask_read[cell_index]);
                if (target_lake_id > 0 && source_lake_id != target_lake_id && target_lake_id < lake_inflow_totals.size()) {
                    float *lake_inflow_write = lake_inflow_totals.ptrw();
                    lake_inflow_write[target_lake_id] += transfer;
                }
            }
            indegree_write[target_index] -= 1;
            if (indegree_write[target_index] == 0) {
                queue.push_back(target_index);
            }
        }
    }

    float max_accumulation = 0.0f;
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        max_accumulation = std::max(max_accumulation, accumulation_write[cell_index]);
    }
    if (max_accumulation > 1.0f + FLOAT_EPSILON) {
        const float log2_divisor = std::log(2.0f);
        const float max_log_accumulation = std::log(max_accumulation) / log2_divisor;
        if (max_log_accumulation > FLOAT_EPSILON) {
            for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
                const float accumulation = std::max(1.0f, accumulation_write[cell_index]);
                const float drainage = (std::log(accumulation) / log2_divisor) / max_log_accumulation;
                drainage_write[cell_index] = std::clamp(drainage, 0.0f, 1.0f);
            }
        }
    }

    result["accumulation_grid"] = accumulation_grid;
    result["drainage_grid"] = drainage_grid;
    result["processed_count"] = processed_count;
    result["lake_inflow_totals"] = lake_inflow_totals;
    return result;
}

Dictionary WorldPrePassKernels::compute_lake_records(
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
) const {
    Dictionary result;
    const int cell_count = grid_width * grid_height;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        height_grid.size() != cell_count ||
        filled_height_grid.size() != cell_count ||
        temperature_grid.size() != cell_count ||
        ruggedness_grid.size() != cell_count ||
        max_lake_id <= 0
    ) {
        return result;
    }

    PackedInt32Array lake_mask;
    lake_mask.resize(cell_count);
    int32_t *lake_mask_write = lake_mask.ptrw();
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        lake_mask_write[cell_index] = 0;
    }

    const float *height_read = height_grid.ptr();
    const float *filled_height_read = filled_height_grid.ptr();
    const float *temperature_read = temperature_grid.ptr();
    const float *ruggedness_read = ruggedness_grid.ptr();

    std::vector<int32_t> component_id_by_cell(static_cast<size_t>(cell_count), -1);
    std::vector<int32_t> lake_cell_offsets;
    std::vector<int32_t> lake_cell_counts;
    std::vector<int32_t> lake_cell_indices;
    std::vector<int32_t> spill_indices;
    std::vector<float> surface_heights;
    std::vector<float> max_depths;
    std::vector<int32_t> area_grid_cells;
    std::vector<uint8_t> lake_type_codes;

    auto heights_match = [&](float left_height, float right_height) -> bool {
        return std::abs(left_height - right_height) <= FLOAT_EPSILON;
    };
    auto is_index_lexicographically_less = [&](int left_index, int right_index) -> bool {
        if (right_index < 0) {
            return true;
        }
        int left_x = 0;
        int left_y = 0;
        int right_x = 0;
        int right_y = 0;
        decode_index(left_index, grid_width, left_x, left_y);
        decode_index(right_index, grid_width, right_x, right_y);
        if (left_y != right_y) {
            return left_y < right_y;
        }
        return left_x < right_x;
    };
    auto classify_lake_type_code = [&](const std::vector<int> &component_cells, float max_depth) -> uint8_t {
        if (component_cells.empty()) {
            return 2;
        }
        const int sample_count = std::max(1, std::min(static_cast<int>(component_cells.size()), std::max(1, max_classify_samples)));
        float total_temperature = 0.0f;
        float total_height = 0.0f;
        float total_ruggedness = 0.0f;
        if (static_cast<int>(component_cells.size()) <= sample_count) {
            for (int cell_index : component_cells) {
                total_temperature += temperature_read[cell_index];
                total_height += height_read[cell_index];
                total_ruggedness += ruggedness_read[cell_index];
            }
        } else {
            const int max_offset = static_cast<int>(component_cells.size()) - 1;
            for (int sample_index = 0; sample_index < sample_count; ++sample_index) {
                int offset = static_cast<int>(std::round(
                    static_cast<float>(sample_index) * static_cast<float>(max_offset) / static_cast<float>(std::max(1, sample_count - 1))
                ));
                offset = std::clamp(offset, 0, max_offset);
                const int cell_index = component_cells[static_cast<size_t>(offset)];
                total_temperature += temperature_read[cell_index];
                total_height += height_read[cell_index];
                total_ruggedness += ruggedness_read[cell_index];
            }
        }
        const float inv_sample_count = 1.0f / static_cast<float>(sample_count);
        const float average_temperature = total_temperature * inv_sample_count;
        if (average_temperature <= frozen_lake_temperature) {
            return 1;
        }
        if (component_cells.size() >= 50 && max_depth > 0.15f) {
            return 3;
        }
        const float average_height = total_height * inv_sample_count;
        const float average_ruggedness = total_ruggedness * inv_sample_count;
        if (average_height >= 0.58f || average_ruggedness >= 0.45f) {
            return 0;
        }
        return 2;
    };

    int next_component_id = 0;
    bool overflowed = false;
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        if (component_id_by_cell[static_cast<size_t>(cell_index)] != -1) {
            continue;
        }
        if (filled_height_read[cell_index] <= height_read[cell_index] + FLOAT_EPSILON) {
            continue;
        }

        const float surface_height = filled_height_read[cell_index];
        std::vector<int> component_cells;
        std::vector<int> queue;
        queue.push_back(cell_index);
        component_id_by_cell[static_cast<size_t>(cell_index)] = next_component_id;
        size_t queue_index = 0;
        while (queue_index < queue.size()) {
            const int current_index = queue[queue_index++];
            component_cells.push_back(current_index);
            for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
                const int neighbor_index = get_neighbor_index(current_index, direction_index, grid_width, grid_height);
                if (neighbor_index < 0) {
                    continue;
                }
                if (component_id_by_cell[static_cast<size_t>(neighbor_index)] != -1) {
                    continue;
                }
                if (filled_height_read[neighbor_index] <= height_read[neighbor_index] + FLOAT_EPSILON) {
                    continue;
                }
                if (!heights_match(filled_height_read[neighbor_index], surface_height)) {
                    continue;
                }
                component_id_by_cell[static_cast<size_t>(neighbor_index)] = next_component_id;
                queue.push_back(neighbor_index);
            }
        }
        next_component_id += 1;
        if (component_cells.empty()) {
            continue;
        }
        std::sort(component_cells.begin(), component_cells.end());
        const int area = static_cast<int>(component_cells.size());
        if (area < min_area) {
            continue;
        }
        float component_max_depth = 0.0f;
        for (int component_cell_index : component_cells) {
            component_max_depth = std::max(component_max_depth, filled_height_read[component_cell_index] - height_read[component_cell_index]);
        }
        if (component_max_depth < min_depth) {
            continue;
        }
        if (static_cast<int>(lake_cell_offsets.size()) >= max_lake_id) {
            overflowed = true;
            break;
        }

        int spill_index = -1;
        float best_filled_height = INFINITY;
        float best_raw_height = INFINITY;
        for (int component_cell_index : component_cells) {
            for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
                const int neighbor_index = get_neighbor_index(component_cell_index, direction_index, grid_width, grid_height);
                if (neighbor_index < 0) {
                    continue;
                }
                if (component_id_by_cell[static_cast<size_t>(neighbor_index)] == next_component_id - 1) {
                    continue;
                }
                const float neighbor_filled_height = filled_height_read[neighbor_index];
                const float neighbor_raw_height = height_read[neighbor_index];
                if (neighbor_filled_height < best_filled_height - FLOAT_EPSILON) {
                    spill_index = neighbor_index;
                    best_filled_height = neighbor_filled_height;
                    best_raw_height = neighbor_raw_height;
                    continue;
                }
                if (std::abs(neighbor_filled_height - best_filled_height) <= FLOAT_EPSILON) {
                    if (neighbor_raw_height < best_raw_height - FLOAT_EPSILON) {
                        spill_index = neighbor_index;
                        best_raw_height = neighbor_raw_height;
                        continue;
                    }
                    if (std::abs(neighbor_raw_height - best_raw_height) <= FLOAT_EPSILON &&
                        is_index_lexicographically_less(neighbor_index, spill_index)) {
                        spill_index = neighbor_index;
                    }
                }
            }
        }
        if (spill_index < 0) {
            spill_index = component_cells.front();
        }

        const uint8_t lake_type_code = classify_lake_type_code(component_cells, component_max_depth);
        const int lake_id = static_cast<int>(lake_cell_offsets.size()) + 1;
        lake_cell_offsets.push_back(static_cast<int32_t>(lake_cell_indices.size()));
        lake_cell_counts.push_back(static_cast<int32_t>(component_cells.size()));
        spill_indices.push_back(static_cast<int32_t>(spill_index));
        surface_heights.push_back(surface_height);
        max_depths.push_back(component_max_depth);
        area_grid_cells.push_back(static_cast<int32_t>(area));
        lake_type_codes.push_back(lake_type_code);
        lake_cell_indices.insert(lake_cell_indices.end(), component_cells.begin(), component_cells.end());
        for (int component_cell_index : component_cells) {
            lake_mask_write[component_cell_index] = lake_id;
        }
    }

    PackedInt32Array lake_cell_offsets_array;
    lake_cell_offsets_array.resize(static_cast<int>(lake_cell_offsets.size()));
    int32_t *lake_cell_offsets_write = lake_cell_offsets_array.ptrw();
    for (int index = 0; index < static_cast<int>(lake_cell_offsets.size()); ++index) {
        lake_cell_offsets_write[index] = lake_cell_offsets[static_cast<size_t>(index)];
    }

    PackedInt32Array lake_cell_counts_array;
    lake_cell_counts_array.resize(static_cast<int>(lake_cell_counts.size()));
    int32_t *lake_cell_counts_write = lake_cell_counts_array.ptrw();
    for (int index = 0; index < static_cast<int>(lake_cell_counts.size()); ++index) {
        lake_cell_counts_write[index] = lake_cell_counts[static_cast<size_t>(index)];
    }

    PackedInt32Array lake_cell_indices_array;
    lake_cell_indices_array.resize(static_cast<int>(lake_cell_indices.size()));
    int32_t *lake_cell_indices_write = lake_cell_indices_array.ptrw();
    for (int index = 0; index < static_cast<int>(lake_cell_indices.size()); ++index) {
        lake_cell_indices_write[index] = lake_cell_indices[static_cast<size_t>(index)];
    }

    PackedInt32Array spill_indices_array;
    spill_indices_array.resize(static_cast<int>(spill_indices.size()));
    int32_t *spill_indices_write = spill_indices_array.ptrw();
    for (int index = 0; index < static_cast<int>(spill_indices.size()); ++index) {
        spill_indices_write[index] = spill_indices[static_cast<size_t>(index)];
    }

    PackedFloat32Array surface_heights_array;
    surface_heights_array.resize(static_cast<int>(surface_heights.size()));
    float *surface_heights_write = surface_heights_array.ptrw();
    for (int index = 0; index < static_cast<int>(surface_heights.size()); ++index) {
        surface_heights_write[index] = surface_heights[static_cast<size_t>(index)];
    }

    PackedFloat32Array max_depths_array;
    max_depths_array.resize(static_cast<int>(max_depths.size()));
    float *max_depths_write = max_depths_array.ptrw();
    for (int index = 0; index < static_cast<int>(max_depths.size()); ++index) {
        max_depths_write[index] = max_depths[static_cast<size_t>(index)];
    }

    PackedInt32Array area_grid_cells_array;
    area_grid_cells_array.resize(static_cast<int>(area_grid_cells.size()));
    int32_t *area_grid_cells_write = area_grid_cells_array.ptrw();
    for (int index = 0; index < static_cast<int>(area_grid_cells.size()); ++index) {
        area_grid_cells_write[index] = area_grid_cells[static_cast<size_t>(index)];
    }

    PackedByteArray lake_type_codes_array;
    lake_type_codes_array.resize(static_cast<int>(lake_type_codes.size()));
    uint8_t *lake_type_codes_write = lake_type_codes_array.ptrw();
    for (int index = 0; index < static_cast<int>(lake_type_codes.size()); ++index) {
        lake_type_codes_write[index] = lake_type_codes[static_cast<size_t>(index)];
    }

    result["lake_mask"] = lake_mask;
    result["lake_cell_offsets"] = lake_cell_offsets_array;
    result["lake_cell_counts"] = lake_cell_counts_array;
    result["lake_cell_indices"] = lake_cell_indices_array;
    result["spill_indices"] = spill_indices_array;
    result["surface_heights"] = surface_heights_array;
    result["max_depths"] = max_depths_array;
    result["area_grid_cells"] = area_grid_cells_array;
    result["lake_type_codes"] = lake_type_codes_array;
    result["overflowed"] = overflowed;
    return result;
}

PackedFloat32Array WorldPrePassKernels::compute_floodplain_strength(
    int grid_width,
    int grid_height,
    PackedByteArray river_mask_grid,
    PackedInt32Array lake_mask,
    PackedFloat32Array floodplain_source_widths,
    PackedFloat32Array neighbor_distances,
    float floodplain_multiplier
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array floodplain_strength_grid;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        river_mask_grid.size() != cell_count ||
        lake_mask.size() != cell_count ||
        floodplain_source_widths.size() != cell_count ||
        neighbor_distances.size() < NEIGHBOR_COUNT
    ) {
        return floodplain_strength_grid;
    }

    floodplain_strength_grid.resize(cell_count);
    float *floodplain_strength_write = floodplain_strength_grid.ptrw();
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        floodplain_strength_write[cell_index] = 0.0f;
    }

    const uint8_t *river_mask_read = river_mask_grid.ptr();
    const int32_t *lake_mask_read = lake_mask.ptr();
    const float *source_widths_read = floodplain_source_widths.ptr();
    const float *neighbor_costs = neighbor_distances.ptr();
    const float safe_multiplier = std::max(1.0f, floodplain_multiplier);

    struct FloodplainEntry {
        float distance = 0.0f;
        int index = -1;
        float floodplain_width = 0.0f;
    };
    struct FloodplainCompare {
        bool operator()(const FloodplainEntry &left, const FloodplainEntry &right) const {
            constexpr float HEAP_FLOAT_EPSILON = 0.00001f;
            if (left.distance > right.distance + HEAP_FLOAT_EPSILON) {
                return true;
            }
            if (left.distance + HEAP_FLOAT_EPSILON < right.distance) {
                return false;
            }
            return left.index > right.index;
        }
    };
    std::priority_queue<FloodplainEntry, std::vector<FloodplainEntry>, FloodplainCompare> heap;

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        if (river_mask_read[cell_index] != 1) {
            continue;
        }
        const float source_width = std::max(0.0f, source_widths_read[cell_index]);
        const float floodplain_width = source_width * safe_multiplier;
        if (floodplain_width <= FLOAT_EPSILON) {
            continue;
        }
        floodplain_strength_write[cell_index] = 1.0f;
        heap.push({0.0f, cell_index, floodplain_width});
    }

    while (!heap.empty()) {
        const FloodplainEntry current = heap.top();
        heap.pop();
        if (current.index < 0 || current.index >= cell_count || current.floodplain_width <= FLOAT_EPSILON) {
            continue;
        }
        const float current_strength = resolve_floodplain_strength(current.distance, current.floodplain_width);
        if (current_strength + FLOAT_EPSILON < floodplain_strength_write[current.index]) {
            continue;
        }
        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_index = get_neighbor_index(current.index, direction_index, grid_width, grid_height);
            if (neighbor_index < 0) {
                continue;
            }
            if (lake_mask_read[neighbor_index] > 0) {
                continue;
            }
            const float next_distance = current.distance + neighbor_costs[direction_index];
            const float next_strength = resolve_floodplain_strength(next_distance, current.floodplain_width);
            if (next_strength <= FLOAT_EPSILON) {
                continue;
            }
            if (next_strength + FLOAT_EPSILON <= floodplain_strength_write[neighbor_index]) {
                continue;
            }
            floodplain_strength_write[neighbor_index] = next_strength;
            heap.push({next_distance, neighbor_index, current.floodplain_width});
        }
    }

    return floodplain_strength_grid;
}

PackedFloat32Array WorldPrePassKernels::compute_floodplain_deposition(
    int grid_width,
    int grid_height,
    PackedFloat32Array eroded_height_grid,
    PackedByteArray river_mask_grid,
    PackedInt32Array lake_mask,
    PackedFloat32Array deposition_source_widths,
    PackedFloat32Array neighbor_distances,
    float floodplain_multiplier,
    float deposit_rate
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array result;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        eroded_height_grid.size() != cell_count ||
        river_mask_grid.size() != cell_count ||
        lake_mask.size() != cell_count ||
        deposition_source_widths.size() != cell_count ||
        neighbor_distances.size() < NEIGHBOR_COUNT
    ) {
        return result;
    }

    result = eroded_height_grid;
    if (deposit_rate <= FLOAT_EPSILON) {
        return result;
    }

    const uint8_t *river_mask_read = river_mask_grid.ptr();
    const int32_t *lake_mask_read = lake_mask.ptr();
    const float *source_widths_read = deposition_source_widths.ptr();
    const float *neighbor_costs = neighbor_distances.ptr();
    const float *eroded_height_read = eroded_height_grid.ptr();
    float *result_write = result.ptrw();
    const float safe_multiplier = std::max(1.0f, floodplain_multiplier);
    const float safe_deposit_rate = std::clamp(deposit_rate, 0.0f, 1.0f);

    std::vector<float> strongest_deposition(static_cast<size_t>(cell_count), 0.0f);
    std::vector<float> river_height_targets(static_cast<size_t>(cell_count), 0.0f);

    struct DepositionEntry {
        float distance = 0.0f;
        int index = -1;
        float floodplain_width = 0.0f;
        float source_height = 0.0f;
    };
    struct DepositionCompare {
        bool operator()(const DepositionEntry &left, const DepositionEntry &right) const {
            constexpr float HEAP_FLOAT_EPSILON = 0.00001f;
            if (left.distance > right.distance + HEAP_FLOAT_EPSILON) {
                return true;
            }
            if (left.distance + HEAP_FLOAT_EPSILON < right.distance) {
                return false;
            }
            return left.index > right.index;
        }
    };
    std::priority_queue<DepositionEntry, std::vector<DepositionEntry>, DepositionCompare> heap;

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        if (river_mask_read[cell_index] != 1) {
            continue;
        }
        const float source_width = std::max(0.0f, source_widths_read[cell_index]);
        const float floodplain_width = source_width * safe_multiplier;
        if (floodplain_width <= FLOAT_EPSILON) {
            continue;
        }
        strongest_deposition[static_cast<size_t>(cell_index)] = 1.0f;
        river_height_targets[static_cast<size_t>(cell_index)] = eroded_height_read[cell_index];
        heap.push({0.0f, cell_index, floodplain_width, eroded_height_read[cell_index]});
    }

    while (!heap.empty()) {
        const DepositionEntry current = heap.top();
        heap.pop();
        if (current.index < 0 || current.index >= cell_count || current.floodplain_width <= FLOAT_EPSILON) {
            continue;
        }
        const float current_strength = resolve_floodplain_strength(current.distance, current.floodplain_width);
        if (current_strength + FLOAT_EPSILON < strongest_deposition[static_cast<size_t>(current.index)]) {
            continue;
        }
        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_index = get_neighbor_index(current.index, direction_index, grid_width, grid_height);
            if (neighbor_index < 0) {
                continue;
            }
            if (lake_mask_read[neighbor_index] > 0) {
                continue;
            }
            const float next_distance = current.distance + neighbor_costs[direction_index];
            const float next_strength = resolve_floodplain_strength(next_distance, current.floodplain_width);
            if (next_strength <= FLOAT_EPSILON) {
                continue;
            }
            if (next_strength + FLOAT_EPSILON <= strongest_deposition[static_cast<size_t>(neighbor_index)]) {
                continue;
            }
            strongest_deposition[static_cast<size_t>(neighbor_index)] = next_strength;
            river_height_targets[static_cast<size_t>(neighbor_index)] = current.source_height;
            heap.push({next_distance, neighbor_index, current.floodplain_width, current.source_height});
        }
    }

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        if (lake_mask_read[cell_index] > 0) {
            continue;
        }
        const float deposition = std::clamp(
            safe_deposit_rate * strongest_deposition[static_cast<size_t>(cell_index)],
            0.0f,
            1.0f
        );
        if (deposition <= FLOAT_EPSILON) {
            continue;
        }
        const float current_height = result_write[cell_index];
        const float target_height = river_height_targets[static_cast<size_t>(cell_index)];
        result_write[cell_index] = std::clamp(
            current_height + (target_height - current_height) * deposition,
            0.0f,
            1.0f
        );
    }

    return result;
}

PackedFloat32Array WorldPrePassKernels::compute_slope_grid(
    int grid_width,
    int grid_height,
    PackedFloat32Array eroded_height_grid,
    PackedFloat32Array neighbor_distances,
    float max_possible_gradient
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array slope_grid;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        eroded_height_grid.size() != cell_count ||
        neighbor_distances.size() < NEIGHBOR_COUNT
    ) {
        return slope_grid;
    }

    slope_grid.resize(cell_count);
    float *slope_write = slope_grid.ptrw();
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        slope_write[cell_index] = 0.0f;
    }
    if (max_possible_gradient <= FLOAT_EPSILON) {
        return slope_grid;
    }

    const float *height_read = eroded_height_grid.ptr();
    const float *neighbor_costs = neighbor_distances.ptr();
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        const float current_height = height_read[cell_index];
        float max_gradient = 0.0f;
        for (int direction_index = 0; direction_index < NEIGHBOR_COUNT; ++direction_index) {
            const int neighbor_index = get_neighbor_index(cell_index, direction_index, grid_width, grid_height);
            if (neighbor_index < 0) {
                continue;
            }
            const float neighbor_distance = std::max(FLOAT_EPSILON, neighbor_costs[direction_index]);
            const float gradient = std::abs(current_height - height_read[neighbor_index]) / neighbor_distance;
            max_gradient = std::max(max_gradient, gradient);
        }
        if (max_gradient <= FLOAT_EPSILON) {
            continue;
        }
        slope_write[cell_index] = std::clamp(max_gradient / max_possible_gradient, 0.0f, 1.0f);
    }

    return slope_grid;
}

PackedFloat32Array WorldPrePassKernels::compute_rain_shadow(
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
) const {
    const int cell_count = grid_width * grid_height;
    PackedFloat32Array rain_shadow_grid;
    if (
        grid_width <= 0 ||
        grid_height <= 0 ||
        cell_count <= 0 ||
        eroded_height_grid.size() != cell_count ||
        moisture_grid.size() != cell_count ||
        grid_world_x.size() != cell_count ||
        grid_world_y.size() != cell_count ||
        grid_span_x <= FLOAT_EPSILON ||
        grid_span_y <= FLOAT_EPSILON
    ) {
        return rain_shadow_grid;
    }

    rain_shadow_grid.resize(cell_count);
    float *rain_write = rain_shadow_grid.ptrw();
    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        rain_write[cell_index] = 0.0f;
    }

    if (column_scale <= FLOAT_EPSILON) {
        return rain_shadow_grid;
    }

    const float *height_read = eroded_height_grid.ptr();
    const float *moisture_read = moisture_grid.ptr();
    const int32_t *world_x_read = grid_world_x.ptr();
    const int32_t *world_y_read = grid_world_y.ptr();
    const float safe_precipitation_rate = std::max(0.0f, precipitation_rate);
    const float safe_lift_factor = std::max(0.0f, lift_factor);
    const float safe_evaporation_rate = std::clamp(evaporation_rate, 0.0f, 1.0f);
    const bool wrap_stabilization = std::abs(wind_direction.y) <= FLOAT_EPSILON && grid_width > 1;
    const Vector2 cross_direction(-wind_direction.y, wind_direction.x);

    struct ColumnEntry {
        int index = -1;
        double along = 0.0;
    };
    std::map<int, std::vector<ColumnEntry>> columns_by_key;

    auto get_world_center = [&](int cell_index) -> Vector2 {
        return Vector2(
            static_cast<float>(world_x_read[cell_index]) + (grid_span_x * 0.5f),
            static_cast<float>(world_y_read[cell_index]) + (grid_span_y * 0.5f)
        );
    };
    auto is_index_lexicographically_less = [&](int left_index, int right_index) -> bool {
        if (right_index < 0) {
            return true;
        }
        int left_x = 0;
        int left_y = 0;
        int right_x = 0;
        int right_y = 0;
        decode_index(left_index, grid_width, left_x, left_y);
        decode_index(right_index, grid_width, right_x, right_y);
        if (left_y != right_y) {
            return left_y < right_y;
        }
        return left_x < right_x;
    };

    for (int cell_index = 0; cell_index < cell_count; ++cell_index) {
        const Vector2 world_center = get_world_center(cell_index);
        const double cross_coord = static_cast<double>(world_center.dot(cross_direction));
        const double along_coord = static_cast<double>(world_center.dot(wind_direction));
        const int column_key = static_cast<int>(std::lround(cross_coord / static_cast<double>(column_scale)));
        columns_by_key[column_key].push_back({cell_index, along_coord});
    }

    auto recover_moisture = [&](float moisture_budget, float base_moisture) -> float {
        if (safe_evaporation_rate <= FLOAT_EPSILON) {
            return std::clamp(moisture_budget, 0.0f, 1.0f);
        }
        const float clamped_budget = std::clamp(moisture_budget, 0.0f, 1.0f);
        const float clamped_base = std::clamp(base_moisture, 0.0f, 1.0f);
        return std::clamp(
            clamped_budget + (clamped_base - clamped_budget) * safe_evaporation_rate,
            0.0f,
            1.0f
        );
    };
    auto compute_orographic_lift = [&](int previous_cell_index, int cell_index) -> float {
        if (previous_cell_index == cell_index) {
            return 0.0f;
        }
        const float height_gain = height_read[cell_index] - height_read[previous_cell_index];
        if (height_gain <= FLOAT_EPSILON || max_possible_gradient <= FLOAT_EPSILON) {
            return 0.0f;
        }
        const Vector2 previous_center = get_world_center(previous_cell_index);
        const Vector2 current_center = get_world_center(cell_index);
        float delta_x = current_center.x - previous_center.x;
        if (wrap_width_tiles > 0) {
            const float wrap_width = static_cast<float>(wrap_width_tiles);
            if (delta_x > wrap_width * 0.5f) {
                delta_x -= wrap_width;
            } else if (delta_x < -wrap_width * 0.5f) {
                delta_x += wrap_width;
            }
        }
        const float delta_y = current_center.y - previous_center.y;
        float along_distance = std::abs(delta_x * wind_direction.x + delta_y * wind_direction.y);
        if (along_distance <= FLOAT_EPSILON) {
            along_distance = std::sqrt(delta_x * delta_x + delta_y * delta_y);
        }
        if (along_distance <= FLOAT_EPSILON) {
            return 0.0f;
        }
        const float raw_gradient = height_gain / along_distance;
        return std::clamp(raw_gradient / max_possible_gradient, 0.0f, 1.0f);
    };

    for (auto &column_pair : columns_by_key) {
        std::vector<ColumnEntry> &entries = column_pair.second;
        std::sort(entries.begin(), entries.end(), [&](const ColumnEntry &left, const ColumnEntry &right) {
            if (std::abs(left.along - right.along) > FLOAT_EPSILON) {
                return left.along < right.along;
            }
            return is_index_lexicographically_less(left.index, right.index);
        });
        if (entries.empty()) {
            continue;
        }

        std::vector<int> column_cells;
        column_cells.reserve(entries.size());
        for (const ColumnEntry &entry : entries) {
            column_cells.push_back(entry.index);
        }

        int step_count = static_cast<int>(column_cells.size());
        int capture_start = 0;
        int previous_cell_index = column_cells.front();
        if (wrap_stabilization && column_cells.size() > 1U) {
            step_count *= 2;
            capture_start = static_cast<int>(column_cells.size());
            previous_cell_index = column_cells.back();
        }

        float moisture_budget = std::clamp(moisture_read[column_cells.front()], 0.0f, 1.0f);
        for (int step = 0; step < step_count; ++step) {
            const int column_index = step % static_cast<int>(column_cells.size());
            const int cell_index = column_cells[static_cast<size_t>(column_index)];
            const float orographic_lift = compute_orographic_lift(previous_cell_index, cell_index);
            const float precipitation = moisture_budget * safe_precipitation_rate * (1.0f + orographic_lift * safe_lift_factor);
            moisture_budget = std::max(0.0f, moisture_budget - precipitation);
            moisture_budget = recover_moisture(moisture_budget, moisture_read[cell_index]);
            if (step >= capture_start) {
                rain_write[cell_index] = std::clamp(moisture_budget, 0.0f, 1.0f);
            }
            previous_cell_index = cell_index;
        }
    }

    return rain_shadow_grid;
}

Dictionary WorldPrePassKernels::compute_river_extraction(
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
    const int32_t *lake_mask_read = lake_mask.ptr();
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
