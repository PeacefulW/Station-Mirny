# Cliff Forge Desktop — ревью под 32px тайлы

Ревью генератора (`tools/rimworld-autotile-lab/desktop_app`) по жалобе:
текстуры мутные при 32px, хочется ощутимых 47 граней, чёрная обводка с
настраиваемой шириной, неровные края у основания, никаких теней
(динамическое освещение) — значит надо проверить нормали.

Файлы, на которые ссылаюсь:
- `core/src/render.rs`
- `core/src/model.rs`
- `core/src/noise.rs`
- `core/src/signature.rs`
- `shell/app.py`

---

## 1. Главное: смысл `texture_scale` инвертирован (это баг) — ADDRESSED in Iteration 1

Status: fixed in `render.rs`; the exported request still uses `texture_scale`,
but UI labels it as texture zoom. Values `> 1.0` now zoom source textures in
via inverse sampling, and the Rust unit test
`texture_scale_above_one_zooms_texture_without_box_blur` covers the contract.

Historical note from the original review:

`render.rs:960-964`:

```rust
let sample = texture.sample_filtered(
    (x as f32 + 0.5) * texture_scale,
    (y as f32 + 0.5) * texture_scale,
    texture_scale,
);
```

Третий аргумент идёт в `sample_filtered` (`render.rs:45-84`). При
`footprint > 1.05` включается box-усреднение 2..8 × 2..8 пикселей.

- `texture_scale = 1.0` — 1:1, билинейка, чётко.
- `texture_scale = 4.0` («по нихачу») — шаг 4 по текстуре + усреднение 4×4
  → жёсткий downsample, та самая мыльная картинка.
- `texture_scale = 0.25` — текстура растягивается, билинейка, тоже не
  чётко, но без усреднения.

Слайдер реально работает наоборот: «выкрутил» = «усреднил». Чтобы
картинка была чёткой при текущей логике, scale должен быть **≤ 1.0**.

**Что сделать (выбрать один путь):**

- **A. Инвертировать семантику** (минимум кода): делить, а не умножать.
  ```rust
  let inv = 1.0 / texture_scale.max(0.001);
  let sample = texture.sample_filtered(
      (x as f32 + 0.5) * inv,
      (y as f32 + 0.5) * inv,
      inv,
  );
  ```
  Тогда «scale = 2.0» = текстура читается в 2× деталях (один её пиксель
  растянут на 2 пикселя тайла) — интуитивный «зум». На 32px тайле
  наконец появятся читаемые элементы. Имя слайдера в `app.py:609`
  переименовать в «Зум текстуры» / «Размер пикселя текстуры».
- **B. Развести два параметра**: `texture_zoom` (растяжение в map-space)
  + `texture_detail_blur` (явный footprint).

This is no longer an open blocker.

---

## 2. 32px физически малы для 47 граней — поднять `min_tile_size` до 48

`AppRequest::sanitized` (`model.rs:145-148`) разрешает `tile_size = 32..128`,
но всё, что зависит от высот, упирается в `tile_size / 2`. На 32px:

- `south_height ≤ 16`, `north_height ≤ 16`, `side_height ≤ 16`.
- `notch_side / notch_north = .max(2.0)` (`render.rs:736-737`) — врез
  шириной всего 2px. У RimWorld notch занимает ~1/4 тайла (на 64 = 16px).
  На 32px нужен notch ≥ 8px, чтобы он *читался*.
- На крыше после bevel остаётся 5-7 пикселей ширины — текстура брика
  8×16 туда не помещается.

Практический порог: **48..64 px**. Если оставаться на 32 — нужен
пиксель-арт пайплайн, а не FBM/voronoi (эти процедурные слои визуально
работают начиная с ~48 px).

- В `sanitized` поставить `clamp(48, 128)`.
- В `app.py:606` слайдер сейчас `32..96` — расширить до `48..128`.
- В UI показывать предупреждение, если пользователь форсит 32.

---

## 3. Нормали слабые/резкие (под динамическое освещение это критично) — ADDRESSED in Iteration 1

Status: fixed in `render.rs`, `model.rs`, and `shell/app.py`.

