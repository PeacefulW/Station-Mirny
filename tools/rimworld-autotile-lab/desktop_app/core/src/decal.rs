use std::fs;
use std::path::Path;
use std::time::Instant;

use anyhow::{Context, Result};
use image::{imageops, Rgba, RgbaImage};
use serde::Serialize;

use crate::model::{AppRequest, DecalCellRequest};
use crate::noise::{clamp, hash2d, value_noise};

const DECAL_COLUMNS: u32 = 4;
const DECAL_ROWS: u32 = 4;
const DECAL_CELL_COUNT: usize = (DECAL_COLUMNS * DECAL_ROWS) as usize;

#[derive(Debug, Clone, Serialize)]
pub struct DecalOutputManifest {
    pub mode: String,
    pub asset_name: String,
    pub cell_size: u32,
    pub columns: u32,
    pub rows: u32,
    pub cell_count: usize,
    pub files: DecalGeneratedFiles,
    pub warnings: Vec<String>,
    pub build_ms: u128,
}

#[derive(Debug, Clone, Serialize)]
pub struct DecalGeneratedFiles {
    pub decal_atlas_png: String,
    pub decal_metadata_json: String,
}

#[derive(Debug, Clone, Serialize)]
struct DecalMetadata {
    tool: &'static str,
    version: u32,
    asset_name: String,
    columns: u32,
    rows: u32,
    cell_size: u32,
    outline_enable: bool,
    cells: Vec<DecalMetadataCell>,
}

#[derive(Debug, Clone, Serialize)]
struct DecalMetadataCell {
    index: usize,
    grid_x: u32,
    grid_y: u32,
    size_class: u32,
    pivot: String,
    source_recipe_summary: SourceRecipeSummary,
}

#[derive(Debug, Clone, Serialize)]
struct SourceRecipeSummary {
    source: String,
    kind: String,
    seed: u32,
    color: String,
    image_path: Option<String>,
}

pub fn run_request(request: &AppRequest, output_dir: &Path) -> Result<DecalOutputManifest> {
    let started = Instant::now();
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create output dir: {}", output_dir.display()))?;

    let atlas_path = output_dir.join(format!("{}_decal_atlas.png", request.asset_name));
    let metadata_path = output_dir.join(format!("{}_decal_metadata.json", request.asset_name));
    let cell_size = request.decal_atlas.cell_size;
    let mut warnings = Vec::new();
    let mut atlas = RgbaImage::from_pixel(
        cell_size * DECAL_COLUMNS,
        cell_size * DECAL_ROWS,
        Rgba([0, 0, 0, 0]),
    );
    let mut metadata_cells = Vec::with_capacity(DECAL_CELL_COUNT);

    for index in 0..DECAL_CELL_COUNT {
        let cell = &request.decal_atlas.cells[index];
        let sprite = render_cell(cell, request.decal_atlas.outline_enable, &mut warnings);
        let grid_x = index as u32 % DECAL_COLUMNS;
        let grid_y = index as u32 / DECAL_COLUMNS;
        let offset_x = grid_x * cell_size + (cell_size - cell.size_class) / 2;
        let offset_y = grid_y * cell_size + (cell_size - cell.size_class) / 2;
        blit(&mut atlas, &sprite, offset_x, offset_y);
        metadata_cells.push(DecalMetadataCell {
            index,
            grid_x,
            grid_y,
            size_class: cell.size_class,
            pivot: cell.pivot.clone(),
            source_recipe_summary: SourceRecipeSummary {
                source: cell.source.clone(),
                kind: cell.kind.clone(),
                seed: cell.seed,
                color: cell.color.clone(),
                image_path: cell.image_path.clone(),
            },
        });
    }

    atlas
        .save(&atlas_path)
        .with_context(|| format!("failed to write decal atlas: {}", atlas_path.display()))?;

    let metadata = DecalMetadata {
        tool: "Cliff Forge Desktop",
        version: 1,
        asset_name: request.asset_name.clone(),
        columns: DECAL_COLUMNS,
        rows: DECAL_ROWS,
        cell_size,
        outline_enable: request.decal_atlas.outline_enable,
        cells: metadata_cells,
    };
    fs::write(&metadata_path, serde_json::to_vec_pretty(&metadata)?)
        .with_context(|| format!("failed to write decal metadata: {}", metadata_path.display()))?;

    Ok(DecalOutputManifest {
        mode: "decals".to_string(),
        asset_name: request.asset_name.clone(),
        cell_size,
        columns: DECAL_COLUMNS,
        rows: DECAL_ROWS,
        cell_count: DECAL_CELL_COUNT,
        files: DecalGeneratedFiles {
            decal_atlas_png: atlas_path.to_string_lossy().to_string(),
            decal_metadata_json: metadata_path.to_string_lossy().to_string(),
        },
        warnings,
        build_ms: started.elapsed().as_millis(),
    })
}

