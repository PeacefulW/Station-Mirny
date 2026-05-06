use std::fs;
use std::path::Path;
use std::time::Instant;

use anyhow::{Context, Result};
use image::{Rgba, RgbaImage};
use serde::Serialize;

use crate::model::{AppRequest, MaterialConfig, SilhouetteAtlasRequest};
use crate::noise::{clamp, hash2d, value_noise};

const SILHOUETTE_DIRECTIONS: [&str; 8] = ["N", "E", "S", "W", "NE", "SE", "SW", "NW"];
const CARDINAL_DIRECTION_COUNT: usize = 4;

#[derive(Debug, Clone, Serialize)]
pub struct SilhouetteOutputManifest {
    pub mode: String,
    pub asset_name: String,
    pub tile_size_px: u32,
    pub silhouette_height_px: u32,
    pub variants: u32,
    pub direction_count: usize,
    pub cell_count: usize,
    pub files: SilhouetteGeneratedFiles,
    pub warnings: Vec<String>,
    pub build_ms: u128,
}

#[derive(Debug, Clone, Serialize)]
pub struct SilhouetteGeneratedFiles {
    pub silhouette_atlas_png: String,
    pub silhouette_metadata_json: String,
}

#[derive(Debug, Clone, Serialize)]
struct SilhouetteMetadata {
    tool: &'static str,
    version: u32,
    asset_name: String,
    tile_size_px: u32,
    silhouette_height_px: u32,
    variants: u32,
    directions: Vec<&'static str>,
    has_corner_sprites: bool,
    cells: Vec<SilhouetteMetadataCell>,
}

#[derive(Debug, Clone, Serialize)]
struct SilhouetteMetadataCell {
    index: usize,
    variant: u32,
    direction: &'static str,
    sprite_kind: &'static str,
    pivot: PivotPx,
    overhang_px: OverhangPx,
    material_summary: MaterialSummary,
}

#[derive(Debug, Clone, Copy, Serialize)]
struct PivotPx {
    x: i32,
    y: i32,
}

#[derive(Debug, Clone, Copy, Serialize)]
struct OverhangPx {
    x: i32,
    y: i32,
}

#[derive(Debug, Clone, Serialize)]
struct MaterialSummary {
    material_slot: String,
    source: String,
    kind: String,
    seed: u32,
}

pub fn run_request(request: &AppRequest, output_dir: &Path) -> Result<SilhouetteOutputManifest> {
    let started = Instant::now();
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create output dir: {}", output_dir.display()))?;

    let atlas_path = output_dir.join(format!("{}_silhouette_atlas.png", request.asset_name));
    let metadata_path = output_dir.join(format!("{}_silhouette_metadata.json", request.asset_name));
    let silhouette = &request.silhouette_atlas;
    let material = material_for_slot(request);
    let atlas_width = silhouette.tile_size_px * SILHOUETTE_DIRECTIONS.len() as u32;
    let atlas_height = silhouette.silhouette_height_px * silhouette.variants;
    let mut atlas = RgbaImage::from_pixel(atlas_width, atlas_height, Rgba([0, 0, 0, 0]));
    let mut metadata_cells = Vec::with_capacity((silhouette.variants as usize) * SILHOUETTE_DIRECTIONS.len());

    for variant in 0..silhouette.variants {
        let top_profile = build_top_profile(silhouette, variant);
        for (direction_index, direction) in SILHOUETTE_DIRECTIONS.iter().enumerate() {
            let sprite = render_cell(silhouette, material, &top_profile, direction_index, variant);
            let offset_x = direction_index as u32 * silhouette.tile_size_px;
            let offset_y = variant * silhouette.silhouette_height_px;
            blit(&mut atlas, &sprite, offset_x, offset_y);
            let index = variant as usize * SILHOUETTE_DIRECTIONS.len() + direction_index;
            metadata_cells.push(SilhouetteMetadataCell {
                index,
                variant,
                direction,
                sprite_kind: if direction_index < CARDINAL_DIRECTION_COUNT {
                    "cardinal"
                } else {
                    "corner"
                },
                pivot: pivot_for_direction(direction_index, silhouette),
                overhang_px: overhang_for_direction(direction_index, silhouette),
                material_summary: MaterialSummary {
                    material_slot: silhouette.material_slot.clone(),
                    source: material.source.clone(),
                    kind: material.kind.clone(),
                    seed: material.seed.wrapping_add(silhouette.seed).wrapping_add(variant),
                },
            });
        }
    }

    atlas
        .save(&atlas_path)
        .with_context(|| format!("failed to write silhouette atlas: {}", atlas_path.display()))?;
    let metadata = SilhouetteMetadata {
        tool: "Cliff Forge Desktop",
        version: 1,
        asset_name: request.asset_name.clone(),
        tile_size_px: silhouette.tile_size_px,
        silhouette_height_px: silhouette.silhouette_height_px,
        variants: silhouette.variants,
        directions: SILHOUETTE_DIRECTIONS.to_vec(),
        has_corner_sprites: true,
        cells: metadata_cells,
    };
    fs::write(&metadata_path, serde_json::to_vec_pretty(&metadata)?)
        .with_context(|| format!("failed to write silhouette metadata: {}", metadata_path.display()))?;

    Ok(SilhouetteOutputManifest {
        mode: "silhouettes".to_string(),
        asset_name: request.asset_name.clone(),
        tile_size_px: silhouette.tile_size_px,
        silhouette_height_px: silhouette.silhouette_height_px,
        variants: silhouette.variants,
        direction_count: SILHOUETTE_DIRECTIONS.len(),
        cell_count: metadata.cells.len(),
        files: SilhouetteGeneratedFiles {
            silhouette_atlas_png: atlas_path.to_string_lossy().to_string(),
            silhouette_metadata_json: metadata_path.to_string_lossy().to_string(),
        },
        warnings: Vec::new(),
        build_ms: started.elapsed().as_millis(),
    })
}

