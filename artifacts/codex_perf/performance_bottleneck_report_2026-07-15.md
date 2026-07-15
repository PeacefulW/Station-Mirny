# Station Peaceful — performance bottleneck report (2026-07-15)

Status: living evidence report. Update this file after every verified runtime
change; do not treat an intended optimization as resolved without a measured
acceptance run.

## Runtime evidence set

- Eight manual `F2` captures from `14:00:53` through `14:02:53`.
- Runtime: Godot 4.7 editor/debug build, D3D12 Forward+,
  NVIDIA GTX 1060 6 GB, 60 Hz, VSync enabled, `Engine.max_fps = 0`.
  The saved PNGs are 1792×1008; environment metadata reports a
  1842×1008 window. Absolute FPS is therefore diagnostic evidence for this
  build and machine, not a shipping baseline.
- The two-sample `20260715_140256_169` session was produced by a headless smoke
  test, not gameplay. It was excluded and removed.
- No valid moving-player `F4` trace exists yet. Manual captures prove steady
  render and reveal problems, but not the exact source of isolated hitches.

## Controlled result at zoom 0.2

The first five captures use the same player position, zero velocity, zoom and
81-chunk visible target. They are a quasi-controlled series: while the
presentation queue drains, content is added to the scene, but in-game time and
lighting also advance from 23:00 to 09:00.

| Metric | First capture | Fifth capture | Delta |
|---|---:|---:|---:|
| Frame monitor | 25.097 ms | 32.358 ms | +28.9% |
| Draw calls | 3,778 | 4,816 | +27.5% |
| Render objects | 12,951 | 16,036 | +23.8% |
| Render primitives | 271,246 | 336,312 | +24.0% |
| Dispatcher | 2.569 ms | 2.438 ms | -5.1% |
| Streaming job | 2.393 ms | 2.178 ms | -9.0% |
| Object upload queue | 82 | 52 | -30 |
| Chunks waiting for reveal | 50 | 21 | -29 |

Frame time versus draw calls has `r = 0.992` in this five-sample series
(`r = 0.986` versus render objects). The measured streaming CPU cost falls
while the frame gets slower, so packet generation/streaming compute does not
explain this regression; neither measured dispatcher, frame setup nor physics
does. Render submission, driver/GPU work or frame pacing is the leading
hypothesis; the correlation alone is not a causal GPU breakdown, and the old
captures' zero viewport CPU/GPU fields cannot split those causes.
The fifth sample is still incomplete (`visibility_wait = 21`, object queue
`= 52`), so it must not be described as a fully loaded steady state.

The object queue drains by only `30 / 52.411 s = 0.572 chunks/s`, approximately
`1.75 s/chunk`. At that rate an 82-chunk cold queue needs about 143 seconds.
Directly visible waits drain `29 / 52.411 s = 0.553 reveals/s`, or about
`1.81 s/reveal`; from the first capture the remaining 50 visible holes imply
roughly another 90 seconds.

## Movement and screen-coverage evidence

- Between captures five and six the player moves 1,375 world units in 7.626 s.
  `visibility_wait` grows from 21 to 28, the object queue remains at 52 and
  prestage moves only 51 to 50 even though all `121/121` CPU results are ready.
  Main-thread presentation therefore fails to keep up with this walking run;
  generation/worker compute is not waiting on work.
- At zoom 0.4 only six chunks wait for reveal, but the PNG shows those six as a
  large central rectangle around the player. The scheduler already gives
  visible class-0 chunks distance-squared priority and allows a nearer class-0
  request to preempt the focus; the hole therefore points back to the slow
  atomic transaction itself, not a reversed/far-first priority queue.
- After the later displacement, capture eight again has `121/121` ready,
  requested/inflight both zero, yet `visibility_wait = 47` and the object queue
  is 74. This independently reproduces the presentation bottleneck.
- Measured streaming rises from about 2.18–2.39 ms in the stationary series to
  3.122 ms while moving and 4.182 ms after the larger displacement. It is not a
  proven hitch yet, but is already a material share of a 16.67 ms frame and
  must be profiled separately at vehicle speed.

## Bottleneck register

