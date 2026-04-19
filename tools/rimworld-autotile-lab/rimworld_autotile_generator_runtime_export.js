const PRESETS = {
  mountain: {
    heightPx: 18,
    lipPx: 6,
    backRimRatio: 0.55,
    northRimThickness: 0,
    roughness: 74,
    faceSlope: 100,
    innerCornerMode: "caps",
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
    roughness: 18,
    faceSlope: 130,
    innerCornerMode: "box",
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
    roughness: 54,
    faceSlope: 78,
    innerCornerMode: "bevel",
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
  previewMode: document.getElementById("previewMode"),
  tileSize: document.getElementById("tileSize"),
  heightPx: document.getElementById("heightPx"),
  lipPx: document.getElementById("lipPx"),
  backRimRatio: document.getElementById("backRimRatio"),
  northRimThickness: document.getElementById("northRimThickness"),
  roughness: document.getElementById("roughness"),
  faceSlope: document.getElementById("faceSlope"),
  innerCornerMode: document.getElementById("innerCornerMode"),
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
  baseTexture: document.getElementById("baseTexture"),
  topTexture: document.getElementById("topTexture"),
  faceTexture: document.getElementById("faceTexture"),
  baseFileName: document.getElementById("baseFileName"),
  topFileName: document.getElementById("topFileName"),
  faceFileName: document.getElementById("faceFileName"),
  baseTexturePreview: document.getElementById("baseTexturePreview"),
  topTexturePreview: document.getElementById("topTexturePreview"),
  faceTexturePreview: document.getElementById("faceTexturePreview"),
  previewCanvas: document.getElementById("previewCanvas"),
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
  downloadAtlas: document.getElementById("downloadAtlas"),
  downloadMaskAtlas: document.getElementById("downloadMaskAtlas"),
  downloadNormalAtlas: document.getElementById("downloadNormalAtlas"),
  downloadTopModulation: document.getElementById("downloadTopModulation"),
  downloadFaceModulation: document.getElementById("downloadFaceModulation"),
  downloadPreview: document.getElementById("downloadPreview"),
  downloadJson: document.getElementById("downloadJson"),
  regenerate: document.getElementById("regenerate")
};

const RANGE_IDS = [
  "tileSize",
  "heightPx",
  "lipPx",
  "backRimRatio",
  "northRimThickness",
  "roughness",
  "faceSlope",
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
  "faceContrast"
];

const COLOR_IDS = ["topTint", "faceTint", "baseTint"];
const PREVIEW_MODES = ["albedo", "mask", "shapeHeight", "shapeNormal", "shaderComposite"];
const MATERIAL_EXPORT_SIZE = 256;

const state = {
  preset: "mountain",
  previewMode: "shaderComposite",
  catalog: [],
  catalogByKey: new Map(),
  textures: { base: null, top: null, face: null },
  textureNames: { base: "procedural", top: "procedural", face: "procedural" },
  generated: {
    tiles: [],
    baseVariants: [],
    atlasManifest: [],
    atlases: {},
    material: { top: null, face: null }
  },
  map: { width: 18, height: 12, cells: [] },
  pendingRender: null
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

function createCanvas(width, height) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  return canvas;
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

function buildTopMaterialMap(params) {
  const width = MATERIAL_EXPORT_SIZE;
  const height = MATERIAL_EXPORT_SIZE;
  const values = new Float32Array(width * height);
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

  const alpha = arrayFilled(values.length, 255);
  return {
    width,
    height,
    values,
    alpha,
    canvas: buildScalarCanvas(values, alpha, width, height),
    normalCanvas: buildNormalCanvas(values, alpha, width, height, 0.8)
  };
}

function buildFaceMaterialMap(params) {
  const width = MATERIAL_EXPORT_SIZE;
  const height = MATERIAL_EXPORT_SIZE;
  const values = new Float32Array(width * height);
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

  const alpha = arrayFilled(values.length, 255);
  return {
    width,
    height,
    values,
    alpha,
    canvas: buildScalarCanvas(values, alpha, width, height),
    normalCanvas: buildNormalCanvas(values, alpha, width, height, 0.75)
  };
}

function getParams() {
  return {
    tileSize: Number(refs.tileSize.value),
    heightPx: Number(refs.heightPx.value),
    lipPx: Number(refs.lipPx.value),
    backRimRatio: Number(refs.backRimRatio.value),
    northRimThickness: Number(refs.northRimThickness.value),
    roughness: Number(refs.roughness.value),
    faceSlope: Number(refs.faceSlope.value),
    innerCornerMode: refs.innerCornerMode.value,
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
    faceContrast: Number(refs.faceContrast.value)
  };
}

function formatRangeValue(id, value) {
  if (id === "backRimRatio") return Number(value).toFixed(2);
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
  const preset = PRESETS[name];
  Object.entries(preset).forEach(([key, value]) => {
    if (refs[key]) refs[key].value = String(value);
  });
  refs.presetButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.preset === name);
  });
  updateRangeLabels();
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
    Math.round(params.lipPx * params.backRimRatio + params.northRimThickness),
    1,
    Math.max(1, Math.floor(params.tileSize * 0.25))
  );
}