fn material_for_slot(request: &AppRequest) -> &MaterialConfig {
    match request.silhouette_atlas.material_slot.as_str() {
        "top" => &request.materials.top,
        "base" => &request.materials.base,
        _ => &request.materials.face,
    }
}

fn build_top_profile(request: &SilhouetteAtlasRequest, variant: u32) -> Vec<u32> {
    let mut profile = Vec::with_capacity(request.tile_size_px as usize);
    let seed = request.seed.wrapping_add(variant * 977).wrapping_add(19);
    let jitter = request.top_jitter_px as f32 * request.top_roughness;

    for x in 0..request.tile_size_px {
        let broad = value_noise(x as f32 * 0.08, variant as f32 * 0.31, seed);
        let chip = hash2d(x as i32 / 3, variant as i32, seed.wrapping_add(37));
        let value = ((broad * 0.75 + chip * 0.25) * jitter).round();
        profile.push(value.clamp(0.0, request.top_jitter_px as f32) as u32);
    }

    for _ in 0..3 {
        smooth_profile(&mut profile);
    }
    limit_profile_slope(&mut profile, 2);
    profile
}

fn smooth_profile(profile: &mut [u32]) {
    if profile.len() < 3 {
        return;
    }
    let copy = profile.to_vec();
    for index in 1..profile.len() - 1 {
        profile[index] = ((copy[index - 1] + copy[index] + copy[index + 1]) as f32 / 3.0).round() as u32;
    }
}

fn limit_profile_slope(profile: &mut [u32], max_delta: u32) {
    if profile.len() < 2 {
        return;
    }

    for index in 1..profile.len() {
        let previous = profile[index - 1];
        if profile[index] > previous + max_delta {
            profile[index] = previous + max_delta;
        } else if previous > profile[index] + max_delta {
            profile[index] = previous - max_delta;
        }
    }

    for index in (0..profile.len() - 1).rev() {
        let next = profile[index + 1];
        if profile[index] > next + max_delta {
            profile[index] = next + max_delta;
        } else if next > profile[index] + max_delta {
            profile[index] = next - max_delta;
        }
    }
}

fn render_cell(
    request: &SilhouetteAtlasRequest,
    material: &MaterialConfig,
    top_profile: &[u32],
    direction_index: usize,
    variant: u32,
) -> RgbaImage {
    let mut sprite = RgbaImage::from_pixel(
        request.tile_size_px,
        request.silhouette_height_px,
        Rgba([0, 0, 0, 0]),
    );
    let base_a = parse_hex_color(&material.color_a);
    let base_b = parse_hex_color(&material.color_b);

    for y in 0..request.silhouette_height_px {
        for x in 0..request.tile_size_px {
            if y < top_profile[x as usize] || !corner_mask(request, direction_index, x, y) {
                continue;
            }
            let t = material_mix(material, x, y, variant);
            let shade = direction_shade(request, direction_index, x, y);
            let color = mix(base_a, base_b, t);
            sprite.put_pixel(x, y, shaded(color, shade, 255));
        }
    }

    sprite
}

