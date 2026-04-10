# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/mountain_reveal_iteration2_far_loop_seed12345.log`
- Lines: `970`
- Errors: `1`
- Warnings: `47`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `44865.74 ms`
- `Startup.start_to_loading_screen_visible_ms`: `15.21 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6553.73 ms`

## Frame summary
- Avg: `7.20 ms`
- P99: `13.10 ms`
- Hitches: `0`

## Runtime validation
- Route preset: `far_loop`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `43`
- `streaming / chunk_manager.streaming_load`: count=`31`, budget=`3.00 ms`, max_used=`22.60 ms`, max_over=`653.3%`
- `visual / chunk_manager.streaming_redraw`: count=`11`, budget=`4.00 ms`, max_used=`10.17 ms`, max_over=`154.2%`
- `topology / underground.fog_update`: count=`1`, budget=`1.00 ms`, max_used=`1.31 ms`, max_over=`31.2%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `995.95 ms`
- `WorldPrePass.compute.flow_accumulation`: `835.21 ms`
- `WorldPrePass.compute.flow_directions`: `702.02 ms`
- `WorldPrePass.compute.lake_aware_fill`: `538.42 ms`
- `WorldPrePass.compute.spine_seeds`: `503.38 ms`
- `WorldPrePass.compute.slope_grid`: `400.42 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `349.84 ms`
- `WorldPrePass.compute.erosion_proxy`: `325.02 ms`
- `WorldPrePass.compute.sample_height_grid`: `157.40 ms`
- `WorldPrePass.compute.ridge_graph`: `70.68 ms`
- `WorldPrePass.compute.continentalness`: `40.38 ms`
- `WorldPrePass.compute.floodplain_strength`: `17.97 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `533.25 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `29.77 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `1.33 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.14 budget_ms=3.00 over_budget_pct=4.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.34 budget_ms=3.00 over_budget_pct=11.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.51 budget_ms=3.00 over_budget_pct=50.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.12 budget_ms=3.00 over_budget_pct=4.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=5.09 budget_ms=3.00 over_budget_pct=69.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.08 budget_ms=3.00 over_budget_pct=2.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=20.01 budget_ms=3.00 over_budget_pct=567.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.25 budget_ms=3.00 over_budget_pct=8.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.28 budget_ms=3.00 over_budget_pct=9.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.15 budget_ms=3.00 over_budget_pct=5.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.37 budget_ms=3.00 over_budget_pct=412.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=2.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.07 budget_ms=3.00 over_budget_pct=2.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=21.63 budget_ms=3.00 over_budget_pct=620.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.05 budget_ms=3.00 over_budget_pct=1.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.09 budget_ms=3.00 over_budget_pct=3.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.11 budget_ms=3.00 over_budget_pct=3.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.18 budget_ms=3.00 over_budget_pct=6.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.25 budget_ms=3.00 over_budget_pct=41.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.21 budget_ms=4.00 over_budget_pct=5.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=6.79 budget_ms=3.00 over_budget_pct=126.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.15 budget_ms=4.00 over_budget_pct=53.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.17 budget_ms=4.00 over_budget_pct=154.2`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=1.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.14 budget_ms=3.00 over_budget_pct=4.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.34 budget_ms=3.00 over_budget_pct=11.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.51 budget_ms=3.00 over_budget_pct=50.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.12 budget_ms=3.00 over_budget_pct=4.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=5.09 budget_ms=3.00 over_budget_pct=69.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.08 budget_ms=3.00 over_budget_pct=2.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=20.01 budget_ms=3.00 over_budget_pct=567.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.25 budget_ms=3.00 over_budget_pct=8.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.28 budget_ms=3.00 over_budget_pct=9.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.15 budget_ms=3.00 over_budget_pct=5.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.37 budget_ms=3.00 over_budget_pct=412.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=2.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.07 budget_ms=3.00 over_budget_pct=2.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=21.63 budget_ms=3.00 over_budget_pct=620.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.05 budget_ms=3.00 over_budget_pct=1.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.09 budget_ms=3.00 over_budget_pct=3.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.11 budget_ms=3.00 over_budget_pct=3.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.18 budget_ms=3.00 over_budget_pct=6.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.25 budget_ms=3.00 over_budget_pct=41.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.21 budget_ms=4.00 over_budget_pct=5.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=6.79 budget_ms=3.00 over_budget_pct=126.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.15 budget_ms=4.00 over_budget_pct=53.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.17 budget_ms=4.00 over_budget_pct=154.2`

## Recent WorldPerf lines
- `[WorldPerf] PlayerChunk coord=(0, -4) z=0 trigger=scheduler loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,generating,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=false generating=true) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=6.9 ms, p99=6.9 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=3.2ms streaming=0.0ms streaming_load=2.9ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=0.1ms spawn=0.0ms total=6.3ms/6.0ms`
- `[WorldPerf] PlayerChunk coord=(0, -3) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -3) z=0 trigger=scheduler loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,generating,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=false generating=true) scheduler(step=0.01ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,staged_apply,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=true generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=3ms full=-ms border=-ms apply=3ms converge=3ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.22ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=94ms full=-ms border=-ms apply=94ms converge=94ms) queues(fast=1 urgent=0 near=6 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (63, 1): 273.57 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 112.78 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=7.2 ms, p99=13.1 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=4.1ms streaming=0.0ms streaming_load=2.5ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=3.0ms spawn=0.0ms total=9.6ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=3.3ms, scheduler.max_urgent_wait_ms=3.3ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=723ms full=-ms border=-ms apply=723ms converge=723ms) queues(fast=1 urgent=0 near=23 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=1.22ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 152.25 ms`
- `[WorldPerf] Shadow.edge_cache_compute (63, 2): 128.31 ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, 2): 214.89 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 1346.70 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=1347ms converge=1347ms) queues(fast=0 urgent=0 near=23 full_near=1 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.29ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1314.41 ms`

## Recent CodexValidation lines
- `[CodexValidation] built validation room`
- `[CodexValidation] removed validation room wall (5, 4)`
- `[CodexValidation] re-placed validation room wall (5, 4)`
- `[CodexValidation] destroyed validation room wall (4, 5)`
- `[CodexValidation] room validation complete`
- `[CodexValidation] placed validation battery (8, 4)`
- `[CodexValidation] removed validation battery (8, 4)`
- `[CodexValidation] power validation complete`
- `[CodexValidation] mined entry tile (191, 94)`
- `[CodexValidation] first entrance reveal activated from exterior; zone_tiles=1`
- `[CodexValidation] mined interior tile (191, 95)`
- `[CodexValidation] entered mined pocket; zone_tiles=2`
- `[CodexValidation] mined deeper tile (191, 96)`
- `[CodexValidation] moved player back to exterior tile (191, 93)`
- `[CodexValidation] mining + persistence validation complete`
- `[CodexValidation] route start: preset=far_loop waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (49152.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (49152.0, 32768.0)`
- `[CodexValidation] reached waypoint 3/6 at (221184.0, 32768.0)`
- `[CodexValidation] reached waypoint 4/6 at (221184.0, -32768.0)`
- `[CodexValidation] reached waypoint 5/6 at (0.0, -32768.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=far_loop reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=far_loop reached=6/6 redraw_backlog=false`
