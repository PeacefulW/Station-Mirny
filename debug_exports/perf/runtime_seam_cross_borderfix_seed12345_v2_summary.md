# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_seam_cross_borderfix_seed12345_v2.log`
- Lines: `689`
- Errors: `1`
- Warnings: `56`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `28044.12 ms`
- `Startup.start_to_loading_screen_visible_ms`: `14.14 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `5879.89 ms`

## Frame summary
- Avg: `7.10 ms`
- P99: `13.30 ms`
- Hitches: `1`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `55`
- `visual / chunk_manager.streaming_redraw`: count=`20`, budget=`4.00 ms`, max_used=`18.68 ms`, max_over=`367.0%`
- `visual / mountain_shadow.visual_rebuild`: count=`18`, budget=`1.00 ms`, max_used=`5.66 ms`, max_over=`466.2%`
- `streaming / chunk_manager.streaming_load`: count=`13`, budget=`3.00 ms`, max_used=`15.82 ms`, max_over=`427.2%`
- `topology / chunk_manager.topology_rebuild`: count=`4`, budget=`2.00 ms`, max_used=`6.42 ms`, max_over=`221.2%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `995.94 ms`
- `WorldPrePass.compute.flow_accumulation`: `854.54 ms`
- `WorldPrePass.compute.flow_directions`: `651.93 ms`
- `WorldPrePass.compute.lake_aware_fill`: `553.31 ms`
- `WorldPrePass.compute.spine_seeds`: `411.90 ms`
- `WorldPrePass.compute.slope_grid`: `397.47 ms`
- `WorldPrePass.compute.erosion_proxy`: `307.25 ms`
- `WorldPrePass.compute.sample_height_grid`: `145.05 ms`
- `WorldPrePass.compute.ridge_graph`: `44.77 ms`
- `WorldPrePass.compute.continentalness`: `37.25 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `25.34 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.35 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `547.51 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.11 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.81 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.17 budget_ms=3.00 over_budget_pct=372.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.41 budget_ms=4.00 over_budget_pct=85.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.54 budget_ms=1.00 over_budget_pct=53.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.24 budget_ms=1.00 over_budget_pct=223.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.29 budget_ms=3.00 over_budget_pct=409.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.69 budget_ms=2.00 over_budget_pct=84.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.32 budget_ms=4.00 over_budget_pct=8.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.53 budget_ms=1.00 over_budget_pct=53.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=8.64 budget_ms=3.00 over_budget_pct=187.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.41 budget_ms=1.00 over_budget_pct=41.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.28 budget_ms=2.00 over_budget_pct=114.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.77 budget_ms=1.00 over_budget_pct=176.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.05 budget_ms=1.00 over_budget_pct=304.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.69 budget_ms=4.00 over_budget_pct=17.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=14.38 budget_ms=4.00 over_budget_pct=259.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.66 budget_ms=1.00 over_budget_pct=466.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=18.68 budget_ms=4.00 over_budget_pct=367.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.97 budget_ms=3.00 over_budget_pct=299.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=6.42 budget_ms=2.00 over_budget_pct=221.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.48 budget_ms=1.00 over_budget_pct=147.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.49 budget_ms=4.00 over_budget_pct=37.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.70 budget_ms=4.00 over_budget_pct=167.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.55 budget_ms=4.00 over_budget_pct=13.7`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.99 budget_ms=3.00 over_budget_pct=299.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=14.17 budget_ms=3.00 over_budget_pct=372.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.41 budget_ms=4.00 over_budget_pct=85.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.54 budget_ms=1.00 over_budget_pct=53.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.24 budget_ms=1.00 over_budget_pct=223.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.29 budget_ms=3.00 over_budget_pct=409.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=3.69 budget_ms=2.00 over_budget_pct=84.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.32 budget_ms=4.00 over_budget_pct=8.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.53 budget_ms=1.00 over_budget_pct=53.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=8.64 budget_ms=3.00 over_budget_pct=187.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.41 budget_ms=1.00 over_budget_pct=41.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.28 budget_ms=2.00 over_budget_pct=114.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.77 budget_ms=1.00 over_budget_pct=176.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.05 budget_ms=1.00 over_budget_pct=304.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.69 budget_ms=4.00 over_budget_pct=17.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=14.38 budget_ms=4.00 over_budget_pct=259.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=5.66 budget_ms=1.00 over_budget_pct=466.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=18.68 budget_ms=4.00 over_budget_pct=367.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=11.97 budget_ms=3.00 over_budget_pct=299.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=6.42 budget_ms=2.00 over_budget_pct=221.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.48 budget_ms=1.00 over_budget_pct=147.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.49 budget_ms=4.00 over_budget_pct=37.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=10.70 budget_ms=4.00 over_budget_pct=167.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.55 budget_ms=4.00 over_budget_pct=13.7`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 1729.72 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -2)@z0: 4472.78 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 4028.75 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (62, -3)@z0: 4318.62 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=33081ms converge=10670ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=18) requests(load=false staged=false generating=false) scheduler(step=0.21ms exhausted=false)`
- `[WorldPerf] stream.chunk_border_fix_ms (62, 2)@z0: 7023.37 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 6680.84 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (63, -3)@z0: 5075.79 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -3)@z0: 4707.84 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (1, -3)@z0: 3667.22 ms`
- `[WorldPerf] FPS: 141.0`
- `[WorldPerf] stream.chunk_first_pass_ms (2, -3)@z0: 3357.93 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (63, -4)@z0: 4733.31 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (0, -4)@z0: 4729.90 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (1, -4)@z0: 4161.84 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (62, -4)@z0: 5415.86 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (3, -2)@z0: 3552.71 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (3, -1)@z0: 3596.80 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (2, -4)@z0: 3778.89 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=7.1 ms, p99=13.3 ms, hitches=1`
- `[WorldPerf] Frame budget: dispatcher=4.2ms streaming=0.0ms streaming_load=0.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=4.1ms spawn=0.0ms total=8.4ms/6.0ms`
- `[WorldPerf] stream.chunk_first_pass_ms (3, 0)@z0: 3650.27 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (3, -3)@z0: 3237.83 ms`

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
- `[CodexValidation] route start: preset=seam_cross waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (8192.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (8192.0, 8192.0)`
- `[CodexValidation] reached waypoint 3/6 at (253952.0, 8192.0)`
- `[CodexValidation] reached waypoint 4/6 at (253952.0, -8192.0)`
- `[CodexValidation] reached waypoint 5/6 at (8192.0, -8192.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=seam_cross reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=seam_cross reached=6/6 redraw_backlog=false`
