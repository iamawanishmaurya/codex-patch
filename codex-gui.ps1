param(
    [Parameter(Position = 0)]
    [string] $Model,

    [string] $Thread,

    [switch] $NoRestart,

    [switch] $KillRunningSessions,

    [switch] $CurrentOnly,

    [switch] $List,

    [Alias("ShowLogs", "Logs")]
    [switch] $VerboseLogs,

    [Alias("Plain")]
    [switch] $NoAnimation,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $ExtraArgs,

    [Alias("h", "?")]
    [switch] $Help
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HardSwitchScript = Join-Path $RepoRoot "hard-switch-codex-gui-model.ps1"

$ModelOptions = @(
    [pscustomobject]@{ Key = "1"; Model = "gpt-5.5"; Label = "GPT-5.5"; Provider = "OpenAI"; Alias = "5.5, gpt55" },
    [pscustomobject]@{ Key = "2"; Model = "gpt-5.4"; Label = "GPT-5.4"; Provider = "OpenAI"; Alias = "5.4, gpt54" },
    [pscustomobject]@{ Key = "3"; Model = "gpt-5.4-mini"; Label = "GPT-5.4 Mini"; Provider = "OpenAI"; Alias = "mini" },
    [pscustomobject]@{ Key = "4"; Model = "gpt-5.3-codex"; Label = "GPT-5.3 Codex"; Provider = "OpenAI"; Alias = "5.3, codex53" },
    [pscustomobject]@{ Key = "5"; Model = "gpt-5.2"; Label = "GPT-5.2"; Provider = "OpenAI"; Alias = "5.2, gpt52" },
    [pscustomobject]@{ Key = "6"; Model = "mimo-v2.5-pro"; Label = "MiMo-V2.5-Pro"; Provider = "Xiaomi proxy"; Alias = "mimo, mino, xiaomi" }
)

function Import-LongArguments {
    $rawArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $rawArgs += $Model
    }
    if ($ExtraArgs) {
        $rawArgs += $ExtraArgs
    }

    if ($rawArgs.Count -eq 0) {
        return
    }

    $modelArgs = @()
    for ($i = 0; $i -lt $rawArgs.Count; $i++) {
        $arg = [string] $rawArgs[$i]
        switch ($arg.ToLowerInvariant()) {
            "--verbose" { $script:VerboseLogs = $true; continue }
            "--logs" { $script:VerboseLogs = $true; continue }
            "--show-logs" { $script:VerboseLogs = $true; continue }
            "--no-animation" { $script:NoAnimation = $true; continue }
            "--plain" { $script:NoAnimation = $true; continue }
            "--no-restart" { $script:NoRestart = $true; continue }
            "--kill-running-sessions" { $script:KillRunningSessions = $true; continue }
            "--current-only" { $script:CurrentOnly = $true; continue }
            "--list" { $script:List = $true; continue }
            "--help" { $script:Help = $true; continue }
            "--thread" {
                if ($i + 1 -ge $rawArgs.Count) {
                    throw "--thread requires a thread id."
                }
                $script:Thread = [string] $rawArgs[$i + 1]
                $i += 1
                continue
            }
            "--model" {
                if ($i + 1 -ge $rawArgs.Count) {
                    throw "--model requires a model or alias."
                }
                $modelArgs += [string] $rawArgs[$i + 1]
                $i += 1
                continue
            }
            default {
                $modelArgs += $arg
            }
        }
    }

    if ($modelArgs.Count -gt 1) {
        throw "Unexpected extra argument: $($modelArgs[1])"
    }

    if ($modelArgs.Count -eq 1) {
        $script:Model = $modelArgs[0]
    } else {
        $script:Model = $null
    }
}

function Write-Color {
    param(
        [string] $Text,
        [ConsoleColor] $Color = [ConsoleColor]::Gray,
        [switch] $NoNewline
    )

    if ($NoNewline) {
        Write-Host -NoNewline $Text -ForegroundColor $Color
        return
    }

    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    Write-Host ""
    Write-Color "  Codex GUI Model Launcher" Cyan
    Write-Color "  ------------------------" DarkCyan
}

function Show-Usage {
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  codex-gui"
    Write-Host "  codex-gui <model-or-alias>"
    Write-Host "  codex-gui gpt-5.5"
    Write-Host "  codex-gui mimo"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -NoRestart            Switch saved state only; do not relaunch Codex Desktop."
    Write-Host "  -KillRunningSessions  Also stop Codex resume/session helper processes."
    Write-Host "  -Thread <id>          Switch a specific Codex Desktop thread row."
    Write-Host "  -CurrentOnly          Switch only the current/latest thread, not all project chats."
    Write-Host "  -List                 Show model choices."
    Write-Host "  -VerboseLogs          Show raw repair/switch logs."
    Write-Host "  -NoAnimation          Disable spinner animation."
    Write-Host ""
    Write-Host "Double-dash aliases also work: --verbose, --logs, --no-restart, --thread."
    Write-Host ""
}

