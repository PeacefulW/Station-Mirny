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

function Deny-ToolUse {
    param([string]$Reason)

    @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $Reason
        }
    } | ConvertTo-Json -Compress -Depth 8
    exit 0
}

function Add-Context {
    param([string]$Context)

    @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            additionalContext = $Context
        }
    } | ConvertTo-Json -Compress -Depth 8
    exit 0
}

$toolName = [string]$payload.tool_name
$toolInput = $payload.tool_input

if ($toolName -eq "Bash") {
    $command = [string]$toolInput.command
    if ([string]::IsNullOrWhiteSpace($command)) {
        exit 0
    }

    $normalized = $command.ToLowerInvariant()

    if ($normalized -match '\bgit\s+reset\s+--hard\b') {
        Deny-ToolUse "Station Mirny guard: git reset --hard is forbidden unless the human explicitly approves destructive cleanup."
    }
    if ($normalized -match '\bgit\s+checkout\s+--\b') {
        Deny-ToolUse "Station Mirny guard: git checkout -- can discard user work. Ask the human before reverting files."
    }
    if ($normalized -match '\bgit\s+clean\b') {
        Deny-ToolUse "Station Mirny guard: git clean can delete untracked work. Ask the human before running it."
    }
    if ($normalized -match '\brm\s+-rf\b' -or $normalized -match '\bremove-item\b.*\b-recurse\b' -or $normalized -match '\bdel\s+/s\b') {
        Deny-ToolUse "Station Mirny guard: recursive deletion is blocked by default. Narrow the target and get explicit approval."
    }

    $hasScopedPath = $normalized -match '(\.claude|docs[/\\]|core[/\\]|data[/\\]|locale[/\\]|scenes[/\\]|tools[/\\]|gdextension[/\\]|agents\.md|claude\.md)'
    $looksLikeBroadScan = (
        ($normalized -match '\brg\s+--files\b') -or
        ($normalized -match '\bgrep\s+(-r|-rn|-R)\b') -or
        ($normalized -match '\bget-childitem\b.*\b-recurse\b') -or
        ($normalized -match '\bfind\s+["'']?\.\b')
    )

    if ($looksLikeBroadScan -and -not $hasScopedPath) {
        Deny-ToolUse "Station Mirny guard: broad repository scans are blocked by default. Read governance docs first, then search only task-scoped paths."
    }
}

if ($toolName -eq "Edit" -or $toolName -eq "MultiEdit" -or $toolName -eq "Write") {
    $filePath = [string]$toolInput.file_path
    if ($filePath -match '\.claude[/\\]agent-memory[/\\]active-epic\.md$') {
        Add-Context "Station Mirny guard: active-epic.md is shared project task state. Only edit it when the current task is explicitly resume-sensitive or multi-iteration."
    }
}

exit 0
