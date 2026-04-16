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

## Resolved violations
- `budget_overrun|visual|mountain_shadow.visual_rebuild`

## Regressions
- `boot.observations.Scheduler.urgent_visual_wait_ms`: baseline=`210.2860`, candidate=`784.5660`, delta=`273.1%`, rule=`lower_is_better`
- `boot.observations.scheduler.max_urgent_wait_ms`: baseline=`210.2860`, candidate=`784.5660`, delta=`273.1%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.chunk_generation_ms`: baseline=`0.0190`, candidate=`0.0390`, delta=`105.3%`, rule=`lower_is_better`
- `boot.observations.Shadow.stale_age_ms`: baseline=`2372.8880`, candidate=`4442.5010`, delta=`87.2%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.dispatcher_ms`: baseline=`2.4960`, candidate=`4.5800`, delta=`83.5%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.world_update_ms`: baseline=`4.8710`, candidate=`8.9190`, delta=`83.1%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.visual_build_ms`: baseline=`2.3410`, candidate=`4.2720`, delta=`82.5%`, rule=`lower_is_better`
- `frame_summary.category_peaks.visual`: baseline=`0.0250`, candidate=`0.0420`, delta=`68.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.fps`: baseline=`138.0000`, candidate=`103.0000`, delta=`-25.4%`, rule=`higher_is_better`

## Improvements
- `frame_summary.hitch_count`: baseline=`3.0000`, candidate=`0.0000`, delta=`-100.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.streaming_load`: baseline=`32.7180`, candidate=`0.0550`, delta=`-99.8%`, rule=`lower_is_better`
- `frame_summary.category_peaks.shadow`: baseline=`101.6970`, candidate=`5.0750`, delta=`-95.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.dispatcher`: baseline=`106.6340`, candidate=`6.5840`, delta=`-93.8%`, rule=`lower_is_better`
- `frame_summary.category_peaks.topology`: baseline=`0.7740`, candidate=`0.0530`, delta=`-93.2%`, rule=`lower_is_better`
- `frame_summary.category_peaks.power`: baseline=`0.0720`, candidate=`0.0320`, delta=`-55.6%`, rule=`lower_is_better`
- `frame_summary.category_peaks.building`: baseline=`0.0260`, candidate=`0.0150`, delta=`-42.3%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.prebaked_visual_ms`: baseline=`14.6149`, candidate=`11.6721`, delta=`-20.1%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.result_build_ms`: baseline=`0.0043`, candidate=`0.0038`, delta=`-11.6%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.result_build_ms`: baseline=`0.0043`, candidate=`0.0038`, delta=`-11.6%`, rule=`lower_is_better`

## Stable sample
- `native_profiling.chunk_generator.phase_peak_ms.feature_and_poi_ms`: baseline=`93.5703`, candidate=`104.3358`, delta=`11.5%`, rule=`lower_is_better`
- `frame_summary.category_peaks.other`: baseline=`10765.0000`, candidate=`9793.0000`, delta=`-9.0%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.terrain_resolve_ms`: baseline=`50.6393`, candidate=`46.2321`, delta=`-8.7%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.total_ms`: baseline=`162.3682`, candidate=`176.0084`, delta=`8.4%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.total_ms`: baseline=`114.4402`, candidate=`106.3884`, delta=`-7.0%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.feature_and_poi_ms`: baseline=`57.3386`, candidate=`53.5842`, delta=`-6.5%`, rule=`lower_is_better`
- `boot.observations.Startup.startup_bubble_ready_to_boot_complete_ms`: baseline=`31001.7050`, candidate=`29087.8280`, delta=`-6.2%`, rule=`lower_is_better`
- `boot.observations.Startup.start_to_loading_screen_visible_ms`: baseline=`12.9740`, candidate=`13.4050`, delta=`3.3%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.flora_ms`: baseline=`0.3460`, candidate=`0.3565`, delta=`3.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.frame_time_ms`: baseline=`6.9444`, candidate=`7.1429`, delta=`2.9%`, rule=`lower_is_better`
- `frame_summary.latest_frame_ms`: baseline=`6.9444`, candidate=`7.1429`, delta=`2.9%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_peak_ms.flora_ms`: baseline=`1.4921`, candidate=`1.4513`, delta=`-2.7%`, rule=`lower_is_better`
- `native_profiling.chunk_generator.phase_avg_ms.prebaked_visual_ms`: baseline=`6.0363`, candidate=`6.1485`, delta=`1.9%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.total_ms`: baseline=`0.7415`, candidate=`0.7293`, delta=`-1.6%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_peak_ms.total_ms`: baseline=`0.7415`, candidate=`0.7293`, delta=`-1.6%`, rule=`lower_is_better`
- `native_profiling.topology_builder.phase_avg_ms.component_scan_ms`: baseline=`0.7367`, candidate=`0.7249`, delta=`-1.6%`, rule=`lower_is_better`
