# Perf Baseline Diff

- Baseline: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/player_hot_publication_before_seed12345.json`
- Candidate: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/player_hot_publication_candidate_seed12345.json`
- Status: `fail`
- Compared metrics: `42`
- Regression fail threshold: `20.0%`
- Improvement progress threshold: `10.0%`

## Contract violations
- Baseline count: `128`
- Candidate count: `128`
- Candidate fails heuristic: `yes`

## Regressions
- `frame_summary.latest_debug_snapshot.visual_build_ms`: baseline=`2.3410`, candidate=`3.3940`, delta=`45.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.world_update_ms`: baseline=`4.8710`, candidate=`6.9980`, delta=`43.7%`, rule=`lower_is_better`
- `frame_summary.category_peaks.shadow`: baseline=`101.6970`, candidate=`145.9380`, delta=`43.5%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.dispatcher_ms`: baseline=`2.4960`, candidate=`3.5700`, delta=`43.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.dispatcher`: baseline=`106.6340`, candidate=`146.3770`, delta=`37.3%`, rule=`lower_is_better`

## Improvements
- `frame_summary.category_peaks.streaming_load`: baseline=`32.7180`, candidate=`0.0360`, delta=`-99.9%`, rule=`lower_is_better`
- `frame_summary.category_peaks.topology`: baseline=`0.7740`, candidate=`0.0230`, delta=`-97.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.power`: baseline=`0.0720`, candidate=`0.0220`, delta=`-69.4%`, rule=`lower_is_better`
- `frame_summary.hitch_count`: baseline=`3.0000`, candidate=`1.0000`, delta=`-66.7%`, rule=`lower_is_better`
- `frame_summary.category_peaks.building`: baseline=`0.0260`, candidate=`0.0170`, delta=`-34.6%`, rule=`lower_is_better`
- `boot.observations.Startup.startup_bubble_ready_to_boot_complete_ms`: baseline=`31001.7050`, candidate=`24544.1810`, delta=`-20.8%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.prebaked_visual_ms`: baseline=`14.6149`, candidate=`12.8034`, delta=`-12.4%`, rule=`lower_is_better`

## Stable sample
- `frame_summary.category_peaks.visual`: baseline=`0.0250`, candidate=`0.0280`, delta=`12.0%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.result_build_ms`: baseline=`0.0043`, candidate=`0.0047`, delta=`9.3%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.result_build_ms`: baseline=`0.0043`, candidate=`0.0047`, delta=`9.3%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.fps`: baseline=`138.0000`, candidate=`126.0000`, delta=`-8.7%`, rule=`higher_is_better`
- `native_profiling.topology_builder.phase_avg_ms.component_scan_ms`: baseline=`0.7367`, candidate=`0.7980`, delta=`8.3%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.component_scan_ms`: baseline=`0.7367`, candidate=`0.7980`, delta=`8.3%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.total_ms`: baseline=`0.7415`, candidate=`0.8031`, delta=`8.3%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.total_ms`: baseline=`0.7415`, candidate=`0.8031`, delta=`8.3%`, rule=`lower_is_better`
- `frame_summary.category_peaks.other`: baseline=`10765.0000`, candidate=`9928.9370`, delta=`-7.8%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.feature_and_poi_ms`: baseline=`93.5703`, candidate=`100.5216`, delta=`7.4%`, rule=`lower_is_better`
- `boot.observations.Startup.loading_screen_visible_to_startup_bubble_ready_ms`: baseline=`47496.0680`, candidate=`50838.6660`, delta=`7.0%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.terrain_resolve_ms`: baseline=`80.2877`, candidate=`75.3772`, delta=`-6.1%`, rule=`lower_is_better`
- `boot.observations.Shadow.stale_age_ms`: baseline=`2372.8880`, candidate=`2243.2130`, delta=`-5.5%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.chunk_generation_ms`: baseline=`0.0190`, candidate=`0.0200`, delta=`5.3%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.terrain_resolve_ms`: baseline=`50.6393`, candidate=`48.3740`, delta=`-4.5%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.flora_ms`: baseline=`0.3460`, candidate=`0.3593`, delta=`3.9%`, rule=`lower_is_better`
