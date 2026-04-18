$ErrorActionPreference = "Stop"

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    exit 0
}

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    exit 0
}

$transcriptPath = [string]$payload.transcript_path
if ([string]::IsNullOrWhiteSpace($transcriptPath) -or -not (Test-Path -LiteralPath $transcriptPath)) {
    exit 0
}

$lines = Get-Content -LiteralPath $transcriptPath -Tail 250
if ($null -eq $lines -or $lines.Count -eq 0) {
    exit 0
}

$records = @()
foreach ($line in $lines) {
    try {
        $records += ($line | ConvertFrom-Json)
    } catch {
        continue
    }
}

if ($records.Count -eq 0) {
    exit 0
}

$lastUserIndex = -1
for ($i = 0; $i -lt $records.Count; $i++) {
    $role = [string]$records[$i].message.role
    $type = [string]$records[$i].type
    if ($role -eq "user" -or $type -eq "user") {
        $lastUserIndex = $i
    }
}

$turnRecords = if ($lastUserIndex -ge 0 -and $lastUserIndex -lt ($records.Count - 1)) {
    $records[($lastUserIndex + 1)..($records.Count - 1)]
} else {
    $records
}

$turnJson = ($turnRecords | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 32 }) -join "`n"
$usedWriteTool = $turnJson -match '"name":"(Edit|Write|MultiEdit)"' -or $turnJson -match '"tool_name":"(Edit|Write|MultiEdit)"' -or $turnJson -match 'apply_patch'
if (-not $usedWriteTool) {
    exit 0
}

$hasClosure = $turnJson -match 'РћС‚С‡[РµС‘]С‚ Рѕ РІС‹РїРѕР»РЅРµРЅРёРё' -or $turnJson -match 'Closure Report'
$hasCanonicalDocEvidence = $turnJson -match 'Canonical documentation check' -or $turnJson -match 'Проверка канонической документации'

if (-not $hasClosure) {
    @{
        decision = "block"
        reason = "Station Mirny guard: file edits were made in this turn, but the final response does not include the required Closure Report."
    } | ConvertTo-Json -Compress -Depth 4
    exit 0
}

if (-not $hasCanonicalDocEvidence) {
    @{
        decision = "block"
        reason = "Station Mirny guard: Closure Report must include grep evidence for the relevant living canonical docs, even when updates are not required."
    } | ConvertTo-Json -Compress -Depth 4
    exit 0
}

exit 0
