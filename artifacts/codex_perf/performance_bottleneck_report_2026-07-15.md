# Station Peaceful — performance bottleneck report (2026-07-15)

Status: living evidence report. Update this file after every verified runtime
change. Structural contracts may verify that an implementation landed, but no
FPS, frame-time, reveal-throughput, or visual-quality outcome is resolved
without a measured windowed acceptance run.

## Runtime evidence set

- Eight manual `F2` captures from `14:00:53` through `14:02:53`.
- Runtime: Godot 4.7 editor/debug build, D3D12 Forward+,
  NVIDIA GTX 1060 6 GB, 60 Hz, VSync enabled, `Engine.max_fps = 0`.
  The saved PNGs are 1792×1008; environment metadata reports a
  1842×1008 window. Absolute FPS is therefore diagnostic evidence for this
  build and machine, not a shipping baseline.
- The two-sample `20260715_140256_169` session was produced by a headless smoke
  test, not gameplay. It was excluded and removed.
- Valid pre-Iteration-7 render-page baseline `F4` session
  `20260715_152917_487`: 5,084 samples over
  exactly 120 s, including repeated zoom changes and 63.9 s of continuous
  zoom-0.2 movement at 320 px/s. Four automatic PNG/JSON events were saved.
- The recorder correctly marks the three samples following every PNG as
  capture-tainted: 5,072 clean + 12 tainted samples. PNG readback reached
  68.074 ms, but no clean frame reached 50 ms, so capture overhead is no
  longer being reported as a gameplay hitch.
- Post-Iteration-7 `F4` session `20260715_214016_869`: 5,016 samples over
  120 s and 10,190 px of travel. Manual settled bookmarks
  `manual_20260715_214218_705`, `manual_20260715_214224_610`, and
  `manual_20260715_214227_343` share one stationary position at zoom `0.2`.
  They are the evidence for the permanent reveal-tail defect below.

## Pre-Iteration-7 F4 baseline (`20260715_152917_487`)

This is the first valid per-frame runtime acceptance trace for the object-upload
and chunk-owned shadow work that preceded the world-owned grass page renderer.
It is the comparison baseline, not evidence for the current Iteration 7
worktree. Its 57-column CSV predates the seven appended `grass_page_*` fields,
so it cannot measure page merge, page upload, or page residency behaviour.

| Clean metric | Result |
|---|---:|
| Average frame / FPS | 23.585 ms / 42.40 FPS |
| p95 / p99 | 35.415 / 37.701 ms |
| 1% low | 26.52 FPS |
| Maximum clean frame | 42.503 ms |
| Viewport GPU average / maximum | 23.003 / 39.655 ms |
| Viewport render CPU average / maximum | 3.002 / 8.403 ms |
| Dispatcher average / p95 / maximum | 3.474 / 6.076 / 11.646 ms |
| Object upload lane average / p95 / maximum | 0.321 / 0.651 / 3.516 ms |
| Draw calls average / maximum | 1,623 / 3,037 |
| Render objects average / maximum | 7,718 / 14,030 |
| Object upload queue maximum | 105 chunks |
| Visibility wait maximum | 53 chunks |

Whole-frame time follows measured viewport GPU time with `r = 0.968` at zero
lag. CPU render submission is much lower, and streaming/object lane time is
not positively correlated with the slowest sustained render periods. This run
is therefore render/GPU-bound overall, not packet-worker or main-thread upload
bound. It shows sustained 26–40 FPS pressure rather than isolated clean-frame
freezes.

The object worker is not the missing-chunk cause: `object_ready_cpu ==
packet_count` in 97.48% of all samples; during radius-4 movement the figure is
96.14% and the largest deficit is two results. Requested packets, object
inflight work and mask retry/upload queues are normally zero. Complete native
data is waiting for main-thread presentation.

Cold stationary zoom 0.2 from 20.718 to 32.351 s improved the estimated visible
reveal rate to 1.719 chunks/s and object-queue drain to 1.461 chunks/s. This is
directionally about 3.1× / 2.6× faster than the old manual-capture series, but
still requires tens of seconds: at 26 s all 81 views are resident while 39 are
still held invisible by the blocking-object reveal gate.

