const PRESETS = {
  mountain: {
    heightPx: 18,
    lipPx: 6,
    backRimRatio: 0.55,
    northRimThickness: 0,
    northHeightPx: 0,
    eastHeightPx: 0,
    westHeightPx: 0,
    roughness: 74,
    faceSlope: 100,
    innerCornerMode: "caps",
    crownBevel: 2,
    outerChamfer: 0,
    baseErosion: 0,
    cornerOverrideNE: "global",
    cornerOverrideNW: "global",
    cornerOverrideSE: "global",
    cornerOverrideSW: "global",
    normalStrength: 90,
    textureScale: 100,
    variants: 4,
    tintJitter: 10,
    topTint: "#6f5a43",
    faceTint: "#2f241d",
    baseTint: "#c79b63",
    topTintOpacity: 100,
    faceTintOpacity: 100,
    baseTintOpacity: 100,
    topMacroScale: 160,
    topMacroStrength: 42,
    topPebbleDensity: 12,
    topPebbleSize: 3,
    topMicroNoise: 26,
    topContrast: 112,
    faceStrataStrength: 30,
    faceVerticalFractures: 24,
    faceChips: 18,
    faceErosion: 28,
    faceContrast: 122
  },
  wall: {
    heightPx: 10,
    lipPx: 4,
    backRimRatio: 0.5,
    northRimThickness: 0,
    northHeightPx: 0,
    eastHeightPx: 0,
    westHeightPx: 0,
    roughness: 18,
    faceSlope: 130,
    innerCornerMode: "box",
    crownBevel: 1,
    outerChamfer: 1,
    baseErosion: 1,
    cornerOverrideNE: "global",
    cornerOverrideNW: "global",
    cornerOverrideSE: "global",
    cornerOverrideSW: "global",
    normalStrength: 75,
    textureScale: 90,
    variants: 3,
    tintJitter: 6,
    topTint: "#745335",
    faceTint: "#3d2c20",
    baseTint: "#c99d67",
    topTintOpacity: 100,
    faceTintOpacity: 100,
    baseTintOpacity: 100,
    topMacroScale: 136,
    topMacroStrength: 28,
    topPebbleDensity: 8,
    topPebbleSize: 2,
    topMicroNoise: 14,
    topContrast: 108,
    faceStrataStrength: 44,
    faceVerticalFractures: 18,
    faceChips: 10,
    faceErosion: 14,
    faceContrast: 118
  },
  earth: {
    heightPx: 8,
    lipPx: 5,
    backRimRatio: 0.45,
    northRimThickness: 1,
    northHeightPx: 0,
    eastHeightPx: 0,
    westHeightPx: 0,
    roughness: 54,
    faceSlope: 78,
    innerCornerMode: "bevel",
    crownBevel: 2,
    outerChamfer: 1,
    baseErosion: 2,
    cornerOverrideNE: "global",
    cornerOverrideNW: "global",
    cornerOverrideSE: "global",
    cornerOverrideSW: "global",
    normalStrength: 70,
    textureScale: 120,
    variants: 4,
    tintJitter: 12,
    topTint: "#704721",
    faceTint: "#50331f",
    baseTint: "#9f642f",
    topTintOpacity: 100,
    faceTintOpacity: 100,
    baseTintOpacity: 100,
    topMacroScale: 176,
    topMacroStrength: 50,
    topPebbleDensity: 10,
    topPebbleSize: 4,
    topMicroNoise: 34,
    topContrast: 118,
    faceStrataStrength: 20,
    faceVerticalFractures: 12,
    faceChips: 26,
    faceErosion: 34,
    faceContrast: 114
  }
};

const refs = {
  presetButtons: [...document.querySelectorAll("[data-preset]")],
  controlSearch: document.getElementById("controlSearch"),
  clearSearch: document.getElementById("clearSearch"),
  customPresetName: document.getElementById("customPresetName"),
  saveCustomPreset: document.getElementById("saveCustomPreset"),
  customPresetSelect: document.getElementById("customPresetSelect"),
  loadCustomPreset: document.getElementById("loadCustomPreset"),
  deleteCustomPreset: document.getElementById("deleteCustomPreset"),
  customPresetMeta: document.getElementById("customPresetMeta"),
  previewMode: document.getElementById("previewMode"),
  tileSize: document.getElementById("tileSize"),
  heightPx: document.getElementById("heightPx"),
  lipPx: document.getElementById("lipPx"),
  backRimRatio: document.getElementById("backRimRatio"),
  northRimThickness: document.getElementById("northRimThickness"),
  northHeightPx: document.getElementById("northHeightPx"),
  eastHeightPx: document.getElementById("eastHeightPx"),
  westHeightPx: document.getElementById("westHeightPx"),
  roughness: document.getElementById("roughness"),
  faceSlope: document.getElementById("faceSlope"),
  innerCornerMode: document.getElementById("innerCornerMode"),
  crownBevel: document.getElementById("crownBevel"),
  outerChamfer: document.getElementById("outerChamfer"),
  baseErosion: document.getElementById("baseErosion"),
  cornerOverrideNE: document.getElementById("cornerOverrideNE"),
  cornerOverrideNW: document.getElementById("cornerOverrideNW"),
  cornerOverrideSE: document.getElementById("cornerOverrideSE"),
  cornerOverrideSW: document.getElementById("cornerOverrideSW"),
  normalStrength: document.getElementById("normalStrength"),
  textureScale: document.getElementById("textureScale"),
  variants: document.getElementById("variants"),
  tintJitter: document.getElementById("tintJitter"),
  seed: document.getElementById("seed"),
  topTint: document.getElementById("topTint"),
  faceTint: document.getElementById("faceTint"),
  baseTint: document.getElementById("baseTint"),
  topTintOpacity: document.getElementById("topTintOpacity"),
  faceTintOpacity: document.getElementById("faceTintOpacity"),
  baseTintOpacity: document.getElementById("baseTintOpacity"),
  topMacroScale: document.getElementById("topMacroScale"),
  topMacroStrength: document.getElementById("topMacroStrength"),
  topPebbleDensity: document.getElementById("topPebbleDensity"),
  topPebbleSize: document.getElementById("topPebbleSize"),
  topMicroNoise: document.getElementById("topMicroNoise"),
  topContrast: document.getElementById("topContrast"),
  faceStrataStrength: document.getElementById("faceStrataStrength"),
  faceVerticalFractures: document.getElementById("faceVerticalFractures"),
  faceChips: document.getElementById("faceChips"),
  faceErosion: document.getElementById("faceErosion"),
  faceContrast: document.getElementById("faceContrast"),
  noisePreset: document.getElementById("noisePreset"),
  applyNoisePreset: document.getElementById("applyNoisePreset"),
  extractPalette: document.getElementById("extractPalette"),
  paletteButtons: [...document.querySelectorAll("[data-palette]")],
  sunAzimuth: document.getElementById("sunAzimuth"),
  layerStack: document.getElementById("layerStack"),
  layerStackSummary: document.getElementById("layerStackSummary"),
  layerLibraryType: document.getElementById("layerLibraryType"),
  addMaterialLayer: document.getElementById("addMaterialLayer"),
  baseTexture: document.getElementById("baseTexture"),
  topTexture: document.getElementById("topTexture"),
  faceTexture: document.getElementById("faceTexture"),
  baseFileName: document.getElementById("baseFileName"),
  topFileName: document.getElementById("topFileName"),
  faceFileName: document.getElementById("faceFileName"),
  baseTexturePreview: document.getElementById("baseTexturePreview"),
  topTexturePreview: document.getElementById("topTexturePreview"),
  faceTexturePreview: document.getElementById("faceTexturePreview"),
  previewViewport: document.getElementById("previewViewport"),
  previewCanvas: document.getElementById("previewCanvas"),
  previewZoomLabel: document.getElementById("previewZoomLabel"),
  resetPreviewView: document.getElementById("resetPreviewView"),
  atlasCanvas: document.getElementById("atlasCanvas"),
  topTilingCanvas: document.getElementById("topTilingCanvas"),
  faceTilingCanvas: document.getElementById("faceTilingCanvas"),
  tileGrid: document.getElementById("tileGrid"),
  galleryVariant: document.getElementById("galleryVariant"),
  status: document.getElementById("status"),
  statCases: document.getElementById("statCases"),
  statVariants: document.getElementById("statVariants"),
  statTotal: document.getElementById("statTotal"),
  catalogInfo: document.getElementById("catalogInfo"),
  randomBlob: document.getElementById("randomBlob"),
  randomCave: document.getElementById("randomCave"),
  roomMap: document.getElementById("roomMap"),
  clearMap: document.getElementById("clearMap"),
  undoMap: document.getElementById("undoMap"),
  redoMap: document.getElementById("redoMap"),
  downloadAtlas: document.getElementById("downloadAtlas"),
  downloadMaskAtlas: document.getElementById("downloadMaskAtlas"),
  downloadNormalAtlas: document.getElementById("downloadNormalAtlas"),
  downloadTopAlbedo: document.getElementById("downloadTopAlbedo"),
  downloadFaceAlbedo: document.getElementById("downloadFaceAlbedo"),
  downloadTopModulation: document.getElementById("downloadTopModulation"),
  downloadFaceModulation: document.getElementById("downloadFaceModulation"),
  downloadTopNormal: document.getElementById("downloadTopNormal"),
  downloadFaceNormal: document.getElementById("downloadFaceNormal"),
  downloadHeightAtlas: document.getElementById("downloadHeightAtlas"),
  downloadOrmAtlas: document.getElementById("downloadOrmAtlas"),
  downloadEmissionAtlas: document.getElementById("downloadEmissionAtlas"),
  downloadFlowAtlas: document.getElementById("downloadFlowAtlas"),
  downloadPreview: document.getElementById("downloadPreview"),
  downloadJson: document.getElementById("downloadJson"),
  downloadShapeTres: document.getElementById("downloadShapeTres"),
  downloadMaterialTres: document.getElementById("downloadMaterialTres"),
  downloadZip: document.getElementById("downloadZip"),
  exportAudit: document.getElementById("exportAudit"),
  loadJson: document.getElementById("loadJson"),
  regenerate: document.getElementById("regenerate")
};

const RANGE_IDS = [
  "tileSize",
  "heightPx",
  "lipPx",
  "backRimRatio",
  "northRimThickness",
  "northHeightPx",
  "eastHeightPx",
  "westHeightPx",
  "roughness",
  "faceSlope",
  "crownBevel",
  "outerChamfer",
  "baseErosion",
  "normalStrength",
  "textureScale",
  "variants",
  "tintJitter",
  "topTintOpacity",
  "faceTintOpacity",
  "baseTintOpacity",
  "topMacroScale",
  "topMacroStrength",
  "topPebbleDensity",
  "topPebbleSize",
  "topMicroNoise",
  "topContrast",
  "faceStrataStrength",
  "faceVerticalFractures",
  "faceChips",
  "faceErosion",
  "faceContrast",
  "sunAzimuth"
];

const COLOR_IDS = ["topTint", "faceTint", "baseTint"];
const PREVIEW_MODES = ["albedo", "mask", "shapeHeight", "shapeNormal", "shaderComposite"];
const ATLAS_EXPORT_MODES = [...PREVIEW_MODES, "height", "orm", "emission", "flow"];
const MATERIAL_EXPORT_SIZE = 512;
const LOCAL_STORAGE_PRESETS_KEY = "cliff_forge_47_custom_presets";
const LOCAL_STORAGE_SESSION_KEY = "cliff_forge_47_last_session";
const ATLAS_PADDING_PX = 2;
const SEAM_LINT_WARN_THRESHOLD = 10;
const NOISE_PRESETS = {
  organic: {
    topMacroScale: 160, topMacroStrength: 42, topPebbleDensity: 12, topPebbleSize: 3, topMicroNoise: 26, topContrast: 112,
    faceStrataStrength: 30, faceVerticalFractures: 24, faceChips: 18, faceErosion: 28, faceContrast: 122
  },
  stratified: {
    topMacroScale: 188, topMacroStrength: 26, topPebbleDensity: 6, topPebbleSize: 2, topMicroNoise: 12, topContrast: 108,
    faceStrataStrength: 62, faceVerticalFractures: 14, faceChips: 10, faceErosion: 18, faceContrast: 126
  },
  fractalRough: {
    topMacroScale: 136, topMacroStrength: 58, topPebbleDensity: 14, topPebbleSize: 4, topMicroNoise: 38, topContrast: 120,
    faceStrataStrength: 28, faceVerticalFractures: 42, faceChips: 34, faceErosion: 30, faceContrast: 130
  },
  quartz: {
    topMacroScale: 208, topMacroStrength: 36, topPebbleDensity: 10, topPebbleSize: 2, topMicroNoise: 18, topContrast: 116,
    faceStrataStrength: 20, faceVerticalFractures: 46, faceChips: 12, faceErosion: 12, faceContrast: 134
  },
  volcanic: {
    topMacroScale: 120, topMacroStrength: 54, topPebbleDensity: 16, topPebbleSize: 5, topMicroNoise: 32, topContrast: 128,
    faceStrataStrength: 18, faceVerticalFractures: 38, faceChips: 30, faceErosion: 42, faceContrast: 138
  }
};
const PRESET_NOISE_PROFILES = {
  mountain: "fractalRough",
  wall: "stratified",
  earth: "organic"
};
const BIOME_PALETTES = {
  alpine: { topTint: "#9aaec1", faceTint: "#57616c", baseTint: "#d5cab5" },
  basalt: { topTint: "#6c706f", faceTint: "#2f3337", baseTint: "#a6947f" },
  rustbelt: { topTint: "#8f704e", faceTint: "#5a3426", baseTint: "#d2a06e" },
  oasis: { topTint: "#6f8d63", faceTint: "#4e5c3b", baseTint: "#c9b07b" },
  tundra: { topTint: "#b7c2c8", faceTint: "#5a6166", baseTint: "#d7d2c4" }
};
const MATERIAL_LAYER_BLEND_MODES = ["overlay", "add", "multiply", "replace", "softLight"];
const MATERIAL_LAYER_MASKS = ["top", "face", "both"];
const MATERIAL_LAYER_TYPES = {
  brick: { label: "Brick", defaultBlend: "overlay", defaultMask: "face", defaultStrength: 56, defaultHeight: 78 },
  plank: { label: "Plank", defaultBlend: "softLight", defaultMask: "top", defaultStrength: 38, defaultHeight: 62 },
  stoneCluster: { label: "Stone Cluster", defaultBlend: "overlay", defaultMask: "both", defaultStrength: 44, defaultHeight: 70 },
  snowDrift: { label: "Snow Drift", defaultBlend: "add", defaultMask: "top", defaultStrength: 26, defaultHeight: 58 },
  cracks: { label: "Cracks", defaultBlend: "multiply", defaultMask: "face", defaultStrength: 34, defaultHeight: 82 },
  moss: { label: "Moss", defaultBlend: "softLight", defaultMask: "both", defaultStrength: 30, defaultHeight: 42 },
  rivets: { label: "Rivets", defaultBlend: "overlay", defaultMask: "face", defaultStrength: 32, defaultHeight: 76 },
  runes: { label: "Runes", defaultBlend: "replace", defaultMask: "face", defaultStrength: 22, defaultHeight: 86 },
  puddles: { label: "Puddles", defaultBlend: "replace", defaultMask: "top", defaultStrength: 24, defaultHeight: 30 },
  debris: { label: "Debris", defaultBlend: "overlay", defaultMask: "top", defaultStrength: 28, defaultHeight: 66 },
  rust: { label: "Rust", defaultBlend: "multiply", defaultMask: "face", defaultStrength: 34, defaultHeight: 40 },
  sand: { label: "Sand", defaultBlend: "add", defaultMask: "top", defaultStrength: 26, defaultHeight: 54 },
  concrete: { label: "Concrete", defaultBlend: "overlay", defaultMask: "both", defaultStrength: 28, defaultHeight: 48 },
  mud: { label: "Mud", defaultBlend: "multiply", defaultMask: "both", defaultStrength: 30, defaultHeight: 52 },
  hex: { label: "Hex", defaultBlend: "replace", defaultMask: "face", defaultStrength: 20, defaultHeight: 74 },
  cobblestone: { label: "Cobblestone", defaultBlend: "overlay", defaultMask: "top", defaultStrength: 42, defaultHeight: 78 }
};

let materialLayerSequence = 1;

function createMaterialLayer(type, overrides = {}) {
  const definition = MATERIAL_LAYER_TYPES[type];
  if (!definition) throw new Error(`Unknown material layer type: ${type}`);
  return {
    id: overrides.id || `layer_${materialLayerSequence++}`,
    type,
    enabled: overrides.enabled ?? true,
    strength: clamp(Number(overrides.strength ?? definition.defaultStrength), 0, 100),
    blend: MATERIAL_LAYER_BLEND_MODES.includes(overrides.blend) ? overrides.blend : definition.defaultBlend,
    mask: MATERIAL_LAYER_MASKS.includes(overrides.mask) ? overrides.mask : definition.defaultMask,
    heightContribution: clamp(Number(overrides.heightContribution ?? definition.defaultHeight), 0, 100)
  };
}

function createDefaultMaterialLayers(preset) {
  const presets = {
    mountain: [
      { type: "stoneCluster", strength: 58, blend: "overlay", mask: "both", heightContribution: 74 },
      { type: "cracks", strength: 42, blend: "multiply", mask: "face", heightContribution: 88 },
      { type: "snowDrift", strength: 18, blend: "add", mask: "top", heightContribution: 44 },
      { type: "brick", strength: 0, blend: "overlay", mask: "face", heightContribution: 72, enabled: false },
      { type: "plank", strength: 0, blend: "softLight", mask: "top", heightContribution: 54, enabled: false }
    ],
    wall: [
      { type: "brick", strength: 62, blend: "overlay", mask: "face", heightContribution: 82 },
      { type: "cracks", strength: 28, blend: "multiply", mask: "face", heightContribution: 84 },
      { type: "plank", strength: 16, blend: "softLight", mask: "top", heightContribution: 40 },
      { type: "stoneCluster", strength: 12, blend: "overlay", mask: "both", heightContribution: 34 },
      { type: "snowDrift", strength: 0, blend: "add", mask: "top", heightContribution: 28, enabled: false }
    ],
    earth: [
      { type: "stoneCluster", strength: 34, blend: "overlay", mask: "both", heightContribution: 56 },
      { type: "plank", strength: 0, blend: "softLight", mask: "top", heightContribution: 48, enabled: false },
      { type: "snowDrift", strength: 0, blend: "add", mask: "top", heightContribution: 36, enabled: false },
      { type: "cracks", strength: 18, blend: "multiply", mask: "face", heightContribution: 72 },
      { type: "brick", strength: 0, blend: "overlay", mask: "face", heightContribution: 80, enabled: false }
    ]
  };
  const config = presets[preset] || presets.mountain;
  return config.map((layer) => createMaterialLayer(layer.type, layer));
}

function serializeMaterialLayers(layers = state?.materialLayers || []) {
  return layers.map((layer) => ({
    type: layer.type,
    enabled: Boolean(layer.enabled),
    strength: clamp(Number(layer.strength), 0, 100),
    blend: layer.blend,
    mask: layer.mask,
    heightContribution: clamp(Number(layer.heightContribution ?? 0), 0, 100)
  }));
}

function normalizeMaterialLayers(layers, preset = state?.preset || "mountain") {
  if (!Array.isArray(layers) || !layers.length) {
    return createDefaultMaterialLayers(preset);
  }
  return layers
    .filter((layer) => MATERIAL_LAYER_TYPES[layer.type])
    .map((layer) => createMaterialLayer(layer.type, layer));
}

function resetMaterialLayersForPreset(preset) {
  state.materialLayers = createDefaultMaterialLayers(preset);
}

function createGeneratedState() {
  return {
    tiles: [],
    baseVariants: [],
    atlasManifest: [],
    atlases: {},
    material: { top: null, face: null, topAlbedo: null, faceAlbedo: null },
    previewCompositeCache: new Map(),
    audit: {
      seamLint: null,
      deterministicProof: null
    }
  };
}

const state = {
  preset: "mountain",
  customPresetName: "",
  materialLayers: [],
  dragLayerId: null,
  previewMode: "shaderComposite",
  catalog: [],
  catalogByKey: new Map(),
  textures: { base: null, top: null, face: null },
  textureNames: { base: "procedural", top: "procedural", face: "procedural" },
  generated: createGeneratedState(),
  preview: {
    sourceCanvas: null,
    logicalTileSize: 64,
    isDraft: false,
    view: {
      scale: 1,
      offsetX: 0,
      offsetY: 0,
      isPanning: false,
      pointerId: null,
      originX: 0,
      originY: 0,
      spaceHeld: false,
      spaceUsedForPan: false
    }
  },
  map: { width: 18, height: 12, cells: [] },
  pendingRenderTimer: null,
  pendingRenderMode: null,
  galleryCards: new Map(),
  history: {
    past: [],
    future: [],
    limit: 64,
    strokeSnapshot: null
  },
  dirty: {
    shape: true,
    material: true,
    color: true,
    variants: true,
    map: true,
    previewMode: true,
    gallery: true,
    stats: true,
    swatches: true
  }
};

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function smoothstep(a, b, value) {
  const t = clamp((value - a) / (b - a || 1), 0, 1);
  return t * t * (3 - 2 * t);
}