function buildProfiles(signature, variantSeed, params) {
  const size = params.tileSize;
  const roughness = params.roughness / 100;
  const profileScale = state.preset === "wall" ? 1.2 : state.preset === "earth" ? 2 : 3.5;
  const driftStrength = roughness * profileScale;
  const backLipPx = backRimThickness(params);
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
    north[index] = signature.openN ? clamp(backLipPx + northNoise * driftStrength, 1, size * 0.22) : 0;
    south[index] = signature.openS ? clamp(params.heightPx + southNoise * driftStrength * 1.2, 2, size * 0.48) : 0;
    west[index] = signature.openW ? clamp(params.lipPx + westNoise * driftStrength, 1, size * 0.24) : 0;
    east[index] = signature.openE ? clamp(params.lipPx + eastNoise * driftStrength, 1, size * 0.24) : 0;
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
  const topDimsBase = { width: Math.max(1, params.lipPx), height: Math.max(1, backRimThickness(params)) };
  const bottomDimsBase = { width: Math.max(1, params.lipPx), height: Math.max(1, params.heightPx) };
  const mode = params.innerCornerMode;

  function dims(base, saltW, saltH) {
    const widthBase = mode === "box" ? Math.max(base.width, base.height) : base.width;
    const heightBase = mode === "box" ? Math.max(base.width, base.height) : base.height;
    return {
      width: jaggedSize(widthBase, x, y, params, saltW),
      height: jaggedSize(heightBase, y, x, params, saltH)
    };
  }

  if (signature.notchNE) {
    const current = dims(topDimsBase, 31, 37);
    const dx = sample.right - x;
    const dy = y - sample.top;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "back", dx, dy, width: current.width, height: current.height };
  }
  if (signature.notchNW) {
    const current = dims(topDimsBase, 41, 43);
    const dx = x - sample.left;
    const dy = y - sample.top;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "back", dx, dy, width: current.width, height: current.height };
  }
  if (signature.notchSE) {
    const current = dims(bottomDimsBase, 47, 53);
    const dx = sample.right - x;
    const dy = sample.bottom - y;
    if (overlayContains(mode, dx, dy, current.width, current.height)) return { zone: "face", dx, dy, width: current.width, height: current.height };
  }
  if (signature.notchSW) {
    const current = dims(bottomDimsBase, 59, 61);
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

function computePixelHeight(zone, sample, overlay, params, x, y) {
  if (zone === "empty") return 0;
  if (zone === "top") return 1;

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

function buildSurfaceColor(kind, zone, x, y, params, offsets) {
  const isTopLike = kind === "top";
  const tint = hexToRgb(isTopLike ? params.topTint : params.faceTint);
  const texture = isTopLike ? state.textures.top : state.textures.face;
  const tintOpacity = isTopLike ? params.topTintOpacity : params.faceTintOpacity;
  const materialMap = isTopLike ? state.generated.material.top : state.generated.material.face;
  const sample = sampleTextureColor(texture, x, y, params, offsets);
  const modulation = sampleScalar(materialMap.values, materialMap.width, materialMap.height, x + offsets.ox, y + offsets.oy);
  const zoneBrightness = zone === "back" ? 0.84 : zone === "face" ? 0.7 : 1;
  const gain = isTopLike
    ? (0.74 + modulation * 0.48) * zoneBrightness * offsets.brightness
    : (0.58 + modulation * 0.55) * zoneBrightness * offsets.brightness;
  const baseColor = sample ? applyTintToSample(sample, tint, tintOpacity) : tint;
  return scaleColor(baseColor, gain);
}

function paintLayeredTile(tile, params, offsets, compositeMode, originX = 0, originY = 0) {
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
      const color = buildSurfaceColor(zone === "face" ? "face" : "top", zone, sampleX, sampleY, params, offsets);
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

function globalPreviewOffsets(params, slot) {
  const salt = slot === "base" ? 1709 : 2719;
  return {
    ox: Math.floor(hash2D(params.seed + salt, salt * 3, salt * 7) * 8192),
    oy: Math.floor(hash2D(params.seed + salt * 5, salt * 11, salt * 13) * 8192),
    brightness: 1
  };
}

function drawContinuousBasePreview(ctx, params) {
  const width = state.map.width * params.tileSize;
  const height = state.map.height * params.tileSize;
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

function renderTile(signature, variantIndex, params) {
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
      const sample = classifyPixel(signature, profiles, params, x, y);
      const overlay = sample.zone === "empty" ? null : classifyNotchOverlay(signature, sample, params, x, y);
      const zone = resolveZone(sample, overlay);
      const index = y * size + x;
      if (zone === "empty") continue;
      alpha[index] = 255;
      if (zone === "top") topMask[index] = 255;
      if (zone === "face") faceMask[index] = 255;
      if (zone === "back") backMask[index] = 255;
      shapeHeight[index] = computePixelHeight(zone, sample, overlay, params, x, y);
    }
  }

  const shapeNormalCanvas = buildNormalCanvas(shapeHeight, alpha, size, size, params.normalStrength / 100);
  return {
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
      shaderComposite: null
    }
  };
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

function buildAtlases(params) {
  const columns = 8;
  const total = state.catalog.length * params.variants;
  const rows = Math.ceil(total / columns);
  state.generated.atlases = {};
  state.generated.atlasManifest = [];

  PREVIEW_MODES.forEach((mode) => {
    const canvas = createCanvas(columns * params.tileSize, rows * params.tileSize);
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    state.generated.atlases[mode] = canvas;
  });

  let atlasIndex = 0;
  for (let variantIndex = 0; variantIndex < params.variants; variantIndex += 1) {
    state.catalog.forEach((signature) => {
      const tile = state.generated.tiles[variantIndex].get(signature.key);
      const col = atlasIndex % columns;
      const row = Math.floor(atlasIndex / columns);
      const dx = col * params.tileSize;
      const dy = row * params.tileSize;
      PREVIEW_MODES.forEach((mode) => {
        state.generated.atlases[mode].getContext("2d").drawImage(tile.canvases[mode], dx, dy);
      });
      state.generated.atlasManifest.push({ atlasIndex, variant: variantIndex, key: signature.key, label: signature.label, column: col, row });
      atlasIndex += 1;
    });
  }
}

function refreshVisibleAtlas() {
  const source = state.generated.atlases[state.previewMode];
  if (!source) return;
  refs.atlasCanvas.width = source.width;
  refs.atlasCanvas.height = source.height;
  const ctx = refs.atlasCanvas.getContext("2d");
  ctx.clearRect(0, 0, source.width, source.height);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(source, 0, 0);
}

function buildGallery() {
  if (!state.generated.tiles.length) {
    refs.tileGrid.innerHTML = "";
    return;
  }
  const variantIndex = Number(refs.galleryVariant.value || 0);
  refs.tileGrid.innerHTML = "";
  state.catalog.forEach((signature) => {
    const tile = state.generated.tiles[variantIndex].get(signature.key);
    const card = document.createElement("div");
    card.className = "tile-card";
    const canvas = createCanvas(128, 128);
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(tile.canvases[state.previewMode], 0, 0, 128, 128);
    const title = document.createElement("strong");
    title.textContent = `${String(signature.index + 1).padStart(2, "0")} · ${signature.key}`;
    const meta = document.createElement("span");
    meta.textContent = signature.label;
    card.append(canvas, title, meta);
    refs.tileGrid.appendChild(card);
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

function chooseBaseVariantForCell(x, y, params) {
  const total = state.generated.baseVariants.length;
  return Math.floor(hash2D(x + 11, y + 17, params.seed + 1907) * total) % total;
}

function drawPreview() {
  if (!state.generated.tiles.length) return;
  const params = getParams();
  state.previewMode = refs.previewMode.value;
  const canvas = refs.previewCanvas;
  canvas.width = state.map.width * params.tileSize;
  canvas.height = state.map.height * params.tileSize;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  if (state.previewMode === "shaderComposite") {
    drawContinuousBasePreview(ctx, params);
  } else if (state.previewMode === "albedo") {
    for (let y = 0; y < state.map.height; y += 1) {
      for (let x = 0; x < state.map.width; x += 1) {
        const baseTile = state.generated.baseVariants[chooseBaseVariantForCell(x, y, params)];
        ctx.drawImage(baseTile, x * params.tileSize, y * params.tileSize);
      }
    }
  } else {
    ctx.fillStyle = "#0f0c0a";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
  }

  const compositeOffsets = state.previewMode === "shaderComposite"
    ? globalPreviewOffsets(params, "surface")
    : null;

  for (let y = 0; y < state.map.height; y += 1) {
    for (let x = 0; x < state.map.width; x += 1) {
      if (!getMapCell(x, y)) continue;
      const signature = signatureAt(x, y);
      const variantIndex = chooseVariantForCell(x, y, params);
      const tile = state.generated.tiles[variantIndex].get(signature.key);
      if (state.previewMode === "shaderComposite") {
        const compositeTile = paintLayeredTile(
          tile,
          params,
          compositeOffsets,
          true,
          x * params.tileSize,
          y * params.tileSize
        );
        ctx.drawImage(compositeTile, x * params.tileSize, y * params.tileSize);
      } else {
        ctx.drawImage(tile.canvases[state.previewMode], x * params.tileSize, y * params.tileSize);
      }
    }
  }
}

function drawSlotPreviewCanvas(canvas, slot, params) {
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(canvas.width, canvas.height);
  const offsets = { ox: params.seed * 7 + canvas.width, oy: params.seed * 13 + canvas.height, brightness: 1 };

  for (let y = 0; y < canvas.height; y += 1) {
    for (let x = 0; x < canvas.width; x += 1) {
      const out = (y * canvas.width + x) * 4;
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
}

function drawTilingPreview(targetCanvas, sourceCanvas) {
  const ctx = targetCanvas.getContext("2d");
  ctx.clearRect(0, 0, targetCanvas.width, targetCanvas.height);
  ctx.imageSmoothingEnabled = false;
  const halfWidth = Math.floor(targetCanvas.width / 2);
  const halfHeight = Math.floor(targetCanvas.height / 2);
  for (let y = 0; y < 2; y += 1) {
    for (let x = 0; x < 2; x += 1) {
      ctx.drawImage(sourceCanvas, x * halfWidth, y * halfHeight, halfWidth, halfHeight);
    }
  }
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
    scheduleRender();
    return;
  }

  const bitmap = await createImageBitmap(file);
  const canvas = createCanvas(bitmap.width, bitmap.height);
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(bitmap, 0, 0);
  if (typeof bitmap.close === "function") bitmap.close();
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
  state.textures[slot] = { width: canvas.width, height: canvas.height, data: image.data };
  state.textureNames[slot] = file.name;
  refs[`${slot}FileName`].textContent = file.name;
  scheduleRender();
}

function createRoomMap() {
  initMap();
  for (let y = 2; y < state.map.height - 2; y += 1) {
    for (let x = 3; x < state.map.width - 3; x += 1) {
      const border = x === 3 || y === 2 || x === state.map.width - 4 || y === state.map.height - 3;
      setMapCell(x, y, border ? 1 : 0);
    }
  }
  if (state.generated.tiles.length) drawPreview();
}

function createBlobMap() {
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
  if (state.generated.tiles.length) drawPreview();
}

function createCaveMap() {
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
  if (state.generated.tiles.length) drawPreview();
}

function clearMap() {
  initMap();
  if (state.generated.tiles.length) drawPreview();
}

function rebuildAll() {
  const params = getParams();
  state.previewMode = refs.previewMode.value;
  state.generated.material.top = buildTopMaterialMap(params);
  state.generated.material.face = buildFaceMaterialMap(params);

  state.generated.tiles = [];
  for (let variantIndex = 0; variantIndex < params.variants; variantIndex += 1) {
    const tileMap = new Map();
    state.catalog.forEach((signature) => {
      const tile = renderTile(signature, variantIndex, params);
      tile.canvases.albedo = paintLayeredTile(tile, params, tile.offsets, false);
      tile.canvases.shaderComposite = paintLayeredTile(tile, params, tile.offsets, true);
      tileMap.set(signature.key, tile);
    });
    state.generated.tiles.push(tileMap);
  }

  state.generated.baseVariants = renderBaseVariants(params);
  buildAtlases(params);
  refreshVisibleAtlas();
  buildGallery();
  drawPreview();
  drawSlotPreviewCanvas(refs.baseTexturePreview, "base", params);
  drawSlotPreviewCanvas(refs.topTexturePreview, "top", params);
  drawSlotPreviewCanvas(refs.faceTexturePreview, "face", params);
  drawTilingPreview(refs.topTilingCanvas, state.generated.material.top.canvas);
  drawTilingPreview(refs.faceTilingCanvas, state.generated.material.face.canvas);
  updateStats(params);
  refs.status.innerHTML = `<span class="ok">Готово.</span> ${state.catalog.length} сигнатур × ${params.variants} вариантов = ${state.catalog.length * params.variants} тайлов.`;
}

function refreshVisibleOutputs() {
  if (!state.generated.tiles.length) return;
  state.previewMode = refs.previewMode.value;
  refreshVisibleAtlas();
  buildGallery();
  drawPreview();
}

function scheduleRender() {
  if (state.pendingRender) cancelAnimationFrame(state.pendingRender);
  refs.status.textContent = "Пересобираю тайлы...";
  state.pendingRender = requestAnimationFrame(() => {
    state.pendingRender = null;
    rebuildAll();
  });
}

function downloadCanvas(canvas, fileName) {
  if (!canvas) return;
  canvas.toBlob((blob) => {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1200);
  }, "image/png");
}

function downloadMaterialRecipe() {
  const params = getParams();
  const payload = {
    tool: "Cliff Forge 47",
    version: 2,
    preset: state.preset,
    previewMode: state.previewMode,
    params,
    textures: {
      base: state.textureNames.base,
      top: state.textureNames.top,
      face: state.textureNames.face
    },
    channelPacking: {
      maskAtlas: { R: "top mask", G: "face mask", B: "back rim mask", A: "occupancy" }
    },
    exports: {
      albedoAtlas: "rimworld_47_albedo_atlas.png",
      maskAtlas: "rimworld_47_mask_atlas.png",
      shapeNormalAtlas: "rimworld_47_shape_normal_atlas.png",
      topModulation: "rimworld_top_modulation.png",
      faceModulation: "rimworld_face_modulation.png",
      preview: "rimworld_preview.png",
      recipe: "rimworld_material_recipe.json"
    },
    atlasManifest: state.generated.atlasManifest
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "rimworld_material_recipe.json";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1200);
}

function bindPreviewPainting() {
  const canvas = refs.previewCanvas;
  let painting = false;
  let paintValue = 1;

  function applyPaint(event) {
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    const tileSize = getParams().tileSize;
    const x = Math.floor(((event.clientX - rect.left) * scaleX) / tileSize);
    const y = Math.floor(((event.clientY - rect.top) * scaleY) / tileSize);
    if (x < 0 || y < 0 || x >= state.map.width || y >= state.map.height) return;
    setMapCell(x, y, paintValue);
    drawPreview();
  }

  canvas.addEventListener("pointerdown", (event) => {
    painting = true;
    paintValue = event.button === 2 ? 0 : 1;
    applyPaint(event);
  });
  canvas.addEventListener("pointermove", (event) => {
    if (painting) applyPaint(event);
  });
  window.addEventListener("pointerup", () => {
    painting = false;
  });
  canvas.addEventListener("contextmenu", (event) => event.preventDefault());
}

function bindUi() {
  refs.presetButtons.forEach((button) => {
    button.addEventListener("click", () => {
      applyPreset(button.dataset.preset);
      refreshGalleryOptions();
      scheduleRender();
    });
  });

  RANGE_IDS.forEach((id) => {
    refs[id].addEventListener("input", () => {
      updateRangeLabels();
      if (id === "variants") refreshGalleryOptions();
      scheduleRender();
    });
  });

  refs.previewMode.addEventListener("change", refreshVisibleOutputs);
  refs.innerCornerMode.addEventListener("change", scheduleRender);
  refs.seed.addEventListener("change", scheduleRender);
  refs.galleryVariant.addEventListener("change", buildGallery);
  refs.regenerate.addEventListener("click", scheduleRender);
  COLOR_IDS.forEach((id) => refs[id].addEventListener("input", scheduleRender));

  refs.baseTexture.addEventListener("change", () => readTexture(refs.baseTexture, "base"));
  refs.topTexture.addEventListener("change", () => readTexture(refs.topTexture, "top"));
  refs.faceTexture.addEventListener("change", () => readTexture(refs.faceTexture, "face"));

  refs.randomBlob.addEventListener("click", createBlobMap);
  refs.randomCave.addEventListener("click", createCaveMap);
  refs.roomMap.addEventListener("click", createRoomMap);
  refs.clearMap.addEventListener("click", clearMap);

  refs.downloadAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.albedo, "rimworld_47_albedo_atlas.png"));
  refs.downloadMaskAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.mask, "rimworld_47_mask_atlas.png"));
  refs.downloadNormalAtlas.addEventListener("click", () => downloadCanvas(state.generated.atlases.shapeNormal, "rimworld_47_shape_normal_atlas.png"));
  refs.downloadTopModulation.addEventListener("click", () => downloadCanvas(state.generated.material.top?.canvas, "rimworld_top_modulation.png"));
  refs.downloadFaceModulation.addEventListener("click", () => downloadCanvas(state.generated.material.face?.canvas, "rimworld_face_modulation.png"));
  refs.downloadPreview.addEventListener("click", () => downloadCanvas(refs.previewCanvas, "rimworld_preview.png"));
  refs.downloadJson.addEventListener("click", downloadMaterialRecipe);
}

function boot() {
  buildCatalog();
  initMap();
  applyPreset("mountain");
  refreshGalleryOptions();
  updateRangeLabels();
  refs.catalogInfo.textContent = `${state.catalog.length}/47`;
  bindUi();
  bindPreviewPainting();
  createBlobMap();
  scheduleRender();
}

boot();
