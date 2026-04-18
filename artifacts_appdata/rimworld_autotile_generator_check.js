
const PRESETS = {
  mountain: {
    heightPx: 18, lipPx: 6, roughness: 74, normalStrength: 90,
    textureScale: 100, variants: 4, topTint: "#6f5a43", faceTint: "#2f241d",
    baseTint: "#c79b63", tintJitter: 10
  },
  wall: {
    heightPx: 10, lipPx: 4, roughness: 18, normalStrength: 75,
    textureScale: 90, variants: 3, topTint: "#745335", faceTint: "#3d2c20",
    baseTint: "#c99d67", tintJitter: 6
  },
  earth: {
    heightPx: 8, lipPx: 5, roughness: 54, normalStrength: 70,
    textureScale: 120, variants: 4, topTint: "#704721", faceTint: "#50331f",
    baseTint: "#9f642f", tintJitter: 12
  }
};

const refs = {
  presetButtons: [...document.querySelectorAll("[data-preset]")],
  tileSize: document.getElementById("tileSize"),
  heightPx: document.getElementById("heightPx"),
  lipPx: document.getElementById("lipPx"),
  roughness: document.getElementById("roughness"),
  normalStrength: document.getElementById("normalStrength"),
  textureScale: document.getElementById("textureScale"),
  variants: document.getElementById("variants"),
  tintJitter: document.getElementById("tintJitter"),
  seed: document.getElementById("seed"),
  topTint: document.getElementById("topTint"),
  faceTint: document.getElementById("faceTint"),
  baseTint: document.getElementById("baseTint"),
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
  normalAtlasCanvas: document.getElementById("normalAtlasCanvas"),
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
  downloadNormalAtlas: document.getElementById("downloadNormalAtlas"),
  downloadPreview: document.getElementById("downloadPreview"),
  downloadJson: document.getElementById("downloadJson"),
  regenerate: document.getElementById("regenerate")
};

const RANGE_IDS = ["tileSize", "heightPx", "lipPx", "roughness", "normalStrength", "textureScale", "variants", "tintJitter"];
const COLOR_IDS = ["topTint", "faceTint", "baseTint"];

const state = {
  preset: "mountain",
  catalog: [],
  catalogByKey: new Map(),
  textures: { base: null, top: null, face: null },
  generated: { tiles: [], atlasManifest: [], baseVariants: [], atlasCanvas: null, normalAtlasCanvas: null },
  map: { width: 18, height: 12, cells: [] },
  pendingRender: null
};

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function smoothstep(a, b, x) {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

function mod(value, size) {
  return ((value % size) + size) % size;
}

function hash2D(x, y, seed) {
  let n = (x * 374761393 + y * 668265263 + seed * 1442695041) >>> 0;
  n = (n ^ (n >>> 13)) >>> 0;
  n = Math.imul(n, 1274126177) >>> 0;
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

function valueNoise(x, y, seed) {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = x - x0;
  const ty = y - y0;
  const v00 = hash2D(x0, y0, seed);
  const v10 = hash2D(x0 + 1, y0, seed);
  const v01 = hash2D(x0, y0 + 1, seed);
  const v11 = hash2D(x0 + 1, y0 + 1, seed);
  const sx = smoothstep(0, 1, tx);
  const sy = smoothstep(0, 1, ty);
  const ix0 = lerp(v00, v10, sx);
  const ix1 = lerp(v01, v11, sx);
  return lerp(ix0, ix1, sy);
}

function fbm(x, y, octaves, seed) {
  let amplitude = 1;
  let frequency = 1;
  let sum = 0;
  let weight = 0;
  for (let index = 0; index < octaves; index += 1) {
    sum += valueNoise(x * frequency, y * frequency, seed + index * 17) * amplitude;
    weight += amplitude;
    amplitude *= 0.5;
    frequency *= 2;
  }
  return weight ? sum / weight : 0;
}

function ridgeNoise(x, y, octaves, seed) {
  return 1 - Math.abs(fbm(x, y, octaves, seed) * 2 - 1);
}

function hexToRgb(hex) {
  return [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16)
  ];
}

function multiplyColor(color, factor) {
  return [
    clamp(Math.round(color[0] * factor), 0, 255),
    clamp(Math.round(color[1] * factor), 0, 255),
    clamp(Math.round(color[2] * factor), 0, 255)
  ];
}

function getParams() {
  return {
    tileSize: Number(refs.tileSize.value),
    heightPx: Number(refs.heightPx.value),
    lipPx: Number(refs.lipPx.value),
    roughness: Number(refs.roughness.value),
    normalStrength: Number(refs.normalStrength.value),
    textureScale: Number(refs.textureScale.value),
    variants: Number(refs.variants.value),
    tintJitter: Number(refs.tintJitter.value),
    seed: Number(refs.seed.value),
    topTint: refs.topTint.value,
    faceTint: refs.faceTint.value,
    baseTint: refs.baseTint.value
  };
}

function applyPreset(name) {
  state.preset = name;
  const preset = PRESETS[name];
  refs.heightPx.value = preset.heightPx;
  refs.lipPx.value = preset.lipPx;
  refs.roughness.value = preset.roughness;
  refs.normalStrength.value = preset.normalStrength;
  refs.textureScale.value = preset.textureScale;
  refs.variants.value = preset.variants;
  refs.topTint.value = preset.topTint;
  refs.faceTint.value = preset.faceTint;
  refs.baseTint.value = preset.baseTint;
  refs.tintJitter.value = preset.tintJitter;
  refs.presetButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.preset === name);
  });
  updateRangeLabels();
}