function mod(value, size) {
  return ((value % size) + size) % size;
}

function hash2D(x, y, seed) {
  let n = (Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(seed, 1442695041)) >>> 0;
  n = (n ^ (n >>> 13)) >>> 0;
  n = Math.imul(n, 1274126177) >>> 0;
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

function hexToRgb(hex) {
  return [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16)
  ];
}

function rgbToHex(color) {
  return `#${color.map((value) => clamp(Math.round(value), 0, 255).toString(16).padStart(2, "0")).join("")}`;
}

function createCanvas(width, height) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  return canvas;
}

function releaseCanvas(canvas) {
  if (!canvas) return;
  canvas.width = 0;
  canvas.height = 0;
}

function presentCanvas(displayCanvas, sourceCanvas) {
  if (!displayCanvas || !sourceCanvas) return;
  const dpr = Math.max(1, window.devicePixelRatio || 1);
  const logicalWidth = sourceCanvas.width;
  const logicalHeight = sourceCanvas.height;
  displayCanvas.width = Math.max(1, Math.round(logicalWidth * dpr));
  displayCanvas.height = Math.max(1, Math.round(logicalHeight * dpr));
  displayCanvas.style.width = `${logicalWidth}px`;
  displayCanvas.style.height = `${logicalHeight}px`;
  displayCanvas.dataset.logicalWidth = String(logicalWidth);
  displayCanvas.dataset.logicalHeight = String(logicalHeight);
  const ctx = displayCanvas.getContext("2d");
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, displayCanvas.width, displayCanvas.height);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(sourceCanvas, 0, 0, displayCanvas.width, displayCanvas.height);
  if (displayCanvas === refs.previewCanvas) applyPreviewTransform();
}

function sanitizeFileStem(value) {
  return String(value || "preset")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/gi, "_")
    .replace(/^_+|_+$/g, "") || "preset";
}

function getDisplayPresetName() {
  return state.customPresetName || state.preset || "preset";
}

function buildExportBaseName(params = getParams()) {
  return `${sanitizeFileStem(getDisplayPresetName())}_${params.seed}_${params.tileSize}`;
}

function updatePreviewZoomLabel() {
  if (!refs.previewZoomLabel) return;
  refs.previewZoomLabel.textContent = `${Math.round(state.preview.view.scale * 100)}%`;
}

function applyPreviewTransform() {
  if (!refs.previewCanvas) return;
  const { scale, offsetX, offsetY, isPanning } = state.preview.view;
  refs.previewCanvas.style.transformOrigin = "0 0";
  refs.previewCanvas.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`;
  refs.previewViewport?.classList.toggle("is-panning", isPanning);
  updatePreviewZoomLabel();
}

function resetPreviewView() {
  state.preview.view.scale = 1;
  state.preview.view.offsetX = 0;
  state.preview.view.offsetY = 0;
  applyPreviewTransform();
}

function updateLayerStackSummary() {
  if (!refs.layerStackSummary) return;
  const total = state.materialLayers.length;
  const enabled = state.materialLayers.filter((layer) => layer.enabled).length;
  refs.layerStackSummary.textContent = `${enabled}/${total}`;
}

function matchingBiomePaletteName() {
  const topTint = refs.topTint?.value?.toLowerCase();
  const faceTint = refs.faceTint?.value?.toLowerCase();
  const baseTint = refs.baseTint?.value?.toLowerCase();
  const match = Object.entries(BIOME_PALETTES).find(([, palette]) => (
    palette.topTint.toLowerCase() === topTint
    && palette.faceTint.toLowerCase() === faceTint
    && palette.baseTint.toLowerCase() === baseTint
  ));
  return match?.[0] || "";
}

function refreshPaletteButtons(activeName = matchingBiomePaletteName()) {
  refs.paletteButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.palette === activeName);
  });
}

function applyBiomePalette(name) {
  const palette = BIOME_PALETTES[name];
  if (!palette) return;
  refs.topTint.value = palette.topTint;
  refs.faceTint.value = palette.faceTint;
  refs.baseTint.value = palette.baseTint;
  refreshPaletteButtons(name);
  markDirty("color");
  scheduleRender("full");
  refs.status.innerHTML = `<span class="ok">Palette applied.</span> ${name} palette обновила top/face/base tint.`;
}

function applyNoisePreset() {
  const preset = NOISE_PRESETS[refs.noisePreset.value];
  if (!preset) return;
  Object.entries(preset).forEach(([key, value]) => {
    if (refs[key]) refs[key].value = String(value);
  });
  updateRangeLabels();
  markDirty("material");
  scheduleRender("full");
  refs.status.innerHTML = `<span class="ok">Noise preset applied.</span> ${refs.noisePreset.value} синхронизировал material sliders.`;
}

function samplePalettePixelsFromTexture(texture, maxSamples) {
  if (!texture) return [];
  const pixels = [];
  const total = texture.width * texture.height;
  const stride = Math.max(1, Math.floor(Math.sqrt(total / Math.max(1, maxSamples))));
  for (let y = 0; y < texture.height; y += stride) {
    for (let x = 0; x < texture.width; x += stride) {
      const index = (y * texture.width + x) * 4;
      if (texture.data[index + 3] < 128) continue;
      pixels.push([texture.data[index], texture.data[index + 1], texture.data[index + 2]]);
      if (pixels.length >= maxSamples) return pixels;
    }
  }
  return pixels;
}

function clusterPaletteColors(samples, centroidCount = 5, iterations = 5) {
  if (!samples.length) return [];
  const centroids = [];
  for (let index = 0; index < Math.min(centroidCount, samples.length); index += 1) {
    const source = samples[Math.floor((index / Math.max(1, centroidCount - 1)) * (samples.length - 1))];
    centroids.push(source.slice());
  }
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const buckets = centroids.map(() => ({ sum: [0, 0, 0], count: 0 }));
    samples.forEach((sample) => {
      let bestIndex = 0;
      let bestDistance = Number.POSITIVE_INFINITY;
      centroids.forEach((centroid, index) => {
        const distance = (
          (sample[0] - centroid[0]) ** 2
          + (sample[1] - centroid[1]) ** 2
          + (sample[2] - centroid[2]) ** 2
        );
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = index;
        }
      });
      buckets[bestIndex].sum[0] += sample[0];
      buckets[bestIndex].sum[1] += sample[1];
      buckets[bestIndex].sum[2] += sample[2];
      buckets[bestIndex].count += 1;
    });
    buckets.forEach((bucket, index) => {
      if (!bucket.count) return;
      centroids[index] = bucket.sum.map((sum) => sum / bucket.count);
    });
  }
  return centroids;
}

function extractPaletteFromTextures() {
  const samples = [
    ...samplePalettePixelsFromTexture(state.textures.top, 160),
    ...samplePalettePixelsFromTexture(state.textures.face, 160),
    ...samplePalettePixelsFromTexture(state.textures.base, 120)
  ];
  if (!samples.length) {
    refs.status.innerHTML = `<span class="warn">Palette unavailable.</span> Сначала загрузи хотя бы одну texture для анализа.`;
    return;
  }
  const centroids = clusterPaletteColors(samples, 5, 6)
    .sort((a, b) => (a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722) - (b[0] * 0.2126 + b[1] * 0.7152 + b[2] * 0.0722));
  const faceTint = rgbToHex(centroids[0] || centroids[centroids.length - 1]);
  const baseTint = rgbToHex(centroids[Math.floor((centroids.length - 1) / 2)] || centroids[0]);
  const topTint = rgbToHex(centroids[centroids.length - 1] || centroids[0]);
  refs.faceTint.value = faceTint;
  refs.baseTint.value = baseTint;
  refs.topTint.value = topTint;
  refreshPaletteButtons("");
  markDirty("color");
  scheduleRender("full");
  refs.status.innerHTML = `<span class="ok">Palette extracted.</span> Tints собраны из загруженных textures через lightweight k-means.`;
}

function addMaterialLayer(type = refs.layerLibraryType.value) {
  if (!MATERIAL_LAYER_TYPES[type]) return;
  state.materialLayers.push(createMaterialLayer(type));
  renderMaterialLayerControls();
  markDirty("material");
  scheduleRender("full");
}

function removeMaterialLayer(layerId) {
  const before = state.materialLayers.length;
  state.materialLayers = state.materialLayers.filter((layer) => layer.id !== layerId);
  if (state.materialLayers.length === before) return;
  renderMaterialLayerControls();
  markDirty("material");
  scheduleRender("full");
}

function moveMaterialLayer(dragId, targetId) {
  if (!dragId || !targetId || dragId === targetId) return;
  const sourceIndex = state.materialLayers.findIndex((layer) => layer.id === dragId);
  const targetIndex = state.materialLayers.findIndex((layer) => layer.id === targetId);
  if (sourceIndex < 0 || targetIndex < 0) return;
  const [moved] = state.materialLayers.splice(sourceIndex, 1);
  const nextTargetIndex = state.materialLayers.findIndex((layer) => layer.id === targetId);
  state.materialLayers.splice(nextTargetIndex < 0 ? state.materialLayers.length : nextTargetIndex, 0, moved);
  renderMaterialLayerControls();
  markDirty("material");
  scheduleRender("full");
}

function renderMaterialLayerControls() {
  if (!refs.layerStack) return;
  refs.layerStack.innerHTML = "";
  updateLayerStackSummary();

  state.materialLayers.forEach((layer, index) => {
    const definition = MATERIAL_LAYER_TYPES[layer.type];
    const card = document.createElement("div");
    card.className = `layer-card${layer.enabled ? "" : " is-disabled"}`;
    card.draggable = true;
    card.dataset.layerId = layer.id;

    const head = document.createElement("div");
    head.className = "layer-card-head";

    const titleWrap = document.createElement("div");
    titleWrap.className = "layer-card-title";

    const drag = document.createElement("span");
    drag.className = "layer-drag";
    drag.textContent = "drag";
    drag.title = "Перетащи, чтобы поменять порядок слоя.";

    const chip = document.createElement("span");
    chip.className = "layer-chip";
    chip.textContent = `#${index + 1}`;

    const title = document.createElement("strong");
    title.textContent = definition.label;

    titleWrap.append(drag, chip, title);

    const toggle = document.createElement("label");
    toggle.className = "layer-toggle";
    toggle.title = "Выключает или включает вклад слоя в material map.";
    const toggleInput = document.createElement("input");
    toggleInput.type = "checkbox";
    toggleInput.checked = layer.enabled;
    const toggleText = document.createElement("span");
    toggleText.textContent = layer.enabled ? "Enabled" : "Disabled";
    toggle.append(toggleInput, toggleText);
    toggleInput.addEventListener("change", () => {
      layer.enabled = toggleInput.checked;
      toggleText.textContent = layer.enabled ? "Enabled" : "Disabled";
      card.classList.toggle("is-disabled", !layer.enabled);
      updateLayerStackSummary();
      markDirty("material");
      scheduleRender("full");
    });

    const headActions = document.createElement("div");
    headActions.className = "inline-tools";
    const removeButton = document.createElement("button");
    removeButton.className = "layer-remove";
    removeButton.type = "button";
    removeButton.textContent = "Remove";
    removeButton.title = "Удалить слой из stack.";
    removeButton.addEventListener("click", () => removeMaterialLayer(layer.id));
    headActions.append(toggle, removeButton);
    head.append(titleWrap, headActions);

    const controls = document.createElement("div");
    controls.className = "layer-grid";

    const maskField = document.createElement("div");
    maskField.className = "field";
    const maskLabel = document.createElement("label");
    maskLabel.textContent = "Mask";
    const maskSelect = document.createElement("select");
    maskSelect.className = "select-input";
    MATERIAL_LAYER_MASKS.forEach((mask) => {
      const option = document.createElement("option");
      option.value = mask;
      option.textContent = mask === "both" ? "Top + Face" : mask === "top" ? "Top only" : "Face only";
      maskSelect.appendChild(option);
    });
    maskSelect.value = layer.mask;
    maskSelect.title = "Куда применять слой: только top, только face или в оба material maps.";
    maskSelect.addEventListener("change", () => {
      layer.mask = maskSelect.value;
      markDirty("material");
      scheduleRender("full");
    });
    maskField.append(maskLabel, maskSelect);

    const blendField = document.createElement("div");
    blendField.className = "field";
    const blendLabel = document.createElement("label");
    blendLabel.textContent = "Blend";
    const blendSelect = document.createElement("select");
    blendSelect.className = "select-input";
    MATERIAL_LAYER_BLEND_MODES.forEach((blend) => {
      const option = document.createElement("option");
      option.value = blend;
      option.textContent = blend;
      blendSelect.appendChild(option);
    });
    blendSelect.value = layer.blend;
    blendSelect.title = "Blend mode слоя поверх legacy base look и предыдущих слоёв.";
    blendSelect.addEventListener("change", () => {
      layer.blend = blendSelect.value;
      markDirty("material");
      scheduleRender("full");
    });
    blendField.append(blendLabel, blendSelect);

    const strengthField = document.createElement("div");
    strengthField.className = "field";
    const strengthLabel = document.createElement("label");
    const strengthValue = document.createElement("span");
    strengthValue.className = "value";
    strengthValue.textContent = String(layer.strength);
    strengthLabel.append(document.createTextNode("Strength"), strengthValue);
    const strengthInput = document.createElement("input");
    strengthInput.className = "range";
    strengthInput.type = "range";
    strengthInput.min = "0";
    strengthInput.max = "100";
    strengthInput.step = "1";
    strengthInput.value = String(layer.strength);
    strengthInput.title = "Сила вклада слоя в modulation.";
    strengthInput.addEventListener("input", () => {
      layer.strength = Number(strengthInput.value);
      strengthValue.textContent = strengthInput.value;
      markDirty("material");
      scheduleRender("draft");
    });
    strengthInput.addEventListener("change", () => {
      layer.strength = Number(strengthInput.value);
      markDirty("material");
      scheduleRender("full");
    });
    strengthField.append(strengthLabel, strengthInput);

    const heightField = document.createElement("div");
    heightField.className = "field";
    const heightLabel = document.createElement("label");
    const heightValue = document.createElement("span");
    heightValue.className = "value";
    heightValue.textContent = String(layer.heightContribution);
    heightLabel.append(document.createTextNode("Height"), heightValue);
    const heightInput = document.createElement("input");
    heightInput.className = "range";
    heightInput.type = "range";
    heightInput.min = "0";
    heightInput.max = "100";
    heightInput.step = "1";
    heightInput.value = String(layer.heightContribution);
    heightInput.title = "Насколько слой влияет на aggregated height для normal canvas.";
    heightInput.addEventListener("input", () => {
      layer.heightContribution = Number(heightInput.value);
      heightValue.textContent = heightInput.value;
      markDirty("material");
      scheduleRender("draft");
    });
    heightInput.addEventListener("change", () => {
      layer.heightContribution = Number(heightInput.value);
      markDirty("material");
      scheduleRender("full");
    });
    heightField.append(heightLabel, heightInput);

    controls.append(maskField, blendField, strengthField, heightField);
    card.append(head, controls);

    card.addEventListener("dragstart", () => {
      state.dragLayerId = layer.id;
      card.classList.add("is-dragging");
    });
    card.addEventListener("dragend", () => {
      state.dragLayerId = null;
      card.classList.remove("is-dragging");
    });
    card.addEventListener("dragover", (event) => {
      event.preventDefault();
    });
    card.addEventListener("drop", (event) => {
      event.preventDefault();
      moveMaterialLayer(state.dragLayerId, layer.id);
    });

    refs.layerStack.appendChild(card);
  });
}

function readJsonStorage(key, fallback) {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function writeJsonStorage(key, value) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Ignore storage quota failures in the tool UI.
  }
}

function readCustomPresets() {
  const value = readJsonStorage(LOCAL_STORAGE_PRESETS_KEY, []);
  return Array.isArray(value) ? value : [];
}

function writeCustomPresets(presets) {
  writeJsonStorage(LOCAL_STORAGE_PRESETS_KEY, presets);
}

function refreshCustomPresetOptions() {
  const presets = readCustomPresets();
  const preferred = refs.customPresetSelect.value || state.customPresetName;
  refs.customPresetSelect.innerHTML = "";
  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = presets.length ? "Выбери preset" : "Список пуст";
  refs.customPresetSelect.appendChild(placeholder);
  presets.forEach((preset) => {
    const option = document.createElement("option");
    option.value = preset.name;
    option.textContent = preset.name;
    refs.customPresetSelect.appendChild(option);
  });
  refs.customPresetSelect.value = presets.some((preset) => preset.name === preferred) ? preferred : "";
  refs.customPresetMeta.textContent = presets.length
    ? `${presets.length} custom preset(ов) в localStorage.`
    : "Custom presets хранятся в localStorage.";
}

function buildCustomPresetPayload(name) {
  return {
    name,
    basePreset: state.preset,
    previewMode: refs.previewMode.value,
    params: getParams(),
    materialLayers: serializeMaterialLayers(state.materialLayers)
  };
}

function applyCustomPresetPayload(payload) {
  Object.entries(payload.params || {}).forEach(([key, value]) => {
    if (refs[key]) refs[key].value = String(value);
  });
  state.preset = payload.basePreset || "mountain";
  state.customPresetName = payload.name || "";
  state.materialLayers = normalizeMaterialLayers(payload.materialLayers, state.preset);
  refs.previewMode.value = payload.previewMode && PREVIEW_MODES.includes(payload.previewMode)
    ? payload.previewMode
    : refs.previewMode.value;
  refs.presetButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.preset === state.preset);
  });
  refs.customPresetName.value = state.customPresetName;
  updateRangeLabels();
  refreshGalleryOptions();
  refreshPaletteButtons();
  renderMaterialLayerControls();
}

function saveCurrentCustomPreset() {
  const name = refs.customPresetName.value.trim();
  if (!name) {
    refs.status.innerHTML = `<span class="warn">Нужно имя preset.</span> Введите название перед сохранением.`;
    return;
  }
  const presets = readCustomPresets().filter((preset) => preset.name !== name);
  presets.push(buildCustomPresetPayload(name));
  presets.sort((a, b) => a.name.localeCompare(b.name));
  writeCustomPresets(presets);
  state.customPresetName = name;
  refreshCustomPresetOptions();
  refs.customPresetSelect.value = name;
  persistSessionState();
  refs.status.innerHTML = `<span class="ok">Preset saved.</span> \`${name}\` сохранён в localStorage.`;
}

function loadSelectedCustomPreset() {
  const name = refs.customPresetSelect.value;
  if (!name) return;
  const preset = readCustomPresets().find((item) => item.name === name);
  if (!preset) return;
  applyCustomPresetPayload(preset);
  markDirty("all");
  scheduleRender("full");
}

function deleteSelectedCustomPreset() {
  const name = refs.customPresetSelect.value;
  if (!name) return;
  const presets = readCustomPresets().filter((preset) => preset.name !== name);
  writeCustomPresets(presets);
  if (state.customPresetName === name) {
    state.customPresetName = "";
    refs.customPresetName.value = "";
  }
  refreshCustomPresetOptions();
  persistSessionState();
  refs.status.innerHTML = `<span class="ok">Preset removed.</span> \`${name}\` удалён из localStorage.`;
}

function persistSessionState() {
  writeJsonStorage(LOCAL_STORAGE_SESSION_KEY, {
    preset: state.preset,
    customPresetName: state.customPresetName,
    previewMode: refs.previewMode.value,
    params: getParams(),
    materialLayers: serializeMaterialLayers(state.materialLayers),
    map: {
      width: state.map.width,
      height: state.map.height,
      cells: state.map.cells.slice()
    }
  });
}

function restoreSessionState() {
  const payload = readJsonStorage(LOCAL_STORAGE_SESSION_KEY, null);
  if (!payload || !payload.params) return false;
  if (payload.map && Array.isArray(payload.map.cells) && payload.map.cells.length === state.map.width * state.map.height) {
    restoreMapSnapshot(payload.map.cells);
  }
  if (payload.previewMode && PREVIEW_MODES.includes(payload.previewMode)) {
    refs.previewMode.value = payload.previewMode;
  }
  Object.entries(payload.params).forEach(([key, value]) => {
    if (refs[key]) refs[key].value = String(value);
  });
  state.preset = payload.preset || "mountain";
  state.customPresetName = payload.customPresetName || "";
  state.materialLayers = normalizeMaterialLayers(payload.materialLayers, state.preset);
  refs.customPresetName.value = state.customPresetName;
  refs.presetButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.preset === state.preset);
  });
  updateRangeLabels();
  refreshGalleryOptions();
  refreshPaletteButtons();
  renderMaterialLayerControls();
  refreshCustomPresetOptions();
  if (state.customPresetName) refs.customPresetSelect.value = state.customPresetName;
  return true;
}

function bindGroupCollapsers() {
  document.querySelectorAll(".sidebar .group h2").forEach((heading) => {
    heading.setAttribute("role", "button");
    heading.setAttribute("tabindex", "0");
    const group = heading.closest(".group");
    const toggle = () => {
      if (refs.controlSearch.value.trim()) return;
      group.classList.toggle("is-collapsed");
    };
    heading.addEventListener("click", toggle);
    heading.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        toggle();
      }
    });
  });
}

