# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_mining_roof_seed12345.log`
- Lines: `1092`
- Errors: `1`
- Warnings: `121`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `24195.94 ms`
- `Startup.start_to_loading_screen_visible_ms`: `22.93 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6523.15 ms`

## Frame summary
- Avg: `7.70 ms`
- P99: `14.40 ms`
- Hitches: `0`

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
- `visual / chunk_manager.streaming_redraw`: count=`43`, budget=`4.00 ms`, max_used=`15.19 ms`, max_over=`279.6%`
- `visual / mountain_shadow.visual_rebuild`: count=`38`, budget=`1.00 ms`, max_used=`14.11 ms`, max_over=`1311.1%`
- `streaming / chunk_manager.streaming_load`: count=`31`, budget=`3.00 ms`, max_used=`39.78 ms`, max_over=`1226.1%`
- `topology / chunk_manager.topology_rebuild`: count=`3`, budget=`2.00 ms`, max_used=`4.08 ms`, max_over=`103.8%`
- `topology / power.balance_recompute`: count=`2`, budget=`1.00 ms`, max_used=`5.20 ms`, max_over=`420.1%`
- `topology / building.room_recompute`: count=`2`, budget=`1.50 ms`, max_used=`3.09 ms`, max_over=`105.7%`
- `topology / underground.fog_update`: count=`1`, budget=`1.00 ms`, max_used=`1.75 ms`, max_over=`74.7%`

## WorldPrePass phases
- `WorldPrePass.compute.flow_directions`: `1061.46 ms`
- `WorldPrePass.compute.rain_shadow`: `1020.50 ms`
- `WorldPrePass.compute.lake_aware_fill`: `1001.04 ms`
- `WorldPrePass.compute.flow_accumulation`: `939.66 ms`
- `WorldPrePass.compute.spine_seeds`: `725.54 ms`
- `WorldPrePass.compute.slope_grid`: `403.08 ms`
- `WorldPrePass.compute.erosion_proxy`: `314.44 ms`
- `WorldPrePass.compute.sample_height_grid`: `262.10 ms`
- `WorldPrePass.compute.ridge_graph`: `87.93 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `52.94 ms`
- `WorldPrePass.compute.continentalness`: `39.79 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.55 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `991.97 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `29.40 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `8.68 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `1.41 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.30 budget_ms=4.00 over_budget_pct=7.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.49 budget_ms=3.00 over_budget_pct=416.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.25 budget_ms=4.00 over_budget_pct=81.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=39.78 budget_ms=3.00 over_budget_pct=1226.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.02 budget_ms=1.00 over_budget_pct=102.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.33 budget_ms=1.00 over_budget_pct=533.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=8.00 budget_ms=1.00 over_budget_pct=700.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.15 budget_ms=4.00 over_budget_pct=3.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=9.59 budget_ms=1.00 over_budget_pct=858.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.70 budget_ms=3.00 over_budget_pct=290.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=21.01 budget_ms=3.00 over_budget_pct=600.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.51 budget_ms=4.00 over_budget_pct=112.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=7.05 budget_ms=1.00 over_budget_pct=605.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.00 budget_ms=2.00 over_budget_pct=50.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.21 budget_ms=4.00 over_budget_pct=205.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.24 budget_ms=4.00 over_budget_pct=230.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.33 budget_ms=3.00 over_budget_pct=11.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.19 budget_ms=4.00 over_budget_pct=279.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.01 budget_ms=2.00 over_budget_pct=100.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.89 budget_ms=1.00 over_budget_pct=389.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.87 budget_ms=1.00 over_budget_pct=587.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.57 budget_ms=4.00 over_budget_pct=164.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.26 budget_ms=1.00 over_budget_pct=226.2`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.26 budget_ms=3.00 over_budget_pct=375.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.30 budget_ms=4.00 over_budget_pct=7.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.49 budget_ms=3.00 over_budget_pct=416.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.25 budget_ms=4.00 over_budget_pct=81.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=39.78 budget_ms=3.00 over_budget_pct=1226.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.02 budget_ms=1.00 over_budget_pct=102.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.33 budget_ms=1.00 over_budget_pct=533.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=8.00 budget_ms=1.00 over_budget_pct=700.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.15 budget_ms=4.00 over_budget_pct=3.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=9.59 budget_ms=1.00 over_budget_pct=858.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.70 budget_ms=3.00 over_budget_pct=290.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=21.01 budget_ms=3.00 over_budget_pct=600.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.51 budget_ms=4.00 over_budget_pct=112.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=7.05 budget_ms=1.00 over_budget_pct=605.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.00 budget_ms=2.00 over_budget_pct=50.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.21 budget_ms=4.00 over_budget_pct=205.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=13.24 budget_ms=4.00 over_budget_pct=230.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=3.33 budget_ms=3.00 over_budget_pct=11.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.19 budget_ms=4.00 over_budget_pct=279.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.01 budget_ms=2.00 over_budget_pct=100.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.89 budget_ms=1.00 over_budget_pct=389.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.87 budget_ms=1.00 over_budget_pct=587.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.57 budget_ms=4.00 over_budget_pct=164.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.26 budget_ms=1.00 over_budget_pct=226.2`

