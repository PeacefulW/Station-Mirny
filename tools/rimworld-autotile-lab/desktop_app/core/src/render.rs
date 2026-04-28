use std::fs;
use std::path::Path;

use anyhow::{Context, Result};
use image::{Rgba, RgbaImage};
use serde::Serialize;

use crate::model::{AppRequest, GeneratedFiles, MaterialConfig, OutputManifest, RenderMode};
use crate::noise::{clamp, fbm_tiled, hash2d, lerp};
use crate::signature::{canonical_signatures, signature_at, Signature};

const ATLAS_COLUMNS: u32 = 8;
const MATERIAL_EXPORT_SIZE: u32 = 512;
const RECIPE_VERSION: u32 = 2;
const EDGE_NOISE_PERIOD_TILES: f32 = 8.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SurfaceZone {
    Top,
    Face,
    Back,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MaterialKind {
    Top,
    Face,
    Base,
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

    fn sample_filtered(&self, x: f32, y: f32, footprint: f32) -> [u8; 4] {
        let filter_width = footprint.max(1.0);
        if filter_width <= 1.05 {
            return self.sample_bilinear(x, y);
        }

        let steps = filter_width.ceil().clamp(2.0, 8.0) as u32;
        let step_size = filter_width / steps as f32;
        let start_x = x - filter_width * 0.5;
        let start_y = y - filter_width * 0.5;
        let mut total = [0.0_f32; 4];

        for sample_y in 0..steps {
            for sample_x in 0..steps {
                let source_x = start_x + (sample_x as f32 + 0.5) * step_size;
                let source_y = start_y + (sample_y as f32 + 0.5) * step_size;
                let color = self.sample_bilinear(source_x, source_y);
                for channel in 0..4 {
                    total[channel] += color[channel] as f32;
                }
            }
        }

        let inv_count = 1.0 / (steps * steps) as f32;
        let averaged = [
            total[0] * inv_count,
            total[1] * inv_count,
            total[2] * inv_count,
            total[3] * inv_count,
        ];
        let center = self.sample_bilinear(x, y);
        let detail_strength = (0.32 / filter_width.sqrt()).clamp(0.08, 0.22);

        [
            restore_filtered_detail(averaged[0], center[0], detail_strength),
            restore_filtered_detail(averaged[1], center[1], detail_strength),
            restore_filtered_detail(averaged[2], center[2], detail_strength),
            restore_filtered_detail(averaged[3], center[3], detail_strength),
        ]
    }

    fn sample_bilinear(&self, x: f32, y: f32) -> [u8; 4] {
        let width = self.image.width().max(1) as f32;
        let height = self.image.height().max(1) as f32;
        let sx = positive_mod(x, width);
        let sy = positive_mod(y, height);
        let x0 = sx.floor() as u32;
        let y0 = sy.floor() as u32;
        let x1 = (x0 + 1) % self.image.width().max(1);
        let y1 = (y0 + 1) % self.image.height().max(1);
        let tx = sx - x0 as f32;
        let ty = sy - y0 as f32;

        let c00 = self.image.get_pixel(x0, y0).0;
        let c10 = self.image.get_pixel(x1, y0).0;
        let c01 = self.image.get_pixel(x0, y1).0;
        let c11 = self.image.get_pixel(x1, y1).0;
        let mut result = [0_u8; 4];

        for channel in 0..4 {
            let top = lerp(c00[channel] as f32, c10[channel] as f32, tx);
            let bottom = lerp(c01[channel] as f32, c11[channel] as f32, tx);
            result[channel] = lerp(top, bottom, ty).round().clamp(0.0, 255.0) as u8;
        }

        result
    }
}

fn restore_filtered_detail(average: f32, center: u8, strength: f32) -> u8 {
    (average + (center as f32 - average) * strength)
        .round()
        .clamp(0.0, 255.0) as u8
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
            top_albedo_png: None,
            face_albedo_png: None,
            base_albedo_png: None,
            top_modulation_png: None,
            face_modulation_png: None,
            top_normal_png: None,
            face_normal_png: None,
            recipe_json: to_string_path(&recipe_path),
        }
    } else {
        let atlases = build_full_atlases(&request, &textures, &signatures);
        let material_exports = build_material_exports(&request, &textures);
        let albedo_atlas_path = output_dir.join("atlas_albedo.png");
        let mask_atlas_path = output_dir.join("atlas_mask.png");
        let height_atlas_path = output_dir.join("atlas_height.png");
        let normal_atlas_path = output_dir.join("atlas_normal.png");
        let top_albedo_path = output_dir.join("top_albedo.png");
        let face_albedo_path = output_dir.join("face_albedo.png");
        let base_albedo_path = output_dir.join("base_albedo.png");
        let top_modulation_path = output_dir.join("top_modulation.png");
        let face_modulation_path = output_dir.join("face_modulation.png");
        let top_normal_path = output_dir.join("top_normal.png");
        let face_normal_path = output_dir.join("face_normal.png");

        atlases.albedo.save(&albedo_atlas_path)?;
        atlases.mask.save(&mask_atlas_path)?;
        atlases.height.save(&height_atlas_path)?;
        atlases.normal.save(&normal_atlas_path)?;
        material_exports.top_albedo.save(&top_albedo_path)?;
        material_exports.face_albedo.save(&face_albedo_path)?;
        material_exports.base_albedo.save(&base_albedo_path)?;
        material_exports.top_modulation.save(&top_modulation_path)?;
        material_exports.face_modulation.save(&face_modulation_path)?;
        material_exports.top_normal.save(&top_normal_path)?;
        material_exports.face_normal.save(&face_normal_path)?;

        GeneratedFiles {
            preview_png: to_string_path(&preview_path),
            atlas_albedo_png: Some(to_string_path(&albedo_atlas_path)),
            atlas_mask_png: Some(to_string_path(&mask_atlas_path)),
            atlas_height_png: Some(to_string_path(&height_atlas_path)),
            atlas_normal_png: Some(to_string_path(&normal_atlas_path)),
            top_albedo_png: Some(to_string_path(&top_albedo_path)),
            face_albedo_png: Some(to_string_path(&face_albedo_path)),
            base_albedo_png: Some(to_string_path(&base_albedo_path)),
            top_modulation_png: Some(to_string_path(&top_modulation_path)),
            face_modulation_png: Some(to_string_path(&face_modulation_path)),
            top_normal_png: Some(to_string_path(&top_normal_path)),
            face_normal_png: Some(to_string_path(&face_normal_path)),
            recipe_json: to_string_path(&recipe_path),
        }
    };

    let recipe = RecipePayload {
        tool: "Cliff Forge Desktop",
        version: RECIPE_VERSION,
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

struct MaterialExports {
    top_albedo: RgbaImage,
    face_albedo: RgbaImage,
    base_albedo: RgbaImage,
    top_modulation: RgbaImage,
    face_modulation: RgbaImage,
    top_normal: RgbaImage,
    face_normal: RgbaImage,
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
    let width = ATLAS_COLUMNS * tile_size;
    let height = rows * tile_size;

    let mut albedo = RgbaImage::new(width, height);
    let mut mask = RgbaImage::new(width, height);
    let mut height_img = RgbaImage::new(width, height);
    let mut normal = RgbaImage::new(width, height);

    let mut atlas_index = 0_u32;
    for variant in 0..request.variants {
        for signature in signatures {
            let tile = render_tile(request, textures, signature, variant, 0, 0);
            let col = atlas_index % ATLAS_COLUMNS;
            let row = atlas_index / ATLAS_COLUMNS;
            let dx = col * tile_size;
            let dy = row * tile_size;
            blit_exact(&mut albedo, &tile.albedo, dx, dy);
            blit_exact(&mut mask, &tile.mask, dx, dy);
            blit_exact(&mut height_img, &tile.height, dx, dy);
            blit_exact(&mut normal, &tile.normal, dx, dy);
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

fn build_material_exports(request: &AppRequest, textures: &TextureSet) -> MaterialExports {
    let (top_albedo, top_values) =
        build_material_albedo_and_values(request, textures, MaterialKind::Top);
    let (face_albedo, face_values) =
        build_material_albedo_and_values(request, textures, MaterialKind::Face);
    let (base_albedo, _) =
        build_material_albedo_and_values(request, textures, MaterialKind::Base);

    MaterialExports {
        top_albedo,
        face_albedo,
        base_albedo,
        top_modulation: build_scalar_image(
            &top_values,
            MATERIAL_EXPORT_SIZE,
            MATERIAL_EXPORT_SIZE,
        ),
        face_modulation: build_scalar_image(
            &face_values,
            MATERIAL_EXPORT_SIZE,
            MATERIAL_EXPORT_SIZE,
        ),
        top_normal: build_wrapped_normal_image(
            &top_values,
            MATERIAL_EXPORT_SIZE,
            MATERIAL_EXPORT_SIZE,
            0.95,
        ),
        face_normal: build_wrapped_normal_image(
            &face_values,
            MATERIAL_EXPORT_SIZE,
            MATERIAL_EXPORT_SIZE,
            0.9,
        ),
    }
}

fn build_material_albedo_and_values(
    request: &AppRequest,
    textures: &TextureSet,
    kind: MaterialKind,
) -> (RgbaImage, Vec<f32>) {
    let (material, tint, texture, seed) = material_slot(request, textures, kind);

    let width = MATERIAL_EXPORT_SIZE;
    let height = MATERIAL_EXPORT_SIZE;
    let mut albedo = RgbaImage::new(width, height);
    let mut values = vec![0.0_f32; (width * height) as usize];

    for y in 0..height {
        for x in 0..width {
            let value = sample_material_value(material, texture, request.texture_scale, width, x, y, seed);
            let color = sample_material_color(
                material,
                tint,
                texture,
                request.texture_scale,
                request.texture_color_overlay,
                width,
                x,
                y,
                seed,
                1.0,
            );
            values[(y * width + x) as usize] = value;
            albedo.put_pixel(x, y, rgba(color, 255));
        }
    }

    (albedo, values)
}

fn build_scalar_image(values: &[f32], width: u32, height: u32) -> RgbaImage {
    let mut image = RgbaImage::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let value = sample_wrapped_value(values, width, height, x as i32, y as i32);
            let byte = (clamp(value, 0.0, 1.0) * 255.0).round() as u8;
            image.put_pixel(x, y, Rgba([byte, byte, byte, 255]));
        }
    }
    image
}

fn build_wrapped_normal_image(values: &[f32], width: u32, height: u32, strength: f32) -> RgbaImage {
    let mut image = RgbaImage::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let xi = x as i32;
            let yi = y as i32;
            let left = sample_wrapped_value(values, width, height, xi - 1, yi);
            let right = sample_wrapped_value(values, width, height, xi + 1, yi);
            let up = sample_wrapped_value(values, width, height, xi, yi - 1);
            let down = sample_wrapped_value(values, width, height, xi, yi + 1);
            let nx = (left - right) * strength;
            let ny = (up - down) * strength;
            let nz = 1.0_f32;
            let length = (nx * nx + ny * ny + nz * nz).sqrt().max(0.0001);
            image.put_pixel(
                x,
                y,
                Rgba([
                    (((nx / length) * 0.5 + 0.5) * 255.0).round() as u8,
                    (((ny / length) * 0.5 + 0.5) * 255.0).round() as u8,
                    (((nz / length) * 0.5 + 0.5) * 255.0).round() as u8,
                    255,
                ]),
            );
        }
    }
    image
}