During continuous zoom-0.2 movement from 41.44 to 105.31 s the result is not
acceptable:

- `visibility_wait` grows from 13 to 37 and peaks at 53; its average from 45
  through 105 s is 42.8 hidden chunks;
- object upload remains between 57 and 82 queued chunks despite native results
  being ready;
- 25 chunk-boundary transitions occur from 45 through 105 s; the observed
  object queue processes roughly 2.58 removals/s while new/stale frontier
  churn is roughly 2.46 additions/s, maintaining a large permanent backlog;
- the automatic PNGs visibly contain rectangular missing-world areas. At the
  second and third events only 32/81 and 30/81 views are resident, with 49 and
  51 still in publish; the fourth event has 32/49 resident, 17 in publish and
  nine already-published chunks still hidden by the blocking-object gate.

The hot view cache accelerates terrain publication on a zoom round trip
(approximately 9.3 newly ready views/s over the measured 2.04 s interval), but
does not remove the object backlog: the object queue remains 74–75. Cache reuse
therefore helps, but cannot substitute for higher presentation throughput.

At zoom 0.2 the worst settled stationary interval averages 35.347 ms with
34.953 ms viewport GPU time. During long zoom-0.2 movement GPU time correlates
with draw calls at `r = 0.881`; this confirms the remaining draw topology as a
separate bottleneck. The new trace peaks at 3,037 calls versus 4,816 in the old
manual series, which is directionally consistent with consolidated grass
shadows, but positions, lighting, visible content and reveal completeness are
not controlled, so this is not a valid before/after percentage.

F12 was off only from 51.439 through 55.006 s while the player and scene were
still changing. Off averages 22.886 ms frame / 22.374 ms GPU, but the adjacent
enabled windows change from 26.383 / 25.803 before to 21.853 / 21.413 after as
draw calls and render objects fall. This A/B is confounded and does not prove a
postprocess cost; no visual setting should be changed from it.

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

## Post-Iteration-7 F4 and permanent reveal tail

The page-enabled `20260715_214016_869` run is a valid current-worktree trace,
but not a controlled renderer A/B: the route, visible completion and scene
population differ from the pre-page baseline. Across the whole session it
records `23.930 ms` average frame time (`41.79 FPS`), `37.328 ms` p95,
`40.309 ms` p99 and a `24.81 FPS` 1% low. Excluding the first five seconds and
capture-tainted samples gives `24.193 ms` average frame / `23.372 ms` viewport
GPU and `37.358 / 36.792 ms` frame/GPU p95. Viewport render CPU remains much
lower at `3.215 ms` average (`4.526 ms` p95), so the run remains GPU/render
bound overall.

The stationary F2 bookmarks isolate a separate correctness failure:

- all desired views and source packets exist (`81/81` resident views,
  `121/121` packets, zero requested packets);
- publish, object upload/prestage/worker, grass upload/worker/page upload,
  mask upload/worker/retry and inflight queues all reach zero;
- `visibility_wait` stays exactly `14` across nine seconds and grass page
  active slots stay `67`, exactly `81 - 14`;
- the PNGs retain the same black rectangular chunks after the player stops.

This is not a slow remaining queue. The reveal latch lost its continuation:
the old compact HUD hid it by omitting `visibility_wait` from `QUEUES`, the
one-frame reveal guard had no autonomous expiry check, and the completed hot
object promotion path unconditionally discarded its upload token when
`ChunkView` adoption returned false. Iteration A now keeps the event callbacks
as the fast path, adds one O(1)-deduplicated dense retry ring (maximum four
explicit wait checks per streaming tick), rejects reveal outside current target
demand, and direct-stages the retained worker result into an already-owned local
view envelope after `adopt=false`. Reveal,
eviction and reset remove the token in O(1); the retry path never scans all
pending or loaded chunks. Headless regression proves mountain/object/frame
blockers, lost wakeup, dedupe/bounds, the real `adopt=false` transfer, atomic
collision enable and exactly-once `chunk_loaded`. A new windowed run is still
required to prove that the real `14`-chunk tail reaches zero visually.

