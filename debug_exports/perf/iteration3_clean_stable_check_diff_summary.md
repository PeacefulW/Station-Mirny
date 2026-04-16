# Perf Baseline Diff

- Baseline: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/iteration3_clean_baseline_fixture.json`
- Candidate: `C:/Users/peaceful/Station Peaceful/Station Peaceful/debug_exports/perf/iteration3_clean_baseline_fixture.json`
- Status: `stable`
- Compared metrics: `35`
- Regression fail threshold: `20.0%`
- Improvement progress threshold: `10.0%`

## Contract violations
- Baseline count: `0`
- Candidate count: `0`
- Candidate fails heuristic: `no`

## Stable sample
- `boot.observations.Startup.loading_screen_visible`: baseline=`0.0000`, candidate=`0.0000`, delta=`0.0%`, rule=`lower_is_better`
- `boot.observations.Startup.start_pressed`: baseline=`0.0000`, candidate=`0.0000`, delta=`0.0%`, rule=`lower_is_better`
- `boot.observations.Startup.start_to_loading_screen_visible_ms`: baseline=`13.5330`, candidate=`13.5330`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.building`: baseline=`0.0090`, candidate=`0.0090`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.dispatcher`: baseline=`0.2300`, candidate=`0.2300`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.other`: baseline=`37113.4830`, candidate=`37113.4830`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.power`: baseline=`0.0080`, candidate=`0.0080`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.shadow`: baseline=`0.0210`, candidate=`0.0210`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.streaming_load`: baseline=`0.0180`, candidate=`0.0180`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.topology`: baseline=`0.0080`, candidate=`0.0080`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.category_peaks.visual`: baseline=`0.0550`, candidate=`0.0550`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.hitch_count`: baseline=`0.0000`, candidate=`0.0000`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.chunk_generation_ms`: baseline=`0.0120`, candidate=`0.0120`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.dispatcher_ms`: baseline=`0.1650`, candidate=`0.1650`, delta=`0.0%`, rule=`lower_is_better`
- `frame_summary.latest_debug_snapshot.fps`: baseline=`141.0000`, candidate=`141.0000`, delta=`0.0%`, rule=`higher_is_better`
- `frame_summary.latest_debug_snapshot.frame_time_ms`: baseline=`11.3319`, candidate=`11.3319`, delta=`0.0%`, rule=`lower_is_better`
