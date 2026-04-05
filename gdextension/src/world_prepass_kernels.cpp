#include "world_prepass_kernels.h"

#include <algorithm>

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
