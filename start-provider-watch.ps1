$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $repo "watch-codex-provider-drift.cjs"
$log = Join-Path $repo "provider-watch.log"

Start-Process powershell.exe `
  -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "cd '$repo'; node '$script' *>> '$log'" `
  -WindowStyle Hidden

Write-Output "started_provider_watch_log=$log"