function applyControlSearch(query) {
  const normalized = query.trim().toLowerCase();
  const groups = [...document.querySelectorAll(".sidebar .group")];
  groups.forEach((group) => {
    const titleText = group.querySelector("h2")?.textContent.toLowerCase() || "";
    const fields = [...group.querySelectorAll(".field, .file-card, .preset-tools, .preset-row, .actions, .hint, .preset-meta, .layer-card, .layer-note")];
    let visibleCount = 0;
    fields.forEach((field) => {
      const matches = !normalized || field.textContent.toLowerCase().includes(normalized) || titleText.includes(normalized);
      field.classList.toggle("is-hidden", !matches);
      if (matches) visibleCount += 1;
    });
    group.querySelectorAll(".row").forEach((row) => {
      const visibleChildren = [...row.children].some((child) => !child.classList.contains("is-hidden"));
      row.classList.toggle("is-hidden", !visibleChildren && Boolean(normalized));
    });
    const isVisible = !normalized || visibleCount > 0 || titleText.includes(normalized);
    group.classList.toggle("is-hidden", !isVisible);
    if (normalized && isVisible) group.classList.remove("is-collapsed");
  });
}

function bindControlSearch() {
  refs.controlSearch.addEventListener("input", () => applyControlSearch(refs.controlSearch.value));
  refs.clearSearch.addEventListener("click", () => {
    refs.controlSearch.value = "";
    applyControlSearch("");
  });
}

function applyTooltips() {
  const tooltips = {
    tileSize: "Размер одной ячейки набора. Больше пикселей — больше detail и тяжелее preview.",
    heightPx: "Глубина южного фасада. Это текущая south-side height.",
    lipPx: "Толщина верхней кромки, которая отделяет top surface от face.",
    backRimRatio: "Насколько толстым будет северный back rim относительно lip.",
    northRimThickness: "Дополнительная толщина северного rim поверх base ratio.",
    northHeightPx: "Явный override высоты северной стороны. 0 = использовать legacy back rim controls.",
    eastHeightPx: "Явный override высоты восточной стороны. 0 = использовать lipPx.",
    westHeightPx: "Явный override высоты западной стороны. 0 = использовать lipPx.",
    roughness: "Сила зазубрин и drift в профилях граней.",
    faceSlope: "Кривая падения высоты на фасаде: ниже значение — мягче склон, выше — отвеснее.",
    crownBevel: "Ширина bevel на верхней кромке top surface для более мягкой нормали.",
    outerChamfer: "Срез внешних углов тайла, чтобы corner silhouettes не были полностью прямоугольными.",
    baseErosion: "Подрезание нижней части face silhouettes у внешних краёв.",
    cornerOverrideNE: "Локальный override для северо-восточного inner corner. Global = использовать общий режим.",
    cornerOverrideNW: "Локальный override для северо-западного inner corner. Global = использовать общий режим.",
    cornerOverrideSE: "Локальный override для юго-восточного inner corner. Global = использовать общий режим.",
    cornerOverrideSW: "Локальный override для юго-западного inner corner. Global = использовать общий режим.",
    normalStrength: "Сила shape normals в shader composite preview.",
    textureScale: "Чем выше значение, тем мельче повторяется загруженная текстура.",
    variants: "Сколько вариаций генерировать на каждую из 47 сигнатур.",
    seed: "Базовый deterministic seed для материалов, вариаций и map generators.",
    topMacroScale: "Размер крупных пятен breakup на верхней поверхности.",
    topMacroStrength: "Контраст и заметность macro breakup на top.",
    topPebbleDensity: "Частота камешков / blobs на top material map.",
    topPebbleSize: "Размер камешков / blob details на top.",
    topMicroNoise: "Сила мелкого шума на top material.",
    topContrast: "Контраст итоговой top modulation.",
    faceStrataStrength: "Сила горизонтальной стратификации фасада.",
    faceVerticalFractures: "Сила и частота вертикальных трещин на face.",
    faceChips: "Количество выбоин и chipped areas на face.",
    faceErosion: "Размыв и erosion toward lower face.",
    faceContrast: "Контраст face modulation.",
    noisePreset: "Готовый профиль шума, который согласованно крутит material sliders.",
    applyNoisePreset: "Применить выбранный noise preset к текущим material sliders.",
    extractPalette: "Собрать top/face/base tint из загруженных textures через lightweight k-means.",
    sunAzimuth: "Глобальное направление weathering. Snow, moss, rust и sand ориентируются по этому углу.",
    layerLibraryType: "Выбери тип слоя, который нужно добавить в текущий stack.",
    addMaterialLayer: "Добавить новый слой выбранного типа в конец stack.",
    randomBlob: "Заполнить preview карту blob-like формой для быстрой проверки связности.",
    randomCave: "Собрать cave-like карту через cellular smoothing.",
    roomMap: "Нарисовать прямоугольную комнату для проверки наружных/внутренних кейсов.",
    clearMap: "Очистить preview карту.",
    undoMap: "Откатить последнее изменение карты. Hotkey: Ctrl/Cmd+Z.",
    redoMap: "Повторить откат. Hotkey: Ctrl/Cmd+Y.",
    saveCustomPreset: "Сохранить текущие authoring settings как именованный custom preset в localStorage.",
    loadCustomPreset: "Загрузить выбранный custom preset из localStorage.",
    deleteCustomPreset: "Удалить выбранный custom preset из localStorage.",
    downloadTopNormal: "Скачать tileable top normal texture для TerrainMaterialSet.",
    downloadFaceNormal: "Скачать tileable face normal texture для TerrainMaterialSet.",
    downloadHeightAtlas: "Скачать combined height atlas с bleed padding.",
    downloadOrmAtlas: "Скачать ORM atlas: occlusion / roughness / metallic.",
    downloadEmissionAtlas: "Скачать emission atlas для glow-aware материалов.",
    downloadFlowAtlas: "Скачать flow atlas: encoded flow x/y и magnitude.",
    downloadShapeTres: "Скачать Godot TerrainShapeSet.tres, совместимый с текущим runtime resource format.",
    downloadMaterialTres: "Скачать Godot TerrainMaterialSet.tres, совместимый с текущим runtime resource format.",
    downloadZip: "Скачать весь текущий export bundle одним ZIP-файлом."
  };
  Object.entries(tooltips).forEach(([id, text]) => {
    const element = refs[id];
    if (element) element.title = text;
    const label = document.querySelector(`label[for="${id}"]`);
    if (label) label.title = text;
  });
  refs.paletteButtons.forEach((button) => {
    button.title = `Применить biome palette ${button.dataset.palette}.`;
  });
}

function bindTextureDrop() {
  document.querySelectorAll(".file-card").forEach((card) => {
    const input = card.querySelector('input[type="file"]');
    if (!input) return;
    const activate = (event) => {
      event.preventDefault();
      card.classList.add("is-dragover");
    };
    const deactivate = () => {
      card.classList.remove("is-dragover");
    };
    card.addEventListener("dragenter", activate);
    card.addEventListener("dragover", activate);
    card.addEventListener("dragleave", deactivate);
    card.addEventListener("drop", (event) => {
      event.preventDefault();
      deactivate();
      const [file] = [...(event.dataTransfer?.files || [])];
      if (!file) return;
      const transfer = new DataTransfer();
      transfer.items.add(file);
      input.files = transfer.files;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    });
  });
}

function createSnapshotFromMap() {
  return state.map.cells.slice();
}

function restoreMapSnapshot(snapshot) {
  state.map.cells = snapshot.slice();
}

function pushHistorySnapshot(snapshot) {
  state.history.past.push(snapshot);
  if (state.history.past.length > state.history.limit) {
    state.history.past.shift();
  }
  state.history.future = [];
  updateHistoryButtons();
}

function beginHistoryStroke() {
  if (!state.history.strokeSnapshot) {
    state.history.strokeSnapshot = createSnapshotFromMap();
  }
}

function commitHistoryStroke() {
  const snapshot = state.history.strokeSnapshot;
  state.history.strokeSnapshot = null;
  if (!snapshot) return;
  const next = createSnapshotFromMap();
  const changed = snapshot.some((value, index) => value !== next[index]);
  if (!changed) return;
  pushHistorySnapshot(snapshot);
  persistSessionState();
}

function recordMapMutation(mutator) {
  const before = createSnapshotFromMap();
  mutator();
  const after = createSnapshotFromMap();
  const changed = before.some((value, index) => value !== after[index]);
  if (!changed) return false;
  pushHistorySnapshot(before);
  return true;
}

function updateHistoryButtons() {
  if (refs.undoMap) refs.undoMap.disabled = state.history.past.length === 0;
  if (refs.redoMap) refs.redoMap.disabled = state.history.future.length === 0;
}

function markDirty(group) {
  switch (group) {
    case "shape":
      state.dirty.shape = true;
      state.dirty.previewMode = true;
      state.dirty.gallery = true;
      break;
    case "material":
      state.dirty.material = true;
      state.dirty.previewMode = true;
      state.dirty.gallery = true;
      state.dirty.swatches = true;
      break;
    case "color":
      state.dirty.color = true;
      state.dirty.previewMode = true;
      state.dirty.gallery = true;
      state.dirty.swatches = true;
      break;
    case "variants":
      state.dirty.variants = true;
      state.dirty.previewMode = true;
      state.dirty.gallery = true;
      state.dirty.stats = true;
      state.dirty.swatches = true;
      break;
    case "map":
      state.dirty.map = true;
      break;
    case "previewMode":
      state.dirty.previewMode = true;
      state.dirty.gallery = true;
      break;
    case "gallery":
      state.dirty.gallery = true;
      break;
    case "swatches":
      state.dirty.swatches = true;
      break;
    case "all":
      Object.keys(state.dirty).forEach((key) => {
        state.dirty[key] = true;
      });
      break;
    default:
      break;
  }
}

function clearCompositeCache(target = state.generated) {
  if (!target?.previewCompositeCache) return;
  target.previewCompositeCache.forEach(releaseCanvas);
  target.previewCompositeCache.clear();
}

function applyContrast01(value, contrastPercent) {
  const contrast = contrastPercent / 100;
  return clamp((value - 0.5) * contrast + 0.5, 0, 1);
}

function scaleColor(color, factor) {
  return [
    clamp(Math.round(color[0] * factor), 0, 255),
    clamp(Math.round(color[1] * factor), 0, 255),
    clamp(Math.round(color[2] * factor), 0, 255)
  ];
}

function multiplyTint(sampled, tint) {
  return [
    clamp(Math.round(sampled[0] * (tint[0] / 255)), 0, 255),
    clamp(Math.round(sampled[1] * (tint[1] / 255)), 0, 255),
    clamp(Math.round(sampled[2] * (tint[2] / 255)), 0, 255)
  ];
}

function blendColors(source, target, opacityPercent) {
  const t = clamp(opacityPercent / 100, 0, 1);
  return [
    clamp(Math.round(lerp(source[0], target[0], t)), 0, 255),
    clamp(Math.round(lerp(source[1], target[1], t)), 0, 255),
    clamp(Math.round(lerp(source[2], target[2], t)), 0, 255)
  ];
}

function applyTintToSample(sampled, tint, opacityPercent) {
  return blendColors(sampled, multiplyTint(sampled, tint), opacityPercent);
}

function normalizeVector(x, y, z) {
  const length = Math.hypot(x, y, z) || 1;
  return { x: x / length, y: y / length, z: z / length };
}

function valueNoisePeriodic(x, y, seed, periodX, periodY) {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = x - x0;
  const ty = y - y0;
  const sx = smoothstep(0, 1, tx);
  const sy = smoothstep(0, 1, ty);
  const v00 = hash2D(mod(x0, periodX), mod(y0, periodY), seed);
  const v10 = hash2D(mod(x0 + 1, periodX), mod(y0, periodY), seed);
  const v01 = hash2D(mod(x0, periodX), mod(y0 + 1, periodY), seed);
  const v11 = hash2D(mod(x0 + 1, periodX), mod(y0 + 1, periodY), seed);
  return lerp(lerp(v00, v10, sx), lerp(v01, v11, sx), sy);
}

function fbmPeriodic(x, y, octaves, seed, periodX, periodY) {
  let amplitude = 1;
  let frequency = 1;
  let sum = 0;
  let weight = 0;
  for (let index = 0; index < octaves; index += 1) {
    sum += valueNoisePeriodic(
      x * frequency,
      y * frequency,
      seed + index * 17,
      Math.max(1, Math.round(periodX * frequency)),
      Math.max(1, Math.round(periodY * frequency))
    ) * amplitude;
    weight += amplitude;
    amplitude *= 0.5;
    frequency *= 2;
  }
  return weight ? sum / weight : 0;
}

function ridgeNoisePeriodic(x, y, octaves, seed, periodX, periodY) {
  return 1 - Math.abs(fbmPeriodic(x, y, octaves, seed, periodX, periodY) * 2 - 1);
}

function samplePeriodicNoisePx(x, y, cellSize, octaves, seed, width, height) {
  const scale = Math.max(1, cellSize);
  return fbmPeriodic(
    x / scale,
    y / scale,
    octaves,
    seed,
    Math.max(1, Math.round(width / scale)),
    Math.max(1, Math.round(height / scale))
  );
}

function samplePeriodicRidgePx(x, y, cellSize, octaves, seed, width, height) {
  const scale = Math.max(1, cellSize);
  return ridgeNoisePeriodic(
    x / scale,
    y / scale,
    octaves,
    seed,
    Math.max(1, Math.round(width / scale)),
    Math.max(1, Math.round(height / scale))
  );
}

function periodicDelta(a, b, period) {
  let delta = a - b;
  if (delta > period * 0.5) delta -= period;
  if (delta < -period * 0.5) delta += period;
  return delta;
}

function circleFieldPeriodic(x, y, gridCount, sizePx, seed, width, height) {
  const cells = Math.max(2, gridCount);
  const cellWidth = width / cells;
  const cellHeight = height / cells;
  const ix = Math.floor(x / cellWidth);
  const iy = Math.floor(y / cellHeight);
  let strength = 0;

  for (let oy = -1; oy <= 1; oy += 1) {
    for (let ox = -1; ox <= 1; ox += 1) {
      const cellX = mod(ix + ox, cells);
      const cellY = mod(iy + oy, cells);
      const centerX = (cellX + hash2D(cellX * 2 + 5, cellY * 2 + 11, seed)) * cellWidth;
      const centerY = (cellY + hash2D(cellX * 2 + 13, cellY * 2 + 17, seed + 37)) * cellHeight;
      const radius = Math.max(1.25, sizePx * lerp(0.65, 1.25, hash2D(cellX * 5, cellY * 7, seed + 73)));
      const dx = periodicDelta(x, centerX, width);
      const dy = periodicDelta(y, centerY, height);
      const distance = Math.hypot(dx, dy);
      const value = 1 - smoothstep(radius * 0.25, radius, distance);
      strength = Math.max(strength, value);
    }
  }

  return strength;
}

function lineFieldPeriodic(x, y, lineCount, thicknessPx, seed, width, height, orientation) {
  const count = Math.max(1, lineCount);
  const axisValue = orientation === "vertical" ? x / width : y / height;
  const otherValue = orientation === "vertical" ? y : x;
  const warp = (samplePeriodicNoisePx(otherValue, axisValue * 127, 42, 2, seed + 19, orientation === "vertical" ? height : width, 127) - 0.5) * 1.4;
  const wave = Math.abs(Math.sin(axisValue * Math.PI * 2 * count + warp + hash2D(seed, count, 91) * Math.PI * 2));
  const threshold = clamp(thicknessPx / (orientation === "vertical" ? width : height), 0.01, 0.18);
  return 1 - smoothstep(0, threshold, wave);
}

function arrayFilled(length, value) {
  const array = new Uint8Array(length);
  array.fill(value);
  return array;
}

function buildScalarCanvas(values, alpha, width, height) {
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(width, height);
  for (let index = 0; index < values.length; index += 1) {
    const value = clamp(Math.round(values[index] * 255), 0, 255);
    const out = index * 4;
    image.data[out] = value;
    image.data[out + 1] = value;
    image.data[out + 2] = value;
    image.data[out + 3] = alpha ? alpha[index] : 255;
  }
  ctx.putImageData(image, 0, 0);
  return canvas;
}

function buildRgbCanvas(redValues, greenValues, blueValues, alpha, width, height) {
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(width, height);
  const count = width * height;
  for (let index = 0; index < count; index += 1) {
    const out = index * 4;
    image.data[out] = clamp(Math.round(redValues[index] * 255), 0, 255);
    image.data[out + 1] = clamp(Math.round(greenValues[index] * 255), 0, 255);
    image.data[out + 2] = clamp(Math.round(blueValues[index] * 255), 0, 255);
    image.data[out + 3] = alpha ? alpha[index] : 255;
  }
  ctx.putImageData(image, 0, 0);
  return canvas;
}

function sampleScalar(values, width, height, x, y) {
  const sx = mod(Math.floor(x), width);
  const sy = mod(Math.floor(y), height);
  return values[sy * width + sx];
}

function normalFromHeightField(values, alpha, width, height, x, y, strength) {
  const sx = mod(x, width);
  const sy = mod(y, height);
  const index = sy * width + sx;
  if (alpha && !alpha[index]) return { x: 0, y: 0, z: 1 };

  const left = sampleScalar(values, width, height, x - 1, y);
  const right = sampleScalar(values, width, height, x + 1, y);
  const up = sampleScalar(values, width, height, x, y - 1);
  const down = sampleScalar(values, width, height, x, y + 1);
  return normalizeVector((left - right) * strength, (up - down) * strength, 1);
}

function buildNormalCanvas(values, alpha, width, height, strength) {
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(width, height);

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const index = y * width + x;
      const out = index * 4;
      if (alpha && !alpha[index]) {
        image.data[out] = 128;
        image.data[out + 1] = 128;
        image.data[out + 2] = 255;
        image.data[out + 3] = 0;
        continue;
      }
      const normal = normalFromHeightField(values, alpha, width, height, x, y, strength);
      image.data[out] = clamp(Math.round((normal.x * 0.5 + 0.5) * 255), 0, 255);
      image.data[out + 1] = clamp(Math.round((normal.y * 0.5 + 0.5) * 255), 0, 255);
      image.data[out + 2] = clamp(Math.round((normal.z * 0.5 + 0.5) * 255), 0, 255);
      image.data[out + 3] = alpha ? alpha[index] : 255;
    }
  }

  ctx.putImageData(image, 0, 0);
  return canvas;
}

function overlayBlend01(base, blend) {
  return base < 0.5
    ? 2 * base * blend
    : 1 - 2 * (1 - base) * (1 - blend);
}

function softLightBlend01(base, blend) {
  const g = base <= 0.25
    ? ((16 * base - 12) * base + 4) * base
    : Math.sqrt(base);
  return blend <= 0.5
    ? base - (1 - 2 * blend) * base * (1 - base)
    : base + (2 * blend - 1) * (g - base);
}

function blendMaterialLayerValue(base, sample, blend, strength) {
  const t = clamp(strength / 100, 0, 1);
  if (!t) return base;
  switch (blend) {
    case "add":
      return clamp(base + (sample - 0.5) * t * 1.15, 0, 1);
    case "multiply":
      return clamp(lerp(base, base * (0.52 + sample * 0.96), t), 0, 1);
    case "replace":
      return clamp(lerp(base, sample, t), 0, 1);
    case "softLight":
      return clamp(lerp(base, softLightBlend01(base, sample), t), 0, 1);
    case "overlay":
    default:
      return clamp(lerp(base, overlayBlend01(base, sample), t), 0, 1);
  }
}

function layerAppliesToKind(layer, kind) {
  return layer.mask === "both" || layer.mask === kind;
}

function periodicDirectionalMask(x, y, params, width, height, phase = 0) {
  const angle = (((params.sunAzimuth ?? 315) + phase) % 360) * (Math.PI / 180);
  const dirX = Math.cos(angle);
  const dirY = Math.sin(angle);
  const waveX = Math.cos((x / Math.max(1, width)) * Math.PI * 2);
  const waveY = Math.sin((y / Math.max(1, height)) * Math.PI * 2);
  const directional = clamp((waveX * dirX + waveY * dirY + 1) * 0.5, 0, 1);
  const breakup = samplePeriodicNoisePx(x, y, 56, 2, params.seed + 821 + Math.round(phase), width, height);
  return clamp(lerp(directional, breakup, 0.24), 0, 1);
}