The fully settled tail before this fix averages about `20.922 ms` frame and
`20.504 ms` viewport GPU at roughly `2,021` draw calls, `11,444` render objects
and `619,165` primitives. Therefore removing the black holes is not expected to
produce 60 FPS by itself; revealing the missing 14 chunks may increase rendered
load. The pre-page movement sample had about `2,281` draw calls versus `1,812`
in the new movement sample, directionally consistent with page topology, but
different content/visibility and primitive counts make this an observation,
not a valid percentage improvement.

## Iteration 7 structural result and measured follow-up

The checked-in full-LOD profile now uses world-owned fixed `4 x 1` grass render
pages. Native workers merge at most four immutable chunk contributors, changing
only transform X by the contributor slot. Main-thread page publication stages
at most one allocation or one packed upload phase per callback and keeps the old
front visible until one atomic commit. A cold page shell owns exactly five
CanvasItems; front/back reuse bounds each stripe to two `MultiMesh` resources.

This removes the repeated horizontal depth-stripe ownership structurally:

- four dense chunk-owned graphs after directional-shadow consolidation are
  `4 * 65 = 260` albedo-plus-shadow owners; one dense page owns `65`;
- a radius-four 81-chunk visible ring occupies at most 27 aligned pages, changing
  the theoretical albedo-plus-directional-shadow graph from `5,265` owners
  (`5,184` albedo + `81` directional shadows) to `1,755` (`1,728 + 27`), a
  `66.7%` reduction;
- those are topology bounds, not measured Godot draw-call or FPS deltas. Empty
  stripes, other world layers, driver behaviour, overdraw and partial reveal all
  prevent converting the ratio into a runtime claim.

Page demand is three-tier: revealed `active`, hidden visible-ring `prestage`, and
outer warm `source`. Testing exposed and fixed two edge defects. First, a
prestage edge page could wait forever for optional source-only slots; reveal
demand now requires only active/prestage revisions, while a pure-source page
remains all-or-nothing. Second, exact committed front residency was conflated
with the active shader mask; readiness now reports the exact front independently
from visibility. The bounded hot round-trip contract restores all returned outer
slots without grass recompute, page merge, or raw page upload.

The page coordinator is now bounded independently from traversal distance:

- zero-demand entries without resident payload are pruned after their
  request/ready/retry/eviction bookkeeping is retired; absent-page invalidation
  and inactive updates do not create tombstones;
- zero demand cancels an unstarted ready result or an in-progress unpublished
  back-buffer transaction. The committed front remains byte-for-byte intact
  when it still contains an exact reusable slot; otherwise the page payload is
  released and pruned instead of consuming the visual upload lane;
- eviction records carry an exact per-entry ticket and are consumed through a
  monotonic cursor rather than `Array.pop_front()`. A callback scans at most
  eight physical records, and physical capacity is
  `clamp(max_resident_pages + 16, 16, 256)`;
- an evicted page is cleared of GPU payload, detached, and admitted to a pool of
  at most four reusable shells. Clear/reconfigure/world-epoch reset frees that
  pool as well as resident pages.

These changes remove an accumulating CPU/memory hazard for long travel and
bound retirement work per callback. The post-change trace above measures the
combined current worktree, not an isolated page delta, and does not establish a
stable 60 FPS result.

Grass mountain-halo construction also moved off the main-frame request path.
When no current explicit halo is reusable, the main thread passes nine shallow
packet envelopes and the same worker derives `remaining_halo` immediately before
scatter packing. No packed terrain/mountain channel is scanned or copied on the
main thread. This is structurally verified but has no isolated before/after
runtime timing.

The post-Iteration-7 trace exists, but is not a controlled A/B and still misses
the 16.67 ms GPU target. It cannot yet prove how much pages changed GPU time or
whether first-time page staging will keep up after the permanent reveal tail is
removed.