## Recent WorldPerf lines
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 12.63 ms`
- `[WorldPerf] PlayerChunk coord=(0, -2) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=659ms full=-ms border=-ms apply=660ms converge=660ms) queues(fast=2 urgent=0 near=22 full_near=0 full_far=71) requests(load=false staged=false generating=false) scheduler(step=3.42ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=505ms full=-ms border=-ms apply=574ms converge=574ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=76) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 8.91 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -2): 67.68 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -1): 68.68 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 1): 64.71 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, -3): 65.94 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=entered_chunk loaded=true visible=false state=native_ready phase=terrain first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=511ms full=-ms border=-ms apply=1001ms converge=1001ms) queues(fast=2 urgent=0 near=18 full_near=0 full_far=81) requests(load=false staged=false generating=false) scheduler(step=0.00ms exhausted=false)`
- `[WorldPerf] Scheduler.fast_visual_wait_ms: 11.79 ms`
- `[WorldPerf] Shadow.edge_cache_compute (2, 1): 133.67 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=native_ready phase=cover first_pass=false full_ready=false issues=first_pass_not_ready,first_pass_pending ages(first=681ms full=-ms border=-ms apply=1171ms converge=1171ms) queues(fast=2 urgent=0 near=23 full_near=0 full_far=81) requests(load=false staged=false generating=false) scheduler(step=1.68ms exhausted=false)`
- `[WorldPerf] Shadow.edge_cache_compute (62, 1): 68.72 ms`
- `[WorldPerf] Shadow.edge_cache_compute (1, 2): 61.32 ms`
- `[WorldPerf] FPS: 97.0`
- `[WorldPerf] Shadow.edge_cache_compute (2, -4): 133.41 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 0)@z0: 1868.51 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=false state=full_pending phase=cliff first_pass=true full_ready=false issues=full_redraw_pending ages(first=-ms full=0ms border=-ms apply=1869ms converge=1869ms) queues(fast=1 urgent=0 near=23 full_near=1 full_far=81) requests(load=false staged=false generating=false) scheduler(step=0.21ms exhausted=false)`
- `[WorldPerf] stream.chunk_first_pass_ms (0, 1)@z0: 1461.42 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=7.7 ms, p99=14.4 ms, hitches=0`
- `[WorldPerf] Frame budget: dispatcher=5.8ms streaming=0.0ms streaming_load=0.4ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.1ms spawn=0.0ms total=14.3ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=11.8ms, scheduler.max_urgent_wait_ms=11.8ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -1)@z0: 2526.86 ms`

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
