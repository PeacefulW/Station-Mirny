use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use image::{Rgba, RgbaImage};
use serde::Serialize;

use crate::model::{AppRequest, GeneratedFiles, OutputManifest, RenderMode};
use crate::noise::{clamp, fbm_tiled, hash2d, lerp};
use crate::signature::{canonical_signatures, signature_at, Signature};

const ATLAS_COLUMNS: u32 = 8;
const ATLAS_PADDING: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SurfaceZone {
    Top,
    Face,
    Back,
}

#[derive(Clone)]
struct LoadedTexture {
    image: RgbaImage,
}

impl LoadedTexture {
    fn load(path: &str) -> Result<Self> {
        let image = image::open(path)
            .with_context(|| format!("failed to open texture: {path}"))?
            .to_rgba8();
        Ok(Self { image })
    }

    fn sample(&self, x: f32, y: f32) -> [u8; 4] {
        let width = self.image.width().max(1) as f32;
        let height = self.image.height().max(1) as f32;
        let sx = positive_mod(x, width).floor() as u32;
        let sy = positive_mod(y, height).floor() as u32;
        self.image.get_pixel(sx, sy).0
    }
}

#[derive(Default)]
struct TextureSet {
    top: Option<LoadedTexture>,
    face: Option<LoadedTexture>,
    base: Option<LoadedTexture>,
}

#[derive(Default)]
struct Warnings {
    items: Vec<String>,
}

impl Warnings {
    fn push(&mut self, value: String) {
        self.items.push(value);
    }
}

#[derive(Default, Clone)]
struct TileBuffers {
    albedo: RgbaImage,
    mask: RgbaImage,
    height: RgbaImage,
    normal: RgbaImage,
}

#[derive(Serialize)]
struct RecipePayload<'a> {
    tool: &'static str,
    version: u32,
    mode: &'a str,
    request: &'a AppRequest,
}

pub fn run_request(mode: RenderMode, request: AppRequest, output_dir: &Path) -> Result<OutputManifest> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create output dir: {}", output_dir.display()))?;

    let started = std::time::Instant::now();
    let mut warnings = Warnings::default();
    let textures = load_textures(&request, &mut warnings);
    let signatures = canonical_signatures();

    let preview = build_map_preview(&request, &textures)?;
    let preview_path = output_dir.join("preview.png");
    preview.save(&preview_path)?;

    let recipe_path = output_dir.join("recipe.json");
    let files = if mode == RenderMode::Draft {
        GeneratedFiles {
            preview_png: to_string_path(&preview_path),
            atlas_albedo_png: None,
            atlas_mask_png: None,
            atlas_height_png: None,
            atlas_normal_png: None,
            recipe_json: to_string_path(&recipe_path),
        }
    } else {
        let atlases = build_full_atlases(&request, &textures, &signatures);
        let albedo_atlas_path = output_dir.join("atlas_albedo.png");
        let mask_atlas_path = output_dir.join("atlas_mask.png");
        let height_atlas_path = output_dir.join("atlas_height.png");
        let normal_atlas_path = output_dir.join("atlas_normal.png");

        atlases.albedo.save(&albedo_atlas_path)?;
        atlases.mask.save(&mask_atlas_path)?;
        atlases.height.save(&height_atlas_path)?;
        atlases.normal.save(&normal_atlas_path)?;

        GeneratedFiles {
            preview_png: to_string_path(&preview_path),
            atlas_albedo_png: Some(to_string_path(&albedo_atlas_path)),
            atlas_mask_png: Some(to_string_path(&mask_atlas_path)),
            atlas_height_png: Some(to_string_path(&height_atlas_path)),
            atlas_normal_png: Some(to_string_path(&normal_atlas_path)),
            recipe_json: to_string_path(&recipe_path),
        }
    };

    let recipe = RecipePayload {
        tool: "Cliff Forge Desktop",
        version: 1,
        mode: mode.as_str(),
        request: &request,
    };
    fs::write(&recipe_path, serde_json::to_vec_pretty(&recipe)?)
        .with_context(|| format!("failed to write recipe: {}", recipe_path.display()))?;

    Ok(OutputManifest {
        mode: mode.as_str().to_string(),
        preset: request.preset.clone(),
        tile_size: request.tile_size,
        variants: request.variants,
        signature_count: signatures.len(),
        total_tiles: signatures.len() * request.variants as usize,
        preview_mode: request.preview_mode.clone(),
        files,
        warnings: warnings.items,
        build_ms: started.elapsed().as_millis(),
    })
}

