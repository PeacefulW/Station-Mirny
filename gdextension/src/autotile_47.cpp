#include "autotile_47.h"

#include <algorithm>
#include <array>
#include <vector>

namespace autotile_47 {

namespace {

constexpr int64_t k_variant_seed_offset = 907;

struct SignatureEntry {
	uint8_t code = 0U;
	uint8_t edge_count = 0U;
	uint8_t notch_count = 0U;
};

uint8_t count_bits(uint8_t p_value) {
	uint8_t count = 0U;
	uint8_t bits = p_value;
	while (bits != 0U) {
		count = static_cast<uint8_t>(count + (bits & 1U));
		bits = static_cast<uint8_t>(bits >> 1U);
	}
	return count;
}

uint8_t build_signature_code(bool p_n, bool p_ne, bool p_e, bool p_se, bool p_s, bool p_sw, bool p_w, bool p_nw) {
	const uint8_t open_n = p_n ? 0U : 1U;
	const uint8_t open_e = p_e ? 0U : 1U;
	const uint8_t open_s = p_s ? 0U : 1U;
	const uint8_t open_w = p_w ? 0U : 1U;
	const uint8_t notch_ne = (p_n && p_e && !p_ne) ? 1U : 0U;
	const uint8_t notch_se = (p_s && p_e && !p_se) ? 1U : 0U;
	const uint8_t notch_sw = (p_s && p_w && !p_sw) ? 1U : 0U;
	const uint8_t notch_nw = (p_n && p_w && !p_nw) ? 1U : 0U;
	return static_cast<uint8_t>(
		(open_n << 7U) |
		(open_e << 6U) |
		(open_s << 5U) |
		(open_w << 4U) |
		(notch_ne << 3U) |
		(notch_se << 2U) |
		(notch_sw << 1U) |
		notch_nw
	);
}

uint32_t hash2d(int64_t p_x, int64_t p_y, int64_t p_seed) {
	uint64_t value = static_cast<uint64_t>(p_x * 374761393LL + p_y * 668265263LL + p_seed * 1442695041LL);
	uint32_t hashed = static_cast<uint32_t>(value & 0xffffffffULL);
	hashed = static_cast<uint32_t>((hashed ^ (hashed >> 13U)) & 0xffffffffU);
	hashed = static_cast<uint32_t>((static_cast<uint64_t>(hashed) * 1274126177ULL) & 0xffffffffULL);
	hashed = static_cast<uint32_t>((hashed ^ (hashed >> 16U)) & 0xffffffffU);
	return hashed;
}

const std::array<int16_t, 256> &get_catalog_index_by_code() {
	static const std::array<int16_t, 256> catalog_index_by_code = []() {
		std::array<int16_t, 256> lookup{};
		lookup.fill(-1);
		std::array<bool, 256> seen{};
		std::vector<SignatureEntry> entries;
		entries.reserve(47);

		for (int mask = 0; mask < 256; ++mask) {
			const uint8_t code = build_signature_code(
				(mask & 1) != 0,
				(mask & 2) != 0,
				(mask & 4) != 0,
				(mask & 8) != 0,
				(mask & 16) != 0,
				(mask & 32) != 0,
				(mask & 64) != 0,
				(mask & 128) != 0
			);
			if (seen[code]) {
				continue;
			}
			seen[code] = true;
			entries.push_back(SignatureEntry{
				code,
				count_bits(static_cast<uint8_t>((code >> 4U) & 0x0fU)),
				count_bits(static_cast<uint8_t>(code & 0x0fU)),
			});
		}

		std::sort(entries.begin(), entries.end(), [](const SignatureEntry &p_a, const SignatureEntry &p_b) {
			if (p_a.edge_count != p_b.edge_count) {
				return p_a.edge_count < p_b.edge_count;
			}
			if (p_a.notch_count != p_b.notch_count) {
				return p_a.notch_count < p_b.notch_count;
			}
			return p_a.code < p_b.code;
		});

		for (size_t index = 0; index < entries.size(); ++index) {
			lookup[entries[index].code] = static_cast<int16_t>(index);
		}
		return lookup;
	}();
	return catalog_index_by_code;
}

} // namespace

int64_t resolve_atlas_index(
	bool p_n,
	bool p_ne,
	bool p_e,
	bool p_se,
	bool p_s,
	bool p_sw,
	bool p_w,
	bool p_nw,
	int64_t p_world_x,
	int64_t p_world_y,
	int64_t p_seed,
	int64_t p_variant_count
) {
	const uint8_t code = build_signature_code(p_n, p_ne, p_e, p_se, p_s, p_sw, p_w, p_nw);
	const int16_t base_index = get_catalog_index_by_code()[code];
	if (base_index < 0) {
		return 0;
	}
	const int64_t safe_variant_count = std::max<int64_t>(1, p_variant_count);
	const int64_t variant_index = static_cast<int64_t>(hash2d(p_world_x, p_world_y, p_seed + k_variant_seed_offset) % static_cast<uint32_t>(safe_variant_count));
	return variant_index * k_case_count + static_cast<int64_t>(base_index);
}

} // namespace autotile_47
