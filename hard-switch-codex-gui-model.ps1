param(
    [Parameter(Mandatory = $true)]
    [string] $Model,

    [string] $Thread,

    [switch] $NoRestart,

    [switch] $Restart,

    [switch] $KillRunningSessions,

    [switch] $ProjectThreads,

    [switch] $AllProjectThreads,

    [switch] $NoThreadSwitch,

    [switch] $VerboseLogs
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModelCatalogPath = Join-Path $RepoRoot "codex-models.json"
$ModelCatalog = Get-Content -LiteralPath $ModelCatalogPath -Raw | ConvertFrom-Json

function Write-Log {
    param([string] $Message)

    if ($VerboseLogs) {
        Write-Host $Message
    }
}

function Invoke-NodeScript {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    if ($VerboseLogs) {
        & node @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "node $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
        return
    }

    $output = & node @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $details = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = "No output was captured."
        }
        throw "node $($Arguments -join ' ') failed with exit code $exitCode`n$details"
    }
}

function Get-ProviderForModel {
    param([string] $ModelName)

    foreach ($provider in $ModelCatalog.providers) {
        foreach ($modelEntry in $provider.models) {
            if ($modelEntry.slug -eq $ModelName) {
                return $provider
            }
        }
    }

    throw "Unknown model: $ModelName"
}

function Restart-MimoProxy {
    $proxyScript = "C:\Users\water\.codex\mimo-responses-proxy\start-mimo-proxy.ps1"

    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match "mimo-responses-proxy"
    } | Where-Object {
        $_.ProcessId -ne $PID
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 500
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $proxyScript
    )
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Uri "http://127.0.0.1:41418/v1/healthz" -TimeoutSec 5 | Out-Null
}

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

function Test-CodexDesktopMainProcess {
    return [bool](Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "Codex.exe" -and $_.CommandLine -notmatch "--type="
    } | Select-Object -First 1)
}

function Open-CodexDesktopNewWindow {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $LaunchTarget
    )

    if (-not (Test-CodexDesktopMainProcess)) {
        Start-CodexDesktop -LaunchTarget $LaunchTarget
        Write-Log "desktop_launch_mode=start_app"
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $activated = $shell.AppActivate("Codex")
    if (-not $activated) {
        Start-CodexDesktop -LaunchTarget $LaunchTarget
        Start-Sleep -Seconds 2
        $activated = $shell.AppActivate("Codex")
    }

    if (-not $activated) {
        throw "Could not focus Codex Desktop to open a new window."
    }

    Start-Sleep -Milliseconds 300
    $shell.SendKeys("^+n")
    Start-Sleep -Milliseconds 800
    $shell.SendKeys("^n")
    Write-Log "desktop_launch_mode=new_window_shortcut"
    Write-Log "desktop_new_chat_shortcut=true"
}

Push-Location $RepoRoot
try {
    $selectedProvider = Get-ProviderForModel -ModelName $Model
    $launchTarget = $null
    $shouldLaunch = -not $NoRestart
    $shouldRestart = $Restart -and -not $NoRestart
    if ($shouldLaunch) {
        $launchTarget = Get-CodexLaunchTarget
        Write-Log "launch_target_kind=$($launchTarget.Kind)"
        Write-Log "launch_target_value=$($launchTarget.Value)"

        if ($shouldRestart) {
            Write-Log "Stopping Codex Desktop before writing model/provider state..."

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
        } else {
            Write-Log "preserve_running_codex=true"
        }
    }

    Invoke-NodeScript -Arguments @("repair-codex-mimo.cjs")

    if ($selectedProvider.id -eq "openai") {
        Invoke-NodeScript -Arguments @("update-gpt-providers.cjs")
    }

    Invoke-NodeScript -Arguments @("set-codex-default-model.cjs", "--model", $Model)

    if ($NoThreadSwitch) {
        Write-Log "thread_switch=skipped"
    } else {
        $switchArgs = @("switch-codex-gui-model.cjs", "--model", $Model)
        if ($Thread) {
            $switchArgs += @("--thread", $Thread)
        }
        if ($ProjectThreads -and -not $Thread) {
            $switchArgs += "--project-threads"
        }
        if ($AllProjectThreads -and -not $Thread) {
            $switchArgs += "--all-project-threads"
        }
        Invoke-NodeScript -Arguments $switchArgs
    }

    if ($selectedProvider.id -eq "xiaomi") {
        Restart-MimoProxy
    }

    if (-not $shouldLaunch) {
        Write-Log "launch_skipped=true"
        return
    }

    if ($shouldRestart) {
        Write-Log "Restarting Codex Desktop so the provider binding reloads..."
        Start-CodexDesktop -LaunchTarget $launchTarget
    } else {
        Write-Log "Opening a new Codex Desktop window without closing existing sessions..."
        Open-CodexDesktopNewWindow -LaunchTarget $launchTarget
    }
    Write-Log "launched=true"
} finally {
    Pop-Location
}
