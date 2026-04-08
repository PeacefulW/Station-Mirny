# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_mining_roof_topologyfix_final_seed12345.log`
- Lines: `1107`
- Errors: `1`
- Warnings: `127`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `19630.85 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.43 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `7114.42 ms`

## Frame summary
- Avg: `7.30 ms`
- P99: `13.40 ms`
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
- Warning count: `126`
- `visual / chunk_manager.streaming_redraw`: count=`50`, budget=`4.00 ms`, max_used=`13.84 ms`, max_over=`245.9%`
- `visual / mountain_shadow.visual_rebuild`: count=`43`, budget=`1.00 ms`, max_used=`13.30 ms`, max_over=`1229.5%`
- `streaming / chunk_manager.streaming_load`: count=`30`, budget=`3.00 ms`, max_used=`45.24 ms`, max_over=`1407.9%`
- `topology / chunk_manager.topology_rebuild`: count=`3`, budget=`2.00 ms`, max_used=`4.43 ms`, max_over=`121.6%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1625.78 ms`
- `WorldPrePass.compute.flow_accumulation`: `836.24 ms`
- `WorldPrePass.compute.flow_directions`: `660.64 ms`
- `WorldPrePass.compute.lake_aware_fill`: `532.05 ms`
- `WorldPrePass.compute.slope_grid`: `400.85 ms`
- `WorldPrePass.compute.erosion_proxy`: `370.89 ms`
- `WorldPrePass.compute.spine_seeds`: `370.70 ms`
- `WorldPrePass.compute.sample_height_grid`: `140.40 ms`
- `WorldPrePass.compute.ridge_graph`: `44.98 ms`
- `WorldPrePass.compute.continentalness`: `38.49 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.63 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.70 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `526.65 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `28.00 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.80 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.99 budget_ms=1.00 over_budget_pct=598.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.67 budget_ms=3.00 over_budget_pct=322.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.26 budget_ms=4.00 over_budget_pct=6.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.31 budget_ms=1.00 over_budget_pct=31.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.89 budget_ms=1.00 over_budget_pct=189.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.95 budget_ms=1.00 over_budget_pct=295.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.68 budget_ms=3.00 over_budget_pct=289.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.56 budget_ms=4.00 over_budget_pct=14.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.10 budget_ms=1.00 over_budget_pct=110.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=13.97 budget_ms=3.00 over_budget_pct=365.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.56 budget_ms=4.00 over_budget_pct=63.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.29 budget_ms=4.00 over_budget_pct=107.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.72 budget_ms=1.00 over_budget_pct=471.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.56 budget_ms=3.00 over_budget_pct=18.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.43 budget_ms=2.00 over_budget_pct=121.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.84 budget_ms=4.00 over_budget_pct=245.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.13 budget_ms=1.00 over_budget_pct=113.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.60 budget_ms=1.00 over_budget_pct=359.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.26 budget_ms=4.00 over_budget_pct=6.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.18 budget_ms=4.00 over_budget_pct=204.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.43 budget_ms=4.00 over_budget_pct=235.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.20 budget_ms=1.00 over_budget_pct=19.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.49 budget_ms=4.00 over_budget_pct=112.4`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.98 budget_ms=4.00 over_budget_pct=124.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.99 budget_ms=1.00 over_budget_pct=598.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=12.67 budget_ms=3.00 over_budget_pct=322.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.26 budget_ms=4.00 over_budget_pct=6.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.31 budget_ms=1.00 over_budget_pct=31.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.89 budget_ms=1.00 over_budget_pct=189.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.95 budget_ms=1.00 over_budget_pct=295.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.68 budget_ms=3.00 over_budget_pct=289.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.56 budget_ms=4.00 over_budget_pct=14.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.10 budget_ms=1.00 over_budget_pct=110.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=13.97 budget_ms=3.00 over_budget_pct=365.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=6.56 budget_ms=4.00 over_budget_pct=63.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.29 budget_ms=4.00 over_budget_pct=107.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.72 budget_ms=1.00 over_budget_pct=471.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.56 budget_ms=3.00 over_budget_pct=18.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.43 budget_ms=2.00 over_budget_pct=121.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.84 budget_ms=4.00 over_budget_pct=245.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.13 budget_ms=1.00 over_budget_pct=113.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.60 budget_ms=1.00 over_budget_pct=359.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.26 budget_ms=4.00 over_budget_pct=6.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.18 budget_ms=4.00 over_budget_pct=204.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.43 budget_ms=4.00 over_budget_pct=235.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.20 budget_ms=1.00 over_budget_pct=19.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.49 budget_ms=4.00 over_budget_pct=112.4`

## Recent WorldPerf lines
- `[WorldPerf] Frame budget: dispatcher=7.3ms streaming=0.0ms streaming_load=3.2ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=5.5ms spawn=0.0ms total=16.0ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=30.6ms, scheduler.max_urgent_wait_ms=30.6ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -2): 62.56 ms`
- `[WorldPerf] Shadow.edge_cache_compute (0, 0): 62.09 ms`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=502ms full=-ms border=-ms apply=639ms converge=639ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=120) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 11.06 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -1): 63.58 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 98.69 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -3): 71.97 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=509ms full=-ms border=-ms apply=967ms converge=967ms) queues(fast=1 urgent=0 near=18 full_near=0 full_far=125) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 12.32 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 129.94 ms`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 65.84 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=683ms full=-ms border=-ms apply=1141ms converge=1141ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=125) requests(load=false staged=false generating=false) scheduler(step=1.75ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (1, 2): 63.95 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -4): 135.07 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 1858.18 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=1858ms converge=1858ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=125) requests(load=false staged=false generating=false) scheduler(step=0.23ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1467.22 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -1)@z0: 2513.83 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=7.3 ms, p99=13.4 ms, hitches=1`
- `[WorldPerf] Frame budget: dispatcher=5.3ms streaming=0.0ms streaming_load=0.1ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=7.9ms spawn=0.0ms total=13.3ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=12.3ms, scheduler.max_urgent_wait_ms=12.3ms`

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
