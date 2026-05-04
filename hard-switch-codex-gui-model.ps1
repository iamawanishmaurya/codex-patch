param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2", "mimo-v2.5-pro")]
    [string] $Model,

    [string] $Thread,

    [switch] $NoRestart,

    [switch] $KillRunningSessions
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-CodexAppPath {
    $runningApp = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "Codex.exe" -and $_.CommandLine -notmatch "--type="
    } | Select-Object -First 1

    if ($runningApp -and $runningApp.ExecutablePath) {
        return $runningApp.ExecutablePath
    }

    $installedApp = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "OpenAI.Codex_*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName "app\Codex.exe" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

    if (-not $installedApp) {
        throw "Could not locate Codex.exe under C:\Program Files\WindowsApps."
    }

    return $installedApp
}

Push-Location $RepoRoot
try {
    node repair-codex-mimo.cjs

    if ($Model.StartsWith("gpt-")) {
        node update-gpt-providers.cjs
    }

    node set-codex-default-model.cjs --model $Model

    $switchArgs = @("switch-codex-gui-model.cjs", "--model", $Model)
    if ($Thread) {
        $switchArgs += @("--thread", $Thread)
    }
    node @switchArgs

    if ($Model -eq "mimo-v2.5-pro") {
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:41418/v1/healthz" -TimeoutSec 3 | Out-Null
        } catch {
            Start-Process -WindowStyle Hidden -FilePath "node" -ArgumentList "C:\Users\water\.codex\mimo-responses-proxy\mimo-responses-proxy.mjs"
            Start-Sleep -Seconds 2
            Invoke-RestMethod -Uri "http://127.0.0.1:41418/v1/healthz" -TimeoutSec 5 | Out-Null
        }
    }

    if ($NoRestart) {
        Write-Host "restart_skipped=true"
        return
    }

    Write-Host "Restarting Codex Desktop so the provider binding reloads..."

    $codexProcesses = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "Codex.exe" -or
        ($_.Name -eq "codex.exe" -and $_.ExecutablePath -like "C:\Program Files\WindowsApps\OpenAI.Codex_*")
    }

    if ($KillRunningSessions) {
        $codexProcesses += Get-CimInstance Win32_Process | Where-Object {
            ($_.Name -eq "codex.exe" -or $_.Name -eq "node.exe") -and
            $_.CommandLine -match "(codex\.js|codex\\codex\.exe)\s+resume"
        }
    }

    $codexProcesses |
        Where-Object { $_.ProcessId -ne $PID } |
        Sort-Object ProcessId -Unique |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Seconds 2
    Start-Process -FilePath (Get-CodexAppPath)
    Write-Host "restarted=true"
} finally {
    Pop-Location
}
