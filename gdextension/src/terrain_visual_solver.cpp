#include "terrain_visual_solver.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

namespace {

constexpr int32_t PACKET_SCHEMA_VERSION = 1;
constexpr int32_t SOLVER_VERSION = 1;

constexpr uint8_t ZONE_EMPTY = 0;
constexpr uint8_t ZONE_TOP = 1;
constexpr uint8_t ZONE_EDGE = 2;
constexpr uint8_t ZONE_FACE = 3;
constexpr uint8_t ZONE_BACK = 4;

struct RecipePayload {
	StringName recipe_id = StringName();
	StringName surface_kind = StringName("rock");
	int32_t tile_size_px = 64;
	double rim_width_px = 6.0;
	double south_height_px = 64.0;
	double north_height_px = 0.0;
	double side_height_px = 0.0;
	double face_power = 1.0;
	double back_drop = 0.8;
	double normal_strength = 2.0;
};

struct EmptyTileGrid {
	int64_t width = 0;
	int64_t height = 0;
	std::vector<uint8_t> empty;
};

struct EmptyTileCandidate {
	int64_t x = 0;
	int64_t y = 0;
};

struct NearestBoundary {
	double distance_px = std::numeric_limits<double>::infinity();
	double normal_x = 0.0;
	double normal_y = 1.0;
};

double clamp01(double p_value) {
	return std::clamp(p_value, 0.0, 1.0);
}

int32_t checked_pixel_size(int64_t p_tiles, int32_t p_tile_size_px) {
	return static_cast<int32_t>(p_tiles * static_cast<int64_t>(p_tile_size_px));
}

bool is_solid_tile(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	int64_t p_x,
	int64_t p_y
) {
	if (p_x < 0 || p_y < 0 || p_x >= p_width_tiles || p_y >= p_height_tiles) {
		return false;
	}
	const int64_t index = p_y * p_width_tiles + p_x;
	return p_solid_mask[static_cast<int32_t>(index)] != 0;
}

StringName get_string_name(
	const Dictionary &p_payload,
	const char *p_key,
	const StringName &p_fallback
) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::STRING_NAME) {
		return static_cast<StringName>(value);
	}
	if (value.get_type() == Variant::STRING) {
		return StringName(static_cast<String>(value));
	}
	return p_fallback;
}

int32_t get_int(const Dictionary &p_payload, const char *p_key, int32_t p_fallback) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
		return static_cast<int32_t>(static_cast<int64_t>(value));
	}
	return p_fallback;
}

double get_double(const Dictionary &p_payload, const char *p_key, double p_fallback) {
	const Variant value = p_payload.get(p_key, p_fallback);
	if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
		return static_cast<double>(value);
	}
	return p_fallback;
}

RecipePayload unpack_recipe_payload(const Dictionary &p_payload) {
	RecipePayload recipe;
	recipe.recipe_id = get_string_name(p_payload, "recipe_id", StringName());
	recipe.surface_kind = get_string_name(p_payload, "surface_kind", StringName("rock"));
	recipe.tile_size_px = std::clamp(get_int(p_payload, "tile_size_px", 64), 1, 4096);
	recipe.rim_width_px = std::max(0.0, get_double(p_payload, "rim_width_px", 6.0));
	recipe.south_height_px = std::max(0.0, get_double(p_payload, "south_height_px", 64.0));
	recipe.north_height_px = std::max(0.0, get_double(p_payload, "north_height_px", 0.0));
	recipe.side_height_px = std::max(0.0, get_double(p_payload, "side_height_px", 0.0));
	recipe.face_power = std::clamp(get_double(p_payload, "face_power", 1.0), 0.1, 8.0);
	recipe.back_drop = std::clamp(get_double(p_payload, "back_drop", 0.8), 0.0, 1.0);
	recipe.normal_strength = std::max(0.0, get_double(p_payload, "normal_strength", 2.0));
	return recipe;
}

