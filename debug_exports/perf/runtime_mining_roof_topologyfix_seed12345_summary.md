# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_mining_roof_topologyfix_seed12345.log`
- Lines: `1093`
- Errors: `1`
- Warnings: `127`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `18158.23 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.84 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6859.01 ms`

## Frame summary
- Avg: `8.80 ms`
- P99: `20.10 ms`
- Hitches: `2`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `126`
- `visual / mountain_shadow.visual_rebuild`: count=`46`, budget=`1.00 ms`, max_used=`12.40 ms`, max_over=`1140.1%`
- `visual / chunk_manager.streaming_redraw`: count=`40`, budget=`4.00 ms`, max_used=`15.07 ms`, max_over=`276.9%`
- `streaming / chunk_manager.streaming_load`: count=`37`, budget=`3.00 ms`, max_used=`17.44 ms`, max_over=`481.2%`
- `topology / chunk_manager.topology_rebuild`: count=`3`, budget=`2.00 ms`, max_used=`4.02 ms`, max_over=`100.8%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `962.08 ms`
- `WorldPrePass.compute.flow_accumulation`: `813.11 ms`
- `WorldPrePass.compute.flow_directions`: `647.07 ms`
- `WorldPrePass.compute.lake_aware_fill`: `525.05 ms`
- `WorldPrePass.compute.slope_grid`: `391.82 ms`
- `WorldPrePass.compute.spine_seeds`: `372.09 ms`
- `WorldPrePass.compute.erosion_proxy`: `317.25 ms`
- `WorldPrePass.compute.sample_height_grid`: `123.86 ms`
- `WorldPrePass.compute.ridge_graph`: `45.93 ms`
- `WorldPrePass.compute.continentalness`: `37.56 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.35 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.59 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `519.60 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.31 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.79 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.15 budget_ms=4.00 over_budget_pct=3.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.66 budget_ms=1.00 over_budget_pct=566.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.99 budget_ms=3.00 over_budget_pct=266.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.15 budget_ms=4.00 over_budget_pct=103.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=16.28 budget_ms=3.00 over_budget_pct=442.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.75 budget_ms=1.00 over_budget_pct=375.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.72 budget_ms=1.00 over_budget_pct=572.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.45 budget_ms=4.00 over_budget_pct=136.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.31 budget_ms=4.00 over_budget_pct=232.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=12.40 budget_ms=1.00 over_budget_pct=1139.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.66 budget_ms=3.00 over_budget_pct=21.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=5.94 budget_ms=3.00 over_budget_pct=97.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.53 budget_ms=3.00 over_budget_pct=284.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=2.77 budget_ms=2.00 over_budget_pct=38.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.53 budget_ms=4.00 over_budget_pct=163.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.56 budget_ms=1.00 over_budget_pct=455.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.94 budget_ms=4.00 over_budget_pct=223.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.07 budget_ms=4.00 over_budget_pct=276.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.02 budget_ms=2.00 over_budget_pct=100.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.70 budget_ms=1.00 over_budget_pct=570.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.68 budget_ms=4.00 over_budget_pct=17.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.54 budget_ms=4.00 over_budget_pct=138.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.33 budget_ms=1.00 over_budget_pct=233.0`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.04 budget_ms=3.00 over_budget_pct=401.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.15 budget_ms=4.00 over_budget_pct=3.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.66 budget_ms=1.00 over_budget_pct=566.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.99 budget_ms=3.00 over_budget_pct=266.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.15 budget_ms=4.00 over_budget_pct=103.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=16.28 budget_ms=3.00 over_budget_pct=442.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.75 budget_ms=1.00 over_budget_pct=375.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.72 budget_ms=1.00 over_budget_pct=572.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.45 budget_ms=4.00 over_budget_pct=136.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.31 budget_ms=4.00 over_budget_pct=232.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=12.40 budget_ms=1.00 over_budget_pct=1139.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.66 budget_ms=3.00 over_budget_pct=21.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=5.94 budget_ms=3.00 over_budget_pct=97.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.53 budget_ms=3.00 over_budget_pct=284.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=2.77 budget_ms=2.00 over_budget_pct=38.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.53 budget_ms=4.00 over_budget_pct=163.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.56 budget_ms=1.00 over_budget_pct=455.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.94 budget_ms=4.00 over_budget_pct=223.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.07 budget_ms=4.00 over_budget_pct=276.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.02 budget_ms=2.00 over_budget_pct=100.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.70 budget_ms=1.00 over_budget_pct=570.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.68 budget_ms=4.00 over_budget_pct=17.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.54 budget_ms=4.00 over_budget_pct=138.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.33 budget_ms=1.00 over_budget_pct=233.0`

## Recent WorldPerf lines
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=503ms full=-ms border=-ms apply=706ms converge=706ms) queues(fast=2 urgent=0 near=16 full_near=0 full_far=126) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 36.85 ms`
- `[WorldPerf] Shadow.try_shadow_step start=none deferred=4: 8.78 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=771ms full=-ms border=-ms apply=975ms converge=975ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=126) requests(load=false staged=false generating=false) scheduler(step=3.34ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=499ms full=-ms border=-ms apply=565ms converge=565ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=131) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 11.61 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -2): 68.87 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=564ms full=-ms border=-ms apply=630ms converge=630ms) queues(fast=2 urgent=0 near=22 full_near=0 full_far=131) requests(load=false staged=false generating=false) scheduler(step=0.60ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 60.86 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -3): 76.69 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=508ms full=-ms border=-ms apply=955ms converge=955ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=136) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 14.64 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 137.12 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=690ms full=-ms border=-ms apply=1137ms converge=1137ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=136) requests(load=false staged=false generating=false) scheduler(step=1.68ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 61.66 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 2): 62.45 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -4): 123.19 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=8.8 ms, p99=20.1 ms, hitches=2`
- `[WorldPerf] Frame budget: dispatcher=6.4ms streaming=0.0ms streaming_load=1.1ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.5ms spawn=0.0ms total=16.0ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=14.6ms, scheduler.max_urgent_wait_ms=14.6ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 1806.99 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=1807ms converge=1807ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=136) requests(load=false staged=false generating=false) scheduler(step=0.18ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1409.70 ms`

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