fn render_cell(cell: &DecalCellRequest, outline_enable: bool, warnings: &mut Vec<String>) -> RgbaImage {
    let mut sprite = if cell.source == "image" {
        render_image_cell(cell, warnings).unwrap_or_else(|| render_procedural_cell(cell))
    } else if cell.source == "color" {
        render_flat_cell(cell)
    } else {
        render_procedural_cell(cell)
    };

    if outline_enable {
        sprite = apply_outline(&sprite);
    }

    sprite
}

fn render_image_cell(cell: &DecalCellRequest, warnings: &mut Vec<String>) -> Option<RgbaImage> {
    let Some(path) = &cell.image_path else {
        warnings.push(format!(
            "Decal image source without image_path; cell with seed {} used procedural fallback.",
            cell.seed
        ));
        return None;
    };

    match image::open(path) {
        Ok(image) => {
            let source = image.to_rgba8();
            Some(imageops::resize(
                &source,
                cell.size_class,
                cell.size_class,
                imageops::FilterType::Nearest,
            ))
        }
        Err(error) => {
            warnings.push(format!(
                "Failed to load decal image '{}': {error}; used procedural fallback.",
                path
            ));
            None
        }
    }
}

fn render_flat_cell(cell: &DecalCellRequest) -> RgbaImage {
    let color = parse_hex_color(&cell.color);
    let mut sprite = RgbaImage::from_pixel(cell.size_class, cell.size_class, Rgba([0, 0, 0, 0]));
    for y in 0..cell.size_class {
        for x in 0..cell.size_class {
            let alpha = decal_alpha(x, y, cell.size_class, cell.seed);
            if alpha > 0 {
                sprite.put_pixel(x, y, Rgba([color[0], color[1], color[2], alpha]));
            }
        }
    }
    sprite
}

fn render_procedural_cell(cell: &DecalCellRequest) -> RgbaImage {
    let base = parse_hex_color(&cell.color);
    let mut sprite = RgbaImage::from_pixel(cell.size_class, cell.size_class, Rgba([0, 0, 0, 0]));

    for y in 0..cell.size_class {
        for x in 0..cell.size_class {
            let alpha = decal_alpha(x, y, cell.size_class, cell.seed);
            if alpha == 0 {
                continue;
            }

            let nx = x as f32 / cell.size_class as f32;
            let ny = y as f32 / cell.size_class as f32;
            let grain = value_noise(nx * 12.0, ny * 12.0, cell.seed);
            let detail = hash2d(x as i32, y as i32, cell.seed.wrapping_add(31));
            let mut shade = 0.75 + grain * 0.35 + (detail - 0.5) * 0.12;

            if cell.kind == "cracked_earth" {
                let crack = crack_mask(x, y, cell.size_class, cell.seed);
                shade -= crack * 0.35;
            } else if cell.kind == "ribbed_steel" {
                let rib = if (x + y + cell.seed % 7) % 7 < 2 { 0.18 } else { -0.05 };
                shade += rib;
            } else if cell.kind == "gravel" {
                shade += (hash2d((x / 3) as i32, (y / 3) as i32, cell.seed) - 0.5) * 0.35;
            }

            sprite.put_pixel(x, y, shaded(base, shade, alpha));
        }
    }

    sprite
}

fn decal_alpha(x: u32, y: u32, size: u32, seed: u32) -> u8 {
    let half = size as f32 * 0.5;
    let nx = (x as f32 + 0.5 - half) / half;
    let ny = (y as f32 + 0.5 - half) / half;
    let radius = (nx * nx * 1.05 + ny * ny * 0.82).sqrt();
    let edge = 0.78 + (value_noise(x as f32 * 0.21, y as f32 * 0.21, seed) - 0.5) * 0.28;
    let fade = clamp((edge - radius) / 0.12, 0.0, 1.0);
    (fade * 230.0).round() as u8
}

fn crack_mask(x: u32, y: u32, size: u32, seed: u32) -> f32 {
    let band_a = ((x as i32 - y as i32 + seed as i32 % 17).abs() % 19) as u32;
    let band_b = ((x + y + seed % 23) % (size / 2).max(7)) as u32;
    if band_a <= 1 || band_b == 0 {
        1.0
    } else {
        0.0
    }
}

fn shaded(color: [u8; 3], shade: f32, alpha: u8) -> Rgba<u8> {
    Rgba([
        (color[0] as f32 * shade.clamp(0.35, 1.35)).round().clamp(0.0, 255.0) as u8,
        (color[1] as f32 * shade.clamp(0.35, 1.35)).round().clamp(0.0, 255.0) as u8,
        (color[2] as f32 * shade.clamp(0.35, 1.35)).round().clamp(0.0, 255.0) as u8,
        alpha,
    ])
}