EmptyTileGrid build_empty_tile_grid(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles
) {
	EmptyTileGrid grid;
	grid.width = p_width_tiles + 2;
	grid.height = p_height_tiles + 2;
	grid.empty.resize(static_cast<size_t>(grid.width * grid.height), 1U);

	for (int64_t tile_y = -1; tile_y <= p_height_tiles; ++tile_y) {
		for (int64_t tile_x = -1; tile_x <= p_width_tiles; ++tile_x) {
			const int64_t grid_x = tile_x + 1;
			const int64_t grid_y = tile_y + 1;
			const bool empty = !is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, tile_x, tile_y);
			grid.empty[static_cast<size_t>(grid_y * grid.width + grid_x)] = empty ? 1U : 0U;
		}
	}

	return grid;
}

bool is_empty_tile(
	const EmptyTileGrid &p_grid,
	int64_t p_tile_x,
	int64_t p_tile_y
) {
	const int64_t grid_x = p_tile_x + 1;
	const int64_t grid_y = p_tile_y + 1;
	if (grid_x < 0 || grid_y < 0 || grid_x >= p_grid.width || grid_y >= p_grid.height) {
		return true;
	}
	return p_grid.empty[static_cast<size_t>(grid_y * p_grid.width + grid_x)] != 0U;
}

double max_relevant_boundary_distance_px(const RecipePayload &p_recipe) {
	return std::max(
		std::max(p_recipe.rim_width_px, p_recipe.south_height_px),
		std::max(p_recipe.north_height_px, p_recipe.side_height_px)
	);
}

int64_t resolve_search_radius_tiles(double p_max_relevant_distance_px, int32_t p_tile_size_px) {
	if (p_max_relevant_distance_px <= 0.0) {
		return 0;
	}
	return std::max<int64_t>(
		1,
		static_cast<int64_t>(std::ceil(p_max_relevant_distance_px / static_cast<double>(p_tile_size_px))) + 1
	);
}

std::vector<std::vector<EmptyTileCandidate>> build_empty_candidates_by_tile(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const EmptyTileGrid &p_empty_grid,
	int64_t p_search_radius_tiles
) {
	std::vector<std::vector<EmptyTileCandidate>> candidates_by_tile;
	candidates_by_tile.resize(static_cast<size_t>(p_width_tiles * p_height_tiles));
	if (p_search_radius_tiles <= 0) {
		return candidates_by_tile;
	}

	for (int64_t tile_y = 0; tile_y < p_height_tiles; ++tile_y) {
		for (int64_t tile_x = 0; tile_x < p_width_tiles; ++tile_x) {
			if (!is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, tile_x, tile_y)) {
				continue;
			}
			std::vector<EmptyTileCandidate> &candidates =
					candidates_by_tile[static_cast<size_t>(tile_y * p_width_tiles + tile_x)];
			for (int64_t candidate_y = tile_y - p_search_radius_tiles; candidate_y <= tile_y + p_search_radius_tiles; ++candidate_y) {
				for (int64_t candidate_x = tile_x - p_search_radius_tiles; candidate_x <= tile_x + p_search_radius_tiles; ++candidate_x) {
					if (!is_empty_tile(p_empty_grid, candidate_x, candidate_y)) {
						continue;
					}
					candidates.push_back(EmptyTileCandidate{ candidate_x, candidate_y });
				}
			}
		}
	}

	return candidates_by_tile;
}

