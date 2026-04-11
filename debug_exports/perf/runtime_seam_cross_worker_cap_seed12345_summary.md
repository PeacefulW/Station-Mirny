# Perf Log Summary

- Log: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/runtime_seam_cross_worker_cap_seed12345.log`
- Lines: `771`
- Errors: `1`
- Warnings: `67`

## Boot metrics
- `Startup.loading_screen_visible_to_startup_bubble_ready_ms`: `44312.33 ms`
- `Startup.start_to_loading_screen_visible_ms`: `14.34 ms`
- `Startup.startup_bubble_ready_to_boot_complete_ms`: `7147.95 ms`

## Frame summary
- Avg: `13.20 ms`
- P99: `34.50 ms`
- Hitches: `55`

## Runtime validation
- Route preset: `seam_cross`
- Waypoints reached: `6/6`
- Route started: `yes`
- Route completed: `yes`
- Drain completed: `yes`
- Validation failed: `no`
- Catch-up timeout: `no`

## Budget overrun offenders
- Warning count: `41`
- `visual / chunk_manager.streaming_redraw`: count=`31`, budget=`4.00 ms`, max_used=`29.36 ms`, max_over=`633.9%`
- `streaming / chunk_manager.streaming_load`: count=`10`, budget=`3.00 ms`, max_used=`24.42 ms`, max_over=`714.0%`

## WorldPrePass phases
- `WorldPrePass.compute.rain_shadow`: `1116.87 ms`
- `WorldPrePass.compute.flow_accumulation`: `806.99 ms`
- `WorldPrePass.compute.flow_directions`: `681.56 ms`
- `WorldPrePass.compute.lake_aware_fill`: `631.94 ms`
- `WorldPrePass.compute.slope_grid`: `394.46 ms`
- `WorldPrePass.compute.spine_seeds`: `383.73 ms`
- `WorldPrePass.compute.erosion_proxy`: `357.51 ms`
- `WorldPrePass.compute.sample_height_grid`: `189.52 ms`
- `WorldPrePass.compute.ridge_graph`: `87.98 ms`
- `WorldPrePass.compute.continentalness`: `71.94 ms`
- `WorldPrePass.compute.mountain_mass_grid`: `46.39 ms`
- `WorldPrePass.compute.floodplain_strength`: `10.67 ms`

## WorldPrePass subphases
- `WorldPrePass.compute.lake_aware_fill.extract_lake_records`: `619.96 ms`
- `WorldPrePass.compute.continentalness.seed_water_sources`: `59.92 ms`
- `WorldPrePass.compute.lake_aware_fill.priority_flood`: `11.63 ms`
- `WorldPrePass.compute.ridge_strength_grid.native_total`: `1.69 ms`

## Recent errors
- `ERROR: 16 resources still in use at exit (run with --verbose for details).`

## Recent warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.92 budget_ms=4.00 over_budget_pct=223.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=14.05 budget_ms=4.00 over_budget_pct=251.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.59 budget_ms=4.00 over_budget_pct=289.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=26.40 budget_ms=4.00 over_budget_pct=560.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.67 budget_ms=4.00 over_budget_pct=591.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=21.12 budget_ms=3.00 over_budget_pct=604.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=29.36 budget_ms=4.00 over_budget_pct=633.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=24.68 budget_ms=4.00 over_budget_pct=517.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=28.66 budget_ms=4.00 over_budget_pct=616.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=21.68 budget_ms=4.00 over_budget_pct=442.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=23.32 budget_ms=4.00 over_budget_pct=483.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.18 budget_ms=4.00 over_budget_pct=579.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.65 budget_ms=3.00 over_budget_pct=421.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=23.52 budget_ms=4.00 over_budget_pct=488.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.69 budget_ms=4.00 over_budget_pct=592.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=23.44 budget_ms=3.00 over_budget_pct=681.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.35 budget_ms=4.00 over_budget_pct=83.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=21.54 budget_ms=4.00 over_budget_pct=438.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=22.72 budget_ms=4.00 over_budget_pct=468.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=24.41 budget_ms=4.00 over_budget_pct=510.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=16.53 budget_ms=3.00 over_budget_pct=450.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=26.02 budget_ms=4.00 over_budget_pct=550.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.62 budget_ms=4.00 over_budget_pct=15.4`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`

## Recent budget overrun warnings
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=11.55 budget_ms=4.00 over_budget_pct=188.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=12.92 budget_ms=4.00 over_budget_pct=223.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=14.05 budget_ms=4.00 over_budget_pct=251.3`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=15.59 budget_ms=4.00 over_budget_pct=289.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=26.40 budget_ms=4.00 over_budget_pct=560.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.67 budget_ms=4.00 over_budget_pct=591.7`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=21.12 budget_ms=3.00 over_budget_pct=604.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=29.36 budget_ms=4.00 over_budget_pct=633.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=24.68 budget_ms=4.00 over_budget_pct=517.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=28.66 budget_ms=4.00 over_budget_pct=616.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=21.68 budget_ms=4.00 over_budget_pct=442.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=23.32 budget_ms=4.00 over_budget_pct=483.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.18 budget_ms=4.00 over_budget_pct=579.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=15.65 budget_ms=3.00 over_budget_pct=421.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=23.52 budget_ms=4.00 over_budget_pct=488.0`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=27.69 budget_ms=4.00 over_budget_pct=592.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=23.44 budget_ms=3.00 over_budget_pct=681.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=7.35 budget_ms=4.00 over_budget_pct=83.8`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=21.54 budget_ms=4.00 over_budget_pct=438.6`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=22.72 budget_ms=4.00 over_budget_pct=468.1`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=24.41 budget_ms=4.00 over_budget_pct=510.2`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_load category=streaming used_ms=16.53 budget_ms=3.00 over_budget_pct=450.9`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=26.02 budget_ms=4.00 over_budget_pct=550.4`
- `WARNING: [WorldPerf] WARNING: FrameBudget overrun job_id=chunk_manager.streaming_redraw category=visual used_ms=4.62 budget_ms=4.00 over_budget_pct=15.4`