fn parse_hex_color(value: &str) -> [u8; 3] {
    let hex = value.trim().trim_start_matches('#');
    if hex.len() != 6 {
        return [127, 114, 95];
    }

    let parse = |start: usize| u8::from_str_radix(&hex[start..start + 2], 16).ok();
    match (parse(0), parse(2), parse(4)) {
        (Some(r), Some(g), Some(b)) => [r, g, b],
        _ => [127, 114, 95],
    }
}

fn apply_outline(sprite: &RgbaImage) -> RgbaImage {
    let mut outlined = sprite.clone();
    let width = sprite.width();
    let height = sprite.height();

    for y in 0..height {
        for x in 0..width {
            if sprite.get_pixel(x, y).0[3] > 0 {
                continue;
            }
            if has_opaque_neighbor(sprite, x, y) {
                outlined.put_pixel(x, y, Rgba([18, 14, 10, 150]));
            }
        }
    }

    outlined
}

fn has_opaque_neighbor(sprite: &RgbaImage, x: u32, y: u32) -> bool {
    let min_x = x.saturating_sub(1);
    let min_y = y.saturating_sub(1);
    let max_x = (x + 1).min(sprite.width().saturating_sub(1));
    let max_y = (y + 1).min(sprite.height().saturating_sub(1));

    for yy in min_y..=max_y {
        for xx in min_x..=max_x {
            if sprite.get_pixel(xx, yy).0[3] > 160 {
                return true;
            }
        }
    }

    false
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

    use image::{Rgba, RgbaImage};

    use crate::model::default_request;

    use super::*;

    fn test_output_dir(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be after unix epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("cliff_forge_decal_{name}_{nonce}"));
        test_fs::create_dir_all(&dir).expect("test output dir should be creatable");
        dir
    }

    #[test]
    fn decal_export_writes_16_cell_atlas_and_metadata() {
        let output_dir = test_output_dir("basic");
        let mut request = default_request();
        request.asset_name = "plains_debris".to_string();
        request.decal_atlas.cell_size = 32;
        request.decal_atlas.cells[0].size_class = 16;
        request.decal_atlas.cells[1].size_class = 32;
        request.decal_atlas.cells[1].pivot = "bottom_center".to_string();
        let request = request.sanitized();

        let manifest = run_request(&request, &output_dir).expect("decal export should render");
        let atlas = image::open(&manifest.files.decal_atlas_png)
            .expect("decal atlas should be readable")
            .to_rgba8();
        let metadata: serde_json::Value = serde_json::from_slice(
            &test_fs::read(&manifest.files.decal_metadata_json).expect("metadata should be readable"),
        )
        .expect("metadata should be json");

        assert_eq!(atlas.dimensions(), (128, 128));
        assert_eq!(metadata["cells"].as_array().expect("cells should be array").len(), 16);
        assert_eq!(metadata["cells"][0]["size_class"], 16);
        assert_eq!(metadata["cells"][1]["pivot"], "bottom_center");
        assert!(output_dir.join("plains_debris_decal_atlas.png").exists());
        assert!(output_dir.join("plains_debris_decal_metadata.json").exists());
    }

    #[test]
    fn decal_export_records_procedural_image_and_color_sources() {
        let output_dir = test_output_dir("sources");
        let image_path = output_dir.join("source.png");
        RgbaImage::from_fn(8, 8, |_, _| Rgba([20, 200, 120, 255]))
            .save(&image_path)
            .expect("source image should be writable");

        let mut request = default_request();
        request.asset_name = "plains_debris".to_string();
        request.decal_atlas.cell_size = 32;
        request.decal_atlas.cells[0].source = "procedural".to_string();
        request.decal_atlas.cells[0].kind = "rough_stone".to_string();
        request.decal_atlas.cells[1].source = "color".to_string();
        request.decal_atlas.cells[1].color = "#30a060".to_string();
        request.decal_atlas.cells[2].source = "image".to_string();
        request.decal_atlas.cells[2].image_path = Some(image_path.to_string_lossy().to_string());
        let request = request.sanitized();

        let manifest = run_request(&request, &output_dir).expect("decal export should render");
        let metadata: serde_json::Value = serde_json::from_slice(
            &test_fs::read(&manifest.files.decal_metadata_json).expect("metadata should be readable"),
        )
        .expect("metadata should be json");

        assert_eq!(metadata["cells"][0]["source_recipe_summary"]["source"], "procedural");
        assert_eq!(metadata["cells"][0]["source_recipe_summary"]["kind"], "rough_stone");
        assert_eq!(metadata["cells"][1]["source_recipe_summary"]["source"], "color");
        assert_eq!(metadata["cells"][2]["source_recipe_summary"]["source"], "image");
    }
}