function sampleMaterialLayer(type, kind, x, y, params, width, height) {
  switch (type) {
    case "brick": {
      const rows = kind === "face" ? 12 : 10;
      const cols = kind === "face" ? 8 : 10;
      const brickHeight = height / rows;
      const brickWidth = width / cols;
      const row = Math.floor(y / brickHeight);
      const offset = row % 2 ? brickWidth * 0.5 : 0;
      const localX = mod(x + offset, brickWidth);
      const localY = mod(y, brickHeight);
      const edge = Math.min(localX, brickWidth - localX, localY, brickHeight - localY);
      const mortar = 1 - smoothstep(0.6, 2.6, edge);
      const grain = samplePeriodicNoisePx(x, y, 18, 3, params.seed + 701, width, height);
      const chips = samplePeriodicRidgePx(x, y, 26, 2, params.seed + 711, width, height);
      const value = clamp(0.7 + (grain - 0.5) * 0.2 - mortar * 0.6 - (chips - 0.5) * 0.08, 0, 1);
      const heightValue = clamp(0.82 - mortar * 0.78 - chips * 0.06, 0, 1);
      return { value, height: heightValue };
    }
    case "plank": {
      const count = kind === "face" ? 11 : 7;
      const axisSize = kind === "face" ? width : height;
      const boardSize = axisSize / count;
      const axis = kind === "face" ? x : y;
      const cross = kind === "face" ? y : x;
      const local = mod(axis, boardSize);
      const seam = 1 - smoothstep(0.4, 2.2, Math.min(local, boardSize - local));
      const grain = samplePeriodicNoisePx(axis, cross, 16, 3, params.seed + 721, axisSize, kind === "face" ? height : width);
      const knots = circleFieldPeriodic(x, y, kind === "face" ? 5 : 4, 8, params.seed + 731, width, height);
      const value = clamp(0.56 + (grain - 0.5) * 0.34 - seam * 0.44 + knots * 0.12, 0, 1);
      const heightValue = clamp(0.62 + (grain - 0.5) * 0.14 - seam * 0.68 + knots * 0.16, 0, 1);
      return { value, height: heightValue };
    }
    case "stoneCluster": {
      const stones = circleFieldPeriodic(x, y, 10, kind === "face" ? 7.5 : 6.5, params.seed + 741, width, height);
      const ridge = samplePeriodicRidgePx(x, y, 24, 3, params.seed + 751, width, height);
      const dust = samplePeriodicNoisePx(x, y, 22, 2, params.seed + 761, width, height);
      const value = clamp(0.5 + stones * 0.28 + (ridge - 0.5) * 0.12 + (dust - 0.5) * 0.1, 0, 1);
      const heightValue = clamp(0.54 + stones * 0.34 + (dust - 0.5) * 0.08, 0, 1);
      return { value, height: heightValue };
    }
    case "snowDrift": {
      const drift = samplePeriodicNoisePx(x, y, 74, 4, params.seed + 771, width, height);
      const sparkle = samplePeriodicRidgePx(x, y, 18, 2, params.seed + 781, width, height);
      const northBias = periodicDirectionalMask(x, y, params, width, height, -90);
      const value = clamp(0.66 + drift * 0.24 + northBias * 0.1 + sparkle * 0.04, 0, 1);
      const heightValue = clamp(0.62 + drift * 0.26 + northBias * 0.16, 0, 1);
      return { value, height: heightValue };
    }
    case "cracks": {
      const main = lineFieldPeriodic(x, y, kind === "face" ? 4 : 3, 1.4, params.seed + 791, width, height, kind === "face" ? "vertical" : "horizontal");
      const branch = lineFieldPeriodic(x + 11, y + 7, kind === "face" ? 3 : 4, 1.1, params.seed + 801, width, height, kind === "face" ? "horizontal" : "vertical");
      const warp = samplePeriodicNoisePx(x, y, 30, 3, params.seed + 811, width, height);
      const crack = clamp(main * 0.82 + branch * 0.46 + Math.max(0, warp - 0.7) * 1.2, 0, 1);
      const value = clamp(0.5 - crack * 0.82 + (warp - 0.5) * 0.06, 0, 1);
      const heightValue = clamp(0.56 - crack * 0.96, 0, 1);
      return { value, height: heightValue };
    }
    case "moss": {
      const patches = samplePeriodicNoisePx(x, y, 42, 4, params.seed + 831, width, height);
      const humidity = periodicDirectionalMask(x, y, params, width, height, 135);
      const fibrous = samplePeriodicRidgePx(x, y, 18, 3, params.seed + 841, width, height);
      const growth = clamp(patches * 0.72 + humidity * 0.28, 0, 1);
      const value = clamp(0.44 + growth * 0.24 + fibrous * 0.08, 0, 1);
      const heightValue = clamp(0.46 + growth * 0.18 + fibrous * 0.12, 0, 1);
      return { value, height: heightValue };
    }
    case "rivets": {
      const columns = kind === "face" ? 8 : 6;
      const rows = kind === "face" ? 10 : 6;
      const cellWidth = width / columns;
      const cellHeight = height / rows;
      const localX = mod(x, cellWidth) - cellWidth * 0.5;
      const localY = mod(y, cellHeight) - cellHeight * 0.5;
      const rivet = 1 - smoothstep(cellWidth * 0.08, cellWidth * 0.24, Math.hypot(localX, localY));
      const panel = samplePeriodicRidgePx(x, y, 28, 2, params.seed + 851, width, height);
      const value = clamp(0.54 + panel * 0.06 + rivet * 0.34, 0, 1);
      const heightValue = clamp(0.48 + rivet * 0.46, 0, 1);
      return { value, height: heightValue };
    }
    case "runes": {
      const vertical = lineFieldPeriodic(x, y, 5, 1.25, params.seed + 861, width, height, "vertical");
      const horizontal = lineFieldPeriodic(x + 17, y + 9, 4, 1.05, params.seed + 871, width, height, "horizontal");
      const diagonals = lineFieldPeriodic(x + y * 0.72, y + x * 0.18, 3, 1.15, params.seed + 881, width, height, "vertical");
      const symbol = clamp(vertical * 0.55 + horizontal * 0.35 + diagonals * 0.4 - 0.2, 0, 1);
      const glow = samplePeriodicNoisePx(x, y, 30, 2, params.seed + 891, width, height);
      const value = clamp(0.42 + symbol * 0.42 + glow * 0.08, 0, 1);
      const heightValue = clamp(0.36 + symbol * 0.5, 0, 1);
      return { value, height: heightValue };
    }
    case "puddles": {
      const puddleMask = circleFieldPeriodic(x, y, 6, 16, params.seed + 901, width, height);
      const ripple = samplePeriodicNoisePx(x, y, 20, 3, params.seed + 911, width, height);
      const value = clamp(0.34 + puddleMask * 0.18 + (ripple - 0.5) * 0.06, 0, 1);
      const heightValue = clamp(0.48 - puddleMask * 0.28 + ripple * 0.04, 0, 1);
      return { value, height: heightValue };
    }
    case "debris": {
      const stones = circleFieldPeriodic(x, y, 12, 5, params.seed + 921, width, height);
      const shards = lineFieldPeriodic(x + 13, y + 19, 8, 0.85, params.seed + 931, width, height, "horizontal");
      const dust = samplePeriodicNoisePx(x, y, 22, 2, params.seed + 941, width, height);
      const value = clamp(0.48 + stones * 0.18 + shards * 0.1 + (dust - 0.5) * 0.08, 0, 1);
      const heightValue = clamp(0.5 + stones * 0.24 + shards * 0.14, 0, 1);
      return { value, height: heightValue };
    }
    case "rust": {
      const drips = lineFieldPeriodic(x, y, 6, 1.2, params.seed + 951, width, height, "vertical");
      const oxidation = samplePeriodicNoisePx(x, y, 28, 3, params.seed + 961, width, height);
      const weathering = periodicDirectionalMask(x, y, params, width, height, 45);
      const streaks = clamp(drips * 0.58 + weathering * 0.28 + Math.max(0, oxidation - 0.55) * 0.5, 0, 1);
      const value = clamp(0.46 - streaks * 0.34 + oxidation * 0.1, 0, 1);
      const heightValue = clamp(0.5 - streaks * 0.12 + oxidation * 0.04, 0, 1);
      return { value, height: heightValue };
    }
    case "sand": {
      const phase = (((params.sunAzimuth ?? 315) % 360) * Math.PI) / 180;
      const ripples = 0.5 + 0.5 * Math.sin((((x * Math.cos(phase)) + (y * Math.sin(phase))) / 18) * Math.PI * 2);
      const drift = periodicDirectionalMask(x, y, params, width, height, 0);
      const dust = samplePeriodicNoisePx(x, y, 36, 2, params.seed + 971, width, height);
      const value = clamp(0.56 + (ripples - 0.5) * 0.18 + drift * 0.16 + (dust - 0.5) * 0.08, 0, 1);
      const heightValue = clamp(0.52 + drift * 0.24 + (ripples - 0.5) * 0.12, 0, 1);
      return { value, height: heightValue };
    }
    case "concrete": {
      const speckle = samplePeriodicNoisePx(x, y, 8, 1, params.seed + 981, width, height);
      const macro = samplePeriodicNoisePx(x, y, 52, 3, params.seed + 991, width, height);
      const pits = circleFieldPeriodic(x, y, 18, 2.8, params.seed + 1001, width, height);
      const value = clamp(0.52 + (macro - 0.5) * 0.14 + (speckle - 0.5) * 0.24 - pits * 0.14, 0, 1);
      const heightValue = clamp(0.5 + (macro - 0.5) * 0.08 - pits * 0.18, 0, 1);
      return { value, height: heightValue };
    }
    case "mud": {
      const blobs = circleFieldPeriodic(x, y, 8, 11, params.seed + 1011, width, height);
      const drips = lineFieldPeriodic(x + 9, y + 21, 5, 1.1, params.seed + 1021, width, height, "vertical");
      const wetness = samplePeriodicNoisePx(x, y, 30, 3, params.seed + 1031, width, height);
      const value = clamp(0.42 + blobs * 0.2 - drips * 0.18 + wetness * 0.06, 0, 1);
      const heightValue = clamp(0.54 + blobs * 0.18 - drips * 0.08, 0, 1);
      return { value, height: heightValue };
    }
    case "hex": {
      const scale = 12;
      const a = Math.abs(Math.sin((x / scale) * Math.PI));
      const b = Math.abs(Math.sin(((x * 0.5 + y * 0.8660254) / scale) * Math.PI));
      const c = Math.abs(Math.sin(((-x * 0.5 + y * 0.8660254) / scale) * Math.PI));
      const edge = Math.min(a, b, c);
      const cell = 1 - smoothstep(0.02, 0.16, edge);
      const fill = samplePeriodicNoisePx(x, y, 26, 2, params.seed + 1041, width, height);
      const value = clamp(0.48 + fill * 0.08 - cell * 0.36, 0, 1);
      const heightValue = clamp(0.5 + cell * 0.32, 0, 1);
      return { value, height: heightValue };
    }
    case "cobblestone": {
      const stones = circleFieldPeriodic(x, y, 11, 8, params.seed + 1051, width, height);
      const grout = samplePeriodicRidgePx(x, y, 14, 2, params.seed + 1061, width, height);
      const settle = samplePeriodicNoisePx(x, y, 28, 3, params.seed + 1071, width, height);
      const value = clamp(0.5 + stones * 0.22 - grout * 0.14 + (settle - 0.5) * 0.08, 0, 1);
      const heightValue = clamp(0.5 + stones * 0.28 - grout * 0.08, 0, 1);
      return { value, height: heightValue };
    }
    default:
      return { value: 0.5, height: 0.5 };
  }
}

function directionVectorFromDegrees(angleDegrees) {
  const radians = angleDegrees * (Math.PI / 180);
  return {
    x: Math.cos(radians),
    y: Math.sin(radians)
  };
}

function sampleMaterialLayerPbr(type, kind, sample, params) {
  const coverage = clamp(sample.height * 0.65 + sample.value * 0.35, 0, 1);
  const directional = directionVectorFromDegrees(params.sunAzimuth ?? 315);
  const gravity = { x: 0, y: 1 };

  switch (type) {
    case "brick":
      return { coverage, roughness: 0.82, metallic: 0, aoBias: 0.08, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    case "plank":
      return { coverage, roughness: 0.72, metallic: 0, aoBias: 0.05, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    case "stoneCluster":
      return { coverage, roughness: 0.86, metallic: 0, aoBias: 0.09, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    case "snowDrift":
      return { coverage, roughness: 0.18, metallic: 0, aoBias: 0.06, flowX: directional.x * 0.2, flowY: directional.y * 0.2, emission: 0, emissionColor: [0, 0, 0] };
    case "cracks":
      return { coverage, roughness: 0.92, metallic: 0, aoBias: 0.22, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    case "moss":
      return { coverage, roughness: 0.68, metallic: 0, aoBias: 0.12, flowX: directional.x * 0.08, flowY: directional.y * 0.08, emission: 0, emissionColor: [0, 0, 0] };
    case "rivets":
      return { coverage, roughness: 0.38, metallic: 0.72, aoBias: 0.08, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    case "runes":
      return { coverage, roughness: 0.16, metallic: 0, aoBias: 0.04, flowX: 0, flowY: 0, emission: coverage * 0.78, emissionColor: [0.42, 0.82, 1] };
    case "puddles":
      return { coverage, roughness: 0.05, metallic: 0, aoBias: 0.05, flowX: directional.x * 0.24, flowY: directional.y * 0.24, emission: 0, emissionColor: [0, 0, 0] };
    case "debris":
      return { coverage, roughness: 0.88, metallic: 0.12, aoBias: 0.14, flowX: gravity.x * 0.08, flowY: gravity.y * 0.08, emission: 0, emissionColor: [0, 0, 0] };
    case "rust":
      return { coverage, roughness: 0.76, metallic: 0.16, aoBias: 0.12, flowX: gravity.x * 0.18, flowY: gravity.y * 0.28, emission: 0, emissionColor: [0, 0, 0] };
    case "sand":
      return { coverage, roughness: 0.91, metallic: 0, aoBias: 0.07, flowX: directional.x * 0.34, flowY: directional.y * 0.34, emission: 0, emissionColor: [0, 0, 0] };
    case "concrete":
      return { coverage, roughness: 0.84, metallic: 0, aoBias: 0.08, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    case "mud":
      return { coverage, roughness: 0.62, metallic: 0, aoBias: 0.1, flowX: gravity.x * 0.14, flowY: gravity.y * 0.22, emission: 0, emissionColor: [0, 0, 0] };
    case "hex":
      return { coverage, roughness: 0.2, metallic: 0.88, aoBias: 0.06, flowX: 0, flowY: 0, emission: coverage * 0.34, emissionColor: [0.96, 0.74, 0.3] };
    case "cobblestone":
      return { coverage, roughness: 0.86, metallic: 0, aoBias: 0.1, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
    default:
      return { coverage, roughness: kind === "top" ? 0.74 : 0.82, metallic: 0, aoBias: 0.05, flowX: 0, flowY: 0, emission: 0, emissionColor: [0, 0, 0] };
  }
}

function buildLegacyMaterialBase(kind, params) {
  const width = MATERIAL_EXPORT_SIZE;
  const height = MATERIAL_EXPORT_SIZE;
  const values = new Float32Array(width * height);
  if (kind === "top") {
    const macroStrength = params.topMacroStrength / 100;
    const microStrength = params.topMicroNoise / 100;
    const pebbleDensity = Math.max(2, Math.round(params.topPebbleDensity));
    const pebbleSize = Math.max(1, params.topPebbleSize);
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const index = y * width + x;
        const macro = samplePeriodicNoisePx(x, y, params.topMacroScale, 4, params.seed + 101, width, height);
        const macroRidge = samplePeriodicRidgePx(x, y, Math.max(18, params.topMacroScale * 0.45), 3, params.seed + 111, width, height);
        const micro = samplePeriodicNoisePx(x, y, 12, 3, params.seed + 121, width, height);
        const pebbles = circleFieldPeriodic(x, y, pebbleDensity, pebbleSize * 1.4, params.seed + 131, width, height);
        const dust = samplePeriodicNoisePx(x, y, 34, 2, params.seed + 141, width, height);
        let value = 0.46;
        value += (macro - 0.5) * (0.85 * macroStrength);
        value += (macroRidge - 0.5) * 0.2;
        value += (micro - 0.5) * (0.34 * microStrength);
        value += pebbles * (0.08 + pebbleSize * 0.012);
        value += (dust - 0.5) * 0.12;
        values[index] = applyContrast01(clamp(value, 0, 1), params.topContrast);
      }
    }
  } else {
    const strataStrength = params.faceStrataStrength / 100;
    const fractureStrength = params.faceVerticalFractures / 100;
    const chipsStrength = params.faceChips / 100;
    const erosionStrength = params.faceErosion / 100;
    const strataCount = Math.max(2, Math.round(2 + strataStrength * 7));
    const fractureCount = Math.max(1, Math.round(1 + fractureStrength * 10));
    const chipCells = Math.max(3, Math.round(4 + chipsStrength * 14));

    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const index = y * width + x;
        const strataWarp = (samplePeriodicNoisePx(x, y, 56, 2, params.seed + 201, width, height) - 0.5) * 1.5;
        const strata = 0.5 + 0.5 * Math.sin((y / height) * Math.PI * 2 * strataCount + strataWarp);
        const fractures = lineFieldPeriodic(x, y, fractureCount, 2 + fractureStrength * 4, params.seed + 211, width, height, "vertical");
        const chips = circleFieldPeriodic(x, y, chipCells, 2.6 + chipsStrength * 6, params.seed + 221, width, height);
        const erosionNoise = samplePeriodicNoisePx(x, y, 40, 3, params.seed + 231, width, height);
        const erosionGradient = smoothstep(0, 1, y / Math.max(1, height - 1));
        let value = 0.5;
        value += (strata - 0.5) * (0.62 * strataStrength);
        value -= fractures * (0.42 * fractureStrength);
        value -= chips * (0.24 * chipsStrength);
        value += (erosionNoise - 0.5) * (0.34 * erosionStrength);
        value -= erosionGradient * (0.08 * erosionStrength);
        values[index] = applyContrast01(clamp(value, 0, 1), params.faceContrast);
      }
    }
  }

  const alpha = arrayFilled(values.length, 255);
  return {
    width,
    height,
    values,
    heightValues: values.slice(),
    alpha
  };
}

function buildLayeredMaterialMap(kind, params) {
  const base = buildLegacyMaterialBase(kind, params);
  const { width, height, values, heightValues, alpha } = base;
  const count = values.length;
  const roughnessValues = new Float32Array(count);
  const metallicValues = new Float32Array(count);
  const aoBiasValues = new Float32Array(count);
  const emissionRValues = new Float32Array(count);
  const emissionGValues = new Float32Array(count);
  const emissionBValues = new Float32Array(count);
  const flowXValues = new Float32Array(count);
  const flowYValues = new Float32Array(count);

  for (let index = 0; index < count; index += 1) {
    roughnessValues[index] = clamp((kind === "top" ? 0.74 : 0.84) + (0.5 - values[index]) * 0.18, 0, 1);
    metallicValues[index] = 0;
  }

  state.materialLayers.forEach((layer) => {
    if (!layer.enabled || !layerAppliesToKind(layer, kind)) return;
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const index = y * width + x;
        const sample = sampleMaterialLayer(layer.type, kind, x, y, params, width, height);
        const pbr = sampleMaterialLayerPbr(layer.type, kind, sample, params);
        const layerMix = clamp((layer.strength / 100) * pbr.coverage, 0, 1);
        values[index] = blendMaterialLayerValue(values[index], sample.value, layer.blend, layer.strength);
        const heightMix = clamp((layer.heightContribution / 100) * (layer.strength / 100), 0, 1);
        heightValues[index] = clamp(lerp(heightValues[index], sample.height, heightMix), 0, 1);
        roughnessValues[index] = clamp(lerp(roughnessValues[index], pbr.roughness, layerMix), 0, 1);
        metallicValues[index] = clamp(lerp(metallicValues[index], pbr.metallic, layerMix), 0, 1);
        aoBiasValues[index] = clamp(aoBiasValues[index] + pbr.aoBias * layerMix, -0.45, 0.45);
        emissionRValues[index] = clamp(emissionRValues[index] + pbr.emissionColor[0] * pbr.emission * layerMix, 0, 1);
        emissionGValues[index] = clamp(emissionGValues[index] + pbr.emissionColor[1] * pbr.emission * layerMix, 0, 1);
        emissionBValues[index] = clamp(emissionBValues[index] + pbr.emissionColor[2] * pbr.emission * layerMix, 0, 1);
        flowXValues[index] = clamp(lerp(flowXValues[index], pbr.flowX, layerMix), -1, 1);
        flowYValues[index] = clamp(lerp(flowYValues[index], pbr.flowY, layerMix), -1, 1);
      }
    }
  });

  const occlusionValues = new Float32Array(count);
  for (let index = 0; index < count; index += 1) {
    const relief = Math.abs(heightValues[index] - 0.5) * 2;
    occlusionValues[index] = clamp(0.92 - relief * 0.16 - aoBiasValues[index], 0, 1);
  }

  const normalStrength = kind === "top" ? 0.95 : 0.9;
  return {
    width,
    height,
    values,
    heightValues,
    roughnessValues,
    metallicValues,
    occlusionValues,
    emissionRValues,
    emissionGValues,
    emissionBValues,
    flowXValues,
    flowYValues,
    alpha,
    canvas: buildScalarCanvas(values, alpha, width, height),
    normalCanvas: buildNormalCanvas(heightValues, alpha, width, height, normalStrength),
    ormCanvas: buildRgbCanvas(occlusionValues, roughnessValues, metallicValues, alpha, width, height),
    emissionCanvas: buildRgbCanvas(emissionRValues, emissionGValues, emissionBValues, alpha, width, height),
    flowCanvas: buildRgbCanvas(
      Array.from(flowXValues, (value) => clamp(value * 0.5 + 0.5, 0, 1)),
      Array.from(flowYValues, (value) => clamp(value * 0.5 + 0.5, 0, 1)),
      Array.from(flowXValues, (value, index) => clamp(Math.hypot(value, flowYValues[index]), 0, 1)),
      alpha,
      width,
      height
    )
  };
}

function buildTopMaterialMap(params) {
  return buildLayeredMaterialMap("top", params);
}

function buildFaceMaterialMap(params) {
  return buildLayeredMaterialMap("face", params);
}

function buildMaterialAlbedoCanvas(kind, params) {
  const width = MATERIAL_EXPORT_SIZE;
  const height = MATERIAL_EXPORT_SIZE;
  const canvas = createCanvas(width, height);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(width, height);
  const offsets = { ox: 0, oy: 0, brightness: 1 };
  const zone = kind === "face" ? "face" : "top";

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const color = buildSurfaceColor(kind, zone, x, y, params, offsets);
      const out = (y * width + x) * 4;
      image.data[out] = color[0];
      image.data[out + 1] = color[1];
      image.data[out + 2] = color[2];
      image.data[out + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);
  return canvas;
}

function getParams() {
  return {
    noisePreset: refs.noisePreset.value,
    tileSize: Number(refs.tileSize.value),
    heightPx: Number(refs.heightPx.value),
    lipPx: Number(refs.lipPx.value),
    backRimRatio: Number(refs.backRimRatio.value),
    northRimThickness: Number(refs.northRimThickness.value),
    northHeightPx: Number(refs.northHeightPx.value),
    eastHeightPx: Number(refs.eastHeightPx.value),
    westHeightPx: Number(refs.westHeightPx.value),
    roughness: Number(refs.roughness.value),
    faceSlope: Number(refs.faceSlope.value),
    innerCornerMode: refs.innerCornerMode.value,
    crownBevel: Number(refs.crownBevel.value),
    outerChamfer: Number(refs.outerChamfer.value),
    baseErosion: Number(refs.baseErosion.value),
    cornerOverrideNE: refs.cornerOverrideNE.value,
    cornerOverrideNW: refs.cornerOverrideNW.value,
    cornerOverrideSE: refs.cornerOverrideSE.value,
    cornerOverrideSW: refs.cornerOverrideSW.value,
    normalStrength: Number(refs.normalStrength.value),
    textureScale: Number(refs.textureScale.value),
    variants: Number(refs.variants.value),
    tintJitter: Number(refs.tintJitter.value),
    seed: Number(refs.seed.value),
    topTint: refs.topTint.value,
    faceTint: refs.faceTint.value,
    baseTint: refs.baseTint.value,
    topTintOpacity: Number(refs.topTintOpacity.value),
    faceTintOpacity: Number(refs.faceTintOpacity.value),
    baseTintOpacity: Number(refs.baseTintOpacity.value),
    topMacroScale: Number(refs.topMacroScale.value),
    topMacroStrength: Number(refs.topMacroStrength.value),
    topPebbleDensity: Number(refs.topPebbleDensity.value),
    topPebbleSize: Number(refs.topPebbleSize.value),
    topMicroNoise: Number(refs.topMicroNoise.value),
    topContrast: Number(refs.topContrast.value),
    faceStrataStrength: Number(refs.faceStrataStrength.value),
    faceVerticalFractures: Number(refs.faceVerticalFractures.value),
    faceChips: Number(refs.faceChips.value),
    faceErosion: Number(refs.faceErosion.value),
    faceContrast: Number(refs.faceContrast.value),
    sunAzimuth: Number(refs.sunAzimuth.value)
  };
}

function formatRangeValue(id, value) {
  if (id === "backRimRatio") return Number(value).toFixed(2);
  if (id === "sunAzimuth") return `${value}°`;
  return String(value);
}

function updateRangeLabels() {
  RANGE_IDS.forEach((id) => {
    const label = document.getElementById(`${id}Value`);
    if (label) label.textContent = formatRangeValue(id, refs[id].value);
  });
}

function applyPreset(name) {
  state.preset = name;
  state.customPresetName = "";
  resetMaterialLayersForPreset(name);
  if (refs.noisePreset && PRESET_NOISE_PROFILES[name]) {
    refs.noisePreset.value = PRESET_NOISE_PROFILES[name];
  }
  const preset = PRESETS[name];
  Object.entries(preset).forEach(([key, value]) => {
    if (refs[key]) refs[key].value = String(value);
  });
  refs.presetButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.preset === name);
  });
  refs.customPresetName.value = "";
  refs.customPresetSelect.value = "";
  updateRangeLabels();
  refreshPaletteButtons();
  renderMaterialLayerControls();
}