fn material_mix(material: &MaterialConfig, x: u32, y: u32, variant: u32) -> f32 {
    let scale = material.scale.max(0.2);
    let seed = material.seed.wrapping_add(variant * 311);
    let mut value = value_noise(x as f32 * 0.12 / scale, y as f32 * 0.09 / scale, seed);
    if material.kind == "stone_bricks" {
        let mortar = x % 16 <= 1 || y % 18 <= 1;
        if mortar {
            value *= 0.45;
        }
    } else if material.kind == "cracked_earth" {
        let crack = ((x as i32 - y as i32 + seed as i32 % 13).abs() % 23) <= 1;
        if crack {
            value *= 0.35;
        }
    } else if material.kind == "ribbed_steel" {
        value = if (x + y + seed % 5) % 9 < 3 { 0.72 } else { 0.38 };
    }
    clamp(value, 0.0, 1.0)
}

fn direction_shade(request: &SilhouetteAtlasRequest, direction_index: usize, x: u32, y: u32) -> f32 {
    let vertical = y as f32 / request.silhouette_height_px.max(1) as f32;
    let horizontal = x as f32 / request.tile_size_px.max(1) as f32;
    let side = match direction_index {
        0 => 1.07 - vertical * 0.20,
        1 => 0.88 + horizontal * 0.28,
        2 => 0.90 - vertical * 0.12,
        3 => 1.14 - horizontal * 0.28,
        4 => 1.05 - (horizontal - 0.5).abs() * 0.22,
        5 => 0.94 - vertical * 0.10 + horizontal * 0.08,
        6 => 0.90 + (horizontal - 0.5).abs() * 0.18,
        _ => 0.98 - horizontal * 0.10,
    };
    side.clamp(0.55, 1.25)
}

fn corner_mask(request: &SilhouetteAtlasRequest, direction_index: usize, x: u32, y: u32) -> bool {
    if direction_index < CARDINAL_DIRECTION_COUNT {
        return true;
    }

    let mid = request.tile_size_px / 2;
    let lower = y > request.silhouette_height_px / 3;
    let near_junction = x.abs_diff(mid) <= 2;
    if near_junction {
        return true;
    }
    match direction_index {
        4 => x <= mid || lower,
        5 => x >= mid || lower,
        6 => x >= mid || lower,
        _ => x <= mid || lower,
    }
}

fn pivot_for_direction(direction_index: usize, request: &SilhouetteAtlasRequest) -> PivotPx {
    let w = request.tile_size_px as i32;
    let h = request.silhouette_height_px as i32;
    match direction_index {
        0 => PivotPx { x: w / 2, y: h },
        1 => PivotPx { x: 0, y: h },
        2 => PivotPx { x: w / 2, y: h },
        3 => PivotPx { x: w, y: h },
        4 => PivotPx { x: 0, y: h },
        5 => PivotPx { x: 0, y: h },
        6 => PivotPx { x: w, y: h },
        _ => PivotPx { x: w, y: h },
    }
}

fn overhang_for_direction(direction_index: usize, request: &SilhouetteAtlasRequest) -> OverhangPx {
    let w = request.tile_size_px as i32;
    let h = request.silhouette_height_px as i32;
    match direction_index {
        0 => OverhangPx { x: 0, y: -h },
        1 => OverhangPx { x: w, y: -h },
        2 => OverhangPx { x: 0, y: -h },
        3 => OverhangPx { x: -w, y: -h },
        4 => OverhangPx { x: w, y: -h },
        5 => OverhangPx { x: w, y: -h },
        6 => OverhangPx { x: -w, y: -h },
        _ => OverhangPx { x: -w, y: -h },
    }
}

fn parse_hex_color(value: &str) -> [u8; 3] {
    let hex = value.trim().trim_start_matches('#');
    if hex.len() != 6 {
        return [75, 68, 60];
    }

    let parse = |start: usize| u8::from_str_radix(&hex[start..start + 2], 16).ok();
    match (parse(0), parse(2), parse(4)) {
        (Some(r), Some(g), Some(b)) => [r, g, b],
        _ => [75, 68, 60],
    }
}

