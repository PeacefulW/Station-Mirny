# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_budget_obs_seam_cross_seed12345.log`
- Lines: `697`
- Errors: `1`
- Warnings: `69`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `18139.41 ms`
- `Startup.start_to_loading_screen_visible_ms`: `13.02 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `6571.72 ms`

## Frame summary
- Avg: `9.00 ms`
- P99: `32.20 ms`
- Hitches: `5`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `68`
- `visual / chunk_manager.streaming_redraw`: count=`32`, budget=`4.00 ms`, max_used=`22.41 ms`, max_over=`460.1%`
- `visual / mountain_shadow.visual_rebuild`: count=`19`, budget=`1.00 ms`, max_used=`6.81 ms`, max_over=`580.8%`
- `streaming / chunk_manager.streaming_load`: count=`14`, budget=`3.00 ms`, max_used=`17.30 ms`, max_over=`476.8%`
- `topology / chunk_manager.topology_rebuild`: count=`3`, budget=`2.00 ms`, max_used=`7.67 ms`, max_over=`283.6%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `974.49 ms`
- `WorldPrePass.compute.flow_accumulation`: `817.25 ms`
- `WorldPrePass.compute.flow_directions`: `658.17 ms`
- `WorldPrePass.compute.lake_aware_fill`: `552.33 ms`
- `WorldPrePass.compute.slope_grid`: `396.71 ms`
- `WorldPrePass.compute.spine_seeds`: `383.48 ms`
- `WorldPrePass.compute.erosion_proxy`: `312.97 ms`
- `WorldPrePass.compute.sample_height_grid`: `125.85 ms`
- `WorldPrePass.compute.ridge_graph`: `43.20 ms`
- `WorldPrePass.compute.continentalness`: `37.63 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `23.25 ms`
- `WorldPrePass.compute.floodplain_strength`: `11.39 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `547.14 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `27.50 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `0.82 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.34 budget_ms=4.00 over_budget_pct=8.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.52 budget_ms=4.00 over_budget_pct=38.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.44 budget_ms=4.00 over_budget_pct=111.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.74 budget_ms=1.00 over_budget_pct=373.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.48 budget_ms=3.00 over_budget_pct=249.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.02 budget_ms=2.00 over_budget_pct=100.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.09 budget_ms=4.00 over_budget_pct=2.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.86 budget_ms=4.00 over_budget_pct=46.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.13 budget_ms=1.00 over_budget_pct=13.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.76 budget_ms=3.00 over_budget_pct=258.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.29 budget_ms=1.00 over_budget_pct=128.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.86 budget_ms=1.00 over_budget_pct=285.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.81 budget_ms=1.00 over_budget_pct=580.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.19 budget_ms=4.00 over_budget_pct=129.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=7.67 budget_ms=2.00 over_budget_pct=283.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.81 budget_ms=4.00 over_budget_pct=195.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.51 budget_ms=1.00 over_budget_pct=50.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.42 budget_ms=1.00 over_budget_pct=242.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=22.41 budget_ms=4.00 over_budget_pct=460.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=16.58 budget_ms=4.00 over_budget_pct=314.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=18.58 budget_ms=4.00 over_budget_pct=364.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.47 budget_ms=1.00 over_budget_pct=47.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.85 budget_ms=4.00 over_budget_pct=21.2`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.03 budget_ms=3.00 over_budget_pct=401.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.34 budget_ms=4.00 over_budget_pct=8.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.52 budget_ms=4.00 over_budget_pct=38.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=8.44 budget_ms=4.00 over_budget_pct=111.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=4.74 budget_ms=1.00 over_budget_pct=373.5`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.48 budget_ms=3.00 over_budget_pct=249.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=4.02 budget_ms=2.00 over_budget_pct=100.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.09 budget_ms=4.00 over_budget_pct=2.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=5.86 budget_ms=4.00 over_budget_pct=46.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.13 budget_ms=1.00 over_budget_pct=13.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=10.76 budget_ms=3.00 over_budget_pct=258.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=2.29 budget_ms=1.00 over_budget_pct=128.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.86 budget_ms=1.00 over_budget_pct=285.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=6.81 budget_ms=1.00 over_budget_pct=580.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=9.19 budget_ms=4.00 over_budget_pct=129.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.topology_rebuild category=topology used_ms=7.67 budget_ms=2.00 over_budget_pct=283.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.81 budget_ms=4.00 over_budget_pct=195.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.51 budget_ms=1.00 over_budget_pct=50.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=3.42 budget_ms=1.00 over_budget_pct=242.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=22.41 budget_ms=4.00 over_budget_pct=460.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=16.58 budget_ms=4.00 over_budget_pct=314.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=18.58 budget_ms=4.00 over_budget_pct=364.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=mountain_shadow.visual_rebuild category=visual used_ms=1.47 budget_ms=1.00 over_budget_pct=47.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.85 budget_ms=4.00 over_budget_pct=21.2`

## Recent WorldPerf lines
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 0)@z0: 6213.85 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -1)@z0: 4902.24 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 4902.34 ms`
- `[WorldPerf] FPS: 115.0`
- `[WorldPerf] stream.chunk_border_fix_ms (62, 1)@z0: 6486.97 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 1)@z0: 6487.10 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=24219ms converge=10805ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=49) requests(load=false staged=false generating=false) scheduler(step=15.97ms exhausted=true)`
- `[WorldPerf] stream.chunk_border_fix_ms (2, -2)@z0: 9627.32 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 2282.47 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -2)@z0: 4901.63 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 4507.69 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (1, 2)@z0: 8763.57 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (1, 2)@z0: 8763.70 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (0, 2)@z0: 8568.42 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 8568.50 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (63, 2)@z0: 7774.55 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, 2)@z0: 7774.64 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (2, 2)@z0: 10037.80 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 2)@z0: 9203.29 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, 2)@z0: 7576.07 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, 2)@z0: 7375.95 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=9.0 ms, p99=32.2 ms, hitches=5`
- `[WorldPerf] Frame budget: dispatcher=7.0ms streaming=0.0ms streaming_load=0.0ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=8.3ms spawn=0.0ms total=15.4ms/6.0ms`

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