function initMap() {
  state.map.cells = new Array(state.map.width * state.map.height).fill(0);
}

function setMapCell(x, y, value) {
  if (x < 0 || y < 0 || x >= state.map.width || y >= state.map.height) return;
  state.map.cells[y * state.map.width + x] = value ? 1 : 0;
}

function getMapCell(x, y) {
  if (x < 0 || y < 0 || x >= state.map.width || y >= state.map.height) return 0;
  return state.map.cells[y * state.map.width + x];
}

function createSignature(n, ne, e, se, s, sw, w, nw) {
  const openN = n ? 0 : 1;
  const openE = e ? 0 : 1;
  const openS = s ? 0 : 1;
  const openW = w ? 0 : 1;
  const notchNE = n && e && !ne ? 1 : 0;
  const notchSE = s && e && !se ? 1 : 0;
  const notchSW = s && w && !sw ? 1 : 0;
  const notchNW = n && w && !nw ? 1 : 0;
  return {
    key: `${openN}${openE}${openS}${openW}|${notchNE}${notchSE}${notchSW}${notchNW}`,
    openN: Boolean(openN),
    openE: Boolean(openE),
    openS: Boolean(openS),
    openW: Boolean(openW),
    notchNE: Boolean(notchNE),
    notchSE: Boolean(notchSE),
    notchSW: Boolean(notchSW),
    notchNW: Boolean(notchNW),
    edgeCount: openN + openE + openS + openW,
    notchCount: notchNE + notchSE + notchSW + notchNW
  };
}

function describeSignature(signature) {
  const edges = [];
  const notches = [];
  if (signature.openN) edges.push("N");
  if (signature.openE) edges.push("E");
  if (signature.openS) edges.push("S");
  if (signature.openW) edges.push("W");
  if (signature.notchNE) notches.push("NE");
  if (signature.notchSE) notches.push("SE");
  if (signature.notchSW) notches.push("SW");
  if (signature.notchNW) notches.push("NW");
  return `${edges.length ? `open ${edges.join("/")}` : "solid"} · ${notches.length ? `cut ${notches.join("/")}` : "no inner cuts"}`;
}

function buildCatalog() {
  const unique = new Map();
  for (let mask = 0; mask < 256; mask += 1) {
    const signature = createSignature(
      Boolean(mask & 1),
      Boolean(mask & 2),
      Boolean(mask & 4),
      Boolean(mask & 8),
      Boolean(mask & 16),
      Boolean(mask & 32),
      Boolean(mask & 64),
      Boolean(mask & 128)
    );
    if (!unique.has(signature.key)) unique.set(signature.key, signature);
  }

  state.catalog = [...unique.values()]
    .sort((a, b) => {
      if (a.edgeCount !== b.edgeCount) return a.edgeCount - b.edgeCount;
      if (a.notchCount !== b.notchCount) return a.notchCount - b.notchCount;
      return a.key.localeCompare(b.key);
    })
    .map((signature, index) => ({ ...signature, index, label: describeSignature(signature) }));
  state.catalogByKey = new Map(state.catalog.map((signature) => [signature.key, signature]));
}

function smoothArray(array) {
  const copy = array.slice();
  for (let index = 1; index < array.length - 1; index += 1) {
    array[index] = (copy[index - 1] + copy[index] * 2 + copy[index + 1]) / 4;
  }
}

function backRimThickness(params) {
  return clamp(
    Math.round((params.northHeightPx ?? 0) || (params.lipPx * params.backRimRatio + params.northRimThickness)),
    1,
    Math.max(1, Math.floor(params.tileSize * 0.25))
  );
}

function sideHeightPx(params, side) {
  if (side === "north") return backRimThickness(params);
  if (side === "south") return clamp(params.heightPx, 1, Math.max(1, Math.floor(params.tileSize * 0.48)));
  if (side === "east") return clamp((params.eastHeightPx ?? 0) || params.lipPx, 1, Math.max(1, Math.floor(params.tileSize * 0.3)));
  if (side === "west") return clamp((params.westHeightPx ?? 0) || params.lipPx, 1, Math.max(1, Math.floor(params.tileSize * 0.3)));
  return params.lipPx;
}

function resolveCornerMode(params, cornerId) {
  const key = `cornerOverride${cornerId}`;
  const value = params[key];
  if (value && value !== "global") return value;
  return params.innerCornerMode;
}

function buildProfiles(signature, variantSeed, params) {
  const size = params.tileSize;
  const roughness = params.roughness / 100;
  const profileScale = state.preset === "wall" ? 1.2 : state.preset === "earth" ? 2 : 3.5;
  const driftStrength = roughness * profileScale;
  const northHeight = sideHeightPx(params, "north");
  const southHeight = sideHeightPx(params, "south");
  const westHeight = sideHeightPx(params, "west");
  const eastHeight = sideHeightPx(params, "east");
  const north = new Float32Array(size);
  const south = new Float32Array(size);
  const west = new Float32Array(size);
  const east = new Float32Array(size);

  for (let index = 0; index < size; index += 1) {
    const t = index / size;
    const northNoise = (fbmPeriodic(t * 7.2, 1.4, 3, variantSeed + 17, 16, 16) - 0.5) * 2;
    const southNoise = (fbmPeriodic(t * 6.6, 3.1, 3, variantSeed + 23, 16, 16) - 0.5) * 2;
    const westNoise = (fbmPeriodic(4.2, t * 6.1, 3, variantSeed + 31, 16, 16) - 0.5) * 2;
    const eastNoise = (fbmPeriodic(6.8, t * 6.7, 3, variantSeed + 43, 16, 16) - 0.5) * 2;
    north[index] = signature.openN ? clamp(northHeight + northNoise * driftStrength, 1, size * 0.28) : 0;
    south[index] = signature.openS ? clamp(southHeight + southNoise * driftStrength * 1.2, 2, size * 0.48) : 0;
    west[index] = signature.openW ? clamp(westHeight + westNoise * driftStrength, 1, size * 0.3) : 0;
    east[index] = signature.openE ? clamp(eastHeight + eastNoise * driftStrength, 1, size * 0.3) : 0;
  }

  for (let pass = 0; pass < 2; pass += 1) {
    smoothArray(north);
    smoothArray(south);
    smoothArray(west);
    smoothArray(east);
  }

  const minSpan = Math.max(8, Math.round(size * 0.22));
  for (let index = 0; index < size; index += 1) {
    if (size - north[index] - south[index] < minSpan) south[index] = Math.max(2, size - north[index] - minSpan);
    if (size - west[index] - east[index] < minSpan) east[index] = Math.max(1, size - west[index] - minSpan);
  }

  return { north, south, west, east };
}

function variantOffsets(signature, variantIndex, params) {
  const salt = signature.index * 92821 + variantIndex * 15331 + params.seed;
  return {
    ox: Math.floor(hash2D(signature.index, variantIndex, salt) * 4096),
    oy: Math.floor(hash2D(signature.index + 11, variantIndex + 9, salt + 7) * 4096),
    brightness: 1 + (hash2D(signature.index + 29, variantIndex + 31, salt + 19) - 0.5) * (params.tintJitter / 100)
  };
}

function classifyPixel(signature, profiles, params, x, y) {
  const left = profiles.west[y];
  const right = params.tileSize - 1 - profiles.east[y];
  const top = profiles.north[x];
  const bottom = params.tileSize - 1 - profiles.south[x];
  const inside = x >= left && x <= right && y >= top && y <= bottom;
  if (inside) return { zone: "top", left, right, top, bottom };
  if (signature.openN && y < top && x >= left && x <= right) return { zone: "northBack", left, right, top, bottom };
  if (signature.openN && signature.openE && x > right && y < top) return { zone: "northCornerBack", left, right, top, bottom };
  if (signature.openN && signature.openW && x < left && y < top) return { zone: "northCornerBack", left, right, top, bottom };
  if (signature.openS && y > bottom && x >= left && x <= right) return { zone: "southFace", left, right, top, bottom };
  if (signature.openE && x > right && y >= top && y <= bottom) return { zone: "eastFace", left, right, top, bottom };
  if (signature.openW && x < left && y >= top && y <= bottom) return { zone: "westFace", left, right, top, bottom };
  if (signature.openS && signature.openE && x > right && y > bottom) return { zone: "southCornerFace", left, right, top, bottom };
  if (signature.openS && signature.openW && x < left && y > bottom) return { zone: "southCornerFace", left, right, top, bottom };
  return { zone: "empty", left, right, top, bottom };
}

function isOuterChamferClipped(sample, params, x, y) {
  const chamfer = Math.max(0, Math.round(params.outerChamfer || 0));
  if (!chamfer) return false;
  if (sample.zone === "northCornerBack") {
    const distTop = y;
    const distOuterX = x > sample.right ? (params.tileSize - 1 - x) : x;
    return distTop < chamfer && distOuterX < chamfer && (distTop + distOuterX) < chamfer;
  }
  if (sample.zone === "southCornerFace") {
    const distBottom = params.tileSize - 1 - y;
    const distOuterX = x > sample.right ? (params.tileSize - 1 - x) : x;
    return distBottom < chamfer && distOuterX < chamfer && (distBottom + distOuterX) < chamfer;
  }
  return false;
}

function isBaseEroded(sample, params, x, y) {
  const erosion = Math.max(0, Math.round(params.baseErosion || 0));
  if (!erosion) return false;
  if (sample.zone === "southFace" || sample.zone === "southCornerFace") {
    const distOuter = params.tileSize - 1 - y;
    const noise = samplePeriodicNoisePx(x + 7, y + 13, 10, 2, params.seed + 1201, params.tileSize, params.tileSize);
    const cut = clamp(Math.round(erosion * (0.5 + noise * 0.8)), 0, erosion * 2);
    return distOuter < cut;
  }
  if (sample.zone === "eastFace") {
    const distOuter = params.tileSize - 1 - x;
    const noise = samplePeriodicNoisePx(x + 17, y + 5, 10, 2, params.seed + 1211, params.tileSize, params.tileSize);
    const cut = clamp(Math.round(erosion * (0.5 + noise * 0.8)), 0, erosion * 2);
    return distOuter < cut;
  }
  if (sample.zone === "westFace") {
    const distOuter = x;
    const noise = samplePeriodicNoisePx(x + 23, y + 9, 10, 2, params.seed + 1221, params.tileSize, params.tileSize);
    const cut = clamp(Math.round(erosion * (0.5 + noise * 0.8)), 0, erosion * 2);
    return distOuter < cut;
  }
  return false;
}

function jaggedSize(baseSize, axisCoord, crossCoord, params, salt) {
  const rough = params.roughness / 100;
  const amplitude = Math.max(0, Math.round(Math.max(1, baseSize * 0.45) * rough));
  if (!amplitude) return baseSize;
  const n = fbmPeriodic(axisCoord * 0.21 + salt * 0.07, crossCoord * 0.13 + salt * 0.11, 3, params.seed + salt * 101, 24, 24);
  return clamp(baseSize + Math.round((n - 0.5) * 2 * amplitude), 1, params.tileSize);
}

function overlayContains(mode, dx, dy, width, height) {
  if (dx < 0 || dy < 0 || dx >= width || dy >= height) return false;
  if (mode !== "bevel") return true;
  const tx = width <= 1 ? 0 : dx / (width - 1);
  const ty = height <= 1 ? 0 : dy / (height - 1);
  return tx + ty <= 1.04;
}

function classifyNotchOverlay(signature, sample, params, x, y) {
  const topNorthBase = { width: Math.max(1, sideHeightPx(params, "east")), height: Math.max(1, sideHeightPx(params, "north")) };
  const topWestBase = { width: Math.max(1, sideHeightPx(params, "west")), height: Math.max(1, sideHeightPx(params, "north")) };
  const bottomEastBase = { width: Math.max(1, sideHeightPx(params, "east")), height: Math.max(1, sideHeightPx(params, "south")) };
  const bottomWestBase = { width: Math.max(1, sideHeightPx(params, "west")), height: Math.max(1, sideHeightPx(params, "south")) };

  function dims(base, saltW, saltH, mode) {
    const widthBase = mode === "box" ? Math.max(base.width, base.height) : base.width;
    const heightBase = mode === "box" ? Math.max(base.width, base.height) : base.height;
    return {
      width: jaggedSize(widthBase, x, y, params, saltW),
      height: jaggedSize(heightBase, y, x, params, saltH)
    };
  }

  if (signature.notchNE) {
    const mode = resolveCornerMode(params, "NE");
    const current = dims(topNorthBase, 31, 37, mode);
    const dx = sample.right - x;
    const dy = y - sample.top;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "back", dx, dy, width: current.width, height: current.height };
  }
  if (signature.notchNW) {
    const mode = resolveCornerMode(params, "NW");
    const current = dims(topWestBase, 41, 43, mode);
    const dx = x - sample.left;
    const dy = y - sample.top;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "back", dx, dy, width: current.width, height: current.height };
  }
  if (signature.notchSE) {
    const mode = resolveCornerMode(params, "SE");
    const current = dims(bottomEastBase, 47, 53, mode);
    const dx = sample.right - x;
    const dy = sample.bottom - y;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "face", dx, dy, width: current.width, height: current.height };
  }
  if (signature.notchSW) {
    const mode = resolveCornerMode(params, "SW");
    const current = dims(bottomWestBase, 59, 61, mode);
    const dx = x - sample.left;
    const dy = sample.bottom - y;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "face", dx, dy, width: current.width, height: current.height };
  }
  return null;
}

function resolveZone(sample, overlay) {
  if (overlay) return overlay.zone;
  if (sample.zone === "top") return "top";
  if (sample.zone === "northBack" || sample.zone === "northCornerBack") return "back";
  if (sample.zone === "southFace" || sample.zone === "eastFace" || sample.zone === "westFace" || sample.zone === "southCornerFace") return "face";
  return "empty";
}

function computePixelHeight(zone, sample, overlay, params, x, y, signature) {
  if (zone === "empty") return 0;
  if (zone === "top") {
    const bevel = Math.max(0, Math.round(params.crownBevel || 0));
    if (!bevel) return 1;
    const openDistances = [];
    if (signature?.openN) openDistances.push(y - sample.top);
    if (signature?.openS) openDistances.push(sample.bottom - y);
    if (signature?.openW) openDistances.push(x - sample.left);
    if (signature?.openE) openDistances.push(sample.right - x);
    if (!openDistances.length) return 1;
    const nearestEdge = Math.min(...openDistances);
    const bevelT = smoothstep(0, Math.max(1, bevel), nearestEdge);
    return clamp(0.84 + bevelT * 0.16, 0.82, 1);
  }

  if (overlay) {
    const progressX = overlay.width <= 1 ? 0 : overlay.dx / (overlay.width - 1);
    const progressY = overlay.height <= 1 ? 0 : overlay.dy / (overlay.height - 1);
    const progress = clamp(Math.max(progressX, progressY), 0, 1);
    if (overlay.zone === "back") return clamp(1 - progress * 0.35, 0.6, 1);
    return Math.pow(1 - progress, clamp(params.faceSlope / 100, 0.5, 1.9));
  }

  const faceCurve = clamp(params.faceSlope / 100, 0.5, 1.9);
  if (sample.zone === "northBack") {
    const progress = clamp((sample.top - y) / Math.max(1, sample.top), 0, 1);
    return clamp(1 - progress * 0.35, 0.6, 1);
  }
  if (sample.zone === "northCornerBack") {
    const progressY = clamp((sample.top - y) / Math.max(1, sample.top), 0, 1);
    const progressX = x > sample.right
      ? clamp((x - sample.right) / Math.max(1, params.tileSize - 1 - sample.right), 0, 1)
      : clamp((sample.left - x) / Math.max(1, sample.left), 0, 1);
    return clamp(1 - Math.max(progressX, progressY) * 0.35, 0.6, 1);
  }
  if (sample.zone === "southFace") {
    const progress = clamp((y - sample.bottom) / Math.max(1, params.tileSize - 1 - sample.bottom), 0, 1);
    return Math.pow(1 - progress, faceCurve);
  }
  if (sample.zone === "eastFace") {
    const progress = clamp((x - sample.right) / Math.max(1, params.tileSize - 1 - sample.right), 0, 1);
    return Math.pow(1 - progress, faceCurve);
  }
  if (sample.zone === "westFace") {
    const progress = clamp((sample.left - x) / Math.max(1, sample.left), 0, 1);
    return Math.pow(1 - progress, faceCurve);
  }
  if (sample.zone === "southCornerFace") {
    const progressY = clamp((y - sample.bottom) / Math.max(1, params.tileSize - 1 - sample.bottom), 0, 1);
    const progressX = x > sample.right
      ? clamp((x - sample.right) / Math.max(1, params.tileSize - 1 - sample.right), 0, 1)
      : clamp((sample.left - x) / Math.max(1, sample.left), 0, 1);
    return Math.pow(1 - Math.max(progressX, progressY), faceCurve);
  }
  return 0;
}

function buildMaskCanvas(topMask, faceMask, backMask, alpha, size) {
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(size, size);
  for (let index = 0; index < alpha.length; index += 1) {
    const out = index * 4;
    image.data[out] = topMask[index];
    image.data[out + 1] = faceMask[index];
    image.data[out + 2] = backMask[index];
    image.data[out + 3] = alpha[index];
  }
  ctx.putImageData(image, 0, 0);
  return canvas;
}

