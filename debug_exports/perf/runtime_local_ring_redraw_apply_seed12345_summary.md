# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_local_ring_redraw_apply_seed12345.log`
- Lines: `609`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25040.99 ms`
- `Startup.start_to_loading_screen_visible_ms`: `12.89 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `16177.23 ms`

## Frame summary
- Avg: `10.20 ms`
- P99: `45.10 ms`
- Hitches: `12`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `955.77 ms`
- `WorldPrePass.compute.flow_accumulation`: `803.01 ms`
- `WorldPrePass.compute.flow_directions`: `655.77 ms`
- `WorldPrePass.compute.lake_aware_fill`: `528.99 ms`
- `WorldPrePass.compute.spine_seeds`: `392.07 ms`
- `WorldPrePass.compute.slope_grid`: `388.56 ms`
- `WorldPrePass.compute.erosion_proxy`: `301.87 ms`
- `WorldPrePass.compute.sample_height_grid`: `154.19 ms`
- `WorldPrePass.compute.ridge_graph`: `43.58 ms`
- `WorldPrePass.compute.continentalness`: `39.03 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.79 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.39 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `523.77 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.68 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.85 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] Shadow.edge_cache_compute (1, -1): 66.70 ms`
- `[WorldPerf] Shadow.edge_cache_compute (63, -1): 65.03 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=500ms full=-ms border=-ms apply=2289ms converge=2289ms) queues(fast=1 urgent=0 near=17 full_near=0 full_far=165) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 13.16 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -1): 154.85 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=737ms full=-ms border=-ms apply=2527ms converge=2527ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=165) requests(load=false staged=false generating=false) scheduler(step=0.41ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (0, 0): 66.03 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=524ms full=-ms border=-ms apply=928ms converge=928ms) queues(fast=1 urgent=0 near=17 full_near=0 full_far=170) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 12.01 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 65.11 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=10.2 ms, p99=45.1 ms, hitches=12`
- `[WorldPerf] Frame budget: dispatcher=7.8ms streaming=0.0ms streaming_load=0.6ms streaming_redraw=0.0ms topology=0.1ms building=0.0ms power=0.0ms visual=0.0ms shadow=11.1ms spawn=0.0ms total=19.6ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=12.0ms, scheduler.max_urgent_wait_ms=12.0ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=823ms full=-ms border=-ms apply=1227ms converge=1227ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=170) requests(load=false staged=false generating=false) scheduler(step=0.28ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 124.56 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=495ms full=-ms border=-ms apply=948ms converge=948ms) queues(fast=2 urgent=0 near=17 full_near=0 full_far=175) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 14.65 ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 128.29 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 2): 66.55 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=810ms full=-ms border=-ms apply=1263ms converge=1263ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=175) requests(load=false staged=false generating=false) scheduler(step=0.21ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 2130.19 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=2130ms converge=2130ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=175) requests(load=false staged=false generating=false) scheduler(step=0.21ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1779.16 ms`

## Recent CodexValidation lines
- `[CodexValidation] mining validation prepared at (59, 0)`
- `[CodexValidation] boot complete; route prepared`
- `[CodexValidation] built validation room`
- `[CodexValidation] removed validation room wall (5, 4)`
- `[CodexValidation] re-placed validation room wall (5, 4)`
- `[CodexValidation] destroyed validation room wall (4, 5)`
- `[CodexValidation] room validation complete`
- `[CodexValidation] placed validation battery (8, 4)`
- `[CodexValidation] removed validation battery (8, 4)`
- `[CodexValidation] power validation complete`
- `[CodexValidation] mined entry tile (59, 0)`
- `[CodexValidation] mined interior tile (60, 0)`
- `[CodexValidation] mined deeper tile (61, 0)`
- `[CodexValidation] moved player back to exterior tile (58, 0)`
- `[CodexValidation] mining + persistence validation complete`
- `[CodexValidation] route start: preset=local_ring waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (24576.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (24576.0, 20480.0)`
- `[CodexValidation] reached waypoint 3/6 at (241664.0, 20480.0)`
- `[CodexValidation] reached waypoint 4/6 at (241664.0, -16384.0)`
- `[CodexValidation] reached waypoint 5/6 at (0.0, -16384.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=local_ring reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=local_ring reached=6/6 redraw_backlog=false`
