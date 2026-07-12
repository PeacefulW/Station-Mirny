#include "mountain_contour.h"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <vector>

#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace mountain_contour {
namespace {

struct ContourPoint {
	float x = 0.0f;
	float y = 0.0f;
};

ContourPoint midpoint(ContourPoint p_a, ContourPoint p_b) {
	return {
		(p_a.x + p_b.x) * 0.5f,
		(p_a.y + p_b.y) * 0.5f,
	};
}

float clamp_coord(float p_value, float p_max) {
	return std::max(0.0f, std::min(p_value, p_max));
}

bool read_solid(const godot::PackedByteArray &p_solid_halo, int32_t p_side, int32_t p_x, int32_t p_y) {
	if (p_x < 0 || p_y < 0 || p_x >= p_side || p_y >= p_side) {
		return false;
	}
	const int32_t index = p_y * p_side + p_x;
	return index >= 0 && index < p_solid_halo.size() && p_solid_halo[index] != 0;
}

float lerp_float(float p_a, float p_b, float p_t) {
	return p_a + (p_b - p_a) * p_t;
}

float smooth_float(float p_t) {
	const float t = std::max(0.0f, std::min(1.0f, p_t));
	return t * t * (3.0f - 2.0f * t);
}

float sample_grid_bilinear(const std::vector<float> &p_values, int32_t p_width, int32_t p_height, float p_x, float p_y) {
	const float x = std::max(0.0f, std::min(p_x, static_cast<float>(p_width - 1)));
	const float y = std::max(0.0f, std::min(p_y, static_cast<float>(p_height - 1)));
	const int32_t x0 = static_cast<int32_t>(std::floor(x));
	const int32_t y0 = static_cast<int32_t>(std::floor(y));
	const int32_t x1 = std::min(p_width - 1, x0 + 1);
	const int32_t y1 = std::min(p_height - 1, y0 + 1);
	const float tx = x - static_cast<float>(x0);
	const float ty = y - static_cast<float>(y0);
	const float a = p_values[static_cast<size_t>(y0 * p_width + x0)];
	const float b = p_values[static_cast<size_t>(y0 * p_width + x1)];
	const float c = p_values[static_cast<size_t>(y1 * p_width + x0)];
	const float d = p_values[static_cast<size_t>(y1 * p_width + x1)];
	return lerp_float(lerp_float(a, b, tx), lerp_float(c, d, tx), ty);
}

float hash_float(int32_t p_x, int32_t p_y) {
	uint32_t value = static_cast<uint32_t>(p_x) * 0x8da6b343U;
	value ^= static_cast<uint32_t>(p_y) * 0xd8163841U;
	value ^= value >> 13U;
	value *= 0x6c50b47cU;
	value ^= value >> 16U;
	return static_cast<float>(value & 0x00ffffffU) / static_cast<float>(0x00ffffffU);
}

float value_noise(float p_x, float p_y) {
	const int32_t ix = static_cast<int32_t>(std::floor(p_x));
	const int32_t iy = static_cast<int32_t>(std::floor(p_y));
	const float fx = p_x - static_cast<float>(ix);
	const float fy = p_y - static_cast<float>(iy);
	const float sx = smooth_float(fx);
	const float sy = smooth_float(fy);
	const float a = hash_float(ix, iy);
	const float b = hash_float(ix + 1, iy);
	const float c = hash_float(ix, iy + 1);
	const float d = hash_float(ix + 1, iy + 1);
	return lerp_float(
		lerp_float(a, b, sx),
		lerp_float(c, d, sx),
		sy
	);
}

float fbm_noise(float p_x, float p_y) {
	float value = 0.0f;
	float amplitude = 0.55f;
	float frequency = 1.0f;
	float total = 0.0f;
	for (int32_t octave = 0; octave < 4; ++octave) {
		value += value_noise(p_x * frequency, p_y * frequency) * amplitude;
		total += amplitude;
		amplitude *= 0.5f;
		frequency *= 2.03f;
	}
	return total > 0.0f ? value / total : 0.5f;
}

float rounded_box_sdf(float p_x, float p_y, float p_half_extent, float p_radius) {
	const float qx = std::fabs(p_x) - p_half_extent + p_radius;
	const float qy = std::fabs(p_y) - p_half_extent + p_radius;
	const float outside_x = std::max(qx, 0.0f);
	const float outside_y = std::max(qy, 0.0f);
	const float outside = std::sqrt(outside_x * outside_x + outside_y * outside_y);
	const float inside = std::min(std::max(qx, qy), 0.0f);
	return outside + inside - p_radius;
}

// Replays the pre-M7 local top-mask patch in the native worker. Each mined
// tile contributes one rounded signed-distance clear; overlapping clears use
// the former Image-mask multiplication rule. Keep this in the worker so
// interactive mining does not resume CPU texture composition.
float legacy_organic_dig_visual_opacity(
	const godot::PackedByteArray &p_dug_halo,
	int32_t p_halo_side,
	int32_t p_pixel_x,
	int32_t p_pixel_y,
	int32_t p_pixels_per_tile,
	int32_t p_tile_size_px,
	float p_step_px,
	double p_origin_world_x,
	double p_origin_world_y
) {
	const int32_t padding_steps = std::max(1, static_cast<int32_t>(std::ceil(2.0f / p_step_px)));
	const float feather_px = std::max(p_step_px * 2.0f, 10.0f);
	const float half_extent = static_cast<float>(p_tile_size_px) * 0.5f + feather_px * 0.45f;
	const float radius = half_extent * 0.46f;
	const int32_t center_tile_x = p_pixel_x / p_pixels_per_tile;
	const int32_t center_tile_y = p_pixel_y / p_pixels_per_tile;
	const float world_x = static_cast<float>(p_origin_world_x) + (static_cast<float>(p_pixel_x) + 0.5f) * p_step_px;
	const float world_y = static_cast<float>(p_origin_world_y) + (static_cast<float>(p_pixel_y) + 0.5f) * p_step_px;
	float opacity = 1.0f;

	for (int32_t tile_y = std::max(0, center_tile_y - 1); tile_y <= std::min(p_halo_side - 1, center_tile_y + 1); ++tile_y) {
		for (int32_t tile_x = std::max(0, center_tile_x - 1); tile_x <= std::min(p_halo_side - 1, center_tile_x + 1); ++tile_x) {
			if (!read_solid(p_dug_halo, p_halo_side, tile_x, tile_y)) {
				continue;
			}
			const int32_t min_x = tile_x * p_pixels_per_tile - padding_steps;
			const int32_t min_y = tile_y * p_pixels_per_tile - padding_steps;
			const int32_t max_x = (tile_x + 1) * p_pixels_per_tile + padding_steps;
			const int32_t max_y = (tile_y + 1) * p_pixels_per_tile + padding_steps;
			if (p_pixel_x < min_x || p_pixel_x > max_x || p_pixel_y < min_y || p_pixel_y > max_y) {
				continue;
			}
			const float tile_center_x = static_cast<float>(p_origin_world_x)
				+ (static_cast<float>(tile_x) + 0.5f) * static_cast<float>(p_tile_size_px);
			const float tile_center_y = static_cast<float>(p_origin_world_y)
				+ (static_cast<float>(tile_y) + 0.5f) * static_cast<float>(p_tile_size_px);
			const float sdf = rounded_box_sdf(world_x - tile_center_x, world_y - tile_center_y, half_extent, radius);
			const float clear_strength = sdf <= -feather_px
				? 1.0f
				: (sdf >= feather_px ? 0.0f : 1.0f - smooth_float((sdf + feather_px) / (feather_px * 2.0f)));
			opacity *= 1.0f - clear_strength;
		}
	}
	return std::max(0.0f, std::min(1.0f, opacity));
}

ContourPoint sample_point(int32_t p_x, int32_t p_y, int32_t p_tile_size_px) {
	const float tile_size = static_cast<float>(p_tile_size_px);
	return {
		(static_cast<float>(p_x) - 0.5f) * tile_size,
		(static_cast<float>(p_y) - 0.5f) * tile_size,
	};
}

void append_polygon(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	std::initializer_list<ContourPoint> p_points,
	float p_chunk_px
) {
	if (p_points.size() < 3) {
		return;
	}
	const int32_t base_index = r_vertices.size();
	for (const ContourPoint &point : p_points) {
		r_vertices.append(godot::Vector2(
			clamp_coord(point.x, p_chunk_px),
			clamp_coord(point.y, p_chunk_px)
		));
	}
	for (int32_t fan_index = 1; fan_index < static_cast<int32_t>(p_points.size()) - 1; ++fan_index) {
		r_indices.append(base_index);
		r_indices.append(base_index + fan_index);
		r_indices.append(base_index + fan_index + 1);
	}
}

void append_case_mesh(
	godot::PackedVector2Array &r_vertices,
	godot::PackedInt32Array &r_indices,
	int32_t p_case_code,
	ContourPoint p_tl,
	ContourPoint p_tr,
	ContourPoint p_br,
	ContourPoint p_bl,
	float p_chunk_px
) {
	const ContourPoint top = midpoint(p_tl, p_tr);
	const ContourPoint right = midpoint(p_tr, p_br);
	const ContourPoint bottom = midpoint(p_bl, p_br);
	const ContourPoint left = midpoint(p_tl, p_bl);

	switch (p_case_code) {
		case 0:
			return;
		case 1:
			append_polygon(r_vertices, r_indices, { p_tl, top, left }, p_chunk_px);
			return;
		case 2:
			append_polygon(r_vertices, r_indices, { p_tr, right, top }, p_chunk_px);
			return;
		case 3:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, right, left }, p_chunk_px);
			return;
		case 4:
			append_polygon(r_vertices, r_indices, { p_br, bottom, right }, p_chunk_px);
			return;
		case 5:
			append_polygon(r_vertices, r_indices, { p_tl, top, left }, p_chunk_px);
			append_polygon(r_vertices, r_indices, { p_br, bottom, right }, p_chunk_px);
			return;
		case 6:
			append_polygon(r_vertices, r_indices, { p_tr, p_br, bottom, top }, p_chunk_px);
			return;
		case 7:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, p_br, bottom, left }, p_chunk_px);
			return;
		case 8:
			append_polygon(r_vertices, r_indices, { p_bl, left, bottom }, p_chunk_px);
			return;
		case 9:
			append_polygon(r_vertices, r_indices, { p_tl, top, bottom, p_bl }, p_chunk_px);
			return;
		case 10:
			append_polygon(r_vertices, r_indices, { p_tr, right, top }, p_chunk_px);
			append_polygon(r_vertices, r_indices, { p_bl, left, bottom }, p_chunk_px);
			return;
		case 11:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, right, bottom, p_bl }, p_chunk_px);
			return;
		case 12:
			append_polygon(r_vertices, r_indices, { left, right, p_br, p_bl }, p_chunk_px);
			return;
		case 13:
			append_polygon(r_vertices, r_indices, { p_tl, top, right, p_br, p_bl }, p_chunk_px);
			return;
		case 14:
			append_polygon(r_vertices, r_indices, { top, p_tr, p_br, p_bl, left }, p_chunk_px);
			return;
		case 15:
			append_polygon(r_vertices, r_indices, { p_tl, p_tr, p_br, p_bl }, p_chunk_px);
			return;
		default:
			return;
	}
}

} // namespace

