param(
    [Parameter(Position = 0)]
    [string] $Model,

    [string] $Thread,

    [switch] $NoRestart,

    [switch] $KillRunningSessions,

    [switch] $List,

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
    Write-Host "  -List                 Show model choices."
    Write-Host ""
}

function Show-ModelMenu {
    Write-Host ""
    Write-Host "Choose the Codex GUI model:"
    foreach ($option in $ModelOptions) {
        Write-Host ("  {0}. {1,-17} {2,-13} aliases: {3}" -f $option.Key, $option.Label, $option.Provider, $option.Alias)
    }
    Write-Host ""
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
        $choice = Read-Host "Enter number or model alias"
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

Write-Host ""
Write-Host "selected_model=$SelectedModel"

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

& $HardSwitchScript @switchParams

if ($NoRestart) {
    Write-Host "codex_gui_restart=skipped"
} else {
    Write-Host "codex_gui_launched=true"
}