function sampleTextureColor(texture, x, y, params, offsets) {
  if (!texture) return null;
  const zoom = 100 / Math.max(10, params.textureScale);
  const sx = mod(Math.floor(x * zoom + offsets.ox), texture.width);
  const sy = mod(Math.floor(y * zoom + offsets.oy), texture.height);
  const index = (sy * texture.width + sx) * 4;
  return [texture.data[index], texture.data[index + 1], texture.data[index + 2]];
}

function buildBaseColor(x, y, params, offsets) {
  const tint = hexToRgb(params.baseTint);
  const sample = sampleTextureColor(state.textures.base, x, y, params, offsets);
  const noise = samplePeriodicNoisePx(x + offsets.ox, y + offsets.oy, 44, 3, params.seed + 301, MATERIAL_EXPORT_SIZE, MATERIAL_EXPORT_SIZE);
  const grit = samplePeriodicRidgePx(x + offsets.ox, y + offsets.oy, 18, 2, params.seed + 311, MATERIAL_EXPORT_SIZE, MATERIAL_EXPORT_SIZE);
  const gain = (0.78 + noise * 0.26 + grit * 0.08) * offsets.brightness;
  const baseColor = sample ? applyTintToSample(sample, tint, params.baseTintOpacity) : tint;
  return scaleColor(baseColor, gain);
}

function buildSurfaceColor(kind, zone, x, y, params, offsets, materialSet = state.generated.material) {
  const isTopLike = kind === "top";
  const tint = hexToRgb(isTopLike ? params.topTint : params.faceTint);
  const texture = isTopLike ? state.textures.top : state.textures.face;
  const tintOpacity = isTopLike ? params.topTintOpacity : params.faceTintOpacity;
  const materialMap = isTopLike ? materialSet.top : materialSet.face;
  const sample = sampleTextureColor(texture, x, y, params, offsets);
  const modulation = sampleScalar(materialMap.values, materialMap.width, materialMap.height, x + offsets.ox, y + offsets.oy);
  const zoneBrightness = zone === "back" ? 0.84 : zone === "face" ? 0.7 : 1;
  const gain = isTopLike
    ? (0.74 + modulation * 0.48) * zoneBrightness * offsets.brightness
    : (0.58 + modulation * 0.55) * zoneBrightness * offsets.brightness;
  const baseColor = sample ? applyTintToSample(sample, tint, tintOpacity) : tint;
  return scaleColor(baseColor, gain);
}

function paintLayeredTile(tile, params, offsets, compositeMode, originX = 0, originY = 0, materialSet = state.generated.material) {
  const size = params.tileSize;
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(size, size);
  const light = normalizeVector(-0.25, -0.35, 0.9);

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const index = y * size + x;
      const out = index * 4;
      if (!tile.alpha[index]) {
        image.data[out + 3] = 0;
        continue;
      }

      const zone = tile.topMask[index] ? "top" : tile.faceMask[index] ? "face" : "back";
      const sampleX = originX + x;
      const sampleY = originY + y;
      const color = buildSurfaceColor(zone === "face" ? "face" : "top", zone, sampleX, sampleY, params, offsets, materialSet);
      let finalColor = color;

      if (compositeMode) {
        const normal = normalFromHeightField(tile.shapeHeight, tile.alpha, size, size, x, y, params.normalStrength / 100);
        const lambert = clamp(normal.x * light.x + normal.y * light.y + normal.z * light.z, 0, 1);
        const lighting = zone === "face" ? 0.76 + lambert * 0.24 : 0.82 + lambert * 0.18;
        finalColor = scaleColor(color, lighting);
      }

      image.data[out] = finalColor[0];
      image.data[out + 1] = finalColor[1];
      image.data[out + 2] = finalColor[2];
      image.data[out + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);
  return canvas;
}

function resolveTileZone(tile, index) {
  return tile.topMask[index] ? "top" : tile.faceMask[index] ? "face" : "back";
}

function buildTileExportCanvas(tile, params, offsets, mode, originX = 0, originY = 0, materialSet = state.generated.material) {
  const size = params.tileSize;
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(size, size);

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const index = y * size + x;
      const out = index * 4;
      if (!tile.alpha[index]) {
        image.data[out + 3] = 0;
        continue;
      }

      const zone = resolveTileZone(tile, index);
      const kind = zone === "face" ? "face" : "top";
      const materialMap = kind === "face" ? materialSet.face : materialSet.top;
      const sampleX = originX + x + offsets.ox;
      const sampleY = originY + y + offsets.oy;

      if (mode === "height") {
        const materialHeight = sampleScalar(materialMap.heightValues, materialMap.width, materialMap.height, sampleX, sampleY);
        const combinedHeight = clamp(tile.shapeHeight[index] * 0.78 + materialHeight * 0.22, 0, 1);
        const value = clamp(Math.round(combinedHeight * 255), 0, 255);
        image.data[out] = value;
        image.data[out + 1] = value;
        image.data[out + 2] = value;
      } else if (mode === "orm") {
        image.data[out] = clamp(Math.round(sampleScalar(materialMap.occlusionValues, materialMap.width, materialMap.height, sampleX, sampleY) * 255), 0, 255);
        image.data[out + 1] = clamp(Math.round(sampleScalar(materialMap.roughnessValues, materialMap.width, materialMap.height, sampleX, sampleY) * 255), 0, 255);
        image.data[out + 2] = clamp(Math.round(sampleScalar(materialMap.metallicValues, materialMap.width, materialMap.height, sampleX, sampleY) * 255), 0, 255);
      } else if (mode === "emission") {
        image.data[out] = clamp(Math.round(sampleScalar(materialMap.emissionRValues, materialMap.width, materialMap.height, sampleX, sampleY) * 255), 0, 255);
        image.data[out + 1] = clamp(Math.round(sampleScalar(materialMap.emissionGValues, materialMap.width, materialMap.height, sampleX, sampleY) * 255), 0, 255);
        image.data[out + 2] = clamp(Math.round(sampleScalar(materialMap.emissionBValues, materialMap.width, materialMap.height, sampleX, sampleY) * 255), 0, 255);
      } else if (mode === "flow") {
        const flowX = sampleScalar(materialMap.flowXValues, materialMap.width, materialMap.height, sampleX, sampleY);
        const flowY = sampleScalar(materialMap.flowYValues, materialMap.width, materialMap.height, sampleX, sampleY);
        image.data[out] = clamp(Math.round((flowX * 0.5 + 0.5) * 255), 0, 255);
        image.data[out + 1] = clamp(Math.round((flowY * 0.5 + 0.5) * 255), 0, 255);
        image.data[out + 2] = clamp(Math.round(Math.hypot(flowX, flowY) * 255), 0, 255);
      }

      image.data[out + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);
  return canvas;
}

function getPreviewCompositeTile(generated, tile, signature, variantIndex, params, originX, originY, offsets) {
  const cacheKey = `${signature.key}|${variantIndex}|${originX}|${originY}|${params.tileSize}|${params.normalStrength}|${params.textureScale}|${params.topTint}|${params.faceTint}|${params.topTintOpacity}|${params.faceTintOpacity}|${params.seed}`;
  const cached = generated.previewCompositeCache.get(cacheKey);
  if (cached) return cached;
  const canvas = paintLayeredTile(tile, params, offsets, true, originX, originY, generated.material);
  generated.previewCompositeCache.set(cacheKey, canvas);
  return canvas;
}

function globalPreviewOffsets(params, slot) {
  const salt = slot === "base" ? 1709 : 2719;
  return {
    ox: Math.floor(hash2D(params.seed + salt, salt * 3, salt * 7) * 8192),
    oy: Math.floor(hash2D(params.seed + salt * 5, salt * 11, salt * 13) * 8192),
    brightness: 1
  };
}

function drawContinuousBasePreview(targetCanvas, params) {
  const width = state.map.width * params.tileSize;
  const height = state.map.height * params.tileSize;
  const ctx = targetCanvas.getContext("2d");
  const image = ctx.createImageData(width, height);
  const offsets = globalPreviewOffsets(params, "base");

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const color = buildBaseColor(x, y, params, offsets);
      const out = (y * width + x) * 4;
      image.data[out] = color[0];
      image.data[out + 1] = color[1];
      image.data[out + 2] = color[2];
      image.data[out + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);
}

function renderTile(signature, variantIndex, params, materialSet = state.generated.material, options = {}) {
  const includeExportChannels = options.includeExportChannels !== false;
  const size = params.tileSize;
  const variantSeed = params.seed + variantIndex * 97 + signature.index * 131;
  const profiles = buildProfiles(signature, variantSeed, params);
  const offsets = variantOffsets(signature, variantIndex, params);
  const topMask = new Uint8Array(size * size);
  const faceMask = new Uint8Array(size * size);
  const backMask = new Uint8Array(size * size);
  const alpha = new Uint8Array(size * size);
  const shapeHeight = new Float32Array(size * size);

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let sample = classifyPixel(signature, profiles, params, x, y);
      if (sample.zone !== "empty" && isOuterChamferClipped(sample, params, x, y)) {
        sample = { ...sample, zone: "empty" };
      }
      if (sample.zone !== "empty" && isBaseEroded(sample, params, x, y)) {
        sample = { ...sample, zone: "empty" };
      }
      const overlay = sample.zone === "empty" ? null : classifyNotchOverlay(signature, sample, params, x, y);
      const zone = resolveZone(sample, overlay);
      const index = y * size + x;
      if (zone === "empty") continue;
      alpha[index] = 255;
      if (zone === "top") topMask[index] = 255;
      if (zone === "face") faceMask[index] = 255;
      if (zone === "back") backMask[index] = 255;
      shapeHeight[index] = computePixelHeight(zone, sample, overlay, params, x, y, signature);
    }
  }

  const shapeNormalCanvas = buildNormalCanvas(shapeHeight, alpha, size, size, params.normalStrength / 100);
  const tile = {
    signature,
    offsets,
    topMask,
    faceMask,
    backMask,
    alpha,
    shapeHeight,
    canvases: {
      mask: buildMaskCanvas(topMask, faceMask, backMask, alpha, size),
      shapeHeight: buildScalarCanvas(shapeHeight, alpha, size, size),
      shapeNormal: shapeNormalCanvas,
      albedo: null,
      shaderComposite: null,
      height: null,
      orm: null,
      emission: null,
      flow: null
    }
  };

  if (includeExportChannels) {
    tile.canvases.height = buildTileExportCanvas(tile, params, offsets, "height", 0, 0, materialSet);
    tile.canvases.orm = buildTileExportCanvas(tile, params, offsets, "orm", 0, 0, materialSet);
    tile.canvases.emission = buildTileExportCanvas(tile, params, offsets, "emission", 0, 0, materialSet);
    tile.canvases.flow = buildTileExportCanvas(tile, params, offsets, "flow", 0, 0, materialSet);
  }

  return tile;
}

function renderBaseVariants(params) {
  const total = Math.max(4, params.variants);
  const variants = [];
  for (let variantIndex = 0; variantIndex < total; variantIndex += 1) {
    const offsets = {
      ox: variantIndex * 117 + params.seed * 3,
      oy: variantIndex * 173 + params.seed * 5,
      brightness: 1 + (variantIndex - (total - 1) / 2) * 0.018
    };
    const canvas = createCanvas(params.tileSize, params.tileSize);
    const ctx = canvas.getContext("2d");
    const image = ctx.createImageData(params.tileSize, params.tileSize);
    for (let y = 0; y < params.tileSize; y += 1) {
      for (let x = 0; x < params.tileSize; x += 1) {
        const color = buildBaseColor(x, y, params, offsets);
        const index = (y * params.tileSize + x) * 4;
        image.data[index] = color[0];
        image.data[index + 1] = color[1];
        image.data[index + 2] = color[2];
        image.data[index + 3] = 255;
      }
    }
    ctx.putImageData(image, 0, 0);
    variants.push(canvas);
  }
  return variants;
}

function rebuildTileSet(params, generated = state.generated, options = {}) {
  generated.tiles = [];
  clearCompositeCache(generated);
  for (let variantIndex = 0; variantIndex < params.variants; variantIndex += 1) {
    const tileMap = new Map();
    state.catalog.forEach((signature) => {
      const tile = renderTile(signature, variantIndex, params, generated.material, options);
      tile.canvases.albedo = paintLayeredTile(tile, params, tile.offsets, false, 0, 0, generated.material);
      tile.canvases.shaderComposite = paintLayeredTile(tile, params, tile.offsets, true, 0, 0, generated.material);
      tileMap.set(signature.key, tile);
    });
    generated.tiles.push(tileMap);
  }
}

function drawAtlasTileWithBleed(ctx, sourceCanvas, dx, dy, tileSize, paddingPx) {
  if (!sourceCanvas) return;
  const innerX = dx + paddingPx;
  const innerY = dy + paddingPx;
  ctx.drawImage(sourceCanvas, innerX, innerY);
  if (!paddingPx) return;
  ctx.drawImage(sourceCanvas, 0, 0, tileSize, 1, innerX, dy, tileSize, paddingPx);
  ctx.drawImage(sourceCanvas, 0, tileSize - 1, tileSize, 1, innerX, innerY + tileSize, tileSize, paddingPx);
  ctx.drawImage(sourceCanvas, 0, 0, 1, tileSize, dx, innerY, paddingPx, tileSize);
  ctx.drawImage(sourceCanvas, tileSize - 1, 0, 1, tileSize, innerX + tileSize, innerY, paddingPx, tileSize);
  ctx.drawImage(sourceCanvas, 0, 0, 1, 1, dx, dy, paddingPx, paddingPx);
  ctx.drawImage(sourceCanvas, tileSize - 1, 0, 1, 1, innerX + tileSize, dy, paddingPx, paddingPx);
  ctx.drawImage(sourceCanvas, 0, tileSize - 1, 1, 1, dx, innerY + tileSize, paddingPx, paddingPx);
  ctx.drawImage(sourceCanvas, tileSize - 1, tileSize - 1, 1, 1, innerX + tileSize, innerY + tileSize, paddingPx, paddingPx);
}

function buildAtlases(params, generated = state.generated) {
  const columns = 8;
  const total = state.catalog.length * params.variants;
  const rows = Math.ceil(total / columns);
  const cellSize = params.tileSize + ATLAS_PADDING_PX * 2;
  Object.values(generated.atlases).forEach(releaseCanvas);
  generated.atlases = {};
  generated.atlasManifest = [];
  const atlasContexts = {};

  ATLAS_EXPORT_MODES.forEach((mode) => {
    const canvas = createCanvas(columns * cellSize, rows * cellSize);
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    generated.atlases[mode] = canvas;
    atlasContexts[mode] = ctx;
  });

  let atlasIndex = 0;
  for (let variantIndex = 0; variantIndex < params.variants; variantIndex += 1) {
    state.catalog.forEach((signature) => {
      const tile = generated.tiles[variantIndex].get(signature.key);
      const col = atlasIndex % columns;
      const row = Math.floor(atlasIndex / columns);
      const dx = col * cellSize;
      const dy = row * cellSize;
      ATLAS_EXPORT_MODES.forEach((mode) => {
        drawAtlasTileWithBleed(atlasContexts[mode], tile.canvases[mode], dx, dy, params.tileSize, ATLAS_PADDING_PX);
      });
      generated.atlasManifest.push({
        atlasIndex,
        variant: variantIndex,
        key: signature.key,
        label: signature.label,
        column: col,
        row,
        pixelX: dx + ATLAS_PADDING_PX,
        pixelY: dy + ATLAS_PADDING_PX,
        tileSizePx: params.tileSize,
        cellSizePx: cellSize,
        paddingPx: ATLAS_PADDING_PX
      });
      atlasIndex += 1;
    });
  }
}

function createDraftParams(params) {
  return {
    ...params,
    tileSize: Math.max(16, Math.floor(params.tileSize / 2))
  };
}

function buildPreviewBundle(params) {
  const generated = createGeneratedState();
  generated.material.top = buildTopMaterialMap(params);
  generated.material.face = buildFaceMaterialMap(params);
  rebuildTileSet(params, generated, { includeExportChannels: false });
  generated.baseVariants = renderBaseVariants(params);
  return generated;
}

function refreshVisibleAtlas() {
  const source = state.generated.atlases[state.previewMode];
  if (!source) return;
  presentCanvas(refs.atlasCanvas, source);
}

function buildGallery() {
  if (!state.generated.tiles.length) {
    refs.tileGrid.innerHTML = "";
    state.galleryCards.clear();
    return;
  }
  const variantIndex = Number(refs.galleryVariant.value || 0);
  if (state.galleryCards.size !== state.catalog.length) {
    refs.tileGrid.innerHTML = "";
    state.galleryCards.clear();
    state.catalog.forEach((signature) => {
      const card = document.createElement("div");
      card.className = "tile-card";
      const canvas = document.createElement("canvas");
      const title = document.createElement("strong");
      title.textContent = `${String(signature.index + 1).padStart(2, "0")} · ${signature.key}`;
      const meta = document.createElement("span");
      meta.textContent = signature.label;
      card.append(canvas, title, meta);
      refs.tileGrid.appendChild(card);
      state.galleryCards.set(signature.key, { card, canvas });
    });
  }
  state.catalog.forEach((signature) => {
    const tile = state.generated.tiles[variantIndex].get(signature.key);
    const galleryCard = state.galleryCards.get(signature.key);
    const source = createCanvas(128, 128);
    const ctx = source.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(tile.canvases[state.previewMode], 0, 0, 128, 128);
    presentCanvas(galleryCard.canvas, source);
    releaseCanvas(source);
  });
}

function signatureAt(x, y) {
  return createSignature(
    Boolean(getMapCell(x, y - 1)),
    Boolean(getMapCell(x + 1, y - 1)),
    Boolean(getMapCell(x + 1, y)),
    Boolean(getMapCell(x + 1, y + 1)),
    Boolean(getMapCell(x, y + 1)),
    Boolean(getMapCell(x - 1, y + 1)),
    Boolean(getMapCell(x - 1, y)),
    Boolean(getMapCell(x - 1, y - 1))
  );
}

function chooseVariantForCell(x, y, params) {
  return Math.floor(hash2D(x, y, params.seed + 907) * params.variants) % params.variants;
}

function chooseBaseVariantForCell(x, y, params, generated = state.generated) {
  const total = generated.baseVariants.length;
  return Math.floor(hash2D(x + 11, y + 17, params.seed + 1907) * total) % total;
}

function drawPreview(params = getParams(), generated = state.generated, options = {}) {
  if (!generated.tiles.length) return;
  state.previewMode = refs.previewMode.value;
  const logicalCanvas = createCanvas(state.map.width * params.tileSize, state.map.height * params.tileSize);
  const ctx = logicalCanvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  ctx.clearRect(0, 0, logicalCanvas.width, logicalCanvas.height);

  if (state.previewMode === "shaderComposite") {
    drawContinuousBasePreview(logicalCanvas, params);
  } else if (state.previewMode === "albedo") {
    for (let y = 0; y < state.map.height; y += 1) {
      for (let x = 0; x < state.map.width; x += 1) {
        const baseTile = generated.baseVariants[chooseBaseVariantForCell(x, y, params, generated)];
        ctx.drawImage(baseTile, x * params.tileSize, y * params.tileSize);
      }
    }
  } else {
    ctx.fillStyle = "#0f0c0a";
    ctx.fillRect(0, 0, logicalCanvas.width, logicalCanvas.height);
  }

  const compositeOffsets = state.previewMode === "shaderComposite"
    ? globalPreviewOffsets(params, "surface")
    : null;

  for (let y = 0; y < state.map.height; y += 1) {
    for (let x = 0; x < state.map.width; x += 1) {
      if (!getMapCell(x, y)) continue;
      const signature = signatureAt(x, y);
      const variantIndex = chooseVariantForCell(x, y, params);
      const tile = generated.tiles[variantIndex].get(signature.key);
      if (state.previewMode === "shaderComposite") {
        const compositeTile = getPreviewCompositeTile(
          generated,
          tile,
          signature,
          variantIndex,
          params,
          x * params.tileSize,
          y * params.tileSize,
          compositeOffsets
        );
        ctx.drawImage(compositeTile, x * params.tileSize, y * params.tileSize);
      } else {
        ctx.drawImage(tile.canvases[state.previewMode], x * params.tileSize, y * params.tileSize);
      }
    }
  }

  if (state.preview.sourceCanvas && state.preview.sourceCanvas !== logicalCanvas) {
    releaseCanvas(state.preview.sourceCanvas);
  }
  state.preview.sourceCanvas = logicalCanvas;
  state.preview.logicalTileSize = params.tileSize;
  state.preview.isDraft = Boolean(options.draft);
  presentCanvas(refs.previewCanvas, logicalCanvas);
}

