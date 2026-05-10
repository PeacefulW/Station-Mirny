use std::fs;
use std::hash::{Hash, Hasher};
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{Context, Result};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use image::{ImageFormat, Rgba, RgbaImage};
use rayon::prelude::*;
use serde::Serialize;

use crate::model::{
    AppRequest, ExportMode, GeneratedFiles, MaterialConfig, OutputManifest, RenderMode,
};
use crate::noise::{clamp, fbm_tiled, hash2d, lerp};
use crate::sdf::MapSdf;
use crate::signature::{Signature, canonical_signatures};

const ATLAS_COLUMNS: u32 = 8;
const MATERIAL_EXPORT_SIZE: u32 = 512;
const RECIPE_VERSION: u32 = 7;
const EDGE_NOISE_PERIOD_TILES: f32 = 8.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SurfaceZone {
    Top,
    Edge,
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

#[derive(Debug, Clone, Copy)]
struct SurfaceSample {
    height: f32,
    zone: SurfaceZone,
    occupancy: f32,
    top_coverage: f32,
    face_coverage: f32,
    back_coverage: f32,
}

#[derive(Clone, Copy)]
enum SurfaceField<'a> {
    // TODO: remove the local marching path after SDF atlas export reaches parity.
    Local(&'a Signature),
    GlobalSdf(&'a MapSdf),
}

#[derive(Serialize)]
struct RecipePayload<'a> {
    tool: &'static str,
    version: u32,
    mode: &'a str,
    request: &'a AppRequest,
}

#[cfg(test)]
fn run_request(mode: RenderMode, request: AppRequest, output_dir: &Path) -> Result<OutputManifest> {
    run_request_with_options(mode, request, output_dir, RenderOptions::default())
}

#[derive(Debug, Clone, Copy, Default)]
pub struct RenderOptions {
    pub inline_preview: bool,
    pub transient: bool,
}

pub fn run_request_with_options(
    mode: RenderMode,
    request: AppRequest,
    output_dir: &Path,
    options: RenderOptions,
) -> Result<OutputManifest> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create output dir: {}", output_dir.display()))?;

    let started = std::time::Instant::now();
    let mut warnings = Warnings::default();
    let textures = load_textures(&request, &mut warnings);
    collect_request_warnings(&request, &mut warnings);
    let signatures = canonical_signatures();

    let mut preview_base64 = None;
    let preview_path = if mode == RenderMode::Draft {
        let preview = build_map_preview(&request, &textures)?;
        if options.inline_preview {
            preview_base64 = Some(encode_png_base64(&preview)?);
            None
        } else {
            let preview_path = export_file_path(output_dir, &request, "preview", "png");
            preview.save(&preview_path)?;
            Some(preview_path)
        }
    } else {
        None
    };

    let recipe_path = export_file_path(output_dir, &request, "recipe", "json");
    let files = if mode == RenderMode::Draft {
        let mut files = if let Some(preview_path) = preview_path.as_deref() {
            generated_files_with_preview(preview_path, &recipe_path)
        } else {
            generated_files_without_preview(&recipe_path)
        };
        files.preview_png_base64 = preview_base64;
        if options.transient {
            files.recipe_json.clear();
        }
        files
    } else {
        match request.export_mode {
            ExportMode::Full47 => {
                let atlases = build_full_atlases(&request, &textures, &signatures);
                let material_exports = build_material_exports(&request, &textures);
                let albedo_atlas_path =
                    export_file_path(output_dir, &request, "atlas_albedo", "png");
                let mask_atlas_path = export_file_path(output_dir, &request, "atlas_mask", "png");
                let height_atlas_path =
                    export_file_path(output_dir, &request, "atlas_height", "png");
                let normal_atlas_path =
                    export_file_path(output_dir, &request, "atlas_normal", "png");
                let top_albedo_path = export_file_path(output_dir, &request, "top_albedo", "png");
                let face_albedo_path = export_file_path(output_dir, &request, "face_albedo", "png");
                let base_albedo_path = export_file_path(output_dir, &request, "base_albedo", "png");
                let top_modulation_path =
                    export_file_path(output_dir, &request, "top_modulation", "png");
                let face_modulation_path =
                    export_file_path(output_dir, &request, "face_modulation", "png");
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
                material_exports
                    .face_modulation
                    .save(&face_modulation_path)?;
                material_exports.top_normal.save(&top_normal_path)?;
                material_exports.face_normal.save(&face_normal_path)?;

                GeneratedFiles {
                    preview_png: String::new(),
                    preview_png_base64: None,
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

                let mut files = generated_files_without_preview(&recipe_path);
                files.atlas_albedo_png = Some(to_string_path(&atlas_path));
                files
            }
            ExportMode::MaskOnly => {
                let atlas = build_mask_atlas(&request, &signatures);
                let atlas_path = export_file_path(output_dir, &request, "atlas_mask", "png");
                atlas.save(&atlas_path)?;

                let mut files = generated_files_without_preview(&recipe_path);
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
    if !options.transient {
        fs::write(&recipe_path, serde_json::to_vec_pretty(&recipe)?)
            .with_context(|| format!("failed to write recipe: {}", recipe_path.display()))?;
    }

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

fn export_file_path(
    output_dir: &Path,
    request: &AppRequest,
    slot: &str,
    extension: &str,
) -> PathBuf {
    output_dir.join(format!("{}_{}.{}", request.asset_name, slot, extension))
}

fn generated_files_with_preview(preview_path: &Path, recipe_path: &Path) -> GeneratedFiles {
    GeneratedFiles {
        preview_png: to_string_path(preview_path),
        ..generated_files_without_preview(recipe_path)
    }
}

fn generated_files_without_preview(recipe_path: &Path) -> GeneratedFiles {
    GeneratedFiles {
        preview_png: String::new(),
        preview_png_base64: None,
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

fn encode_png_base64(image: &RgbaImage) -> Result<String> {
    let mut bytes = Vec::new();
    image.write_to(&mut Cursor::new(&mut bytes), ImageFormat::Png)?;
    Ok(BASE64_STANDARD.encode(bytes))
}

fn collect_request_warnings(request: &AppRequest, warnings: &mut Warnings) {
    warn_invalid_hex("colors.top", &request.colors.top, warnings);
    warn_invalid_hex("colors.face", &request.colors.face, warnings);
    warn_invalid_hex("colors.edge", &request.colors.edge, warnings);
    warn_invalid_hex("colors.back", &request.colors.back, warnings);
    warn_invalid_hex("colors.base", &request.colors.base, warnings);
    warn_material_config("materials.top", &request.materials.top, warnings);
    warn_material_config("materials.face", &request.materials.face, warnings);
    warn_material_config("materials.base", &request.materials.base, warnings);

    if front_only_projection_active(request) && request.south_height == 0 {
        warnings.push(
            "front-only SDF preview is active but south_height is 0; no facade can be projected"
                .to_string(),
        );
    }
}

fn warn_material_config(slot: &str, material: &MaterialConfig, warnings: &mut Warnings) {
    warn_invalid_hex(&format!("{slot}.color_a"), &material.color_a, warnings);
    warn_invalid_hex(&format!("{slot}.color_b"), &material.color_b, warnings);
    warn_invalid_hex(&format!("{slot}.highlight"), &material.highlight, warnings);
    if material.scale < 0.5 || material.scale > 4.0 {
        warnings.push(format!(
            "{slot}.scale={} is outside the preview-safe 0.5..4.0 range and can produce oversized or noisy procedural detail",
            material.scale
        ));
    }
}

fn warn_invalid_hex(label: &str, value: &str, warnings: &mut Warnings) {
    if try_parse_hex_color(value).is_none() {
        warnings.push(format!(
            "{label} has invalid hex color '{value}'; falling back to white or the slot fallback"
        ));
    }
}

fn build_full_atlases(
    request: &AppRequest,
    textures: &TextureSet,
    signatures: &[Signature],
) -> Atlases {
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

fn render_base_variant_tile(
    request: &AppRequest,
    textures: &TextureSet,
    variant: u32,
) -> RgbaImage {
    let size = request.tile_size;
    let (material, base_color, texture, seed) =
        material_slot(request, textures, MaterialKind::Base);
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
                x as f32,
                y as f32,
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
            let variant = atlas_index / signature_count;
            let sig_idx = (atlas_index % signature_count) as usize;
            let signature = &signatures[sig_idx];
            let tile = render_mask_tile(request, signature, variant, 0, 0);
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

fn render_mask_tile(
    request: &AppRequest,
    signature: &Signature,
    variant: u32,
    origin_x: u32,
    origin_y: u32,
) -> RgbaImage {
    let size = request.tile_size;
    let mut mask = RgbaImage::new(size, size);
    let geometry_seed = geometry_seed_for_variant(request, variant);

    for y in 0..size {
        for x in 0..size {
            let sample =
                sample_surface_pixel(request, signature, geometry_seed, x, y, origin_x, origin_y);
            let top_mask = if matches!(sample.zone, SurfaceZone::Top | SurfaceZone::Edge) {
                255
            } else {
                0
            };
            let face_mask = if matches!(sample.zone, SurfaceZone::Face | SurfaceZone::Edge) {
                255
            } else {
                0
            };
            let back_mask = if sample.zone == SurfaceZone::Back {
                255
            } else {
                0
            };
            let occupancy = (sample.occupancy.clamp(0.0, 1.0) * 255.0).round() as u8;
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
    let (base_albedo, _) = build_material_albedo_and_values(request, textures, MaterialKind::Base);

    MaterialExports {
        top_albedo,
        face_albedo,
        base_albedo,
        top_modulation: build_scalar_image(&top_values, MATERIAL_EXPORT_SIZE, MATERIAL_EXPORT_SIZE),
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
            let base = sample_material_base(
                material,
                texture,
                request.texture_scale,
                width,
                x as f32,
                y as f32,
                seed,
            );
            *value = srgb_luminance_rgb(base.rgb) / 255.0;
            let color = apply_material_tint(base, tint, request.texture_color_overlay, 1.0);
            pixel[0] = color[0];
            pixel[1] = color[1];
            pixel[2] = color[2];
            pixel[3] = 255;
        });

    let albedo = RgbaImage::from_raw(width, height, raw).expect("buffer size matches dimensions");
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MapSdfCacheKey {
    width: u32,
    height: u32,
    outside_padding: u32,
    cells_hash: u64,
}

static MAP_SDF_CACHE: OnceLock<Mutex<Option<(MapSdfCacheKey, Arc<MapSdf>)>>> = OnceLock::new();

fn cached_map_sdf(map: &crate::model::MapData, outside_padding: u32) -> Arc<MapSdf> {
    let key = map_sdf_cache_key(map, outside_padding);
    let cache = MAP_SDF_CACHE.get_or_init(|| Mutex::new(None));
    let mut cache = cache
        .lock()
        .expect("SDF cache mutex should not be poisoned");
    if let Some((cached_key, sdf)) = cache.as_ref() {
        if *cached_key == key {
            return Arc::clone(sdf);
        }
    }

    let sdf = Arc::new(MapSdf::compute_with_padding(map, outside_padding));
    *cache = Some((key, Arc::clone(&sdf)));
    sdf
}

fn map_sdf_cache_key(map: &crate::model::MapData, outside_padding: u32) -> MapSdfCacheKey {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    map.cells.hash(&mut hasher);
    MapSdfCacheKey {
        width: map.width,
        height: map.height,
        outside_padding,
        cells_hash: hasher.finish(),
    }
}

fn map_sdf_padding_for_request(request: &AppRequest) -> u32 {
    let max_height_px = request
        .south_height
        .max(request.north_height)
        .max(request.side_height)
        .max(request.rim_width) as f32
        + request.contour_warp_px.abs().ceil();
    ((max_height_px / request.tile_size.max(1) as f32).ceil() as u32 + 2).max(8)
}

fn build_map_preview(request: &AppRequest, textures: &TextureSet) -> Result<RgbaImage> {
    let width = request.map.width * request.tile_size;
    let height = request.map.height * request.tile_size;
    let mut preview = RgbaImage::new(width, height);
    let sdf = cached_map_sdf(&request.map, map_sdf_padding_for_request(request));

    let tile_size = request.tile_size as usize;
    let preview_width = width as usize;
    let row_band_bytes = preview_width * 4 * tile_size;
    let raw: &mut [u8] = &mut preview;
    raw.par_chunks_mut(row_band_bytes)
        .enumerate()
        .for_each(|(map_y, band)| {
            for map_x in 0..request.map.width as usize {
                let origin_x = map_x as u32 * request.tile_size;
                let origin_y = map_y as u32 * request.tile_size;
                let variant = request.forced_variant.unwrap_or_else(|| {
                    pick_variant(map_x as i32, map_y as i32, request.seed, request.variants)
                });
                let tile = render_tile_with_sdf(
                    request,
                    textures,
                    sdf.as_ref(),
                    variant,
                    origin_x,
                    origin_y,
                );
                let img = extract_mode_image(tile, request);
                blit_exact_band(band, preview_width, tile_size, map_x * tile_size, &img);
            }
        });

    Ok(preview)
}

fn pick_variant(x: i32, y: i32, seed: u32, total: u32) -> u32 {
    if total <= 1 {
        0
    } else {
        ((hash2d(x, y, seed.wrapping_add(991)) * total as f32).floor() as u32).min(total - 1)
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
    render_tile_with_field(
        request,
        textures,
        SurfaceField::Local(signature),
        variant,
        origin_x,
        origin_y,
    )
}

fn render_tile_with_sdf(
    request: &AppRequest,
    textures: &TextureSet,
    sdf: &MapSdf,
    variant: u32,
    origin_x: u32,
    origin_y: u32,
) -> TileBuffers {
    render_tile_with_field(
        request,
        textures,
        SurfaceField::GlobalSdf(sdf),
        variant,
        origin_x,
        origin_y,
    )
}

fn render_tile_with_field(
    request: &AppRequest,
    textures: &TextureSet,
    field: SurfaceField<'_>,
    variant: u32,
    origin_x: u32,
    origin_y: u32,
) -> TileBuffers {
    let size = request.tile_size;
    let pixel_count = (size * size) as usize;
    let mut heights = vec![0.0_f32; pixel_count];
    let mut zones = vec![SurfaceZone::Top; pixel_count];
    let mut occupancies = vec![1.0_f32; pixel_count];
    let mut top_coverages = vec![1.0_f32; pixel_count];
    let mut face_coverages = vec![0.0_f32; pixel_count];
    let mut back_coverages = vec![0.0_f32; pixel_count];

    let geometry_variant = match field {
        SurfaceField::GlobalSdf(_) => request.forced_variant.unwrap_or(0),
        SurfaceField::Local(_) => variant,
    };
    let geometry_seed = geometry_seed_for_variant(request, geometry_variant);
    let material_seed = request
        .seed
        .wrapping_add(variant.wrapping_mul(4_091))
        .wrapping_add(17_371);

    let global_distance_cache = if let SurfaceField::GlobalSdf(sdf) = field {
        Some(GlobalSdfDistanceCache::new(
            request,
            sdf,
            geometry_seed,
            origin_x,
            origin_y,
            size,
        ))
    } else {
        None
    };

    for y in 0..size {
        for x in 0..size {
            let index = (y * size + x) as usize;
            let sample = sample_surface_for_field(
                request,
                field,
                global_distance_cache.as_ref(),
                geometry_seed,
                x,
                y,
                origin_x,
                origin_y,
            );
            heights[index] = sample.height;
            zones[index] = sample.zone;
            occupancies[index] = sample.occupancy;
            top_coverages[index] = sample.top_coverage;
            face_coverages[index] = sample.face_coverage;
            back_coverages[index] = sample.back_coverage;
        }
    }

    let needs_height_adjustments = match field {
        SurfaceField::GlobalSdf(_) => {
            matches!(request.preview_mode.as_str(), "height" | "lit") || request.bake_height_shading
        }
        SurfaceField::Local(_) => true,
    };
    if needs_height_adjustments {
        apply_crown_bevel(
            request,
            field,
            global_distance_cache.as_ref(),
            geometry_seed,
            origin_x,
            origin_y,
            &mut heights,
            &zones,
        );
        apply_organic_height_relief(
            request,
            field,
            global_distance_cache.as_ref(),
            geometry_seed,
            origin_x,
            origin_y,
            &mut heights,
            &zones,
            &occupancies,
        );
    }
    let needs_normal = match field {
        SurfaceField::GlobalSdf(_) => matches!(request.preview_mode.as_str(), "normal" | "lit"),
        SurfaceField::Local(_) => true,
    };
    let normal_heights = if needs_normal && matches!(field, SurfaceField::Local(_)) {
        blur_heights_3x3(size, &heights)
    } else {
        Vec::new()
    };
    let global_height_cache = if needs_normal
        && matches!(request.preview_mode.as_str(), "normal" | "lit")
        && let SurfaceField::GlobalSdf(sdf) = field
    {
        Some(GlobalRenderHeightCache::new(
            GlobalSdfSampler {
                request,
                sdf,
                seed: geometry_seed,
                distance_cache: global_distance_cache.as_ref(),
            },
            origin_x,
            origin_y,
            size,
        ))
    } else {
        None
    };

    let mut albedo = RgbaImage::new(size, size);
    let mut mask = RgbaImage::new(size, size);
    let mut height_img = RgbaImage::new(size, size);
    let mut normal = RgbaImage::new(size, size);

    let (top_material, top_color, top_texture, top_seed) =
        material_slot(request, textures, MaterialKind::Top);
    let (face_material, face_color, face_texture, face_seed) =
        material_slot(request, textures, MaterialKind::Face);
    let (base_material, base_color, base_texture, base_seed) =
        material_slot(request, textures, MaterialKind::Base);
    let back_color = parse_hex_color(&request.colors.back);
    let edge_color = parse_hex_color(&request.colors.edge);

    for y in 0..size {
        for x in 0..size {
            let index = (y * size + x) as usize;
            let zone = zones[index];
            let height_value = heights[index];
            let sample_x = origin_x + x;
            let sample_y = origin_y + y;
            let world_x = sample_x as f32;
            let world_y = sample_y as f32;
            let (facade_x, facade_y) = material_coords_for_zone(
                request,
                field,
                global_distance_cache.as_ref(),
                geometry_seed,
                zone,
                world_x,
                world_y,
            );
            let sample_seed = material_seed;

            let base = match zone {
                SurfaceZone::Top => sample_material_color(
                    top_material,
                    top_color,
                    top_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    world_x,
                    world_y,
                    top_seed.wrapping_add(sample_seed),
                    1.0,
                ),
                SurfaceZone::Edge => {
                    let edge_distance = exposed_edge_distance(
                        request,
                        field,
                        global_distance_cache.as_ref(),
                        geometry_seed,
                        x as f32,
                        y as f32,
                        sample_x as f32,
                        sample_y as f32,
                    )
                    .unwrap_or(0.0);
                    let edge_width = edge_relief_width_px(request);
                    let edge_t = (1.0 - edge_distance / edge_width).clamp(0.0, 1.0);
                    let chip = fbm_tiled(
                        sample_x as f32 * 0.19 + 19.0,
                        sample_y as f32 * 0.17 + 43.0,
                        edge_noise_period(request) * 0.19,
                        edge_noise_period(request) * 0.17,
                        2,
                        geometry_seed.wrapping_add(9_337),
                    );
                    let top_sample = sample_material_color(
                        top_material,
                        top_color,
                        top_texture,
                        request.texture_scale,
                        request.texture_color_overlay,
                        request.tile_size,
                        world_x,
                        world_y,
                        top_seed.wrapping_add(sample_seed),
                        1.0,
                    );
                    let face_sample = sample_material_color(
                        face_material,
                        face_color,
                        face_texture,
                        request.texture_scale,
                        request.texture_color_overlay,
                        request.tile_size,
                        facade_x,
                        facade_y,
                        face_seed.wrapping_add(sample_seed).wrapping_add(73),
                        1.0,
                    );
                    let debris = request.edge_debris.clamp(0.0, 1.0);
                    let mix_factor = ((0.22 + debris * 0.18)
                        + (chip - 0.5) * debris * 0.20
                        + edge_t * debris * 0.06)
                        .clamp(0.16, 0.58);
                    let mixed = mix_color(top_sample, face_sample, mix_factor);
                    let edge_strength = request.edge_color_strength.clamp(0.0, 1.0);
                    let tinted =
                        mix_color(mixed, edge_color, edge_strength * (0.65 + edge_t * 0.35));
                    let darken = (0.96 - edge_t * debris * (0.05 + chip * 0.12)).clamp(0.78, 0.98);
                    scale_color(tinted, darken)
                }
                SurfaceZone::Face => sample_material_color(
                    face_material,
                    face_color,
                    face_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    facade_x,
                    facade_y,
                    face_seed.wrapping_add(sample_seed),
                    1.0,
                ),
                SurfaceZone::Back => sample_material_color(
                    face_material,
                    back_color,
                    face_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    facade_x,
                    facade_y,
                    face_seed.wrapping_add(sample_seed).wrapping_add(181),
                    1.0,
                ),
                SurfaceZone::Empty => sample_material_color(
                    base_material,
                    base_color,
                    base_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    world_x,
                    world_y,
                    base_seed.wrapping_add(sample_seed),
                    0.92,
                ),
            };

            let shaded = if matches!(field, SurfaceField::GlobalSdf(_))
                && zone != SurfaceZone::Edge
                && top_coverages[index] > 0.0
                && (face_coverages[index] > 0.0 || back_coverages[index] > 0.0)
            {
                let (wall_x, wall_y) = material_coords_for_zone(
                    request,
                    field,
                    global_distance_cache.as_ref(),
                    geometry_seed,
                    SurfaceZone::Face,
                    world_x,
                    world_y,
                );
                let top_sample = sample_material_color(
                    top_material,
                    top_color,
                    top_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    world_x,
                    world_y,
                    top_seed.wrapping_add(sample_seed),
                    1.0,
                );
                let face_sample = sample_material_color(
                    face_material,
                    face_color,
                    face_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    wall_x,
                    wall_y,
                    face_seed.wrapping_add(sample_seed),
                    1.0,
                );
                let back_sample = sample_material_color(
                    face_material,
                    back_color,
                    face_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    wall_x,
                    wall_y,
                    face_seed.wrapping_add(sample_seed).wrapping_add(181),
                    1.0,
                );
                blend_coverage_color(
                    maybe_apply_height_shading(
                        top_sample,
                        height_value,
                        SurfaceZone::Top,
                        request.bake_height_shading,
                    ),
                    top_coverages[index],
                    maybe_apply_height_shading(
                        face_sample,
                        height_value,
                        SurfaceZone::Face,
                        request.bake_height_shading,
                    ),
                    face_coverages[index],
                    maybe_apply_height_shading(
                        back_sample,
                        height_value,
                        SurfaceZone::Back,
                        request.bake_height_shading,
                    ),
                    back_coverages[index],
                )
            } else {
                maybe_apply_height_shading(base, height_value, zone, request.bake_height_shading)
            };
            let occupancy = occupancies[index].clamp(0.0, 1.0);
            let visible = if occupancy > 0.0 && occupancy < 1.0 && zone != SurfaceZone::Empty {
                let empty_base = sample_material_color(
                    base_material,
                    base_color,
                    base_texture,
                    request.texture_scale,
                    request.texture_color_overlay,
                    request.tile_size,
                    world_x,
                    world_y,
                    base_seed.wrapping_add(sample_seed),
                    0.92,
                );
                mix_color(empty_base, shaded, occupancy)
            } else {
                shaded
            };
            albedo.put_pixel(x, y, rgba(visible, 255));

            let use_coverage_mask = matches!(field, SurfaceField::GlobalSdf(_));
            let top_mask = if use_coverage_mask {
                coverage_byte(top_coverages[index])
            } else if matches!(zone, SurfaceZone::Top | SurfaceZone::Edge) {
                255
            } else {
                0
            };
            let face_mask = if use_coverage_mask {
                coverage_byte(face_coverages[index])
            } else if matches!(zone, SurfaceZone::Face | SurfaceZone::Edge) {
                255
            } else {
                0
            };
            let back_mask = if use_coverage_mask {
                coverage_byte(back_coverages[index])
            } else if zone == SurfaceZone::Back {
                255
            } else {
                0
            };
            let occupancy_alpha = (occupancy * 255.0).round() as u8;
            mask.put_pixel(
                x,
                y,
                Rgba([top_mask, face_mask, back_mask, occupancy_alpha]),
            );

            let height_byte = (clamp(height_value, 0.0, 1.0) * 255.0).round() as u8;
            height_img.put_pixel(
                x,
                y,
                Rgba([height_byte, height_byte, height_byte, occupancy_alpha]),
            );

            let encoded = if !needs_normal || zone == SurfaceZone::Empty {
                [128, 128, 255]
            } else if let Some(cache) = &global_height_cache {
                encode_global_normal_from_cache(
                    cache,
                    sample_x as f32,
                    sample_y as f32,
                    request.normal_strength,
                )
            } else {
                encode_normal(size, &normal_heights, x, y, request.normal_strength)
            };
            normal.put_pixel(
                x,
                y,
                Rgba([encoded[0], encoded[1], encoded[2], occupancy_alpha]),
            );
        }
    }

    TileBuffers {
        albedo,
        mask,
        height: height_img,
        normal,
    }
}

fn extract_mode_image(tile: TileBuffers, request: &AppRequest) -> RgbaImage {
    match request.preview_mode.as_str() {
        "albedo" | "composite" => tile.albedo,
        "lit" => build_lit_preview_image(&tile, request.light_angle_deg),
        "mask" => tile.mask,
        "height" => tile.height,
        "normal" => tile.normal,
        _ => tile.albedo,
    }
}

fn build_lit_preview_image(tile: &TileBuffers, light_angle_deg: f32) -> RgbaImage {
    let (width, height) = tile.albedo.dimensions();
    let mut image = RgbaImage::new(width, height);
    let angle = light_angle_deg.to_radians();
    let light_dir = normalize3(angle.cos() * 0.766, angle.sin() * 0.766, 0.64);

    for y in 0..height {
        for x in 0..width {
            let albedo = tile.albedo.get_pixel(x, y).0;
            let normal = tile.normal.get_pixel(x, y).0;
            let mask = tile.mask.get_pixel(x, y).0;
            let height_value = tile.height.get_pixel(x, y).0[0] as f32 / 255.0;
            let nx = normal[0] as f32 / 127.5 - 1.0;
            let ny = normal[1] as f32 / 127.5 - 1.0;
            let nz = normal[2] as f32 / 127.5 - 1.0;
            let dot = (nx * light_dir.0 + ny * light_dir.1 + nz * light_dir.2).max(0.0);
            let zone_factor = if dominant_mask_zone(mask) == SurfaceZone::Edge {
                0.98
            } else if dominant_mask_zone(mask) == SurfaceZone::Face {
                0.84
            } else if dominant_mask_zone(mask) == SurfaceZone::Back {
                0.91
            } else if dominant_mask_zone(mask) == SurfaceZone::Top {
                1.02
            } else {
                0.96
            };
            let height_ao = 0.82 + height_value * 0.18;
            let light = (0.54 + dot * 0.56) * zone_factor * height_ao;
            image.put_pixel(
                x,
                y,
                Rgba([
                    (albedo[0] as f32 * light).round().clamp(0.0, 255.0) as u8,
                    (albedo[1] as f32 * light).round().clamp(0.0, 255.0) as u8,
                    (albedo[2] as f32 * light).round().clamp(0.0, 255.0) as u8,
                    albedo[3],
                ]),
            );
        }
    }

    image
}

fn dominant_mask_zone(mask: [u8; 4]) -> SurfaceZone {
    if mask[3] == 0 {
        return SurfaceZone::Empty;
    }
    let top = mask[0];
    let face = mask[1];
    let back = mask[2];
    if top > 0 && face > 0 && face >= 64 && top.abs_diff(face) <= 96 {
        SurfaceZone::Edge
    } else if face >= top && face >= back && face >= 64 {
        SurfaceZone::Face
    } else if back >= top && back >= face && back >= 64 {
        SurfaceZone::Back
    } else if top > 0 {
        SurfaceZone::Top
    } else {
        SurfaceZone::Empty
    }
}

fn normalize3(x: f32, y: f32, z: f32) -> (f32, f32, f32) {
    let len = (x * x + y * y + z * z).sqrt().max(0.0001);
    (x / len, y / len, z / len)
}

fn geometry_seed_for_variant(request: &AppRequest, variant: u32) -> u32 {
    if request.geometry_variance <= 0.0 || variant == 0 {
        request.seed
    } else {
        request
            .seed
            .wrapping_add(variant.wrapping_mul(8_119))
            .wrapping_add(31_337)
    }
}

fn sample_surface_for_field(
    request: &AppRequest,
    field: SurfaceField<'_>,
    global_distance_cache: Option<&GlobalSdfDistanceCache>,
    seed: u32,
    x: u32,
    y: u32,
    origin_x: u32,
    origin_y: u32,
) -> SurfaceSample {
    match field {
        SurfaceField::Local(signature) => {
            sample_surface_pixel(request, signature, seed, x, y, origin_x, origin_y)
        }
        SurfaceField::GlobalSdf(sdf) => sample_global_surface_pixel(
            GlobalSdfSampler {
                request,
                sdf,
                seed,
                distance_cache: global_distance_cache,
            },
            x,
            y,
            origin_x,
            origin_y,
        ),
    }
}

fn surface_sample(height: f32, zone: SurfaceZone, occupancy: f32) -> SurfaceSample {
    let (top_coverage, face_coverage, back_coverage) =
        coverage_for_zone(zone, occupancy.clamp(0.0, 1.0));
    SurfaceSample {
        height,
        zone,
        occupancy,
        top_coverage,
        face_coverage,
        back_coverage,
    }
}

fn coverage_for_zone(zone: SurfaceZone, occupancy: f32) -> (f32, f32, f32) {
    match zone {
        SurfaceZone::Top => (occupancy, 0.0, 0.0),
        SurfaceZone::Edge => (occupancy, occupancy, 0.0),
        SurfaceZone::Face => (0.0, occupancy, 0.0),
        SurfaceZone::Back => (0.0, 0.0, occupancy),
        SurfaceZone::Empty => (0.0, 0.0, 0.0),
    }
}

fn coverage_byte(value: f32) -> u8 {
    (value.clamp(0.0, 1.0) * 255.0).round() as u8
}

fn sample_surface_pixel(
    request: &AppRequest,
    signature: &Signature,
    seed: u32,
    x: u32,
    y: u32,
    origin_x: u32,
    origin_y: u32,
) -> SurfaceSample {
    let samples = request.shape_supersampling.max(1);
    if samples <= 1 {
        let (height, zone) = sample_height(
            request,
            signature,
            seed,
            x as f32,
            y as f32,
            (origin_x + x) as f32,
            (origin_y + y) as f32,
        );
        let occupancy = if zone == SurfaceZone::Empty { 0.0 } else { 1.0 };
        return surface_sample(height, zone, occupancy);
    }

    let inv_samples = 1.0 / samples as f32;
    let mut height_sum = 0.0_f32;
    let mut occupied = 0_u32;
    let mut zone_counts = [0_u32; 5];
    let mut top_coverage = 0.0_f32;
    let mut face_coverage = 0.0_f32;
    let mut back_coverage = 0.0_f32;

    for sy in 0..samples {
        for sx in 0..samples {
            let offset_x = (sx as f32 + 0.5) * inv_samples;
            let offset_y = (sy as f32 + 0.5) * inv_samples;
            let sample_x = x as f32 + offset_x;
            let sample_y = y as f32 + offset_y;
            let (height, zone) = sample_height(
                request,
                signature,
                seed,
                sample_x,
                sample_y,
                origin_x as f32 + sample_x,
                origin_y as f32 + sample_y,
            );
            zone_counts[zone_index(zone)] += 1;
            if zone != SurfaceZone::Empty {
                height_sum += height;
                occupied += 1;
            }
            let (top, face, back) = coverage_for_zone(zone, 1.0);
            top_coverage += top;
            face_coverage += face;
            back_coverage += back;
        }
    }

    let total = samples * samples;
    let inv_total = 1.0 / total as f32;
    SurfaceSample {
        height: if occupied == 0 {
            0.0
        } else {
            height_sum / occupied as f32
        },
        zone: if occupied == 0 {
            SurfaceZone::Empty
        } else {
            dominant_occupied_zone(zone_counts)
        },
        occupancy: occupied as f32 / total as f32,
        top_coverage: top_coverage * inv_total,
        face_coverage: face_coverage * inv_total,
        back_coverage: back_coverage * inv_total,
    }
}

#[derive(Clone, Copy)]
struct GlobalSdfSampler<'a> {
    request: &'a AppRequest,
    sdf: &'a MapSdf,
    seed: u32,
    distance_cache: Option<&'a GlobalSdfDistanceCache>,
}

impl<'a> GlobalSdfSampler<'a> {
    #[cfg(test)]
    fn uncached(request: &'a AppRequest, sdf: &'a MapSdf, seed: u32) -> Self {
        Self {
            request,
            sdf,
            seed,
            distance_cache: None,
        }
    }

    fn distance_px(self, world_x: f32, world_y: f32) -> f32 {
        self.distance_cache.map_or_else(
            || controlled_sdf_distance_px(self.request, self.sdf, self.seed, world_x, world_y),
            |cache| cache.sample(world_x, world_y),
        )
    }

    fn gradient(self, world_x: f32, world_y: f32) -> (f32, f32) {
        self.distance_cache.map_or_else(
            || controlled_sdf_gradient(self.request, self.sdf, self.seed, world_x, world_y),
            |cache| cache.gradient(world_x, world_y),
        )
    }
}

fn sample_global_surface_pixel(
    sampler: GlobalSdfSampler<'_>,
    x: u32,
    y: u32,
    origin_x: u32,
    origin_y: u32,
) -> SurfaceSample {
    let request = sampler.request;
    let samples = request.shape_supersampling.max(1);
    if samples <= 1 {
        let world_x = origin_x as f32 + x as f32;
        let world_y = origin_y as f32 + y as f32;
        let (height, zone) = sample_global_height_with_sampler(sampler, world_x, world_y);
        let occupancy = if zone == SurfaceZone::Empty { 0.0 } else { 1.0 };
        return surface_sample(height, zone, occupancy);
    }

    let inv_samples = 1.0 / samples as f32;
    let mut height_sum = 0.0_f32;
    let mut occupied = 0_u32;
    let mut zone_counts = [0_u32; 5];
    let mut top_coverage = 0.0_f32;
    let mut face_coverage = 0.0_f32;
    let mut back_coverage = 0.0_f32;

    for sy in 0..samples {
        for sx in 0..samples {
            let offset_x = (sx as f32 + 0.5) * inv_samples;
            let offset_y = (sy as f32 + 0.5) * inv_samples;
            let sample_x = x as f32 + offset_x;
            let sample_y = y as f32 + offset_y;
            let world_x = origin_x as f32 + sample_x;
            let world_y = origin_y as f32 + sample_y;
            let (height, zone) = sample_global_height_with_sampler(sampler, world_x, world_y);
            zone_counts[zone_index(zone)] += 1;
            if zone != SurfaceZone::Empty {
                height_sum += height;
                occupied += 1;
            }
            let (top, face, back) = coverage_for_zone(zone, 1.0);
            top_coverage += top;
            face_coverage += face;
            back_coverage += back;
        }
    }

    let total = samples * samples;
    let inv_total = 1.0 / total as f32;
    SurfaceSample {
        height: if occupied == 0 {
            0.0
        } else {
            height_sum / occupied as f32
        },
        zone: if occupied == 0 {
            SurfaceZone::Empty
        } else {
            dominant_occupied_zone(zone_counts)
        },
        occupancy: occupied as f32 / total as f32,
        top_coverage: top_coverage * inv_total,
        face_coverage: face_coverage * inv_total,
        back_coverage: back_coverage * inv_total,
    }
}

#[cfg(test)]
fn sample_global_height(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
) -> (f32, SurfaceZone) {
    sample_global_height_with_sampler(
        GlobalSdfSampler::uncached(request, sdf, seed),
        world_x,
        world_y,
    )
}

fn sample_global_height_with_sampler(
    sampler: GlobalSdfSampler<'_>,
    world_x: f32,
    world_y: f32,
) -> (f32, SurfaceZone) {
    let request = sampler.request;
    let signed_distance_px = sampler.distance_px(world_x, world_y);
    if front_only_projection_active(request) {
        return sample_front_only_projected_height(sampler, world_x, world_y, signed_distance_px);
    }

    let (gx, gy) = sampler.gradient(world_x, world_y);
    let (zone, depth) = marching_zone_and_depth(request, gx, gy);

    if signed_distance_px < 0.0 {
        let outside_distance = -signed_distance_px;
        if outside_distance > depth {
            return (0.0, SurfaceZone::Empty);
        }
        let progress = (outside_distance / depth.max(1.0)).clamp(0.0, 1.0);
        let height = match zone {
            SurfaceZone::Back => back_height_for_progress(request, progress),
            _ => face_height_for_progress(request, progress),
        };
        return (clamp(height, 0.0, 1.0), zone);
    }

    let edge_width = preview_edge_width_px(request);
    if edge_width > 0.0 && signed_distance_px <= edge_width {
        let progress = (signed_distance_px / edge_width.max(1.0)).clamp(0.0, 1.0);
        return (edge_height_for_progress(progress), SurfaceZone::Edge);
    }

    (1.0, SurfaceZone::Top)
}

fn front_only_projection_active(request: &AppRequest) -> bool {
    request.side_height == 0 && request.north_height == 0
}

fn sample_front_only_projected_height(
    sampler: GlobalSdfSampler<'_>,
    world_x: f32,
    world_y: f32,
    signed_distance_px: f32,
) -> (f32, SurfaceZone) {
    let request = sampler.request;
    if signed_distance_px >= 0.0 {
        let edge_width = preview_edge_width_px(request);
        if edge_width > 0.0 && signed_distance_px <= edge_width {
            let progress = (signed_distance_px / edge_width.max(1.0)).clamp(0.0, 1.0);
            return (edge_height_for_progress(progress), SurfaceZone::Edge);
        }
        return (1.0, SurfaceZone::Top);
    }

    let Some(progress) = front_only_projected_facade_progress(sampler, world_x, world_y) else {
        return (0.0, SurfaceZone::Empty);
    };
    (
        clamp(face_height_for_progress(request, progress), 0.0, 1.0),
        SurfaceZone::Face,
    )
}

fn front_only_projected_facade_progress(
    sampler: GlobalSdfSampler<'_>,
    world_x: f32,
    world_y: f32,
) -> Option<f32> {
    let request = sampler.request;
    let mut best_progress = None;

    if let Some(depth) = projected_axis_depth(
        sampler,
        world_x,
        world_y,
        0.0,
        -1.0,
        request.south_height as f32,
    ) {
        best_progress = Some((depth / request.south_height.max(1) as f32).clamp(0.0, 1.0));
    }

    best_progress
}

fn projected_axis_depth(
    sampler: GlobalSdfSampler<'_>,
    world_x: f32,
    world_y: f32,
    direction_x: f32,
    direction_y: f32,
    max_depth: f32,
) -> Option<f32> {
    if max_depth <= 0.0 {
        return None;
    }

    let inside_x = world_x + direction_x * max_depth;
    let inside_y = world_y + direction_y * max_depth;
    if sampler.distance_px(inside_x, inside_y) < 0.0 {
        return None;
    }

    let mut outside = 0.0_f32;
    let mut inside = max_depth;
    for _ in 0..7 {
        let mid = (outside + inside) * 0.5;
        let sample_x = world_x + direction_x * mid;
        let sample_y = world_y + direction_y * mid;
        if sampler.distance_px(sample_x, sample_y) >= 0.0 {
            inside = mid;
        } else {
            outside = mid;
        }
    }
    Some(inside)
}

#[cfg(test)]
fn sample_global_render_height(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
) -> f32 {
    sample_global_render_height_with_sampler(
        GlobalSdfSampler::uncached(request, sdf, seed),
        world_x,
        world_y,
    )
}

fn sample_global_render_height_with_sampler(
    sampler: GlobalSdfSampler<'_>,
    world_x: f32,
    world_y: f32,
) -> f32 {
    let request = sampler.request;
    let (mut height, zone) = sample_global_height_with_sampler(sampler, world_x, world_y);
    if zone == SurfaceZone::Empty {
        return 0.0;
    }

    let contour = global_contour_distance_with_sampler(sampler, world_x, world_y);
    let bevel = request.crown_bevel as f32;
    if bevel > 0.0 && zone == SurfaceZone::Top {
        let nearest = contour.signed_distance;
        if nearest >= 0.0 && nearest < bevel {
            let t = (nearest / bevel).clamp(0.0, 1.0);
            height = height.min(lerp(0.86, 1.0, t));
        }
    }

    height = clamp(
        height
            + organic_height_delta(
                request,
                zone,
                sampler.seed,
                world_x,
                world_y,
                Some(contour.signed_distance.abs()),
            ),
        0.0,
        1.0,
    );

    clamp(height, 0.0, 1.0)
}

#[cfg(test)]
fn sample_blurred_global_render_height(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
) -> f32 {
    let mut total = 0.0;
    for oy in -1..=1 {
        for ox in -1..=1 {
            total += sample_global_render_height(
                request,
                sdf,
                seed,
                world_x + ox as f32,
                world_y + oy as f32,
            );
        }
    }
    total / 9.0
}

struct GlobalSdfDistanceCache {
    origin_x: i32,
    origin_y: i32,
    width: u32,
    height: u32,
    values: Vec<f32>,
}

impl GlobalSdfDistanceCache {
    fn new(
        request: &AppRequest,
        sdf: &MapSdf,
        seed: u32,
        tile_origin_x: u32,
        tile_origin_y: u32,
        tile_size: u32,
    ) -> Self {
        let padding = global_sdf_distance_cache_padding_px(request);
        let width = tile_size + padding as u32 * 2 + 2;
        let height = width;
        let origin_x = tile_origin_x as i32 - padding;
        let origin_y = tile_origin_y as i32 - padding;
        let mut values = vec![0.0_f32; (width * height) as usize];
        values
            .par_iter_mut()
            .enumerate()
            .for_each(|(index, value)| {
                let x = (index as u32) % width;
                let y = (index as u32) / width;
                *value = controlled_sdf_distance_px(
                    request,
                    sdf,
                    seed,
                    (origin_x + x as i32) as f32,
                    (origin_y + y as i32) as f32,
                );
            });
        Self {
            origin_x,
            origin_y,
            width,
            height,
            values,
        }
    }

    fn sample(&self, world_x: f32, world_y: f32) -> f32 {
        let x = world_x - self.origin_x as f32;
        let y = world_y - self.origin_y as f32;
        let x0 = x.floor();
        let y0 = y.floor();
        let tx = x - x0;
        let ty = y - y0;
        let x0 = x0 as i32;
        let y0 = y0 as i32;
        let nw = self.value_at(x0, y0);
        let ne = self.value_at(x0 + 1, y0);
        let sw = self.value_at(x0, y0 + 1);
        let se = self.value_at(x0 + 1, y0 + 1);
        lerp(lerp(nw, ne, tx), lerp(sw, se, tx), ty)
    }

    fn gradient(&self, world_x: f32, world_y: f32) -> (f32, f32) {
        let step = 1.0_f32;
        let dx = (self.sample(world_x + step, world_y) - self.sample(world_x - step, world_y))
            / (step * 2.0);
        let dy = (self.sample(world_x, world_y + step) - self.sample(world_x, world_y - step))
            / (step * 2.0);
        (dx, dy)
    }

    fn value_at(&self, x: i32, y: i32) -> f32 {
        let x = x.clamp(0, self.width as i32 - 1) as u32;
        let y = y.clamp(0, self.height as i32 - 1) as u32;
        self.values[(y * self.width + x) as usize]
    }
}

fn global_sdf_distance_cache_padding_px(request: &AppRequest) -> i32 {
    let max_projection = request
        .south_height
        .max(request.north_height)
        .max(request.side_height)
        .max(request.crown_bevel)
        .max(request.rim_width)
        .max(request.outer_corner_radius)
        .max(request.inner_corner_radius)
        .max(request.corner_round_px)
        .max(request.diagonal_smooth_px) as f32
        + request.contour_warp_px.abs().ceil()
        + 4.0;
    max_projection.ceil().max(4.0) as i32
}

struct GlobalRenderHeightCache {
    origin_x: i32,
    origin_y: i32,
    width: u32,
    height: u32,
    values: Vec<f32>,
}

impl GlobalRenderHeightCache {
    fn new(
        sampler: GlobalSdfSampler<'_>,
        tile_origin_x: u32,
        tile_origin_y: u32,
        tile_size: u32,
    ) -> Self {
        let padding = 2_i32;
        let width = tile_size + padding as u32 * 2;
        let height = width;
        let origin_x = tile_origin_x as i32 - padding;
        let origin_y = tile_origin_y as i32 - padding;
        let mut values = vec![0.0_f32; (width * height) as usize];
        values
            .par_iter_mut()
            .enumerate()
            .for_each(|(index, value)| {
                let x = (index as u32) % width;
                let y = (index as u32) / width;
                *value = sample_global_render_height_with_sampler(
                    sampler,
                    (origin_x + x as i32) as f32,
                    (origin_y + y as i32) as f32,
                );
            });
        Self {
            origin_x,
            origin_y,
            width,
            height,
            values,
        }
    }

    fn sample(&self, world_x: f32, world_y: f32) -> f32 {
        let x = (world_x.round() as i32 - self.origin_x).clamp(0, self.width as i32 - 1) as u32;
        let y = (world_y.round() as i32 - self.origin_y).clamp(0, self.height as i32 - 1) as u32;
        self.values[(y * self.width + x) as usize]
    }
}

fn sample_blurred_global_render_height_from_cache(
    cache: &GlobalRenderHeightCache,
    world_x: f32,
    world_y: f32,
) -> f32 {
    let mut total = 0.0;
    for oy in -1..=1 {
        for ox in -1..=1 {
            total += cache.sample(world_x + ox as f32, world_y + oy as f32);
        }
    }
    total / 9.0
}

fn encode_global_normal_from_cache(
    cache: &GlobalRenderHeightCache,
    world_x: f32,
    world_y: f32,
    strength: f32,
) -> [u8; 3] {
    let at = |ox: i32, oy: i32| {
        sample_blurred_global_render_height_from_cache(
            cache,
            world_x + ox as f32,
            world_y + oy as f32,
        )
    };
    let (dx, dy) = sobel_gradient_from_samples(at);
    encode_normal_from_gradient(dx, dy, strength)
}

#[cfg(test)]
fn encode_global_normal(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
    strength: f32,
) -> [u8; 3] {
    let at = |ox: i32, oy: i32| {
        sample_blurred_global_render_height(
            request,
            sdf,
            seed,
            world_x + ox as f32,
            world_y + oy as f32,
        )
    };
    let (dx, dy) = sobel_gradient_from_samples(at);
    encode_normal_from_gradient(dx, dy, strength)
}

fn preview_edge_width_px(request: &AppRequest) -> f32 {
    let debris_width = request.tile_size as f32 * 0.06 * request.edge_debris.clamp(0.0, 1.0);
    (request.rim_width as f32)
        .max(debris_width)
        .min(request.tile_size as f32 * 0.25)
}

fn edge_relief_width_px(request: &AppRequest) -> f32 {
    preview_edge_width_px(request).max(request.rim_width.max(1) as f32)
}

fn edge_height_for_progress(progress: f32) -> f32 {
    lerp(0.90, 1.0, progress.clamp(0.0, 1.0))
}

fn controlled_sdf_distance_px(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
) -> f32 {
    let tile_size = request.tile_size.max(1) as f32;
    let cell_x = world_x / tile_size;
    let cell_y = world_y / tile_size;
    let field = smoothed_sdf_value(request, sdf, seed, world_x, world_y, cell_x, cell_y);
    field * tile_size - contour_distance_offset_px(request, seed, world_x, world_y)
}

fn controlled_sdf_gradient(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
) -> (f32, f32) {
    if !sdf_shape_controls_active(request) {
        let tile_size = request.tile_size.max(1) as f32;
        return sdf.gradient_with_step(world_x / tile_size, world_y / tile_size, 1.0 / tile_size);
    }

    let step = 1.0_f32;
    let dx = (controlled_sdf_distance_px(request, sdf, seed, world_x + step, world_y)
        - controlled_sdf_distance_px(request, sdf, seed, world_x - step, world_y))
        / (step * 2.0);
    let dy = (controlled_sdf_distance_px(request, sdf, seed, world_x, world_y + step)
        - controlled_sdf_distance_px(request, sdf, seed, world_x, world_y - step))
        / (step * 2.0);
    (dx, dy)
}

fn sdf_shape_controls_active(request: &AppRequest) -> bool {
    request.outer_corner_radius > 0
        || request.inner_corner_radius > 0
        || request.corner_round_px > 0
        || request.diagonal_smooth_px > 0
        || request.contour_warp_px > 0.0
        || request.roughness > 0.0
        || request.corner_variation > 0.0
}

fn smoothed_sdf_value(
    request: &AppRequest,
    sdf: &MapSdf,
    seed: u32,
    world_x: f32,
    world_y: f32,
    cell_x: f32,
    cell_y: f32,
) -> f32 {
    let tile_size = request.tile_size.max(1) as f32;
    let mut value = sdf.sample(cell_x, cell_y);
    let relax = (0.65 + request.contour_relax * 0.45).clamp(0.35, 1.1);
    let corner_mask = sdf_corner_mask(sdf, cell_x, cell_y);
    let corner_count = corner_mask.count_ones();

    if request.outer_corner_radius > 0 && corner_count == 1 {
        let strength = (request.outer_corner_radius as f32 / (tile_size * 0.5)).clamp(0.0, 1.0);
        let radius = varied_smoothing_radius_cells(
            request,
            seed.wrapping_add(1_701),
            world_x,
            world_y,
            request.outer_corner_radius as f32,
        );
        let smoothed = average_sdf_neighborhood(sdf, cell_x, cell_y, radius);
        value = lerp(value, smoothed, (strength * 0.78 * relax).clamp(0.0, 0.9));
    }

    if request.inner_corner_radius > 0 && corner_count == 3 {
        let strength = (request.inner_corner_radius as f32 / (tile_size * 0.5)).clamp(0.0, 1.0);
        let radius = varied_smoothing_radius_cells(
            request,
            seed.wrapping_add(1_907),
            world_x,
            world_y,
            request.inner_corner_radius as f32,
        );
        let smoothed = average_sdf_neighborhood(sdf, cell_x, cell_y, radius);
        value = lerp(value, smoothed, (strength * 0.78 * relax).clamp(0.0, 0.9));
    }

    if request.corner_round_px > 0 {
        let strength = (request.corner_round_px as f32 / (tile_size * 0.5)).clamp(0.0, 1.0);
        let radius = varied_smoothing_radius_cells(
            request,
            seed.wrapping_add(2_101),
            world_x,
            world_y,
            request.corner_round_px as f32,
        );
        let smoothed = average_sdf_neighborhood(sdf, cell_x, cell_y, radius);
        value = lerp(value, smoothed, (strength * 0.72 * relax).clamp(0.0, 0.88));
    }

    if request.diagonal_smooth_px > 0 {
        let strength = (request.diagonal_smooth_px as f32 / (tile_size * 0.5)).clamp(0.0, 1.0);
        let radius = varied_smoothing_radius_cells(
            request,
            seed.wrapping_add(3_307),
            world_x,
            world_y,
            request.diagonal_smooth_px as f32,
        );
        let smoothed = average_sdf_diagonals(sdf, cell_x, cell_y, radius);
        let softened = lerp(value, smoothed, (strength * 0.64 * relax).clamp(0.0, 0.82));
        value = value.max(softened);
        if let Some(bridge) = diagonal_bridge_sdf_value(sdf, cell_x, cell_y, strength, relax) {
            if value >= 0.0 {
                let saddle_width = lerp(0.035, 0.13, strength) * (0.85 + relax * 0.15);
                let saddle = line_mask(value, saddle_width);
                value = lerp(value, bridge, saddle);
            } else {
                value = value.max(bridge);
            }
        }
    }

    value
}

fn sdf_corner_mask(sdf: &MapSdf, cell_x: f32, cell_y: f32) -> u8 {
    let x0 = cell_x.floor() as i32;
    let y0 = cell_y.floor() as i32;
    u8::from(sdf.sample(x0 as f32, y0 as f32) > 0.0)
        | (u8::from(sdf.sample((x0 + 1) as f32, y0 as f32) > 0.0) << 1)
        | (u8::from(sdf.sample((x0 + 1) as f32, (y0 + 1) as f32) > 0.0) << 2)
        | (u8::from(sdf.sample(x0 as f32, (y0 + 1) as f32) > 0.0) << 3)
}

fn varied_smoothing_radius_cells(
    request: &AppRequest,
    seed: u32,
    world_x: f32,
    world_y: f32,
    radius_px: f32,
) -> f32 {
    let tile_size = request.tile_size.max(1) as f32;
    let mut radius = (radius_px / tile_size).max(0.001);
    if request.corner_variation > 0.0 {
        let period = (tile_size * 5.0).max(1.0);
        let noise = fbm_tiled(
            world_x * 0.037 + 13.0,
            world_y * 0.037 + 29.0,
            period * 0.037,
            period * 0.037,
            2,
            seed,
        );
        radius *= 1.0 + (noise - 0.5) * 2.0 * request.corner_variation * 0.45;
    }
    radius.clamp(0.001, 0.75)
}

fn average_sdf_neighborhood(sdf: &MapSdf, cell_x: f32, cell_y: f32, radius: f32) -> f32 {
    let samples = [
        (0.0_f32, 0.0_f32, 4.0_f32),
        (-radius, 0.0, 2.0),
        (radius, 0.0, 2.0),
        (0.0, -radius, 2.0),
        (0.0, radius, 2.0),
        (-radius, -radius, 1.0),
        (radius, -radius, 1.0),
        (-radius, radius, 1.0),
        (radius, radius, 1.0),
    ];
    weighted_sdf_average(sdf, cell_x, cell_y, &samples)
}

fn average_sdf_diagonals(sdf: &MapSdf, cell_x: f32, cell_y: f32, radius: f32) -> f32 {
    let samples = [
        (0.0_f32, 0.0_f32, 2.0_f32),
        (-radius, -radius, 1.0),
        (radius, -radius, 1.0),
        (-radius, radius, 1.0),
        (radius, radius, 1.0),
    ];
    weighted_sdf_average(sdf, cell_x, cell_y, &samples)
}

fn diagonal_bridge_sdf_value(
    sdf: &MapSdf,
    cell_x: f32,
    cell_y: f32,
    strength: f32,
    relax: f32,
) -> Option<f32> {
    let x0 = cell_x.floor() as i32;
    let y0 = cell_y.floor() as i32;
    let u = (cell_x - x0 as f32).clamp(0.0, 1.0);
    let v = (cell_y - y0 as f32).clamp(0.0, 1.0);
    let corner_inside = |ox: i32, oy: i32| sdf.sample((x0 + ox) as f32, (y0 + oy) as f32) > 0.0;
    let mask = u8::from(corner_inside(0, 0))
        | (u8::from(corner_inside(1, 0)) << 1)
        | (u8::from(corner_inside(1, 1)) << 2)
        | (u8::from(corner_inside(0, 1)) << 3);
    let diagonal_distance = match mask & 0x0f {
        0b0101 => (u - v).abs(),
        0b1010 => (u + v - 1.0).abs(),
        _ => return None,
    };
    let width =
        lerp(0.18, 0.72, strength).clamp(0.04, 0.74) * (0.85 + relax * 0.18).clamp(0.85, 1.05);
    if diagonal_distance >= width {
        return None;
    }

    let endpoint_distance = u.min(1.0 - u).min(v.min(1.0 - v));
    let endpoint_fade = line_mask(0.04 - endpoint_distance, 0.04);
    if endpoint_fade <= 0.001 {
        return None;
    }
    let bridge_strength = line_mask(diagonal_distance, width) * endpoint_fade;
    Some(-lerp(0.018, 0.105, strength) * bridge_strength)
}

fn weighted_sdf_average(
    sdf: &MapSdf,
    cell_x: f32,
    cell_y: f32,
    samples: &[(f32, f32, f32)],
) -> f32 {
    let mut sum = 0.0_f32;
    let mut weight_sum = 0.0_f32;
    for (offset_x, offset_y, weight) in samples {
        sum += sdf.sample(cell_x + *offset_x, cell_y + *offset_y) * *weight;
        weight_sum += *weight;
    }
    sum / weight_sum.max(0.001)
}

fn contour_distance_offset_px(request: &AppRequest, seed: u32, world_x: f32, world_y: f32) -> f32 {
    let mut offset = 0.0_f32;
    if request.contour_warp_px > 0.0 {
        let period = (request.tile_size as f32 * 8.0).max(1.0);
        let warp = fbm_tiled(
            world_x * 0.055,
            world_y * 0.055,
            period * 0.055,
            period * 0.055,
            2,
            seed.wrapping_add(5_911),
        ) - 0.5;
        offset += warp * request.contour_warp_px;
    }

    let rough_px = (request.roughness / 100.0) * (request.tile_size as f32 * 0.085);
    if rough_px > 0.0 {
        let period = edge_noise_period(request);
        let rough = fbm_tiled(
            world_x * 0.11 + 31.0,
            world_y * 0.11 + 17.0,
            period * 0.11,
            period * 0.11,
            3,
            seed.wrapping_add(8_711),
        ) - 0.5;
        offset += rough * rough_px * 2.0;
    }

    offset
}

fn zone_index(zone: SurfaceZone) -> usize {
    match zone {
        SurfaceZone::Top => 0,
        SurfaceZone::Edge => 1,
        SurfaceZone::Face => 2,
        SurfaceZone::Back => 3,
        SurfaceZone::Empty => 4,
    }
}

fn dominant_zone(counts: [u32; 5]) -> SurfaceZone {
    let mut best_index = 0_usize;
    let mut best_count = counts[0];
    for (index, count) in counts.iter().copied().enumerate().skip(1) {
        if count > best_count {
            best_index = index;
            best_count = count;
        }
    }
    match best_index {
        0 => SurfaceZone::Top,
        1 => SurfaceZone::Edge,
        2 => SurfaceZone::Face,
        3 => SurfaceZone::Back,
        _ => SurfaceZone::Empty,
    }
}

fn dominant_occupied_zone(counts: [u32; 5]) -> SurfaceZone {
    let occupied_counts = [counts[0], counts[1], counts[2], counts[3], 0];
    dominant_zone(occupied_counts)
}

#[derive(Debug, Clone, Copy)]
struct ContourDistance {
    signed_distance: f32,
    zone: SurfaceZone,
    depth: f32,
    gradient_x: f32,
    gradient_y: f32,
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
    let rough_px = edge_rough_px(request);
    let edge_period = edge_noise_period(request);

    let mut min_height = 1.0_f32;
    let mut min_zone = SurfaceZone::Top;

    if let Some(contour) = outer_contour_distance(request, signature, seed, x, y, world_x, world_y)
    {
        if contour.signed_distance < 0.0 {
            let outside_distance = -contour.signed_distance;
            if outside_distance > contour.depth {
                return (0.0, SurfaceZone::Empty);
            }
            let progress = (outside_distance / contour.depth.max(1.0)).clamp(0.0, 1.0);
            let height = match contour.zone {
                SurfaceZone::Back => back_height_for_progress(request, progress),
                _ => face_height_for_progress(request, progress),
            };
            return (clamp(height, 0.0, 1.0), contour.zone);
        }
    }

    let notch_side = side_depth.max(2.0);
    let notch_north = north_depth.max(2.0);
    let inner_radius = relaxed_corner_radius(
        request,
        request.inner_corner_radius as f32,
        seed.wrapping_add(719),
        world_x,
        world_y,
    );

    if signature.notch_ne {
        let x_start = size - notch_side
            + edge_jitter(world_y, seed.wrapping_add(53), rough_px * 0.8, edge_period);
        let y_end =
            notch_north + edge_jitter(world_x, seed.wrapping_add(59), rough_px * 0.8, edge_period);
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(
                x - x_start,
                y_end - y,
                notch_side,
                notch_north,
                inner_radius,
            ) {
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
        let x_end =
            notch_side + edge_jitter(world_y, seed.wrapping_add(61), rough_px * 0.8, edge_period);
        let y_end =
            notch_north + edge_jitter(world_x, seed.wrapping_add(67), rough_px * 0.8, edge_period);
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(
                x_end - x,
                y_end - y,
                notch_side,
                notch_north,
                inner_radius,
            ) {
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
        let x_start = east_boundary(
            request,
            rough_px,
            edge_period,
            seed.wrapping_add(37),
            world_y,
        );
        let y_start = south_boundary(
            request,
            rough_px,
            edge_period,
            seed.wrapping_add(23),
            world_x,
        );
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(
                x - x_start,
                y - y_start,
                notch_side,
                request.south_height as f32,
                inner_radius,
            ) {
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
        let x_end = west_boundary(
            request,
            rough_px,
            edge_period,
            seed.wrapping_add(41),
            world_y,
        );
        let y_start = south_boundary(
            request,
            rough_px,
            edge_period,
            seed.wrapping_add(23),
            world_x,
        );
        if inner_radius > 0.0 {
            if let Some(progress) = rounded_inner_notch_progress(
                x_end - x,
                y - y_start,
                notch_side,
                request.south_height as f32,
                inner_radius,
            ) {
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

    (clamp(min_height, 0.0, 1.0), min_zone)
}

fn outer_contour_distance(
    request: &AppRequest,
    signature: &Signature,
    seed: u32,
    x: f32,
    y: f32,
    world_x: f32,
    world_y: f32,
) -> Option<ContourDistance> {
    marching_contour_distance(request, signature, seed, x, y, world_x, world_y)
}

fn marching_contour_distance(
    request: &AppRequest,
    signature: &Signature,
    seed: u32,
    x: f32,
    y: f32,
    world_x: f32,
    world_y: f32,
) -> Option<ContourDistance> {
    let mask = signature.marching_mask & 0x0f;
    if mask == 0 {
        return Some(ContourDistance {
            signed_distance: -(request.tile_size as f32),
            zone: SurfaceZone::Face,
            depth: 0.0,
            gradient_x: 0.0,
            gradient_y: 1.0,
        });
    }
    if mask == 0x0f {
        return None;
    }

    let size = (request.tile_size as f32 - 1.0).max(1.0);
    let u = (x / size).clamp(0.0, 1.0);
    let v = (y / size).clamp(0.0, 1.0);
    let nw = f32::from(signature.corner_nw);
    let ne = f32::from(signature.corner_ne);
    let se = f32::from(signature.corner_se);
    let sw = f32::from(signature.corner_sw);
    let north = lerp(nw, ne, u);
    let south = lerp(sw, se, u);
    let value = lerp(north, south, v);
    let du = lerp(ne - nw, se - sw, v);
    let dv = lerp(sw - nw, se - ne, u);
    let mut gx = du;
    let mut gy = dv;
    let mut gradient_len = (gx * gx + gy * gy).sqrt();
    if gradient_len < 0.001 {
        let fallback = fallback_marching_gradient(signature, u, v);
        gx = fallback.0;
        gy = fallback.1;
        gradient_len = (gx * gx + gy * gy).sqrt().max(0.001);
    }

    let value = adjusted_marching_value(request, signature, value, u, v);
    let threshold = marching_threshold(request, seed, world_x, world_y);
    let signed_distance = ((value - threshold) / gradient_len) * request.tile_size as f32;
    let (zone, depth) = marching_zone_and_depth(request, gx, gy);

    Some(ContourDistance {
        signed_distance,
        zone,
        depth,
        gradient_x: gx,
        gradient_y: gy,
    })
}

fn adjusted_marching_value(
    request: &AppRequest,
    signature: &Signature,
    base_value: f32,
    u: f32,
    v: f32,
) -> f32 {
    let max_radius = (request.tile_size as f32 * 0.5).max(1.0);
    let mut value = base_value;

    if request.corner_round_px > 0 {
        let strength = (request.corner_round_px as f32 / max_radius).clamp(0.0, 1.0);
        let rounded_value = rounded_corner_field(signature, u, v, strength);
        value = lerp(value, rounded_value, strength * 0.55);
    }

    if request.diagonal_smooth_px > 0 {
        let strength = (request.diagonal_smooth_px as f32 / max_radius).clamp(0.0, 1.0);
        if let Some(diagonal_value) = diagonal_smooth_field(signature.marching_mask, u, v) {
            value = lerp(value, diagonal_value, strength * 0.35);
        }
    }

    value.clamp(0.0, 1.0)
}

fn rounded_corner_field(signature: &Signature, u: f32, v: f32, strength: f32) -> f32 {
    let corners = [
        (0.0_f32, 0.0_f32, signature.corner_nw),
        (1.0_f32, 0.0_f32, signature.corner_ne),
        (1.0_f32, 1.0_f32, signature.corner_se),
        (0.0_f32, 1.0_f32, signature.corner_sw),
    ];
    let sigma = lerp(0.18, 0.58, strength).max(0.001);
    let sigma_sq = sigma * sigma * 2.0;
    let mut inside_weight = 0.0_f32;
    let mut empty_weight = 0.0_f32;

    for (corner_u, corner_v, filled) in corners {
        let du = u - corner_u;
        let dv = v - corner_v;
        let weight = (-(du * du + dv * dv) / sigma_sq).exp();
        if filled {
            inside_weight += weight;
        } else {
            empty_weight += weight;
        }
    }

    let total = inside_weight + empty_weight;
    if total <= 0.0001 {
        0.5
    } else {
        inside_weight / total
    }
}

fn diagonal_smooth_field(mask: u8, u: f32, v: f32) -> Option<f32> {
    match mask & 0x0f {
        0b0101 => Some((1.0 - (u - v).abs()).clamp(0.0, 1.0)),
        0b1010 => Some((1.0 - (u + v - 1.0).abs()).clamp(0.0, 1.0)),
        _ => None,
    }
}

fn fallback_marching_gradient(signature: &Signature, u: f32, v: f32) -> (f32, f32) {
    let corners = [
        (0.0_f32, 0.0_f32, signature.corner_nw),
        (1.0_f32, 0.0_f32, signature.corner_ne),
        (1.0_f32, 1.0_f32, signature.corner_se),
        (0.0_f32, 1.0_f32, signature.corner_sw),
    ];
    let mut nearest_inside = None;
    let mut nearest_empty = None;
    for (cx, cy, filled) in corners {
        let dx = cx - u;
        let dy = cy - v;
        let distance_sq = dx * dx + dy * dy;
        let slot = if filled {
            &mut nearest_inside
        } else {
            &mut nearest_empty
        };
        if slot.map_or(true, |(_, _, current): (f32, f32, f32)| {
            distance_sq < current
        }) {
            *slot = Some((dx, dy, distance_sq));
        }
    }

    match (nearest_inside, nearest_empty) {
        (Some((ix, iy, _)), Some((ex, ey, _))) => (ix - ex, iy - ey),
        (Some((ix, iy, _)), None) => (ix, iy),
        _ => (0.0, 1.0),
    }
}

fn marching_threshold(request: &AppRequest, seed: u32, world_x: f32, world_y: f32) -> f32 {
    if request.contour_warp_px <= 0.0 {
        return 0.5;
    }

    let period = (request.tile_size as f32 * 8.0).max(1.0);
    let warp = fbm_tiled(
        world_x * 0.055,
        world_y * 0.055,
        period * 0.055,
        period * 0.055,
        2,
        seed.wrapping_add(5_911),
    ) - 0.5;
    (0.5 + warp * request.contour_warp_px / request.tile_size as f32).clamp(0.38, 0.62)
}

fn marching_zone_and_depth(request: &AppRequest, gx: f32, gy: f32) -> (SurfaceZone, f32) {
    let ax = gx.abs();
    let ay = gy.abs();
    let total = (ax + ay).max(0.001);
    if gy > ax * 0.75 {
        let north_weight = ay / total;
        let side_weight = ax / total;
        let side_depth = if request.north_height > 0 {
            request.side_height as f32 * side_weight
        } else {
            0.0
        };
        return (
            SurfaceZone::Back,
            request.north_height as f32 * north_weight + side_depth,
        );
    }

    let south_weight = if gy < 0.0 { ay / total } else { 0.0 };
    let side_fade = if request.north_height == 0 && gy > 0.0 {
        let fade_span = (ax * 0.75).max(0.001);
        (1.0 - gy / fade_span).clamp(0.0, 1.0)
    } else {
        1.0
    };
    let side_weight = (1.0 - south_weight) * side_fade;
    (
        SurfaceZone::Face,
        request.south_height as f32 * south_weight + request.side_height as f32 * side_weight,
    )
}

fn south_boundary(
    request: &AppRequest,
    rough_px: f32,
    edge_period: f32,
    seed: u32,
    edge_coord: f32,
) -> f32 {
    (request.tile_size as f32 - 1.0 - request.south_height as f32)
        + edge_jitter(edge_coord, seed, rough_px, edge_period)
}

fn east_boundary(
    request: &AppRequest,
    rough_px: f32,
    edge_period: f32,
    seed: u32,
    edge_coord: f32,
) -> f32 {
    (request.tile_size as f32 - 1.0 - request.side_height as f32)
        + edge_jitter(edge_coord, seed, rough_px, edge_period)
}

fn west_boundary(
    request: &AppRequest,
    rough_px: f32,
    edge_period: f32,
    seed: u32,
    edge_coord: f32,
) -> f32 {
    request.side_height as f32 + edge_jitter(edge_coord, seed, rough_px, edge_period)
}

fn edge_rough_px(request: &AppRequest) -> f32 {
    (request.roughness / 100.0) * (request.tile_size as f32 * 0.085) + request.contour_warp_px
}

fn back_height_for_progress(request: &AppRequest, progress: f32) -> f32 {
    1.0 - progress * request.back_drop
}

fn face_height_for_progress(request: &AppRequest, progress: f32) -> f32 {
    (1.0 - progress).powf(request.face_power)
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

fn relaxed_corner_radius(
    request: &AppRequest,
    base_radius: f32,
    seed: u32,
    world_x: f32,
    world_y: f32,
) -> f32 {
    let relax = request.contour_relax * request.tile_size as f32 * 0.07;
    let mut radius = base_radius + relax;
    if request.corner_variation > 0.0 && radius > 0.0 {
        let period = (request.tile_size as f32 * 5.0).max(1.0);
        let noise = fbm_tiled(
            world_x * 0.037 + 13.0,
            world_y * 0.037 + 29.0,
            period * 0.037,
            period * 0.037,
            2,
            seed,
        );
        let variation = (noise - 0.5) * 2.0 * request.corner_variation;
        radius *= 1.0 + variation;
    }

    radius.clamp(0.0, request.tile_size as f32 * 0.5)
}

fn set_min_height(
    current_height: &mut f32,
    current_zone: &mut SurfaceZone,
    candidate: f32,
    zone: SurfaceZone,
) {
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
    field: SurfaceField<'_>,
    global_distance_cache: Option<&GlobalSdfDistanceCache>,
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
            if let Some(contour) = contour_distance_for_field(
                request,
                field,
                global_distance_cache,
                seed,
                xf,
                yf,
                world_x,
                world_y,
            ) {
                let nearest = contour.signed_distance;
                if nearest < 0.0 || nearest >= bevel {
                    continue;
                }
                let t = (nearest / bevel).clamp(0.0, 1.0);
                heights[index] = heights[index].min(lerp(0.86, 1.0, t));
            }
        }
    }
}

fn apply_organic_height_relief(
    request: &AppRequest,
    field: SurfaceField<'_>,
    global_distance_cache: Option<&GlobalSdfDistanceCache>,
    seed: u32,
    origin_x: u32,
    origin_y: u32,
    heights: &mut [f32],
    zones: &[SurfaceZone],
    occupancies: &[f32],
) {
    if request.rim_width == 0 && request.edge_debris <= 0.0 && request.normal_detail_strength <= 0.0
    {
        return;
    }

    let size = request.tile_size as usize;
    for y in 0..size {
        for x in 0..size {
            let index = y * size + x;
            let zone = zones[index];
            if zone == SurfaceZone::Empty || occupancies[index] <= 0.0 {
                continue;
            }

            let world_x = origin_x as f32 + x as f32;
            let world_y = origin_y as f32 + y as f32;
            let edge_distance = if request.rim_width > 0 || request.edge_debris > 0.0 {
                exposed_edge_distance(
                    request,
                    field,
                    global_distance_cache,
                    seed,
                    x as f32,
                    y as f32,
                    world_x,
                    world_y,
                )
            } else {
                None
            };
            let delta = organic_height_delta(request, zone, seed, world_x, world_y, edge_distance);
            heights[index] = clamp(heights[index] + delta, 0.0, 1.0);
        }
    }
}

fn organic_height_delta(
    request: &AppRequest,
    zone: SurfaceZone,
    seed: u32,
    world_x: f32,
    world_y: f32,
    edge_distance: Option<f32>,
) -> f32 {
    if zone == SurfaceZone::Empty
        || (request.rim_width == 0
            && request.edge_debris <= 0.0
            && request.normal_detail_strength <= 0.0)
    {
        return 0.0;
    }

    let period = (request.tile_size as f32 * 4.0).max(1.0);
    let broad = fbm_tiled(
        world_x * 0.065,
        world_y * 0.065,
        period * 0.065,
        period * 0.065,
        3,
        seed.wrapping_add(1_003),
    );
    let fine = fbm_tiled(
        world_x * 0.21 + 41.0,
        world_y * 0.19 + 17.0,
        period * 0.21,
        period * 0.19,
        2,
        seed.wrapping_add(1_819),
    );
    let zone_amp = match zone {
        SurfaceZone::Top => 0.012,
        SurfaceZone::Edge => 0.026,
        SurfaceZone::Face => 0.036,
        SurfaceZone::Back => 0.022,
        SurfaceZone::Empty => 0.0,
    };
    let mut delta =
        ((broad - 0.5) * 0.65 + (fine - 0.5) * 0.35) * zone_amp * request.normal_detail_strength;

    if (request.rim_width > 0 || request.edge_debris > 0.0)
        && let Some(distance) = edge_distance
    {
        let rim = (1.0 - distance / edge_relief_width_px(request)).clamp(0.0, 1.0);
        if rim > 0.0 {
            let chip = ((fine - 0.38) * 2.2).clamp(0.0, 1.0);
            let rim_cut = if request.rim_width > 0 {
                request.contour_relax * 0.018
            } else {
                0.0
            };
            let edge_cut = rim * (rim_cut + chip * request.edge_debris * 0.045);
            delta -= edge_cut;
            if zone == SurfaceZone::Face {
                delta += rim * request.edge_debris * (broad - 0.45) * 0.026;
            }
        }
    }

    delta
}

fn exposed_edge_distance(
    request: &AppRequest,
    field: SurfaceField<'_>,
    global_distance_cache: Option<&GlobalSdfDistanceCache>,
    seed: u32,
    x: f32,
    y: f32,
    world_x: f32,
    world_y: f32,
) -> Option<f32> {
    contour_distance_for_field(
        request,
        field,
        global_distance_cache,
        seed,
        x,
        y,
        world_x,
        world_y,
    )
    .map(|contour| contour.signed_distance.abs())
}

fn contour_distance_for_field(
    request: &AppRequest,
    field: SurfaceField<'_>,
    global_distance_cache: Option<&GlobalSdfDistanceCache>,
    seed: u32,
    x: f32,
    y: f32,
    world_x: f32,
    world_y: f32,
) -> Option<ContourDistance> {
    match field {
        SurfaceField::Local(signature) => {
            outer_contour_distance(request, signature, seed, x, y, world_x, world_y)
        }
        SurfaceField::GlobalSdf(sdf) => Some(global_contour_distance_with_sampler(
            GlobalSdfSampler {
                request,
                sdf,
                seed,
                distance_cache: global_distance_cache,
            },
            world_x,
            world_y,
        )),
    }
}

fn global_contour_distance_with_sampler(
    sampler: GlobalSdfSampler<'_>,
    world_x: f32,
    world_y: f32,
) -> ContourDistance {
    let signed_distance = sampler.distance_px(world_x, world_y);
    let (gx, gy) = sampler.gradient(world_x, world_y);
    let request = sampler.request;
    let (zone, depth) = marching_zone_and_depth(request, gx, gy);

    ContourDistance {
        signed_distance,
        zone,
        depth,
        gradient_x: gx,
        gradient_y: gy,
    }
}

fn material_coords_for_zone(
    request: &AppRequest,
    field: SurfaceField<'_>,
    global_distance_cache: Option<&GlobalSdfDistanceCache>,
    seed: u32,
    zone: SurfaceZone,
    world_x: f32,
    world_y: f32,
) -> (f32, f32) {
    if !matches!(
        zone,
        SurfaceZone::Face | SurfaceZone::Back | SurfaceZone::Edge
    ) {
        return (world_x, world_y);
    }

    match field {
        SurfaceField::GlobalSdf(sdf) => {
            let sampler = GlobalSdfSampler {
                request,
                sdf,
                seed,
                distance_cache: global_distance_cache,
            };
            let contour = global_contour_distance_with_sampler(sampler, world_x, world_y);
            let (gx, gy) = (contour.gradient_x, contour.gradient_y);
            let len = (gx * gx + gy * gy).sqrt();
            if len <= 0.0001 {
                return (world_x, world_y);
            }

            let nx = gx / len;
            let ny = gy / len;
            let tangent_x = -ny;
            let tangent_y = nx;
            let along = (world_x * tangent_x + world_y * tangent_y).abs();
            let depth = if zone == SurfaceZone::Face && front_only_projection_active(request) {
                front_only_projected_facade_progress(sampler, world_x, world_y)
                    .map(|progress| progress * request.south_height as f32)
                    .unwrap_or_else(|| contour.signed_distance.abs())
            } else {
                contour.signed_distance.abs()
            };
            (along, depth)
        }
        SurfaceField::Local(_) => (world_x, world_y),
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
    x: f32,
    y: f32,
    seed: u32,
) -> MaterialBaseSample {
    match material.source.as_str() {
        "image" => {
            if let Some(texture) = texture {
                let sample_scale = 1.0 / texture_scale.max(0.001);
                let sample = texture.sample_filtered(
                    (x + 0.5) * sample_scale,
                    (y + 0.5) * sample_scale,
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
                        x,
                        y,
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
            rgb: procedural_layer_material(material, seed, x, y, tile_size as f32, [128, 128, 128]),
            is_image_source: false,
        },
    }
}

#[cfg(test)]
mod tests {
    #![allow(unused_variables)]

    use crate::model::{ExportMode, MapData, default_request};
    use crate::sdf::MapSdf;
    use crate::signature::signature_at;
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

    fn images_differ(left: &RgbaImage, right: &RgbaImage) -> bool {
        left.dimensions() == right.dimensions()
            && left
                .pixels()
                .zip(right.pixels())
                .any(|(left_pixel, right_pixel)| left_pixel.0 != right_pixel.0)
    }

    fn occupied_pixels(image: &RgbaImage) -> usize {
        image.pixels().filter(|pixel| pixel.0[3] > 0).count()
    }

    fn images_match(left: &RgbaImage, right: &RgbaImage) -> bool {
        left.dimensions() == right.dimensions()
            && left
                .pixels()
                .zip(right.pixels())
                .all(|(left_pixel, right_pixel)| left_pixel.0 == right_pixel.0)
    }

    fn thin_occupied_columns(image: &RgbaImage) -> usize {
        (0..image.width())
            .filter(|x| {
                let occupied = (0..image.height())
                    .filter(|y| image.get_pixel(*x, *y).0[3] > 0)
                    .count();
                occupied > 0 && occupied <= 3
            })
            .count()
    }

    fn unique_edge_albedo_colors(tile: &TileBuffers) -> usize {
        let mut colors = std::collections::BTreeSet::new();
        for y in 0..tile.albedo.height() {
            for x in 0..tile.albedo.width() {
                let mask = tile.mask.get_pixel(x, y).0;
                if mask[0] == 255 && mask[1] == 255 && mask[3] == 255 {
                    let albedo = tile.albedo.get_pixel(x, y).0;
                    colors.insert([albedo[0], albedo[1], albedo[2]]);
                }
            }
        }
        colors.len()
    }

    fn flat_material(color: &str) -> MaterialConfig {
        MaterialConfig {
            source: "flat".to_string(),
            kind: "rough_stone".to_string(),
            scale: 1.0,
            contrast: 1.0,
            crack_amount: 0.0,
            wear: 0.0,
            grain: 0.0,
            edge_darkening: 0.0,
            seed: 0,
            color_a: color.to_string(),
            color_b: color.to_string(),
            highlight: color.to_string(),
        }
    }

    fn flat_preview_request() -> AppRequest {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_round_px = 0;
        request.diagonal_smooth_px = 0;
        request.corner_variation = 0.0;
        request.geometry_variance = 0.0;
        request.normal_detail_strength = 0.0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.shape_supersampling = 4;
        request.materials.top = flat_material("#ffffff");
        request.materials.face = flat_material("#000000");
        request.materials.base = flat_material("#ff0000");
        request.colors.top = "#ffffff".to_string();
        request.colors.face = "#000000".to_string();
        request.colors.back = "#404040".to_string();
        request.colors.base = "#ff0000".to_string();
        request.sanitized()
    }

    fn partial_mask_pixels_with_unblended_albedo(tile: &TileBuffers) -> usize {
        let mut count = 0_usize;
        for y in 0..tile.mask.height() {
            for x in 0..tile.mask.width() {
                let alpha = tile.mask.get_pixel(x, y).0[3];
                if alpha == 0 || alpha == 255 {
                    continue;
                }
                let rgb = &tile.albedo.get_pixel(x, y).0[0..3];
                if rgb == [255, 255, 255] || rgb == [0, 0, 0] || rgb == [255, 0, 0] {
                    count += 1;
                }
            }
        }
        count
    }

    #[test]
    fn texture_scale_above_one_zooms_texture_without_box_blur() {
        let texture = LoadedTexture {
            image: RgbaImage::from_fn(4, 1, |x, _| Rgba([(x * 64) as u8, 0, 0, 255])),
        };

        let sample = sample_material_base(&image_material(), Some(&texture), 4.0, 32, 0.0, 0.0, 0);

        assert!(
            sample.rgb[0] < 24,
            "expected scale 4.0 to magnify the first texel, got red={}",
            sample.rgb[0]
        );
        assert!(sample.is_image_source);
    }

    #[test]
    fn zone_tint_does_not_multiply_non_image_materials() {
        let color = sample_material_color(
            &flat_material("#804020"),
            [0x20, 0x40, 0x60],
            None,
            1.0,
            false,
            64,
            8.0,
            8.0,
            0,
            1.0,
        );

        assert_eq!(
            color,
            [0x80, 0x40, 0x20],
            "flat/procedural materials already carry their own color and must not be multiplied by colors.*"
        );
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
    fn lit_preview_uses_normals_without_baking_albedo() {
        let mut request = default_request();
        request.tile_size = 64;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.normal_detail_strength = 2.0;
        request.bake_height_shading = false;
        request.preview_mode = "lit".to_string();
        let request = request.sanitized();
        let signature = Signature::from_marching_mask(0b0011);

        let tile = render_tile(&request, &TextureSet::default(), &signature, 0, 0, 0);
        let raw_albedo = tile.albedo.clone();
        let lit_preview = extract_mode_image(tile, &request);

        assert!(
            images_differ(&raw_albedo, &lit_preview),
            "lit preview should visualize normal/height response without requiring baked albedo shading"
        );
    }

    #[test]
    fn global_sdf_height_transitions_from_top_to_face_to_empty() {
        let mut request = default_request();
        request.tile_size = 64;
        request.side_height = 16;
        request.south_height = 16;
        request.north_height = 8;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_round_px = 0;
        request.diagonal_smooth_px = 0;
        request.corner_variation = 0.0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        let request = request.sanitized();
        let map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        let sdf = MapSdf::compute(&map);

        let (inside_height, inside_zone) =
            sample_global_height(&request, &sdf, request.seed, 1.25 * 64.0, 1.0 * 64.0);
        let (face_height, face_zone) =
            sample_global_height(&request, &sdf, request.seed, 1.51 * 64.0, 1.0 * 64.0);
        let (empty_height, empty_zone) =
            sample_global_height(&request, &sdf, request.seed, 1.80 * 64.0, 1.0 * 64.0);

        assert_eq!(inside_zone, SurfaceZone::Top);
        assert_eq!(inside_height, 1.0);
        assert_eq!(face_zone, SurfaceZone::Face);
        assert!(face_height > 0.0 && face_height < 1.0);
        assert_eq!(empty_zone, SurfaceZone::Empty);
        assert_eq!(empty_height, 0.0);
    }

    #[test]
    fn cached_map_sdf_returns_shared_arc_on_cache_hit() {
        let map = MapData {
            width: 2,
            height: 2,
            cells: vec![1, 0, 0, 1],
        };

        let first = cached_map_sdf(&map, 8);
        let second = cached_map_sdf(&map, 8);

        assert!(
            std::sync::Arc::ptr_eq(&first, &second),
            "cache hits should share the same SDF allocation instead of cloning the value table"
        );
    }

    #[test]
    fn mask_preview_empty_cells_are_transparent() {
        let mut request = flat_preview_request();
        request.preview_mode = "mask".to_string();
        request.map = MapData {
            width: 1,
            height: 1,
            cells: vec![0],
        };

        let preview = build_map_preview(&request, &TextureSet::default())
            .expect("mask preview should render");

        assert_eq!(
            preview.get_pixel(0, 0).0,
            [0, 0, 0, 0],
            "mask preview should not paint base albedo into empty cells"
        );
    }

    fn single_cell_sdf_request() -> (AppRequest, MapSdf, Signature) {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_round_px = 0;
        request.diagonal_smooth_px = 0;
        request.geometry_variance = 0.0;
        request.normal_detail_strength = 0.0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.shape_supersampling = 4;
        let mut request = request.sanitized();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        (request, sdf, signature)
    }

    fn diagonal_sdf_request() -> (AppRequest, MapSdf, Signature) {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_round_px = 0;
        request.diagonal_smooth_px = 0;
        request.geometry_variance = 0.0;
        request.normal_detail_strength = 0.0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.shape_supersampling = 4;
        let mut request = request.sanitized();
        request.map = MapData {
            width: 2,
            height: 2,
            cells: vec![1, 0, 0, 1],
        };
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 0, 0);
        (request, sdf, signature)
    }

    fn straight_south_sdf_request() -> (AppRequest, MapSdf, Signature) {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 32;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_round_px = 0;
        request.diagonal_smooth_px = 0;
        request.geometry_variance = 0.0;
        request.normal_detail_strength = 0.0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.shape_supersampling = 4;
        let mut request = request.sanitized();
        request.map = MapData {
            width: 2,
            height: 2,
            cells: vec![1, 1, 0, 0],
        };
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 0, 0);
        (request, sdf, signature)
    }

    #[test]
    fn global_sdf_south_face_uses_the_configured_pixel_depth() {
        let (request, sdf, signature) = straight_south_sdf_request();
        let world_x = 32.0;
        let world_y = 63.0;
        let (local_height, local_zone) = sample_height(
            &request,
            &signature,
            request.seed,
            world_x,
            world_y,
            world_x,
            world_y,
        );
        let (global_height, global_zone) =
            sample_global_height(&request, &sdf, request.seed, world_x, world_y);

        assert_eq!(local_zone, SurfaceZone::Face);
        assert_eq!(
            global_zone, local_zone,
            "global SDF should not halve the configured south face depth"
        );
        assert!(
            (global_height - local_height).abs() < 0.05,
            "global height {global_height} should stay close to local marching height {local_height}"
        );
    }

    #[test]
    fn global_sdf_keeps_diagonal_neck_as_wide_as_local_marching() {
        let (mut request, sdf, signature) = diagonal_sdf_request();
        request.diagonal_smooth_px = 6;
        let request = request.sanitized();
        let world_x = 48.0;
        let world_y = 16.0;
        let (local_height, local_zone) = sample_height(
            &request,
            &signature,
            request.seed,
            world_x,
            world_y,
            world_x,
            world_y,
        );
        let (global_height, global_zone) =
            sample_global_height(&request, &sdf, request.seed, world_x, world_y);

        assert_ne!(
            local_zone,
            SurfaceZone::Empty,
            "local marching keeps this diagonal throat sample occupied"
        );
        assert_eq!(
            global_zone, local_zone,
            "global SDF should preserve the old diagonal throat instead of collapsing it"
        );
        assert!(
            (global_height - local_height).abs() < 0.15,
            "global height {global_height} should stay close to local marching height {local_height}"
        );
    }

    #[test]
    fn corner_round_px_changes_sdf_preview_mask_geometry() {
        let (sharp, sdf, signature) = single_cell_sdf_request();
        let mut rounded = sharp.clone();
        rounded.corner_round_px = 24;
        let rounded = rounded.sanitized();

        let sharp_tile = render_tile_with_sdf(&sharp, &TextureSet::default(), &sdf, 0, 64, 64);
        let rounded_tile = render_tile_with_sdf(&rounded, &TextureSet::default(), &sdf, 0, 64, 64);

        assert!(
            images_differ(&sharp_tile.mask, &rounded_tile.mask),
            "corner_round_px should alter live SDF preview mask geometry"
        );
    }

    #[test]
    fn diagonal_smooth_px_changes_sdf_preview_mask_geometry() {
        let (sharp, sdf, signature) = diagonal_sdf_request();
        let mut smoothed = sharp.clone();
        smoothed.diagonal_smooth_px = 24;
        let smoothed = smoothed.sanitized();

        let sharp_tile = render_tile_with_sdf(&sharp, &TextureSet::default(), &sdf, 0, 0, 0);
        let smoothed_tile = render_tile_with_sdf(&smoothed, &TextureSet::default(), &sdf, 0, 0, 0);

        assert!(
            images_differ(&sharp_tile.mask, &smoothed_tile.mask),
            "diagonal_smooth_px should alter live SDF preview mask geometry"
        );
    }

    #[test]
    fn diagonal_smooth_px_widens_sdf_preview_diagonal_neck() {
        let (sharp, sdf, signature) = diagonal_sdf_request();
        let mut smoothed = sharp.clone();
        smoothed.diagonal_smooth_px = 24;
        let smoothed = smoothed.sanitized();

        let sharp_tile = render_tile_with_sdf(&sharp, &TextureSet::default(), &sdf, 0, 0, 0);
        let smoothed_tile = render_tile_with_sdf(&smoothed, &TextureSet::default(), &sdf, 0, 0, 0);

        assert!(
            occupied_pixels(&smoothed_tile.mask) > occupied_pixels(&sharp_tile.mask),
            "diagonal_smooth_px should widen, not merely perturb, the SDF diagonal throat"
        );
    }

    #[test]
    fn outer_corner_radius_changes_sdf_preview_mask_geometry() {
        let (sharp, sdf, signature) = single_cell_sdf_request();
        let mut rounded = sharp.clone();
        rounded.outer_corner_radius = 32;
        let rounded = rounded.sanitized();

        let sharp_tile = render_tile_with_sdf(&sharp, &TextureSet::default(), &sdf, 0, 64, 64);
        let rounded_tile = render_tile_with_sdf(&rounded, &TextureSet::default(), &sdf, 0, 64, 64);

        assert!(
            images_differ(&sharp_tile.mask, &rounded_tile.mask),
            "outer_corner_radius should affect live SDF preview corners"
        );
    }

    #[test]
    fn inner_corner_radius_changes_sdf_preview_concave_corners() {
        let mut sharp = flat_preview_request();
        sharp.map = MapData {
            width: 3,
            height: 3,
            cells: vec![1, 1, 1, 1, 0, 1, 1, 1, 1],
        };
        sharp.preview_mode = "mask".to_string();
        let mut rounded = sharp.clone();
        rounded.inner_corner_radius = 32;
        let sharp = sharp.sanitized();
        let rounded = rounded.sanitized();

        let sharp_preview = build_map_preview(&sharp, &TextureSet::default())
            .expect("sharp concave preview should render");
        let rounded_preview = build_map_preview(&rounded, &TextureSet::default())
            .expect("rounded concave preview should render");

        assert!(
            images_differ(&sharp_preview, &rounded_preview),
            "inner_corner_radius should affect live SDF preview concave corners"
        );
    }

    #[test]
    fn sdf_preview_albedo_blends_partial_coverage_against_base() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 2,
            height: 2,
            cells: vec![1, 0, 0, 1],
        };
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 0, 0);

        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 0, 0);

        assert_eq!(
            partial_mask_pixels_with_unblended_albedo(&tile),
            0,
            "partial-coverage pixels should be blended against base instead of keeping a hard zone color"
        );
    }

    #[test]
    fn sdf_preview_draws_visible_edge_band_on_the_top_lip() {
        let mut flat = flat_preview_request();
        flat.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        let mut edged = flat.clone();
        edged.rim_width = 8;
        edged.edge_debris = 0.0;
        let flat = flat.sanitized();
        let edged = edged.sanitized();
        let sdf = MapSdf::compute(&flat.map);
        let signature = signature_at(&flat.map, 1, 1);

        let flat_tile = render_tile_with_sdf(&flat, &TextureSet::default(), &sdf, 0, 64, 64);
        let edged_tile = render_tile_with_sdf(&edged, &TextureSet::default(), &sdf, 0, 64, 64);

        assert!(
            images_differ(&flat_tile.albedo, &edged_tile.albedo),
            "rim_width should create a visibly distinct albedo edge band in SDF preview"
        );
    }

    #[test]
    fn sdf_preview_normal_reads_neighboring_cells_at_tile_boundaries() {
        let (mut request, sdf, signature) = single_cell_sdf_request();
        request.preview_mode = "normal".to_string();
        let request = request.sanitized();
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);

        let expected = encode_global_normal(
            &request,
            &sdf,
            request.seed,
            127.0,
            96.0,
            request.normal_strength,
        );
        let actual = tile.normal.get_pixel(63, 32).0;

        for channel in 0..3 {
            assert!(
                (actual[channel] as i16 - expected[channel] as i16).abs() <= 1,
                "normal channel {channel} should use map-space height across the tile edge: actual={} expected={}",
                actual[channel],
                expected[channel]
            );
        }
    }

    #[test]
    fn corner_radii_activate_sdf_gradient_controls() {
        let (mut request, _sdf, _signature) = single_cell_sdf_request();
        request.corner_round_px = 0;
        request.diagonal_smooth_px = 0;
        request.contour_warp_px = 0.0;
        request.roughness = 0.0;
        request.corner_variation = 0.0;
        request.outer_corner_radius = 24;
        request.inner_corner_radius = 0;
        assert!(
            sdf_shape_controls_active(&request),
            "outer_corner_radius changes the SDF contour, so facade gradients must use the controlled SDF"
        );

        request.outer_corner_radius = 0;
        request.inner_corner_radius = 24;
        assert!(
            sdf_shape_controls_active(&request),
            "inner_corner_radius changes the SDF contour, so facade gradients must use the controlled SDF"
        );
    }

    #[test]
    fn controlled_sdf_distance_cache_matches_direct_samples_and_gradients() {
        let (mut request, sdf, _signature) = single_cell_sdf_request();
        request.corner_round_px = 24;
        request.outer_corner_radius = 24;
        request.contour_warp_px = 2.0;
        request.roughness = 20.0;
        let request = request.sanitized();
        let cache =
            GlobalSdfDistanceCache::new(&request, &sdf, request.seed, 64, 64, request.tile_size);
        let samples = [(80.0, 80.0), (96.25, 96.75), (127.0, 96.0)];

        for (world_x, world_y) in samples {
            let direct = controlled_sdf_distance_px(&request, &sdf, request.seed, world_x, world_y);
            let cached = cache.sample(world_x, world_y);
            assert!(
                (cached - direct).abs() < 0.25,
                "cached distance should stay close to direct SDF: ({world_x},{world_y}) direct={direct}, cached={cached}"
            );

            let (direct_x, direct_y) =
                controlled_sdf_gradient(&request, &sdf, request.seed, world_x, world_y);
            let (cached_x, cached_y) = cache.gradient(world_x, world_y);
            assert!(
                (cached_x - direct_x).abs() < 0.15 && (cached_y - direct_y).abs() < 0.15,
                "cached gradient should stay close to direct central differences: ({world_x},{world_y}) direct=({direct_x},{direct_y}), cached=({cached_x},{cached_y})"
            );
        }
    }

    #[test]
    fn diagonal_smooth_px_keeps_diagonal_center_from_becoming_flat_top() {
        let (mut request, sdf, _signature) = diagonal_sdf_request();
        request.diagonal_smooth_px = 24;
        let request = request.sanitized();

        let (height, zone) = sample_global_height(&request, &sdf, request.seed, 32.0, 32.0);

        assert_ne!(
            zone,
            SurfaceZone::Top,
            "diagonal smoothing should not turn the ambiguous cell center into a flat top plateau"
        );
        assert!(
            height < 1.0,
            "diagonal center should stay transitional, got height={height}"
        );
    }

    #[test]
    fn diagonal_smooth_px_does_not_leave_isolated_column_artifacts() {
        let (mut request, _sdf, _signature) = diagonal_sdf_request();
        request.preview_mode = "mask".to_string();
        request.diagonal_smooth_px = 24;
        let request = request.sanitized();

        let preview = build_map_preview(&request, &TextureSet::default())
            .expect("diagonal preview should render");

        assert_eq!(
            thin_occupied_columns(&preview),
            0,
            "diagonal smoothing should not leave one-pixel column artifacts at cell boundaries"
        );
    }

    #[test]
    fn edge_debris_only_uses_visible_edge_width_for_height_relief() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.rim_width = 0;
        request.edge_debris = 1.0;
        request.normal_detail_strength = 0.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let edge_width = preview_edge_width_px(&request);

        let mut sample = None;
        for y in 64..128 {
            for x in 64..128 {
                let world_x = x as f32 + 0.5;
                let world_y = y as f32 + 0.5;
                let signed_distance =
                    controlled_sdf_distance_px(&request, &sdf, request.seed, world_x, world_y);
                if signed_distance > 1.1 && signed_distance < edge_width - 0.25 {
                    sample = Some((world_x, world_y));
                    break;
                }
            }
            if sample.is_some() {
                break;
            }
        }
        let (world_x, world_y) = sample.expect("expected a sample inside the visible edge band");
        let (base_height, zone) =
            sample_global_height(&request, &sdf, request.seed, world_x, world_y);
        let render_height =
            sample_global_render_height(&request, &sdf, request.seed, world_x, world_y);

        assert_eq!(zone, SurfaceZone::Edge);
        assert!(
            (render_height - base_height).abs() > 0.001,
            "edge_debris should chip height across the visible edge band even when rim_width is zero"
        );
    }

    #[test]
    fn edge_debris_varies_visible_edge_albedo() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.rim_width = 8;
        request.edge_debris = 1.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);

        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);

        assert!(
            unique_edge_albedo_colors(&tile) > 3,
            "edge_debris should add spatial color variation to the visible edge band"
        );
    }

    #[test]
    fn edge_debris_width_scales_from_zero_without_a_step_change() {
        let mut request = flat_preview_request();
        request.rim_width = 0;
        request.edge_debris = 0.25;
        let request = request.sanitized();

        let expected = request.tile_size as f32 * 0.06 * request.edge_debris;

        assert!(
            (preview_edge_width_px(&request) - expected).abs() < 0.001,
            "edge_debris should grow the visible edge width gradually from zero"
        );
    }

    #[test]
    fn sdf_preview_mask_channels_preserve_supersampled_zone_coverage() {
        let (mut request, sdf, signature) = diagonal_sdf_request();
        request.shape_supersampling = 4;
        request.preview_mode = "mask".to_string();
        let request = request.sanitized();

        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 0, 0);

        assert!(
            tile.mask.pixels().any(|pixel| {
                pixel.0[3] > 0
                    && pixel.0[3] < 255
                    && pixel.0[..3]
                        .iter()
                        .any(|channel| *channel > 0 && *channel < 255)
            }),
            "partial SDF coverage should be visible in mask channels, not only alpha"
        );
    }

    #[test]
    fn contour_warp_px_changes_sdf_preview_mask_geometry() {
        let (flat, sdf, signature) = single_cell_sdf_request();
        let mut warped = flat.clone();
        warped.contour_warp_px = 10.0;
        let warped = warped.sanitized();

        let flat_tile = render_tile_with_sdf(&flat, &TextureSet::default(), &sdf, 0, 64, 64);
        let warped_tile = render_tile_with_sdf(&warped, &TextureSet::default(), &sdf, 0, 64, 64);

        assert!(
            images_differ(&flat_tile.mask, &warped_tile.mask),
            "contour_warp_px should alter live SDF preview mask geometry"
        );
    }

    #[test]
    fn roughness_changes_sdf_preview_mask_geometry() {
        let (flat, sdf, signature) = single_cell_sdf_request();
        let mut rough = flat.clone();
        rough.roughness = 100.0;
        let rough = rough.sanitized();

        let flat_tile = render_tile_with_sdf(&flat, &TextureSet::default(), &sdf, 0, 64, 64);
        let rough_tile = render_tile_with_sdf(&rough, &TextureSet::default(), &sdf, 0, 64, 64);

        assert!(
            images_differ(&flat_tile.mask, &rough_tile.mask),
            "roughness should alter live SDF preview mask geometry"
        );
    }

    #[test]
    fn automatic_variants_do_not_change_sdf_preview_geometry() {
        let (mut request, sdf, signature) = single_cell_sdf_request();
        request.contour_warp_px = 8.0;
        request.geometry_variance = 1.0;
        request.forced_variant = None;
        let request = request.sanitized();

        let variant_a = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);
        let variant_b = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 1, 64, 64);

        assert!(
            images_match(&variant_a.mask, &variant_b.mask),
            "auto variants may vary material, but SDF preview geometry must stay continuous across map tiles"
        );
    }

    #[test]
    fn sdf_preview_procedural_material_seed_is_stable_across_pixels() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![1, 1, 1, 1, 1, 1, 1, 1, 1],
        };
        request.materials.top.kind = "rough_stone".to_string();
        request.materials.top.scale = 1.0;
        request.preview_mode = "albedo".to_string();
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);
        let sample_x = 96.0;
        let sample_y = 96.0;
        let material_seed = request.seed.wrapping_add(17_371);
        let expected = sample_material_color(
            &request.materials.top,
            parse_hex_color(&request.colors.top),
            None,
            request.texture_scale,
            request.texture_color_overlay,
            request.tile_size,
            sample_x,
            sample_y,
            request
                .seed
                .wrapping_add(20_001)
                .wrapping_add(material_seed),
            1.0,
        );

        assert_eq!(
            tile.albedo.get_pixel(32, 32).0[..3],
            expected,
            "procedural materials should use a stable layer/variant seed; coordinates already provide per-pixel texture variation"
        );
    }

    #[test]
    fn front_only_sdf_preview_does_not_emit_side_facade_lobes() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.south_height = 16;
        request.side_height = 0;
        request.north_height = 0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);

        let (_height, zone) = sample_global_height(&request, &sdf, request.seed, 128.5, 96.0);

        assert_eq!(
            zone,
            SurfaceZone::Empty,
            "with side_height=0, east/west contour normals must not create protruding side facade"
        );
    }

    #[test]
    fn front_only_south_face_is_vertical_projection_without_side_lobes() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.south_height = 20;
        request.side_height = 0;
        request.north_height = 0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_variation = 0.0;
        request.shape_supersampling = 4;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);

        let mut unsupported_face_pixels = 0_usize;
        for y in 0..tile.mask.height() {
            for x in 0..tile.mask.width() {
                if tile.mask.get_pixel(x, y).0[1] == 0 {
                    continue;
                }
                let supported_by_top_above = (1..=request.south_height)
                    .any(|dy| y >= dy && tile.mask.get_pixel(x, y - dy).0[0] > 0);
                if !supported_by_top_above {
                    unsupported_face_pixels += 1;
                }
            }
        }

        assert_eq!(
            unsupported_face_pixels, 0,
            "front-only south facade must project vertically from top coverage without side lobes"
        );
    }

    #[test]
    fn side_height_with_zero_north_height_does_not_emit_north_back_horns() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.south_height = 20;
        request.side_height = 16;
        request.north_height = 0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 0);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 0);

        assert!(
            !tile.mask.pixels().any(|pixel| pixel.0[2] > 0),
            "side height must not create north/back facade horns when north_height is zero"
        );
    }

    #[test]
    fn side_height_preview_stays_within_configured_side_depth() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.south_height = 20;
        request.side_height = 16;
        request.north_height = 0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);

        let contour_x = (request.tile_size / 2) as i32;
        let mut max_side_depth = -1_i32;
        let mut side_pixels = 0_usize;
        for y in 0..tile.mask.height() {
            for x in contour_x as u32..tile.mask.width() {
                if tile.mask.get_pixel(x, y).0[1] > 0 {
                    side_pixels += 1;
                    max_side_depth = max_side_depth.max(x as i32 - contour_x);
                }
            }
        }

        assert!(side_pixels > 0, "side height should create a side facade");
        assert!(
            max_side_depth <= request.side_height as i32,
            "side facade depth should stay within side_height: got {max_side_depth}"
        );
    }

    #[test]
    fn global_preview_blends_top_and_face_boundary_pixels() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.colors.top = "#ffffff".to_string();
        request.colors.face = "#000000".to_string();
        request.materials.top = flat_material("#ffffff");
        request.materials.face = flat_material("#000000");
        request.south_height = 20;
        request.side_height = 16;
        request.north_height = 0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_variation = 0.0;
        request.bake_height_shading = false;
        request.shape_supersampling = 4;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);

        let boundary_pixel = tile
            .mask
            .enumerate_pixels()
            .find(|(_x, _y, mask)| {
                mask.0[0] > 0 && mask.0[1] > 0 && mask.0[2] == 0 && mask.0[3] == 255
            })
            .expect("expected a supersampled top/face boundary pixel");
        let albedo = tile.albedo.get_pixel(boundary_pixel.0, boundary_pixel.1).0;

        assert!(
            albedo[0] > 0 && albedo[0] < 255,
            "mixed top/face boundary pixels should render as blended preview color, got {albedo:?}"
        );
    }

    #[test]
    fn edge_color_tints_visible_preview_lip() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.colors.top = "#202020".to_string();
        request.colors.face = "#202020".to_string();
        request.colors.edge = "#ff0000".to_string();
        request.edge_color_strength = 1.0;
        request.rim_width = 8;
        request.edge_debris = 0.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 64);
        let mut edge_pixels = tile
            .albedo
            .pixels()
            .zip(tile.mask.pixels())
            .filter(|(_albedo, mask)| mask.0[0] > 0 && mask.0[1] > 0);

        let (albedo, _mask) = edge_pixels
            .next()
            .expect("expected at least one visible edge pixel");

        assert!(
            albedo.0[0] > albedo.0[1] * 2 && albedo.0[0] > albedo.0[2] * 2,
            "edge color should visibly tint the preview lip"
        );
    }

    #[test]
    fn sdf_preview_back_zone_does_not_multiply_flat_face_material() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.materials.face = flat_material("#806040");
        request.colors.face = "#ffffff".to_string();
        request.colors.back = "#204060".to_string();
        request.bake_height_shading = false;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.roughness = 0.0;
        request.contour_warp_px = 0.0;
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 0);
        let tile = render_tile_with_sdf(&request, &TextureSet::default(), &sdf, 0, 64, 0);

        let (albedo, _mask) = tile
            .albedo
            .pixels()
            .zip(tile.mask.pixels())
            .find(|(_albedo, mask)| mask.0[2] == 255 && mask.0[3] == 255)
            .expect("expected a fully covered north/back SDF preview pixel");

        assert_eq!(
            albedo.0[..3],
            [0x80, 0x60, 0x40],
            "back SDF zone should use the face material color directly, not multiply it by colors.back"
        );
    }

    #[test]
    fn side_facade_image_texture_wraps_by_wall_depth() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };
        request.south_height = 16;
        request.side_height = 16;
        request.north_height = 0;
        request.rim_width = 0;
        request.edge_debris = 0.0;
        request.texture_scale = 1.0;
        request.materials.face.source = "image".to_string();
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let signature = signature_at(&request.map, 1, 1);
        let texture = LoadedTexture {
            image: RgbaImage::from_fn(32, 32, |_x, y| {
                if y < 8 {
                    Rgba([40, 40, 40, 255])
                } else {
                    Rgba([220, 220, 220, 255])
                }
            }),
        };
        let textures = TextureSet {
            face: Some(texture),
            ..TextureSet::default()
        };
        let tile = render_tile_with_sdf(&request, &textures, &sdf, 0, 64, 64);

        let shallow = tile.albedo.get_pixel(34, 0).0;
        let deep = tile.albedo.get_pixel(46, 0).0;

        assert_ne!(
            shallow[..3],
            deep[..3],
            "side wall textures should turn with the facade and vary by wall depth, not fixed screen Y"
        );
    }

    #[test]
    fn sdf_facade_tangent_coordinates_keep_same_sign_on_opposite_sides() {
        let (request, sdf, _signature) = single_cell_sdf_request();
        let (west_along, _west_depth) = material_coords_for_zone(
            &request,
            SurfaceField::GlobalSdf(&sdf),
            None,
            request.seed,
            SurfaceZone::Face,
            63.0,
            96.0,
        );
        let (east_along, _east_depth) = material_coords_for_zone(
            &request,
            SurfaceField::GlobalSdf(&sdf),
            None,
            request.seed,
            SurfaceZone::Face,
            129.0,
            96.0,
        );

        assert!(
            west_along.signum() == east_along.signum(),
            "facade material projection should not mirror across opposite SDF contours: west={west_along}, east={east_along}"
        );
    }

    #[test]
    fn sdf_facade_material_coordinates_are_continuous_across_cell_boundaries() {
        let mut request = flat_preview_request();
        request.map = MapData {
            width: 4,
            height: 2,
            cells: vec![1, 1, 1, 1, 0, 0, 0, 0],
        };
        let request = request.sanitized();
        let sdf = MapSdf::compute(&request.map);
        let (left_along, _left_depth) = material_coords_for_zone(
            &request,
            SurfaceField::GlobalSdf(&sdf),
            None,
            request.seed,
            SurfaceZone::Face,
            127.5,
            80.0,
        );
        let (right_along, _right_depth) = material_coords_for_zone(
            &request,
            SurfaceField::GlobalSdf(&sdf),
            None,
            request.seed,
            SurfaceZone::Face,
            128.5,
            80.0,
        );

        assert!(
            (right_along - left_along).abs() < 3.0,
            "facade material coordinates should not jump at cell boundaries: left={left_along}, right={right_along}"
        );
    }

    #[test]
    fn lit_preview_uses_dominant_mask_zone_for_anti_aliased_pixels() {
        let albedo = RgbaImage::from_pixel(1, 1, Rgba([200, 200, 200, 255]));
        let normal = RgbaImage::from_pixel(1, 1, Rgba([128, 128, 255, 255]));
        let height = RgbaImage::from_pixel(1, 1, Rgba([255, 255, 255, 255]));
        let top_mask = RgbaImage::from_pixel(1, 1, Rgba([255, 0, 0, 255]));
        let fringe_mask = RgbaImage::from_pixel(1, 1, Rgba([255, 16, 0, 255]));

        let top_lit = build_lit_preview_image(
            &TileBuffers {
                albedo: albedo.clone(),
                mask: top_mask,
                height: height.clone(),
                normal: normal.clone(),
            },
            234.0,
        );
        let fringe_lit = build_lit_preview_image(
            &TileBuffers {
                albedo,
                mask: fringe_mask,
                height,
                normal,
            },
            234.0,
        );

        assert_eq!(
            top_lit.get_pixel(0, 0).0[..3],
            fringe_lit.get_pixel(0, 0).0[..3],
            "small anti-aliased face coverage should not reclassify a dominant top pixel as a darker edge"
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

        let (height, zone) =
            sample_height(&request, &signature, request.seed, 45.0, 45.0, 45.0, 45.0);

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
        let tile = render_mask_tile(&request, &signature, 0, 0, 0);

        assert_eq!(
            tile.get_pixel(63, 63).0[3],
            0,
            "rounded face geometry should clear occupancy in the old square corner"
        );
    }

    #[test]
    fn shape_supersampling_antialiases_curved_mask_edge() {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 0.0;
        request.outer_corner_radius = 12;
        request.shape_supersampling = 4;
        let request = request.sanitized();
        let signature = Signature::create(true, false, false, false, false, false, true, true);

        let tile = render_mask_tile(&request, &signature, 0, 0, 0);
        let has_partial_alpha = (48..64).any(|y| {
            (48..64).any(|x| {
                let alpha = tile.get_pixel(x, y).0[3];
                alpha > 0 && alpha < 255
            })
        });

        assert!(
            has_partial_alpha,
            "supersampling should write partial occupancy somewhere along the curved edge"
        );
    }

    #[test]
    fn marching_square_diagonal_case_antialiases_contour() {
        let mut request = default_request();
        request.tile_size = 64;
        request.roughness = 0.0;
        request.contour_relax = 0.0;
        request.contour_warp_px = 0.0;
        request.corner_variation = 0.0;
        request.shape_supersampling = 4;
        let request = request.sanitized();
        let signature = Signature::from_marching_mask(0b0101);

        let tile = render_mask_tile(&request, &signature, 0, 0, 0);
        let has_partial_alpha = (8..56).any(|y| {
            (8..56).any(|x| {
                let alpha = tile.get_pixel(x, y).0[3];
                alpha > 0 && alpha < 255
            })
        });

        assert!(
            has_partial_alpha,
            "true marching-squares diagonal case should produce an anti-aliased curved contour"
        );
    }

    #[test]
    fn corner_round_px_changes_active_marching_square_mask() {
        let mut sharp = default_request();
        sharp.tile_size = 64;
        sharp.roughness = 0.0;
        sharp.contour_relax = 0.0;
        sharp.contour_warp_px = 0.0;
        sharp.corner_variation = 0.0;
        sharp.corner_round_px = 0;
        sharp.shape_supersampling = 4;
        let sharp = sharp.sanitized();

        let mut rounded = sharp.clone();
        rounded.corner_round_px = 20;
        let rounded = rounded.sanitized();

        let signature = Signature::from_marching_mask(0b0001);
        let sharp_tile = render_mask_tile(&sharp, &signature, 0, 0, 0);
        let rounded_tile = render_mask_tile(&rounded, &signature, 0, 0, 0);

        assert!(
            images_differ(&sharp_tile, &rounded_tile),
            "corner_round_px should affect current ms_* mask geometry, not only legacy notch cases"
        );
    }

    #[test]
    fn diagonal_smooth_px_changes_diagonal_marching_square_mask() {
        let mut sharp = default_request();
        sharp.tile_size = 64;
        sharp.roughness = 0.0;
        sharp.contour_relax = 0.0;
        sharp.contour_warp_px = 0.0;
        sharp.corner_variation = 0.0;
        sharp.corner_round_px = 0;
        sharp.diagonal_smooth_px = 0;
        sharp.shape_supersampling = 4;
        let sharp = sharp.sanitized();

        let mut smoothed = sharp.clone();
        smoothed.diagonal_smooth_px = 16;
        let smoothed = smoothed.sanitized();

        let signature = Signature::from_marching_mask(0b0101);
        let sharp_tile = render_mask_tile(&sharp, &signature, 0, 0, 0);
        let smoothed_tile = render_mask_tile(&smoothed, &signature, 0, 0, 0);

        assert!(
            images_differ(&sharp_tile, &smoothed_tile),
            "diagonal_smooth_px should alter diagonal ms_* masks"
        );
    }

    #[test]
    fn rim_detail_and_micro_relief_add_height_variation_for_normals() {
        let mut flat = default_request();
        flat.tile_size = 64;
        flat.south_height = 16;
        flat.north_height = 8;
        flat.side_height = 16;
        flat.roughness = 0.0;
        flat.rim_width = 0;
        flat.edge_debris = 0.0;
        flat.normal_detail_strength = 0.0;
        let flat = flat.sanitized();

        let mut detailed = flat.clone();
        detailed.rim_width = 8;
        detailed.edge_debris = 1.0;
        detailed.normal_detail_strength = 2.0;
        let detailed = detailed.sanitized();

        let signature = Signature::create(true, true, true, true, false, true, true, true);
        let flat_tile = render_tile(&flat, &TextureSet::default(), &signature, 0, 0, 0);
        let detailed_tile = render_tile(&detailed, &TextureSet::default(), &signature, 0, 0, 0);

        assert!(
            images_differ(&flat_tile.height, &detailed_tile.height),
            "rim/detail relief should change exported height near exposed cliff edges"
        );
        assert!(
            images_differ(&flat_tile.normal, &detailed_tile.normal),
            "height relief should produce more varied normals for dynamic lighting"
        );
    }

    #[test]
    fn geometry_variants_change_shape_height() {
        let mut request = default_request();
        request.tile_size = 64;
        request.south_height = 16;
        request.north_height = 8;
        request.side_height = 16;
        request.roughness = 40.0;
        request.geometry_variance = 1.0;
        request.normal_detail_strength = 0.0;
        request.contour_warp_px = 8.0;
        let request = request.sanitized();
        let signature = Signature::from_marching_mask(0b0011);

        let variant_a = render_tile(&request, &TextureSet::default(), &signature, 0, 0, 0);
        let variant_b = render_tile(&request, &TextureSet::default(), &signature, 1, 0, 0);

        assert!(
            images_differ(&variant_a.height, &variant_b.height),
            "geometry variants should change the baked shape height, not only material color"
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

        let (height, zone) =
            sample_height(&request, &signature, request.seed, 51.0, 13.0, 51.0, 13.0);

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

    #[test]
    fn full_export_does_not_recompute_map_preview() {
        let output_dir = test_output_dir("full_export_without_preview");
        let mut request = default_request();
        request.asset_name = "plains_ground".to_string();
        request.export_mode = ExportMode::BaseVariantsOnly;
        request.tile_size = 32;
        request.variants = 2;
        let request = request.sanitized();

        let manifest = run_request(RenderMode::Full, request, &output_dir)
            .expect("full export should render without preview");

        assert!(manifest.files.preview_png.is_empty());
        assert!(!output_dir.join("plains_ground_preview.png").exists());
        assert!(manifest.files.atlas_albedo_png.is_some());
    }
}

fn apply_material_tint(
    base: MaterialBaseSample,
    tint: [u8; 3],
    texture_color_overlay: bool,
    brightness: f32,
) -> [u8; 3] {
    let tint_factor = if base.is_image_source {
        if texture_color_overlay {
            tint
        } else {
            [255, 255, 255]
        }
    } else {
        [255, 255, 255]
    };
    [
        ((base.rgb[0] as f32 * (tint_factor[0] as f32 / 255.0) * brightness).round() as i32)
            .clamp(0, 255) as u8,
        ((base.rgb[1] as f32 * (tint_factor[1] as f32 / 255.0) * brightness).round() as i32)
            .clamp(0, 255) as u8,
        ((base.rgb[2] as f32 * (tint_factor[2] as f32 / 255.0) * brightness).round() as i32)
            .clamp(0, 255) as u8,
    ]
}

fn sample_material_color(
    material: &MaterialConfig,
    tint: [u8; 3],
    texture: Option<&LoadedTexture>,
    texture_scale: f32,
    texture_color_overlay: bool,
    tile_size: u32,
    x: f32,
    y: f32,
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
    let scale = 1.0 / material.scale.max(0.2);
    let px = x * scale;
    let py = y * scale;
    let period = (tile_period * EDGE_NOISE_PERIOD_TILES * scale).max(1.0);
    let feature_period = (tile_period * scale).max(1.0);
    let seed = seed.wrapping_add(material.seed.wrapping_mul(193));
    let broad = fbm_tiled(
        px * 0.045,
        py * 0.045,
        period * 0.045,
        period * 0.045,
        4,
        seed,
    );
    let fine = fbm_tiled(
        px * 0.18 + 37.0,
        py * 0.18 + 19.0,
        period * 0.18,
        period * 0.18,
        3,
        seed.wrapping_add(97),
    );
    let speck = hash2d(
        (px * 1.7).floor() as i32,
        (py * 1.7).floor() as i32,
        seed.wrapping_add(307),
    );
    let (mut value, crack, wear_mask, highlight_mask) = match material.kind.as_str() {
        "stone_bricks" => stone_brick_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "stratified_rock" => stratified_rock_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "cracked_earth" => cracked_earth_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "worn_metal" => worn_metal_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "wood_planks" => wood_plank_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "packed_dirt" => packed_dirt_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "concrete" => concrete_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "ice_frost" => ice_frost_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "ash_burnt_ground" => ash_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "snow" => snow_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "sand" => sand_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "moss" => moss_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "gravel" => gravel_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "rusty_metal" => rusty_metal_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "concrete_floor" => concrete_floor_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        "ribbed_steel" => ribbed_steel_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
        _ => rough_stone_layers(
            material,
            seed,
            px,
            py,
            period,
            feature_period,
            speck,
            broad,
            fine,
        ),
    };

    value += (speck - 0.5) * material.grain * 0.18;
    value = apply_value_contrast(value, material.contrast);
    let mut color = mix_color(color_a, color_b, value);
    color = mix_color(color, highlight, highlight_mask.clamp(0.0, 1.0));

    let darkening = crack * (0.28 + material.edge_darkening * 0.55)
        + wear_mask * material.edge_darkening * 0.18;
    color = scale_color(color, 1.0 - darkening.clamp(0.0, 0.82));
    color = mix_color(
        color,
        highlight,
        (wear_mask * material.wear * 0.22).clamp(0.0, 0.35),
    );
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
    let offset = if row.rem_euclid(2) == 0 {
        0.0
    } else {
        brick_w * 0.5
    };
    let bx = positive_mod(px + offset, brick_w);
    let by = positive_mod(py, brick_h);
    let edge_distance = bx.min(brick_w - bx).min(by.min(brick_h - by));
    let mortar = line_mask(edge_distance, 0.8 + material.crack_amount * 1.8);
    let cell_x = ((px + offset) / brick_w).floor() as i32;
    let cell_y = (py / brick_h).floor() as i32;
    let cell = hash2d(cell_x, cell_y, seed.wrapping_add(701));
    let chip = (hash2d(
        (px * 0.65) as i32,
        (py * 0.65) as i32,
        seed.wrapping_add(709),
    ) - 0.5)
        * material.wear;
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
    let warp_x = (fbm_tiled(
        px * 0.035,
        py * 0.035,
        period * 0.035,
        period * 0.035,
        3,
        seed,
    ) - 0.5)
        * 7.0;
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
    let hairline = clamp(
        (0.16 - (fine - 0.48).abs()).max(0.0) * material.crack_amount * 3.0,
        0.0,
        1.0,
    );
    let crack = clamp(main_crack + hairline * 0.45, 0.0, 1.0);
    let value = 0.44 + broad * 0.25 + fine * 0.16;
    (
        value,
        crack,
        material.wear * (1.0 - broad),
        0.04 + fine * 0.08,
    )
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
    let crack = clamp(
        (0.34 - fine).max(0.0) * material.crack_amount * 1.8,
        0.0,
        1.0,
    );
    let value = 0.36 + broad * 0.34 + fine * 0.18 + speck * material.grain * 0.16;
    (value, crack, material.wear * speck, fine * 0.12)
}

fn stratified_rock_layers(
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
    let band_height = (feature_period * 0.105).max(3.0);
    let warp = (fbm_tiled(
        px * 0.035,
        py * 0.045,
        period * 0.035,
        period * 0.045,
        3,
        seed.wrapping_add(607),
    ) - 0.5)
        * band_height
        * 1.8;
    let tilted_y = py + px * 0.10 + warp;
    let band_pos = positive_mod(tilted_y, band_height);
    let band_edge = line_mask(
        band_pos.min(band_height - band_pos),
        0.55 + material.crack_amount,
    );
    let shelf = ((tilted_y / band_height).floor() as i32).rem_euclid(5) as f32 / 5.0;
    let vertical_crack = clamp(
        (0.13
            - (fbm_tiled(
                px * 0.095 + 31.0,
                py * 0.028,
                period * 0.095,
                period * 0.028,
                2,
                seed.wrapping_add(613),
            ) - 0.48)
                .abs())
            * material.crack_amount
            * 5.0,
        0.0,
        1.0,
    );
    let chip = clamp((speck - 0.73) * 3.8, 0.0, 1.0) * material.wear;
    let crack = clamp(
        band_edge * 0.75 + vertical_crack * 0.65 + chip * 0.35,
        0.0,
        1.0,
    );
    let value = 0.34 + broad * 0.22 + fine * 0.12 + shelf * 0.16 + speck * material.grain * 0.10;
    let highlight = clamp((1.0 - band_edge) * fine * 0.10 + chip * 0.16, 0.0, 1.0);
    (value, crack, chip + vertical_crack * 0.35, highlight)
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
    (
        value,
        scratches * material.crack_amount,
        scratches,
        scratches * 0.28,
    )
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
    let grain = fbm_tiled(
        px * 0.03,
        py * 0.34,
        period * 0.03,
        period * 0.34,
        4,
        seed.wrapping_add(41),
    );
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
    let crack = clamp(
        (0.28 - fine).max(0.0) * material.crack_amount * 1.6,
        0.0,
        1.0,
    );
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
    let crack_line = fbm_tiled(
        px * 0.08,
        py * 0.08,
        period * 0.08,
        period * 0.08,
        2,
        seed.wrapping_add(89),
    );
    let crack = clamp(
        (0.18 - (crack_line - 0.5).abs()).max(0.0) * material.crack_amount * 4.0,
        0.0,
        1.0,
    );
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
    let frost = fbm_tiled(
        px * 0.12 + 9.0,
        py * 0.12,
        period * 0.12,
        period * 0.12,
        4,
        seed.wrapping_add(103),
    );
    let vein = clamp(
        (0.10 - (frost - 0.52).abs()).max(0.0) * material.crack_amount * 5.0,
        0.0,
        1.0,
    );
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
    let crack = clamp(
        (0.25 - fine).max(0.0) * material.crack_amount * 1.8,
        0.0,
        1.0,
    );
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
    let crack = clamp(
        (0.18 - fine).max(0.0) * material.crack_amount * 0.8,
        0.0,
        1.0,
    );
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
    let crack = clamp(
        (0.20 - fine).max(0.0) * material.crack_amount * 0.6,
        0.0,
        1.0,
    );
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
    let value = 0.30
        + broad * 0.16
        + fine * 0.08
        + pebble_var * 0.30
        + (speck - 0.5) * material.grain * 0.18;
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

fn blend_coverage_color(
    top: [u8; 3],
    top_weight: f32,
    face: [u8; 3],
    face_weight: f32,
    back: [u8; 3],
    back_weight: f32,
) -> [u8; 3] {
    let top_weight = top_weight.clamp(0.0, 1.0);
    let face_weight = face_weight.clamp(0.0, 1.0);
    let back_weight = back_weight.clamp(0.0, 1.0);
    let total = top_weight + face_weight + back_weight;
    if total <= 0.0001 {
        return top;
    }

    [
        ((top[0] as f32 * top_weight + face[0] as f32 * face_weight + back[0] as f32 * back_weight)
            / total)
            .round()
            .clamp(0.0, 255.0) as u8,
        ((top[1] as f32 * top_weight + face[1] as f32 * face_weight + back[1] as f32 * back_weight)
            / total)
            .round()
            .clamp(0.0, 255.0) as u8,
        ((top[2] as f32 * top_weight + face[2] as f32 * face_weight + back[2] as f32 * back_weight)
            / total)
            .round()
            .clamp(0.0, 255.0) as u8,
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
    try_parse_hex_color(value).unwrap_or(fallback)
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
        SurfaceZone::Edge => 0.93 + height * 0.08,
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
                    total +=
                        sample_height_value_clamped(size, heights, x as i32 + ox, y as i32 + oy);
                }
            }
            out[(y * size + x) as usize] = total / 9.0;
        }
    }
    out
}

