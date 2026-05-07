use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use image::{Rgba, RgbaImage};
use rayon::prelude::*;
use serde::Serialize;

use crate::model::{AppRequest, ExportMode, GeneratedFiles, MaterialConfig, OutputManifest, RenderMode};
use crate::noise::{clamp, fbm_tiled, hash2d, lerp};
use crate::signature::{canonical_signatures, signature_at, Signature};

const ATLAS_COLUMNS: u32 = 8;
const MATERIAL_EXPORT_SIZE: u32 = 512;
const RECIPE_VERSION: u32 = 4;
const EDGE_NOISE_PERIOD_TILES: f32 = 8.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SurfaceZone {
    Top,
    Face,
    Back,
    Empty,
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
    let preview_path = export_file_path(output_dir, &request, "preview", "png");
    preview.save(&preview_path)?;

    let recipe_path = export_file_path(output_dir, &request, "recipe", "json");
    let files = if mode == RenderMode::Draft {
        generated_files_with_preview(&preview_path, &recipe_path)
    } else {
        match request.export_mode {
            ExportMode::Full47 => {
                let atlases = build_full_atlases(&request, &textures, &signatures);
                let material_exports = build_material_exports(&request, &textures);
                let albedo_atlas_path = export_file_path(output_dir, &request, "atlas_albedo", "png");
                let mask_atlas_path = export_file_path(output_dir, &request, "atlas_mask", "png");
                let height_atlas_path = export_file_path(output_dir, &request, "atlas_height", "png");
                let normal_atlas_path = export_file_path(output_dir, &request, "atlas_normal", "png");
                let top_albedo_path = export_file_path(output_dir, &request, "top_albedo", "png");
                let face_albedo_path = export_file_path(output_dir, &request, "face_albedo", "png");
                let base_albedo_path = export_file_path(output_dir, &request, "base_albedo", "png");
                let top_modulation_path = export_file_path(output_dir, &request, "top_modulation", "png");
                let face_modulation_path = export_file_path(output_dir, &request, "face_modulation", "png");
                let top_normal_path = export_file_path(output_dir, &request, "top_normal", "png");
                let face_normal_path = export_file_path(output_dir, &request, "face_normal", "png");

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
            }
            ExportMode::BaseVariantsOnly => {
                let atlas = build_base_variants_atlas(&request, &textures);
                let atlas_path = export_file_path(output_dir, &request, "atlas_albedo", "png");
                atlas.save(&atlas_path)?;

                let mut files = generated_files_with_preview(&preview_path, &recipe_path);
                files.atlas_albedo_png = Some(to_string_path(&atlas_path));
                files
            }
            ExportMode::MaskOnly => {
                let atlas = build_mask_atlas(&request, &signatures);
                let atlas_path = export_file_path(output_dir, &request, "atlas_mask", "png");
                atlas.save(&atlas_path)?;

                let mut files = generated_files_with_preview(&preview_path, &recipe_path);
                files.atlas_mask_png = Some(to_string_path(&atlas_path));
                files
            }
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
        export_mode: request.export_mode.as_str().to_string(),
        preset: request.preset.clone(),
        tile_size: request.tile_size,
        variants: request.variants,
        signature_count: manifest_signature_count(&request, signatures.len()),
        total_tiles: manifest_total_tiles(&request, signatures.len()),
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

fn export_file_path(output_dir: &Path, request: &AppRequest, slot: &str, extension: &str) -> PathBuf {
    output_dir.join(format!("{}_{}.{}", request.asset_name, slot, extension))
}

fn generated_files_with_preview(preview_path: &Path, recipe_path: &Path) -> GeneratedFiles {
    GeneratedFiles {
        preview_png: to_string_path(preview_path),
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
        recipe_json: to_string_path(recipe_path),
    }
}

fn manifest_signature_count(request: &AppRequest, full_signature_count: usize) -> usize {
    match request.export_mode {
        ExportMode::BaseVariantsOnly => 1,
        ExportMode::Full47 | ExportMode::MaskOnly => full_signature_count,
    }
}

fn manifest_total_tiles(request: &AppRequest, full_signature_count: usize) -> usize {
    manifest_signature_count(request, full_signature_count) * request.variants as usize
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
    let signature_count = signatures.len() as u32;
    let total = signature_count * request.variants;
    let rows = total.div_ceil(ATLAS_COLUMNS);
    let width = ATLAS_COLUMNS * tile_size;
    let height = rows * tile_size;

    let tiles: Vec<(u32, TileBuffers)> = (0..total)
        .into_par_iter()
        .map(|atlas_index| {
            let variant = atlas_index / signature_count;
            let sig_idx = (atlas_index % signature_count) as usize;
            let signature = &signatures[sig_idx];
            let tile = render_tile(request, textures, signature, variant, 0, 0);
            (atlas_index, tile)
        })
        .collect();

    let mut albedo = RgbaImage::new(width, height);
    let mut mask = RgbaImage::new(width, height);
    let mut height_img = RgbaImage::new(width, height);
    let mut normal = RgbaImage::new(width, height);

    for (atlas_index, tile) in tiles {
        let col = atlas_index % ATLAS_COLUMNS;
        let row = atlas_index / ATLAS_COLUMNS;
        let dx = col * tile_size;
        let dy = row * tile_size;
        blit_exact(&mut albedo, &tile.albedo, dx, dy);
        blit_exact(&mut mask, &tile.mask, dx, dy);
        blit_exact(&mut height_img, &tile.height, dx, dy);
        blit_exact(&mut normal, &tile.normal, dx, dy);
    }

    Atlases {
        albedo,
        mask,
        height: height_img,
        normal,
    }
}

fn build_base_variants_atlas(request: &AppRequest, textures: &TextureSet) -> RgbaImage {
    let tile_size = request.tile_size;
    let width = tile_size * request.variants;
    let height = tile_size;
    let tiles: Vec<(u32, RgbaImage)> = (0..request.variants)
        .into_par_iter()
        .map(|variant| {
            let tile = render_base_variant_tile(request, textures, variant);
            (variant, tile)
        })
        .collect();

    let mut atlas = RgbaImage::new(width, height);
    for (variant, tile) in tiles {
        blit_exact(&mut atlas, &tile, variant * tile_size, 0);
    }
    atlas
}

fn render_base_variant_tile(request: &AppRequest, textures: &TextureSet, variant: u32) -> RgbaImage {
    let size = request.tile_size;
    let (material, base_color, texture, seed) = material_slot(request, textures, MaterialKind::Base);
    let variant_seed = request
        .seed
        .wrapping_add(variant.wrapping_mul(4_091))
        .wrapping_add(17_371);
    let mut image = RgbaImage::new(size, size);

    for y in 0..size {
        for x in 0..size {
            let local_seed = variant_seed
                .wrapping_add(y.wrapping_mul(4_099))
                .wrapping_add(x)
                .wrapping_mul(13);
            let color = sample_material_color(
                material,
                base_color,
                texture,
                request.texture_scale,
                request.texture_color_overlay,
                size,
                x,
                y,
                seed.wrapping_add(local_seed),
                1.0,
            );
            image.put_pixel(x, y, rgba(color, 255));
        }
    }

    image
}

fn build_mask_atlas(request: &AppRequest, signatures: &[Signature]) -> RgbaImage {
    let tile_size = request.tile_size;
    let signature_count = signatures.len() as u32;
    let total = signature_count * request.variants;
    let rows = total.div_ceil(ATLAS_COLUMNS);
    let width = ATLAS_COLUMNS * tile_size;
    let height = rows * tile_size;

    let tiles: Vec<(u32, RgbaImage)> = (0..total)
        .into_par_iter()
        .map(|atlas_index| {
            let sig_idx = (atlas_index % signature_count) as usize;
            let signature = &signatures[sig_idx];
            let tile = render_mask_tile(request, signature, 0, 0);
            (atlas_index, tile)
        })
        .collect();

    let mut atlas = RgbaImage::new(width, height);
    for (atlas_index, tile) in tiles {
        let col = atlas_index % ATLAS_COLUMNS;
        let row = atlas_index / ATLAS_COLUMNS;
        blit_exact(&mut atlas, &tile, col * tile_size, row * tile_size);
    }
    atlas
}

fn render_mask_tile(request: &AppRequest, signature: &Signature, origin_x: u32, origin_y: u32) -> RgbaImage {
    let size = request.tile_size;
    let mut mask = RgbaImage::new(size, size);
    let geometry_seed = request.seed;

    for y in 0..size {
        for x in 0..size {
            let (_, zone) = sample_height(
                request,
                signature,
                geometry_seed,
                x as f32,
                y as f32,
                (origin_x + x) as f32,
                (origin_y + y) as f32,
            );
            let top_mask = if zone == SurfaceZone::Top { 255 } else { 0 };
            let face_mask = if zone == SurfaceZone::Face { 255 } else { 0 };
            let back_mask = if zone == SurfaceZone::Back { 255 } else { 0 };
            let occupancy = if zone == SurfaceZone::Empty { 0 } else { 255 };
            mask.put_pixel(x, y, Rgba([top_mask, face_mask, back_mask, occupancy]));
        }
    }

    mask
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
            request.normal_strength,
        ),
        face_normal: build_wrapped_normal_image(
            &face_values,
            MATERIAL_EXPORT_SIZE,
            MATERIAL_EXPORT_SIZE,
            request.normal_strength,
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
    let pixel_count = (width as usize) * (height as usize);
    let mut raw = vec![0_u8; pixel_count * 4];
    let mut values = vec![0.0_f32; pixel_count];

    raw.par_chunks_mut(4)
        .zip(values.par_iter_mut())
        .enumerate()
        .for_each(|(i, (pixel, value))| {
            let x = (i as u32) % width;
            let y = (i as u32) / width;
            let base = sample_material_base(material, texture, request.texture_scale, width, x, y, seed);
            *value = srgb_luminance_rgb(base.rgb) / 255.0;
            let color = apply_material_tint(base, tint, request.texture_color_overlay, 1.0);
            pixel[0] = color[0];
            pixel[1] = color[1];
            pixel[2] = color[2];
            pixel[3] = 255;
        });

    let albedo = RgbaImage::from_raw(width, height, raw)
        .expect("buffer size matches dimensions");
    (albedo, values)
}

fn build_scalar_image(values: &[f32], width: u32, height: u32) -> RgbaImage {
    let mut raw = vec![0_u8; (width as usize) * (height as usize) * 4];
    raw.par_chunks_mut(4).enumerate().for_each(|(i, pixel)| {
        let x = ((i as u32) % width) as i32;
        let y = ((i as u32) / width) as i32;
        let value = sample_wrapped_value(values, width, height, x, y);
        let byte = (clamp(value, 0.0, 1.0) * 255.0).round() as u8;
        pixel[0] = byte;
        pixel[1] = byte;
        pixel[2] = byte;
        pixel[3] = 255;
    });
    RgbaImage::from_raw(width, height, raw).expect("buffer size matches dimensions")
}

fn build_wrapped_normal_image(values: &[f32], width: u32, height: u32, strength: f32) -> RgbaImage {
    let mut raw = vec![0_u8; (width as usize) * (height as usize) * 4];
    raw.par_chunks_mut(4).enumerate().for_each(|(i, pixel)| {
        let xi = ((i as u32) % width) as i32;
        let yi = ((i as u32) / width) as i32;
        let (dx, dy) = sobel_gradient_wrapped(values, width, height, xi, yi);
        let encoded = encode_normal_from_gradient(dx, dy, strength);
        pixel[0] = encoded[0];
        pixel[1] = encoded[1];
        pixel[2] = encoded[2];
        pixel[3] = 255;
    });
    RgbaImage::from_raw(width, height, raw).expect("buffer size matches dimensions")
}

fn sample_wrapped_value(values: &[f32], width: u32, height: u32, x: i32, y: i32) -> f32 {
    let sx = x.rem_euclid(width as i32) as u32;
    let sy = y.rem_euclid(height as i32) as u32;
    values[(sy * width + sx) as usize]
}

fn sobel_gradient_wrapped(values: &[f32], width: u32, height: u32, x: i32, y: i32) -> (f32, f32) {
    let at = |ox: i32, oy: i32| sample_wrapped_value(values, width, height, x + ox, y + oy);
    sobel_gradient_from_samples(at)
}

fn build_map_preview(request: &AppRequest, textures: &TextureSet) -> Result<RgbaImage> {
    let width = request.map.width * request.tile_size;
    let height = request.map.height * request.tile_size;
    let mut preview = RgbaImage::new(width, height);

    let positions: Vec<(i32, i32)> = (0..request.map.height as i32)
        .flat_map(|y| (0..request.map.width as i32).map(move |x| (x, y)))
        .collect();

    let cell_renders: Vec<(u32, u32, RgbaImage)> = positions
        .into_par_iter()
        .map(|(map_x, map_y)| {
            let cell_index = (map_y as u32 * request.map.width + map_x as u32) as usize;
            let filled = request.map.cells.get(cell_index).copied().unwrap_or(0) > 0;
            let origin_x = map_x as u32 * request.tile_size;
            let origin_y = map_y as u32 * request.tile_size;
            let img = if filled {
                let signature = signature_at(&request.map, map_x, map_y);
                let variant = request
                    .forced_variant
                    .unwrap_or_else(|| pick_variant(map_x, map_y, request.seed, request.variants));
                let tile = render_tile(request, textures, &signature, variant, origin_x, origin_y);
                extract_mode_image(tile, &request.preview_mode)
            } else {
                render_empty_cell(textures, request, origin_x, origin_y)
            };
            (origin_x, origin_y, img)
        })
        .collect();

    for (origin_x, origin_y, img) in cell_renders {
        blit_exact(&mut preview, &img, origin_x, origin_y);
    }

    Ok(preview)
}

fn render_empty_cell(textures: &TextureSet, request: &AppRequest, origin_x: u32, origin_y: u32) -> RgbaImage {
    let (material, base_color, texture, seed) = material_slot(request, textures, MaterialKind::Base);
    let mut img = RgbaImage::new(request.tile_size, request.tile_size);
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
            img.put_pixel(local_x, local_y, rgba(color, 255));
        }
    }
    img
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
    let normal_heights = blur_heights_3x3(size, &heights);

    let mut albedo = RgbaImage::new(size, size);
    let mut mask = RgbaImage::new(size, size);
    let mut height_img = RgbaImage::new(size, size);
    let mut normal = RgbaImage::new(size, size);

    let (top_material, top_color, top_texture, top_seed) = material_slot(request, textures, MaterialKind::Top);
    let (face_material, face_color, face_texture, face_seed) = material_slot(request, textures, MaterialKind::Face);
    let (base_material, base_color, base_texture, base_seed) = material_slot(request, textures, MaterialKind::Base);
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
                SurfaceZone::Empty => sample_material_color(
                    base_material,
                    base_color,
                    base_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    sample_x,
                    sample_y,
                    base_seed.wrapping_add(local_seed),
                    0.92,
                ),
            };

            let shaded = maybe_apply_height_shading(
                base,
                height_value,
                zone,
                request.bake_height_shading,
            );
            albedo.put_pixel(x, y, rgba(shaded, 255));

            let top_mask = if zone == SurfaceZone::Top { 255 } else { 0 };
            let face_mask = if zone == SurfaceZone::Face { 255 } else { 0 };
            let back_mask = if zone == SurfaceZone::Back { 255 } else { 0 };
            let occupancy = if zone == SurfaceZone::Empty { 0 } else { 255 };
            mask.put_pixel(x, y, Rgba([top_mask, face_mask, back_mask, occupancy]));

            let height_byte = (clamp(height_value, 0.0, 1.0) * 255.0).round() as u8;
            height_img.put_pixel(x, y, Rgba([height_byte, height_byte, height_byte, occupancy]));

            let encoded = if zone == SurfaceZone::Empty {
                [128, 128, 255]
            } else {
                encode_normal(size, &normal_heights, x, y, request.normal_strength)
            };
            normal.put_pixel(x, y, Rgba([encoded[0], encoded[1], encoded[2], occupancy]));
        }
    }

    TileBuffers {
        albedo,
        mask,
        height: height_img,
        normal,
    }
}