## Bottleneck register

| ID | Finding and evidence | User impact | State / action |
|---|---|---|---|
| P-01 | Publish readiness previously called forensic mountain debug state and repeatedly scanned large halo/mask buffers (measured up to 10.7 ms). | Finalizing an otherwise ready chunk could hitch. | Resolved in `03232ff`: hot readiness is cached O(1); forensic snapshots remain explicit diagnostics only. |
| P-02 | Grass packed-buffer compute previously ran synchronously from the main-frame path despite the worker contract; a cache miss could also construct the cross-chunk mountain halo while scheduling from the main thread. | Chunk arrival charged generation/derived-field work to gameplay. | **Resolved structurally.** Scatter packing and optional fixed-3x3 `remaining_halo` derivation now execute on the same worker-local `WorldCore`. The main thread copies only nine shallow envelope shells, never packed channels, then performs bounded page apply. No isolated runtime delta is claimed. |
| P-03 | Terrain/grass/publish work previously shared coarse phases and repeated cold work after zoom round trips. Iteration 7 testing additionally found that a visible prestage page could wait for optional source slots and that committed readiness incorrectly included shader-active state. | Long initial appearance, idle edge pages, and unnecessary repeat uploads. | **Hot round trip resolved structurally; cold presentation remains open.** Dedicated lanes/caches plus three-tier page demand restore the complete bounded outer ring with zero scatter recompute, page request/merge, or raw upload. Reveal pages no longer wait on optional source slots, and exact front residency is independent from shader visibility. Revalidate cold latency and real traversal in the post-Iteration-7 F4 run. |
| P-04 | Object presentation CPU construction needed native packed results and bounded apply instead of node-per-object work. | Asset-rich chunks did not scale. | Implemented in `85c81db`; captures show every requested CPU result ready (`121/121` at zoom 0.2, `81/81` at zoom 0.4) with zero inflight work. Main-thread presentation remains P-05. |
| P-05 | Cold object-packet materialization serializes the focused atomic reveal. The baseline F4 improves stationary reveal to an estimated 1.719/s, but at 320 px/s `visibility_wait` averages 42.8, peaks at 53 and produces visible rectangular holes while native object results are already ready. | Player catches hidden chunks even on foot; transport would be worse. | **Throughput remains open; permanent-stall subcase moved to P-14.** Allocation-only phases/high-water budgeting pass contracts, but the process-frame-per-transition transaction still needs a measured frontier-rate improvement. Do not decouple terrain from genuinely blocking objects/colliders merely to hide holes. Revalidate continuous walking after P-14, then specify bounded multi-transaction throughput for vehicle speed. |
| P-06 | The pre-page F4 is GPU-bound (`frame↔GPU r=0.968`; zoom-0.2 movement `GPU↔draw r=0.881`) and reaches 3,037 calls / 39.655 ms GPU. Even after per-chunk directional-shadow consolidation, every horizontal chunk repeated the same 64 exact albedo stripe owners. | Fully revealing chunks expose more render load; the baseline far view sustains 26–40 FPS. | **Iteration 7 implemented; isolated effect still unproven.** Fixed `4 x 1` pages reduce four dense post-shadow graphs from `260` to `65` owners. The post-page run is still GPU-bound (`23.372 ms` clean average GPU; settled tail `20.504 ms`) and differs in visibility/content, so its lower directional draw counts are not a controlled FPS delta. P-14 must be visually closed before a fully revealed renderer A/B. |
| P-07 | Grass preset has `lod_min_fraction = 1.0`; far zoom does not reduce instances. Structural page batching removes repeated owners but not vertex/pixel work or overdraw inside retained full-density buffers. | Far-world view still renders close-detail density and may remain fill/overdraw bound after draw-topology reduction. | **Open.** Page batching has landed; any far-field representation or authored density change still needs visual A/B approval. It must not hide missing content or rebuild buffers on every zoom. |
| P-08 | `Performance.TIME_PROCESS` was labelled as pure CPU and steady >22 ms was labelled as a freeze. | HUD diagnosis blamed the wrong subsystem and produced false alarms. | Resolved by performance HUD: whole-frame wording and 50 ms isolated-hitch threshold; 16.67–50 ms is sustained pressure. |
| P-09 | Standalone F2 enabled viewport timing for only one frame, producing CPU/GPU = 0, and its viewport readback polluted subsequent HUD peaks (55–75 ms). | Diagnostic action looked like a gameplay freeze and could not separate CPU submission from GPU time. | **Resolved and runtime-verified.** F4 has valid viewport timing after warm-up and excludes exactly 12 PNG-tainted samples; the 68.074 ms capture readback is absent from clean statistics. |
| P-10 | Recorder smoke tests wrote into player `performance_captures`; retention sorted F2/F4 prefixes incorrectly and could keep nine folders or evict a newer F4 session. F2 and F4 state could overlap. | Evidence could be lost or counters/measurement state mixed. | Fixed in current worktree: injected isolated test root, chronological normalized retention, current-session protection, and F2/F4 transaction guard. |
| P-11 | F12 off was recorded for 3.567 s, but movement, queue drain, draw calls and content changed throughout the adjacent windows. Off is not faster than the later enabled window. | Possible postprocess GPU bandwidth/mipmap cost remains unquantified. | Inconclusive. Run a settled, stationary, fixed-camera alternating F12 test before changing visuals. |
| P-12 | Repeated zoom transitions and a 10,190 px post-page traversal now reproduce current GPU pressure and the permanent reveal tail. Mountain digging and actual vehicle-speed traversal remain absent, and Iteration 7 deliberately adds no direction/velocity forward lobe. | Episodic mountain/mining and faster-travel hitch sources remain unknown; a symmetric source ring may still be insufficient for transport. | **Open / partially covered.** Re-run the walking route after P-14, then record dedicated mountain-dig and vehicle traces. Specify and measure a predictive forward source lobe separately instead of hiding holes with queue throttling. |
| P-13 | The first page-manager implementation could retain zero-demand entries, force already-completed stale pages through GPU publication, used an `Array.pop_front()` eviction queue, and left canceled coordinate records in that queue. State, protected ready work and stale-record traversal could therefore grow with travel distance; destroying every evicted shell also repeated scene allocation. | A sufficiently long infinite-world traversal could accumulate coordinator cost and produce retirement/upload/allocation hitches even with worker compute bounded. | **Resolved structurally; runtime delta unmeasured.** Demand zero cancels ready/staged unpublished work while preserving any exact committed front; entries without reusable front are released and pruned. Exact ticket+cursor retirement scans at most eight physical records per callback with capacity `clamp(max_resident_pages + 16, 16, 256)`. Cleared detached shells are reused from a pool capped at four and are all freed on epoch/reset. A 320-page completed-then-abandoned stress ends with zero entries, residency, ready work, uploads and commits. This is a bounded-lifetime guarantee, not evidence of higher FPS or stable 60 FPS. |
| P-14 | After all producer queues drained, three settled bookmarks retained `visibility_wait=14`, grass active slots `67/81`, and identical black rectangles. Reveal was callback-only: an expired frame guard had no autonomous wakeup, and hot promotion dropped the unique upload token on `adopt=false`. Compact HUD simultaneously reported `QUEUES 0` because it omitted the wait counter. | Chunks could remain black forever even while standing still, and the compact diagnostic concealed the cause. | **Fixed structurally in Iteration A; manual visual verification required.** Event callbacks remain the fast path. A dense O(1)-deduplicated retry ring checks at most four waiting chunks per streaming tick; terminal lifecycle removes tokens by swap index, while out-of-demand tokens stay hidden until eviction or re-entry. Failed hot adoption direct-stages the retained worker result into the live local envelope and keeps one continuation token. Compact HUD now includes `visibility_wait`. Headless tests cover blockers, lost wakeup, stale-demand suppression, swap-remove cursor stability, `adopt=false`, atomic collision/reveal, exactly-once event, dedupe and bound; a fresh F4/F2 run must prove real wait `14 -> 0`. |

