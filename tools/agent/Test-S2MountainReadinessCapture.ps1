[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CaptureDirectory,

    [switch]$SkipRouteValidation
)

$ErrorActionPreference = 'Stop'
$capturePath = [System.IO.Path]::GetFullPath($CaptureDirectory)
$sessionPath = Join-Path -Path $capturePath -ChildPath 'session.json'
if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
    throw "S2 capture is missing session.json: $sessionPath"
}

if (-not $SkipRouteValidation) {
    $s1Analyzer = Join-Path -Path $PSScriptRoot -ChildPath 'Test-S1MountainCapture.ps1'
    & $s1Analyzer -CaptureDirectory $capturePath
    if ($LASTEXITCODE -ne 0) {
        throw "S1-MOUNTAIN-SOUTH-01 route validation failed with exit code $LASTEXITCODE."
    }
}

$session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
$readiness = $session.streaming_readiness
if ($null -eq $readiness -or [int]$readiness.schema_version -ne 1) {
    throw 'Final F4 metadata has no StreamingReadinessDiagnosticSnapshot schema_version=1.'
}

$requiredLayers = @(
    'packet',
    'gameplay',
    'terrain',
    'mountain_mask',
    'terrain_edge_mask',
    'objects',
    'grass',
    'roof_cavity',
    'visibility'
)
$invalidEntries = [System.Collections.Generic.List[string]]::new()
$reasonCounts = @{}
$oldestWait = $null
foreach ($entry in @($readiness.entries)) {
    $coord = "($($entry.chunk_coord.x),$($entry.chunk_coord.y))"
    foreach ($layerName in $requiredLayers) {
        $layer = $entry.layers.$layerName
        if ($null -eq $layer) {
            $invalidEntries.Add("$coord missing layer $layerName")
            continue
        }
        if ([string]$layer.state -eq 'waiting') {
            if ([string]::IsNullOrWhiteSpace([string]$layer.reason)) {
                $invalidEntries.Add("$coord layer $layerName has no concrete reason")
            }
            if ([int64]$layer.elapsed_ms -lt 0) {
                $invalidEntries.Add("$coord layer $layerName has negative elapsed_ms")
            }
        }
    }
    if (-not [bool]$entry.ready) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.blocking_layer) -or
            [string]::IsNullOrWhiteSpace([string]$entry.blocking_reason)) {
            $invalidEntries.Add("$coord missing entry has no unique blocker")
            continue
        }
        if ([string]$entry.blocking_reason -eq 'not_ready') {
            $invalidEntries.Add("$coord uses forbidden generic not_ready")
        }
        $reason = [string]$entry.blocking_reason
        if (-not $reasonCounts.ContainsKey($reason)) {
            $reasonCounts[$reason] = 0
        }
        $reasonCounts[$reason]++
        if ($null -eq $oldestWait -or
            [int64]$entry.blocking_elapsed_ms -gt [int64]$oldestWait.blocking_elapsed_ms) {
            $oldestWait = $entry
        }
    }
}

$manualSidecars = @(
    Get-ChildItem -LiteralPath (Join-Path $capturePath 'events') -Filter '*.json' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json -Depth 100
            }
            catch {
                $invalidEntries.Add("Unparseable event sidecar: $($_.FullName)")
            }
        } |
        Where-Object { [bool]$_.manual }
)
if ($manualSidecars.Count -eq 0) {
    $invalidEntries.Add('Capture contains no F2 manual sidecar.')
}
foreach ($sidecar in $manualSidecars) {
    if ($null -eq $sidecar.streaming_readiness -or
        [int]$sidecar.streaming_readiness.schema_version -ne 1) {
        $invalidEntries.Add('An F2 sidecar has no readiness schema_version=1.')
    }
}

if ($invalidEntries.Count -gt 0) {
    $invalidEntries | ForEach-Object { Write-Error $_ }
    throw "S2 readiness capture validation failed with $($invalidEntries.Count) error(s)."
}

$reasonSummary = @(
    $reasonCounts.GetEnumerator() |
        Sort-Object -Property Name |
        ForEach-Object { "$($_.Name)=$($_.Value)" }
) -join ', '
$oldestSummary = 'none'
if ($null -ne $oldestWait) {
    $oldestSummary = "($($oldestWait.chunk_coord.x),$($oldestWait.chunk_coord.y)) " +
        "$($oldestWait.blocking_layer)/$($oldestWait.blocking_reason) " +
        "$($oldestWait.blocking_elapsed_ms)ms"
}

Write-Output "S2_READINESS_CAPTURE_OK path=$capturePath"
Write-Output "entries=$(@($readiness.entries).Count) missing=$($readiness.missing_chunk_count) manual_sidecars=$($manualSidecars.Count)"
Write-Output "reasons=$reasonSummary"
Write-Output "oldest_wait=$oldestSummary"