NearestBoundary find_nearest_empty_boundary_limited(
	const std::vector<EmptyTileCandidate> &p_candidates,
	int32_t p_tile_size_px,
	double p_max_relevant_distance_px,
	double p_x,
	double p_y
) {
	NearestBoundary nearest;
	if (p_max_relevant_distance_px <= 0.0) {
		return nearest;
	}

	const double max_distance_with_margin = p_max_relevant_distance_px + 1.0;
	const double max_distance_sq = max_distance_with_margin * max_distance_with_margin;
	double nearest_distance_sq = std::numeric_limits<double>::infinity();

	for (const EmptyTileCandidate &candidate : p_candidates) {
		const double min_x = static_cast<double>(candidate.x * p_tile_size_px);
		const double min_y = static_cast<double>(candidate.y * p_tile_size_px);
		const double max_x = min_x + static_cast<double>(p_tile_size_px);
		const double max_y = min_y + static_cast<double>(p_tile_size_px);
		const double closest_x = std::clamp(p_x, min_x, max_x);
		const double closest_y = std::clamp(p_y, min_y, max_y);
		const double delta_x = closest_x - p_x;
		const double delta_y = closest_y - p_y;
		const double distance_sq = delta_x * delta_x + delta_y * delta_y;
		if (distance_sq > max_distance_sq || distance_sq >= nearest_distance_sq) {
			continue;
		}

		nearest_distance_sq = distance_sq;
		const double distance = std::sqrt(distance_sq);
		nearest.distance_px = distance;
		if (distance > 0.0001) {
			nearest.normal_x = delta_x / distance;
			nearest.normal_y = delta_y / distance;
		}
	}

	return nearest;
}

uint8_t classify_zone(const RecipePayload &p_recipe, const NearestBoundary &p_boundary) {
	if (p_boundary.normal_y > 0.45 &&
			p_recipe.south_height_px > 0.0 &&
			p_boundary.distance_px <= p_recipe.south_height_px) {
		return ZONE_FACE;
	}
	if (std::abs(p_boundary.normal_x) > 0.45 &&
			p_recipe.side_height_px > 0.0 &&
			p_boundary.distance_px <= p_recipe.side_height_px) {
		return ZONE_FACE;
	}
	if (p_boundary.normal_y < -0.45 &&
			p_recipe.north_height_px > 0.0 &&
			p_boundary.distance_px <= p_recipe.north_height_px) {
		return ZONE_BACK;
	}
	if (p_recipe.rim_width_px > 0.0 && p_boundary.distance_px <= p_recipe.rim_width_px) {
		return ZONE_EDGE;
	}
	return ZONE_TOP;
}

double directional_depth_px(const RecipePayload &p_recipe, const NearestBoundary &p_boundary) {
	if (p_boundary.normal_y > 0.45) {
		return std::max(0.0001, p_recipe.south_height_px);
	}
	if (std::abs(p_boundary.normal_x) > 0.45) {
		return std::max(0.0001, p_recipe.side_height_px);
	}
	if (p_boundary.normal_y < -0.45) {
		return std::max(0.0001, p_recipe.north_height_px);
	}
	return std::max(0.0001, p_recipe.rim_width_px);
}

double solve_height_norm(
	const RecipePayload &p_recipe,
	uint8_t p_zone,
	const NearestBoundary &p_boundary
) {
	if (p_zone == ZONE_EMPTY) {
		return 0.0;
	}
	if (p_zone == ZONE_TOP) {
		return 1.0;
	}
	if (p_zone == ZONE_EDGE) {
		const double edge_t = p_recipe.rim_width_px > 0.0 ?
				clamp01(p_boundary.distance_px / p_recipe.rim_width_px) :
				1.0;
		return 0.92 + edge_t * 0.08;
	}
	if (p_zone == ZONE_BACK) {
		const double back_t = p_recipe.north_height_px > 0.0 ?
				clamp01(p_boundary.distance_px / p_recipe.north_height_px) :
				1.0;
		return p_recipe.back_drop * back_t;
	}

	const double face_depth = directional_depth_px(p_recipe, p_boundary);
	const double face_t = std::pow(clamp01(p_boundary.distance_px / face_depth), p_recipe.face_power);
	return face_t;
}

void write_q16(uint8_t *r_bytes, int32_t p_pixel_index, double p_value) {
	const uint16_t q16 = static_cast<uint16_t>(
		std::round(clamp01(p_value) * static_cast<double>(std::numeric_limits<uint16_t>::max()))
	);
	const int32_t offset = p_pixel_index * 2;
	r_bytes[offset] = q16 & 0xff;
	r_bytes[offset + 1] = (q16 >> 8) & 0xff;
}

