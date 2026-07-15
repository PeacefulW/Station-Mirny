#include "object_presentation_buffer.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

namespace object_presentation {
namespace {

constexpr uint8_t OBJECT_KIND_LIVING_FLORA = 2;
constexpr uint8_t OBJECT_KIND_SPIKY_FLORA = 3;
constexpr uint8_t OBJECT_KIND_TREE = 4;
constexpr uint8_t OBJECT_KIND_SMALL_ROCK = 7;
constexpr int32_t BUFFER_STRIDE = 12;
constexpr int32_t COLLISION_RECORD_STRIDE = 3;
constexpr int32_t MAX_DEPTH_STRIPE_COUNT = 4096;

struct Metric {
	float frame_width_px = 0.0f;
	float frame_height_px = 0.0f;
	float anchor_x_px = 0.0f;
	float anchor_y_px = 0.0f;
	float scale_or_visible_width = 0.0f;
};

Dictionary make_empty_result() {
	Dictionary result;
	result["tree_atlas_bucket_buffers"] = Array();
	result["rock_atlas_bucket_buffers"] = Array();
	result["living_flora_bucket_buffers"] = Array();
	result["living_flora_shadow_buffer"] = PackedFloat32Array();
	result["spiky_flora_atlas_bucket_buffers"] = Array();
	result["spiky_flora_atlas_bank_count"] = 0;
	result["tree_collision_records"] = PackedFloat32Array();
	result["object_count"] = 0;
	result["tree_instance_count"] = 0;
	result["rock_instance_count"] = 0;
	result["living_flora_count"] = 0;
	result["spiky_flora_count"] = 0;
	result["living_flora_record_count"] = 0;
	result["spiky_flora_record_count"] = 0;
	result["suppressed_instance_count"] = 0;
	result["ignored_instance_count"] = 0;
	result["buffer_float_count"] = 0;
	result["payload_bytes"] = 0;
	return result;
}

bool is_finite(float p_value) {
	return std::isfinite(static_cast<double>(p_value));
}

bool decode_metrics(
		const PackedFloat32Array &p_packed,
		const char *p_family,
		std::vector<Metric> &r_metrics,
		String &r_error) {
	if (p_packed.size() % METRIC_STRIDE != 0) {
		r_error = String("object_presentation: ") + p_family + " metrics size is not divisible by METRIC_STRIDE";
		return false;
	}
	const int64_t metric_count = p_packed.size() / METRIC_STRIDE;
	if (metric_count > 256) {
		r_error = String("object_presentation: ") + p_family + " metric count exceeds byte atlas frame capacity";
		return false;
	}
	r_metrics.resize(static_cast<size_t>(metric_count));
	const float *packed = p_packed.ptr();
	for (int64_t index = 0; index < metric_count; ++index) {
		const int64_t offset = index * METRIC_STRIDE;
		Metric metric;
		metric.frame_width_px = packed[offset + METRIC_FRAME_WIDTH_PX];
		metric.frame_height_px = packed[offset + METRIC_FRAME_HEIGHT_PX];
		metric.anchor_x_px = packed[offset + METRIC_ANCHOR_X_PX];
		metric.anchor_y_px = packed[offset + METRIC_ANCHOR_Y_PX];
		metric.scale_or_visible_width = packed[offset + METRIC_SCALE_OR_VISIBLE_WIDTH];
		if (!is_finite(metric.frame_width_px) || metric.frame_width_px <= 0.0f ||
				!is_finite(metric.frame_height_px) || metric.frame_height_px <= 0.0f ||
				!is_finite(metric.anchor_x_px) || !is_finite(metric.anchor_y_px) ||
				!is_finite(metric.scale_or_visible_width) || metric.scale_or_visible_width <= 0.0f) {
			r_error = String("object_presentation: invalid ") + p_family + " metric at index " + String::num_int64(index);
			return false;
		}
		r_metrics[static_cast<size_t>(index)] = metric;
	}
	return true;
}

void append_instance(std::vector<float> &r_buffer, const float p_instance[BUFFER_STRIDE]) {
	r_buffer.insert(r_buffer.end(), p_instance, p_instance + BUFFER_STRIDE);
}

PackedFloat32Array pack_vector(const std::vector<float> &p_source) {
	PackedFloat32Array packed;
	packed.resize(static_cast<int64_t>(p_source.size()));
	if (!p_source.empty()) {
		std::copy(p_source.begin(), p_source.end(), packed.ptrw());
	}
	return packed;
}

Array pack_buckets(const std::vector<std::vector<float>> &p_buckets) {
	Array result;
	result.resize(static_cast<int64_t>(p_buckets.size()));
	for (size_t index = 0; index < p_buckets.size(); ++index) {
		result[static_cast<int64_t>(index)] = pack_vector(p_buckets[index]);
	}
	return result;
}

Array pack_atlas_buckets(const std::vector<std::vector<std::vector<float>>> &p_atlas_buckets) {
	Array result;
	result.resize(static_cast<int64_t>(p_atlas_buckets.size()));
	for (size_t atlas_index = 0; atlas_index < p_atlas_buckets.size(); ++atlas_index) {
		result[static_cast<int64_t>(atlas_index)] = pack_buckets(p_atlas_buckets[atlas_index]);
	}
	return result;
}

int32_t depth_stripe_for(float p_root_y, float p_stripe_px, int32_t p_stripe_count) {
	const int64_t raw = static_cast<int64_t>(std::floor(p_root_y / p_stripe_px));
	return static_cast<int32_t>(std::clamp<int64_t>(raw, 0, p_stripe_count - 1));
}

void build_instance(
		float p_root_x,
		float p_root_y,
		float p_width,
		float p_height,
		const Metric &p_metric,
		float p_scale,
		size_t p_atlas_frame_index,
		uint8_t p_tint,
		uint8_t p_phase,
		float r_instance[BUFFER_STRIDE]) {
	const float center_x = p_metric.frame_width_px * 0.5f;
	const float center_y = p_metric.frame_height_px * 0.5f;
	const float origin_x = p_root_x - (p_metric.anchor_x_px - center_x) * p_scale;
	const float origin_y = p_root_y - (p_metric.anchor_y_px - center_y) * p_scale;
	const float tint = static_cast<float>(p_tint) / 255.0f;
	const float phase = static_cast<float>(p_phase) / 255.0f;
	const float instance[BUFFER_STRIDE] = {
		p_width, 0.0f, 0.0f, origin_x,
		0.0f, p_height, 0.0f, origin_y,
		static_cast<float>(p_atlas_frame_index) / 255.0f, tint, phase, 1.0f,
	};
	std::copy(instance, instance + BUFFER_STRIDE, r_instance);
}

void build_classic_decor_instance(
		float p_position_x,
		float p_position_y,
		float p_width,
		float p_height,
		uint8_t p_frame,
		uint8_t p_tint,
		uint8_t p_phase,
		float p_alpha,
		float r_instance[BUFFER_STRIDE]) {
	const float tint = static_cast<float>(p_tint) / 255.0f;
	const float phase = static_cast<float>(p_phase) / 255.0f;
	const float instance[BUFFER_STRIDE] = {
		p_width, 0.0f, 0.0f, p_position_x,
		0.0f, p_height, 0.0f, p_position_y,
		static_cast<float>(p_frame) / 255.0f, tint, phase, p_alpha,
	};
	std::copy(instance, instance + BUFFER_STRIDE, r_instance);
}

void build_classic_shadow_instance(
		float p_position_x,
		float p_position_y,
		float p_width,
		float p_height,
		float p_shadow_scale,
		float p_alpha,
		float r_instance[BUFFER_STRIDE]) {
	// This is the raw color encoding produced by the legacy
	// WorldDecorBatchLayer before assigning a shadow MultiMesh.
	const float instance[BUFFER_STRIDE] = {
		p_width, 0.0f, 0.0f, p_position_x,
		0.0f, p_height, 0.0f, p_position_y,
		std::clamp(p_shadow_scale / 4.0f, 0.0f, 1.0f),
		1.0f / std::max(1.0f, p_width),
		1.0f / std::max(1.0f, p_height),
		std::clamp(p_alpha, 0.0f, 1.0f),
	};
	std::copy(instance, instance + BUFFER_STRIDE, r_instance);
}

} // namespace

Dictionary build_buffers(
		const PackedByteArray &p_object_kind,
		const PackedByteArray &p_object_local_x_px_q4,
		const PackedByteArray &p_object_local_y_px_q4,
		const PackedByteArray &p_object_size_px,
		const PackedByteArray &p_object_atlas_index,
		const PackedByteArray &p_object_variant,
		const PackedByteArray &p_object_flags,
		const PackedByteArray &p_object_tint,
		const PackedByteArray &p_object_phase,
		const PackedFloat32Array &p_tree_metrics,
		const PackedFloat32Array &p_rock_metrics,
		const PackedFloat32Array &p_params) {
	Dictionary result = make_empty_result();
	const int64_t object_count = p_object_kind.size();
	const int64_t array_sizes[] = {
		p_object_local_x_px_q4.size(),
		p_object_local_y_px_q4.size(),
		p_object_size_px.size(),
		p_object_atlas_index.size(),
		p_object_variant.size(),
		p_object_flags.size(),
		p_object_tint.size(),
		p_object_phase.size(),
	};
	for (const int64_t size : array_sizes) {
		if (size != object_count) {
			result["error"] = "object_presentation: object_* arrays must have identical length";
			return result;
		}
	}
	if (p_params.size() < PARAM_COUNT) {
		result["error"] = "object_presentation: params size is smaller than PARAM_COUNT";
		return result;
	}

	const float *params = p_params.ptr();
	const float local_px_quantum = params[PARAM_LOCAL_PX_QUANTUM];
	const float depth_stripe_px = params[PARAM_DEPTH_STRIPE_PX];
	const float stripe_count_f = params[PARAM_DEPTH_STRIPE_COUNT];
	const float collision_scale = params[PARAM_TREE_COLLISION_RADIUS_SCALE];
	const float collision_min = params[PARAM_TREE_COLLISION_MIN_RADIUS_PX];
	const float collision_max = params[PARAM_TREE_COLLISION_MAX_RADIUS_PX];
	const float decor_depth_anchor_y_scale = params[PARAM_DECOR_DEPTH_ANCHOR_Y_SCALE];
	const float spiky_atlas_bank_count_f = params[PARAM_SPIKY_ATLAS_BANK_COUNT];
	const float living_alpha = params[PARAM_LIVING_ALPHA];
	const float spiky_alpha = params[PARAM_SPIKY_ALPHA];
	const float living_shadow_width_scale = params[PARAM_LIVING_SHADOW_WIDTH_SCALE];
	const float living_shadow_height_scale = params[PARAM_LIVING_SHADOW_HEIGHT_SCALE];
	const float living_shadow_center_y_scale = params[PARAM_LIVING_SHADOW_CENTER_Y_SCALE];
	const float living_shadow_min_width_px = params[PARAM_LIVING_SHADOW_MIN_WIDTH_PX];
	const float living_shadow_min_height_px = params[PARAM_LIVING_SHADOW_MIN_HEIGHT_PX];
	const float living_shadow_alpha = params[PARAM_LIVING_SHADOW_ALPHA];
	const float living_shadow_size_divisor = params[PARAM_LIVING_SHADOW_SIZE_DIVISOR];
	const float living_shadow_min_scale = params[PARAM_LIVING_SHADOW_MIN_SCALE];
	const float living_presentation_enabled_f = params[PARAM_LIVING_PRESENTATION_ENABLED];
	const float spiky_presentation_enabled_f = params[PARAM_SPIKY_PRESENTATION_ENABLED];
	if (!is_finite(local_px_quantum) || local_px_quantum <= 0.0f ||
			!is_finite(depth_stripe_px) || depth_stripe_px <= 0.0f ||
			!is_finite(stripe_count_f) || stripe_count_f < 1.0f || stripe_count_f > MAX_DEPTH_STRIPE_COUNT ||
			!is_finite(collision_scale) || collision_scale < 0.0f ||
			!is_finite(collision_min) || collision_min < 0.0f ||
			!is_finite(collision_max) || collision_max < collision_min ||
			!is_finite(decor_depth_anchor_y_scale) ||
			!is_finite(spiky_atlas_bank_count_f) || spiky_atlas_bank_count_f < 1.0f || spiky_atlas_bank_count_f > 256.0f ||
			!is_finite(living_alpha) || living_alpha < 0.0f || living_alpha > 1.0f ||
			!is_finite(spiky_alpha) || spiky_alpha < 0.0f || spiky_alpha > 1.0f ||
			!is_finite(living_shadow_width_scale) || living_shadow_width_scale < 0.0f ||
			!is_finite(living_shadow_height_scale) || living_shadow_height_scale < 0.0f ||
			!is_finite(living_shadow_center_y_scale) ||
			!is_finite(living_shadow_min_width_px) || living_shadow_min_width_px < 0.0f ||
			!is_finite(living_shadow_min_height_px) || living_shadow_min_height_px < 0.0f ||
			!is_finite(living_shadow_alpha) || living_shadow_alpha < 0.0f || living_shadow_alpha > 1.0f ||
			!is_finite(living_shadow_size_divisor) || living_shadow_size_divisor <= 0.0f ||
			!is_finite(living_shadow_min_scale) || living_shadow_min_scale < 0.0f ||
			!is_finite(living_presentation_enabled_f) ||
			!is_finite(spiky_presentation_enabled_f) ||
			(living_presentation_enabled_f != 0.0f && living_presentation_enabled_f != 1.0f) ||
			(spiky_presentation_enabled_f != 0.0f && spiky_presentation_enabled_f != 1.0f)) {
		result["error"] = "object_presentation: invalid params";
		return result;
	}
	const int32_t depth_stripe_count = static_cast<int32_t>(stripe_count_f);
	const int32_t spiky_atlas_bank_count = static_cast<int32_t>(spiky_atlas_bank_count_f);
	const bool living_presentation_enabled = living_presentation_enabled_f > 0.5f;
	const bool spiky_presentation_enabled = spiky_presentation_enabled_f > 0.5f;
	if (std::fabs(stripe_count_f - static_cast<float>(depth_stripe_count)) > 0.0001f) {
		result["error"] = "object_presentation: depth stripe count must be an integer";
		return result;
	}
	if (std::fabs(spiky_atlas_bank_count_f - static_cast<float>(spiky_atlas_bank_count)) > 0.0001f) {
		result["error"] = "object_presentation: spiky atlas bank count must be an integer";
		return result;
	}

	std::vector<Metric> tree_metrics;
	std::vector<Metric> rock_metrics;
	String metric_error;
	if (!decode_metrics(p_tree_metrics, "tree", tree_metrics, metric_error) ||
			!decode_metrics(p_rock_metrics, "rock", rock_metrics, metric_error)) {
		result["error"] = metric_error;
		return result;
	}

	std::vector<std::vector<float>> tree_atlas_buckets(static_cast<size_t>(depth_stripe_count));
	std::vector<std::vector<float>> rock_atlas_buckets(static_cast<size_t>(depth_stripe_count));
	// These optional families allocate their bucket tables lazily on the first
	// matching packet record. With placement disabled, the warm payload remains
	// three empty values rather than 192 empty PackedFloat32Array objects.
	std::vector<std::vector<float>> living_flora_buckets;
	std::vector<float> living_flora_shadow_buffer;
	std::vector<std::vector<std::vector<float>>> spiky_flora_atlas_buckets;
	std::vector<float> collision_records;

	const uint8_t *kinds = p_object_kind.ptr();
	const uint8_t *xs = p_object_local_x_px_q4.ptr();
	const uint8_t *ys = p_object_local_y_px_q4.ptr();
	const uint8_t *sizes = p_object_size_px.ptr();
	const uint8_t *atlas_indices = p_object_atlas_index.ptr();
	const uint8_t *variants = p_object_variant.ptr();
	const uint8_t *tints = p_object_tint.ptr();
	const uint8_t *phases = p_object_phase.ptr();
	int32_t tree_count = 0;
	int32_t rock_count = 0;
	int32_t living_count = 0;
	int32_t spiky_count = 0;
	int32_t living_record_count = 0;
	int32_t spiky_record_count = 0;
	int32_t suppressed_count = 0;
	int32_t ignored_count = 0;
	for (int64_t index = 0; index < object_count; ++index) {
		const uint8_t kind = kinds[index];
		if (kind == OBJECT_KIND_LIVING_FLORA) {
			living_record_count++;
			if (!living_presentation_enabled) {
				suppressed_count++;
				continue;
			}
			if (living_flora_buckets.empty()) {
				living_flora_buckets.resize(static_cast<size_t>(depth_stripe_count));
			}
			const float root_x = (static_cast<float>(xs[index]) + 0.5f) * local_px_quantum;
			const float root_y = (static_cast<float>(ys[index]) + 0.5f) * local_px_quantum;
			const float size_px = static_cast<float>(sizes[index]);
			const int32_t stripe = depth_stripe_for(
					root_y + size_px * decor_depth_anchor_y_scale,
					depth_stripe_px,
					depth_stripe_count);
			float instance[BUFFER_STRIDE];
			build_classic_decor_instance(
					root_x,
					root_y,
					size_px,
					size_px,
					variants[index],
					tints[index],
					phases[index],
					living_alpha,
					instance);
			append_instance(living_flora_buckets[static_cast<size_t>(stripe)], instance);

			const float shadow_width = std::max(size_px * living_shadow_width_scale, living_shadow_min_width_px);
			const float shadow_height = std::max(size_px * living_shadow_height_scale, living_shadow_min_height_px);
			const float shadow_scale = std::max(size_px / living_shadow_size_divisor, living_shadow_min_scale);
			build_classic_shadow_instance(
					root_x,
					root_y + size_px * living_shadow_center_y_scale,
					shadow_width,
					shadow_height,
					shadow_scale,
					living_shadow_alpha,
					instance);
			append_instance(living_flora_shadow_buffer, instance);
			living_count++;
			continue;
		}
		if (kind == OBJECT_KIND_SPIKY_FLORA) {
			spiky_record_count++;
			if (!spiky_presentation_enabled) {
				suppressed_count++;
				continue;
			}
			const int32_t atlas_index = static_cast<int32_t>(atlas_indices[index]);
			if (atlas_index < 0 || atlas_index >= spiky_atlas_bank_count) {
				result["error"] = "object_presentation: spiky flora atlas index exceeds prepared bank count";
				return result;
			}
			if (spiky_flora_atlas_buckets.empty()) {
				spiky_flora_atlas_buckets.resize(static_cast<size_t>(spiky_atlas_bank_count));
				for (std::vector<std::vector<float>> &atlas_buckets : spiky_flora_atlas_buckets) {
					atlas_buckets.resize(static_cast<size_t>(depth_stripe_count));
				}
			}
			const float root_x = (static_cast<float>(xs[index]) + 0.5f) * local_px_quantum;
			const float root_y = (static_cast<float>(ys[index]) + 0.5f) * local_px_quantum;
			const float size_px = static_cast<float>(sizes[index]);
			const int32_t stripe = depth_stripe_for(
					root_y + size_px * decor_depth_anchor_y_scale,
					depth_stripe_px,
					depth_stripe_count);
			float instance[BUFFER_STRIDE];
			build_classic_decor_instance(
					root_x,
					root_y,
					size_px,
					size_px,
					variants[index],
					tints[index],
					phases[index],
					spiky_alpha,
					instance);
			append_instance(
					spiky_flora_atlas_buckets[static_cast<size_t>(atlas_index)][static_cast<size_t>(stripe)],
					instance);
			spiky_count++;
			continue;
		}
		if (kind != OBJECT_KIND_TREE && kind != OBJECT_KIND_SMALL_ROCK) {
			ignored_count++;
			continue;
		}

		const std::vector<Metric> &metrics = kind == OBJECT_KIND_TREE ? tree_metrics : rock_metrics;
		if (metrics.empty()) {
			result["error"] = kind == OBJECT_KIND_TREE ?
					"object_presentation: tree packet records require tree metrics" :
					"object_presentation: rock packet records require rock metrics";
			return result;
		}
		const uint8_t packet_variant = variants[index];
		const size_t metric_index = static_cast<size_t>(packet_variant) % metrics.size();
		const Metric &metric = metrics[metric_index];
		// Packet coordinates address the centre of a quantum cell, matching the
		// canonical GDScript decoder (q * quantum + quantum * 0.5).
		const float root_x = (static_cast<float>(xs[index]) + 0.5f) * local_px_quantum;
		const float root_y = (static_cast<float>(ys[index]) + 0.5f) * local_px_quantum;
		const int32_t stripe = depth_stripe_for(root_y, depth_stripe_px, depth_stripe_count);
		float scale = metric.scale_or_visible_width;
		if (kind == OBJECT_KIND_SMALL_ROCK) {
			scale = std::clamp(static_cast<float>(sizes[index]), 1.0f, 254.0f) /
					metric.scale_or_visible_width;
		}
		const float width = metric.frame_width_px * scale;
		const float height = metric.frame_height_px * scale;
		float instance[BUFFER_STRIDE];
		build_instance(
				root_x,
				root_y,
				width,
				height,
				metric,
				scale,
				metric_index,
				tints[index],
				phases[index],
				instance);

		if (kind == OBJECT_KIND_TREE) {
			append_instance(tree_atlas_buckets[static_cast<size_t>(stripe)], instance);
			const float radius = std::clamp(static_cast<float>(sizes[index]) * collision_scale, collision_min, collision_max);
			collision_records.push_back(root_x);
			collision_records.push_back(root_y - radius * 0.5f);
			collision_records.push_back(radius);
			tree_count++;
		} else {
			append_instance(rock_atlas_buckets[static_cast<size_t>(stripe)], instance);
			rock_count++;
		}
	}

	result["tree_atlas_bucket_buffers"] = pack_buckets(tree_atlas_buckets);
	result["rock_atlas_bucket_buffers"] = pack_buckets(rock_atlas_buckets);
	result["living_flora_bucket_buffers"] = pack_buckets(living_flora_buckets);
	result["living_flora_shadow_buffer"] = pack_vector(living_flora_shadow_buffer);
	result["spiky_flora_atlas_bucket_buffers"] = pack_atlas_buckets(spiky_flora_atlas_buckets);
	result["spiky_flora_atlas_bank_count"] = spiky_count > 0 ? spiky_atlas_bank_count : 0;
	result["tree_collision_records"] = pack_vector(collision_records);
	result["object_count"] = object_count;
	result["tree_instance_count"] = tree_count;
	result["rock_instance_count"] = rock_count;
	result["living_flora_count"] = living_count;
	result["spiky_flora_count"] = spiky_count;
	result["living_flora_record_count"] = living_record_count;
	result["spiky_flora_record_count"] = spiky_record_count;
	result["suppressed_instance_count"] = suppressed_count;
	result["ignored_instance_count"] = ignored_count;
	const int64_t buffer_float_count = static_cast<int64_t>((tree_count + rock_count + spiky_count) * BUFFER_STRIDE +
			static_cast<int64_t>(living_count) * BUFFER_STRIDE * 2 +
			static_cast<int64_t>(tree_count) * COLLISION_RECORD_STRIDE);
	result["buffer_float_count"] = buffer_float_count;
	result["payload_bytes"] = buffer_float_count * static_cast<int64_t>(sizeof(float));
	return result;
}

} // namespace object_presentation