struct Atlases {
    albedo: RgbaImage,
    mask: RgbaImage,
    height: RgbaImage,
    normal: RgbaImage,
}

fn load_textures(request: &AppRequest, warnings: &mut Warnings) -> TextureSet {
    TextureSet {
        top: load_texture_slot(request.textures.top.as_deref(), warnings),
        face: load_texture_slot(request.textures.face.as_deref(), warnings),
        base: load_texture_slot(request.textures.base.as_deref(), warnings),
    }
}

fn load_texture_slot(path: Option<&str>, warnings: &mut Warnings) -> Option<LoadedTexture> {
    let path = path?.trim();
    if path.is_empty() {
        return None;
    }
    match LoadedTexture::load(path) {
        Ok(texture) => Some(texture),
        Err(error) => {
            warnings.push(error.to_string());
            None
        }
    }
}

fn build_full_atlases(request: &AppRequest, textures: &TextureSet, signatures: &[Signature]) -> Atlases {
    let tile_size = request.tile_size;
    let total = signatures.len() as u32 * request.variants;
    let rows = total.div_ceil(ATLAS_COLUMNS);
    let cell = tile_size + ATLAS_PADDING * 2;
    let width = ATLAS_COLUMNS * cell;
    let height = rows * cell;

    let mut albedo = RgbaImage::new(width, height);
    let mut mask = RgbaImage::new(width, height);
    let mut height_img = RgbaImage::new(width, height);
    let mut normal = RgbaImage::new(width, height);

    let mut atlas_index = 0_u32;
    for variant in 0..request.variants {
        for signature in signatures {
            let tile = render_tile(request, textures, signature, variant);
            let col = atlas_index % ATLAS_COLUMNS;
            let row = atlas_index / ATLAS_COLUMNS;
            let dx = col * cell + ATLAS_PADDING;
            let dy = row * cell + ATLAS_PADDING;
            blit_with_bleed(&mut albedo, &tile.albedo, dx, dy);
            blit_with_bleed(&mut mask, &tile.mask, dx, dy);
            blit_with_bleed(&mut height_img, &tile.height, dx, dy);
            blit_with_bleed(&mut normal, &tile.normal, dx, dy);
            atlas_index += 1;
        }
    }

    Atlases {
        albedo,
        mask,
        height: height_img,
        normal,
    }
}

fn build_map_preview(request: &AppRequest, textures: &TextureSet) -> Result<RgbaImage> {
    let width = request.map.width * request.tile_size;
    let height = request.map.height * request.tile_size;
    let mut preview = RgbaImage::new(width, height);

    for map_y in 0..request.map.height as i32 {
        for map_x in 0..request.map.width as i32 {
            let cell_index = (map_y as u32 * request.map.width + map_x as u32) as usize;
            let filled = request.map.cells.get(cell_index).copied().unwrap_or(0) > 0;
            let origin_x = map_x as u32 * request.tile_size;
            let origin_y = map_y as u32 * request.tile_size;

            if filled {
                let signature = signature_at(&request.map, map_x, map_y);
                let variant = request
                    .forced_variant
                    .unwrap_or_else(|| pick_variant(map_x, map_y, request.seed, request.variants));
                let tile = render_tile(request, textures, &signature, variant);
                let source = choose_mode_image(&tile, &request.preview_mode);
                blit_exact(&mut preview, source, origin_x, origin_y);
            } else {
                fill_empty_cell(&mut preview, textures, request, origin_x, origin_y);
            }
        }
    }

    Ok(preview)
}

fn fill_empty_cell(target: &mut RgbaImage, textures: &TextureSet, request: &AppRequest, origin_x: u32, origin_y: u32) {
    let base_color = parse_hex_color(&request.colors.base);
    for local_y in 0..request.tile_size {
        for local_x in 0..request.tile_size {
            let color = sample_material_color(
                base_color,
                textures.base.as_ref(),
                request.texture_scale,
                request.tile_size,
                origin_x + local_x,
                origin_y + local_y,
                request.seed.wrapping_add(10_001),
                0.92,
            );
            target.put_pixel(origin_x + local_x, origin_y + local_y, rgba(color, 255));
        }
    }
}

fn pick_variant(x: i32, y: i32, seed: u32, total: u32) -> u32 {
    if total <= 1 {
        0
    } else {
        (hash2d(x, y, seed.wrapping_add(991)) * total as f32).floor() as u32 % total
    }
}