void write_normal_rgba8(
	uint8_t *r_bytes,
	int32_t p_pixel_index,
	double p_x,
	double p_y,
	double p_z
) {
	const double length = std::sqrt(p_x * p_x + p_y * p_y + p_z * p_z);
	const double safe_length = length > 0.0001 ? length : 1.0;
	const double nx = p_x / safe_length;
	const double ny = p_y / safe_length;
	const double nz = p_z / safe_length;
	const int32_t offset = p_pixel_index * 4;
	r_bytes[offset] = static_cast<uint8_t>(std::round((nx * 0.5 + 0.5) * 255.0));
	r_bytes[offset + 1] = static_cast<uint8_t>(std::round((ny * 0.5 + 0.5) * 255.0));
	r_bytes[offset + 2] = static_cast<uint8_t>(std::round((nz * 0.5 + 0.5) * 255.0));
	r_bytes[offset + 3] = 255;
}

double sample_height(
	const std::vector<double> &p_heights,
	int32_t p_width,
	int32_t p_height,
	int32_t p_x,
	int32_t p_y
) {
	const int32_t clamped_x = std::clamp(p_x, 0, p_width - 1);
	const int32_t clamped_y = std::clamp(p_y, 0, p_height - 1);
	return p_heights[static_cast<size_t>(clamped_y * p_width + clamped_x)];
}

void write_material_uv(
	uint8_t *r_u,
	uint8_t *r_v,
	int32_t p_pixel_index,
	double p_x,
	double p_y,
	const RecipePayload &p_recipe,
	uint8_t p_zone,
	const NearestBoundary &p_boundary
) {
	const double tile_size = static_cast<double>(p_recipe.tile_size_px);
	double u = std::fmod(std::max(0.0, p_x), tile_size) / tile_size;
	double v = std::fmod(std::max(0.0, p_y), tile_size) / tile_size;

	if (p_zone == ZONE_FACE || p_zone == ZONE_BACK || p_zone == ZONE_EDGE) {
		const double tangent_x = -p_boundary.normal_y;
		const double tangent_y = p_boundary.normal_x;
		const double projected = p_x * tangent_x + p_y * tangent_y;
		u = std::fmod(std::abs(projected), tile_size) / tile_size;
		v = clamp01(p_boundary.distance_px / directional_depth_px(p_recipe, p_boundary));
	}

	write_q16(r_u, p_pixel_index, u);
	write_q16(r_v, p_pixel_index, v);
}

void increment_zone_counter(
	uint8_t p_zone,
	int64_t &r_top_pixels,
	int64_t &r_edge_pixels,
	int64_t &r_face_pixels,
	int64_t &r_back_pixels,
	int64_t &r_empty_pixels
) {
	switch (p_zone) {
		case ZONE_TOP:
			++r_top_pixels;
			break;
		case ZONE_EDGE:
			++r_edge_pixels;
			break;
		case ZONE_FACE:
			++r_face_pixels;
			break;
		case ZONE_BACK:
			++r_back_pixels;
			break;
		case ZONE_EMPTY:
		default:
			++r_empty_pixels;
			break;
	}
}

