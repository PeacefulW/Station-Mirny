use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppRequest {
    pub preset: String,
    pub tile_size: u32,
    pub south_height: u32,
    pub north_height: u32,
    pub side_height: u32,
    pub roughness: f32,
    pub face_power: f32,
    pub back_drop: f32,
    pub crown_bevel: u32,
    pub variants: u32,
    pub forced_variant: Option<u32>,
    pub seed: u32,
    pub texture_scale: f32,
    pub preview_mode: String,
    pub textures: TexturePaths,
    pub colors: ColorSet,
    pub map: MapData,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TexturePaths {
    pub top: Option<String>,
    pub face: Option<String>,
    pub base: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorSet {
    pub top: String,
    pub face: String,
    pub back: String,
    pub base: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MapData {
    pub width: u32,
    pub height: u32,
    pub cells: Vec<u8>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OutputManifest {
    pub mode: String,
    pub preset: String,
    pub tile_size: u32,
    pub variants: u32,
    pub signature_count: usize,
    pub total_tiles: usize,
    pub preview_mode: String,
    pub files: GeneratedFiles,
    pub warnings: Vec<String>,
    pub build_ms: u128,
}

#[derive(Debug, Clone, Serialize)]
pub struct GeneratedFiles {
    pub preview_png: String,
    pub atlas_albedo_png: Option<String>,
    pub atlas_mask_png: Option<String>,
    pub atlas_height_png: Option<String>,
    pub atlas_normal_png: Option<String>,
    pub top_albedo_png: Option<String>,
    pub face_albedo_png: Option<String>,
    pub base_albedo_png: Option<String>,
    pub top_modulation_png: Option<String>,
    pub face_modulation_png: Option<String>,
    pub top_normal_png: Option<String>,
    pub face_normal_png: Option<String>,
    pub recipe_json: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RenderMode {
    Draft,
    Full,
}

impl RenderMode {
    pub fn from_arg(value: &str) -> Self {
        match value.trim().to_ascii_lowercase().as_str() {
            "draft" => Self::Draft,
            _ => Self::Full,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Full => "full",
        }
    }
}

impl AppRequest {
    pub fn sanitized(mut self) -> Self {
        let preset = Preset::from_name(&self.preset);
        self.preset = preset.name.to_string();
        self.tile_size = self.tile_size.clamp(32, 128);
        self.south_height = self.south_height.clamp(4, self.tile_size / 2);
        self.north_height = self.north_height.clamp(2, self.tile_size / 2);
        self.side_height = self.side_height.clamp(2, self.tile_size / 2);
        self.roughness = self.roughness.clamp(0.0, 100.0);
        self.face_power = self.face_power.clamp(0.4, 2.8);
        self.back_drop = self.back_drop.clamp(0.1, 0.8);
        self.crown_bevel = self.crown_bevel.clamp(0, 12);
        self.variants = self.variants.clamp(1, 8);
        self.forced_variant = self.forced_variant.map(|value| value.min(self.variants.saturating_sub(1)));
        self.texture_scale = self.texture_scale.clamp(0.25, 4.0);
        self.preview_mode = normalize_preview_mode(&self.preview_mode).to_string();

        if self.colors.top.is_empty() {
            self.colors.top = preset.colors.top.to_string();
        }
        if self.colors.face.is_empty() {
            self.colors.face = preset.colors.face.to_string();
        }
        if self.colors.back.is_empty() {
            self.colors.back = preset.colors.back.to_string();
        }
        if self.colors.base.is_empty() {
            self.colors.base = preset.colors.base.to_string();
        }

        let expected = (self.map.width * self.map.height) as usize;
        if self.map.width == 0 || self.map.height == 0 || self.map.cells.len() != expected {
            self.map = default_map();
        } else {
            self.map.cells.iter_mut().for_each(|cell| *cell = u8::from(*cell > 0));
        }

        self
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Preset {
    pub name: &'static str,
    pub south_height: u32,
    pub north_height: u32,
    pub side_height: u32,
    pub roughness: f32,
    pub face_power: f32,
    pub back_drop: f32,
    pub crown_bevel: u32,
    pub variants: u32,
    pub colors: PresetColors,
}

#[derive(Debug, Clone, Copy)]
pub struct PresetColors {
    pub top: &'static str,
    pub face: &'static str,
    pub back: &'static str,
    pub base: &'static str,
}

impl Preset {
    pub fn from_name(name: &str) -> Self {
        match name.trim().to_ascii_lowercase().as_str() {
            "wall" => Self::wall(),
            "earth" => Self::earth(),
            _ => Self::mountain(),
        }
    }

    pub fn mountain() -> Self {
        Self {
            name: "mountain",
            south_height: 18,
            north_height: 10,
            side_height: 16,
            roughness: 52.0,
            face_power: 1.0,
            back_drop: 0.34,
            crown_bevel: 2,
            variants: 4,
            colors: PresetColors {
                top: "#705940",
                face: "#3e2f25",
                back: "#564436",
                base: "#b88d58",
            },
        }
    }

    pub fn wall() -> Self {
        Self {
            name: "wall",
            south_height: 10,
            north_height: 6,
            side_height: 8,
            roughness: 18.0,
            face_power: 1.34,
            back_drop: 0.24,
            crown_bevel: 1,
            variants: 3,
            colors: PresetColors {
                top: "#765439",
                face: "#473328",
                back: "#5e4636",
                base: "#bb9361",
            },
        }
    }

    pub fn earth() -> Self {
        Self {
            name: "earth",
            south_height: 8,
            north_height: 5,
            side_height: 7,
            roughness: 34.0,
            face_power: 0.82,
            back_drop: 0.28,
            crown_bevel: 2,
            variants: 4,
            colors: PresetColors {
                top: "#7b5027",
                face: "#5a3822",
                back: "#6b452a",
                base: "#a56a36",
            },
        }
    }
}

pub fn default_request() -> AppRequest {
    let preset = Preset::mountain();
    AppRequest {
        preset: preset.name.to_string(),
        tile_size: 64,
        south_height: preset.south_height,
        north_height: preset.north_height,
        side_height: preset.side_height,
        roughness: preset.roughness,
        face_power: preset.face_power,
        back_drop: preset.back_drop,
        crown_bevel: preset.crown_bevel,
        variants: preset.variants,
        forced_variant: None,
        seed: 240_518,
        texture_scale: 1.0,
        preview_mode: "composite".to_string(),
        textures: TexturePaths {
            top: None,
            face: None,
            base: None,
        },
        colors: ColorSet {
            top: preset.colors.top.to_string(),
            face: preset.colors.face.to_string(),
            back: preset.colors.back.to_string(),
            base: preset.colors.base.to_string(),
        },
        map: default_map(),
    }
}

pub fn default_map() -> MapData {
    let width = 18_u32;
    let height = 12_u32;
    let mut cells = vec![0_u8; (width * height) as usize];
    let cx = width as f32 / 2.0;
    let cy = height as f32 / 2.0;

    for y in 0..height {
        for x in 0..width {
            let dx = (x as f32 - cx) / (width as f32 * 0.38);
            let dy = (y as f32 - cy) / (height as f32 * 0.38);
            let radial = 1.0 - (dx * dx + dy * dy).sqrt();
            cells[(y * width + x) as usize] = u8::from(radial > 0.36);
        }
    }

    MapData {
        width,
        height,
        cells,
    }
}

pub fn normalize_preview_mode(value: &str) -> &'static str {
    match value.trim().to_ascii_lowercase().as_str() {
        "albedo" => "albedo",
        "mask" => "mask",
        "height" => "height",
        "normal" => "normal",
        _ => "composite",
    }
}