fn render_tile(request: &AppRequest, textures: &TextureSet, signature: &Signature, variant: u32) -> TileBuffers {
    let size = request.tile_size;
    let pixel_count = (size * size) as usize;
    let mut heights = vec![0.0_f32; pixel_count];
    let mut zones = vec![SurfaceZone::Top; pixel_count];

    let geometry_seed = request.seed.wrapping_add(variant.wrapping_mul(4_091));
    let material_seed = geometry_seed.wrapping_add(17_371);

    for y in 0..size {
        for x in 0..size {
            let index = (y * size + x) as usize;
            let (height, zone) = sample_height(request, signature, geometry_seed, x as f32, y as f32);
            heights[index] = height;
            zones[index] = zone;
        }
    }

    apply_crown_bevel(request, signature, geometry_seed, &mut heights, &zones);

    let mut albedo = RgbaImage::new(size, size);
    let mut mask = RgbaImage::new(size, size);
    let mut height_img = RgbaImage::new(size, size);
    let mut normal = RgbaImage::new(size, size);

    let top_color = parse_hex_color(&request.colors.top);
    let face_color = parse_hex_color(&request.colors.face);
    let back_color = parse_hex_color(&request.colors.back);

    for y in 0..size {
        for x in 0..size {
            let index = (y * size + x) as usize;
            let zone = zones[index];
            let height_value = heights[index];
            let sample_seed = material_seed.wrapping_add(index as u32 * 13);

            let base = match zone {
                SurfaceZone::Top => sample_material_color(
                    top_color,
                    textures.top.as_ref(),
                    request.texture_scale,
                    request.tile_size,
                    x,
                    y,
                    sample_seed,
                    1.0,
                ),
                SurfaceZone::Face => sample_material_color(
                    face_color,
                    textures.face.as_ref(),
                    request.texture_scale,
                    request.tile_size,
                    x,
                    y,
                    sample_seed,
                    1.0,
                ),
                SurfaceZone::Back => sample_material_color(
                    back_color,
                    textures.face.as_ref(),
                    request.texture_scale,
                    request.tile_size,
                    x,
                    y,
                    sample_seed,
                    1.0,
                ),
            };

            let shaded = apply_height_shading(base, height_value, zone);
            albedo.put_pixel(x, y, rgba(shaded, 255));

            let top_mask = if zone == SurfaceZone::Top { 255 } else { 0 };
            let face_mask = if zone == SurfaceZone::Face { 255 } else { 0 };
            let back_mask = if zone == SurfaceZone::Back { 255 } else { 0 };
            mask.put_pixel(x, y, Rgba([top_mask, face_mask, back_mask, 255]));

            let height_byte = (clamp(height_value, 0.0, 1.0) * 255.0).round() as u8;
            height_img.put_pixel(x, y, Rgba([height_byte, height_byte, height_byte, 255]));

            let encoded = encode_normal(size, &heights, x, y);
            normal.put_pixel(x, y, Rgba([encoded[0], encoded[1], encoded[2], 255]));
        }
    }

    TileBuffers {
        albedo,
        mask,
        height: height_img,
        normal,
    }
}

fn choose_mode_image<'a>(tile: &'a TileBuffers, preview_mode: &str) -> &'a RgbaImage {
    match preview_mode {
        "albedo" | "composite" => &tile.albedo,
        "mask" => &tile.mask,
        "height" => &tile.height,
        "normal" => &tile.normal,
        _ => &tile.albedo,
    }
}

