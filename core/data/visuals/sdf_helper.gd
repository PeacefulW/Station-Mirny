class_name SdfHelper
extends RefCounted

## Helper for computing a signed distance field (SDF) from a binary rock mask.
##
## SDF is the per-cell distance to the nearest mask boundary, signed positive
## inside the rock region and negative outside. It's the foundation for
## smooth-shaped rock rendering (height field, zone fading, normals from
## gradient) — Variant D shader reads it as a sampler2D and derives height,
## zones, and normals per fragment, the way the old Rust render.rs did.
##
## Brute-force O((W*H)²). For 16×16 chunks this is ~65k ops — well under a
## frame. For 32×32 it's ~1M — still fine for chunk-load amortization.

const ROCK_MASK_VALUE: int = 1

## Compute SDF image from a binary mask. Returns Image FORMAT_R8 where each
## texel encodes (sdf + max_dist) / (2 * max_dist), clamped to [0..1].
## Shader decodes via `(texel * 2 - 1) * max_dist` to recover signed distance
## in mask-cell units.
static func compute_sdf_image(mask: PackedInt32Array, width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_R8)
	var max_dist: float = float(maxi(width, height))
	var denom: float = 2.0 * max_dist
	for y: int in range(height):
		for x: int in range(width):
			var idx: int = y * width + x
			var is_rock: bool = mask[idx] == ROCK_MASK_VALUE
			var best: float = max_dist
			for ny: int in range(height):
				for nx: int in range(width):
					var nidx: int = ny * width + nx
					var n_is_rock: bool = mask[nidx] == ROCK_MASK_VALUE
					if n_is_rock == is_rock:
						continue
					var dx: int = nx - x
					var dy: int = ny - y
					var d: float = sqrt(float(dx * dx + dy * dy))
					if d < best:
						best = d
			var sdf: float = best if is_rock else -best
			var encoded: float = clamp((sdf + max_dist) / denom, 0.0, 1.0)
			image.set_pixel(x, y, Color(encoded, 0.0, 0.0, 1.0))
	return image


## Returns the max_dist used for encoding (so the shader can decode).
## Equals max(width, height) — the upper bound of any SDF magnitude.
static func max_dist_for(width: int, height: int) -> float:
	return float(maxi(width, height))