function drawSlotPreviewCanvas(canvas, slot, params) {
  const logicalWidth = Number(canvas.dataset.logicalWidth || canvas.getAttribute("width") || 96);
  const logicalHeight = Number(canvas.dataset.logicalHeight || canvas.getAttribute("height") || 96);
  const source = createCanvas(logicalWidth, logicalHeight);
  const ctx = source.getContext("2d");
  const image = ctx.createImageData(logicalWidth, logicalHeight);
  const offsets = { ox: params.seed * 7 + logicalWidth, oy: params.seed * 13 + logicalHeight, brightness: 1 };

  for (let y = 0; y < logicalHeight; y += 1) {
    for (let x = 0; x < logicalWidth; x += 1) {
      const out = (y * logicalWidth + x) * 4;
      const color = slot === "base"
        ? buildBaseColor(x, y, params, offsets)
        : buildSurfaceColor(slot, slot === "face" ? "face" : "top", x, y, params, offsets);
      image.data[out] = color[0];
      image.data[out + 1] = color[1];
      image.data[out + 2] = color[2];
      image.data[out + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);
  presentCanvas(canvas, source);
  releaseCanvas(source);
}

function drawTilingPreview(targetCanvas, sourceCanvas) {
  const logicalWidth = Number(targetCanvas.dataset.logicalWidth || targetCanvas.getAttribute("width") || 256);
  const logicalHeight = Number(targetCanvas.dataset.logicalHeight || targetCanvas.getAttribute("height") || 256);
  const target = createCanvas(logicalWidth, logicalHeight);
  const ctx = target.getContext("2d");
  ctx.clearRect(0, 0, logicalWidth, logicalHeight);
  ctx.imageSmoothingEnabled = false;
  const halfWidth = Math.floor(logicalWidth / 2);
  const halfHeight = Math.floor(logicalHeight / 2);
  for (let y = 0; y < 2; y += 1) {
    for (let x = 0; x < 2; x += 1) {
      ctx.drawImage(sourceCanvas, x * halfWidth, y * halfHeight, halfWidth, halfHeight);
    }
  }
  presentCanvas(targetCanvas, target);
  releaseCanvas(target);
}

function updateStats(params) {
  refs.statCases.textContent = String(state.catalog.length);
  refs.statVariants.textContent = String(params.variants);
  refs.statTotal.textContent = String(state.catalog.length * params.variants);
  refs.catalogInfo.textContent = `${state.catalog.length}/47`;
}

function refreshGalleryOptions() {
  const total = Number(refs.variants.value);
  const previous = Number(refs.galleryVariant.value || 0);
  refs.galleryVariant.innerHTML = "";
  for (let index = 0; index < total; index += 1) {
    const option = document.createElement("option");
    option.value = String(index);
    option.textContent = `v${index + 1}`;
    refs.galleryVariant.appendChild(option);
  }
  refs.galleryVariant.value = String(Math.min(previous, total - 1));
}

async function readTexture(input, slot) {
  const file = input.files[0];
  if (!file) {
    state.textures[slot] = null;
    state.textureNames[slot] = "procedural";
    refs[`${slot}FileName`].textContent = "procedural";
    markDirty("color");
    scheduleRender("full");
    return;
  }

  try {
    const bitmap = await createImageBitmap(file);
    const canvas = createCanvas(bitmap.width, bitmap.height);
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(bitmap, 0, 0);
    if (typeof bitmap.close === "function") bitmap.close();
    const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
    state.textures[slot] = { width: canvas.width, height: canvas.height, data: image.data };
    state.textureNames[slot] = file.name;
    refs[`${slot}FileName`].textContent = file.name;
    markDirty("color");
    scheduleRender("full");
  } catch (error) {
    refs.status.innerHTML = `<span class="warn">Ошибка текстуры.</span> ${error.message}`;
  }
}

function createRoomMap() {
  const changed = recordMapMutation(() => {
    initMap();
    for (let y = 2; y < state.map.height - 2; y += 1) {
      for (let x = 3; x < state.map.width - 3; x += 1) {
        const border = x === 3 || y === 2 || x === state.map.width - 4 || y === state.map.height - 3;
        setMapCell(x, y, border ? 1 : 0);
      }
    }
  });
  if (changed && state.generated.tiles.length) {
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
    persistSessionState();
  }
}

function createBlobMap() {
  const changed = recordMapMutation(() => {
    initMap();
    const params = getParams();
    const cx = state.map.width / 2;
    const cy = state.map.height / 2;
    for (let y = 0; y < state.map.height; y += 1) {
      for (let x = 0; x < state.map.width; x += 1) {
        const dx = (x - cx) / (state.map.width * 0.38);
        const dy = (y - cy) / (state.map.height * 0.38);
        const radial = 1 - Math.sqrt(dx * dx + dy * dy);
        const noise = fbmPeriodic(x * 0.42, y * 0.42, 4, params.seed + 91, 32, 32);
        setMapCell(x, y, radial + noise * 0.55 > 0.66);
      }
    }
  });
  if (changed && state.generated.tiles.length) {
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
    persistSessionState();
  }
}

function createCaveMap() {
  const changed = recordMapMutation(() => {
    initMap();
    const params = getParams();
    for (let y = 0; y < state.map.height; y += 1) {
      for (let x = 0; x < state.map.width; x += 1) {
        setMapCell(x, y, fbmPeriodic(x * 0.3, y * 0.3, 5, params.seed + 403, 24, 24) > 0.56 ? 1 : 0);
      }
    }
    for (let pass = 0; pass < 3; pass += 1) {
      const next = state.map.cells.slice();
      for (let y = 0; y < state.map.height; y += 1) {
        for (let x = 0; x < state.map.width; x += 1) {
          let count = 0;
          for (let oy = -1; oy <= 1; oy += 1) {
            for (let ox = -1; ox <= 1; ox += 1) {
              if (!ox && !oy) continue;
              count += getMapCell(x + ox, y + oy);
            }
          }
          next[y * state.map.width + x] = count >= 4 ? 1 : 0;
        }
      }
      state.map.cells = next;
    }
  });
  if (changed && state.generated.tiles.length) {
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
    persistSessionState();
  }
}

function clearMap() {
  const changed = recordMapMutation(() => {
    initMap();
  });
  if (changed && state.generated.tiles.length) {
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
    persistSessionState();
  }
}

function rebuildDraftPreview() {
  const params = getParams();
  const draftParams = createDraftParams(params);
  const generated = buildPreviewBundle(draftParams);
  drawPreview(draftParams, generated, { draft: true });
  refs.status.innerHTML = `<span class="ok">Draft preview.</span> ${state.catalog.length} сигнатур × ${params.variants} вариантов в ${draftParams.tileSize}px для плавного drag.`;
}

function rebuildAll() {
  const params = getParams();
  state.previewMode = refs.previewMode.value;

  const rebuildMaterial = state.dirty.material || state.dirty.variants;
  const rebuildMaterialAlbedo = rebuildMaterial || state.dirty.color;
  const rebuildTilesFlag = state.dirty.shape || rebuildMaterial || state.dirty.color || state.dirty.variants;
  const rebuildBase = state.dirty.color || state.dirty.variants;
  const rebuildAtlasFlag = rebuildTilesFlag;
  const refreshAudit = rebuildMaterial || rebuildMaterialAlbedo || rebuildAtlasFlag;
  const refreshPreview = rebuildTilesFlag || rebuildBase || state.dirty.map || state.dirty.previewMode;
  const refreshGallery = rebuildTilesFlag || state.dirty.gallery;
  const refreshSwatches = rebuildMaterialAlbedo || state.dirty.swatches;

  if (rebuildMaterial) {
    state.generated.material.top = buildTopMaterialMap(params);
    state.generated.material.face = buildFaceMaterialMap(params);
  }
  if (rebuildMaterialAlbedo) {
    state.generated.material.topAlbedo = buildMaterialAlbedoCanvas("top", params);
    state.generated.material.faceAlbedo = buildMaterialAlbedoCanvas("face", params);
  }
  if (rebuildTilesFlag) {
    rebuildTileSet(params, state.generated);
  }
  if (rebuildBase) {
    state.generated.baseVariants = renderBaseVariants(params);
  }
  if (rebuildAtlasFlag) {
    buildAtlases(params, state.generated);
  }
  if (rebuildAtlasFlag || state.dirty.previewMode) {
    refreshVisibleAtlas();
  }
  if (refreshGallery) {
    buildGallery();
  }
  if (refreshPreview) {
    drawPreview(params, state.generated, { draft: false });
  }
  if (refreshSwatches) {
    drawSlotPreviewCanvas(refs.baseTexturePreview, "base", params);
    drawSlotPreviewCanvas(refs.topTexturePreview, "top", params);
    drawSlotPreviewCanvas(refs.faceTexturePreview, "face", params);
    drawTilingPreview(refs.topTilingCanvas, state.generated.material.top.canvas);
    drawTilingPreview(refs.faceTilingCanvas, state.generated.material.face.canvas);
  }
  if (refreshAudit) {
    state.generated.audit = buildExportAudit(params);
    updateExportAuditStatus();
  }
  if (state.dirty.stats) {
    updateStats(params);
  }
  Object.keys(state.dirty).forEach((key) => {
    state.dirty[key] = false;
  });
  persistSessionState();
  refs.status.innerHTML = `<span class="ok">Готово.</span> ${state.catalog.length} сигнатур × ${params.variants} вариантов = ${state.catalog.length * params.variants} тайлов.`;
}

function refreshVisibleOutputs() {
  if (!state.generated.tiles.length) return;
  if (state.pendingRenderTimer) {
    clearTimeout(state.pendingRenderTimer);
    state.pendingRenderTimer = null;
    state.pendingRenderMode = null;
  }
  markDirty("previewMode");
  rebuildAll();
}

function scheduleRender(mode = "full") {
  const delay = mode === "draft" ? 120 : 60;
  if (state.pendingRenderTimer) clearTimeout(state.pendingRenderTimer);
  state.pendingRenderMode = state.pendingRenderMode === "full" || mode === "full" ? "full" : "draft";
  refs.status.textContent = state.pendingRenderMode === "full"
    ? "Пересобираю тайлы..."
    : "Обновляю draft preview...";
  state.pendingRenderTimer = setTimeout(() => {
    const nextMode = state.pendingRenderMode;
    state.pendingRenderTimer = null;
    state.pendingRenderMode = null;
    if (nextMode === "draft") rebuildDraftPreview();
    else rebuildAll();
  }, delay);
}

function downloadBlob(blob, fileName) {
  if (!blob) return;
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1200);
}

function downloadCanvas(canvas, fileName) {
  if (!canvas) return;
  canvas.toBlob((blob) => {
    if (!blob) return;
    downloadBlob(blob, fileName);
  }, "image/png");
}

function downloadTextFile(content, fileName, mimeType = "text/plain;charset=utf-8") {
  downloadBlob(new Blob([content], { type: mimeType }), fileName);
}

function getCanvasPixelBytes(canvas) {
  if (!canvas) return new Uint8Array();
  const ctx = canvas.getContext("2d");
  return new Uint8Array(ctx.getImageData(0, 0, canvas.width, canvas.height).data);
}

function toCrcHex(value) {
  return `crc32:${value.toString(16).padStart(8, "0")}`;
}

function hashCanvasPixels(canvas) {
  return toCrcHex(crc32(getCanvasPixelBytes(canvas)));
}

function measureCanvasSeamRms(canvas) {
  if (!canvas || canvas.width < 2 || canvas.height < 2) return 0;
  const { width, height } = canvas;
  const data = getCanvasPixelBytes(canvas);
  let sum = 0;
  let count = 0;

  for (let y = 0; y < height; y += 1) {
    const left = (y * width) * 4;
    const right = ((y * width) + (width - 1)) * 4;
    for (let channel = 0; channel < 4; channel += 1) {
      const diff = data[left + channel] - data[right + channel];
      sum += diff * diff;
      count += 1;
    }
  }

  for (let x = 0; x < width; x += 1) {
    const top = x * 4;
    const bottom = (((height - 1) * width) + x) * 4;
    for (let channel = 0; channel < 4; channel += 1) {
      const diff = data[top + channel] - data[bottom + channel];
      sum += diff * diff;
      count += 1;
    }
  }

  return Math.sqrt(sum / Math.max(1, count));
}

function buildExportAudit(params = getParams()) {
  const seamTargets = {
    topAlbedo: state.generated.material.topAlbedo,
    faceAlbedo: state.generated.material.faceAlbedo,
    topModulation: state.generated.material.top?.canvas,
    faceModulation: state.generated.material.face?.canvas,
    topNormal: state.generated.material.top?.normalCanvas,
    faceNormal: state.generated.material.face?.normalCanvas,
    topOrm: state.generated.material.top?.ormCanvas,
    faceOrm: state.generated.material.face?.ormCanvas,
    topEmission: state.generated.material.top?.emissionCanvas,
    faceEmission: state.generated.material.face?.emissionCanvas,
    topFlow: state.generated.material.top?.flowCanvas,
    faceFlow: state.generated.material.face?.flowCanvas
  };
  const seamMetrics = {};
  let worstKey = "";
  let worstScore = 0;

  Object.entries(seamTargets).forEach(([key, canvas]) => {
    if (!canvas) return;
    const score = Number(measureCanvasSeamRms(canvas).toFixed(2));
    seamMetrics[key] = {
      score,
      status: score <= SEAM_LINT_WARN_THRESHOLD ? "ok" : "warn"
    };
    if (score >= worstScore) {
      worstScore = score;
      worstKey = key;
    }
  });

  const proofArtifacts = {
    albedoAtlas: hashCanvasPixels(state.generated.atlases.albedo),
    maskAtlas: hashCanvasPixels(state.generated.atlases.mask),
    shapeNormalAtlas: hashCanvasPixels(state.generated.atlases.shapeNormal),
    heightAtlas: hashCanvasPixels(state.generated.atlases.height),
    ormAtlas: hashCanvasPixels(state.generated.atlases.orm),
    emissionAtlas: hashCanvasPixels(state.generated.atlases.emission),
    flowAtlas: hashCanvasPixels(state.generated.atlases.flow),
    topAlbedo: hashCanvasPixels(state.generated.material.topAlbedo),
    faceAlbedo: hashCanvasPixels(state.generated.material.faceAlbedo),
    topModulation: hashCanvasPixels(state.generated.material.top?.canvas),
    faceModulation: hashCanvasPixels(state.generated.material.face?.canvas),
    topNormal: hashCanvasPixels(state.generated.material.top?.normalCanvas),
    faceNormal: hashCanvasPixels(state.generated.material.face?.normalCanvas)
  };
  const proofSeed = {
    preset: state.preset,
    customPresetName: state.customPresetName || null,
    params,
    materialLayers: serializeMaterialLayers(state.materialLayers),
    textureNames: state.textureNames,
    atlasManifest: state.generated.atlasManifest,
    artifacts: proofArtifacts
  };
  const proofPayload = JSON.stringify(proofSeed);
  const deterministicProof = {
    mode: "raw_rgba_crc32",
    combinedHash: toCrcHex(crc32(new TextEncoder().encode(proofPayload))),
    artifacts: proofArtifacts
  };

  return {
    seamLint: {
      threshold: SEAM_LINT_WARN_THRESHOLD,
      allOk: worstScore <= SEAM_LINT_WARN_THRESHOLD,
      worstKey,
      worstScore: Number(worstScore.toFixed(2)),
      metrics: seamMetrics
    },
    deterministicProof
  };
}

function updateExportAuditStatus() {
  if (!refs.exportAudit) return;
  const audit = state.generated.audit;
  if (!audit?.deterministicProof) {
    refs.exportAudit.textContent = "Export audit появится после полной пересборки.";
    return;
  }
  const seamText = audit.seamLint?.allOk
    ? `Seam lint OK, worst ${audit.seamLint.worstKey || "n/a"} = ${audit.seamLint.worstScore}.`
    : `Seam lint предупреждает: worst ${audit.seamLint.worstKey || "n/a"} = ${audit.seamLint.worstScore} при threshold ${audit.seamLint.threshold}.`;
  refs.exportAudit.innerHTML = `<span class="ok">Deterministic proof.</span> ${audit.deterministicProof.combinedHash}<br>${seamText}`;
}

function buildGodotExportInfo(params = getParams()) {
  const stem = sanitizeFileStem(buildExportBaseName(params));
  return {
    assetDir: `res://assets/generated/terrain/${stem}`,
    shapeId: `generated:${stem}_shape`,
    materialId: `generated:${stem}_material`
  };
}

function formatGodotVariant(value) {
  if (typeof value === "number") {
    if (Number.isInteger(value)) return String(value);
    return Number(value).toFixed(4).replace(/0+$/g, "").replace(/\.$/, "");
  }
  if (typeof value === "boolean") return value ? "true" : "false";
  return JSON.stringify(String(value));
}

function formatGodotDictionary(dictionary) {
  const entries = Object.entries(dictionary || {}).sort(([left], [right]) => left.localeCompare(right));
  if (!entries.length) return "{}";
  return `{\n${entries.map(([key, value]) => `"${key}": ${formatGodotVariant(value)}`).join(",\n")}\n}`;
}

function buildShapeSetTres() {
  const params = getParams();
  const fileNames = buildExportFileNames(params);
  const exportInfo = buildGodotExportInfo(params);
  return `[gd_resource type="Resource" script_class="TerrainShapeSet" load_steps=4 format=3]

[ext_resource type="Script" path="res://data/terrain/terrain_shape_set.gd" id="1"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.maskAtlas}" id="2"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.shapeNormalAtlas}" id="3"]

[resource]
script = ExtResource("1")
id = &"${exportInfo.shapeId}"
topology_family_id = &"autotile_47"
mask_atlas = ExtResource("2")
shape_normal_atlas = ExtResource("3")
tile_size_px = ${params.tileSize}
case_count = ${state.catalog.length}
variant_count = ${params.variants}
`;
}

function buildMaterialSetTres() {
  const params = getParams();
  const fileNames = buildExportFileNames(params);
  const exportInfo = buildGodotExportInfo(params);
  const samplingParams = {
    atlas_padding_px: ATLAS_PADDING_PX,
    back_rim_ratio: params.backRimRatio,
    deterministic_proof: state.generated.audit?.deterministicProof?.combinedHash || "",
    face_slope: params.faceSlope,
    generated_recipe: fileNames.recipe,
    noise_preset: params.noisePreset,
    normal_strength: params.normalStrength,
    texture_scale: params.textureScale,
    tint_jitter: params.tintJitter,
    top_tint: params.topTint,
    face_tint: params.faceTint,
    base_tint: params.baseTint
  };
  return `[gd_resource type="Resource" script_class="TerrainMaterialSet" load_steps=8 format=3]

[ext_resource type="Script" path="res://data/terrain/terrain_material_set.gd" id="1"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.topAlbedo}" id="2"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.faceAlbedo}" id="3"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.topModulation}" id="4"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.faceModulation}" id="5"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.topNormal}" id="6"]
[ext_resource type="Texture2D" path="${exportInfo.assetDir}/${fileNames.faceNormal}" id="7"]

[resource]
script = ExtResource("1")
id = &"${exportInfo.materialId}"
shader_family_id = &"terrain.ground_hybrid"
top_albedo = ExtResource("2")
face_albedo = ExtResource("3")
top_modulation = ExtResource("4")
face_modulation = ExtResource("5")
top_normal = ExtResource("6")
face_normal = ExtResource("7")
sampling_params = ${formatGodotDictionary(samplingParams)}
`;
}

function buildExportFileNames(params = getParams()) {
  const base = buildExportBaseName(params);
  return {
    albedoAtlas: `${base}_albedo_atlas.png`,
    maskAtlas: `${base}_mask_atlas.png`,
    shapeNormalAtlas: `${base}_shape_normal_atlas.png`,
    heightAtlas: `${base}_height_atlas.png`,
    ormAtlas: `${base}_orm_atlas.png`,
    emissionAtlas: `${base}_emission_atlas.png`,
    flowAtlas: `${base}_flow_atlas.png`,
    topAlbedo: `${base}_top_albedo.png`,
    faceAlbedo: `${base}_face_albedo.png`,
    topModulation: `${base}_top_modulation.png`,
    faceModulation: `${base}_face_modulation.png`,
    topNormal: `${base}_top_normal.png`,
    faceNormal: `${base}_face_normal.png`,
    preview: `${base}_preview.png`,
    recipe: `${base}_material_recipe.json`,
    shapeSetTres: `${base}_terrain_shape_set.tres`,
    materialSetTres: `${base}_terrain_material_set.tres`,
    zip: `${base}_bundle.zip`
  };
}

function buildMaterialRecipePayload() {
  const params = getParams();
  const fileNames = buildExportFileNames(params);
  return {
    tool: "Cliff Forge 47",
    version: 7,
    generatedAt: new Date().toISOString(),
    preset: state.preset,
    customPresetName: state.customPresetName || null,
    previewMode: state.previewMode,
    params,
    materialLayers: serializeMaterialLayers(state.materialLayers),
    map: {
      width: state.map.width,
      height: state.map.height,
      cells: state.map.cells.slice()
    },
    textures: {
      base: state.textureNames.base,
      top: state.textureNames.top,
      face: state.textureNames.face
    },
    atlasLayout: {
      columns: 8,
      paddingPx: ATLAS_PADDING_PX,
      cellSizePx: params.tileSize + ATLAS_PADDING_PX * 2
    },
    channelPacking: {
      maskAtlas: { R: "top mask", G: "face mask", B: "back rim mask", A: "occupancy" },
      heightAtlas: { RGB: "combined shape + material height", A: "occupancy" },
      ormAtlas: { R: "occlusion", G: "roughness", B: "metallic", A: "occupancy" },
      emissionAtlas: { RGB: "emission color", A: "occupancy" },
      flowAtlas: { R: "flow x encoded to 0..1", G: "flow y encoded to 0..1", B: "flow magnitude", A: "occupancy" }
    },
    exports: fileNames,
    atlasManifest: state.generated.atlasManifest,
    audits: state.generated.audit
  };
}

function downloadMaterialRecipe() {
  const payload = buildMaterialRecipePayload();
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  downloadBlob(blob, payload.exports.recipe);
}

function canvasToBlobAsync(canvas) {
  return new Promise((resolve, reject) => {
    if (!canvas) {
      reject(new Error("Canvas missing"));
      return;
    }
    canvas.toBlob((blob) => {
      if (!blob) reject(new Error("Canvas export failed"));
      else resolve(blob);
    }, "image/png");
  });
}

function crc32(bytes) {
  if (!crc32.table) {
    crc32.table = new Uint32Array(256);
    for (let i = 0; i < 256; i += 1) {
      let c = i;
      for (let j = 0; j < 8; j += 1) {
        c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      }
      crc32.table[i] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i += 1) {
    crc = crc32.table[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function buildZipBlob(files) {
  const encoder = new TextEncoder();
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  files.forEach((file) => {
    const nameBytes = encoder.encode(file.name);
    const data = file.bytes;
    const header = new Uint8Array(30 + nameBytes.length);
    const headerView = new DataView(header.buffer);
    headerView.setUint32(0, 0x04034b50, true);
    headerView.setUint16(4, 20, true);
    headerView.setUint16(6, 0, true);
    headerView.setUint16(8, 0, true);
    headerView.setUint16(10, 0, true);
    headerView.setUint16(12, 0, true);
    headerView.setUint32(14, crc32(data), true);
    headerView.setUint32(18, data.length, true);
    headerView.setUint32(22, data.length, true);
    headerView.setUint16(26, nameBytes.length, true);
    headerView.setUint16(28, 0, true);
    header.set(nameBytes, 30);
    localParts.push(header, data);

    const central = new Uint8Array(46 + nameBytes.length);
    const centralView = new DataView(central.buffer);
    centralView.setUint32(0, 0x02014b50, true);
    centralView.setUint16(4, 20, true);
    centralView.setUint16(6, 20, true);
    centralView.setUint16(8, 0, true);
    centralView.setUint16(10, 0, true);
    centralView.setUint16(12, 0, true);
    centralView.setUint16(14, 0, true);
    centralView.setUint32(16, crc32(data), true);
    centralView.setUint32(20, data.length, true);
    centralView.setUint32(24, data.length, true);
    centralView.setUint16(28, nameBytes.length, true);
    centralView.setUint16(30, 0, true);
    centralView.setUint16(32, 0, true);
    centralView.setUint16(34, 0, true);
    centralView.setUint16(36, 0, true);
    centralView.setUint32(38, 0, true);
    centralView.setUint32(42, offset, true);
    central.set(nameBytes, 46);
    centralParts.push(central);

    offset += header.length + data.length;
  });

  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0);
  const end = new Uint8Array(22);
  const endView = new DataView(end.buffer);
  endView.setUint32(0, 0x06054b50, true);
  endView.setUint16(4, 0, true);
  endView.setUint16(6, 0, true);
  endView.setUint16(8, files.length, true);
  endView.setUint16(10, files.length, true);
  endView.setUint32(12, centralSize, true);
  endView.setUint32(16, offset, true);
  endView.setUint16(20, 0, true);

  return new Blob([...localParts, ...centralParts, end], { type: "application/zip" });
}

async function downloadBundleZip() {
  const fileNames = buildExportFileNames();
  const recipeBytes = new TextEncoder().encode(JSON.stringify(buildMaterialRecipePayload(), null, 2));
  const shapeSetTresBytes = new TextEncoder().encode(buildShapeSetTres());
  const materialSetTresBytes = new TextEncoder().encode(buildMaterialSetTres());
  const files = [
    { name: fileNames.albedoAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.albedo)).arrayBuffer()) },
    { name: fileNames.maskAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.mask)).arrayBuffer()) },
    { name: fileNames.shapeNormalAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.shapeNormal)).arrayBuffer()) },
    { name: fileNames.heightAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.height)).arrayBuffer()) },
    { name: fileNames.ormAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.orm)).arrayBuffer()) },
    { name: fileNames.emissionAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.emission)).arrayBuffer()) },
    { name: fileNames.flowAtlas, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.atlases.flow)).arrayBuffer()) },
    { name: fileNames.topAlbedo, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.material.topAlbedo)).arrayBuffer()) },
    { name: fileNames.faceAlbedo, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.material.faceAlbedo)).arrayBuffer()) },
    { name: fileNames.topModulation, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.material.top?.canvas)).arrayBuffer()) },
    { name: fileNames.faceModulation, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.material.face?.canvas)).arrayBuffer()) },
    { name: fileNames.topNormal, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.material.top?.normalCanvas)).arrayBuffer()) },
    { name: fileNames.faceNormal, bytes: new Uint8Array(await (await canvasToBlobAsync(state.generated.material.face?.normalCanvas)).arrayBuffer()) },
    { name: fileNames.preview, bytes: new Uint8Array(await (await canvasToBlobAsync(state.preview.sourceCanvas || refs.previewCanvas)).arrayBuffer()) },
    { name: fileNames.recipe, bytes: recipeBytes },
    { name: fileNames.shapeSetTres, bytes: shapeSetTresBytes },
    { name: fileNames.materialSetTres, bytes: materialSetTresBytes }
  ];
  downloadBlob(buildZipBlob(files), fileNames.zip);
}