- `AppRequest.normal_strength` is now exported from the UI and defaults to
  `tile_size / 32.0`.
- `AppRequest.bake_height_shading` defaults to `false`; albedo stays flat for
  dynamic lighting unless the author opts into baked shading.
- Shape normals use a one-pass 3x3 height blur followed by Sobel gradients.
- `encode_normal` and `build_wrapped_normal_image` share the same gradient
  sign convention and strength helper.
- Rust unit tests cover the diagonal Sobel signal, disabled height shading, and
  matching wrapped/tile normal formula.

Historical note from the original review:

`encode_normal` в `render.rs:1590-1607`:

```rust
let dx = right - left;     // 1-пикс. центральная разность
let dy = bottom - top;
let nx = -dx * 2.4;        // фиксированный strength
let ny = -dy * 2.4;
let nz = 1.0;
```

Проблемы:

- `face_power.powf` (`render.rs:822`) делает зону face крутой: высота у
  нижней грани падает с 1.0 до 0 на ~`south_height` пикселей нелинейно.
  На 32px это 6-10 пикселей. Центральная разность даёт **огромный
  градиент в 2-3 пикселях у самого края** и почти `nz≈1.0` (плоско) во
  всём остальном. На свету видна тонкая «фаска» и плоская стена. Это и
  есть «нет объёма».
- Множитель `2.4` захардкожен и не зависит ни от `tile_size`, ни от
  `face_power`. На 32px он слишком резкий, на 128 — слишком мягкий.
- На границе `Top↔Face` тоже центральная разность 1px — нормаль смотрит
  ровно по нормали к локальному скату. Никакого smoothing нет.

**Что делать (от дешёвого к лучшему):**

1. **Sobel 3×3** вместо центральных разностей:
   ```
   Gx = (h[+1,-1] + 2h[+1,0] + h[+1,+1]) - (h[-1,-1] + 2h[-1,0] + h[-1,+1])
   Gy = (h[-1,+1] + 2h[0,+1] + h[+1,+1]) - (h[-1,-1] + 2h[0,-1] + h[+1,-1])
   ```
2. Перед нормалью — лёгкий box-blur 3×3 (вес ~0.5) по `heights` в
   отдельный буфер, чтобы убрать ступеньки от `apply_crown_bevel` и
   `edge_jitter`. Один проход хватит.
3. Сделать `normal_strength` параметром в `AppRequest` (default
   `tile_size / 32.0`: на 32 — 1.0, на 64 — 2.0, на 128 — 4.0). Текущее
   2.4 как раз попадает в 64-96 диапазон.
4. **Рассинхрон знаков** между tile-нормалями и material-нормалями:
   - `encode_normal:1598` → `nx = -(right-left)`, `ny = -(bottom-top)`
   - `build_wrapped_normal_image:427` → `nx = (left-right)`, `ny = (up-down)`

   Алгебраически одинаково по знаку, но `strength` разный
   (`2.4` vs `0.95/0.9`) — в шейдере объёмы не стыкуются, если их
   совмещать. Унифицировать формулу.

`apply_height_shading` no longer affects albedo when
`bake_height_shading = false`.

---

## 4. Чёрная обводка — правильное решение под динамику

Reference (Img2/Img3) — это _diegetic outline_ (как в RimWorld и Don't
Starve). При динамическом свете контур остаётся, потому что его
генерирует не свет, а художник.

**Куда вставить:** в `render_tile` после `apply_crown_bevel`, перед
сэмплингом цветов — отдельный массив `outline_distance: Vec<f32>`.

**Расчёт расстояния** (наследует существующий jitter, поэтому контур
автоматически неровный):

```rust
fn outline_distance_at(
    request: &AppRequest, signature: &Signature, seed: u32,
    world_x: f32, world_y: f32, x: f32, y: f32,
    edge_period: f32, rough_px: f32,
) -> f32 {
    let mut nearest = f32::MAX;
    if signature.open_n {
        let b = north_boundary(request, rough_px, edge_period, seed.wrapping_add(11), world_x);
        nearest = nearest.min((y - b).abs());
    }
    // analogous for open_s/e/w + notch_* using границы из render.rs
    nearest
}
```