fn sample_height(request: &AppRequest, signature: &Signature, seed: u32, x: f32, y: f32) -> (f32, SurfaceZone) {
    let size = request.tile_size as f32;
    let north_depth = request.north_height as f32;
    let side_depth = request.side_height as f32;
    let rough_px = (request.roughness / 100.0) * (request.tile_size as f32 * 0.085);
    let north_open_boundary = signature
        .open_n
        .then(|| north_boundary(request, rough_px, seed.wrapping_add(11), x, y));
    let south_open_boundary = signature
        .open_s
        .then(|| south_boundary(request, rough_px, seed.wrapping_add(23), x, y));
    let east_open_boundary = signature
        .open_e
        .then(|| east_boundary(request, rough_px, seed.wrapping_add(37), x, y));
    let west_open_boundary = signature
        .open_w
        .then(|| west_boundary(request, rough_px, seed.wrapping_add(41), x, y));

    let mut min_height = 1.0_f32;
    let mut min_zone = SurfaceZone::Top;
    let overlap_ne = matches!((north_open_boundary, east_open_boundary), (Some(north), Some(east)) if y < north && x > east);
    let overlap_nw = matches!((north_open_boundary, west_open_boundary), (Some(north), Some(west)) if y < north && x < west);
    let overlap_se = matches!((south_open_boundary, east_open_boundary), (Some(south), Some(east)) if y > south && x > east);
    let overlap_sw = matches!((south_open_boundary, west_open_boundary), (Some(south), Some(west)) if y > south && x < west);

    if signature.open_n {
        let boundary = north_open_boundary.expect("north boundary must exist when open_n");
        if y < boundary && !overlap_ne && !overlap_nw {
            let progress = 1.0 - (y / boundary.max(1.0));
            set_min_height(
                &mut min_height,
                &mut min_zone,
                back_height_for_progress(request, progress),
                SurfaceZone::Back,
            );
        }
    }
    if signature.open_s {
        let boundary = south_open_boundary.expect("south boundary must exist when open_s");
        if y > boundary {
            let progress = ((y - boundary) / (size - 1.0 - boundary).max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, progress),
                SurfaceZone::Face,
            );
        }
    }
    if signature.open_e {
        let boundary = east_open_boundary.expect("east boundary must exist when open_e");
        if x > boundary && !overlap_se {
            let progress = ((x - boundary) / (size - 1.0 - boundary).max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, progress),
                SurfaceZone::Face,
            );
        }
    }
    if signature.open_w {
        let boundary = west_open_boundary.expect("west boundary must exist when open_w");
        if x < boundary && !overlap_sw {
            let progress = 1.0 - (x / boundary.max(1.0));
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, progress),
                SurfaceZone::Face,
            );
        }
    }

    let notch_side = side_depth.max(2.0);
    let notch_north = north_depth.max(2.0);

    if signature.notch_ne {
        let x_start = size - notch_side
            + edge_jitter(y, seed.wrapping_add(53), rough_px * 0.8, (request.tile_size.saturating_sub(1)).max(1) as f32);
        let y_end = notch_north
            + edge_jitter(x, seed.wrapping_add(59), rough_px * 0.8, (request.tile_size.saturating_sub(1)).max(1) as f32);
        if x > x_start && y < y_end {
            let east_progress = ((x - x_start) / notch_side.max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, east_progress),
                SurfaceZone::Face,
            );
        }
    }
    if signature.notch_nw {
        let x_end = notch_side
            + edge_jitter(y, seed.wrapping_add(61), rough_px * 0.8, (request.tile_size.saturating_sub(1)).max(1) as f32);
        let y_end = notch_north
            + edge_jitter(x, seed.wrapping_add(67), rough_px * 0.8, (request.tile_size.saturating_sub(1)).max(1) as f32);
        if x < x_end && y < y_end {
            let west_progress = (1.0 - x / x_end.max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, west_progress),
                SurfaceZone::Face,
            );
        }
    }
    if signature.notch_se {
        let x_start = east_boundary(request, rough_px, seed.wrapping_add(37), x, y);
        let y_start = south_boundary(request, rough_px, seed.wrapping_add(23), x, y);
        if x > x_start && y > y_start {
            let progress = ((y - y_start) / (size - 1.0 - y_start).max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, progress),
                SurfaceZone::Face,
            );
        }
    }
    if signature.notch_sw {
        let x_end = west_boundary(request, rough_px, seed.wrapping_add(41), x, y);
        let y_start = south_boundary(request, rough_px, seed.wrapping_add(23), x, y);
        if x < x_end && y > y_start {
            let progress = ((y - y_start) / (size - 1.0 - y_start).max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, progress),
                SurfaceZone::Face,
            );
        }
    }

    (clamp(min_height, 0.0, 1.0), min_zone)
}

fn north_boundary(request: &AppRequest, rough_px: f32, seed: u32, x: f32, y: f32) -> f32 {
    let _ = y;
    request.north_height as f32 + edge_jitter(x, seed, rough_px, (request.tile_size.saturating_sub(1)).max(1) as f32)
}

fn south_boundary(request: &AppRequest, rough_px: f32, seed: u32, x: f32, y: f32) -> f32 {
    let _ = y;
    (request.tile_size as f32 - 1.0 - request.south_height as f32)
        + edge_jitter(x, seed, rough_px, (request.tile_size.saturating_sub(1)).max(1) as f32)
}