fn mix(a: [u8; 3], b: [u8; 3], t: f32) -> [u8; 3] {
    [
        (a[0] as f32 + (b[0] as f32 - a[0] as f32) * t).round() as u8,
        (a[1] as f32 + (b[1] as f32 - a[1] as f32) * t).round() as u8,
        (a[2] as f32 + (b[2] as f32 - a[2] as f32) * t).round() as u8,
    ]
}

fn shaded(color: [u8; 3], shade: f32, alpha: u8) -> Rgba<u8> {
    Rgba([
        (color[0] as f32 * shade).round().clamp(0.0, 255.0) as u8,
        (color[1] as f32 * shade).round().clamp(0.0, 255.0) as u8,
        (color[2] as f32 * shade).round().clamp(0.0, 255.0) as u8,
        alpha,
    ])
}

fn blit(target: &mut RgbaImage, sprite: &RgbaImage, offset_x: u32, offset_y: u32) {
    for y in 0..sprite.height() {
        for x in 0..sprite.width() {
            target.put_pixel(offset_x + x, offset_y + y, *sprite.get_pixel(x, y));
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fs as test_fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use crate::model::default_request;

    use super::*;

    fn test_output_dir(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be after unix epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cliff_forge_silhouette_{name}_{nonce}"));
        test_fs::create_dir_all(&dir).expect("test output dir should be creatable");
        dir
    }

    #[test]
    fn silhouette_export_writes_cardinal_and_corner_atlas_with_metadata() {
        let output_dir = test_output_dir("basic");
        let mut request = default_request();
        request.asset_name = "first_biome_rock_wall".to_string();
        request.silhouette_atlas.tile_size_px = 64;
        request.silhouette_atlas.silhouette_height_px = 96;
        request.silhouette_atlas.variants = 3;
        let request = request.sanitized();

        let manifest = run_request(&request, &output_dir).expect("silhouette export should render");
        let atlas = image::open(&manifest.files.silhouette_atlas_png)
            .expect("silhouette atlas should be readable")
            .to_rgba8();
        let metadata: serde_json::Value = serde_json::from_slice(
            &test_fs::read(&manifest.files.silhouette_metadata_json).expect("metadata should be readable"),
        )
        .expect("metadata should be json");

        assert_eq!(atlas.dimensions(), (64 * 8, 96 * 3));
        assert_eq!(manifest.cell_count, 24);
        assert_eq!(metadata["cells"].as_array().expect("cells should be array").len(), 24);
        assert_eq!(metadata["cells"][0]["direction"], "N");
        assert_eq!(metadata["cells"][4]["direction"], "NE");
        assert!(metadata["cells"][0]["pivot"].is_object());
        assert!(metadata["cells"][4]["pivot"].is_object());
        assert!(output_dir.join("first_biome_rock_wall_silhouette_atlas.png").exists());
        assert!(output_dir.join("first_biome_rock_wall_silhouette_metadata.json").exists());
    }

    #[test]
    fn corner_sprite_keeps_top_jitter_continuous_at_l_junction() {
        let output_dir = test_output_dir("corner");
        let mut request = default_request();
        request.asset_name = "first_biome_rock_wall".to_string();
        request.silhouette_atlas.tile_size_px = 64;
        request.silhouette_atlas.silhouette_height_px = 96;
        request.silhouette_atlas.variants = 3;
        let request = request.sanitized();

        let manifest = run_request(&request, &output_dir).expect("silhouette export should render");
        let atlas = image::open(&manifest.files.silhouette_atlas_png)
            .expect("silhouette atlas should be readable")
            .to_rgba8();
        let ne_cell_x = 4 * 64;
        let samples = [
            first_opaque_y(&atlas, ne_cell_x + 30, 0, 96),
            first_opaque_y(&atlas, ne_cell_x + 31, 0, 96),
            first_opaque_y(&atlas, ne_cell_x + 32, 0, 96),
            first_opaque_y(&atlas, ne_cell_x + 33, 0, 96),
        ];

        assert!(samples.iter().all(Option::is_some));
        let min_y = samples.iter().copied().flatten().min().expect("samples should exist");
        let max_y = samples.iter().copied().flatten().max().expect("samples should exist");
        assert!(max_y - min_y <= 2);
    }

    fn first_opaque_y(image: &image::RgbaImage, x: u32, top: u32, height: u32) -> Option<u32> {
        (top..top + height).find(|y| image.get_pixel(x, *y).0[3] > 0)
    }
}