Dictionary build_packet_from_mask(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_input_world_origin_tile,
	Vector2i p_chunk_coord,
	int64_t p_seed,
	Rect2i p_output_rect_tiles,
	const char *p_entrypoint_name
) {
	Dictionary packet;
	const String entrypoint = String("TerrainVisualSolver.") + p_entrypoint_name;
	ERR_FAIL_COND_V_MSG(
		p_width_tiles < 0 || p_height_tiles < 0,
		packet,
		entrypoint + String(" received a negative mask dimension.")
	);

	const int64_t expected_mask_size = p_width_tiles * p_height_tiles;
	ERR_FAIL_COND_V_MSG(
		expected_mask_size != p_solid_mask.size(),
		packet,
		entrypoint + String(" received a mask size that does not match width * height.")
	);

	const Vector2i output_pos = p_output_rect_tiles.position;
	const Vector2i output_size = p_output_rect_tiles.size;
	const Vector2i output_end = output_pos + output_size;
	ERR_FAIL_COND_V_MSG(
		output_pos.x < 0 ||
			output_pos.y < 0 ||
			output_size.x < 0 ||
			output_size.y < 0 ||
			output_end.x > p_width_tiles ||
			output_end.y > p_height_tiles,
		packet,
		entrypoint + String(" received an output rect outside the input mask.")
	);

	const RecipePayload recipe = unpack_recipe_payload(p_recipe_payload);
	const int32_t pixel_width = checked_pixel_size(output_size.x, recipe.tile_size_px);
	const int32_t pixel_height = checked_pixel_size(output_size.y, recipe.tile_size_px);
	const int64_t pixel_count_64 = static_cast<int64_t>(pixel_width) * static_cast<int64_t>(pixel_height);
	ERR_FAIL_COND_V_MSG(
		pixel_count_64 > std::numeric_limits<int32_t>::max(),
		packet,
		entrypoint + String(" received an output rect that is too large for one packet.")
	);

	const int32_t pixel_count = static_cast<int32_t>(pixel_count_64);
	const EmptyTileGrid empty_grid = build_empty_tile_grid(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles
	);
	const double max_relevant_distance_px = max_relevant_boundary_distance_px(recipe);
	const int64_t search_radius_tiles = resolve_search_radius_tiles(
		max_relevant_distance_px,
		recipe.tile_size_px
	);
	const std::vector<std::vector<EmptyTileCandidate>> candidates_by_tile =
			build_empty_candidates_by_tile(
				p_solid_mask,
				p_width_tiles,
				p_height_tiles,
				empty_grid,
				search_radius_tiles
			);

	PackedByteArray zone_ids;
	PackedByteArray coverage_top;
	PackedByteArray coverage_edge;
	PackedByteArray coverage_face;
	PackedByteArray coverage_back;
	PackedByteArray height_q16;
	PackedByteArray normal_rgba8;
	PackedByteArray material_u_q16;
	PackedByteArray material_v_q16;

	zone_ids.resize(pixel_count);
	coverage_top.resize(pixel_count);
	coverage_edge.resize(pixel_count);
	coverage_face.resize(pixel_count);
	coverage_back.resize(pixel_count);
	height_q16.resize(pixel_count * 2);
	normal_rgba8.resize(pixel_count * 4);
	material_u_q16.resize(pixel_count * 2);
	material_v_q16.resize(pixel_count * 2);

	uint8_t *zone_ids_w = zone_ids.ptrw();
	uint8_t *coverage_top_w = coverage_top.ptrw();
	uint8_t *coverage_edge_w = coverage_edge.ptrw();
	uint8_t *coverage_face_w = coverage_face.ptrw();
	uint8_t *coverage_back_w = coverage_back.ptrw();
	uint8_t *height_q16_w = height_q16.ptrw();
	uint8_t *normal_rgba8_w = normal_rgba8.ptrw();
	uint8_t *material_u_q16_w = material_u_q16.ptrw();
	uint8_t *material_v_q16_w = material_v_q16.ptrw();

	std::vector<double> heights;
	heights.resize(static_cast<size_t>(pixel_count), 0.0);

	int64_t solid_pixels = 0;
	int64_t top_pixels = 0;
	int64_t edge_pixels = 0;
	int64_t face_pixels = 0;
	int64_t back_pixels = 0;
	int64_t empty_pixels = 0;

	const int64_t output_origin_px_x = static_cast<int64_t>(output_pos.x) * recipe.tile_size_px;
	const int64_t output_origin_px_y = static_cast<int64_t>(output_pos.y) * recipe.tile_size_px;

	for (int32_t y = 0; y < pixel_height; ++y) {
		for (int32_t x = 0; x < pixel_width; ++x) {
			const int32_t pixel_index = y * pixel_width + x;
			const int64_t input_x = output_origin_px_x + x;
			const int64_t input_y = output_origin_px_y + y;
			const int64_t tile_x = input_x / recipe.tile_size_px;
			const int64_t tile_y = input_y / recipe.tile_size_px;
			const bool solid = is_solid_tile(p_solid_mask, p_width_tiles, p_height_tiles, tile_x, tile_y);
			uint8_t zone = ZONE_EMPTY;
			NearestBoundary boundary;
			const double sample_x = static_cast<double>(input_x) + 0.5;
			const double sample_y = static_cast<double>(input_y) + 0.5;

			if (solid) {
				++solid_pixels;
				const std::vector<EmptyTileCandidate> &candidates =
						candidates_by_tile[static_cast<size_t>(tile_y * p_width_tiles + tile_x)];
				boundary = find_nearest_empty_boundary_limited(
					candidates,
					recipe.tile_size_px,
					max_relevant_distance_px,
					sample_x,
					sample_y
				);
				zone = classify_zone(recipe, boundary);
			}

			const double height = solve_height_norm(recipe, zone, boundary);
			heights[static_cast<size_t>(pixel_index)] = height;
			zone_ids_w[pixel_index] = zone;
			coverage_top_w[pixel_index] = zone == ZONE_TOP ? 255 : 0;
			coverage_edge_w[pixel_index] = zone == ZONE_EDGE ? 255 : 0;
			coverage_face_w[pixel_index] = zone == ZONE_FACE ? 255 : 0;
			coverage_back_w[pixel_index] = zone == ZONE_BACK ? 255 : 0;
			write_q16(height_q16_w, pixel_index, height);
			write_material_uv(
				material_u_q16_w,
				material_v_q16_w,
				pixel_index,
				sample_x,
				sample_y,
				recipe,
				zone,
				boundary
			);
			increment_zone_counter(
				zone,
				top_pixels,
				edge_pixels,
				face_pixels,
				back_pixels,
				empty_pixels
			);
		}
	}

	for (int32_t y = 0; y < pixel_height; ++y) {
		for (int32_t x = 0; x < pixel_width; ++x) {
			const int32_t pixel_index = y * pixel_width + x;
			const double dx = (
				sample_height(heights, pixel_width, pixel_height, x + 1, y) -
				sample_height(heights, pixel_width, pixel_height, x - 1, y)
			) * 0.5;
			const double dy = (
				sample_height(heights, pixel_width, pixel_height, x, y + 1) -
				sample_height(heights, pixel_width, pixel_height, x, y - 1)
			) * 0.5;
			write_normal_rgba8(
				normal_rgba8_w,
				pixel_index,
				-dx * recipe.normal_strength,
				-dy * recipe.normal_strength,
				1.0
			);
		}
	}

	Dictionary debug_counters;
	debug_counters["solver_version"] = SOLVER_VERSION;
	debug_counters["seed"] = p_seed;
	debug_counters["solid_pixels"] = solid_pixels;
	debug_counters["empty_pixels"] = empty_pixels;
	debug_counters["top_pixels"] = top_pixels;
	debug_counters["edge_pixels"] = edge_pixels;
	debug_counters["face_pixels"] = face_pixels;
	debug_counters["back_pixels"] = back_pixels;
	debug_counters["input_width_tiles"] = static_cast<int32_t>(p_width_tiles);
	debug_counters["input_height_tiles"] = static_cast<int32_t>(p_height_tiles);
	debug_counters["output_width_tiles"] = output_size.x;
	debug_counters["output_height_tiles"] = output_size.y;
	debug_counters["outline_polyline_count"] = 0;

	packet["schema_version"] = PACKET_SCHEMA_VERSION;
	packet["recipe_id"] = recipe.recipe_id;
	packet["surface_kind"] = recipe.surface_kind;
	packet["world_origin_tile"] = p_input_world_origin_tile + output_pos;
	packet["chunk_coord"] = p_chunk_coord;
	packet["dirty_rect_tiles"] = Rect2i(Vector2i(0, 0), output_size);
	packet["dirty_rect_px"] = Rect2i(Vector2i(0, 0), Vector2i(pixel_width, pixel_height));
	packet["tile_size_px"] = recipe.tile_size_px;
	packet["pixel_width"] = pixel_width;
	packet["pixel_height"] = pixel_height;
	packet["zone_ids"] = zone_ids;
	packet["coverage_top"] = coverage_top;
	packet["coverage_edge"] = coverage_edge;
	packet["coverage_face"] = coverage_face;
	packet["coverage_back"] = coverage_back;
	packet["height_q16"] = height_q16;
	packet["normal_rgba8"] = normal_rgba8;
	packet["material_u_q16"] = material_u_q16;
	packet["material_v_q16"] = material_v_q16;
	packet["outline_polylines"] = Array();
	packet["debug_counters"] = debug_counters;
	return packet;
}

} // namespace