fn encode_normal(size: u32, heights: &[f32], x: u32, y: u32, strength: f32) -> [u8; 3] {
    let at =
        |ox: i32, oy: i32| sample_height_value_clamped(size, heights, x as i32 + ox, y as i32 + oy);
    let (dx, dy) = sobel_gradient_from_samples(at);
    encode_normal_from_gradient(dx, dy, strength)
}

fn sobel_gradient_from_samples<F>(at: F) -> (f32, f32)
where
    F: Fn(i32, i32) -> f32,
{
    let dx =
        (at(1, -1) + 2.0 * at(1, 0) + at(1, 1) - at(-1, -1) - 2.0 * at(-1, 0) - at(-1, 1)) * 0.25;
    let dy =
        (at(-1, 1) + 2.0 * at(0, 1) + at(1, 1) - at(-1, -1) - 2.0 * at(0, -1) - at(1, -1)) * 0.25;
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

fn blit_exact_band(
    band: &mut [u8],
    target_width: usize,
    tile_size: usize,
    dx: usize,
    source: &RgbaImage,
) {
    let source_width = source.width() as usize;
    let source_height = source.height() as usize;
    debug_assert_eq!(source_width, tile_size);
    debug_assert_eq!(source_height, tile_size);
    let row_bytes = source_width * 4;
    let target_row_bytes = target_width * 4;
    let dx_offset = dx * 4;
    let src: &[u8] = source;

    for y in 0..source_height {
        let src_offset = y * row_bytes;
        let dst_offset = y * target_row_bytes + dx_offset;
        band[dst_offset..dst_offset + row_bytes]
            .copy_from_slice(&src[src_offset..src_offset + row_bytes]);
    }
}

fn parse_hex_color(value: &str) -> [u8; 3] {
    try_parse_hex_color(value).unwrap_or([255, 255, 255])
}

fn try_parse_hex_color(value: &str) -> Option<[u8; 3]> {
    let trimmed = value.trim().trim_start_matches('#');
    if trimmed.len() != 6 {
        return None;
    }
    if !trimmed.as_bytes().iter().all(u8::is_ascii_hexdigit) {
        return None;
    }

    let parse = |slice: std::ops::Range<usize>| u8::from_str_radix(&trimmed[slice], 16).ok();
    Some([parse(0..2)?, parse(2..4)?, parse(4..6)?])
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