function zoomPreviewTo(nextScale, clientX, clientY) {
  const view = state.preview.view;
  const targetScale = clamp(nextScale, 0.5, 6);
  if (!refs.previewViewport) {
    view.scale = targetScale;
    applyPreviewTransform();
    return;
  }
  const rect = refs.previewViewport.getBoundingClientRect();
  const localX = clientX - rect.left;
  const localY = clientY - rect.top;
  const worldX = (localX - view.offsetX) / view.scale;
  const worldY = (localY - view.offsetY) / view.scale;
  view.scale = targetScale;
  view.offsetX = localX - worldX * view.scale;
  view.offsetY = localY - worldY * view.scale;
  applyPreviewTransform();
}

function shuffleSeed() {
  refs.seed.value = String(Math.floor(Math.random() * 2147483647));
  markDirty("material");
  markDirty("color");
  markDirty("variants");
  scheduleRender("full");
}

function loadMaterialRecipe(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = (event) => {
    try {
      const payload = JSON.parse(event.target.result);
      const params = payload.params ?? payload;
      Object.entries(params).forEach(([key, value]) => {
        if (refs[key]) refs[key].value = String(value);
      });
      if (payload.preset && PRESETS[payload.preset]) {
        state.preset = payload.preset;
        refs.presetButtons.forEach((button) => {
          button.classList.toggle("active", button.dataset.preset === payload.preset);
        });
      }
      if (payload.previewMode && PREVIEW_MODES.includes(payload.previewMode)) {
        refs.previewMode.value = payload.previewMode;
        state.previewMode = payload.previewMode;
      }
      state.customPresetName = payload.customPresetName || "";
      state.materialLayers = normalizeMaterialLayers(payload.materialLayers, state.preset);
      refs.customPresetName.value = state.customPresetName;
      refreshPaletteButtons();
      renderMaterialLayerControls();
      refreshCustomPresetOptions();
      if (state.customPresetName) refs.customPresetSelect.value = state.customPresetName;
      if (payload.map && Array.isArray(payload.map.cells) && payload.map.cells.length === state.map.width * state.map.height) {
        restoreMapSnapshot(payload.map.cells);
      }
      state.history.past = [];
      state.history.future = [];
      state.history.strokeSnapshot = null;
      updateHistoryButtons();
      updateRangeLabels();
      refreshGalleryOptions();
      markDirty("all");
      scheduleRender("full");
    } catch (error) {
      refs.status.innerHTML = `<span class="warn">Ошибка JSON.</span> ${error.message}`;
    } finally {
      refs.loadJson.value = "";
    }
  };
  reader.readAsText(file);
}

function undoMap() {
  if (!state.history.past.length) return;
  const previous = state.history.past.pop();
  state.history.future.push(createSnapshotFromMap());
  restoreMapSnapshot(previous);
  updateHistoryButtons();
  if (state.generated.tiles.length) {
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
    persistSessionState();
  }
}

function redoMap() {
  if (!state.history.future.length) return;
  const next = state.history.future.pop();
  state.history.past.push(createSnapshotFromMap());
  restoreMapSnapshot(next);
  updateHistoryButtons();
  if (state.generated.tiles.length) {
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
    persistSessionState();
  }
}

function bindPreviewPainting() {
  const canvas = refs.previewCanvas;
  let painting = false;
  let paintValue = 1;

  function isPanGesture(event) {
    return event.button === 1 || (event.button === 0 && state.preview.view.spaceHeld);
  }

  function applyPaint(event) {
    const rect = canvas.getBoundingClientRect();
    const logicalWidth = Number(canvas.dataset.logicalWidth || canvas.width);
    const logicalHeight = Number(canvas.dataset.logicalHeight || canvas.height);
    const scaleX = logicalWidth / rect.width;
    const scaleY = logicalHeight / rect.height;
    const tileSize = state.preview.logicalTileSize || getParams().tileSize;
    const x = Math.floor(((event.clientX - rect.left) * scaleX) / tileSize);
    const y = Math.floor(((event.clientY - rect.top) * scaleY) / tileSize);
    if (x < 0 || y < 0 || x >= state.map.width || y >= state.map.height) return;
    setMapCell(x, y, paintValue);
    markDirty("map");
    drawPreview();
    state.dirty.map = false;
  }

  canvas.addEventListener("pointerdown", (event) => {
    if (isPanGesture(event)) {
      if (event.button === 0 && state.preview.view.spaceHeld) {
        state.preview.view.spaceUsedForPan = true;
      }
      state.preview.view.isPanning = true;
      state.preview.view.pointerId = event.pointerId;
      state.preview.view.originX = event.clientX - state.preview.view.offsetX;
      state.preview.view.originY = event.clientY - state.preview.view.offsetY;
      canvas.setPointerCapture?.(event.pointerId);
      applyPreviewTransform();
      return;
    }
    if (event.button !== 0 && event.button !== 2) return;
    painting = true;
    paintValue = event.button === 2 ? 0 : 1;
    beginHistoryStroke();
    canvas.setPointerCapture?.(event.pointerId);
    applyPaint(event);
  });
  canvas.addEventListener("pointermove", (event) => {
    if (state.preview.view.isPanning && state.preview.view.pointerId === event.pointerId) {
      state.preview.view.offsetX = event.clientX - state.preview.view.originX;
      state.preview.view.offsetY = event.clientY - state.preview.view.originY;
      applyPreviewTransform();
      return;
    }
    if (painting) applyPaint(event);
  });
  function releasePointerInteraction(event) {
    if (state.preview.view.isPanning && state.preview.view.pointerId === event.pointerId) {
      state.preview.view.isPanning = false;
      state.preview.view.pointerId = null;
      if (canvas.hasPointerCapture?.(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
      applyPreviewTransform();
      return;
    }
    if (!painting) return;
    painting = false;
    if (canvas.hasPointerCapture?.(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    commitHistoryStroke();
  }
  window.addEventListener("pointerup", releasePointerInteraction);
  window.addEventListener("pointercancel", releasePointerInteraction);
  canvas.addEventListener("contextmenu", (event) => event.preventDefault());
}

function bindPreviewViewport() {
  refs.previewViewport.addEventListener("wheel", (event) => {
    event.preventDefault();
    const factor = event.deltaY < 0 ? 1.12 : 1 / 1.12;
    zoomPreviewTo(state.preview.view.scale * factor, event.clientX, event.clientY);
  }, { passive: false });
  refs.resetPreviewView.addEventListener("click", resetPreviewView);
  updatePreviewZoomLabel();
}

function bindShortcuts() {
  function isEditingElement() {
    const activeTag = document.activeElement?.tagName;
    return activeTag === "INPUT" || activeTag === "SELECT" || activeTag === "TEXTAREA";
  }

  window.addEventListener("keydown", (event) => {
    const editing = isEditingElement();
    if (event.code === "Space" && !editing) {
      if (!state.preview.view.spaceHeld) {
        state.preview.view.spaceHeld = true;
        state.preview.view.spaceUsedForPan = false;
      }
      event.preventDefault();
    }
    if (editing) return;
    const key = event.key.toLowerCase();
    const isUndo = (event.ctrlKey || event.metaKey) && !event.shiftKey && key === "z";
    const isRedo = (event.ctrlKey || event.metaKey) && (key === "y" || (event.shiftKey && key === "z"));
    if (isUndo) {
      event.preventDefault();
      undoMap();
    } else if (isRedo) {
      event.preventDefault();
      redoMap();
    } else if (!event.ctrlKey && !event.metaKey && key === "r") {
      event.preventDefault();
      shuffleSeed();
    } else if (!event.ctrlKey && !event.metaKey && event.code === "Space") {
      event.preventDefault();
    } else if (!event.ctrlKey && !event.metaKey && ["1", "2", "3"].includes(event.key)) {
      event.preventDefault();
      const button = refs.presetButtons[Number(event.key) - 1];
      button?.click();
    }
  });
  window.addEventListener("keyup", (event) => {
    if (event.code === "Space") {
      const editing = isEditingElement();
      const usedForPan = state.preview.view.spaceUsedForPan || state.preview.view.isPanning;
      state.preview.view.spaceHeld = false;
      state.preview.view.spaceUsedForPan = false;
      if (editing) return;
      event.preventDefault();
      if (usedForPan) return;
      markDirty("all");
      scheduleRender("full");
    }
  });
  window.addEventListener("blur", () => {
    state.preview.view.spaceHeld = false;
    state.preview.view.spaceUsedForPan = false;
    if (state.preview.view.isPanning) {
      state.preview.view.isPanning = false;
      state.preview.view.pointerId = null;
      applyPreviewTransform();
    }
  });
}

function bindUi() {
  refs.presetButtons.forEach((button) => {
    button.addEventListener("click", () => {
      applyPreset(button.dataset.preset);
      refreshGalleryOptions();
      markDirty("shape");
      markDirty("material");
      markDirty("color");
      markDirty("variants");
      scheduleRender("full");
    });
  });

  const shapeRangeIds = new Set([
    "tileSize",
    "heightPx",
    "lipPx",
    "backRimRatio",
    "northRimThickness",
    "northHeightPx",
    "eastHeightPx",
    "westHeightPx",
    "roughness",
    "faceSlope",
    "crownBevel",
    "outerChamfer",
    "baseErosion",
    "normalStrength"
  ]);
  const materialRangeIds = new Set(["topMacroScale", "topMacroStrength", "topPebbleDensity", "topPebbleSize", "topMicroNoise", "topContrast", "faceStrataStrength", "faceVerticalFractures", "faceChips", "faceErosion", "faceContrast", "sunAzimuth"]);
  const colorRangeIds = new Set(["textureScale", "tintJitter", "topTintOpacity", "faceTintOpacity", "baseTintOpacity"]);

  RANGE_IDS.forEach((id) => {
    refs[id].addEventListener("input", () => {
      updateRangeLabels();
      if (id === "variants") refreshGalleryOptions();
      if (shapeRangeIds.has(id)) markDirty("shape");
      else if (materialRangeIds.has(id)) markDirty("material");
      else if (colorRangeIds.has(id)) markDirty("color");
      if (id === "variants") markDirty("variants");
      scheduleRender("draft");
    });
    refs[id].addEventListener("change", () => {
      if (shapeRangeIds.has(id)) markDirty("shape");
      else if (materialRangeIds.has(id)) markDirty("material");
      else if (colorRangeIds.has(id)) markDirty("color");
      if (id === "variants") markDirty("variants");
      scheduleRender("full");
    });
  });

  refs.previewMode.addEventListener("change", refreshVisibleOutputs);
  refs.innerCornerMode.addEventListener("change", () => {
    markDirty("shape");
    scheduleRender("full");
  });
  ["cornerOverrideNE", "cornerOverrideNW", "cornerOverrideSE", "cornerOverrideSW"].forEach((id) => {
    refs[id].addEventListener("change", () => {
      markDirty("shape");
      scheduleRender("full");
    });
  });
  refs.seed.addEventListener("change", () => {
    markDirty("material");
    markDirty("color");
    markDirty("variants");
    scheduleRender("full");
  });
  refs.galleryVariant.addEventListener("change", () => {
    markDirty("gallery");
    buildGallery();
    state.dirty.gallery = false;
  });
  refs.regenerate.addEventListener("click", () => {
    markDirty("all");
    scheduleRender("full");
  });
  COLOR_IDS.forEach((id) => {
    refs[id].addEventListener("input", () => {
      refreshPaletteButtons();
      markDirty("color");
      scheduleRender("draft");
    });
    refs[id].addEventListener("change", () => {
      refreshPaletteButtons();
      markDirty("color");
      scheduleRender("full");
    });
  });

  refs.applyNoisePreset.addEventListener("click", applyNoisePreset);
  refs.extractPalette.addEventListener("click", extractPaletteFromTextures);
  refs.addMaterialLayer.addEventListener("click", () => addMaterialLayer(refs.layerLibraryType.value));
  refs.paletteButtons.forEach((button) => {
    button.addEventListener("click", () => applyBiomePalette(button.dataset.palette));
  });

  refs.baseTexture.addEventListener("change", () => readTexture(refs.baseTexture, "base"));
  refs.topTexture.addEventListener("change", () => readTexture(refs.topTexture, "top"));
  refs.faceTexture.addEventListener("change", () => readTexture(refs.faceTexture, "face"));
  refs.saveCustomPreset.addEventListener("click", saveCurrentCustomPreset);
  refs.loadCustomPreset.addEventListener("click", loadSelectedCustomPreset);
  refs.deleteCustomPreset.addEventListener("click", deleteSelectedCustomPreset);
  refs.customPresetSelect.addEventListener("change", () => {
    const selected = refs.customPresetSelect.value;
    if (selected) refs.customPresetName.value = selected;
  });

  refs.randomBlob.addEventListener("click", createBlobMap);
  refs.randomCave.addEventListener("click", createCaveMap);
  refs.roomMap.addEventListener("click", createRoomMap);
  refs.clearMap.addEventListener("click", clearMap);
  refs.undoMap.addEventListener("click", undoMap);
  refs.redoMap.addEventListener("click", redoMap);

  refs.downloadAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.albedo, buildExportFileNames().albedoAtlas));
  refs.downloadMaskAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.mask, buildExportFileNames().maskAtlas));
  refs.downloadNormalAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.shapeNormal, buildExportFileNames().shapeNormalAtlas));
  refs.downloadTopAlbedo.addEventListener("click", () => downloadCanvas(state.generated.material.topAlbedo, buildExportFileNames().topAlbedo));
  refs.downloadFaceAlbedo.addEventListener("click", () => downloadCanvas(state.generated.material.faceAlbedo, buildExportFileNames().faceAlbedo));
  refs.downloadTopModulation.addEventListener("click", () => downloadCanvas(state.generated.material.top?.canvas, buildExportFileNames().topModulation));
  refs.downloadFaceModulation.addEventListener("click", () => downloadCanvas(state.generated.material.face?.canvas, buildExportFileNames().faceModulation));
  refs.downloadTopNormal.addEventListener("click", () => downloadCanvas(state.generated.material.top?.normalCanvas, buildExportFileNames().topNormal));
  refs.downloadFaceNormal.addEventListener("click", () => downloadCanvas(state.generated.material.face?.normalCanvas, buildExportFileNames().faceNormal));
  refs.downloadHeightAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.height, buildExportFileNames().heightAtlas));
  refs.downloadOrmAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.orm, buildExportFileNames().ormAtlas));
  refs.downloadEmissionAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.emission, buildExportFileNames().emissionAtlas));
  refs.downloadFlowAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.flow, buildExportFileNames().flowAtlas));
  refs.downloadPreview.addEventListener("click", () => downloadCanvas(state.preview.sourceCanvas || refs.previewCanvas, buildExportFileNames().preview));
  refs.downloadJson.addEventListener("click", downloadMaterialRecipe);
  refs.downloadShapeTres.addEventListener("click", () => downloadTextFile(buildShapeSetTres(), buildExportFileNames().shapeSetTres, "text/plain;charset=utf-8"));
  refs.downloadMaterialTres.addEventListener("click", () => downloadTextFile(buildMaterialSetTres(), buildExportFileNames().materialSetTres, "text/plain;charset=utf-8"));
  refs.downloadZip.addEventListener("click", () => {
    downloadBundleZip().catch((error) => {
      refs.status.innerHTML = `<span class="warn">Ошибка ZIP.</span> ${error.message}`;
    });
  });
  refs.loadJson.addEventListener("change", () => loadMaterialRecipe(refs.loadJson.files[0]));
}

function boot() {
  buildCatalog();
  initMap();
  applyPreset("mountain");
  refreshCustomPresetOptions();
  bindGroupCollapsers();
  bindControlSearch();
  applyTooltips();
  bindTextureDrop();
  bindPreviewViewport();
  const restoredSession = restoreSessionState();
  refs.catalogInfo.textContent = `${state.catalog.length}/47`;
  bindUi();
  bindPreviewPainting();
  bindShortcuts();
  updateHistoryButtons();
  if (!restoredSession) createBlobMap();
  markDirty("all");
  scheduleRender("full");
}

boot();
