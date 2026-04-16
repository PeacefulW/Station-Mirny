# Perf Baseline Diff

- Baseline: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/baseline_seed12345.json`
- Candidate: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/investigation_boot_seed12345.json`
- Status: `fail`
- Compared metrics: `35`
- Regression fail threshold: `20.0%`
- Improvement progress threshold: `10.0%`

## Contract violations
- Baseline count: `1`
- Candidate count: `1`
- Candidate fails heuristic: `yes`

## Regressions
- `frame_summary.category_peaks.streaming_load`: baseline=`0.0180`, candidate=`0.0480`, delta=`166.7%`, rule=`lower_is_better`
- `frame_summary.hitch_count`: baseline=`0.0000`, candidate=`1.0000`, delta=`100.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.visual_build_ms`: baseline=`0.0160`, candidate=`0.0230`, delta=`43.7%`, rule=`lower_is_better`
- `frame_summary.category_peaks.power`: baseline=`0.0080`, candidate=`0.0110`, delta=`37.5%`, rule=`lower_is_better`
- `frame_summary.category_peaks.topology`: baseline=`0.0080`, candidate=`0.0110`, delta=`37.5%`, rule=`lower_is_better`
- `frame_summary.category_peaks.dispatcher`: baseline=`0.2300`, candidate=`0.3080`, delta=`33.9%`, rule=`lower_is_better`
- `frame_summary.category_peaks.visual`: baseline=`0.0550`, candidate=`0.0710`, delta=`29.1%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.result_build_ms`: baseline=`0.0040`, candidate=`0.0051`, delta=`27.5%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.result_build_ms`: baseline=`0.0040`, candidate=`0.0051`, delta=`27.5%`, rule=`lower_is_better`
- `frame_summary.category_peaks.building`: baseline=`0.0090`, candidate=`0.0110`, delta=`22.2%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.dispatcher_ms`: baseline=`0.1650`, candidate=`0.2000`, delta=`21.2%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.world_update_ms`: baseline=`0.2000`, candidate=`0.2420`, delta=`21.0%`, rule=`lower_is_better`

## Improvements
- `frame_summary.latest_debug_snapshot.frame_time_ms`: baseline=`11.3319`, candidate=`6.9444`, delta=`-38.7%`, rule=`lower_is_better`
- `frame_summary.latest_frame_ms`: baseline=`11.3319`, candidate=`6.9444`, delta=`-38.7%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.flora_ms`: baseline=`1.4258`, candidate=`1.2137`, delta=`-14.9%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.flora_ms`: baseline=`0.6595`, candidate=`0.5844`, delta=`-11.4%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.terrain_resolve_ms`: baseline=`58.6508`, candidate=`52.5801`, delta=`-10.4%`, rule=`lower_is_better`

## Stable sample
- `frame_summary.category_peaks.other`: baseline=`37113.4830`, candidate=`43220.3260`, delta=`16.5%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.terrain_resolve_ms`: baseline=`37.3847`, candidate=`34.4960`, delta=`-7.7%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.total_ms`: baseline=`134.3390`, candidate=`125.7598`, delta=`-6.4%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.total_ms`: baseline=`0.1763`, candidate=`0.1869`, delta=`6.0%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.total_ms`: baseline=`0.1763`, candidate=`0.1869`, delta=`6.0%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.component_scan_ms`: baseline=`0.1717`, candidate=`0.1813`, delta=`5.6%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.component_scan_ms`: baseline=`0.1717`, candidate=`0.1813`, delta=`5.6%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.total_ms`: baseline=`94.2895`, candidate=`89.6078`, delta=`-5.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.shadow`: baseline=`0.0210`, candidate=`0.0220`, delta=`4.8%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.prebaked_visual_ms`: baseline=`6.4379`, candidate=`6.1925`, delta=`-3.8%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.prebaked_visual_ms`: baseline=`8.6447`, candidate=`8.3700`, delta=`-3.2%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.feature_and_poi_ms`: baseline=`49.7344`, candidate=`48.2612`, delta=`-3.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.fps`: baseline=`141.0000`, candidate=`137.0000`, delta=`-2.8%`, rule=`higher_is_better`
- `boot.observations.Startup.start_to_loading_screen_visible_ms`: baseline=`13.5330`, candidate=`13.8230`, delta=`2.1%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.feature_and_poi_ms`: baseline=`81.6158`, candidate=`80.9145`, delta=`-0.9%`, rule=`lower_is_better`
- `boot.observations.Startup.loading_screen_visible`: baseline=`0.0000`, candidate=`0.0000`, delta=`0.0%`, rule=`lower_is_better`