| ID | Finding and evidence | User impact | State / action |
|---|---|---|---|
| P-01 | Publish readiness previously called forensic mountain debug state and repeatedly scanned large halo/mask buffers (measured up to 10.7 ms). | Finalizing an otherwise ready chunk could hitch. | Resolved in `03232ff`: hot readiness is cached O(1); forensic snapshots remain explicit diagnostics only. |
| P-02 | Grass packed-buffer compute previously ran synchronously from the main-frame path despite the worker contract. | Chunk arrival charged generation work to gameplay. | Resolved in `03232ff`: native worker compute/result drain, bounded main-thread RenderingServer apply. |
| P-03 | Terrain/grass/publish work previously shared coarse phases and repeated cold work after zoom round trips. | Long initial appearance and unnecessary repeat uploads. | Partially resolved in `03232ff`: dedicated grass lane, packet/grass warm caches and hot ChunkView reuse. Revalidate zoom round trips after P-05/P-06. |
| P-04 | Object presentation CPU construction needed native packed results and bounded apply instead of node-per-object work. | Asset-rich chunks did not scale. | Implemented in `85c81db`; captures show every requested CPU result ready (`121/121` at zoom 0.2, `81/81` at zoom 0.4) with zero inflight work. Main-thread presentation remains P-05. |
| P-05 | Cold object-packet materialization serialized the focused atomic reveal. Captures show a mean 0.178 ms inside a 0.75 ms lane while reveal drains at only 0.553/s; zoom-0.4 central holes remain despite the existing class-0 + distance² priority. | Player catches hidden chunks even on foot; transport would be worse. | Implemented in the current worktree: tree/living/spiky/rock expose allocation-only reservation and phase hints. The first family allocation yields; later same-family allocations use monotonic measured high-water +25%+25 us inside a 0.65 ms sub-budget, at most two/frame. Allocation→upload, heterogeneous phase changes, COMPLETE and FINALIZE remain separate process-frame boundaries. Contracts/stress pass; runtime drain rate remains to be measured. |
| P-06 | Grass presentation used up to 64 exact albedo depth stripes plus 64 fixed-z directional-shadow CanvasItems per dense chunk. `36 × 128 = 4,608` is an architectural estimate, not a measured per-pass breakdown, but it is the right order of magnitude beside the observed 4,816 total calls. | The partially revealed zoom-0.2 state already reaches 30–33 ms; faster reveal alone would expose more render load sooner. | Iteration A implemented in the current worktree: native workers flatten finalized tuft transforms and full-LOD chunks upload one fixed-z directional-shadow MultiMesh, reducing the synthetic dense contract from `128` to `65` layers while preserving all 64 albedo stripes. Fractional-LOD profiles keep the exact legacy path. Runtime draw-call/FPS acceptance remains required; horizontal global-stripe pages remain the larger future step. |
| P-07 | Grass preset has `lod_min_fraction = 1.0`; far zoom does not reduce instances. Existing instance LOD would not remove empty/non-empty stripe draw surfaces anyway. | Far-world view renders close-detail density and cost. | Open after structural batching. Any far-field representation needs visual A/B approval; do not hide missing content or trigger rebuilds on every zoom. |
| P-08 | `Performance.TIME_PROCESS` was labelled as pure CPU and steady >22 ms was labelled as a freeze. | HUD diagnosis blamed the wrong subsystem and produced false alarms. | Resolved by performance HUD: whole-frame wording and 50 ms isolated-hitch threshold; 16.67–50 ms is sustained pressure. |
| P-09 | Standalone F2 enabled viewport timing for only one frame, producing CPU/GPU = 0, and its viewport readback polluted subsequent HUD peaks (55–75 ms). | Diagnostic action looked like a gameplay freeze and could not separate CPU submission from GPU time. | Fixed in current worktree: render timing warm-up, capture-taint exclusion in trace and HUD, plus manual-event confirmation. Requires one windowed acceptance capture. |
| P-10 | Recorder smoke tests wrote into player `performance_captures`; retention sorted F2/F4 prefixes incorrectly and could keep nine folders or evict a newer F4 session. F2 and F4 state could overlap. | Evidence could be lost or counters/measurement state mixed. | Fixed in current worktree: injected isolated test root, chronological normalized retention, current-session protection, and F2/F4 transaction guard. |
| P-11 | Full-screen postprocess is enabled in every capture. No controlled F12 on/off sample exists. | Possible extra GPU bandwidth/mipmap cost remains unquantified. | Unconfirmed. Measure in a valid F4 A/B before changing visuals. |
| P-12 | Mountain digging, camera zoom transitions and vehicle-speed traversal are absent from the valid trace set. | Episodic mountain/mining/fast-travel hitch sources remain unknown. | Unconfirmed. Record separate route phases after recorder P-09 is verified. |

## Important interpretation

P-05 and P-06 must be solved together. Faster object reveal removes the black
holes, but it also reaches an even denser state than the already expensive
partially revealed 4,816-draw sample much sooner. Queue throttling must never be
used as a render optimization: the player must receive complete nearby chunks
promptly, while render topology is reduced independently.

The captured 55–75 ms HUD peaks are not accepted as gameplay evidence. Every
capture whose 300-frame HUD window still contained the previous F2 readback
(`188`, `196`, `245`, `298` frames) shows a >50 ms peak; captures taken `770`,
`636` or `2,003` frames later do not. This is a strong attribution inference
from the old recorder, not a historical taint tag. Current/steady frame values,
draw counters and queue state remain valid. Tables use JSON as the canonical
sample because the on-screen HUD refreshes at a different cadence.

## Required acceptance run after P-05/P-09

1. Start `F4` before moving; let the world finish its initial reveal.
2. Move continuously for at least two minutes, including zoom 1.0 → 0.4 → 0.2
   → 1.0 → 0.2 and one F12 postprocess A/B interval.
3. Press `F2` only to bookmark a visible anomaly; F4 already records every
   frame.
4. Stop with `F4` and compare: reveal drain rate, maximum `visibility_wait`,
   p95/p99 frame time, viewport CPU/GPU, draw calls and repeat-zoom queues.
5. Run dedicated mountain-dig and future vehicle-speed traces separately so
   their causes are not mixed with cold-start publication.

## Current worktree verification

- Debug and release GDExtension builds are up to date.
- Recorder/HUD smoke, object queue/cache, flora, dense object stress, object
  packet/backend, native grass flattening, hot ChunkView cache, depth-ladder and
  zoom round-trip contracts pass.
- Synthetic dense grass retains 64 exact albedo ladder stripes while reducing
  grass + directional-shadow layers from 128 to 65.
- Zoom round-trip preserves 56/56 outer-ring grass and terrain views with zero
  second-pass grass upload queue.
- These contracts prove scheduling, cache, packet and ordering invariants. They
  do not replace the required windowed runtime comparison for FPS, visual
  identity and real reveal throughput.
