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

$eventName = [string]$payload.hook_event_name
if ([string]::IsNullOrWhiteSpace($eventName)) {
    exit 0
}

if ($eventName -eq "UserPromptSubmit") {
    $prompt = [string]$payload.prompt
    if (-not [string]::IsNullOrWhiteSpace($prompt)) {
        $trimmedPrompt = $prompt.TrimStart()
        if ($trimmedPrompt.StartsWith("/")) {
            exit 0
        }
    }
}

$sessionContext = @(
    "Station Mirny doc-first preflight:",
    "Before acting on repository tasks, read AGENTS.md, then docs/00_governance/WORKFLOW.md, then docs/00_governance/ENGINEERING_STANDARDS.md, then the relevant feature spec and subsystem doc before code.",
    "For world/chunk/mining/topology/reveal/presentation work, read the relevant world/runtime ADRs and the current world spec in docs/02_system_specs/world/ when the task uses it.",
    "For runtime-sensitive or extensible changes, also read docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md plus the relevant subsystem spec or ADR before implementation.",
    "If the request is new feature work or a structural change without an approved spec, stop and create/refine the spec first instead of coding."
) -join "`n"

$turnContext = @(
    "Before executing this task, follow the Station Mirny doc-first order: AGENTS.md -> WORKFLOW.md -> ENGINEERING_STANDARDS.md -> relevant spec/ADR -> relevant subsystem doc. For world/runtime tasks, use the living ADR stack and current world specs instead of deleted legacy docs."
) -join "`n"

$additionalContext = if ($eventName -eq "SessionStart") {
    $sessionContext
} else {
    $turnContext
}

$result = @{
    hookSpecificOutput = @{
        hookEventName = $eventName
        additionalContext = $additionalContext
    }
}

$result | ConvertTo-Json -Compress -Depth 6
