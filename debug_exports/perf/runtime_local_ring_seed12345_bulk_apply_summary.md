# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_local_ring_seed12345_bulk_apply.log`
- Lines: `604`
- Errors: `1`
- Warnings: `1`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `25211.19 ms`
- `Startup.start_to_loading_screen_visible_ms`: `12.96 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `15181.35 ms`

## Frame summary
- Avg: `9.10 ms`
- P99: `19.70 ms`
- Hitches: `2`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1016.77 ms`
- `WorldPrePass.compute.flow_accumulation`: `837.46 ms`
- `WorldPrePass.compute.flow_directions`: `666.36 ms`
- `WorldPrePass.compute.lake_aware_fill`: `543.08 ms`
- `WorldPrePass.compute.slope_grid`: `419.37 ms`
- `WorldPrePass.compute.spine_seeds`: `378.19 ms`
- `WorldPrePass.compute.erosion_proxy`: `315.02 ms`
- `WorldPrePass.compute.sample_height_grid`: `124.18 ms`
- `WorldPrePass.compute.ridge_graph`: `43.11 ms`
- `WorldPrePass.compute.continentalness`: `38.65 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.26 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.35 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `537.76 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `28.18 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.80 ms`

## Recent errors
- `ERROR: 22 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent WorldPerf lines
- `[WorldPerf] Shadow.edge_cache_compute (2, -1): 184.15 ms`
- `[WorldPerf] Shadow.edge_cache_compute (0, -1): 63.06 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=507ms full=-ms border=-ms apply=2235ms converge=2235ms) queues(fast=2 urgent=0 near=14 full_near=0 full_far=162) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 15.82 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, -1): 66.14 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=769ms full=-ms border=-ms apply=2498ms converge=2498ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=165) requests(load=false staged=false generating=false) scheduler(step=0.14ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (0, 0): 62.81 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=499ms full=-ms border=-ms apply=913ms converge=913ms) queues(fast=2 urgent=0 near=17 full_near=0 full_far=170) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 13.66 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 66.37 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=796ms full=-ms border=-ms apply=1211ms converge=1211ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=170) requests(load=false staged=false generating=false) scheduler(step=0.16ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 129.62 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=513ms full=-ms border=-ms apply=936ms converge=935ms) queues(fast=1 urgent=0 near=14 full_near=0 full_far=175) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 23.07 ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 132.78 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 2): 61.87 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=801ms full=-ms border=-ms apply=1224ms converge=1224ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=175) requests(load=false staged=false generating=false) scheduler(step=0.14ms exhausted=false)`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=9.1 ms, p99=19.7 ms, hitches=2`
- `[WorldPerf] Frame budget: dispatcher=6.9ms streaming=0.0ms streaming_load=0.4ms streaming_redraw=0.0ms topology=0.1ms building=0.0ms power=0.0ms visual=0.0ms shadow=10.3ms spawn=0.0ms total=17.7ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=23.1ms, scheduler.max_urgent_wait_ms=23.1ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 2213.06 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=2213ms converge=2213ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=175) requests(load=false staged=false generating=false) scheduler(step=0.20ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1913.01 ms`

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