fn extract_mode_image(tile: TileBuffers, preview_mode: &str) -> RgbaImage {
    match preview_mode {
        "albedo" | "composite" => tile.albedo,
        "mask" => tile.mask,
        "height" => tile.height,
        "normal" => tile.normal,
        _ => tile.albedo,
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

    let outer_radius = request.outer_corner_radius as f32;
    if outer_radius > 0.0 {
        if let (Some(north), Some(east)) = (north_open_boundary, east_open_boundary) {
            set_rounded_outer_corner_height(
                request,
                &mut min_height,
                &mut min_zone,
                x - (east - outer_radius),
                (north + outer_radius) - y,
                outer_radius,
                (size - 1.0 - east).max(north),
            );
        }
        if let (Some(south), Some(east)) = (south_open_boundary, east_open_boundary) {
            set_rounded_outer_corner_height(
                request,
                &mut min_height,
                &mut min_zone,
                x - (east - outer_radius),
                y - (south - outer_radius),
                outer_radius,
                (size - 1.0 - east).max(size - 1.0 - south),
            );
        }
        if let (Some(south), Some(west)) = (south_open_boundary, west_open_boundary) {
            set_rounded_outer_corner_height(
                request,
                &mut min_height,
                &mut min_zone,
                (west + outer_radius) - x,
                y - (south - outer_radius),
                outer_radius,
                west.max(size - 1.0 - south),
            );
        }
        if let (Some(north), Some(west)) = (north_open_boundary, west_open_boundary) {
            set_rounded_outer_corner_height(
                request,
                &mut min_height,
                &mut min_zone,
                (west + outer_radius) - x,
                (north + outer_radius) - y,
                outer_radius,
                west.max(north),
            );
        }
    }

    let notch_side = side_depth.max(2.0);
    let notch_north = north_depth.max(2.0);
    let inner_radius = request.inner_corner_radius as f32;

    if signature.notch_ne {
        let x_start = size - notch_side
            + edge_jitter(world_y, seed.wrapping_add(53), rough_px * 0.8, edge_period);
        let y_end = notch_north
            + edge_jitter(world_x, seed.wrapping_add(59), rough_px * 0.8, edge_period);
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(x - x_start, y_end - y, notch_side, notch_north, inner_radius) {
                set_min_height(
                    &mut min_height,
                    &mut min_zone,
                    face_height_for_progress(request, progress),
                    SurfaceZone::Face,
                );
            }
        } else if x > x_start && y < y_end {
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
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(x_end - x, y_end - y, notch_side, notch_north, inner_radius) {
                set_min_height(
                    &mut min_height,
                    &mut min_zone,
                    face_height_for_progress(request, progress),
                    SurfaceZone::Face,
                );
            }
        } else if x < x_end && y < y_end {
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
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(x - x_start, y - y_start, notch_side, request.south_height as f32, inner_radius) {
                set_min_height(
                    &mut min_height,
                    &mut min_zone,
                    face_height_for_progress(request, progress),
                    SurfaceZone::Face,
                );
            }
        } else if x > x_start && y > y_start {
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
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(x_end - x, y - y_start, notch_side, request.south_height as f32, inner_radius) {
                set_min_height(
                    &mut min_height,
                    &mut min_zone,
                    face_height_for_progress(request, progress),
                    SurfaceZone::Face,
                );
            }
        } else if x < x_end && y > y_start {
            let progress = ((y - y_start) / (size - 1.0 - y_start).max(1.0)).clamp(0.0, 1.0);
            set_min_height(
                &mut min_height,
                &mut min_zone,
                face_height_for_progress(request, progress),
                SurfaceZone::Face,
            );
        }
    }

    if rounded_outer_corner_is_empty(request, signature, x, y) {
        return (0.0, SurfaceZone::Empty);
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

fn set_rounded_outer_corner_height(
    request: &AppRequest,
    current_height: &mut f32,
    current_zone: &mut SurfaceZone,
    dx: f32,
    dy: f32,
    radius: f32,
    outward_span: f32,
) {
    if dx <= 0.0 || dy <= 0.0 || radius <= 0.0 {
        return;
    }

    let distance = (dx * dx + dy * dy).sqrt();
    if distance <= radius {
        return;
    }

    let progress = ((distance - radius) / outward_span.max(1.0)).clamp(0.0, 1.0);
    set_min_height(
        current_height,
        current_zone,
        face_height_for_progress(request, progress),
        SurfaceZone::Face,
    );
}

fn rounded_inner_notch_progress(
    dx: f32,
    dy: f32,
    notch_width: f32,
    notch_height: f32,
    radius: f32,
) -> Option<f32> {
    if dx <= 0.0 || dy <= 0.0 {
        return None;
    }

    let radius = radius.min(notch_width).min(notch_height);
    let distance = (dx * dx + dy * dy).sqrt();
    if distance <= radius {
        return None;
    }

    Some(((distance - radius) / notch_width.max(notch_height).max(1.0)).clamp(0.0, 1.0))
}

fn rounded_outer_corner_is_empty(request: &AppRequest, signature: &Signature, x: f32, y: f32) -> bool {
    let radius = request.outer_corner_radius as f32;
    if radius <= 0.0 {
        return false;
    }

    let size = request.tile_size as f32 - 1.0;
    let max_radius = size * 0.5;
    let radius = radius.min(max_radius);
    if radius <= 0.0 {
        return false;
    }

    (signature.open_n && signature.open_e && outside_corner_arc(x, y, size - radius, radius, radius, 1.0, -1.0))
        || (signature.open_s && signature.open_e && outside_corner_arc(x, y, size - radius, size - radius, radius, 1.0, 1.0))
        || (signature.open_s && signature.open_w && outside_corner_arc(x, y, radius, size - radius, radius, -1.0, 1.0))
        || (signature.open_n && signature.open_w && outside_corner_arc(x, y, radius, radius, radius, -1.0, -1.0))
}

fn outside_corner_arc(
    x: f32,
    y: f32,
    center_x: f32,
    center_y: f32,
    radius: f32,
    sign_x: f32,
    sign_y: f32,
) -> bool {
    let dx = (x - center_x) * sign_x;
    let dy = (y - center_y) * sign_y;
    if dx <= 0.0 || dy <= 0.0 {
        return false;
    }

    dx * dx + dy * dy > radius * radius
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

#[derive(Clone, Copy)]
struct MaterialBaseSample {
    rgb: [u8; 3],
    is_image_source: bool,
}

fn sample_material_base(
    material: &MaterialConfig,
    texture: Option<&LoadedTexture>,
    texture_scale: f32,
    tile_size: u32,
    x: u32,
    y: u32,
    seed: u32,
) -> MaterialBaseSample {
    match material.source.as_str() {
        "image" => {
            if let Some(texture) = texture {
                let sample_scale = 1.0 / texture_scale.max(0.001);
                let sample = texture.sample_filtered(
                    (x as f32 + 0.5) * sample_scale,
                    (y as f32 + 0.5) * sample_scale,
                    sample_scale,
                );
                MaterialBaseSample {
                    rgb: [sample[0], sample[1], sample[2]],
                    is_image_source: true,
                }
            } else {
                MaterialBaseSample {
                    rgb: procedural_layer_material(
                        material,
                        seed,
                        x as f32,
                        y as f32,
                        tile_size as f32,
                        [128, 128, 128],
                    ),
                    is_image_source: false,
                }
            }
        }
        "flat" => MaterialBaseSample {
            rgb: parse_hex_color(&material.color_a),
            is_image_source: false,
        },
        _ => MaterialBaseSample {
            rgb: procedural_layer_material(
                material,
                seed,
                x as f32,
                y as f32,
                tile_size as f32,
                [128, 128, 128],
            ),
            is_image_source: false,
        },
    }
}

#[cfg(test)]
mod tests {
    use crate::model::{default_request, ExportMode};
    use std::fs as test_fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    fn test_output_dir(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be after unix epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cliff_forge_{name}_{nonce}"));
        test_fs::create_dir_all(&dir).expect("test output dir should be creatable");
        dir
    }

    fn image_material() -> MaterialConfig {
        MaterialConfig {
            source: "image".to_string(),
            kind: "rough_stone".to_string(),
            scale: 1.0,
            contrast: 1.0,
            crack_amount: 0.0,
            wear: 0.0,
            grain: 0.0,
            edge_darkening: 0.0,
            seed: 0,
            color_a: "#000000".to_string(),
            color_b: "#ffffff".to_string(),
            highlight: "#ffffff".to_string(),
        }
    }

    #[test]
    fn texture_scale_above_one_zooms_texture_without_box_blur() {
        let texture = LoadedTexture {
            image: RgbaImage::from_fn(4, 1, |x, _| {
                Rgba([(x * 64) as u8, 0, 0, 255])
            }),
        };

        let sample = sample_material_base(
            &image_material(),
            Some(&texture),
            4.0,
            32,
            0,
            0,
            0,
        );

        assert!(
            sample.rgb[0] < 24,
            "expected scale 4.0 to magnify the first texel, got red={}",
            sample.rgb[0]
        );
        assert!(sample.is_image_source);
    }

    #[test]
    fn sobel_normal_uses_diagonal_height_signal() {
        let size = 3;
        let mut heights = vec![0.0_f32; (size * size) as usize];
        heights[0] = 1.0;

        let encoded = encode_normal(size, &heights, 1, 1, 2.0);

        assert_ne!(encoded[0], 128, "Sobel should read diagonal X contribution");
        assert_ne!(encoded[1], 128, "Sobel should read diagonal Y contribution");
    }

    #[test]
    fn wrapped_and_tile_normals_share_gradient_formula() {
        let size = 5;
        let heights: Vec<f32> = (0..size)
            .flat_map(|y| (0..size).map(move |x| (x as f32 + y as f32 * 2.0) / 16.0))
            .collect();
        let strength = 2.0;

        let tile_normal = encode_normal(size, &heights, 2, 2, strength);
        let wrapped = build_wrapped_normal_image(&heights, size, size, strength);
        let wrapped_normal = wrapped.get_pixel(2, 2).0;

        for channel in 0..3 {
            assert!(
                (tile_normal[channel] as i16 - wrapped_normal[channel] as i16).abs() <= 1,
                "normal channel {channel} diverged: tile={} wrapped={}",
                tile_normal[channel],
                wrapped_normal[channel]
            );
        }
    }

    #[test]
    fn height_shading_can_be_disabled_for_flat_albedo() {
        let color = [100, 150, 200];

        assert_eq!(
            maybe_apply_height_shading(color, 0.2, SurfaceZone::Face, false),
            color
        );
        assert_ne!(
            maybe_apply_height_shading(color, 0.2, SurfaceZone::Face, true),
            color
        );
    }

    #[test]
    fn outer_corner_radius_rounds_exposed_face_corner() {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.outer_corner_radius = 12;
        let request = request.sanitized();
        let signature = Signature::create(true, false, false, false, false, false, true, true);

        let (height, zone) = sample_height(
            &request,
            &signature,
            request.seed,
            45.0,
            45.0,
            45.0,
            45.0,
        );

        assert_eq!(zone, SurfaceZone::Face);
        assert!(
            height < 0.99,
            "rounded corner should cut the old square top corner into the face zone, got height={height}"
        );
    }

    #[test]
    fn outer_corner_radius_clips_square_face_silhouette() {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.outer_corner_radius = 12;
        let request = request.sanitized();
        let signature = Signature::create(true, false, false, false, false, false, true, true);
        let tile = render_mask_tile(&request, &signature, 0, 0);

        assert_eq!(
            tile.get_pixel(63, 63).0[3],
            0,
            "rounded face geometry should clear occupancy in the old square corner"
        );
    }

    #[test]
    fn inner_corner_radius_rounds_notch_cut() {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 16;
        request.side_height = 16;
        request.roughness = 0.0;
        request.outer_corner_radius = 0;
        request.inner_corner_radius = 10;
        let request = request.sanitized();
        let signature = Signature::create(true, false, true, true, true, true, true, true);

        let (height, zone) = sample_height(
            &request,
            &signature,
            request.seed,
            51.0,
            13.0,
            51.0,
            13.0,
        );

        assert_eq!(zone, SurfaceZone::Top);
        assert_eq!(height, 1.0);
    }

    #[test]
    fn export_file_names_are_prefixed_with_asset_name() {
        let output_dir = Path::new("exports");
        let mut request = default_request();
        request.asset_name = "plains_ground".to_string();
        let request = request.sanitized();

        assert_eq!(
            export_file_path(output_dir, &request, "top_albedo", "png"),
            output_dir.join("plains_ground_top_albedo.png")
        );
        assert_eq!(
            export_file_path(output_dir, &request, "recipe", "json"),
            output_dir.join("plains_ground_recipe.json")
        );
    }

    #[test]
    fn base_variants_only_writes_one_by_variant_albedo_atlas() {
        let output_dir = test_output_dir("base_variants_only");
        let mut request = default_request();
        request.asset_name = "plains_ground".to_string();
        request.export_mode = ExportMode::BaseVariantsOnly;
        request.tile_size = 32;
        request.variants = 6;
        request.normal_strength = 1.0;
        let request = request.sanitized();

        let manifest = run_request(RenderMode::Full, request, &output_dir)
            .expect("base variants export should render");
        let atlas_path = manifest
            .files
            .atlas_albedo_png
            .as_deref()
            .expect("base variants mode should write an albedo atlas");
        let atlas = image::open(atlas_path)
            .expect("base variants atlas should be readable")
            .to_rgba8();

        assert_eq!(atlas.dimensions(), (32 * 6, 32));
        assert!(manifest.files.atlas_mask_png.is_none());
        assert!(manifest.files.top_albedo_png.is_none());
        assert!(!output_dir.join("plains_ground_atlas_mask.png").exists());
    }

    #[test]
    fn mask_only_writes_mask_atlas_and_skips_material_exports() {
        let output_dir = test_output_dir("mask_only");
        let mut request = default_request();
        request.asset_name = "plains_ground".to_string();
        request.export_mode = ExportMode::MaskOnly;
        request.tile_size = 32;
        request.variants = 6;
        request.normal_strength = 1.0;
        let request = request.sanitized();

        let manifest = run_request(RenderMode::Full, request, &output_dir)
            .expect("mask-only export should render");
        let mask_path = manifest
            .files
            .atlas_mask_png
            .as_deref()
            .expect("mask-only mode should write mask atlas");

        assert!(Path::new(mask_path).exists());
        assert!(manifest.files.atlas_albedo_png.is_none());
        assert!(manifest.files.top_albedo_png.is_none());
        assert!(!output_dir.join("plains_ground_atlas_albedo.png").exists());
        assert!(!output_dir.join("plains_ground_top_albedo.png").exists());
    }
}

fn apply_material_tint(
    base: MaterialBaseSample,
    tint: [u8; 3],
    texture_color_overlay: bool,
    brightness: f32,
) -> [u8; 3] {
    let tint_factor = if base.is_image_source && texture_color_overlay {
        tint
    } else {
        [255, 255, 255]
    };
    [
        ((base.rgb[0] as f32 * (tint_factor[0] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
        ((base.rgb[1] as f32 * (tint_factor[1] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
        ((base.rgb[2] as f32 * (tint_factor[2] as f32 / 255.0) * brightness).round() as i32).clamp(0, 255) as u8,
    ]
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
    let base = sample_material_base(material, texture, texture_scale, tile_size, x, y, seed);
    apply_material_tint(base, tint, texture_color_overlay, brightness)
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
    let feature_period = (tile_period * scale).max(1.0);
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
        "stone_bricks" => stone_brick_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "cracked_earth" => cracked_earth_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "worn_metal" => worn_metal_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "wood_planks" => wood_plank_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "packed_dirt" => packed_dirt_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "concrete" => concrete_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "ice_frost" => ice_frost_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "ash_burnt_ground" => ash_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "snow" => snow_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "sand" => sand_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "moss" => moss_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "gravel" => gravel_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "rusty_metal" => rusty_metal_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "concrete_floor" => concrete_floor_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        "ribbed_steel" => ribbed_steel_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
        _ => rough_stone_layers(material, seed, px, py, period, feature_period, speck, broad, fine),
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
    _period: f32,
    feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let brick_w = (feature_period * 0.3125).max(2.0);
    let brick_h = (feature_period * 0.140625).max(1.0);
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
    feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let cell = (feature_period * 0.28125).max(2.0);
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

fn rough_stone_layers(
    material: &MaterialConfig,
    _seed: u32,
    _px: f32,
    _py: f32,
    _period: f32,
    _feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let crack = clamp((0.34 - fine).max(0.0) * material.crack_amount * 1.8, 0.0, 1.0);
    let value = 0.36 + broad * 0.34 + fine * 0.18 + speck * material.grain * 0.16;
    (value, crack, material.wear * speck, fine * 0.12)
}

fn worn_metal_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let scratch_period = (feature_period * 0.140625).max(2.0);
    let bands = ((py * 0.22).sin() * 0.5 + 0.5) * 0.16;
    let warp = fbm_tiled(px * 0.06, py * 0.06, period * 0.06, period * 0.06, 2, seed) * 3.0;
    let scratch_coord = positive_mod(py + warp, scratch_period);
    let scratches = line_mask(
        scratch_coord.min(scratch_period - scratch_coord),
        0.18 + material.wear * 0.8,
    );
    let value = 0.42 + broad * 0.18 + fine * 0.16 + bands;
    (value, scratches * material.crack_amount, scratches, scratches * 0.28)
}

fn wood_plank_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let plank_w = (feature_period * 0.15625).max(2.0);
    let lx = positive_mod(px, plank_w);
    let seam = line_mask(lx.min(plank_w - lx), 0.45 + material.crack_amount * 1.3);
    let grain = fbm_tiled(px * 0.03, py * 0.34, period * 0.03, period * 0.34, 4, seed.wrapping_add(41));
    let knot_x = (feature_period * 0.21875).max(2.0);
    let knot_y = (feature_period * 0.28125).max(2.0);
    let knot = hash2d(
        (px / knot_x).floor() as i32,
        (py / knot_y).floor() as i32,
        seed.wrapping_add(43),
    );
    let value = 0.38 + broad * 0.10 + fine * 0.08 + grain * 0.34 + knot * material.wear * 0.08;
    (value, seam, material.wear * (1.0 - grain), grain * 0.12)
}

fn packed_dirt_layers(
    material: &MaterialConfig,
    _seed: u32,
    _px: f32,
    _py: f32,
    _period: f32,
    _feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
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
    period: f32,
    _feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let pore = hash2d((px * 2.1) as i32, (py * 2.1) as i32, seed.wrapping_add(83));
    let crack_line = fbm_tiled(px * 0.08, py * 0.08, period * 0.08, period * 0.08, 2, seed.wrapping_add(89));
    let crack = clamp((0.18 - (crack_line - 0.5).abs()).max(0.0) * material.crack_amount * 4.0, 0.0, 1.0);
    let value = 0.48 + broad * 0.16 + fine * 0.08 + (pore - 0.5) * material.grain * 0.08;
    (value, crack, material.wear * pore, 0.04)
}

fn ice_frost_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    _feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let frost = fbm_tiled(px * 0.12 + 9.0, py * 0.12, period * 0.12, period * 0.12, 4, seed.wrapping_add(103));
    let vein = clamp((0.10 - (frost - 0.52).abs()).max(0.0) * material.crack_amount * 5.0, 0.0, 1.0);
    let value = 0.50 + broad * 0.16 + fine * 0.12 + frost * 0.18;
    (value, vein, material.wear * (1.0 - frost), frost * 0.24)
}

fn ash_layers(
    material: &MaterialConfig,
    _seed: u32,
    _px: f32,
    _py: f32,
    _period: f32,
    _feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let ember = clamp((speck - 0.92) * 8.0, 0.0, 1.0) * material.wear;
    let crack = clamp((0.25 - fine).max(0.0) * material.crack_amount * 1.8, 0.0, 1.0);
    let value = 0.28 + broad * 0.25 + fine * 0.12 + ember * 0.18;
    (value, crack, material.wear * (1.0 - broad), ember)
}

fn snow_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    _feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let drift = fbm_tiled(
        px * 0.07 + 5.0,
        py * 0.07 + 13.0,
        period * 0.07,
        period * 0.07,
        3,
        seed.wrapping_add(211),
    );
    let sparkle = clamp((speck - 0.94) * 16.0, 0.0, 1.0) * (0.4 + material.grain * 0.6);
    let crack = clamp((0.18 - fine).max(0.0) * material.crack_amount * 0.8, 0.0, 1.0);
    let value = 0.62 + drift * 0.20 + broad * 0.10 + fine * 0.06;
    (value, crack, material.wear * (1.0 - drift), sparkle * 0.55)
}

fn sand_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let ripple_period = (feature_period * 0.125).max(2.0);
    let warp = (fbm_tiled(
        px * 0.05,
        py * 0.05,
        period * 0.05,
        period * 0.05,
        2,
        seed.wrapping_add(241),
    ) - 0.5)
        * 4.0;
    let ripple = (((py + warp) / ripple_period) * std::f32::consts::TAU).sin() * 0.5 + 0.5;
    let pebble = clamp((speck - 0.84) * 5.0, 0.0, 1.0) * material.grain;
    let value = 0.44 + broad * 0.20 + fine * 0.10 + ripple * 0.10 + pebble * 0.10;
    let highlight = ripple * 0.10 + pebble * 0.18;
    (value, 0.0, material.wear * fine, highlight)
}

fn moss_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    _feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let blob = fbm_tiled(
        px * 0.06 + 13.0,
        py * 0.06 + 7.0,
        period * 0.06,
        period * 0.06,
        4,
        seed.wrapping_add(151),
    );
    let cluster = (blob - 0.45).max(0.0) * 1.6;
    let spores = clamp((speck - 0.92) * 12.0, 0.0, 1.0);
    let value = 0.32 + broad * 0.14 + fine * 0.10 + cluster * 0.20;
    let crack = clamp((0.20 - fine).max(0.0) * material.crack_amount * 0.6, 0.0, 1.0);
    let highlight = spores * 0.40 + cluster * 0.08;
    (value, crack, material.wear * (1.0 - cluster), highlight)
}

fn gravel_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let cell_size = (feature_period * 0.10).max(2.0);
    let edge = voronoi_edge_mask(
        px,
        py,
        cell_size,
        period,
        seed.wrapping_add(331),
        0.6 + material.crack_amount * 1.4,
    );
    let pebble_var = fbm_tiled(
        px * 0.16,
        py * 0.16,
        period * 0.16,
        period * 0.16,
        2,
        seed.wrapping_add(337),
    );
    let value =
        0.30 + broad * 0.16 + fine * 0.08 + pebble_var * 0.30 + (speck - 0.5) * material.grain * 0.18;
    let highlight = clamp((1.0 - edge) * pebble_var * 0.20, 0.0, 1.0);
    (value, edge, material.wear * (1.0 - pebble_var), highlight)
}

fn rusty_metal_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    period: f32,
    feature_period: f32,
    speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let scratch_period = (feature_period * 0.140625).max(2.0);
    let warp = fbm_tiled(
        px * 0.06,
        py * 0.06,
        period * 0.06,
        period * 0.06,
        2,
        seed.wrapping_add(401),
    ) * 3.0;
    let scratch_coord = positive_mod(py + warp, scratch_period);
    let scratches = line_mask(
        scratch_coord.min(scratch_period - scratch_coord),
        0.18 + material.wear * 0.6,
    );
    let rust = fbm_tiled(
        px * 0.08 + 23.0,
        py * 0.08,
        period * 0.08,
        period * 0.08,
        4,
        seed.wrapping_add(409),
    );
    let rust_mask = clamp((rust - 0.42) * 4.0, 0.0, 1.0);
    let pit = clamp((speck - 0.78) * 8.0, 0.0, 1.0) * (0.4 + material.crack_amount * 0.8);
    let value = 0.36 + broad * 0.18 + fine * 0.16 + rust_mask * 0.18 - pit * 0.28;
    let crack = clamp(scratches * material.crack_amount + pit, 0.0, 1.0);
    (value, crack, scratches + rust_mask * 0.5, rust_mask * 0.30)
}

fn concrete_floor_layers(
    material: &MaterialConfig,
    seed: u32,
    px: f32,
    py: f32,
    _period: f32,
    feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let tile_w = (feature_period * 0.5).max(4.0);
    let bx = positive_mod(px, tile_w);
    let by = positive_mod(py, tile_w);
    let edge_dist = bx.min(tile_w - bx).min(by).min(tile_w - by);
    let seam = line_mask(edge_dist, 0.5 + material.crack_amount * 1.4);
    let cell_x = (px / tile_w).floor() as i32;
    let cell_y = (py / tile_w).floor() as i32;
    let pour = hash2d(cell_x, cell_y, seed.wrapping_add(503));
    let pore = (hash2d((px * 2.1) as i32, (py * 2.1) as i32, seed.wrapping_add(509)) - 0.5)
        * material.grain
        * 0.10;
    let value = 0.50 + broad * 0.12 + fine * 0.08 + pour * 0.10 + pore;
    let highlight = (1.0 - seam) * 0.05 + pour * 0.05;
    (value, seam, material.wear * (1.0 - pour), highlight)
}

fn ribbed_steel_layers(
    material: &MaterialConfig,
    _seed: u32,
    px: f32,
    py: f32,
    _period: f32,
    feature_period: f32,
    _speck: f32,
    broad: f32,
    fine: f32,
) -> (f32, f32, f32, f32) {
    let rib_period = (feature_period * 0.1875).max(2.0);
    let diag1 = positive_mod(px + py, rib_period);
    let diag2 = positive_mod(px - py, rib_period);
    let rib_dist = diag1
        .min(rib_period - diag1)
        .min(diag2)
        .min(rib_period - diag2);
    let rib_mask = line_mask(rib_dist, 1.5);
    let bands = ((py * 0.04).sin() * 0.5 + 0.5) * 0.06;
    let scratch = clamp((fine - 0.55) * 2.5, 0.0, 1.0) * material.wear * 0.10;
    let value = 0.46 + broad * 0.10 + fine * 0.10 + bands + rib_mask * 0.18 - scratch;
    let crack = scratch * material.crack_amount * 0.5;
    let highlight = rib_mask * 0.32 + bands * 0.18;
    (value, crack, scratch, highlight)
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

fn srgb_luminance_rgb(color: [u8; 3]) -> f32 {
    color[0] as f32 * 0.2126 + color[1] as f32 * 0.7152 + color[2] as f32 * 0.0722
}

fn maybe_apply_height_shading(
    color: [u8; 3],
    height: f32,
    zone: SurfaceZone,
    bake_height_shading: bool,
) -> [u8; 3] {
    if bake_height_shading {
        apply_height_shading(color, height, zone)
    } else {
        color
    }
}

fn apply_height_shading(color: [u8; 3], height: f32, zone: SurfaceZone) -> [u8; 3] {
    let factor = match zone {
        SurfaceZone::Top => 0.96 + height * 0.08,
        SurfaceZone::Face => 0.90 + height * 0.10,
        SurfaceZone::Back => 0.94 + height * 0.08,
        SurfaceZone::Empty => 1.0,
    };
    [
        ((color[0] as f32 * factor).round() as i32).clamp(0, 255) as u8,
        ((color[1] as f32 * factor).round() as i32).clamp(0, 255) as u8,
        ((color[2] as f32 * factor).round() as i32).clamp(0, 255) as u8,
    ]
}

fn blur_heights_3x3(size: u32, heights: &[f32]) -> Vec<f32> {
    let mut out = vec![0.0_f32; heights.len()];
    for y in 0..size {
        for x in 0..size {
            let mut total = 0.0;
            for oy in -1..=1 {
                for ox in -1..=1 {
                    total += sample_height_value_clamped(size, heights, x as i32 + ox, y as i32 + oy);
                }
            }
            out[(y * size + x) as usize] = total / 9.0;
        }
    }
    out
}

fn encode_normal(size: u32, heights: &[f32], x: u32, y: u32, strength: f32) -> [u8; 3] {
    let at = |ox: i32, oy: i32| {
        sample_height_value_clamped(size, heights, x as i32 + ox, y as i32 + oy)
    };
    let (dx, dy) = sobel_gradient_from_samples(at);
    encode_normal_from_gradient(dx, dy, strength)
}

fn sobel_gradient_from_samples<F>(at: F) -> (f32, f32)
where
    F: Fn(i32, i32) -> f32,
{
    let dx = (
        at(1, -1) + 2.0 * at(1, 0) + at(1, 1)
            - at(-1, -1) - 2.0 * at(-1, 0) - at(-1, 1)
    ) * 0.25;
    let dy = (
        at(-1, 1) + 2.0 * at(0, 1) + at(1, 1)
            - at(-1, -1) - 2.0 * at(0, -1) - at(1, -1)
    ) * 0.25;
    (dx, dy)
}

fn encode_normal_from_gradient(dx: f32, dy: f32, strength: f32) -> [u8; 3] {
    let nx = -dx * strength;
    let ny = -dy * strength;
    let nz = 1.0_f32;
    let length = (nx * nx + ny * ny + nz * nz).sqrt().max(0.0001);
    [
        (((nx / length) * 0.5 + 0.5) * 255.0).round() as u8,
        (((ny / length) * 0.5 + 0.5) * 255.0).round() as u8,
        (((nz / length) * 0.5 + 0.5) * 255.0).round() as u8,
    ]
}

fn sample_height_value_clamped(size: u32, heights: &[f32], x: i32, y: i32) -> f32 {
    let sx = x.clamp(0, size as i32 - 1) as u32;
    let sy = y.clamp(0, size as i32 - 1) as u32;
    heights[(sy * size + sx) as usize]
}

fn blit_exact(target: &mut RgbaImage, source: &RgbaImage, dx: u32, dy: u32) {
    let source_width = source.width() as usize;
    let source_height = source.height() as usize;
    let target_width = target.width() as usize;
    let row_bytes = source_width * 4;
    let target_row_bytes = target_width * 4;
    let dx_offset = dx as usize * 4;
    let dy_usize = dy as usize;

    let src: &[u8] = source;
    let dst: &mut [u8] = target;

    for y in 0..source_height {
        let src_offset = y * row_bytes;
        let dst_offset = (dy_usize + y) * target_row_bytes + dx_offset;
        dst[dst_offset..dst_offset + row_bytes]
            .copy_from_slice(&src[src_offset..src_offset + row_bytes]);
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
