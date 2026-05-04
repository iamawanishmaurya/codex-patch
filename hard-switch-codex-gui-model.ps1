param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2", "mimo-v2.5-pro")]
    [string] $Model,

    [string] $Thread,

    [switch] $NoRestart,

    [switch] $KillRunningSessions,

    [switch] $AllProjectThreads
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-CodexLaunchTarget {
    $startApp = Get-StartApps | Where-Object {
        $_.Name -eq "Codex" -or $_.AppID -like "OpenAI.Codex_*"
    } | Select-Object -First 1

    if ($startApp -and $startApp.AppID) {
        return [pscustomobject]@{
            Kind = "AppId"
            Value = $startApp.AppID
        }
    }

    $runningApp = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "Codex.exe" -and $_.CommandLine -notmatch "--type="
    } | Select-Object -First 1

    if ($runningApp -and $runningApp.ExecutablePath) {
        return [pscustomobject]@{
            Kind = "Path"
            Value = $runningApp.ExecutablePath
        }
    }

    $installedApp = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "OpenAI.Codex_*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName "app\Codex.exe" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

    if ($installedApp) {
        return [pscustomobject]@{
            Kind = "Path"
            Value = $installedApp
        }
    }

    throw "Could not locate Codex Desktop from running processes, Start menu apps, or C:\Program Files\WindowsApps."
}

function Start-CodexDesktop {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $LaunchTarget
    )

    if ($LaunchTarget.Kind -eq "Path") {
        Start-Process -FilePath $LaunchTarget.Value
        return
    }

    if ($LaunchTarget.Kind -eq "AppId") {
        Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\$($LaunchTarget.Value)"
        return
    }

    throw "Unknown Codex Desktop launch target kind: $($LaunchTarget.Kind)"
}

Push-Location $RepoRoot
try {
    $launchTarget = $null
    if (-not $NoRestart) {
        $launchTarget = Get-CodexLaunchTarget
        Write-Host "launch_target_kind=$($launchTarget.Kind)"
        Write-Host "launch_target_value=$($launchTarget.Value)"
        Write-Host "Stopping Codex Desktop before writing model/provider state..."

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
    }

    node repair-codex-mimo.cjs

    if ($Model.StartsWith("gpt-")) {
        node update-gpt-providers.cjs
    }

    node set-codex-default-model.cjs --model $Model

    $switchArgs = @("switch-codex-gui-model.cjs", "--model", $Model)
    if ($Thread) {
        $switchArgs += @("--thread", $Thread)
    }
    if ($AllProjectThreads -and -not $Thread) {
        $switchArgs += "--all-project-threads"
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
    Start-CodexDesktop -LaunchTarget $launchTarget
    Write-Host "restarted=true"
} finally {
    Pop-Location
}