godot::Dictionary build_debug_mesh(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px
) {
	godot::PackedVector2Array vertices;
	godot::PackedInt32Array indices;
	godot::Dictionary result;
	result["vertices"] = vertices;
	result["indices"] = indices;
	result["solid_sample_count"] = 0;
	result["halo_side"] = 0;

	if (p_chunk_size <= 0 || p_tile_size_px <= 0) {
		return result;
	}
	const int32_t halo_side = p_chunk_size + 2;
	if (p_solid_halo.size() != halo_side * halo_side) {
		return result;
	}

	int32_t solid_sample_count = 0;
	for (int32_t y = 1; y <= p_chunk_size; ++y) {
		for (int32_t x = 1; x <= p_chunk_size; ++x) {
			if (read_solid(p_solid_halo, halo_side, x, y)) {
				++solid_sample_count;
			}
		}
	}

	const float chunk_px = static_cast<float>(p_chunk_size * p_tile_size_px);
	for (int32_t y = 0; y < halo_side - 1; ++y) {
		for (int32_t x = 0; x < halo_side - 1; ++x) {
			const bool tl_solid = read_solid(p_solid_halo, halo_side, x, y);
			const bool tr_solid = read_solid(p_solid_halo, halo_side, x + 1, y);
			const bool br_solid = read_solid(p_solid_halo, halo_side, x + 1, y + 1);
			const bool bl_solid = read_solid(p_solid_halo, halo_side, x, y + 1);
			const int32_t case_code =
					(tl_solid ? 1 : 0) |
					(tr_solid ? 2 : 0) |
					(br_solid ? 4 : 0) |
					(bl_solid ? 8 : 0);
			if (case_code == 0) {
				continue;
			}
			append_case_mesh(
				vertices,
				indices,
				case_code,
				sample_point(x, y, p_tile_size_px),
				sample_point(x + 1, y, p_tile_size_px),
				sample_point(x + 1, y + 1, p_tile_size_px),
				sample_point(x, y + 1, p_tile_size_px),
				chunk_px
			);
		}
	}

	result["vertices"] = vertices;
	result["indices"] = indices;
	result["solid_sample_count"] = solid_sample_count;
	result["halo_side"] = halo_side;
	return result;
}

