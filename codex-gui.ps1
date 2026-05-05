param(
    [Parameter(Position = 0)]
    [string] $Model,

    [string] $Thread,

    [switch] $NoRestart,

    [switch] $KillRunningSessions,

    [switch] $CurrentOnly,

    [switch] $ProjectThreads,

    [switch] $AllProjectThreads,

    [switch] $List,

    [switch] $Login,

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
$ModelCatalogPath = Join-Path $RepoRoot "codex-models.json"
$ModelCatalog = Get-Content -LiteralPath $ModelCatalogPath -Raw | ConvertFrom-Json

$ProviderOptions = @($ModelCatalog.providers)
$ModelOptions = @(
    foreach ($provider in $ProviderOptions) {
        foreach ($modelEntry in @($provider.models)) {
            [pscustomobject]@{
                Model = $modelEntry.slug
                Label = $modelEntry.displayName
                Provider = $provider.name
                ProviderId = $provider.id
                ProviderConfig = $provider
                Alias = (@($modelEntry.aliases) -join ", ")
                Description = $modelEntry.description
            }
        }
    }
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
            "--project-threads" { $script:ProjectThreads = $true; continue }
            "--all-project-threads" { $script:AllProjectThreads = $true; continue }
            "--list" { $script:List = $true; continue }
            "--login" { $script:Login = $true; continue }
            "--help" { $script:Help = $true; continue }
            "/login" { $script:Login = $true; continue }
            "login" { $script:Login = $true; continue }
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
    Write-Host "  codex-gui /login"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -NoRestart            Switch saved state only; do not relaunch Codex Desktop."
    Write-Host "  -KillRunningSessions  Also stop Codex resume/session helper processes."
    Write-Host "  -Thread <id>          Switch a specific Codex Desktop thread row."
    Write-Host "  -CurrentOnly          Switch only the current/latest thread row."
    Write-Host "  -ProjectThreads       Switch visible chats in this project only. This is the default."
    Write-Host "  -AllProjectThreads    Switch every visible GUI chat across projects."
    Write-Host "  -List                 Show model choices."
    Write-Host "  -Login                Interactive provider/API setup and model picker."
    Write-Host "  -VerboseLogs          Show raw repair/switch logs."
    Write-Host "  -NoAnimation          Disable spinner animation."
    Write-Host ""
    Write-Host "Double-dash aliases also work: --login, --verbose, --logs, --no-restart, --thread."
    Write-Host ""
}

function Show-ProviderMenu {
    Write-Header
    Write-Color "  Choose a provider:" Gray
    Write-Host ""
    for ($i = 0; $i -lt $ProviderOptions.Count; $i++) {
        $provider = $ProviderOptions[$i]
        $providerColor = if ($provider.id -eq "xiaomi") { [ConsoleColor]::Magenta } else { [ConsoleColor]::Cyan }
        Write-Color ("  {0}. " -f ($i + 1)) DarkGray -NoNewline
        Write-Color ("{0,-18}" -f $provider.name) $providerColor -NoNewline
        Write-Color (" {0}" -f $provider.description) DarkGray
    }
    Write-Host ""
}

function Show-ModelMenu {
    param([object] $Provider)

    if (-not $Provider) {
        Show-ProviderMenu
        foreach ($provider in $ProviderOptions) {
            Show-ModelMenu -Provider $provider
        }
        return
    }

    Write-Color ("  {0} models:" -f $Provider.name) Gray
    $models = @($Provider.models)
    for ($i = 0; $i -lt $models.Count; $i++) {
        $modelEntry = $models[$i]
        $modelColor = if ($Provider.id -eq "xiaomi") { [ConsoleColor]::Magenta } else { [ConsoleColor]::Cyan }
        $aliases = @($modelEntry.aliases) -join ", "
        Write-Color ("  {0}. " -f ($i + 1)) DarkGray -NoNewline
        Write-Color ("{0,-18}" -f $modelEntry.displayName) $modelColor -NoNewline
        Write-Color (" {0,-17}" -f $modelEntry.slug) DarkGray -NoNewline
        Write-Color (" aliases: {0}" -f $aliases) DarkYellow
    }
    Write-Host ""
}

function Get-ModelOption {
    param([string] $ModelName)

    return $ModelOptions | Where-Object { $_.Model -eq $ModelName } | Select-Object -First 1
}

function Resolve-Provider {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    for ($i = 0; $i -lt $ProviderOptions.Count; $i++) {
        $provider = $ProviderOptions[$i]
        $aliases = @($provider.aliases)
        if ($normalized -eq [string]($i + 1) -or $normalized -eq $provider.id -or $aliases -contains $normalized) {
            return $provider
        }
    }

    throw "Unknown provider choice: $Value"
}

function Resolve-Model {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    foreach ($option in $ModelOptions) {
        $aliases = @($option.ProviderConfig.aliases) + @($option.Alias -split ",\s*")
        if (
            $normalized -eq $option.Model.ToLowerInvariant() -or
            $normalized -eq $option.Label.ToLowerInvariant() -or
            ($aliases | Where-Object { $_ -and $_.ToLowerInvariant() -eq $normalized } | Select-Object -First 1)
        ) {
            return $option.Model
        }
    }

    throw "Unknown model choice: $Value"
}

function Read-ProviderChoice {
    while ($true) {
        Show-ProviderMenu
        Write-Color "Enter number or provider alias: " Yellow -NoNewline
        $choice = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = "1"
        }

        if ($choice.Trim() -match "^(q|quit|exit)$") {
            throw "Cancelled."
        }

        try {
            return Resolve-Provider $choice
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Read-ModelChoice {
    param([object] $Provider)

    if (-not $Provider) {
        $Provider = Read-ProviderChoice
    }

    while ($true) {
        Write-Header
        Show-ModelMenu -Provider $Provider
        Write-Color "Enter number or model alias: " Yellow -NoNewline
        $choice = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = "1"
        }

        if ($choice.Trim() -match "^(q|quit|exit)$") {
            throw "Cancelled."
        }

        $models = @($Provider.models)
        if ($choice.Trim() -match "^\d+$") {
            $index = [int]$choice.Trim() - 1
            if ($index -ge 0 -and $index -lt $models.Count) {
                return $models[$index].slug
            }
        }

        try {
            $resolved = Resolve-Model $choice
            $selected = Get-ModelOption $resolved
            if ($selected.ProviderId -eq $Provider.id) {
                return $resolved
            }

            Write-Warning "$resolved belongs to $($selected.Provider), not $($Provider.name)."
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Test-ProviderModels {
    param([object] $Provider)

    if (-not $Provider.modelsEndpoint) {
        return
    }

    $apiKeyName = $Provider.apiKeyEnv
    $apiKey = [Environment]::GetEnvironmentVariable($apiKeyName, "User")
    if (-not $apiKey) {
        $apiKey = [Environment]::GetEnvironmentVariable($apiKeyName, "Process")
    }
    if (-not $apiKey) {
        Write-Color ("  {0} is not set yet." -f $apiKeyName) Yellow
        return
    }

    try {
        $headers = @{ Authorization = "Bearer $apiKey" }
        $response = Invoke-RestMethod -Uri $Provider.modelsEndpoint -Headers $headers -Method Get -TimeoutSec 20
        $remoteModels = @($response.data | ForEach-Object { $_.id })
        $configuredModels = @($Provider.models | ForEach-Object { $_.slug })
        $activeModels = @($configuredModels | Where-Object { $remoteModels -contains $_ })
        $unsupported = @($remoteModels | Where-Object { $configuredModels -notcontains $_ })

        Write-Color ("  API connected. Codex-ready models: {0}" -f ($activeModels -join ", ")) Green
        if ($unsupported.Count -gt 0) {
            Write-Color ("  Other API models not used for Codex chat: {0}" -f ($unsupported -join ", ")) DarkGray
        }
    } catch {
        Write-Color ("  API model check failed: {0}" -f $_.Exception.Message) Yellow
    }
}

function Invoke-ProviderLogin {
    Write-Header
    Write-Color "  Provider login and model setup" Cyan
    $provider = Read-ProviderChoice

    if ($provider.requiresApiKey) {
        $apiKeyName = $provider.apiKeyEnv
        $existingKey = [Environment]::GetEnvironmentVariable($apiKeyName, "User")
        if ($existingKey) {
            Write-Color ("  Existing {0} found in the user environment." -f $apiKeyName) Green
            Write-Color "  Press Enter to keep it, or paste a replacement key." DarkGray
        } else {
            Write-Color ("  Paste your {0} value for {1}." -f $apiKeyName, $provider.name) Yellow
        }

        Write-Color "API key: " Yellow -NoNewline
        $apiKeyInput = [Console]::ReadLine()
        if (-not [string]::IsNullOrWhiteSpace($apiKeyInput)) {
            [Environment]::SetEnvironmentVariable($apiKeyName, $apiKeyInput.Trim(), "User")
            [Environment]::SetEnvironmentVariable($apiKeyName, $apiKeyInput.Trim(), "Process")
            Write-Color ("  Saved {0} to the user environment for future proxy launches." -f $apiKeyName) Green
        } elseif (-not $existingKey) {
            throw "$apiKeyName is required for $($provider.name)."
        }

        Test-ProviderModels -Provider $provider
    } else {
        Write-Color "  This provider uses your existing Codex Desktop sign-in." Green
    }

    return Read-ModelChoice -Provider $provider
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

$scopeFlags = @($CurrentOnly, $ProjectThreads, $AllProjectThreads) | Where-Object { $_ }
if ($scopeFlags.Count -gt 1) {
    throw "-CurrentOnly, -ProjectThreads, and -AllProjectThreads cannot be combined."
}

if (-not (Test-Path -LiteralPath $HardSwitchScript)) {
    throw "Missing hard switch helper: $HardSwitchScript"
}

$SelectedModel = if ($Login) {
    Invoke-ProviderLogin
} elseif ($Model) {
    Resolve-Model $Model
} else {
    Read-ModelChoice
}
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
if (-not $Thread -and -not $CurrentOnly) {
    if ($AllProjectThreads) {
        $switchParams.AllProjectThreads = $true
    } else {
        $switchParams.ProjectThreads = $true
    }
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
