[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CaptureDirectory
)

$ErrorActionPreference = 'Stop'

$resolvedDirectory = (Resolve-Path -LiteralPath $CaptureDirectory).Path
$sessionPath = Join-Path $resolvedDirectory 'session.json'
$tracePath = Join-Path $resolvedDirectory 'trace.csv'
if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
    throw "Missing session.json: $sessionPath"
}
if (-not (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
    throw "Missing trace.csv: $tracePath"
}

$session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json
$rows = @(Import-Csv -LiteralPath $tracePath)
if ($rows.Count -lt 2) {
    throw "Trace must contain at least two samples: $tracePath"
}

$fullPathDistancePx = 0.0
for ($index = 1; $index -lt $rows.Count; $index++) {
    $deltaX = [double]$rows[$index].player_x - [double]$rows[$index - 1].player_x
    $deltaY = [double]$rows[$index].player_y - [double]$rows[$index - 1].player_y
    $fullPathDistancePx += [Math]::Sqrt($deltaX * $deltaX + $deltaY * $deltaY)
}

$zoomValues = @($rows | ForEach-Object { [double]$_.camera_zoom })
$zoomMinimum = ($zoomValues | Measure-Object -Minimum).Minimum
$zoomMaximum = ($zoomValues | Measure-Object -Maximum).Maximum
$durationSeconds = [double]$rows[-1].elapsed_ms / 1000.0
$startChunkX = [int][double]$rows[0].player_chunk_x
$startChunkY = [int][double]$rows[0].player_chunk_y
$lastNonRouteZoomIndex = -1
for ($index = 0; $index -lt $rows.Count; $index++) {
    if ([Math]::Abs([double]$rows[$index].camera_zoom - 0.2) -gt 0.005) {
        $lastNonRouteZoomIndex = $index
    }
}
$routeStartIndex = $lastNonRouteZoomIndex + 1
$hasSettledRouteZoom = $routeStartIndex -lt $rows.Count
$routeDurationSeconds = 0.0
$routePathDistancePx = 0.0
$routeDeltaX = 0.0
$routeDeltaY = 0.0
if ($hasSettledRouteZoom) {
    $routeDurationSeconds = (
        [double]$rows[-1].elapsed_ms - [double]$rows[$routeStartIndex].elapsed_ms
    ) / 1000.0
    for ($index = $routeStartIndex + 1; $index -lt $rows.Count; $index++) {
        $deltaX = [double]$rows[$index].player_x - [double]$rows[$index - 1].player_x
        $deltaY = [double]$rows[$index].player_y - [double]$rows[$index - 1].player_y
        $stepDistance = [Math]::Sqrt($deltaX * $deltaX + $deltaY * $deltaY)
        # Dev probe performs one intentional long teleport to its fixed mountain.
        # It must not make the ordinary movement route pass accidentally.
        if ($stepDistance -le 1024.0) {
            $routePathDistancePx += $stepDistance
        }
    }
    $routeDeltaX = [double]$rows[-1].player_x - [double]$rows[$routeStartIndex].player_x
    $routeDeltaY = [double]$rows[-1].player_y - [double]$rows[$routeStartIndex].player_y
}
$containsMountainCheckpoint = @($rows | Where-Object {
    [Math]::Abs([int][double]$_.player_chunk_x - 131) -le 1 -and
    [Math]::Abs([int][double]$_.player_chunk_y - 29) -le 1
}).Count -gt 0
$eventReasons = @(
    Get-ChildItem -LiteralPath (Join-Path $resolvedDirectory 'events') -Filter '*.json' -File |
        ForEach-Object { (Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json).reason }
)

$checks = [System.Collections.Generic.List[object]]::new()
function Add-RouteCheck {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Actual,
        [string]$Expected
    )
    $checks.Add([pscustomobject]@{
        name = $Name
        passed = $Passed
        actual = $Actual
        expected = $Expected
    })
}

Add-RouteCheck 'startup_and_route_duration' ($durationSeconds -ge 80.0 -and $durationSeconds -le 120.5) `
    ('{0:F3} s' -f $durationSeconds) '80.0..120.5 s'
Add-RouteCheck 'route_zoom_settled' (
    $hasSettledRouteZoom -and $routeDurationSeconds -ge 60.0
) ('zoom range {0:F3}..{1:F3}; settled route {2:F3} s' -f `
    $zoomMinimum, $zoomMaximum, $routeDurationSeconds) 'final zoom 0.200 for >= 60 s'
