$ErrorActionPreference = "SilentlyContinue"

$rollout = "C:\Users\water\.codex\sessions\2026\05\05\rollout-2026-05-05T18-18-49-019df82f-1755-7532-a8ca-0cecb1604df8.jsonl"
$logDir = "C:\Users\water\.codex\mimo-debug"
$log = Join-Path $logDir "test1-chat-monitor.log"
$state = "C:\Users\water\.codex\state_5.sqlite"
$proxyErr = "C:\Users\water\.codex\mimo-responses-proxy\proxy.stderr.log"
$proxyOut = "C:\Users\water\.codex\mimo-responses-proxy\proxy.stdout.log"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-MonitorLog {
    param([string] $Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -Path $log -Value "[$stamp] $Message"
}

Write-MonitorLog "monitor_started rollout=$rollout"

$lastLength = -1
$lastWrite = $null
$proxyPositions = @{}
while ($true) {
    if (Test-Path -LiteralPath $rollout) {
        $item = Get-Item -LiteralPath $rollout
        if ($item.Length -ne $lastLength -or $item.LastWriteTimeUtc -ne $lastWrite) {
            $lastLength = $item.Length
            $lastWrite = $item.LastWriteTimeUtc
            Write-MonitorLog "rollout_changed size=$($item.Length) last_write_utc=$($item.LastWriteTimeUtc.ToString('o'))"
            Get-Content -LiteralPath $rollout -Tail 8 | ForEach-Object {
                if ($_ -match '"type":"task_complete"|agent_message|response.failed|token_count|turn_context') {
                    Add-Content -Path $log -Value $_
                }
            }
        }
    } else {
        Write-MonitorLog "rollout_missing"
    }

    foreach ($proxyLog in @($proxyErr, $proxyOut)) {
        if (Test-Path -LiteralPath $proxyLog) {
            $item = Get-Item -LiteralPath $proxyLog
            $previous = 0
            if ($proxyPositions.ContainsKey($proxyLog)) {
                $previous = [int64]$proxyPositions[$proxyLog]
            }
            if ($item.Length -gt $previous) {
                $stream = [System.IO.File]::Open($proxyLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $stream.Seek($previous, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $reader = New-Object System.IO.StreamReader($stream)
                    $newText = $reader.ReadToEnd()
                    foreach ($line in ($newText -split "`r?`n")) {
                        if ($line) {
                            Write-MonitorLog "proxy_log $(Split-Path -Leaf $proxyLog): $line"
                        }
                    }
                } finally {
                    $stream.Close()
                }
                $proxyPositions[$proxyLog] = $item.Length
            }
        }
    }

    Start-Sleep -Seconds 5
}