fn sample_wrapped_value(values: &[f32], width: u32, height: u32, x: i32, y: i32) -> f32 {
    let sx = x.rem_euclid(width as i32) as u32;
    let sy = y.rem_euclid(height as i32) as u32;
    values[(sy * width + sx) as usize]
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
                let tile = render_tile(request, textures, &signature, variant, origin_x, origin_y);
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
    let (material, base_color, texture, seed) = material_slot(request, textures, MaterialKind::Base);
    for local_y in 0..request.tile_size {
        for local_x in 0..request.tile_size {
            let color = sample_material_color(
                material,
                base_color,
                texture,
                request.texture_scale,
                request.texture_color_overlay,
                request.tile_size,
                origin_x + local_x,
                origin_y + local_y,
                seed,
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

fn render_tile(
    request: &AppRequest,
    textures: &TextureSet,
    signature: &Signature,
    variant: u32,
    origin_x: u32,
    origin_y: u32,
) -> TileBuffers {
    let size = request.tile_size;
    let pixel_count = (size * size) as usize;
    let mut heights = vec![0.0_f32; pixel_count];
    let mut zones = vec![SurfaceZone::Top; pixel_count];

    let geometry_seed = request.seed;
    let material_seed = request
        .seed
        .wrapping_add(variant.wrapping_mul(4_091))
        .wrapping_add(17_371);

    for y in 0..size {
        for x in 0..size {
            let index = (y * size + x) as usize;
            let (height, zone) = sample_height(
                request,
                signature,
                geometry_seed,
                x as f32,
                y as f32,
                (origin_x + x) as f32,
                (origin_y + y) as f32,
            );
            heights[index] = height;
            zones[index] = zone;
        }
    }

    apply_crown_bevel(
        request,
        signature,
        geometry_seed,
        origin_x,
        origin_y,
        &mut heights,
        &zones,
    );

    let mut albedo = RgbaImage::new(size, size);
    let mut mask = RgbaImage::new(size, size);
    let mut height_img = RgbaImage::new(size, size);
    let mut normal = RgbaImage::new(size, size);

    let (top_material, top_color, top_texture, top_seed) = material_slot(request, textures, MaterialKind::Top);
    let (face_material, face_color, face_texture, face_seed) = material_slot(request, textures, MaterialKind::Face);
    let back_color = parse_hex_color(&request.colors.back);

    for y in 0..size {
        for x in 0..size {
            let index = (y * size + x) as usize;
            let zone = zones[index];
            let height_value = heights[index];
            let sample_x = origin_x + x;
            let sample_y = origin_y + y;
            let local_seed = material_seed
                .wrapping_add(sample_y.wrapping_mul(4_099))
                .wrapping_add(sample_x)
                .wrapping_mul(13);

            let base = match zone {
                SurfaceZone::Top => sample_material_color(
                    top_material,
                    top_color,
                    top_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    sample_x,
                    sample_y,
                    top_seed.wrapping_add(local_seed),
                    1.0,
                ),
                SurfaceZone::Face => sample_material_color(
                    face_material,
                    face_color,
                    face_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    sample_x,
                    sample_y,
                    face_seed.wrapping_add(local_seed),
                    1.0,
                ),
                SurfaceZone::Back => sample_material_color(
                    face_material,
                    back_color,
                    face_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    sample_x,
                    sample_y,
                    face_seed.wrapping_add(local_seed).wrapping_add(181),
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

fn sample_height(
    request: &AppRequest,
    signature: &Signature,
    seed: u32,
    x: f32,
    y: f32,
    world_x: f32,
    world_y: f32,
) -> (f32, SurfaceZone) {
    let size = request.tile_size as f32;
    let north_depth = request.north_height as f32;
    let side_depth = request.side_height as f32;
    let rough_px = (request.roughness / 100.0) * (request.tile_size as f32 * 0.085);
    let edge_period = edge_noise_period(request);
    let north_open_boundary = signature
        .open_n
        .then(|| north_boundary(request, rough_px, edge_period, seed.wrapping_add(11), world_x));
    let south_open_boundary = signature
        .open_s
        .then(|| south_boundary(request, rough_px, edge_period, seed.wrapping_add(23), world_x));
    let east_open_boundary = signature
        .open_e
        .then(|| east_boundary(request, rough_px, edge_period, seed.wrapping_add(37), world_y));
    let west_open_boundary = signature
        .open_w
        .then(|| west_boundary(request, rough_px, edge_period, seed.wrapping_add(41), world_y));

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
            + edge_jitter(world_y, seed.wrapping_add(53), rough_px * 0.8, edge_period);
        let y_end = notch_north
            + edge_jitter(world_x, seed.wrapping_add(59), rough_px * 0.8, edge_period);
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
            + edge_jitter(world_y, seed.wrapping_add(61), rough_px * 0.8, edge_period);
        let y_end = notch_north
            + edge_jitter(world_x, seed.wrapping_add(67), rough_px * 0.8, edge_period);
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
        let x_start = east_boundary(request, rough_px, edge_period, seed.wrapping_add(37), world_y);
        let y_start = south_boundary(request, rough_px, edge_period, seed.wrapping_add(23), world_x);
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
        let x_end = west_boundary(request, rough_px, edge_period, seed.wrapping_add(41), world_y);
        let y_start = south_boundary(request, rough_px, edge_period, seed.wrapping_add(23), world_x);
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

fn north_boundary(request: &AppRequest, rough_px: f32, edge_period: f32, seed: u32, edge_coord: f32) -> f32 {
    request.north_height as f32 + edge_jitter(edge_coord, seed, rough_px, edge_period)
}

fn south_boundary(request: &AppRequest, rough_px: f32, edge_period: f32, seed: u32, edge_coord: f32) -> f32 {
    (request.tile_size as f32 - 1.0 - request.south_height as f32)
        + edge_jitter(edge_coord, seed, rough_px, edge_period)
}

fn east_boundary(request: &AppRequest, rough_px: f32, edge_period: f32, seed: u32, edge_coord: f32) -> f32 {
    (request.tile_size as f32 - 1.0 - request.side_height as f32)
        + edge_jitter(edge_coord, seed, rough_px, edge_period)
}

fn west_boundary(request: &AppRequest, rough_px: f32, edge_period: f32, seed: u32, edge_coord: f32) -> f32 {
    request.side_height as f32 + edge_jitter(edge_coord, seed, rough_px, edge_period)
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

fn edge_noise_period(request: &AppRequest) -> f32 {
    (request.tile_size as f32 * EDGE_NOISE_PERIOD_TILES).max(1.0)
}

fn apply_crown_bevel(
    request: &AppRequest,
    signature: &Signature,
    seed: u32,
    origin_x: u32,
    origin_y: u32,
    heights: &mut [f32],
    zones: &[SurfaceZone],
) {
    let bevel = request.crown_bevel as f32;
    if bevel <= 0.0 {
        return;
    }

    let size = request.tile_size as usize;
    let rough_px = (request.roughness / 100.0) * (request.tile_size as f32 * 0.085);
    let edge_period = edge_noise_period(request);

    for y in 0..size {
        for x in 0..size {
            let index = y * size + x;
            if zones[index] != SurfaceZone::Top {
                continue;
            }

            let xf = x as f32;
            let yf = y as f32;
            let world_x = origin_x as f32 + xf;
            let world_y = origin_y as f32 + yf;
            let mut nearest = f32::MAX;

            if signature.open_n {
                let boundary = north_boundary(request, rough_px, edge_period, seed.wrapping_add(11), world_x);
                nearest = nearest.min((yf - boundary).abs());
            }
            if signature.open_s {
                let boundary = south_boundary(request, rough_px, edge_period, seed.wrapping_add(23), world_x);
                nearest = nearest.min((yf - boundary).abs());
            }
            if signature.open_e {
                let boundary = east_boundary(request, rough_px, edge_period, seed.wrapping_add(37), world_y);
                nearest = nearest.min((xf - boundary).abs());
            }
            if signature.open_w {
                let boundary = west_boundary(request, rough_px, edge_period, seed.wrapping_add(41), world_y);
                nearest = nearest.min((xf - boundary).abs());
            }
            if nearest.is_finite() && nearest < bevel {
                let t = (nearest / bevel).clamp(0.0, 1.0);
                heights[index] = heights[index].min(lerp(0.86, 1.0, t));
            }
        }
    }
}

fn material_slot<'a>(
    request: &'a AppRequest,
    textures: &'a TextureSet,
    kind: MaterialKind,
) -> (&'a MaterialConfig, [u8; 3], Option<&'a LoadedTexture>, u32) {
    match kind {
        MaterialKind::Top => (
            &request.materials.top,
            parse_hex_color(&request.colors.top),
            textures.top.as_ref(),
            request.seed.wrapping_add(20_001),
        ),
        MaterialKind::Face => (
            &request.materials.face,
            parse_hex_color(&request.colors.face),
            textures.face.as_ref(),
            request.seed.wrapping_add(20_101),
        ),
        MaterialKind::Base => (
            &request.materials.base,
            parse_hex_color(&request.colors.base),
            textures.base.as_ref(),
            request.seed.wrapping_add(20_201),
        ),
    }
}

fn sample_material_color(
    material: &MaterialConfig,
    tint: [u8; 3],
    texture: Option<&LoadedTexture>,
    texture_scale: f32,
    texture_color_overlay: bool,
    tile_size: u32,
    x: u32,
    y: u32,
    seed: u32,
    brightness: f32,
) -> [u8; 3] {
    let source = material.source.as_str();
    let (sampled, has_texture) = match source {
        "image" => {
            if let Some(texture) = texture {
                let source = texture.sample_filtered(
                    (x as f32 + 0.5) * texture_scale,
                    (y as f32 + 0.5) * texture_scale,
                    texture_scale,
                );
                ([source[0], source[1], source[2]], true)
            } else {
                (
                    procedural_layer_material(material, seed, x as f32, y as f32, tile_size as f32, tint),
                    false,
                )
            }
        }
        "flat" => (parse_hex_color(&material.color_a), false),
        _ => (
            procedural_layer_material(material, seed, x as f32, y as f32, tile_size as f32, tint),
            false,
        ),
    };
    let tint_factor = if has_texture && texture_color_overlay {
        tint
    } else {
        [255, 255, 255]
    };

    [
        ((sampled[0] as f32 * (tint_factor[0] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
        ((sampled[1] as f32 * (tint_factor[1] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
        ((sampled[2] as f32 * (tint_factor[2] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
    ]
}

fn sample_material_value(
    material: &MaterialConfig,
    texture: Option<&LoadedTexture>,
    texture_scale: f32,
    tile_size: u32,
    x: u32,
    y: u32,
    seed: u32,
) -> f32 {
    if material.source == "image" {
        if let Some(texture) = texture {
            let source = texture.sample_filtered(
                (x as f32 + 0.5) * texture_scale,
                (y as f32 + 0.5) * texture_scale,
                texture_scale,
            );
            return srgb_luminance(source) / 255.0;
        }
    }

    let color = if material.source == "flat" {
        parse_hex_color(&material.color_a)
    } else {
        procedural_layer_material(material, seed, x as f32, y as f32, tile_size as f32, [128, 128, 128])
    };
    srgb_luminance_rgb(color) / 255.0
}

fn procedural_layer_material(
    material: &MaterialConfig,
    seed: u32,
    x: f32,
    y: f32,
    tile_period: f32,
    fallback_tint: [u8; 3],
) -> [u8; 3] {
    let color_a = parse_or_fallback(&material.color_a, fallback_tint);
    let color_b = parse_or_fallback(&material.color_b, lighten_color(fallback_tint, 1.18));
    let highlight = parse_or_fallback(&material.highlight, lighten_color(color_b, 1.22));
    let scale = material.scale.max(0.2);
    let px = x * scale;
    let py = y * scale;
    let period = (tile_period * EDGE_NOISE_PERIOD_TILES * scale).max(1.0);
    let seed = seed.wrapping_add(material.seed.wrapping_mul(193));
    let broad = fbm_tiled(px * 0.045, py * 0.045, period * 0.045, period * 0.045, 4, seed);
    let fine = fbm_tiled(
        px * 0.18 + 37.0,
        py * 0.18 + 19.0,
        period * 0.18,
        period * 0.18,
        3,
        seed.wrapping_add(97),
    );
    let speck = hash2d((px * 1.7).floor() as i32, (py * 1.7).floor() as i32, seed.wrapping_add(307));
    let (mut value, crack, wear_mask, highlight_mask) = match material.kind.as_str() {
        "stone_bricks" => stone_brick_layers(material, seed, px, py, broad, fine),
        "cracked_earth" => cracked_earth_layers(material, seed, px, py, period, broad, fine),
        "worn_metal" => worn_metal_layers(material, seed, px, py, broad, fine),
        "wood_planks" => wood_plank_layers(material, seed, px, py, broad, fine),
        "packed_dirt" => packed_dirt_layers(material, speck, broad, fine),
        "concrete" => concrete_layers(material, seed, px, py, broad, fine),
        "ice_frost" => ice_frost_layers(material, seed, px, py, broad, fine),
        "ash_burnt_ground" => ash_layers(material, speck, broad, fine),
        _ => rough_stone_layers(material, speck, broad, fine),
    };

    value += (speck - 0.5) * material.grain * 0.18;
    value = apply_value_contrast(value, material.contrast);
    let mut color = mix_color(color_a, color_b, value);
    color = mix_color(color, highlight, highlight_mask.clamp(0.0, 1.0));

    let darkening = crack * (0.28 + material.edge_darkening * 0.55)
        + wear_mask * material.edge_darkening * 0.18;
    color = scale_color(color, 1.0 - darkening.clamp(0.0, 0.82));
    color = mix_color(color, highlight, (wear_mask * material.wear * 0.22).clamp(0.0, 0.35));
    color
}

fn stone_brick_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let brick_w = 20.0;
    let brick_h = 9.0;
    let row = (py / brick_h).floor() as i32;
    let offset = if row.rem_euclid(2) == 0 { 0.0 } else { brick_w * 0.5 };
    let bx = positive_mod(px + offset, brick_w);
    let by = positive_mod(py, brick_h);
    let edge_distance = bx.min(brick_w - bx).min(by.min(brick_h - by));
    let mortar = line_mask(edge_distance, 0.8 + material.crack_amount * 1.8);
    let cell_x = ((px + offset) / brick_w).floor() as i32;
    let cell_y = (py / brick_h).floor() as i32;
    let cell = hash2d(cell_x, cell_y, seed.wrapping_add(701));
    let chip = (hash2d((px * 0.65) as i32, (py * 0.65) as i32, seed.wrapping_add(709)) - 0.5) * material.wear;
    let value = 0.42 + broad * 0.22 + fine * 0.14 + cell * 0.20 + chip * 0.12;
    let highlight = line_mask(edge_distance, 2.2) * (1.0 - mortar) * 0.18;
    (value, mortar, chip.abs(), highlight)
}

fn cracked_earth_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let cell = 18.0;
    let warp_x = (fbm_tiled(px * 0.035, py * 0.035, period * 0.035, period * 0.035, 3, seed) - 0.5) * 7.0;
    let warp_y = (fbm_tiled(
        px * 0.038 + 31.0,
        py * 0.038 + 11.0,
        period * 0.038,
        period * 0.038,
        3,
        seed.wrapping_add(3),
    ) - 0.5)
        * 7.0;
    let main_crack = voronoi_edge_mask(
        px + warp_x,
        py + warp_y,
        cell,
        period,
        seed.wrapping_add(17),
        0.35 + material.crack_amount * 2.4,
    );
    let hairline = clamp((0.16 - (fine - 0.48).abs()).max(0.0) * material.crack_amount * 3.0, 0.0, 1.0);
    let crack = clamp(main_crack + hairline * 0.45, 0.0, 1.0);
    let value = 0.44 + broad * 0.25 + fine * 0.16;
    (value, crack, material.wear * (1.0 - broad), 0.04 + fine * 0.08)
}

fn rough_stone_layers(material: &MaterialConfig, speck: f32, broad: f32, fine: f32) -> (f32, f32, f32, f32) {
    let crack = clamp((0.34 - fine).max(0.0) * material.crack_amount * 1.8, 0.0, 1.0);
    let value = 0.36 + broad * 0.34 + fine * 0.18 + speck * material.grain * 0.16;
    (value, crack, material.wear * speck, fine * 0.12)
}

fn worn_metal_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let bands = ((py * 0.22).sin() * 0.5 + 0.5) * 0.16;
    let scratch_coord = positive_mod(py + fbm_tiled(px * 0.06, py * 0.06, 64.0, 64.0, 2, seed) * 3.0, 9.0);
    let scratches = line_mask(scratch_coord.min(9.0 - scratch_coord), 0.18 + material.wear * 0.8);
    let value = 0.42 + broad * 0.18 + fine * 0.16 + bands;
    (value, scratches * material.crack_amount, scratches, scratches * 0.28)
}

fn wood_plank_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let plank_w = 10.0;
    let lx = positive_mod(px, plank_w);
    let seam = line_mask(lx.min(plank_w - lx), 0.45 + material.crack_amount * 1.3);
    let grain = fbm_tiled(px * 0.03, py * 0.34, 64.0, 64.0, 4, seed.wrapping_add(41));
    let knot = hash2d((px / 14.0).floor() as i32, (py / 18.0).floor() as i32, seed.wrapping_add(43));
    let value = 0.38 + broad * 0.10 + fine * 0.08 + grain * 0.34 + knot * material.wear * 0.08;
    (value, seam, material.wear * (1.0 - grain), grain * 0.12)
}

fn packed_dirt_layers(material: &MaterialConfig, speck: f32, broad: f32, fine: f32) -> (f32, f32, f32, f32) {
    let pebble = clamp((speck - 0.72) * 4.0, 0.0, 1.0) * material.grain;
    let crack = clamp((0.28 - fine).max(0.0) * material.crack_amount * 1.6, 0.0, 1.0);
    let value = 0.40 + broad * 0.30 + fine * 0.12 + pebble * 0.10;
    (value, crack, material.wear * (1.0 - broad), pebble * 0.18)
}

fn concrete_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let pore = hash2d((px * 2.1) as i32, (py * 2.1) as i32, seed.wrapping_add(83));
    let crack_line = fbm_tiled(px * 0.08, py * 0.08, 64.0, 64.0, 2, seed.wrapping_add(89));
    let crack = clamp((0.18 - (crack_line - 0.5).abs()).max(0.0) * material.crack_amount * 4.0, 0.0, 1.0);
    let value = 0.48 + broad * 0.16 + fine * 0.08 + (pore - 0.5) * material.grain * 0.08;
    (value, crack, material.wear * pore, 0.04)
}

fn ice_frost_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let frost = fbm_tiled(px * 0.12 + 9.0, py * 0.12, 64.0, 64.0, 4, seed.wrapping_add(103));
    let vein = clamp((0.10 - (frost - 0.52).abs()).max(0.0) * material.crack_amount * 5.0, 0.0, 1.0);
    let value = 0.50 + broad * 0.16 + fine * 0.12 + frost * 0.18;
    (value, vein, material.wear * (1.0 - frost), frost * 0.24)
}

fn ash_layers(material: &MaterialConfig, speck: f32, broad: f32, fine: f32) -> (f32, f32, f32, f32) {
    let ember = clamp((speck - 0.92) * 8.0, 0.0, 1.0) * material.wear;
    let crack = clamp((0.25 - fine).max(0.0) * material.crack_amount * 1.8, 0.0, 1.0);
    let value = 0.28 + broad * 0.25 + fine * 0.12 + ember * 0.18;
    (value, crack, material.wear * (1.0 - broad), ember)
}

fn line_mask(distance: f32, width: f32) -> f32 {
    clamp(1.0 - distance / width.max(0.001), 0.0, 1.0)
}

fn voronoi_edge_mask(px: f32, py: f32, cell_size: f32, period: f32, seed: u32, width: f32) -> f32 {
    let cells = (period / cell_size).round().max(3.0) as i32;
    let actual_period = cells as f32 * cell_size;
    let local_x = positive_mod(px, actual_period);
    let local_y = positive_mod(py, actual_period);
    let base_x = (local_x / cell_size).floor() as i32;
    let base_y = (local_y / cell_size).floor() as i32;
    let mut nearest = f32::INFINITY;
    let mut second = f32::INFINITY;

    for oy in -1..=1 {
        for ox in -1..=1 {
            let cell_x = base_x + ox;
            let cell_y = base_y + oy;
            let hash_x = cell_x.rem_euclid(cells);
            let hash_y = cell_y.rem_euclid(cells);
            let jitter_x = hash2d(hash_x, hash_y, seed) * 0.62 + 0.19;
            let jitter_y = hash2d(hash_x, hash_y, seed.wrapping_add(29)) * 0.62 + 0.19;
            let point_x = (cell_x as f32 + jitter_x) * cell_size;
            let point_y = (cell_y as f32 + jitter_y) * cell_size;
            let dx = local_x - point_x;
            let dy = local_y - point_y;
            let distance = dx * dx + dy * dy;

            if distance < nearest {
                second = nearest;
                nearest = distance;
            } else if distance < second {
                second = distance;
            }
        }
    }

    line_mask(second.sqrt() - nearest.sqrt(), width)
}

fn apply_value_contrast(value: f32, contrast: f32) -> f32 {
    clamp((value - 0.5) * contrast + 0.5, 0.0, 1.0)
}

fn mix_color(a: [u8; 3], b: [u8; 3], t: f32) -> [u8; 3] {
    let t = t.clamp(0.0, 1.0);
    [
        lerp(a[0] as f32, b[0] as f32, t).round() as u8,
        lerp(a[1] as f32, b[1] as f32, t).round() as u8,
        lerp(a[2] as f32, b[2] as f32, t).round() as u8,
    ]
}

fn scale_color(color: [u8; 3], factor: f32) -> [u8; 3] {
    [
        (color[0] as f32 * factor).round().clamp(0.0, 255.0) as u8,
        (color[1] as f32 * factor).round().clamp(0.0, 255.0) as u8,
        (color[2] as f32 * factor).round().clamp(0.0, 255.0) as u8,
    ]
}

fn lighten_color(color: [u8; 3], factor: f32) -> [u8; 3] {
    scale_color(color, factor)
}

fn parse_or_fallback(value: &str, fallback: [u8; 3]) -> [u8; 3] {
    let trimmed = value.trim().trim_start_matches('#');
    if trimmed.len() != 6 {
        fallback
    } else {
        parse_hex_color(value)
    }
}

fn srgb_luminance(color: [u8; 4]) -> f32 {
    color[0] as f32 * 0.2126 + color[1] as f32 * 0.7152 + color[2] as f32 * 0.0722
}

fn srgb_luminance_rgb(color: [u8; 3]) -> f32 {
    color[0] as f32 * 0.2126 + color[1] as f32 * 0.7152 + color[2] as f32 * 0.0722
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