Add-RouteCheck 'ordinary_path_distance' ($routePathDistancePx -ge 20000.0) `
    ('{0:F3} px' -f $routePathDistancePx) '>= 20000 px after zoom 0.2; dev teleport excluded'
Add-RouteCheck 'southbound_route' (
    $routeDeltaY -ge 20000.0 -and [Math]::Abs($routeDeltaX) -le 4096.0
) ('delta ({0:F3}, {1:F3}) px' -f $routeDeltaX, $routeDeltaY) `
    'south delta Y >= 20000 px; lateral drift <= 4096 px'
Add-RouteCheck 'mountain_checkpoint' $containsMountainCheckpoint `
    "trace start ($startChunkX, $startChunkY)" 'trace contains fixed mountain chunk (131, 29), tolerance 1'
Add-RouteCheck 'manual_bookmark' ($eventReasons -contains 'manual') `
    (($eventReasons | Group-Object | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ', ') `
    'at least one F2/manual event inside F4'
Add-RouteCheck 'renderer' (
    $session.get_current_rendering_driver_name -eq 'd3d12' -and
    $session.get_current_rendering_method -eq 'forward_plus'
) "$($session.get_current_rendering_method)/$($session.get_current_rendering_driver_name)" `
    'forward_plus/d3d12'
Add-RouteCheck 'vsync_60hz' (
    [int]$session.vsync_mode -eq 1 -and [Math]::Abs([double]$session.refresh_rate_hz - 60.0) -le 0.5
) "mode=$($session.vsync_mode), refresh=$($session.refresh_rate_hz) Hz" 'VSync enabled, 60 Hz'

$statistics = $session.statistics
$result = [ordered]@{
    schema = 's1_mountain_capture_analysis_v1'
    capture_directory = $resolvedDirectory
    route_passed = -not ($checks | Where-Object { -not $_.passed })
    checks = $checks
    environment = [ordered]@{
        engine = $session.engine_version.string
        gpu = $session.get_video_adapter_name
        renderer = "$($session.get_current_rendering_method)/$($session.get_current_rendering_driver_name)"
        window = "$($session.window_width)x$($session.window_height)"
        refresh_rate_hz = $session.refresh_rate_hz
        vsync_mode = $session.vsync_mode
        debug_build = $session.debug_build
        editor_run = $session.editor_run
    }
    route = [ordered]@{
        duration_seconds = [Math]::Round($durationSeconds, 3)
        samples = $rows.Count
        full_path_distance_px = [Math]::Round($fullPathDistancePx, 3)
        ordinary_route_distance_px = [Math]::Round($routePathDistancePx, 3)
        route_delta_x = [Math]::Round($routeDeltaX, 3)
        route_delta_y = [Math]::Round($routeDeltaY, 3)
        route_zoom_duration_seconds = [Math]::Round($routeDurationSeconds, 3)
        straight_line_distance_px = $statistics.straight_line_distance_px
        zoom_min = $zoomMinimum
        zoom_max = $zoomMaximum
        start_chunk = @($startChunkX, $startChunkY)
        end_chunk = @([int][double]$rows[-1].player_chunk_x, [int][double]$rows[-1].player_chunk_y)
    }
    performance = [ordered]@{
        average_fps = $statistics.average_fps
        one_percent_low_fps = $statistics.one_percent_low_fps
        average_frame_ms = $statistics.average_frame_ms
        p95_frame_ms = $statistics.p95_frame_ms
        p99_frame_ms = $statistics.p99_frame_ms
        max_frame_ms = $statistics.max_frame_ms
        max_viewport_cpu_ms = $statistics.max_viewport_cpu_ms
        max_viewport_gpu_ms = $statistics.max_viewport_gpu_ms
        max_visibility_wait = $statistics.max_visibility_wait
        max_publish_queue = (($rows | ForEach-Object { [int][double]$_.publish_queue }) | Measure-Object -Maximum).Maximum
        max_requested_packets = (($rows | ForEach-Object { [int][double]$_.requested_packets }) | Measure-Object -Maximum).Maximum
    }
    event_counts = [ordered]@{}
}
foreach ($group in ($eventReasons | Group-Object)) {
    $result.event_counts[$group.Name] = $group.Count
}

$result | ConvertTo-Json -Depth 8
if (-not $result.route_passed) {
    exit 2
}
