# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_mining_roof_seed12345_rerun.log`
- Lines: `1067`
- Errors: `1`
- Warnings: `121`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `19303.95 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.68 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6765.68 ms`

## Frame summary
- Avg: `9.80 ms`
- P99: `17.50 ms`
- Hitches: `1`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `120`
- `visual / mountain_shadow.visual_rebuild`: count=`45`, budget=`1.00 ms`, max_used=`37.76 ms`, max_over=`3676.1%`
- `visual / chunk_manager.streaming_redraw`: count=`41`, budget=`4.00 ms`, max_used=`14.73 ms`, max_over=`268.3%`
- `streaming / chunk_manager.streaming_load`: count=`32`, budget=`3.00 ms`, max_used=`16.51 ms`, max_over=`450.4%`
- `topology / chunk_manager.topology_rebuild`: count=`2`, budget=`2.00 ms`, max_used=`3.38 ms`, max_over=`69.0%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1011.64 ms`
- `WorldPrePass.compute.flow_accumulation`: `937.16 ms`
- `WorldPrePass.compute.flow_directions`: `687.61 ms`
- `WorldPrePass.compute.lake_aware_fill`: `592.51 ms`
- `WorldPrePass.compute.spine_seeds`: `410.59 ms`
- `WorldPrePass.compute.slope_grid`: `404.59 ms`
- `WorldPrePass.compute.erosion_proxy`: `323.91 ms`
- `WorldPrePass.compute.sample_height_grid`: `139.41 ms`
- `WorldPrePass.compute.ridge_graph`: `46.35 ms`
- `WorldPrePass.compute.continentalness`: `42.22 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `25.78 ms`
- `WorldPrePass.compute.floodplain_strength`: `13.27 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `586.82 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `31.77 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.86 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.19 budget_ms=4.00 over_budget_pct=29.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.98 budget_ms=3.00 over_budget_pct=332.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.19 budget_ms=1.00 over_budget_pct=319.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.95 budget_ms=1.00 over_budget_pct=495.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.00 budget_ms=3.00 over_budget_pct=366.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.10 budget_ms=4.00 over_budget_pct=2.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.08 budget_ms=1.00 over_budget_pct=208.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.92 budget_ms=1.00 over_budget_pct=491.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.89 budget_ms=4.00 over_budget_pct=47.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.07 budget_ms=4.00 over_budget_pct=76.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=13.83 budget_ms=3.00 over_budget_pct=361.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=8.27 budget_ms=1.00 over_budget_pct=727.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.38 budget_ms=2.00 over_budget_pct=69.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.73 budget_ms=4.00 over_budget_pct=218.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.50 budget_ms=3.00 over_budget_pct=16.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.30 budget_ms=1.00 over_budget_pct=30.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.23 budget_ms=1.00 over_budget_pct=323.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=14.73 budget_ms=4.00 over_budget_pct=268.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.91 budget_ms=1.00 over_budget_pct=591.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.24 budget_ms=4.00 over_budget_pct=31.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.66 budget_ms=4.00 over_budget_pct=141.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.24 budget_ms=1.00 over_budget_pct=24.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.90 budget_ms=1.00 over_budget_pct=290.5`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.82 budget_ms=1.00 over_budget_pct=182.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.19 budget_ms=4.00 over_budget_pct=29.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.98 budget_ms=3.00 over_budget_pct=332.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.19 budget_ms=1.00 over_budget_pct=319.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.95 budget_ms=1.00 over_budget_pct=495.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.00 budget_ms=3.00 over_budget_pct=366.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.10 budget_ms=4.00 over_budget_pct=2.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.08 budget_ms=1.00 over_budget_pct=208.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.92 budget_ms=1.00 over_budget_pct=491.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.89 budget_ms=4.00 over_budget_pct=47.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.07 budget_ms=4.00 over_budget_pct=76.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=13.83 budget_ms=3.00 over_budget_pct=361.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=8.27 budget_ms=1.00 over_budget_pct=727.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.38 budget_ms=2.00 over_budget_pct=69.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.73 budget_ms=4.00 over_budget_pct=218.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.50 budget_ms=3.00 over_budget_pct=16.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.30 budget_ms=1.00 over_budget_pct=30.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.23 budget_ms=1.00 over_budget_pct=323.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=14.73 budget_ms=4.00 over_budget_pct=268.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.91 budget_ms=1.00 over_budget_pct=591.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.24 budget_ms=4.00 over_budget_pct=31.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.66 budget_ms=4.00 over_budget_pct=141.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.24 budget_ms=1.00 over_budget_pct=24.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.90 budget_ms=1.00 over_budget_pct=290.5`

## Recent WorldPerf lines
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=464ms full=-ms border=-ms apply=465ms converge=464ms) queues(fast=2 urgent=0 near=17 full_near=0 full_far=121) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 11.25 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=672ms full=-ms border=-ms apply=672ms converge=672ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=121) requests(load=false staged=false generating=false) scheduler(step=3.01ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, -2): 68.79 ms`
- `[WorldPerf] Shadow.edge_cache_compute (0, 0): 62.11 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=517ms full=-ms border=-ms apply=633ms converge=633ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=126) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 12.98 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -1): 61.41 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 67.27 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -3): 79.14 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 129.12 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=503ms full=-ms border=-ms apply=991ms converge=991ms) queues(fast=1 urgent=0 near=18 full_near=0 full_far=131) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 10.03 ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 119.82 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=9.8 ms, p99=17.5 ms, hitches=1`
- `[WorldPerf] Frame budget: dispatcher=6.9ms streaming=0.0ms streaming_load=2.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.9ms spawn=0.0ms total=17.9ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=10.0ms, scheduler.max_urgent_wait_ms=10.0ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=691ms full=-ms border=-ms apply=1179ms converge=1179ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=131) requests(load=false staged=false generating=false) scheduler(step=1.70ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, -4): 132.00 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 1870.65 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=1871ms converge=1871ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=131) requests(load=false staged=false generating=false) scheduler(step=0.21ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1432.88 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -1)@z0: 2308.36 ms`

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
