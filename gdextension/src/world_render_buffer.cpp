#include "world_render_buffer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <vector>

#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

namespace world_render_buffer {
namespace {

constexpr int32_t SOURCE_STRIDE = 12;
constexpr int32_t GPU_STRIDE = 16;
constexpr int32_t BASE_METRIC_STRIDE = 5;
constexpr int32_t METRIC_FRAME_WIDTH = 0;
constexpr int32_t METRIC_FRAME_HEIGHT = 1;
constexpr int32_t METRIC_ANCHOR_X = 2;
constexpr int32_t METRIC_ANCHOR_Y = 3;
constexpr int32_t RENDER_CROP_STRIDE = 4;
constexpr float RENDER_PAGE_HEIGHT_PX = 1024.0f;
constexpr int32_t MAX_RENDER_PAGE_SPAN = 17;
constexpr int32_t MAX_RENDER_DESCRIPTORS = 64;
constexpr int64_t MAX_VISIBLE_INSTANCES = 1LL << 20;
constexpr int64_t MAX_VISIBLE_ACTORS = 1LL << 12;
constexpr int64_t MAX_SPORE_INSTANCES = 1LL << 20;
constexpr int64_t CPU_SNAPSHOT_WORKING_SET_BOUND_BYTES = 1LL << 30;

constexpr int32_t SOURCE_SET_OBJECTS = 0;
constexpr int32_t SOURCE_SET_GRASS = 1;
constexpr int32_t GEOMETRY_ANCHORED = 0;
constexpr int32_t GEOMETRY_SOUTH_EDGE = 1;

constexpr int32_t PASS_GROUND = 1;
constexpr int32_t PASS_BODY = 2;
constexpr int32_t PASS_SHADOW = 4;
constexpr int32_t PASS_EMISSIVE = 8;
constexpr int32_t PASS_OVERHEAD = 16;
constexpr int32_t PASS_MASK = PASS_GROUND | PASS_BODY | PASS_SHADOW | PASS_EMISSIVE | PASS_OVERHEAD;

constexpr float SHADOW_OUTPUT_MIN_X = -0.10f;
constexpr float SHADOW_OUTPUT_MIN_Y = -0.10f;
constexpr float SHADOW_OUTPUT_MAX_X = 1.70f;
constexpr float SHADOW_OUTPUT_MAX_Y = 1.50f;
constexpr float MAX_SHADOW_LENGTH_SCALE = 1.85f;
constexpr float SHADOW_DIRECTION_X = 0.887216f;
constexpr float SHADOW_DIRECTION_Y = 0.461354f;

struct Bounds2D {
	float min_x = std::numeric_limits<float>::infinity();
	float min_y = std::numeric_limits<float>::infinity();
	float max_x = -std::numeric_limits<float>::infinity();
	float max_y = -std::numeric_limits<float>::infinity();

	void include(float p_x, float p_y) {
		min_x = std::min(min_x, p_x);
		min_y = std::min(min_y, p_y);
		max_x = std::max(max_x, p_x);
		max_y = std::max(max_y, p_y);
	}