godot::Dictionary build_halo_mask(
	const godot::PackedByteArray &p_solid_halo,
	int32_t p_chunk_size,
	int32_t p_tile_size_px,
	int32_t p_pixels_per_tile,
	double p_origin_world_x,
	double p_origin_world_y,
	const godot::PackedByteArray &p_dug_halo
) {
	godot::Dictionary result;
	result["mask"] = godot::PackedByteArray();
	result["physical_mouth_aperture_mask"] = godot::PackedByteArray();
	result["width"] = 0;
	result["height"] = 0;
	result["step_px"] = 0.0;
	result["solid_sample_count"] = 0;
	result["halo_side"] = 0;

	if (p_chunk_size <= 0 || p_tile_size_px <= 0) {
		return result;
	}
	const int32_t halo_side = static_cast<int32_t>(std::lround(std::sqrt(static_cast<double>(p_solid_halo.size()))));
	if (p_solid_halo.size() != halo_side * halo_side) {
		return result;
	}
	const bool dual_mask_requested = !p_dug_halo.is_empty();
	if (dual_mask_requested && p_dug_halo.size() != p_solid_halo.size()) {
		return result;
	}
	const int32_t halo_margin = halo_side - p_chunk_size;
	if (halo_margin < 2 || (halo_margin % 2) != 0) {
		return result;
	}
	const int32_t halo_radius_tiles = halo_margin / 2;
	const int32_t pixels_per_tile = std::max(4, std::min(p_pixels_per_tile, 32));
	const int32_t width = halo_side * pixels_per_tile;
	const int32_t height = halo_side * pixels_per_tile;
	const float step_px = static_cast<float>(p_tile_size_px) / static_cast<float>(pixels_per_tile);
	const int32_t pixel_count = width * height;
	godot::PackedByteArray bytes;
	bytes.resize(pixel_count);
	uint8_t *bytes_write = bytes.ptrw();

	int32_t closed_sample_count = 0;
	int32_t dug_sample_count = 0;
	int32_t solid_sample_count = 0;
	for (int32_t y = halo_radius_tiles; y < halo_radius_tiles + p_chunk_size; ++y) {
		for (int32_t x = halo_radius_tiles; x < halo_radius_tiles + p_chunk_size; ++x) {
			const bool closed_solid = read_solid(p_solid_halo, halo_side, x, y);
			const bool dug = dual_mask_requested && read_solid(p_dug_halo, halo_side, x, y);
			if (closed_solid) {
				++closed_sample_count;
			}
			if (dug) {
				++dug_sample_count;
			}
			if (closed_solid && !dug) {
				++solid_sample_count;
			}
		}
	}

	std::vector<float> field(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> temp(static_cast<size_t>(pixel_count), 0.0f);
	std::vector<float> blurred(static_cast<size_t>(pixel_count), 0.0f);
	for (int32_t py = 0; py < height; ++py) {
		const int32_t tile_y = std::max(0, std::min(halo_side - 1, py / pixels_per_tile));
		for (int32_t px = 0; px < width; ++px) {
			const int32_t tile_x = std::max(0, std::min(halo_side - 1, px / pixels_per_tile));
			field[static_cast<size_t>(py * width + px)] = read_solid(p_solid_halo, halo_side, tile_x, tile_y) ? 1.0f : 0.0f;
		}
	}

	const int32_t blur_radius = std::max(2, (pixels_per_tile * 5) / 8);
	for (int32_t pass = 0; pass < 3; ++pass) {
		const std::vector<float> &src_h = pass == 0 ? field : blurred;
		for (int32_t y = 0; y < height; ++y) {
			float sum = 0.0f;
			for (int32_t x = -blur_radius; x <= blur_radius; ++x) {
				const int32_t sample_x = std::max(0, std::min(width - 1, x));
				sum += src_h[static_cast<size_t>(y * width + sample_x)];
			}
			for (int32_t x = 0; x < width; ++x) {
				temp[static_cast<size_t>(y * width + x)] = sum / static_cast<float>(blur_radius * 2 + 1);
				const int32_t remove_x = std::max(0, std::min(width - 1, x - blur_radius));
				const int32_t add_x = std::max(0, std::min(width - 1, x + blur_radius + 1));
				sum += src_h[static_cast<size_t>(y * width + add_x)];
				sum -= src_h[static_cast<size_t>(y * width + remove_x)];
			}
		}
		for (int32_t x = 0; x < width; ++x) {
			float sum = 0.0f;
			for (int32_t y = -blur_radius; y <= blur_radius; ++y) {
				const int32_t sample_y = std::max(0, std::min(height - 1, y));
				sum += temp[static_cast<size_t>(sample_y * width + x)];
			}
			for (int32_t y = 0; y < height; ++y) {
				blurred[static_cast<size_t>(y * width + x)] = sum / static_cast<float>(blur_radius * 2 + 1);
				const int32_t remove_y = std::max(0, std::min(height - 1, y - blur_radius));
				const int32_t add_y = std::max(0, std::min(height - 1, y + blur_radius + 1));
				sum += temp[static_cast<size_t>(add_y * width + x)];
				sum -= temp[static_cast<size_t>(remove_y * width + x)];
			}
		}
	}

	for (int32_t py = 0; py < height; ++py) {
		const float world_y = static_cast<float>(p_origin_world_y) + (static_cast<float>(py) + 0.5f) * step_px;
		for (int32_t px = 0; px < width; ++px) {
			const float world_x = static_cast<float>(p_origin_world_x) + (static_cast<float>(px) + 0.5f) * step_px;
			const float broad = fbm_noise((world_x - 173.0f) / 420.0f, (world_y + 211.0f) / 420.0f);
			const float macro = fbm_noise(world_x / 220.0f, world_y / 220.0f);
			const float fine = fbm_noise((world_x + 91.0f) / 104.0f, (world_y - 37.0f) / 104.0f);
			const float disp_x = ((fbm_noise((world_x + 43.0f) / 360.0f, (world_y - 139.0f) / 360.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 1.15f)
					+ ((fbm_noise((world_x - 211.0f) / 170.0f, (world_y + 79.0f) / 170.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 0.46f);
			const float disp_y = ((fbm_noise((world_x - 97.0f) / 380.0f, (world_y + 181.0f) / 380.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 1.15f)
					+ ((fbm_noise((world_x + 157.0f) / 176.0f, (world_y - 223.0f) / 176.0f) - 0.5f) * static_cast<float>(pixels_per_tile) * 0.46f);
			const float threshold = 0.455f
					+ ((broad - 0.5f) * 0.150f)
					+ ((macro - 0.5f) * 0.150f)
					+ ((fine - 0.5f) * 0.035f);
			const float edge_width = 0.110f;
			const float field = sample_grid_bilinear(blurred, width, height, static_cast<float>(px) + disp_x, static_cast<float>(py) + disp_y);
			float alpha = smooth_float((field - (threshold - edge_width)) / (edge_width * 2.0f));
			alpha = std::max(0.0f, std::min(1.0f, alpha));
			const int32_t byte_value = std::max(0, std::min(255, static_cast<int32_t>(std::lround(alpha * 255.0f))));
			bytes_write[py * width + px] = static_cast<uint8_t>(byte_value);
		}
	}

	if (dual_mask_requested) {
		godot::PackedByteArray closed_roof_mask = bytes;
		godot::PackedByteArray remaining_mass_mask;
		remaining_mass_mask.resize(pixel_count);
		uint8_t *remaining_write = remaining_mass_mask.ptrw();
		godot::PackedByteArray visual_remaining_mass_mask;
		visual_remaining_mass_mask.resize(pixel_count);
		uint8_t *visual_remaining_write = visual_remaining_mass_mask.ptrw();
		godot::PackedByteArray physical_mouth_aperture_mask;
		uint8_t *physical_mouth_aperture_write = nullptr;
		bool has_physical_mouth_aperture = false;

		for (int32_t py = 0; py < height; ++py) {
			const int32_t tile_y = py / pixels_per_tile;
			for (int32_t px = 0; px < width; ++px) {
				const int32_t index = py * width + px;
				const int32_t tile_x = px / pixels_per_tile;
				const bool dug = read_solid(p_dug_halo, halo_side, tile_x, tile_y);
				// Gameplay remaining mass hard-clears the whole source tile. Outside
				// the source tile it follows the same contour as presentation so a
				// visible cutout fringe never hides an invisible ledge.
				remaining_write[index] = dug ? 0 : closed_roof_mask[index];
				float cutout_alpha = 1.0f - legacy_organic_dig_visual_opacity(
					p_dug_halo,
					halo_side,
					px,
					py,
					pixels_per_tile,
					p_tile_size_px,
					step_px,
					p_origin_world_x,
					p_origin_world_y
				);
				bool physical_mouth_aperture_pixel = false;

				if (dug) {
					const bool north_exterior = !read_solid(p_solid_halo, halo_side, tile_x, tile_y - 1);
					const bool east_exterior = !read_solid(p_solid_halo, halo_side, tile_x + 1, tile_y);
					const bool south_exterior = !read_solid(p_solid_halo, halo_side, tile_x, tile_y + 1);
					const bool west_exterior = !read_solid(p_solid_halo, halo_side, tile_x - 1, tile_y);
					// Square mining owns the whole source tile, including every boundary
					// exposure. Treating each dug-to-exterior contact as a narrow portal
					// leaves detached shoulders after a wider excavation reaches the
					// organic mountain edge. Roof entry/exit is component metadata and
					// does not depend on those visual shoulders.
					cutout_alpha = 1.0f;
					physical_mouth_aperture_pixel = north_exterior || east_exterior || south_exterior || west_exterior;
				} else if (!read_solid(p_solid_halo, halo_side, tile_x, tile_y)) {
					// CLOSED's organic contour intentionally spills into the first
					// exterior tile. Once a cardinally adjacent owned tile is dug, that
					// spill has no mineable source tile and must be cleared completely.
					// Keeping portal shoulders here creates detached, undiggable L-shaped
					// BASE facades and matching gameplay/light occluders.
					const bool source_north = read_solid(p_dug_halo, halo_side, tile_x, tile_y - 1);
					const bool source_east = read_solid(p_dug_halo, halo_side, tile_x + 1, tile_y);
					const bool source_south = read_solid(p_dug_halo, halo_side, tile_x, tile_y + 1);
					const bool source_west = read_solid(p_dug_halo, halo_side, tile_x - 1, tile_y);
					const bool has_projection_source = source_north || source_east || source_south || source_west;
					if (has_projection_source) {
						cutout_alpha = 1.0f;
						physical_mouth_aperture_pixel = true;
					}
				}
				const float remaining_alpha = static_cast<float>(closed_roof_mask[index])
					* (1.0f - cutout_alpha);
				const uint8_t visual_value = static_cast<uint8_t>(std::max(
					0,
					std::min(255, static_cast<int32_t>(std::lround(remaining_alpha)))
				));
				visual_remaining_write[index] = visual_value;
				remaining_write[index] = dug ? 0 : visual_value;
				if (physical_mouth_aperture_pixel) {
					// The aperture is canonical geometry, not a second procedural
					// approximation: record the exact CLOSED - VISUAL cut in the full
					// physical source tile and its single exterior projection. Deeper
					// excavation can alter V elsewhere without moving this entrance.
					const uint8_t aperture_value = static_cast<uint8_t>(std::max(
						0,
						static_cast<int32_t>(closed_roof_mask[index]) - static_cast<int32_t>(visual_value)
					));
					if (aperture_value != 0) {
						if (!has_physical_mouth_aperture) {
							physical_mouth_aperture_mask.resize(pixel_count);
							physical_mouth_aperture_write = physical_mouth_aperture_mask.ptrw();
							std::fill(
								physical_mouth_aperture_write,
								physical_mouth_aperture_write + pixel_count,
								static_cast<uint8_t>(0)
							);
							has_physical_mouth_aperture = true;
						}
						physical_mouth_aperture_write[index] = aperture_value;
					}
				}
			}
		}

		bytes = remaining_mass_mask;
		result["closed_roof_mask"] = closed_roof_mask;
		result["remaining_mass_mask"] = remaining_mass_mask;
		result["visual_remaining_mass_mask"] = visual_remaining_mass_mask;
		if (has_physical_mouth_aperture) {
			result["physical_mouth_aperture_mask"] = physical_mouth_aperture_mask;
		}
		result["closed_sample_count"] = closed_sample_count;
		result["dug_sample_count"] = dug_sample_count;
	}

	result["mask"] = bytes;
	result["width"] = width;
	result["height"] = height;
	result["step_px"] = static_cast<double>(step_px);
	result["solid_sample_count"] = solid_sample_count;
	result["halo_side"] = halo_side;
	result["halo_radius_tiles"] = halo_radius_tiles;
	result["pixels_per_tile"] = pixels_per_tile;
	return result;
}

} // namespace mountain_contour
