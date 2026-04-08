# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_mining_roof_topologyfix3_seed12345.log`
- Lines: `1089`
- Errors: `1`
- Warnings: `126`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `18032.50 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.69 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6092.53 ms`

## Frame summary
- Avg: `10.40 ms`
- P99: `21.70 ms`
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
- Warning count: `125`
- `visual / mountain_shadow.visual_rebuild`: count=`45`, budget=`1.00 ms`, max_used=`12.28 ms`, max_over=`1128.1%`
- `visual / chunk_manager.streaming_redraw`: count=`45`, budget=`4.00 ms`, max_used=`17.58 ms`, max_over=`339.6%`
- `streaming / chunk_manager.streaming_load`: count=`32`, budget=`3.00 ms`, max_used=`19.39 ms`, max_over=`546.4%`
- `topology / chunk_manager.topology_rebuild`: count=`3`, budget=`2.00 ms`, max_used=`3.98 ms`, max_over=`99.2%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `973.64 ms`
- `WorldPrePass.compute.flow_accumulation`: `828.96 ms`
- `WorldPrePass.compute.flow_directions`: `642.98 ms`
- `WorldPrePass.compute.lake_aware_fill`: `520.86 ms`
- `WorldPrePass.compute.slope_grid`: `412.99 ms`
- `WorldPrePass.compute.spine_seeds`: `369.68 ms`
- `WorldPrePass.compute.erosion_proxy`: `314.92 ms`
- `WorldPrePass.compute.sample_height_grid`: `125.30 ms`
- `WorldPrePass.compute.ridge_graph`: `47.48 ms`
- `WorldPrePass.compute.continentalness`: `37.85 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.75 ms`
- `WorldPrePass.compute.floodplain_strength`: `12.91 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `515.64 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.73 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.81 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.42 budget_ms=4.00 over_budget_pct=85.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=7.02 budget_ms=1.00 over_budget_pct=601.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.00 budget_ms=3.00 over_budget_pct=366.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=18.14 budget_ms=3.00 over_budget_pct=504.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.41 budget_ms=4.00 over_budget_pct=60.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=17.58 budget_ms=4.00 over_budget_pct=339.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.50 budget_ms=1.00 over_budget_pct=450.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=8.68 budget_ms=1.00 over_budget_pct=768.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=2.82 budget_ms=2.00 over_budget_pct=40.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.16 budget_ms=4.00 over_budget_pct=4.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.08 budget_ms=4.00 over_budget_pct=177.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.13 budget_ms=3.00 over_budget_pct=4.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.98 budget_ms=2.00 over_budget_pct=99.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.52 budget_ms=4.00 over_budget_pct=213.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.43 budget_ms=1.00 over_budget_pct=42.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.68 budget_ms=1.00 over_budget_pct=168.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.83 budget_ms=4.00 over_budget_pct=245.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.07 budget_ms=1.00 over_budget_pct=307.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.46 budget_ms=3.00 over_budget_pct=48.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.91 budget_ms=4.00 over_budget_pct=97.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.11 budget_ms=1.00 over_budget_pct=11.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.82 budget_ms=1.00 over_budget_pct=281.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.12 budget_ms=4.00 over_budget_pct=128.1`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.08 budget_ms=3.00 over_budget_pct=302.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.42 budget_ms=4.00 over_budget_pct=85.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=7.02 budget_ms=1.00 over_budget_pct=601.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.00 budget_ms=3.00 over_budget_pct=366.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=18.14 budget_ms=3.00 over_budget_pct=504.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.41 budget_ms=4.00 over_budget_pct=60.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=17.58 budget_ms=4.00 over_budget_pct=339.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.50 budget_ms=1.00 over_budget_pct=450.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=8.68 budget_ms=1.00 over_budget_pct=768.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=2.82 budget_ms=2.00 over_budget_pct=40.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.16 budget_ms=4.00 over_budget_pct=4.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.08 budget_ms=4.00 over_budget_pct=177.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.13 budget_ms=3.00 over_budget_pct=4.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.98 budget_ms=2.00 over_budget_pct=99.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.52 budget_ms=4.00 over_budget_pct=213.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.43 budget_ms=1.00 over_budget_pct=42.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.68 budget_ms=1.00 over_budget_pct=168.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.83 budget_ms=4.00 over_budget_pct=245.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.07 budget_ms=1.00 over_budget_pct=307.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.46 budget_ms=3.00 over_budget_pct=48.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.91 budget_ms=4.00 over_budget_pct=97.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.11 budget_ms=1.00 over_budget_pct=11.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.82 budget_ms=1.00 over_budget_pct=281.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.12 budget_ms=4.00 over_budget_pct=128.1`

## Recent WorldPerf lines
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=505ms full=-ms border=-ms apply=594ms converge=594ms) queues(fast=2 urgent=0 near=16 full_near=0 full_far=126) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 16.73 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=769ms full=-ms border=-ms apply=858ms converge=858ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=126) requests(load=false staged=false generating=false) scheduler(step=0.43ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=499ms full=-ms border=-ms apply=582ms converge=582ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=131) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 12.16 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -2): 62.82 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=568ms full=-ms border=-ms apply=650ms converge=650ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=131) requests(load=false staged=false generating=false) scheduler(step=0.48ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, -1): 65.41 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=10.4 ms, p99=21.7 ms, hitches=2`
- `[WorldPerf] Frame budget: dispatcher=7.3ms streaming=0.0ms streaming_load=2.8ms streaming_redraw=0.1ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=7.7ms spawn=0.0ms total=18.0ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=12.2ms, scheduler.max_urgent_wait_ms=12.2ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 64.90 ms`
- `[WorldPerf] FPS: 88.0`
- `[WorldPerf] Shadow.edge_cache_compute (2, -3): 62.92 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=507ms full=-ms border=-ms apply=986ms converge=986ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=136) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 14.45 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 122.14 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=655ms full=-ms border=-ms apply=1134ms converge=1134ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=136) requests(load=false staged=false generating=false) scheduler(step=1.84ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (2, -4): 133.19 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 1837.88 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=1838ms converge=1838ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=136) requests(load=false staged=false generating=false) scheduler(step=0.20ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1417.62 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -1)@z0: 2538.03 ms`

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