## Recent WorldPerf lines
- `[WorldPerf] PlayerChunk coord=(1, -2) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=18509ms converge=18509ms) queues(fast=0 urgent=0 near=1 full_near=0 full_far=0) requests(load=false staged=false generating=false) scheduler(step=0.25ms exhausted=false)`
- `[WorldPerf] PlayerChunk coord=(0, -1) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=47708ms converge=19284ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=1) requests(load=false staged=false generating=false) scheduler(step=7.10ms exhausted=false)`
- `[WorldPerf] FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: 24.41 ms`
- `[WorldPerf] PlayerChunk coord=(0, 0) z=0 trigger=scheduler loaded=true visible=true state=full_ready phase=done first_pass=true full_ready=true issues=healthy ages(first=-ms full=-ms border=-ms apply=48432ms converge=48432ms) queues(fast=0 urgent=0 near=0 full_near=0 full_far=1) requests(load=false staged=false generating=false) scheduler(step=18.62ms exhausted=false)`
- `[WorldPerf] stream.chunk_border_fix_ms (2, 1)@z0: 9943.10 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 1)@z0: 9943.28 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (0, 2)@z0: 7987.60 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (0, 2)@z0: 7987.74 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (2, 0)@z0: 9972.75 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, 0)@z0: 9972.86 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -2)@z0: 4273.65 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -2)@z0: 4273.75 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (62, -1)@z0: 4265.34 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (62, -1)@z0: 4265.51 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (2, -2)@z0: 2406.36 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (2, -2)@z0: 2406.50 ms`
- `[WorldPerf] stream.chunk_border_fix_ms (63, -2)@z0: 1076.42 ms`
- `[WorldPerf] stream.chunk_full_redraw_ms (63, -2)@z0: 1076.53 ms`
- `[WorldPerf] === Frame Summary (300 frames) ===`
- `[WorldPerf] Frame time: avg=13.2 ms, p99=34.5 ms, hitches=55`
- `[WorldPerf] Frame budget: dispatcher=10.1ms streaming=0.0ms streaming_load=2.3ms streaming_redraw=0.0ms topology=0.0ms building=0.0ms power=0.0ms visual=0.0ms shadow=7.6ms spawn=0.0ms total=20.1ms/6.0ms`
- `[WorldPerf] Observability: Scheduler.urgent_visual_wait_ms=2.8ms, scheduler.max_urgent_wait_ms=2.8ms`
- `[WorldPerf] stream.chunk_first_pass_ms (3, -2)@z0: 3348.81 ms`
- `[WorldPerf] stream.chunk_first_pass_ms (63, -3)@z0: 2019.63 ms`

## Recent CodexValidation lines
- `[CodexValidation] runtime validation driver enabled; route_preset=seam_cross`
- `[CodexValidation] route prepared: preset=seam_cross waypoints=6 start=(0.0, 0.0) chunk_pixels=4096.0`
- `[CodexValidation] room validation prepared at (4, 4)`
- `[CodexValidation] power validation prepared at (8, 4)`
- `[CodexValidation] mining validation skipped; no suitable mountain edge found in loaded chunks`
- `[CodexValidation] boot complete; route prepared`
- `[CodexValidation] built validation room`
- `[CodexValidation] removed validation room wall (5, 4)`
- `[CodexValidation] re-placed validation room wall (5, 4)`
- `[CodexValidation] destroyed validation room wall (4, 5)`
- `[CodexValidation] room validation complete`
- `[CodexValidation] placed validation battery (8, 4)`
- `[CodexValidation] removed validation battery (8, 4)`
- `[CodexValidation] power validation complete`
- `[CodexValidation] route start: preset=seam_cross waypoints=6`
- `[CodexValidation] reached waypoint 1/6 at (8192.0, 0.0)`
- `[CodexValidation] reached waypoint 2/6 at (8192.0, 8192.0)`
- `[CodexValidation] reached waypoint 3/6 at (253952.0, 8192.0)`
- `[CodexValidation] reached waypoint 4/6 at (253952.0, -8192.0)`
- `[CodexValidation] reached waypoint 5/6 at (8192.0, -8192.0)`
- `[CodexValidation] reached waypoint 6/6 at (0.0, 0.0)`
- `[CodexValidation] route complete: preset=seam_cross reached=6/6 draining_background_work=true`
- `[CodexValidation] route drain complete; preset=seam_cross reached=6/6 redraw_backlog=false`