void TerrainVisualSolver::_bind_methods() {
	ClassDB::bind_method(
		D_METHOD(
			"build_editor_preview_packet",
			"solid_mask",
			"width_tiles",
			"height_tiles",
			"recipe_payload",
			"preview_origin_tile",
			"seed"
		),
		&TerrainVisualSolver::build_editor_preview_packet
	);
	ClassDB::bind_method(
		D_METHOD(
			"build_chunk_visual_packet",
			"solid_mask",
			"width_tiles",
			"height_tiles",
			"recipe_payload",
			"world_origin_tile",
			"chunk_coord",
			"seed"
		),
		&TerrainVisualSolver::build_chunk_visual_packet
	);
	ClassDB::bind_method(
		D_METHOD(
			"build_chunk_visual_packet_with_halo",
			"solid_mask",
			"width_tiles",
			"height_tiles",
			"recipe_payload",
			"input_world_origin_tile",
			"chunk_coord",
			"seed",
			"output_rect_tiles"
		),
		&TerrainVisualSolver::build_chunk_visual_packet_with_halo
	);
}

Dictionary TerrainVisualSolver::build_editor_preview_packet(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_preview_origin_tile,
	int64_t p_seed
) const {
	return build_packet_from_mask(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles,
		p_recipe_payload,
		p_preview_origin_tile,
		Vector2i(0, 0),
		p_seed,
		Rect2i(
			Vector2i(0, 0),
			Vector2i(static_cast<int32_t>(p_width_tiles), static_cast<int32_t>(p_height_tiles))
		),
		"build_editor_preview_packet"
	);
}

Dictionary TerrainVisualSolver::build_chunk_visual_packet(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_world_origin_tile,
	Vector2i p_chunk_coord,
	int64_t p_seed
) const {
	Dictionary packet = build_editor_preview_packet(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles,
		p_recipe_payload,
		p_world_origin_tile,
		p_seed
	);
	if (packet.is_empty()) {
		return packet;
	}
	packet["world_origin_tile"] = p_world_origin_tile;
	packet["chunk_coord"] = p_chunk_coord;
	return packet;
}

Dictionary TerrainVisualSolver::build_chunk_visual_packet_with_halo(
	const PackedByteArray &p_solid_mask,
	int64_t p_width_tiles,
	int64_t p_height_tiles,
	const Dictionary &p_recipe_payload,
	Vector2i p_input_world_origin_tile,
	Vector2i p_chunk_coord,
	int64_t p_seed,
	Rect2i p_output_rect_tiles
) const {
	return build_packet_from_mask(
		p_solid_mask,
		p_width_tiles,
		p_height_tiles,
		p_recipe_payload,
		p_input_world_origin_tile,
		p_chunk_coord,
		p_seed,
		p_output_rect_tiles,
		"build_chunk_visual_packet_with_halo"
	);
}