function Show-ModelMenu {
    Write-Header
    Write-Color "  Choose the model to launch:" Gray
    Write-Host ""
    foreach ($option in $ModelOptions) {
        $modelColor = if ($option.Model -eq "mimo-v2.5-pro") { [ConsoleColor]::Magenta } else { [ConsoleColor]::Cyan }
        Write-Color ("  {0}. " -f $option.Key) DarkGray -NoNewline
        Write-Color ("{0,-17}" -f $option.Label) $modelColor -NoNewline
        Write-Color (" {0,-13}" -f $option.Provider) DarkGray -NoNewline
        Write-Color (" aliases: {0}" -f $option.Alias) DarkYellow
    }
    Write-Host ""
}

function Get-ModelOption {
    param([string] $ModelName)

    return $ModelOptions | Where-Object { $_.Model -eq $ModelName } | Select-Object -First 1
}

function Resolve-Model {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    switch -Regex ($normalized) {
        "^(1|gpt-?5\.?5|gpt55|5\.5|55|openai|codex)$" { return "gpt-5.5" }
        "^(2|gpt-?5\.?4|gpt54|5\.4|54)$" { return "gpt-5.4" }
        "^(3|gpt-?5\.?4-mini|gpt54-mini|gpt-?mini|mini|5\.4-mini)$" { return "gpt-5.4-mini" }
        "^(4|gpt-?5\.?3-codex|gpt53|codex53|5\.3|53)$" { return "gpt-5.3-codex" }
        "^(5|gpt-?5\.?2|gpt52|5\.2|52)$" { return "gpt-5.2" }
        "^(6|mimo|mino|xiaomi|mimo-v2\.5-pro|mimo-v2-pro)$" { return "mimo-v2.5-pro" }
        default { throw "Unknown model choice: $Value" }
    }
}

function Read-ModelChoice {
    while ($true) {
        Show-ModelMenu
        Write-Color "Enter number or model alias: " Yellow -NoNewline
        $choice = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = "1"
        }

        if ($choice.Trim() -match "^(q|quit|exit)$") {
            throw "Cancelled."
        }

        try {
            return Resolve-Model $choice
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Invoke-HardSwitchWithSpinner {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $SwitchParams,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($VerboseLogs -or $NoAnimation) {
        & $HardSwitchScript @SwitchParams
        return
    }

    $job = Start-Job -ScriptBlock {
        param(
            [string] $ScriptPath,
            [string] $WorkingDirectory,
            [hashtable] $Parameters
        )

        Set-Location -LiteralPath $WorkingDirectory
        & $ScriptPath @Parameters
    } -ArgumentList $HardSwitchScript, $RepoRoot, $SwitchParams

    $frames = @("|", "/", "-", "\")
    $colors = @([ConsoleColor]::Cyan, [ConsoleColor]::Magenta, [ConsoleColor]::Yellow, [ConsoleColor]::Green)
    $index = 0

    try {
        while ($job.State -eq "Running") {
            $frame = $frames[$index % $frames.Count]
            $color = $colors[$index % $colors.Count]
            Write-Host -NoNewline ("`r  {0} {1}" -f $frame, $Message) -ForegroundColor $color
            Start-Sleep -Milliseconds 120
            $index += 1
        }

        $logs = Receive-Job -Job $job 2>&1 3>&1 4>&1 5>&1 6>&1 | Out-String
        Write-Host -NoNewline ("`r" + (" " * 100) + "`r")

        if ($job.State -ne "Completed") {
            $details = $logs.Trim()
            if ([string]::IsNullOrWhiteSpace($details)) {
                $details = $job.JobStateInfo.Reason
            }
            throw "Codex GUI switch failed.`n$details"
        }
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

Import-LongArguments

if ($Help) {
    Show-Usage
    Show-ModelMenu
    exit 0
}

if ($List) {
    Show-ModelMenu
    exit 0
}

if (-not (Test-Path -LiteralPath $HardSwitchScript)) {
    throw "Missing hard switch helper: $HardSwitchScript"
}

$SelectedModel = if ($Model) { Resolve-Model $Model } else { Read-ModelChoice }
$SelectedOption = Get-ModelOption $SelectedModel

Write-Host ""
Write-Header
Write-Color ("  Selected: {0}" -f $SelectedOption.Label) Green
Write-Color ("  Provider: {0}" -f $SelectedOption.Provider) DarkGray
if ($VerboseLogs) {
    Write-Color "  Logs: verbose raw output enabled" Yellow
} else {
    Write-Color "  Logs: quiet mode (use -VerboseLogs or --verbose for raw output)" DarkGray
}
Write-Host ""

$switchParams = @{ Model = $SelectedModel }
if ($Thread) {
    $switchParams.Thread = $Thread
}
if ($NoRestart) {
    $switchParams.NoRestart = $true
}
if ($KillRunningSessions) {
    $switchParams.KillRunningSessions = $true
}
if (-not $CurrentOnly -and -not $Thread) {
    $switchParams.AllProjectThreads = $true
}
if ($VerboseLogs) {
    $switchParams.VerboseLogs = $true
}

$actionText = if ($NoRestart) {
    "Patching saved Codex state..."
} else {
    "Patching state and relaunching Codex Desktop..."
}

Invoke-HardSwitchWithSpinner -SwitchParams $switchParams -Message $actionText

if ($NoRestart) {
    Write-Color "  OK Saved model state updated. Restart skipped." Green
} else {
    Write-Color "  OK Codex Desktop is opening with $($SelectedOption.Label)." Green
}