	Rect2 to_rect() const {
		if (!std::isfinite(min_x) || !std::isfinite(min_y) ||
				!std::isfinite(max_x) || !std::isfinite(max_y)) {
			return Rect2();
		}
		return Rect2(min_x, min_y, std::max(0.0f, max_x - min_x), std::max(0.0f, max_y - min_y));
	}
};

struct SourceBinding {
	int32_t descriptor_id = -1;
	int32_t passes = 0;
	int32_t result_set = SOURCE_SET_OBJECTS;
	StringName buffer_key;
	int32_t geometry = GEOMETRY_ANCHORED;
	int32_t semantic_layer = 10;
	int32_t metric_stride = BASE_METRIC_STRIDE;
	PackedFloat32Array metrics;
	PackedFloat32Array render_crops;
	PackedFloat32Array compact_ground_shadow_rects;
	PackedFloat32Array shadow_source_crops;
	std::array<float, RENDER_CROP_STRIDE> shadow_source_crop{0.0f, 0.0f, 1.0f, 1.0f};
	bool lod_scaled = false;
	bool shadow_lod_scaled = false;
	float shadow_lod_start_fraction = 0.0f;
};

struct RenderAtom {
	std::array<float, SOURCE_STRIDE> source{};
	float root_y = 0.0f;
	int32_t descriptor_id = 0;
	int32_t passes = 0;
	int32_t semantic_layer = 0;
	uint64_t stable_id = 0;
	std::array<float, RENDER_CROP_STRIDE> render_crop{0.0f, 0.0f, 1.0f, 1.0f};
	std::array<float, RENDER_CROP_STRIDE> shadow_output_crop{
			SHADOW_OUTPUT_MIN_X,
			SHADOW_OUTPUT_MIN_Y,
			SHADOW_OUTPUT_MAX_X - SHADOW_OUTPUT_MIN_X,
			SHADOW_OUTPUT_MAX_Y - SHADOW_OUTPUT_MIN_Y};
	std::array<float, RENDER_CROP_STRIDE> compact_ground_shadow_rect{};
	float anchor_u = 0.5f;
	float anchor_v = 0.5f;
	bool shadow_enabled = true;
};

void resolve_shadow_output_crop(
		RenderAtom &r_atom,
		const SourceBinding &p_binding,
		int32_t p_frame) {
	const int64_t offset = static_cast<int64_t>(p_frame) * RENDER_CROP_STRIDE;
	const float *source_crops = p_binding.shadow_source_crops.ptr();
	const float source_x = source_crops[offset];
	const float source_y = source_crops[offset + 1];
	const float source_width = source_crops[offset + 2];
	const float source_height = source_crops[offset + 3];
	if (p_binding.geometry == GEOMETRY_SOUTH_EDGE) {
		r_atom.shadow_output_crop = {source_x, source_y, source_width, source_height};
		return;
	}
	float min_x = std::numeric_limits<float>::infinity();
	float min_y = std::numeric_limits<float>::infinity();
	float max_x = -std::numeric_limits<float>::infinity();
	float max_y = -std::numeric_limits<float>::infinity();
	for (const float corner_y : {source_y, source_y + source_height}) {
		for (const float corner_x : {source_x, source_x + source_width}) {
			float delta_x = corner_x - r_atom.anchor_u;
			float delta_y = corner_y - r_atom.anchor_v;
			const float forward = delta_x * SHADOW_DIRECTION_X + delta_y * SHADOW_DIRECTION_Y;
			if (forward > 0.0f) {
				const float extension = forward * (MAX_SHADOW_LENGTH_SCALE - 1.0f);
				delta_x += SHADOW_DIRECTION_X * extension;
				delta_y += SHADOW_DIRECTION_Y * extension;
			}
			const float output_x = r_atom.anchor_u + delta_x;
			const float output_y = r_atom.anchor_v + delta_y;
			min_x = std::min(min_x, output_x);
			min_y = std::min(min_y, output_y);
			max_x = std::max(max_x, output_x);
			max_y = std::max(max_y, output_y);
		}
	}
	r_atom.shadow_output_crop = {
			min_x,
			min_y,
			std::max(0.001f, max_x - min_x),
			std::max(0.001f, max_y - min_y)};
}

bool finite_transform(const float *p_source) {
	for (int32_t index = 0; index < SOURCE_STRIDE; ++index) {
		if (!std::isfinite(static_cast<double>(p_source[index]))) {
			return false;
		}
	}
	return true;
}

uint64_t hash_u64(uint64_t p_hash, uint64_t p_value) {
	constexpr uint64_t FNV_PRIME = 1099511628211ULL;
	for (int32_t byte_index = 0; byte_index < 8; ++byte_index) {
		p_hash ^= (p_value >> (byte_index * 8)) & 0xFFULL;
		p_hash *= FNV_PRIME;
	}
	return p_hash;
}

uint64_t make_static_stable_id(
		const Vector2 &p_chunk_origin,
		int32_t p_descriptor_id,
		uint64_t p_stream_tag,
		int64_t p_instance_index) {
	uint64_t hash = 1469598103934665603ULL;
	hash = hash_u64(hash, static_cast<uint64_t>(static_cast<int64_t>(
			std::llround(static_cast<double>(p_chunk_origin.x) * 16.0))));
	hash = hash_u64(hash, static_cast<uint64_t>(static_cast<int64_t>(
			std::llround(static_cast<double>(p_chunk_origin.y) * 16.0))));
	hash = hash_u64(hash, static_cast<uint64_t>(p_descriptor_id));
	hash = hash_u64(hash, p_stream_tag);
	hash = hash_u64(hash, static_cast<uint64_t>(p_instance_index));
	// Stable ids cross the Variant boundary as signed int64 values. Keeping the
	// high bit clear preserves the exact native ordering after publication.
	return hash & 0x7FFFFFFFFFFFFFFFULL;
}

void include_unit_quad(const float *p_instance, Bounds2D &r_bounds) {
	const float xx = p_instance[0];
	const float yx = p_instance[1];
	const float origin_x = p_instance[3];
	const float xy = p_instance[4];
	const float yy = p_instance[5];
	const float origin_y = p_instance[7];
	for (const float local_y : {-0.5f, 0.5f}) {
		for (const float local_x : {-0.5f, 0.5f}) {
			r_bounds.include(
					origin_x + xx * local_x + yx * local_y,
					origin_y + xy * local_x + yy * local_y);
		}
	}
}

int32_t decoded_frame(const float *p_source, int32_t p_metric_count) {
	if (p_metric_count <= 0) {
		return 0;
	}
	const int32_t encoded = static_cast<int32_t>(std::floor(std::clamp(p_source[8], 0.0f, 1.0f) * 255.0f + 0.5f));
	return encoded % p_metric_count;
}

bool parse_source_bindings(
		const Array &p_binding_values,
		std::vector<SourceBinding> &r_bindings,
		String &r_error) {
	if (p_binding_values.is_empty() || p_binding_values.size() > MAX_RENDER_DESCRIPTORS) {
		r_error = "world_render_buffer: source binding count violates authored bound";
		return false;
	}
	std::array<bool, MAX_RENDER_DESCRIPTORS> seen{};
	r_bindings.clear();
	r_bindings.reserve(static_cast<size_t>(p_binding_values.size()));
	for (int64_t binding_index = 0; binding_index < p_binding_values.size(); ++binding_index) {
		const Variant binding_value = p_binding_values[binding_index];
		if (binding_value.get_type() != Variant::DICTIONARY) {
			r_error = "world_render_buffer: source binding is not a Dictionary";
			return false;
		}
		const Dictionary source = binding_value;
		SourceBinding binding;
		binding.descriptor_id = static_cast<int32_t>(source.get("descriptor_id", -1));
		binding.passes = static_cast<int32_t>(source.get("passes", 0));
		binding.result_set = static_cast<int32_t>(source.get("result_set", -1));
		binding.buffer_key = source.get("buffer_key", StringName());
		binding.geometry = static_cast<int32_t>(source.get("geometry", -1));
		binding.semantic_layer = static_cast<int32_t>(source.get("semantic_layer", 10));
		binding.metric_stride = static_cast<int32_t>(source.get("metric_stride", 0));
		binding.metrics = source.get("metrics", PackedFloat32Array());
		binding.render_crops = source.get("render_crops", PackedFloat32Array());
		binding.compact_ground_shadow_rects = source.get(
				"compact_ground_shadow_rects", PackedFloat32Array());
		binding.shadow_source_crops = source.get("shadow_source_crops", PackedFloat32Array());
		const PackedFloat32Array shadow_crop = source.get("shadow_source_crop", PackedFloat32Array());
		binding.lod_scaled = static_cast<bool>(source.get("lod_scaled", false));
		binding.shadow_lod_scaled = static_cast<bool>(source.get("shadow_lod_scaled", false));
		binding.shadow_lod_start_fraction = static_cast<float>(
				source.get("shadow_lod_start_fraction", 0.0f));
		const int32_t primary_pass = binding.passes & (PASS_GROUND | PASS_BODY);
		if (binding.descriptor_id < 0 || binding.descriptor_id >= MAX_RENDER_DESCRIPTORS ||
				seen[static_cast<size_t>(binding.descriptor_id)] || binding.passes <= 0 ||
				(binding.passes & ~PASS_MASK) != 0 ||
				(primary_pass != PASS_GROUND && primary_pass != PASS_BODY) ||
				(binding.result_set != SOURCE_SET_OBJECTS && binding.result_set != SOURCE_SET_GRASS) ||
				binding.buffer_key == StringName() ||
				(binding.geometry != GEOMETRY_ANCHORED && binding.geometry != GEOMETRY_SOUTH_EDGE) ||
				binding.metric_stride < BASE_METRIC_STRIDE ||
				binding.metrics.size() % binding.metric_stride != 0 ||
				binding.render_crops.is_empty() || binding.render_crops.size() % RENDER_CROP_STRIDE != 0 ||
				shadow_crop.size() != RENDER_CROP_STRIDE ||
				!std::isfinite(binding.shadow_lod_start_fraction) ||
				binding.shadow_lod_start_fraction < 0.0f ||
				binding.shadow_lod_start_fraction >= 1.0f) {
			r_error = "world_render_buffer: invalid data-driven source binding";
			return false;
		}
		if (binding.geometry == GEOMETRY_ANCHORED && binding.metrics.is_empty()) {
			r_error = "world_render_buffer: anchored source binding requires metrics";
			return false;
		}
		if (primary_pass == PASS_GROUND &&
				binding.compact_ground_shadow_rects.size() != binding.render_crops.size()) {
			r_error = "world_render_buffer: ground shadow rect count does not match variants";
			return false;
		}
		if (binding.shadow_source_crops.size() != binding.render_crops.size()) {
			r_error = "world_render_buffer: shadow crop count does not match variants";
			return false;
		}
		for (int32_t component = 0; component < RENDER_CROP_STRIDE; ++component) {
			binding.shadow_source_crop[static_cast<size_t>(component)] = shadow_crop[component];
		}
		if (binding.shadow_source_crop[2] <= 0.0f || binding.shadow_source_crop[3] <= 0.0f) {
			r_error = "world_render_buffer: source shadow crop is empty";
			return false;
		}
		seen[static_cast<size_t>(binding.descriptor_id)] = true;
		r_bindings.push_back(binding);
	}
	return true;
}

int64_t visible_bucket_instance_count(
		const Dictionary &p_result,
		const SourceBinding &p_binding,
		float p_lod_fraction,
		String &r_error) {
	const Variant table_value = p_result.get(p_binding.buffer_key, Array());
	if (table_value.get_type() != Variant::ARRAY) {
		r_error = "world_render_buffer: source bucket table has invalid type";
		return -1;
	}
	int64_t total = 0;
	const Array buckets = table_value;
	for (int64_t bucket_index = 0; bucket_index < buckets.size(); ++bucket_index) {
		const Variant buffer_value = buckets[bucket_index];
		if (buffer_value.get_type() != Variant::PACKED_FLOAT32_ARRAY) {
			r_error = "world_render_buffer: source bucket is not PackedFloat32Array";
			return -1;
		}
		const PackedFloat32Array buffer = buffer_value;
		if (buffer.size() % SOURCE_STRIDE != 0) {
			r_error = "world_render_buffer: source bucket violates instance stride";
			return -1;
		}
		const int64_t full_count = buffer.size() / SOURCE_STRIDE;
		total += p_binding.lod_scaled
				? static_cast<int64_t>(std::ceil(static_cast<double>(full_count) *
						static_cast<double>(std::clamp(p_lod_fraction, 0.0f, 1.0f))))
				: full_count;
	}
	return total;
}

bool append_source_buffer(
		const PackedFloat32Array &p_buffer,
		const Vector2 &p_chunk_origin,
		const SourceBinding &p_binding,
		uint64_t p_stream_tag,
		std::vector<RenderAtom> &r_atoms,
		String &r_error,
		int64_t p_instance_limit = -1,
		int64_t p_shadow_instance_limit = -1) {
	if (p_buffer.size() % SOURCE_STRIDE != 0) {
		r_error = "world_render_buffer: source buffer violates 12-float instance stride";
		return false;
	}
	const int32_t metric_count = static_cast<int32_t>(p_binding.metrics.size() / p_binding.metric_stride);
	const int32_t crop_count = static_cast<int32_t>(p_binding.render_crops.size() / RENDER_CROP_STRIDE);
	const float *metrics = p_binding.metrics.ptr();
	const float *render_crops = p_binding.render_crops.ptr();
	const float *compact_ground_shadow_rects = p_binding.compact_ground_shadow_rects.ptr();
	const float *source = p_buffer.ptr();
	const int64_t available_instance_count = p_buffer.size() / SOURCE_STRIDE;
	const int64_t instance_count = p_instance_limit < 0
			? available_instance_count
			: std::min(available_instance_count, p_instance_limit);
	for (int64_t instance_index = 0; instance_index < instance_count; ++instance_index) {
		const float *raw = source + instance_index * SOURCE_STRIDE;
		if (!finite_transform(raw)) {
			r_error = "world_render_buffer: source buffer contains non-finite values";
			return false;
		}
		RenderAtom atom;
		std::copy(raw, raw + SOURCE_STRIDE, atom.source.begin());
		atom.source[3] += p_chunk_origin.x;
		atom.source[7] += p_chunk_origin.y;
		atom.descriptor_id = p_binding.descriptor_id;
		atom.passes = p_binding.passes;
		atom.shadow_enabled = p_shadow_instance_limit < 0 ||
				instance_index < p_shadow_instance_limit;
		atom.semantic_layer = p_binding.semantic_layer;
		atom.stable_id = make_static_stable_id(
				p_chunk_origin,
				p_binding.descriptor_id,
				p_stream_tag,
				instance_index);
		const int32_t crop_frame = decoded_frame(raw, crop_count);
		if (crop_count > 0) {
			const int64_t crop_offset = static_cast<int64_t>(crop_frame) * RENDER_CROP_STRIDE;
			atom.render_crop[0] = std::clamp(render_crops[crop_offset], 0.0f, 1.0f);
			atom.render_crop[1] = std::clamp(render_crops[crop_offset + 1], 0.0f, 1.0f);
			atom.render_crop[2] = std::clamp(render_crops[crop_offset + 2], 0.001f, 1.0f);
			atom.render_crop[3] = std::clamp(render_crops[crop_offset + 3], 0.001f, 1.0f);
			if ((p_binding.passes & PASS_GROUND) != 0) {
				for (int32_t component = 0; component < RENDER_CROP_STRIDE; ++component) {
					atom.compact_ground_shadow_rect[static_cast<size_t>(component)] =
							compact_ground_shadow_rects[crop_offset + component];
				}
			}
		}

		if (p_binding.geometry == GEOMETRY_SOUTH_EDGE) {
			const float y_axis_x = raw[1];
			const float y_axis_y = raw[5];
			const float height = std::sqrt(y_axis_x * y_axis_x + y_axis_y * y_axis_y);
			atom.root_y = atom.source[7] + height * 0.5f;
		} else {
			const int32_t frame = decoded_frame(raw, metric_count);
			const int64_t metric_offset = static_cast<int64_t>(frame) * p_binding.metric_stride;
			const float frame_width = metrics[metric_offset + METRIC_FRAME_WIDTH];
			const float frame_height = metrics[metric_offset + METRIC_FRAME_HEIGHT];
			const float anchor_x = metrics[metric_offset + METRIC_ANCHOR_X];
			const float anchor_y = metrics[metric_offset + METRIC_ANCHOR_Y];
			atom.anchor_u = anchor_x / std::max(frame_width, 0.001f);
			atom.anchor_v = anchor_y / std::max(frame_height, 0.001f);
			const float x_axis_x = raw[0];
			const float x_axis_y = raw[4];
			const float y_axis_x = raw[1];
			const float y_axis_y = raw[5];
			const float width = std::sqrt(x_axis_x * x_axis_x + x_axis_y * x_axis_y);
			const float height = std::sqrt(y_axis_x * y_axis_x + y_axis_y * y_axis_y);
			const float scale_x = width / std::max(frame_width, 0.001f);
			const float scale_y = height / std::max(frame_height, 0.001f);
			atom.root_y = atom.source[7] + (anchor_y - frame_height * 0.5f) * scale_y;
		}
		resolve_shadow_output_crop(atom, p_binding, crop_frame);
		r_atoms.push_back(atom);
	}
	return true;
}

bool append_source_bucket_table(
		const Dictionary &p_result,
		const Vector2 &p_chunk_origin,
		const SourceBinding &p_binding,
		float p_lod_fraction,
		std::vector<RenderAtom> &r_atoms,
		String &r_error) {
	const Variant table_value = p_result.get(p_binding.buffer_key, Array());
	if (table_value.get_type() != Variant::ARRAY) {
		r_error = "world_render_buffer: source bucket table has invalid type";
		return false;
	}
	const float lod_fraction = std::clamp(p_lod_fraction, 0.0f, 1.0f);
	const Array buckets = table_value;
	for (int64_t bucket_index = 0; bucket_index < buckets.size(); ++bucket_index) {
		const Variant buffer_value = buckets[bucket_index];
		if (buffer_value.get_type() != Variant::PACKED_FLOAT32_ARRAY) {
			r_error = "world_render_buffer: source bucket is not PackedFloat32Array";
			return false;
		}
		const PackedFloat32Array buffer = buffer_value;
		if (buffer.size() % SOURCE_STRIDE != 0) {
			r_error = "world_render_buffer: source bucket violates instance stride";
			return false;
		}
		const int64_t full_count = buffer.size() / SOURCE_STRIDE;
		const int64_t visible_count = p_binding.lod_scaled
				? static_cast<int64_t>(std::ceil(
						static_cast<double>(full_count) * static_cast<double>(lod_fraction)))
				: full_count;
		const float shadow_fraction = p_binding.shadow_lod_scaled
				? std::clamp(
						(lod_fraction - p_binding.shadow_lod_start_fraction) /
								(1.0f - p_binding.shadow_lod_start_fraction),
						0.0f,
						1.0f)
				: 1.0f;
		const int64_t shadow_count = static_cast<int64_t>(std::ceil(
				static_cast<double>(full_count) * static_cast<double>(shadow_fraction)));
		if (!append_source_buffer(
				buffer,
				p_chunk_origin,
				p_binding,
				(static_cast<uint64_t>(p_binding.descriptor_id + 1) << 32) |
						static_cast<uint64_t>(bucket_index),
				r_atoms,
				r_error,
				visible_count,
				shadow_count)) {
			return false;
		}
	}
	return true;
}

void append_gpu_instance(
		const RenderAtom &p_atom,
		bool p_shadow,
		std::vector<float> &r_buffer,
		Bounds2D &r_bounds) {
	float instance[GPU_STRIDE] = {};
	std::copy(p_atom.source.begin(), p_atom.source.end(), instance);
	if (!p_shadow) {
		const float crop_x = p_atom.render_crop[0];
		const float crop_y = p_atom.render_crop[1];
		const float crop_width = p_atom.render_crop[2];
		const float crop_height = p_atom.render_crop[3];
		const float center_x = crop_x + crop_width * 0.5f - 0.5f;
		const float center_y = crop_y + crop_height * 0.5f - 0.5f;
		const float xx = instance[0];
		const float yx = instance[1];
		const float xy = instance[4];
		const float yy = instance[5];
		instance[3] += xx * center_x + yx * center_y;
		instance[7] += xy * center_x + yy * center_y;
		instance[0] = xx * crop_width;
		instance[4] = xy * crop_width;
		instance[1] = yx * crop_height;
		instance[5] = yy * crop_height;
	} else {
		const float crop_x = p_atom.shadow_output_crop[0];
		const float crop_y = p_atom.shadow_output_crop[1];
		const float crop_width = p_atom.shadow_output_crop[2];
		const float crop_height = p_atom.shadow_output_crop[3];
		const float offset_x = crop_x + crop_width * 0.5f - 0.5f;
		const float offset_y = crop_y + crop_height * 0.5f - 0.5f;
		const float xx = instance[0];
		const float yx = instance[1];
		const float xy = instance[4];
		const float yy = instance[5];
		instance[3] += xx * offset_x + yx * offset_y;
		instance[7] += xy * offset_x + yy * offset_y;
		instance[0] = xx * crop_width;
		instance[4] = xy * crop_width;
		instance[1] = yx * crop_height;
		instance[5] = yy * crop_height;
	}
	instance[12] = static_cast<float>(p_atom.descriptor_id);
	instance[13] = std::floor(std::clamp(p_atom.source[8], 0.0f, 1.0f) * 255.0f + 0.5f);
	// z is deliberately unused. Painter metadata stays in the compact CPU-side
	// arrays and does not consume the GPU instance payload.
	instance[14] = 0.0f;
	instance[15] = p_shadow ? p_atom.shadow_output_crop[3] : 0.0f;
	if (p_shadow && (p_atom.passes & PASS_GROUND) != 0) {
		// A positive custom.z tags the compact ground-shadow payload. The four
		// custom floats are its already-resolved atlas UV rectangle.
		for (int32_t component = 0; component < RENDER_CROP_STRIDE; ++component) {
			instance[12 + component] =
					p_atom.compact_ground_shadow_rect[static_cast<size_t>(component)];
		}
	} else if (p_shadow) {
		instance[8] = p_atom.shadow_output_crop[0];
		instance[9] = p_atom.shadow_output_crop[1];
		instance[10] = p_atom.shadow_output_crop[2];
	}
	r_buffer.insert(r_buffer.end(), instance, instance + GPU_STRIDE);
	include_unit_quad(instance, r_bounds);
}

PackedFloat32Array pack(const std::vector<float> &p_source) {
	PackedFloat32Array result;
	result.resize(static_cast<int64_t>(p_source.size()));
	if (!p_source.empty()) {
		std::copy(p_source.begin(), p_source.end(), result.ptrw());
	}
	return result;
}

bool append_flat_buffer(
		const PackedFloat32Array &p_buffer,
		const Vector2 &p_chunk_origin,
		std::vector<float> &r_buffer,
		Bounds2D &r_bounds,
		String &r_error) {
	if (p_buffer.size() % SOURCE_STRIDE != 0) {
		r_error = "world_render_buffer: flat buffer violates 12-float instance stride";
		return false;
	}
	const float *source = p_buffer.ptr();
	for (int64_t offset = 0; offset < p_buffer.size(); offset += SOURCE_STRIDE) {
		if (!finite_transform(source + offset)) {
			r_error = "world_render_buffer: flat buffer contains non-finite values";
			return false;
		}
		float instance[SOURCE_STRIDE];
		std::copy(source + offset, source + offset + SOURCE_STRIDE, instance);
		instance[3] += p_chunk_origin.x;
		instance[7] += p_chunk_origin.y;
		r_buffer.insert(r_buffer.end(), instance, instance + SOURCE_STRIDE);
		include_unit_quad(instance, r_bounds);
	}
	return true;
}

Dictionary error_result(const String &p_error) {
	Dictionary result;
	result["success"] = false;
	result["error"] = p_error;
	result["body_buffer"] = PackedFloat32Array();
	result["shadow_buffer"] = PackedFloat32Array();
	result["instance_count"] = 0;
	return result;
}

struct ComposedBodyInstance {
	std::array<float, GPU_STRIDE> gpu{};
	float feet_y = 0.0f;
	int32_t semantic_layer = 0;
	uint64_t stable_id = 0;
};

bool painter_key_less(
		float p_left_y, int32_t p_left_layer, uint64_t p_left_id,
		float p_right_y, int32_t p_right_layer, uint64_t p_right_id) {
	if (p_left_y != p_right_y) {
		return p_left_y < p_right_y;
	}
	if (p_left_layer != p_right_layer) {
		return p_left_layer < p_right_layer;
	}
	return p_left_id < p_right_id;
}

struct ParsedActorInstance {
	ComposedBodyInstance body;
	std::array<float, GPU_STRIDE> shadow{};
	bool has_shadow = false;
	int64_t page_y = 0;
};

void write_transform(const Transform2D &p_transform, float *r_gpu) {
	const Vector2 axis_x = p_transform[0];
	const Vector2 axis_y = p_transform[1];
	const Vector2 origin = p_transform[2];
	r_gpu[0] = axis_x.x;
	r_gpu[1] = axis_y.x;
	r_gpu[3] = origin.x;
	r_gpu[4] = axis_x.y;
	r_gpu[5] = axis_y.y;
	r_gpu[7] = origin.y;
}

bool finite_gpu_instance(const float *p_gpu) {
	for (int32_t index = 0; index < GPU_STRIDE; ++index) {
		if (!std::isfinite(static_cast<double>(p_gpu[index]))) {
			return false;
		}
	}
	return true;
}

bool parse_actor_record(
		const Dictionary &p_record,
		ParsedActorInstance &r_actor,
		String &r_error) {
	const Variant body_transform_value = p_record.get("body_transform", Variant());
	if (body_transform_value.get_type() != Variant::TRANSFORM2D) {
		r_error = "world_render_buffer: actor body_transform is not Transform2D";
		return false;
	}
	const double feet_y_value = static_cast<double>(p_record.get("feet_y", 0.0));
	const int64_t stable_id_value = static_cast<int64_t>(p_record.get("stable_id", -1));
	const int64_t semantic_layer_value = static_cast<int64_t>(p_record.get("semantic_layer", 20));
	const int64_t direction_index = static_cast<int64_t>(p_record.get("direction_index", 0));
	const int64_t frame_index = static_cast<int64_t>(p_record.get("frame_index", 0));
	const int64_t sprite_id = static_cast<int64_t>(p_record.get("sprite_id", 0));
	if (!std::isfinite(feet_y_value) || stable_id_value < 0 ||
			semantic_layer_value < std::numeric_limits<int32_t>::min() ||
			semantic_layer_value > std::numeric_limits<int32_t>::max() ||
			direction_index < 0 || direction_index > 15 ||
			frame_index < 0 || frame_index > 15 ||
			sprite_id < 0 || sprite_id >= MAX_RENDER_DESCRIPTORS) {
		r_error = "world_render_buffer: actor record contains an invalid painter or frame field";
		return false;
	}

	r_actor.body.feet_y = static_cast<float>(feet_y_value);
	r_actor.body.semantic_layer = static_cast<int32_t>(semantic_layer_value);
	r_actor.body.stable_id = static_cast<uint64_t>(stable_id_value);
	r_actor.page_y = static_cast<int64_t>(std::floor(
			r_actor.body.feet_y / RENDER_PAGE_HEIGHT_PX));
	write_transform(body_transform_value, r_actor.body.gpu.data());
	const Variant tint_value = p_record.get("tint", Color(1.0f, 1.0f, 1.0f, 1.0f));
	if (tint_value.get_type() != Variant::COLOR) {
		r_error = "world_render_buffer: actor tint is not Color";
		return false;
	}
	const Color tint = tint_value;
	r_actor.body.gpu[8] = tint.r;
	r_actor.body.gpu[9] = tint.g;
	r_actor.body.gpu[10] = tint.b;
	r_actor.body.gpu[11] = tint.a;
	r_actor.body.gpu[12] = static_cast<float>(sprite_id);
	r_actor.body.gpu[13] = static_cast<float>(direction_index * 16 + frame_index);
	r_actor.body.gpu[14] = 0.0f;
	if (!finite_gpu_instance(r_actor.body.gpu.data())) {
		r_error = "world_render_buffer: actor body instance contains non-finite values";
		return false;
	}

	const bool shadow_visible = static_cast<bool>(p_record.get("shadow_visible", true));
	const float shadow_opacity = static_cast<float>(p_record.get("shadow_opacity", 1.0));
	if (!shadow_visible || shadow_opacity <= 0.0f) {
		return true;
	}
	const Variant shadow_transform_value = p_record.get("shadow_transform", Variant());
	const Variant shadow_anchor_value = p_record.get("shadow_anchor", Vector2(0.5f, 0.5f));
	if (shadow_transform_value.get_type() != Variant::TRANSFORM2D ||
			shadow_anchor_value.get_type() != Variant::VECTOR2) {
		r_error = "world_render_buffer: actor shadow contract has invalid transform or anchor";
		return false;
	}
	const float shadow_softness = static_cast<float>(p_record.get("shadow_softness", 0.5));
	const float shadow_length_scale = static_cast<float>(p_record.get("shadow_length_scale", 1.0));
	if (!std::isfinite(shadow_opacity) || !std::isfinite(shadow_softness) ||
			!std::isfinite(shadow_length_scale)) {
		r_error = "world_render_buffer: actor shadow contract contains non-finite values";
		return false;
	}
	write_transform(shadow_transform_value, r_actor.shadow.data());
	const Vector2 shadow_anchor = shadow_anchor_value;
	r_actor.shadow[8] = std::max(0.0f, shadow_softness);
	r_actor.shadow[9] = shadow_anchor.x;
	r_actor.shadow[10] = shadow_anchor.y;
	r_actor.shadow[11] = std::clamp(shadow_opacity, 0.0f, 1.0f);
	r_actor.shadow[12] = static_cast<float>(sprite_id);
	r_actor.shadow[13] = static_cast<float>(direction_index * 16 + frame_index);
	r_actor.shadow[14] = 0.0f;
	r_actor.shadow[15] = std::max(0.0f, shadow_length_scale);
	if (!finite_gpu_instance(r_actor.shadow.data())) {
		r_error = "world_render_buffer: actor shadow instance contains non-finite values";
		return false;
	}
	r_actor.has_shadow = true;
	return true;
}

float fract_float(float p_value) {
	return p_value - std::floor(p_value);
}

float wind_hash(float p_x, float p_y) {
	float x = fract_float(p_x * 0.1031f);
	float y = fract_float(p_y * 0.1031f);
	float z = x;
	const float dot = x * (y + 33.33f) + y * (z + 33.33f) + z * (x + 33.33f);
	x += dot;
	y += dot;
	z += dot;
	return fract_float((x + y) * z);
}

std::array<float, 2> wind_gradient(int32_t p_x, int32_t p_y, int32_t p_period) {
	const int32_t wrapped_x = (p_x % p_period + p_period) % p_period;
	const int32_t wrapped_y = (p_y % p_period + p_period) % p_period;
	const float x = static_cast<float>(wrapped_x);
	const float y = static_cast<float>(wrapped_y);
	const float gx = wind_hash(x, y) * 2.0f - 1.0f + 0.001f;
	const float gy = wind_hash(x + 17.31f, y - 41.77f) * 2.0f - 1.0f - 0.001f;
	const float length = std::sqrt(gx * gx + gy * gy);
	if (length <= 0.000001f) {
		return {1.0f, 0.0f};
	}
	return {gx / length, gy / length};
}

float periodic_gradient_noise(float p_x, float p_y, int32_t p_period) {
	const int32_t ix = static_cast<int32_t>(std::floor(p_x));
	const int32_t iy = static_cast<int32_t>(std::floor(p_y));
	const float fx = p_x - static_cast<float>(ix);
	const float fy = p_y - static_cast<float>(iy);
	const float ux = fx * fx * fx * (fx * (fx * 6.0f - 15.0f) + 10.0f);
	const float uy = fy * fy * fy * (fy * (fy * 6.0f - 15.0f) + 10.0f);
	const auto g00 = wind_gradient(ix, iy, p_period);
	const auto g10 = wind_gradient(ix + 1, iy, p_period);
	const auto g01 = wind_gradient(ix, iy + 1, p_period);
	const auto g11 = wind_gradient(ix + 1, iy + 1, p_period);
	const float a = g00[0] * fx + g00[1] * fy;
	const float b = g10[0] * (fx - 1.0f) + g10[1] * fy;
	const float c = g01[0] * fx + g01[1] * (fy - 1.0f);
	const float d = g11[0] * (fx - 1.0f) + g11[1] * (fy - 1.0f);
	const float top = a + (b - a) * ux;
	const float bottom = c + (d - c) * ux;
	return std::clamp((top + (bottom - top) * uy) * 0.71f + 0.5f, 0.0f, 1.0f);
}

} // namespace

PackedByteArray build_periodic_gradient_noise_texture(
		int32_t p_size,
		int32_t p_texels_per_cell) {
	if (p_size < 16 || p_size > 4096 || p_texels_per_cell < 1 ||
			p_size % p_texels_per_cell != 0) {
		return PackedByteArray();
	}
	const int32_t period = p_size / p_texels_per_cell;
	PackedByteArray bytes;
	bytes.resize(static_cast<int64_t>(p_size) * p_size);
	uint8_t *output = bytes.ptrw();
	for (int32_t y = 0; y < p_size; ++y) {
		for (int32_t x = 0; x < p_size; ++x) {
			const float sample_x = (static_cast<float>(x) + 0.5f) /
					static_cast<float>(p_texels_per_cell);
			const float sample_y = (static_cast<float>(y) + 0.5f) /
					static_cast<float>(p_texels_per_cell);
			output[static_cast<int64_t>(y) * p_size + x] = static_cast<uint8_t>(
					std::lround(periodic_gradient_noise(sample_x, sample_y, period) * 255.0f));
		}
	}
	return bytes;
}

Dictionary build_snapshot(
		const PackedVector2Array &p_chunk_origins,
		const Array &p_object_results,
		const Array &p_grass_results,
		const Array &p_source_binding_values,
		float p_grass_lod_fraction) {
	if (p_object_results.size() != p_chunk_origins.size() ||
			p_grass_results.size() != p_chunk_origins.size()) {
		return error_result("world_render_buffer: chunk origin/result array sizes differ");
	}
	String error;
	std::vector<SourceBinding> bindings;
	if (!parse_source_bindings(p_source_binding_values, bindings, error)) {
		return error_result(error);
	}

	// Reserve once from the immutable worker result tables. RenderAtom remains in
	// place after construction; painter ordering below sorts compact indices.
	int64_t estimated_instance_count = 0;
	for (int64_t chunk_index = 0; chunk_index < p_chunk_origins.size(); ++chunk_index) {
		for (const SourceBinding &binding : bindings) {
			const Variant result_value = binding.result_set == SOURCE_SET_OBJECTS
					? p_object_results[chunk_index]
					: p_grass_results[chunk_index];
			if (result_value.get_type() == Variant::NIL) {
				continue;
			}
			if (result_value.get_type() != Variant::DICTIONARY) {
				return error_result("world_render_buffer: source result is not a Dictionary");
			}
			const Dictionary result = result_value;
			if (result.is_empty()) {
				continue;
			}
			const int64_t count = visible_bucket_instance_count(
					result, binding, p_grass_lod_fraction, error);
			if (count < 0) {
				return error_result(error);
			}
			estimated_instance_count += count;
			if (estimated_instance_count > MAX_VISIBLE_INSTANCES) {
				return error_result("world_render_buffer: visible instance hard bound exceeded");
			}
		}
	}

	std::vector<RenderAtom> atoms;
	atoms.reserve(static_cast<size_t>(estimated_instance_count));
	std::vector<float> spore_buffer;
	Bounds2D spore_bounds;
	for (int64_t chunk_index = 0; chunk_index < p_chunk_origins.size(); ++chunk_index) {
		const Vector2 chunk_origin = p_chunk_origins[chunk_index];
		for (const SourceBinding &binding : bindings) {
			const Variant result_value = binding.result_set == SOURCE_SET_OBJECTS
					? p_object_results[chunk_index]
					: p_grass_results[chunk_index];
			if (result_value.get_type() == Variant::NIL) {
				continue;
			}
			const Dictionary result = result_value;
			if (!result.is_empty() && !append_source_bucket_table(
					result,
					chunk_origin,
					binding,
					p_grass_lod_fraction,
					atoms,
					error)) {
				return error_result(error);
			}
		}
		const Variant grass_value = p_grass_results[chunk_index];
		if (grass_value.get_type() == Variant::DICTIONARY) {
			const Dictionary grass_result = grass_value;
			if (!grass_result.is_empty()) {
				const Variant spore_value = grass_result.get("spore_buffer", PackedFloat32Array());
				if (spore_value.get_type() != Variant::PACKED_FLOAT32_ARRAY ||
						!append_flat_buffer(
								spore_value,
								chunk_origin,
								spore_buffer,
								spore_bounds,
								error)) {
					return error_result(error.is_empty()
							? String("world_render_buffer: grass spore buffer has invalid type")
							: error);
				}
				if (static_cast<int64_t>(spore_buffer.size() / SOURCE_STRIDE) >
						MAX_SPORE_INSTANCES) {
					return error_result("world_render_buffer: spore instance hard bound exceeded");
				}
			}
		} else if (grass_value.get_type() != Variant::NIL) {
			return error_result("world_render_buffer: grass result is not a Dictionary");
		}
	}
	if (static_cast<int64_t>(atoms.size()) != estimated_instance_count) {
		return error_result("world_render_buffer: source reserve/count contract mismatch");
	}
	std::vector<size_t> sorted_indices(atoms.size());
	size_t object_shadow_instance_count = 0;
	for (size_t index = 0; index < atoms.size(); ++index) {
		sorted_indices[index] = index;
		const RenderAtom &atom = atoms[index];
		if ((atom.passes & PASS_SHADOW) != 0 &&
				(atom.passes & PASS_GROUND) == 0 && atom.shadow_enabled) {
			object_shadow_instance_count++;
		}
	}
	std::stable_sort(sorted_indices.begin(), sorted_indices.end(), [&atoms](size_t p_a, size_t p_b) {
		const RenderAtom &left = atoms[p_a];
		const RenderAtom &right = atoms[p_b];
		if (left.root_y != right.root_y) {
			return left.root_y < right.root_y;
		}
		if (left.semantic_layer != right.semantic_layer) {
			return left.semantic_layer < right.semantic_layer;
		}
		return left.stable_id < right.stable_id;
	});

	Array pages;
	int64_t occupied_page_count = 0;
	int64_t world_shadow_count = 0;
	std::vector<float> object_shadow_buffer;
	object_shadow_buffer.reserve(object_shadow_instance_count * GPU_STRIDE);
	Bounds2D object_shadow_bounds;
	int64_t total_buffer_float_count = spore_buffer.size();
	int64_t page_window_min_y = 0;
	int64_t page_window_max_y = -1;
	if (!sorted_indices.empty()) {
		page_window_min_y = static_cast<int64_t>(std::floor(
				atoms[sorted_indices.front()].root_y / RENDER_PAGE_HEIGHT_PX));
		page_window_max_y = static_cast<int64_t>(std::floor(
				atoms[sorted_indices.back()].root_y / RENDER_PAGE_HEIGHT_PX));
		if (page_window_max_y - page_window_min_y + 1 > MAX_RENDER_PAGE_SPAN) {
			return error_result("world_render_buffer: absolute render-page span exceeds the bounded slot window");
		}
	}
	std::array<int64_t, MAX_RENDER_DESCRIPTORS> descriptor_counts{};
	int64_t atom_cursor = 0;
	for (int64_t page_y = page_window_min_y; page_y <= page_window_max_y; ++page_y) {
		const int64_t page_begin = atom_cursor;
		int64_t page_ground_count = 0;
		int64_t page_body_count = 0;
		int64_t page_shadow_count = 0;
		int64_t page_emissive_count = 0;
		int64_t page_overhead_count = 0;
		while (atom_cursor < static_cast<int64_t>(sorted_indices.size()) &&
				static_cast<int64_t>(std::floor(
						atoms[sorted_indices[static_cast<size_t>(atom_cursor)]].root_y /
						RENDER_PAGE_HEIGHT_PX)) == page_y) {
			const RenderAtom &atom = atoms[sorted_indices[static_cast<size_t>(atom_cursor)]];
			page_ground_count += (atom.passes & PASS_GROUND) != 0;
			page_body_count += (atom.passes & PASS_BODY) != 0;
			page_shadow_count += (atom.passes & (PASS_GROUND | PASS_SHADOW)) ==
					(PASS_GROUND | PASS_SHADOW) && atom.shadow_enabled;
			page_emissive_count += (atom.passes & PASS_EMISSIVE) != 0;
			page_overhead_count += (atom.passes & PASS_OVERHEAD) != 0;
			atom_cursor++;
		}
		std::vector<float> page_ground;
		std::vector<float> page_body;
		std::vector<float> page_shadow;
		std::vector<float> page_emissive;
		std::vector<float> page_overhead;
		page_ground.reserve(static_cast<size_t>(page_ground_count) * GPU_STRIDE);
		page_body.reserve(static_cast<size_t>(page_body_count) * GPU_STRIDE);
		page_shadow.reserve(static_cast<size_t>(page_shadow_count) * GPU_STRIDE);
		page_emissive.reserve(static_cast<size_t>(page_emissive_count) * GPU_STRIDE);
		page_overhead.reserve(static_cast<size_t>(page_overhead_count) * GPU_STRIDE);
		std::vector<float> page_feet_y;
		std::vector<int32_t> page_semantic_layers;
		std::vector<int64_t> page_stable_ids;
		page_feet_y.reserve(static_cast<size_t>(page_body_count));
		page_semantic_layers.reserve(static_cast<size_t>(page_body_count));
		page_stable_ids.reserve(static_cast<size_t>(page_body_count));
		Bounds2D page_ground_bounds;
		Bounds2D page_body_bounds;
		Bounds2D page_shadow_bounds;
		Bounds2D page_emissive_bounds;
		Bounds2D page_overhead_bounds;
		for (int64_t sorted_cursor = page_begin; sorted_cursor < atom_cursor; ++sorted_cursor) {
			const RenderAtom &atom = atoms[sorted_indices[static_cast<size_t>(sorted_cursor)]];
			descriptor_counts[static_cast<size_t>(atom.descriptor_id)]++;
			if ((atom.passes & PASS_GROUND) != 0) {
				append_gpu_instance(atom, false, page_ground, page_ground_bounds);
			}
			if ((atom.passes & PASS_BODY) != 0) {
				append_gpu_instance(atom, false, page_body, page_body_bounds);
				page_feet_y.push_back(atom.root_y);
				page_semantic_layers.push_back(atom.semantic_layer);
				page_stable_ids.push_back(static_cast<int64_t>(atom.stable_id));
			}
			if ((atom.passes & PASS_SHADOW) != 0 && atom.shadow_enabled) {
				if ((atom.passes & PASS_GROUND) != 0) {
					append_gpu_instance(atom, true, page_shadow, page_shadow_bounds);
				} else {
					append_gpu_instance(atom, true, object_shadow_buffer, object_shadow_bounds);
				}
				world_shadow_count++;
			}
			if ((atom.passes & PASS_EMISSIVE) != 0) {
				append_gpu_instance(atom, false, page_emissive, page_emissive_bounds);
			}
			if ((atom.passes & PASS_OVERHEAD) != 0) {
				append_gpu_instance(atom, false, page_overhead, page_overhead_bounds);
			}
		}
		PackedFloat32Array feet_y;
		feet_y.resize(static_cast<int64_t>(page_feet_y.size()));
		if (!page_feet_y.empty()) {
			std::copy(page_feet_y.begin(), page_feet_y.end(), feet_y.ptrw());
		}
		PackedInt32Array semantic_layers;
		semantic_layers.resize(static_cast<int64_t>(page_semantic_layers.size()));
		if (!page_semantic_layers.empty()) {
			std::copy(page_semantic_layers.begin(), page_semantic_layers.end(), semantic_layers.ptrw());
		}
		PackedInt64Array stable_ids;
		stable_ids.resize(static_cast<int64_t>(page_stable_ids.size()));
		if (!page_stable_ids.empty()) {
			std::copy(page_stable_ids.begin(), page_stable_ids.end(), stable_ids.ptrw());
		}
		Dictionary page;
		page["page_y"] = page_y;
		page["ground_buffer"] = pack(page_ground);
		page["ground_bounds"] = page_ground_bounds.to_rect();
		page["ground_count"] = page_ground_count;
		page["body_buffer"] = pack(page_body);
		page["body_feet_y"] = feet_y;
		page["body_semantic_layers"] = semantic_layers;
		page["body_stable_ids"] = stable_ids;
		page["body_bounds"] = page_body_bounds.to_rect();
		page["body_instance_count"] = page_body_count;
		page["static_instance_count"] = page_body_count;
		page["instance_count"] = page_ground_count + page_body_count;
		page["shadow_buffer"] = pack(page_shadow);
		page["shadow_bounds"] = page_shadow_bounds.to_rect();
		page["shadow_count"] = page_shadow_count;
		page["emissive_buffer"] = pack(page_emissive);
		page["emissive_bounds"] = page_emissive_bounds.to_rect();
		page["emissive_count"] = page_emissive_count;
		page["overhead_buffer"] = pack(page_overhead);
		page["overhead_bounds"] = page_overhead_bounds.to_rect();
		page["overhead_count"] = page_overhead_count;
		pages.append(page);
		if (page_ground_count + page_body_count + page_shadow_count +
				page_emissive_count + page_overhead_count > 0) {
			occupied_page_count++;
		}
		total_buffer_float_count += page_ground.size() + page_body.size() + page_shadow.size() +
				page_emissive.size() + page_overhead.size();
	}
	total_buffer_float_count += object_shadow_buffer.size();
	PackedInt32Array packed_descriptor_counts;
	packed_descriptor_counts.resize(MAX_RENDER_DESCRIPTORS);
	int32_t *packed_descriptor_counts_write = packed_descriptor_counts.ptrw();
	for (int64_t descriptor_index = 0; descriptor_index < MAX_RENDER_DESCRIPTORS; descriptor_index++) {
		packed_descriptor_counts_write[descriptor_index] =
				static_cast<int32_t>(descriptor_counts[descriptor_index]);
	}

	Dictionary result;
	result["success"] = true;
	result["pages"] = pages;
	result["page_window_min_y"] = page_window_min_y;
	result["page_window_max_y"] = page_window_max_y;
	result["world_shadow_count"] = world_shadow_count;
	result["object_shadow_buffer"] = pack(object_shadow_buffer);
	result["object_shadow_bounds"] = object_shadow_bounds.to_rect();
	result["object_shadow_count"] = static_cast<int64_t>(object_shadow_buffer.size() / GPU_STRIDE);
	result["spore_buffer"] = pack(spore_buffer);
	result["instance_count"] = static_cast<int64_t>(atoms.size());
	result["descriptor_counts"] = packed_descriptor_counts;
	result["source_binding_count"] = static_cast<int64_t>(bindings.size());
	result["spore_bounds"] = spore_bounds.to_rect();
	result["spore_count"] = static_cast<int64_t>(spore_buffer.size() / SOURCE_STRIDE);
	result["buffer_float_count"] = total_buffer_float_count;
	result["render_page_count"] = occupied_page_count;
	result["render_page_slot_count"] = pages.size();
	result["render_atom_stride_bytes"] = static_cast<int64_t>(sizeof(RenderAtom));
	result["cpu_render_atom_capacity_bytes"] =
			MAX_VISIBLE_INSTANCES * static_cast<int64_t>(sizeof(RenderAtom));
	result["cpu_sort_index_capacity_bytes"] =
			MAX_VISIBLE_INSTANCES * static_cast<int64_t>(sizeof(size_t));
	result["cpu_snapshot_working_set_bound_bytes"] = CPU_SNAPSHOT_WORKING_SET_BOUND_BYTES;
	return result;
}

Dictionary compose_actor_snapshot(
		const Dictionary &p_static_snapshot,
		const Array &p_actor_records) {
	if (!static_cast<bool>(p_static_snapshot.get("success", false))) {
		return error_result("world_render_buffer: cannot compose actors into an unsuccessful static snapshot");
	}
	if (p_actor_records.size() > MAX_VISIBLE_ACTORS) {
		return error_result("world_render_buffer: visible actor hard bound exceeded");
	}
	const Variant static_pages_value = p_static_snapshot.get("pages", Variant());
	if (static_pages_value.get_type() != Variant::ARRAY) {
		return error_result("world_render_buffer: static snapshot pages are not an Array");
	}

	std::map<int64_t, Dictionary> static_pages;
	const Array source_pages = static_pages_value;
	int64_t window_min_y = 0;
	int64_t window_max_y = -1;
	for (int64_t page_index = 0; page_index < source_pages.size(); ++page_index) {
		const Variant page_value = source_pages[page_index];
		if (page_value.get_type() != Variant::DICTIONARY) {
			return error_result("world_render_buffer: static render page is not a Dictionary");
		}
		const Dictionary page = page_value;
		const int64_t page_y = static_cast<int64_t>(page.get("page_y", 0));
		if (static_pages.find(page_y) != static_pages.end()) {
			return error_result("world_render_buffer: static snapshot contains duplicate absolute page_y");
		}
		static_pages.emplace(page_y, page);
		if (window_max_y < window_min_y) {
			window_min_y = page_y;
			window_max_y = page_y;
		} else {
			window_min_y = std::min(window_min_y, page_y);
			window_max_y = std::max(window_max_y, page_y);
		}
	}

	std::vector<ParsedActorInstance> actors;
	actors.reserve(static_cast<size_t>(p_actor_records.size()));
	for (int64_t actor_index = 0; actor_index < p_actor_records.size(); ++actor_index) {
		const Variant record_value = p_actor_records[actor_index];
		if (record_value.get_type() != Variant::DICTIONARY) {
			return error_result("world_render_buffer: actor record is not a Dictionary");
		}
		ParsedActorInstance actor;
		String error;
		if (!parse_actor_record(record_value, actor, error)) {
			return error_result(error);
		}
		if (window_max_y < window_min_y) {
			window_min_y = actor.page_y;
			window_max_y = actor.page_y;
		} else {
			window_min_y = std::min(window_min_y, actor.page_y);
			window_max_y = std::max(window_max_y, actor.page_y);
		}
		actors.push_back(actor);
	}
	if (window_max_y >= window_min_y &&
			window_max_y - window_min_y + 1 > MAX_RENDER_PAGE_SPAN) {
		return error_result("world_render_buffer: composed absolute render-page span exceeds the bounded slot window");
	}

	std::stable_sort(actors.begin(), actors.end(), [](const ParsedActorInstance &p_a, const ParsedActorInstance &p_b) {
		return painter_key_less(
				p_a.body.feet_y, p_a.body.semantic_layer, p_a.body.stable_id,
				p_b.body.feet_y, p_b.body.semantic_layer, p_b.body.stable_id);
	});
	std::map<int64_t, std::vector<const ParsedActorInstance *>> actors_by_page;
	std::vector<float> actor_shadow_buffer;
	Bounds2D actor_shadow_bounds;
	for (const ParsedActorInstance &actor : actors) {
		actors_by_page[actor.page_y].push_back(&actor);
		if (actor.has_shadow) {
			actor_shadow_buffer.insert(
					actor_shadow_buffer.end(),
					actor.shadow.begin(),
					actor.shadow.end());
			include_unit_quad(actor.shadow.data(), actor_shadow_bounds);
		}
	}

	Array pages;
	PackedInt32Array actor_page_slots;
	int64_t occupied_page_count = 0;
	for (int64_t page_y = window_min_y; page_y <= window_max_y; ++page_y) {
		Dictionary page;
		const auto static_page_iterator = static_pages.find(page_y);
		if (static_page_iterator != static_pages.end()) {
			// Copy only the small page dictionary. Packed buffers remain shared by
			// reference and detach only for the actor-touched page fields replaced
			// below; an interactive update must never deep-copy the static window.
			page = static_page_iterator->second.duplicate(false);
		}
		page["page_y"] = page_y;
		const auto actors_iterator = actors_by_page.find(page_y);
		// The immutable static page is already sorted and packed. Preserve it by
		// reference/copy-on-write when this interactive update does not touch it.
		if (static_page_iterator != static_pages.end() &&
				actors_iterator == actors_by_page.end()) {
			page["actor_instance_count"] = 0;
			pages.append(page);
			if (static_cast<int64_t>(page.get("instance_count", 0)) > 0) {
				occupied_page_count++;
			}
			continue;
		}
		const Variant body_buffer_value = page.get("body_buffer", PackedFloat32Array());
		const Variant feet_y_value = page.get("body_feet_y", PackedFloat32Array());
		const Variant semantic_layers_value = page.get("body_semantic_layers", PackedInt32Array());
		const Variant stable_ids_value = page.get("body_stable_ids", PackedInt64Array());
		if (body_buffer_value.get_type() != Variant::PACKED_FLOAT32_ARRAY ||
				feet_y_value.get_type() != Variant::PACKED_FLOAT32_ARRAY ||
				semantic_layers_value.get_type() != Variant::PACKED_INT32_ARRAY ||
				stable_ids_value.get_type() != Variant::PACKED_INT64_ARRAY) {
			return error_result("world_render_buffer: static page painter metadata has invalid types");
		}
		const PackedFloat32Array static_body = body_buffer_value;
		const PackedFloat32Array static_feet_y = feet_y_value;
		const PackedInt32Array static_semantic_layers = semantic_layers_value;
		const PackedInt64Array static_stable_ids = stable_ids_value;
		if (static_body.size() % GPU_STRIDE != 0) {
			return error_result("world_render_buffer: static page body buffer violates 16-float GPU stride");
		}
		const int64_t static_count = static_body.size() / GPU_STRIDE;
		if (static_feet_y.size() != static_count ||
				static_semantic_layers.size() != static_count ||
				static_stable_ids.size() != static_count) {
			return error_result("world_render_buffer: static page painter metadata count mismatch");
		}

		const int64_t page_actor_count = actors_iterator == actors_by_page.end()
				? 0
				: static_cast<int64_t>(actors_iterator->second.size());
		const int64_t composed_count = static_count + page_actor_count;
		const float *static_gpu = static_body.ptr();
		for (int64_t instance_index = 0; instance_index < static_count; ++instance_index) {
			const int64_t stable_id = static_stable_ids[instance_index];
			if (!std::isfinite(static_feet_y[instance_index]) || stable_id < 0 ||
					!finite_gpu_instance(static_gpu + instance_index * GPU_STRIDE)) {
				return error_result("world_render_buffer: static page contains invalid painter data");
			}
			if (instance_index > 0 && painter_key_less(
					static_feet_y[instance_index], static_semantic_layers[instance_index],
					static_cast<uint64_t>(stable_id),
					static_feet_y[instance_index - 1], static_semantic_layers[instance_index - 1],
					static_cast<uint64_t>(static_stable_ids[instance_index - 1]))) {
				return error_result("world_render_buffer: static page painter data is not sorted");
			}
		}
		if (actors_iterator != actors_by_page.end()) {
			const int64_t slot = page_y - window_min_y;
			actor_page_slots.append(static_cast<int32_t>(slot));
		}

		// Both input streams already have the worker's exact painter order. Merge
		// directly into final packed storage; static density must not add another
		// comparison sort or temporary instance copy to every actor update.
		PackedFloat32Array body;
		body.resize(composed_count * GPU_STRIDE);
		PackedFloat32Array packed_feet_y;
		packed_feet_y.resize(composed_count);
		PackedInt32Array packed_semantic_layers;
		packed_semantic_layers.resize(composed_count);
		PackedInt64Array packed_stable_ids;
		packed_stable_ids.resize(composed_count);
		float *body_write = body.ptrw();
		float *feet_y_write = packed_feet_y.ptrw();
		int32_t *semantic_layers_write = packed_semantic_layers.ptrw();
		int64_t *stable_ids_write = packed_stable_ids.ptrw();
		Bounds2D body_bounds;
		int64_t static_cursor = 0;
		int64_t actor_cursor = 0;
		for (int64_t output_index = 0; output_index < composed_count; ++output_index) {
			const ComposedBodyInstance *actor = actor_cursor < page_actor_count
					? &actors_iterator->second[static_cast<size_t>(actor_cursor)]->body
					: nullptr;
			const bool take_actor = actor != nullptr &&
					(static_cursor == static_count || painter_key_less(
							actor->feet_y, actor->semantic_layer, actor->stable_id,
							static_feet_y[static_cursor], static_semantic_layers[static_cursor],
							static_cast<uint64_t>(static_stable_ids[static_cursor])));
			const float *instance_gpu;
			if (take_actor) {
				instance_gpu = actor->gpu.data();
				feet_y_write[output_index] = actor->feet_y;
				semantic_layers_write[output_index] = actor->semantic_layer;
				stable_ids_write[output_index] = static_cast<int64_t>(actor->stable_id);
				actor_cursor++;
			} else {
				instance_gpu = static_gpu + static_cursor * GPU_STRIDE;
				feet_y_write[output_index] = static_feet_y[static_cursor];
				semantic_layers_write[output_index] = static_semantic_layers[static_cursor];
				stable_ids_write[output_index] = static_stable_ids[static_cursor];
				static_cursor++;
			}
			std::copy(instance_gpu, instance_gpu + GPU_STRIDE,
					body_write + output_index * GPU_STRIDE);
			include_unit_quad(instance_gpu, body_bounds);
		}
		page["body_buffer"] = body;
		page["body_feet_y"] = packed_feet_y;
		page["body_semantic_layers"] = packed_semantic_layers;
		page["body_stable_ids"] = packed_stable_ids;
		page["body_bounds"] = body_bounds.to_rect();
		page["body_instance_count"] = composed_count;
		page["instance_count"] = static_cast<int64_t>(page.get("ground_count", 0)) +
				composed_count;
		page["static_instance_count"] = static_count;
		page["actor_instance_count"] = page_actor_count;
		pages.append(page);
		if (static_cast<int64_t>(page.get("instance_count", 0)) > 0 ||
				static_cast<int64_t>(page.get("emissive_count", 0)) > 0 ||
				static_cast<int64_t>(page.get("overhead_count", 0)) > 0) {
			occupied_page_count++;
		}
	}

	// Snapshot metadata is shallow-copied for the same reason: `pages` and the
	// actor streams below replace the only interactive fields, while immutable
	// static/ground buffers retain copy-on-write storage.
	Dictionary result = p_static_snapshot.duplicate(false);
	result["success"] = true;
	result["pages"] = pages;
	result["page_window_min_y"] = window_min_y;
	result["page_window_max_y"] = window_max_y;
	result["render_page_count"] = occupied_page_count;
	result["render_page_slot_count"] = pages.size();
	result["actor_page_slots"] = actor_page_slots;
	result["actor_shadow_buffer"] = pack(actor_shadow_buffer);
	result["actor_shadow_bounds"] = actor_shadow_bounds.to_rect();
	result["actor_shadow_count"] = static_cast<int64_t>(actor_shadow_buffer.size() / GPU_STRIDE);
	result["actor_count"] = static_cast<int64_t>(actors.size());
	result["instance_count"] = static_cast<int64_t>(p_static_snapshot.get("instance_count", 0)) +
			static_cast<int64_t>(actors.size());
	result["buffer_float_count"] = static_cast<int64_t>(p_static_snapshot.get("buffer_float_count", 0)) +
			static_cast<int64_t>(actors.size()) * GPU_STRIDE +
			static_cast<int64_t>(actor_shadow_buffer.size());
	return result;
}

Dictionary build_ground_field_snapshot(
		const PackedVector2Array &p_chunk_origins,
		const Array &p_grass_results) {
	Dictionary result;
	result["success"] = false;
	if (p_chunk_origins.is_empty() || p_chunk_origins.size() != p_grass_results.size()) {
		result["error"] = "ground field snapshot requires matching non-empty origins/results";
		return result;
	}
	const Variant first_value = p_grass_results[0];
	if (first_value.get_type() != Variant::DICTIONARY) {
		result["error"] = "ground field snapshot first result is not a Dictionary";
		return result;
	}
	const Dictionary first = first_value;
	const int32_t nodes = static_cast<int32_t>(first.get("visual_field_grid_nodes", 0));
	const float step_px = static_cast<float>(first.get("visual_field_step_px", 0.0));
	if (nodes < 2 || !std::isfinite(step_px) || step_px <= 0.0f) {
		result["error"] = "ground field snapshot has invalid tile geometry";
		return result;
	}
	const float chunk_size_px = step_px * static_cast<float>(nodes - 1);
	float min_x = p_chunk_origins[0].x;
	float min_y = p_chunk_origins[0].y;
	float max_x = min_x;
	float max_y = min_y;
	for (int64_t index = 1; index < p_chunk_origins.size(); ++index) {
		const Vector2 origin = p_chunk_origins[index];
		min_x = std::min(min_x, origin.x);
		min_y = std::min(min_y, origin.y);
		max_x = std::max(max_x, origin.x);
		max_y = std::max(max_y, origin.y);
	}
	const int32_t chunk_columns = static_cast<int32_t>(std::lround((max_x - min_x) / chunk_size_px)) + 1;
	const int32_t chunk_rows = static_cast<int32_t>(std::lround((max_y - min_y) / chunk_size_px)) + 1;
	if (chunk_columns <= 0 || chunk_rows <= 0 ||
			static_cast<int64_t>(chunk_columns) * chunk_rows != p_chunk_origins.size()) {
		result["error"] = "ground field snapshot origins are not one dense rectangular grid";
		return result;
	}
	const int32_t width = chunk_columns * (nodes - 1) + 1;
	const int32_t height = chunk_rows * (nodes - 1) + 1;
	constexpr int32_t channel_count = 4;
	constexpr int32_t texture_count = 4;
	const int64_t output_bytes = static_cast<int64_t>(width) * height * channel_count;
	std::array<PackedByteArray, texture_count> textures;
	for (PackedByteArray &texture : textures) {
		texture.resize(output_bytes);
	}
	std::vector<uint8_t> occupied(static_cast<size_t>(chunk_columns * chunk_rows), 0U);
	for (int64_t index = 0; index < p_chunk_origins.size(); ++index) {
		const Variant value = p_grass_results[index];
		if (value.get_type() != Variant::DICTIONARY) {
			result["error"] = "ground field snapshot result is not a Dictionary";
			return result;
		}
		const Dictionary grass = value;
		if (static_cast<int32_t>(grass.get("visual_field_grid_nodes", 0)) != nodes ||
				std::abs(static_cast<float>(grass.get("visual_field_step_px", 0.0)) - step_px) > 0.001f) {
			result["error"] = "ground field snapshot tile geometry mismatch";
			return result;
		}
		const Vector2 origin = p_chunk_origins[index];
		const int32_t chunk_x = static_cast<int32_t>(std::lround((origin.x - min_x) / chunk_size_px));
		const int32_t chunk_y = static_cast<int32_t>(std::lround((origin.y - min_y) / chunk_size_px));
		if (chunk_x < 0 || chunk_x >= chunk_columns || chunk_y < 0 || chunk_y >= chunk_rows) {
			result["error"] = "ground field snapshot chunk lies outside resolved grid";
			return result;
		}
		const int32_t occupancy_index = chunk_y * chunk_columns + chunk_x;
		if (occupied[static_cast<size_t>(occupancy_index)] != 0U) {
			result["error"] = "ground field snapshot contains duplicate chunk origin";
			return result;
		}
		occupied[static_cast<size_t>(occupancy_index)] = 1U;
		for (int32_t texture_index = 0; texture_index < texture_count; ++texture_index) {
			const String key = String("visual_field_") + String::num_int64(texture_index);
			const Variant tile_value = grass.get(key, PackedByteArray());
			if (tile_value.get_type() != Variant::PACKED_BYTE_ARRAY) {
				result["error"] = "ground field snapshot tile has invalid payload type";
				return result;
			}
			const PackedByteArray tile = tile_value;
			if (tile.size() != static_cast<int64_t>(nodes) * nodes * channel_count) {
				result["error"] = "ground field snapshot tile payload size mismatch";
				return result;
			}
			const uint8_t *source = tile.ptr();
			uint8_t *destination = textures[texture_index].ptrw();
			const int32_t base_x = chunk_x * (nodes - 1);
			const int32_t base_y = chunk_y * (nodes - 1);
			for (int32_t row = 0; row < nodes; ++row) {
				const int64_t source_offset = static_cast<int64_t>(row) * nodes * channel_count;
				const int64_t destination_offset =
						(static_cast<int64_t>(base_y + row) * width + base_x) * channel_count;
				std::copy(
						source + source_offset,
						source + source_offset + static_cast<int64_t>(nodes) * channel_count,
						destination + destination_offset);
			}
		}
	}
	result["success"] = true;
	result["origin_world"] = Vector2(min_x, min_y);
	result["step_px"] = step_px;
	result["width"] = width;
	result["height"] = height;
	result["field_0"] = textures[0];
	result["field_1"] = textures[1];
	result["field_2"] = textures[2];
	result["field_3"] = textures[3];
	result["payload_bytes"] = output_bytes * texture_count;
	return result;
}

} // namespace world_render_buffer