`north_boundary/south_boundary/east_boundary/west_boundary` уже
используются в `apply_crown_bevel:891-906` — переиспользовать. Notches
учитывать через минимальное расстояние до прямоугольника врезки.

**Композитинг (albedo-only):**

```rust
if outline_enable {
    let d = outline_distance_at(...);
    if d < outline_width as f32 {
        let t = (d / outline_width as f32).clamp(0.0, 1.0);
        let alpha = 1.0 - smoothstep(t);
        shaded = mix_color(shaded, outline_color_rgb, alpha);
    }
}
```

**Параметры в `AppRequest` (`model.rs`):**

```rust
#[serde(default = "default_outline_enable")] pub outline_enable: bool,
#[serde(default = "default_outline_width")]  pub outline_width: u32,   // 0..6
#[serde(default = "default_outline_color")]  pub outline_color: String,
```

**Толщина:** для 32 — `outline_width = 1`, для 64 — `1..2`, для 128 —
`2..3`. Слайдер 0..6 + подсказка «1px на 32-tile».

**Важно:** обводку вести по `heights`, **не записывать её в
height/normal** — это чисто albedo, иначе свет «осветит» её как
геометрию.

---

## 5. Неровный нижний край (skirt / plinth у основания)

Img3 — у каменной стены тёмная нижняя полоса с рваным контуром. Сейчас
этого нет: `south_boundary` даёт неровную верхнюю кромку лицевой зоны
(хорошо), а нижняя строка face упирается в ровный край тайла без
отделки.

**Реализация:**

- Завести `SurfaceZone::Plinth`.
- Для каждого пикселя зоны `Face`, у которого
  `y >= south_boundary + plinth_lift` — пометить как `Plinth`.
- `plinth_lift = edge_jitter(world_x, ..., plinth_roughness, edge_period)`
  — **отдельный** jitter с большей амплитудой и меньшим периодом → даст
  рваный край.
- Сэмплировать материал face, но `scale_color(..., 0.7)` (или своим
  `plinth_color`).

**Параметры:** `plinth_height: u32 (0..8)`, `plinth_roughness: f32 (0..100)`,
`plinth_color: String`. На 32-tile `plinth_height = 2..3`.

Совместно с outline: outline = жёсткий 1px чёрный, plinth = мягкая
тёмная «юбка» 2..4px над ним. Оба слоя rimworld-style без теней.

---

## 6. Меньшие, но полезные

- `material_slot` (`render.rs:915-940`): зона `Back` принудительно
  использует `face_material/face_texture` с `back_color` тинтом
  (`render.rs:605-616`). Настройка верхняя/лицевая/основа в UI не
  управляет текстурой задней грани. Завести отдельный материал для
  `back` (или явно задокументировать, что back = дарк-вариант face).
- `EDGE_NOISE_PERIOD_TILES = 8.0` — после 8 тайлов край повторяется. На
  больших картах будет видимый паттерн. Сделать параметр.
- В `model.rs:147` `north_height` clamps к `tile_size/2`, но
  `notch_north = north_depth.max(2.0)` (`render.rs:737`) на 32px ≈ 1/16
  тайла → 47 сигнатур не различимы. Сделать `notch_*` пропорциональным
  `tile_size/4..tile_size/3`, не фиксированным `north_height`.
- `apply_crown_bevel` сглаживает `0.86..1.0` (height), но
  `apply_height_shading` для Top даёт factor только `0.96..1.04` → bevel
  на 32px почти не виден. Если `bake_height_shading` включён — поднять
  для Top диапазон до `0.85..1.05`.

---

## Порядок действий

1. Поправить `texture_scale` (инвертировать или развести с `footprint`) — done.
2. Чёрная обводка через дистанцию до boundaries (контентный эффект сразу).
3. Plinth у основания (отдельная зона с большим roughness).
4. Sobel 3×3 + лёгкий blur для нормалей, `normal_strength` параметром,
   `bake_height_shading` опциональным флагом — done.
5. Поднять `min tile_size` до 48 в `sanitized` и UI, добавить в README
   дисклеймер про 32px.