function updateRangeLabels() {
  RANGE_IDS.forEach((id) => {
    const label = document.getElementById(`${id}Value`);
    if (label) label.textContent = refs[id].value;
  });
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

function createRoomMap() {
  initMap();
  for (let y = 2; y < state.map.height - 2; y += 1) {
    for (let x = 3; x < state.map.width - 3; x += 1) {
      const border = x === 3 || y === 2 || x === state.map.width - 4 || y === state.map.height - 3;
      setMapCell(x, y, border ? 1 : 0);
    }
  }
  scheduleRender();
}

function createBlobMap() {
  initMap();
  const seed = getParams().seed + 91;
  const cx = state.map.width / 2;
  const cy = state.map.height / 2;
  for (let y = 0; y < state.map.height; y += 1) {
    for (let x = 0; x < state.map.width; x += 1) {
      const dx = (x - cx) / (state.map.width * 0.38);
      const dy = (y - cy) / (state.map.height * 0.38);
      const radial = 1 - Math.sqrt(dx * dx + dy * dy);
      const noise = fbm(x * 0.18, y * 0.18, 4, seed);
      setMapCell(x, y, radial + noise * 0.55 > 0.64);
    }
  }
  scheduleRender();
}

function createCaveMap() {
  initMap();
  const seed = getParams().seed + 403;
  for (let y = 0; y < state.map.height; y += 1) {
    for (let x = 0; x < state.map.width; x += 1) {
      setMapCell(x, y, fbm(x * 0.21, y * 0.21, 5, seed) > 0.56 ? 1 : 0);
    }
  }
  for (let pass = 0; pass < 3; pass += 1) {
    const next = state.map.cells.slice();
    for (let y = 0; y < state.map.height; y += 1) {
      for (let x = 0; x < state.map.width; x += 1) {
        let count = 0;
        for (let oy = -1; oy <= 1; oy += 1) {
          for (let ox = -1; ox <= 1; ox += 1) {
            if (ox === 0 && oy === 0) continue;
            count += getMapCell(x + ox, y + oy);
          }
        }
        next[y * state.map.width + x] = count >= 4 ? 1 : 0;
      }
    }
    state.map.cells = next;
  }
  scheduleRender();
}

function clearMap() {
  initMap();
  scheduleRender();
}

function smoothArray(array) {
  const copy = array.slice();
  for (let index = 1; index < array.length - 1; index += 1) {
    array[index] = (copy[index - 1] + copy[index] * 2 + copy[index + 1]) / 4;
  }
}

function backRimThickness(params) {
  return Math.max(1, Math.round(Math.max(1, params.lipPx) * 0.5));
}

function buildProfiles(signature, variantSeed, params) {
  const size = params.tileSize;
  const roughness = params.roughness / 100;
  const profileScale = state.preset === "wall" ? 1.3 : state.preset === "earth" ? 2.2 : 3.6;
  const driftStrength = roughness * profileScale;
  const backLipPx = backRimThickness(params);
  const north = new Float32Array(size);
  const south = new Float32Array(size);
  const west = new Float32Array(size);
  const east = new Float32Array(size);

  for (let index = 0; index < size; index += 1) {
    const t = index / size;
    const northNoise = (fbm(t * 2.2 + 1.3, 1.4, 3, variantSeed + 17) - 0.5) * 2;
    const southNoise = (fbm(t * 2.0 + 2.9, 3.1, 3, variantSeed + 23) - 0.5) * 2;
    const westNoise = (fbm(4.2, t * 2.1 + 0.9, 3, variantSeed + 31) - 0.5) * 2;
    const eastNoise = (fbm(6.8, t * 2.3 + 1.7, 3, variantSeed + 43) - 0.5) * 2;

    north[index] = signature.openN ? clamp(backLipPx + northNoise * driftStrength, 0, size * 0.18) : 0;
    south[index] = signature.openS ? clamp(params.heightPx + southNoise * driftStrength * 1.2, 2, size * 0.45) : 0;
    west[index] = signature.openW ? clamp(params.lipPx + westNoise * driftStrength, 0, size * 0.24) : 0;
    east[index] = signature.openE ? clamp(params.lipPx + eastNoise * driftStrength, 0, size * 0.24) : 0;
  }

  for (let pass = 0; pass < 2; pass += 1) {
    smoothArray(north);
    smoothArray(south);
    smoothArray(west);
    smoothArray(east);
  }

  const minSpan = Math.max(8, Math.round(size * 0.22));
  for (let index = 0; index < size; index += 1) {
    if (size - north[index] - south[index] < minSpan) {
      south[index] = Math.max(2, size - north[index] - minSpan);
    }
    if (size - west[index] - east[index] < minSpan) {
      east[index] = Math.max(0, size - west[index] - minSpan);
    }
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

function sampleTexture(texture, x, y, params, offsets) {
  if (!texture) return null;
  const zoom = 100 / params.textureScale;
  const sx = mod(Math.floor(x * zoom + offsets.ox), texture.width);
  const sy = mod(Math.floor(y * zoom + offsets.oy), texture.height);
  const index = (sy * texture.width + sx) * 4;
  return [texture.data[index], texture.data[index + 1], texture.data[index + 2]];
}

function buildMaterialColor(kind, x, y, texture, tint, params, offsets, seedOffset) {
  const tintRgb = hexToRgb(tint);
  const sampled = sampleTexture(texture, x, y, params, offsets);
  const macro = fbm(x * 0.055 + 0.7, y * 0.055 + 1.1, 4, params.seed + seedOffset);
  const ridge = ridgeNoise(x * 0.14 + 2.3, y * 0.14 + 1.7, 3, params.seed + seedOffset + 111);
  const procedural = kind === "face"
    ? 0.55 + macro * 0.22 + ridge * 0.16
    : kind === "base"
      ? 0.74 + macro * 0.21 + ridge * 0.08
      : 0.68 + macro * 0.26 + ridge * 0.12;

  if (!sampled) {
    return multiplyColor(tintRgb, procedural * offsets.brightness);
  }

  return [
    clamp(Math.round(sampled[0] * (tintRgb[0] / 255) * (0.75 + procedural * 0.5) * offsets.brightness), 0, 255),
    clamp(Math.round(sampled[1] * (tintRgb[1] / 255) * (0.75 + procedural * 0.5) * offsets.brightness), 0, 255),
    clamp(Math.round(sampled[2] * (tintRgb[2] / 255) * (0.75 + procedural * 0.5) * offsets.brightness), 0, 255)
  ];
}

function insideCornerBox(x, y, anchorX, anchorY, width, height, corner) {
  if (corner === "NE") {
    return x > anchorX - width && y < anchorY + height;
  }
  if (corner === "SE") {
    return x > anchorX - width && y > anchorY - height;
  }
  if (corner === "SW") {
    return x < anchorX + width && y > anchorY - height;
  }
  return x < anchorX + width && y < anchorY + height;
}

function classifyPixel(signature, profiles, params, x, y) {
  const left = profiles.west[y];
  const right = params.tileSize - 1 - profiles.east[y];
  const top = profiles.north[x];
  const bottom = params.tileSize - 1 - profiles.south[x];

  let onTop = x >= left && x <= right && y >= top && y <= bottom;

  if (onTop) return { zone: "top", left, right, top, bottom };
  if (signature.openN && y < top && x >= left && x <= right) return { zone: "northFace", left, right, top, bottom };
  if (signature.openN && signature.openE && x > right && y < top) return { zone: "northCornerFace", left, right, top, bottom };
  if (signature.openN && signature.openW && x < left && y < top) return { zone: "northCornerFace", left, right, top, bottom };
  if (signature.openS && y > bottom && x >= left && x <= right) return { zone: "southFace", left, right, top, bottom };
  if (signature.openE && x > right && y >= top && y <= bottom) return { zone: "eastFace", left, right, top, bottom };
  if (signature.openW && x < left && y >= top && y <= bottom) return { zone: "westFace", left, right, top, bottom };
  if (signature.openS && signature.openE && x > right && y > bottom) return { zone: "cornerFace", left, right, top, bottom };
  if (signature.openS && signature.openW && x < left && y > bottom) return { zone: "cornerFace", left, right, top, bottom };
  return { zone: "empty", left, right, top, bottom };
}

function jaggedSize(baseSize, axisCoord, crossCoord, params, salt) {
  const rough = params.roughness / 100;
  const amplitude = Math.max(0, Math.round(Math.max(1, baseSize * 0.45) * rough));
  if (!amplitude) return baseSize;
  const n = fbm(axisCoord * 0.21 + salt * 0.07, crossCoord * 0.13 + salt * 0.11, 3, params.seed + salt * 101);
  return clamp(baseSize + Math.round((n - 0.5) * 2 * amplitude), 1, params.tileSize);
}

function classifyNotchOverlay(signature, sample, params, x, y) {
  const rimWidthBase = Math.max(1, Math.min(params.lipPx, params.tileSize));
  const topCapHeightBase = Math.max(1, Math.min(backRimThickness(params), params.tileSize));
  const bottomCapHeightBase = Math.max(1, Math.min(params.heightPx, params.tileSize));

  if (signature.notchNE) {
    const width = jaggedSize(rimWidthBase, y, sample.right, params, 31);
    const height = jaggedSize(topCapHeightBase, x, sample.top, params, 37);
    if (insideCornerBox(x, y, sample.right, sample.top, width, height, "NE")) return { kind: "topCapNE", width, height };
  }
  if (signature.notchNW) {
    const width = jaggedSize(rimWidthBase, y, sample.left, params, 41);
    const height = jaggedSize(topCapHeightBase, x, sample.top, params, 43);
    if (insideCornerBox(x, y, sample.left, sample.top, width, height, "NW")) return { kind: "topCapNW", width, height };
  }
  if (signature.notchSE) {
    const width = jaggedSize(rimWidthBase, y, sample.right, params, 47);
    const height = jaggedSize(bottomCapHeightBase, x, sample.bottom, params, 53);
    if (insideCornerBox(x, y, sample.right, sample.bottom, width, height, "SE")) return { kind: "bottomCapSE", width, height };
  }
  if (signature.notchSW) {
    const width = jaggedSize(rimWidthBase, y, sample.left, params, 59);
    const height = jaggedSize(bottomCapHeightBase, x, sample.bottom, params, 61);
    if (insideCornerBox(x, y, sample.left, sample.bottom, width, height, "SW")) return { kind: "bottomCapSW", width, height };
  }
  return null;
}

function computePixelHeight(sample, notchOverlay, params, x, y) {
  if (sample.zone === "empty") return 0;
  if (sample.zone === "top" && !notchOverlay) return 1;

  if (notchOverlay) {
    const width = Math.max(1, notchOverlay.width);
    const height = Math.max(1, notchOverlay.height);

    if (notchOverlay.kind === "topCapNE") {
      const progressX = clamp((x - (sample.right - width + 1)) / Math.max(1, width - 1), 0, 1);
      const progressY = clamp((y - sample.top) / Math.max(1, height - 1), 0, 1);
      return clamp(Math.max(1 - progressX, progressY), 0, 1);
    }
    if (notchOverlay.kind === "topCapNW") {
      const progressX = clamp((x - sample.left) / Math.max(1, width - 1), 0, 1);
      const progressY = clamp((y - sample.top) / Math.max(1, height - 1), 0, 1);
      return clamp(Math.max(progressX, progressY), 0, 1);
    }
    if (notchOverlay.kind === "bottomCapSE") {
      const progressX = clamp((x - (sample.right - width + 1)) / Math.max(1, width - 1), 0, 1);
      const progressY = clamp((y - (sample.bottom - height + 1)) / Math.max(1, height - 1), 0, 1);
      return clamp(Math.max(1 - progressX, 1 - progressY), 0, 1);
    }
    const progressX = clamp((x - sample.left) / Math.max(1, width - 1), 0, 1);
    const progressY = clamp((y - (sample.bottom - height + 1)) / Math.max(1, height - 1), 0, 1);
    return clamp(Math.max(progressX, 1 - progressY), 0, 1);
  }

  if (sample.zone === "southFace") {
    const progress = clamp((y - sample.bottom) / Math.max(1, params.tileSize - 1 - sample.bottom), 0, 1);
    return 1 - progress;
  }
  if (sample.zone === "northFace") {
    const progress = clamp((sample.top - y) / Math.max(1, sample.top), 0, 1);
    return 1 - progress;
  }
  if (sample.zone === "eastFace") {
    const progress = clamp((x - sample.right) / Math.max(1, params.tileSize - 1 - sample.right), 0, 1);
    return 1 - progress;
  }
  if (sample.zone === "westFace") {
    const progress = clamp((sample.left - x) / Math.max(1, sample.left), 0, 1);
    return 1 - progress;
  }
  if (sample.zone === "northCornerFace") {
    const progressY = clamp((sample.top - y) / Math.max(1, sample.top), 0, 1);
    const progressX = x > sample.right
      ? clamp((x - sample.right) / Math.max(1, params.tileSize - 1 - sample.right), 0, 1)
      : clamp((sample.left - x) / Math.max(1, sample.left), 0, 1);
    return 1 - Math.max(progressX, progressY);
  }
  if (sample.zone === "cornerFace") {
    const progressY = clamp((y - sample.bottom) / Math.max(1, params.tileSize - 1 - sample.bottom), 0, 1);
    const progressX = x > sample.right
      ? clamp((x - sample.right) / Math.max(1, params.tileSize - 1 - sample.right), 0, 1)
      : clamp((sample.left - x) / Math.max(1, sample.left), 0, 1);
    return 1 - Math.max(progressX, progressY);
  }
  return 0;
}

function buildNormalCanvas(heightMap, alphaMap, params) {
  const size = params.tileSize;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(size, size);
  const pixels = image.data;
  const strength = params.normalStrength / 100;

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const index = y * size + x;
      const outIndex = index * 4;
      const alpha = alphaMap[index];
      if (!alpha) {
        pixels[outIndex] = 128;
        pixels[outIndex + 1] = 128;
        pixels[outIndex + 2] = 255;
        pixels[outIndex + 3] = 0;
        continue;
      }

      const left = x > 0 ? heightMap[index - 1] : heightMap[index];
      const right = x < size - 1 ? heightMap[index + 1] : heightMap[index];
      const up = y > 0 ? heightMap[index - size] : heightMap[index];
      const down = y < size - 1 ? heightMap[index + size] : heightMap[index];
      let nx = (left - right) * strength;
      let ny = (up - down) * strength;
      let nz = 1;
      const length = Math.hypot(nx, ny, nz) || 1;
      nx /= length;
      ny /= length;
      nz /= length;

      pixels[outIndex] = clamp(Math.round((nx * 0.5 + 0.5) * 255), 0, 255);
      pixels[outIndex + 1] = clamp(Math.round((ny * 0.5 + 0.5) * 255), 0, 255);
      pixels[outIndex + 2] = clamp(Math.round((nz * 0.5 + 0.5) * 255), 0, 255);
      pixels[outIndex + 3] = alpha;
    }
  }

  ctx.putImageData(image, 0, 0);
  return canvas;
}

function renderTile(signature, variantIndex, params) {
  const tileCanvas = document.createElement("canvas");
  tileCanvas.width = params.tileSize;
  tileCanvas.height = params.tileSize;
  const ctx = tileCanvas.getContext("2d");
  const image = ctx.createImageData(params.tileSize, params.tileSize);
  const pixels = image.data;
  const heightMap = new Float32Array(params.tileSize * params.tileSize);
  const alphaMap = new Uint8Array(params.tileSize * params.tileSize);
  const offsets = variantOffsets(signature, variantIndex, params);
  const profiles = buildProfiles(signature, params.seed + variantIndex * 97 + signature.index * 131, params);

  for (let y = 0; y < params.tileSize; y += 1) {
    for (let x = 0; x < params.tileSize; x += 1) {
      const sample = classifyPixel(signature, profiles, params, x, y);
      const notchOverlay = sample.zone === "empty" ? null : classifyNotchOverlay(signature, sample, params, x, y);
      const index = (y * params.tileSize + x) * 4;
      const pixelIndex = y * params.tileSize + x;

      if (sample.zone === "empty") {
        heightMap[pixelIndex] = 0;
        alphaMap[pixelIndex] = 0;
        pixels[index + 3] = 0;
        continue;
      }

      if (sample.zone === "top") {
        let color;
        if (notchOverlay) {
          color = buildMaterialColor("face", x, y, state.textures.face, params.faceTint, params, offsets, signature.index * 19 + variantIndex * 23);
        } else {
          color = buildMaterialColor("top", x, y, state.textures.top, params.topTint, params, offsets, signature.index * 13 + variantIndex * 17);
        }
        heightMap[pixelIndex] = computePixelHeight(sample, notchOverlay, params, x, y);
        alphaMap[pixelIndex] = 255;
        pixels[index] = color[0];
        pixels[index + 1] = color[1];
        pixels[index + 2] = color[2];
        pixels[index + 3] = 255;
        continue;
      }

      const color = buildMaterialColor("face", x, y, state.textures.face, params.faceTint, params, offsets, signature.index * 19 + variantIndex * 23);
      heightMap[pixelIndex] = computePixelHeight(sample, notchOverlay, params, x, y);
      alphaMap[pixelIndex] = 255;
      pixels[index] = color[0];
      pixels[index + 1] = color[1];
      pixels[index + 2] = color[2];
      pixels[index + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);
  const normalCanvas = buildNormalCanvas(heightMap, alphaMap, params);
  return { canvas: tileCanvas, normalCanvas };
}

function renderBaseVariants(params) {
  const total = Math.max(4, params.variants);
  const variants = [];
  for (let variantIndex = 0; variantIndex < total; variantIndex += 1) {
    const canvas = document.createElement("canvas");
    canvas.width = params.tileSize;
    canvas.height = params.tileSize;
    const ctx = canvas.getContext("2d");
    const image = ctx.createImageData(params.tileSize, params.tileSize);
    const pixels = image.data;
    const offsets = { ox: variantIndex * 117 + params.seed * 3, oy: variantIndex * 173 + params.seed * 5, brightness: 1 + (variantIndex - (total - 1) / 2) * 0.018 };

    for (let y = 0; y < params.tileSize; y += 1) {
      for (let x = 0; x < params.tileSize; x += 1) {
        const color = buildMaterialColor("base", x, y, state.textures.base, params.baseTint, params, offsets, variantIndex * 31 + 7);
        const grit = ridgeNoise(x * 0.21 + variantIndex, y * 0.21 + variantIndex, 2, params.seed + variantIndex * 43);
        const finalColor = multiplyColor(color, 0.94 + grit * 0.16);
        const index = (y * params.tileSize + x) * 4;
        pixels[index] = finalColor[0];
        pixels[index + 1] = finalColor[1];
        pixels[index + 2] = finalColor[2];
        pixels[index + 3] = 255;
      }
    }
    ctx.putImageData(image, 0, 0);
    variants.push(canvas);
  }
  return variants;
}

function buildAtlas(params) {
  const atlas = refs.atlasCanvas;
  const normalAtlas = refs.normalAtlasCanvas;
  const columns = 8;
  const total = state.catalog.length * params.variants;
  const rows = Math.ceil(total / columns);
  atlas.width = columns * params.tileSize;
  atlas.height = rows * params.tileSize;
  normalAtlas.width = atlas.width;
  normalAtlas.height = atlas.height;

  const ctx = atlas.getContext("2d");
  const normalCtx = normalAtlas.getContext("2d");
  ctx.clearRect(0, 0, atlas.width, atlas.height);
  normalCtx.clearRect(0, 0, normalAtlas.width, normalAtlas.height);
  ctx.imageSmoothingEnabled = false;
  normalCtx.imageSmoothingEnabled = false;
  state.generated.atlasManifest = [];
  let atlasIndex = 0;

  for (let variantIndex = 0; variantIndex < params.variants; variantIndex += 1) {
    state.catalog.forEach((signature) => {
      const col = atlasIndex % columns;
      const row = Math.floor(atlasIndex / columns);
      const tileSet = state.generated.tiles[variantIndex].get(signature.key);
      const dx = col * params.tileSize;
      const dy = row * params.tileSize;
      ctx.drawImage(tileSet.canvas, dx, dy);
      normalCtx.drawImage(tileSet.normalCanvas, dx, dy);
      state.generated.atlasManifest.push({ atlasIndex, variant: variantIndex, key: signature.key, label: signature.label, column: col, row });
      atlasIndex += 1;
    });
  }
  state.generated.atlasCanvas = atlas;
  state.generated.normalAtlasCanvas = normalAtlas;
}

function buildGallery() {
  const variantIndex = Number(refs.galleryVariant.value || 0);
  refs.tileGrid.innerHTML = "";
  state.catalog.forEach((signature) => {
    const card = document.createElement("div");
    card.className = "tile-card";
    const canvas = document.createElement("canvas");
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(state.generated.tiles[variantIndex].get(signature.key).canvas, 0, 0, 128, 128);
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

function chooseBaseVariantForCell(x, y) {
  const total = state.generated.baseVariants.length;
  return Math.floor(hash2D(x + 11, y + 17, getParams().seed + 1907) * total) % total;
}

function drawPreview() {
  const params = getParams();
  const canvas = refs.previewCanvas;
  canvas.width = state.map.width * params.tileSize;
  canvas.height = state.map.height * params.tileSize;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingEnabled = false;
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  for (let y = 0; y < state.map.height; y += 1) {
    for (let x = 0; x < state.map.width; x += 1) {
      const baseTile = state.generated.baseVariants[chooseBaseVariantForCell(x, y)];
      ctx.drawImage(baseTile, x * params.tileSize, y * params.tileSize);
    }
  }
  for (let y = 0; y < state.map.height; y += 1) {
    for (let x = 0; x < state.map.width; x += 1) {
      if (!getMapCell(x, y)) continue;
      const signature = signatureAt(x, y);
      const variantIndex = chooseVariantForCell(x, y, params);
      ctx.drawImage(state.generated.tiles[variantIndex].get(signature.key).canvas, x * params.tileSize, y * params.tileSize);
    }
  }
}

function drawTexturePreviewCanvas(canvas, texture, tint, seedOffset) {
  const ctx = canvas.getContext("2d");
  const image = ctx.createImageData(canvas.width, canvas.height);
  const pixels = image.data;
  const offsets = { ox: seedOffset * 97, oy: seedOffset * 151, brightness: 1 };
  const params = getParams();
  for (let y = 0; y < canvas.height; y += 1) {
    for (let x = 0; x < canvas.width; x += 1) {
      const color = buildMaterialColor("base", x, y, texture, tint, params, offsets, seedOffset);
      const index = (y * canvas.width + x) * 4;
      pixels[index] = color[0];
      pixels[index + 1] = color[1];
      pixels[index + 2] = color[2];
      pixels[index + 3] = 255;
    }
  }
  ctx.putImageData(image, 0, 0);
}

function updateStats(params) {
  refs.statCases.textContent = String(state.catalog.length);
  refs.statVariants.textContent = String(params.variants);
  refs.statTotal.textContent = String(state.catalog.length * params.variants);
  refs.catalogInfo.textContent = `${state.catalog.length}/47`;
}

async function readTexture(input, slot) {
  const file = input.files[0];
  if (!file) {
    state.textures[slot] = null;
    updateFileLabel(slot, "procedural");
    scheduleRender();
    return;
  }
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement("canvas");
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(bitmap, 0, 0);
  if (typeof bitmap.close === "function") bitmap.close();
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
  state.textures[slot] = { width: canvas.width, height: canvas.height, data: image.data };
  updateFileLabel(slot, file.name);
  scheduleRender();
}

function updateFileLabel(slot, value) {
  if (slot === "base") refs.baseFileName.textContent = value;
  if (slot === "top") refs.topFileName.textContent = value;
  if (slot === "face") refs.faceFileName.textContent = value;
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

function rebuildAll() {
  const params = getParams();
  state.generated.tiles = [];
  for (let variantIndex = 0; variantIndex < params.variants; variantIndex += 1) {
    const tileMap = new Map();
    state.catalog.forEach((signature) => {
      tileMap.set(signature.key, renderTile(signature, variantIndex, params));
    });
    state.generated.tiles.push(tileMap);
  }
  state.generated.baseVariants = renderBaseVariants(params);
  buildAtlas(params);
  buildGallery();
  drawPreview();
  drawTexturePreviewCanvas(refs.baseTexturePreview, state.textures.base, params.baseTint, 13);
  drawTexturePreviewCanvas(refs.topTexturePreview, state.textures.top, params.topTint, 29);
  drawTexturePreviewCanvas(refs.faceTexturePreview, state.textures.face, params.faceTint, 47);
  updateStats(params);
  refs.status.innerHTML = `<span class="ok">Готово.</span> ${state.catalog.length} сигнатур × ${params.variants} вариантов = ${state.catalog.length * params.variants} тайлов.`;
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

function downloadManifest() {
  const payload = {
    preset: state.preset,
    params: getParams(),
    catalogCount: state.catalog.length,
    atlas: state.generated.atlasManifest
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "rimworld_autotile_manifest.json";
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

  COLOR_IDS.forEach((id) => refs[id].addEventListener("input", scheduleRender));
  refs.seed.addEventListener("change", scheduleRender);
  refs.galleryVariant.addEventListener("change", buildGallery);
  refs.regenerate.addEventListener("click", scheduleRender);

  refs.baseTexture.addEventListener("change", () => readTexture(refs.baseTexture, "base"));
  refs.topTexture.addEventListener("change", () => readTexture(refs.topTexture, "top"));
  refs.faceTexture.addEventListener("change", () => readTexture(refs.faceTexture, "face"));

  refs.randomBlob.addEventListener("click", createBlobMap);
  refs.randomCave.addEventListener("click", createCaveMap);
  refs.roomMap.addEventListener("click", createRoomMap);
  refs.clearMap.addEventListener("click", clearMap);

  refs.downloadAtlas.addEventListener("click", () => downloadCanvas(refs.atlasCanvas, "rimworld_47_atlas.png"));
  refs.downloadNormalAtlas.addEventListener("click", () => downloadCanvas(refs.normalAtlasCanvas, "rimworld_47_normal_atlas.png"));
  refs.downloadPreview.addEventListener("click", () => downloadCanvas(refs.previewCanvas, "rimworld_preview.png"));
  refs.downloadJson.addEventListener("click", downloadManifest);
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
}

boot();