## Important interpretation

P-05, P-06 and P-14 must be validated together. Iteration 7 landed the grass
topology change and Iteration A closes the permanent reveal continuation hole,
but cold object throughput and the fully revealed GPU budget remain independent
open problems. Faster/correct reveal removes black holes, but it also reaches a
denser render state sooner. Queue throttling must never be used as a render
optimization: the player must receive complete nearby chunks promptly, while
render topology/fill cost is reduced independently.

The captured 55–75 ms HUD peaks are not accepted as gameplay evidence. Every
capture whose 300-frame HUD window still contained the previous F2 readback
(`188`, `196`, `245`, `298` frames) shows a >50 ms peak; captures taken `770`,
`636` or `2,003` frames later do not. This is a strong attribution inference
from the old recorder, not a historical taint tag. Current/steady frame values,
draw counters and queue state remain valid. Tables use JSON as the canonical
sample because the on-screen HUD refreshes at a different cadence.

## Required post-Iteration-A windowed acceptance run

1. Start `F4` before moving; separately time cold initial reveal and a hot zoom
   round trip.
2. Move continuously for at least two minutes, including zoom 1.0 → 0.4 → 0.2
   → 1.0 → 0.2 and one F12 postprocess A/B interval.
3. Press `F2` only to bookmark a visible anomaly; F4 already records every
   frame.
