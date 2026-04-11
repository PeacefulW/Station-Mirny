# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/mountain_reveal_iteration2_runtime_seed12345_fixroof3.log`
- Lines: `933`
- Errors: `1`
- Warnings: `77`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `43114.97 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.47 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6338.38 ms`

## Frame summary
- Avg: `7.80 ms`
- P99: `12.30 ms`
- Hitches: `0`

## Runtime validation
- Route preset: `local_ring`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`
- Latest catch-up status: `[CodexValidation] catch-up status: blocker=streaming_truth stalled_intervals=0 streaming_truth_idle=false redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=18076 gen_coord=(0, -3) topology_ready=true native_topology=true native_dirty=false dirty=false build_in_progress=false`

## Budget overrun offenders
- Warning count: `47`
- `streaming / chunk_manager.streaming_load`: count=`21`, budget=`3.00 ms`, max_used=`22.48 ms`, max_over=`649.5%`
- `visual / chunk_manager.streaming_redraw`: count=`17`, budget=`4.00 ms`, max_used=`30.05 ms`, max_over=`651.3%`
- `visual / mountain_shadow.visual_rebuild`: count=`9`, budget=`1.00 ms`, max_used=`4.68 ms`, max_over=`367.8%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1005.54 ms`
- `WorldPrePass.compute.flow_accumulation`: `833.89 ms`
- `WorldPrePass.compute.flow_directions`: `675.96 ms`
- `WorldPrePass.compute.spine_seeds`: `544.45 ms`
- `WorldPrePass.compute.lake_aware_fill`: `537.91 ms`
- `WorldPrePass.compute.slope_grid`: `395.00 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `356.83 ms`
- `WorldPrePass.compute.erosion_proxy`: `323.68 ms`
- `WorldPrePass.compute.sample_height_grid`: `142.35 ms`
- `WorldPrePass.compute.ridge_graph`: `68.47 ms`
- `WorldPrePass.compute.continentalness`: `39.28 ms`
- `WorldPrePass.compute.floodplain_strength`: `17.70 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `532.53 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `28.57 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `1.25 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.09 budget_ms=3.00 over_budget_pct=3.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=20.25 budget_ms=4.00 over_budget_pct=406.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.01 budget_ms=4.00 over_budget_pct=575.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=30.05 budget_ms=4.00 over_budget_pct=651.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=2.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=22.48 budget_ms=3.00 over_budget_pct=649.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=1.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.08 budget_ms=3.00 over_budget_pct=2.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.27 budget_ms=3.00 over_budget_pct=42.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.09 budget_ms=3.00 over_budget_pct=3.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=17.54 budget_ms=3.00 over_budget_pct=484.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.54 budget_ms=1.00 over_budget_pct=253.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=2.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.08 budget_ms=3.00 over_budget_pct=2.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.42 budget_ms=3.00 over_budget_pct=47.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=6.01 budget_ms=3.00 over_budget_pct=100.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.40 budget_ms=1.00 over_budget_pct=40.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=8.20 budget_ms=3.00 over_budget_pct=173.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.57 budget_ms=4.00 over_budget_pct=14.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.07 budget_ms=4.00 over_budget_pct=76.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.47 budget_ms=1.00 over_budget_pct=146.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.66 budget_ms=4.00 over_budget_pct=16.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.18 budget_ms=4.00 over_budget_pct=204.4`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.68 budget_ms=1.00 over_budget_pct=367.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.09 budget_ms=3.00 over_budget_pct=3.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=20.25 budget_ms=4.00 over_budget_pct=406.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.01 budget_ms=4.00 over_budget_pct=575.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=30.05 budget_ms=4.00 over_budget_pct=651.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=2.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=22.48 budget_ms=3.00 over_budget_pct=649.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=1.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.08 budget_ms=3.00 over_budget_pct=2.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.27 budget_ms=3.00 over_budget_pct=42.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.09 budget_ms=3.00 over_budget_pct=3.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=17.54 budget_ms=3.00 over_budget_pct=484.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.54 budget_ms=1.00 over_budget_pct=253.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.06 budget_ms=3.00 over_budget_pct=2.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.08 budget_ms=3.00 over_budget_pct=2.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=4.42 budget_ms=3.00 over_budget_pct=47.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=6.01 budget_ms=3.00 over_budget_pct=100.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.40 budget_ms=1.00 over_budget_pct=40.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=8.20 budget_ms=3.00 over_budget_pct=173.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.57 budget_ms=4.00 over_budget_pct=14.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.07 budget_ms=4.00 over_budget_pct=76.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.47 budget_ms=1.00 over_budget_pct=146.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.66 budget_ms=4.00 over_budget_pct=16.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.18 budget_ms=4.00 over_budget_pct=204.4`

## Recent WorldPerf lines
- `[WorldPerf] PlayerChunk coord=(0, -4) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -4) z=0 trigger=scheduler loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,generating,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=false generating=true) scheduler(step=0.02ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -3) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=8.5 ms, p99=11.4 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=5.0ms streaming=0.0ms streaming_load=2.9ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=3.9ms spawn=0.0ms total=11.8ms/6.0ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,staged_apply,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=true generating=false) scheduler(step=0.01ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=3ms full=-ms border=-ms apply=3ms converge=3ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.30ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,load_queued,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=true staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=false visible=false state=not_loaded phase=none first_pass=false full_ready=false issues=not_loaded,staged_apply,first_pass_not_ready ages(first=-ms full=-ms border=-ms apply=-ms converge=-ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=true generating=false) scheduler(step=0.03ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=2ms full=-ms border=-ms apply=2ms converge=2ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.22ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=82ms full=-ms border=-ms apply=82ms converge=82ms) queues(fast=1 urgent=0 near=6 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (63, 1): 331.55 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 161.32 ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 143.66 ms`
- `[WorldPerf] Shadow.edge_cache_compute (63, 2): 130.63 ms`
- `[WorldPerf] FPS: 118.0`
- `[WorldPerf] Shadow.edge_cache_compute (62, 2): 267.60 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=1577ms full=-ms border=-ms apply=1577ms converge=1577ms) queues(fast=2 urgent=0 near=22 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.75ms exhausted=false)`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=7.8 ms, p99=12.3 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=5.3ms streaming=0.0ms streaming_load=1.3ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=7.5ms spawn=0.0ms total=14.1ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=3.5ms, scheduler.max_urgent_wait_ms=3.5ms`

## Recent CodexValidation lines
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
- `[CodexValidation] route start: preset=local_ring waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (24576.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (24576.0, 20480.0)`
- `[CodexValidation] reached waypoint 3/6 at (241664.0, 20480.0)`
- `[CodexValidation] reached waypoint 4/6 at (241664.0, -16384.0)`
- `[CodexValidation] reached waypoint 5/6 at (0.0, -16384.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=local_ring reached=6/6 draining_background_work=true`
- `[CodexValidation] waiting for world catch-up: preset=local_ring reached=6/6`
- `[CodexValidation] catch-up status: blocker=streaming_truth stalled_intervals=0 streaming_truth_idle=false redraw_idle=true load_queue=0 load_queue_preview=[] redraw=0 staged_chunk=no staged_data=0 gen_task_id=18076 gen_coord=(0, -3) topology_ready=true native_topology=true native_dirty=false dirty=false build_in_progress=false`
- `[CodexValidation] route drain complete; preset=local_ring reached=6/6 redraw_backlog=false`