fn east_boundary(request: &AppRequest, rough_px: f32, seed: u32, x: f32, y: f32) -> f32 {
    let _ = x;
    (request.tile_size as f32 - 1.0 - request.side_height as f32)
        + edge_jitter(y, seed, rough_px, (request.tile_size.saturating_sub(1)).max(1) as f32)
}

fn west_boundary(request: &AppRequest, rough_px: f32, seed: u32, x: f32, y: f32) -> f32 {
    let _ = x;
    request.side_height as f32 + edge_jitter(y, seed, rough_px, (request.tile_size.saturating_sub(1)).max(1) as f32)
}

fn back_height_for_progress(request: &AppRequest, progress: f32) -> f32 {
    1.0 - progress * request.back_drop
}

fn face_height_for_progress(request: &AppRequest, progress: f32) -> f32 {
    (1.0 - progress).powf(request.face_power)
}

fn set_min_height(current_height: &mut f32, current_zone: &mut SurfaceZone, candidate: f32, zone: SurfaceZone) {
    if candidate < *current_height {
        *current_height = candidate;
        *current_zone = zone;
    }
}

fn edge_jitter(coord: f32, seed: u32, amplitude: f32, tile_period: f32) -> f32 {
    if amplitude <= 0.01 {
        return 0.0;
    }
    let primary = fbm_tiled(
        coord * 0.12,
        0.0,
        (tile_period * 0.12).max(0.001),
        1.0,
        3,
        seed,
    );
    let secondary = fbm_tiled(
        coord * 0.31 + 17.0,
        0.0,
        (tile_period * 0.04).max(0.001),
        1.0,
        2,
        seed.wrapping_add(131),
    );
    let noise = (primary * 0.72 + secondary * 0.28) - 0.5;
    noise * amplitude * 2.0
}

fn apply_crown_bevel(request: &AppRequest, signature: &Signature, seed: u32, heights: &mut [f32], zones: &[SurfaceZone]) {
    let bevel = request.crown_bevel as f32;
    if bevel <= 0.0 {
        return;
    }

    let size = request.tile_size as usize;
    let rough_px = (request.roughness / 100.0) * (request.tile_size as f32 * 0.085);

    for y in 0..size {
        for x in 0..size {
            let index = y * size + x;
            if zones[index] != SurfaceZone::Top {
                continue;
            }

            let xf = x as f32;
            let yf = y as f32;
            let mut nearest = f32::MAX;

            if signature.open_n {
                let boundary = north_boundary(request, rough_px, seed.wrapping_add(11), xf, yf);
                nearest = nearest.min((yf - boundary).abs());
            }
            if signature.open_s {
                let boundary = south_boundary(request, rough_px, seed.wrapping_add(23), xf, yf);
                nearest = nearest.min((yf - boundary).abs());
            }
            if signature.open_e {
                let boundary = east_boundary(request, rough_px, seed.wrapping_add(37), xf, yf);
                nearest = nearest.min((xf - boundary).abs());
            }
            if signature.open_w {
                let boundary = west_boundary(request, rough_px, seed.wrapping_add(41), xf, yf);
                nearest = nearest.min((xf - boundary).abs());
            }
            if nearest.is_finite() && nearest < bevel {
                let t = (nearest / bevel).clamp(0.0, 1.0);
                heights[index] = heights[index].min(lerp(0.86, 1.0, t));
            }
        }
    }
}