4. Stop with `F4` and compare against both `20260715_152917_487` and
   `20260715_214016_869`: reveal throughput,
   maximum/mean `visibility_wait`, p95/p99 frame time, viewport CPU/GPU, draw
   calls and repeat-zoom queues. Include all appended page fields:
   `grass_page_inflight`, `grass_page_ready_cpu`, `grass_page_upload_queue`,
   `grass_page_resident`, `grass_page_active_slots`, `grass_page_worker_ms`, and
   `grass_page_latency_ms`. After stopping, `visibility_wait` must reach `0`,
   active grass slots must reach `81`, and the bookmarked black rectangles must
   disappear. Merely bounding the queue is not success.
5. Run dedicated mountain-dig and future vehicle-speed traces separately so
   their causes are not mixed with cold-start publication.

## Current worktree verification

- Debug and release GDExtension builds are up to date.
- Recorder/HUD smoke, object queue/cache, flora, dense object stress, object
  packet/backend, native grass flattening/page merge, worker-local 3x3 halo,
  page/backend/manager, hot ChunkView cache, depth-ladder and zoom round-trip
  contracts pass.
- Reveal regression now proves a maximum of four explicit retry checks per
  streaming tick, O(1) dedupe/removal, mountain/object/frame blockers,
  `adopt=false` local restaging, collision activation only at reveal and one
  `chunk_loaded` emission. HUD regression proves `visibility_wait=12` cannot be
  rendered as `QUEUES 0`.
- Synthetic dense grass retains the 64 exact albedo ladder stripes while four
  post-shadow chunk graphs collapse from `260` albedo-plus-directional-shadow
  owners to one page's `65`; the radius-four structural bound is
  `5,265 -> 1,755` (`-66.7%`).
- Zoom round-trip preserves 56/56 outer-ring terrain views and the page-mode
  assertion reuses at least 56 committed grass page slots. Its legacy per-view
  grass-preserve counter correctly remains zero in page mode. The second zoom-out
  performs zero grass worker recomputes, page requests/merges and raw page-buffer
  uploads; every returned slot is an exact front-buffer cache hit.
- Page-manager residency is bounded by zero-demand nonresident pruning, an
  exact-ticket cursor queue (eight records maximum per callback; physical cap
  `clamp(max_resident_pages + 16, 16, 256)`), and four detached cleared shells.
  Diagnostic entry/queue/cursor/pool counters expose those bounds without
  turning them into a frame-rate claim.
- These contracts prove scheduling, cache, packet and ordering invariants. They
  do not replace the still-pending post-Iteration-A windowed runtime comparison
  for FPS, GPU/draw-call effect, visual identity and real reveal throughput.