fn sample_material_color(
    tint: [u8; 3],
    texture: Option<&LoadedTexture>,
    texture_scale: f32,
    tile_size: u32,
    x: u32,
    y: u32,
    seed: u32,
    brightness: f32,
) -> [u8; 3] {
    let sampled = if let Some(texture) = texture {
        let source = texture.sample(x as f32 * texture_scale, y as f32 * texture_scale);
        [source[0], source[1], source[2]]
    } else {
        procedural_material(seed, x as f32, y as f32, tile_size as f32, tint)
    };

    [
        ((sampled[0] as f32 * (tint[0] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
        ((sampled[1] as f32 * (tint[1] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
        ((sampled[2] as f32 * (tint[2] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
    ]
}

fn procedural_material(seed: u32, x: f32, y: f32, tile_period: f32, tint: [u8; 3]) -> [u8; 3] {
    let broad = fbm_tiled(x * 0.08, y * 0.08, tile_period * 0.08, tile_period * 0.08, 4, seed);
    let fine = fbm_tiled(
        x * 0.24 + 13.0,
        y * 0.24 + 27.0,
        tile_period * 0.24,
        tile_period * 0.24,
        3,
        seed.wrapping_add(177),
    );
    let speck = hash2d(x as i32 * 3, y as i32 * 3, seed.wrapping_add(991));
    let mix = clamp(0.62 + broad * 0.28 + fine * 0.14 + (speck - 0.5) * 0.08, 0.25, 1.18);
    [
        ((tint[0] as f32 * mix).round() as i32).clamp(0, 255) as u8,
        ((tint[1] as f32 * mix).round() as i32).clamp(0, 255) as u8,
        ((tint[2] as f32 * mix).round() as i32).clamp(0, 255) as u8,
    ]
}

fn apply_height_shading(color: [u8; 3], height: f32, zone: SurfaceZone) -> [u8; 3] {
    let factor = match zone {
        SurfaceZone::Top => 0.96 + height * 0.08,
        SurfaceZone::Face => 0.90 + height * 0.10,
        SurfaceZone::Back => 0.94 + height * 0.08,
    };
    [
        ((color[0] as f32 * factor).round() as i32).clamp(0, 255) as u8,
        ((color[1] as f32 * factor).round() as i32).clamp(0, 255) as u8,
        ((color[2] as f32 * factor).round() as i32).clamp(0, 255) as u8,
    ]
}

fn encode_normal(size: u32, heights: &[f32], x: u32, y: u32) -> [u8; 3] {
    let left = sample_height_value(size, heights, x.saturating_sub(1), y);
    let right = sample_height_value(size, heights, (x + 1).min(size - 1), y);
    let top = sample_height_value(size, heights, x, y.saturating_sub(1));
    let bottom = sample_height_value(size, heights, x, (y + 1).min(size - 1));

    let dx = right - left;
    let dy = bottom - top;
    let nx = -dx * 2.4;
    let ny = -dy * 2.4;
    let nz = 1.0;
    let length = (nx * nx + ny * ny + nz * nz).sqrt().max(0.0001);
    [
        (((nx / length) * 0.5 + 0.5) * 255.0).round() as u8,
        (((ny / length) * 0.5 + 0.5) * 255.0).round() as u8,
        (((nz / length) * 0.5 + 0.5) * 255.0).round() as u8,
    ]
}

fn sample_height_value(size: u32, heights: &[f32], x: u32, y: u32) -> f32 {
    heights[(y * size + x) as usize]
}

fn blit_with_bleed(target: &mut RgbaImage, source: &RgbaImage, dx: u32, dy: u32) {
    let width = source.width();
    let height = source.height();
    blit_exact(target, source, dx, dy);

    for x in 0..width {
        let top = *source.get_pixel(x, 0);
        let bottom = *source.get_pixel(x, height - 1);
        for pad in 1..=ATLAS_PADDING {
            target.put_pixel(dx + x, dy - pad, top);
            target.put_pixel(dx + x, dy + height - 1 + pad, bottom);
        }
    }

    for y in 0..height {
        let left = *source.get_pixel(0, y);
        let right = *source.get_pixel(width - 1, y);
        for pad in 1..=ATLAS_PADDING {
            target.put_pixel(dx - pad, dy + y, left);
            target.put_pixel(dx + width - 1 + pad, dy + y, right);
        }
    }
}

fn blit_exact(target: &mut RgbaImage, source: &RgbaImage, dx: u32, dy: u32) {
    for y in 0..source.height() {
        for x in 0..source.width() {
            target.put_pixel(dx + x, dy + y, *source.get_pixel(x, y));
        }
    }
}

fn parse_hex_color(value: &str) -> [u8; 3] {
    let trimmed = value.trim().trim_start_matches('#');
    if trimmed.len() != 6 {
        return [255, 255, 255];
    }

    let parse = |slice: std::ops::Range<usize>| u8::from_str_radix(&trimmed[slice], 16).unwrap_or(255);
    [parse(0..2), parse(2..4), parse(4..6)]
}

fn rgba(rgb: [u8; 3], alpha: u8) -> Rgba<u8> {
    Rgba([rgb[0], rgb[1], rgb[2], alpha])
}

fn positive_mod(value: f32, size: f32) -> f32 {
    ((value % size) + size) % size
}

fn to_string_path(path: &Path) -> String {
    path.to_string_lossy().to_string()
}
