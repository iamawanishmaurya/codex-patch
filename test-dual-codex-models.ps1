param(
    [int] $TimeoutSeconds = 180,

    [string] $OpenAIModel = "gpt-5.5",

    [string] $MimoModel = "mimo-v2.5-pro"
)

$ErrorActionPreference = "Stop"

function Quote-CmdArg {
    param([string] $Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

function New-CodexCommandLine {
    param([string[]] $Arguments)

    return "codex " + (($Arguments | ForEach-Object { Quote-CmdArg $_ }) -join " ")
}

function Start-CodexSmoke {
    param(
        [string] $Name,
        [string[]] $Arguments,
        [string] $Directory
    )

    $stdout = Join-Path $Directory "$Name.out.txt"
    $stderr = Join-Path $Directory "$Name.err.txt"
    $cmdLine = New-CodexCommandLine -Arguments $Arguments

    $process = Start-Process -FilePath "cmd.exe" -ArgumentList @(
        "/d",
        "/c",
        $cmdLine
    ) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden

    [pscustomobject]@{
        Name = $Name
        Process = $process
        Command = "cmd.exe /d /c $cmdLine"
        Stdout = $stdout
        Stderr = $stderr
        TimedOut = $false
    }
}

function Read-TextFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return [System.IO.File]::ReadAllText($Path)
}

function Summarize-Smoke {
    param([object] $Run)

    $stdout = Read-TextFile $Run.Stdout
    $stderr = Read-TextFile $Run.Stderr
    $combined = "$stdout`n$stderr"
    $exitCode = $Run.Process.ExitCode
    if ($null -eq $exitCode) {
        $exitCode = "unavailable"
    }

    [pscustomobject]@{
        name = $Run.Name
        timedOut = $Run.TimedOut
        hasExited = $Run.Process.HasExited
        exitCode = $exitCode
        stdoutContainsGptMarker = $stdout -match "DUAL_GPT55_OK"
        stdoutContainsMimoMarker = $stdout -match "DUAL_MIMO_OK"
        hitOpenAIUsageLimit = $combined -match "usage limit"
        hasMimoUpstreamError = $combined -match "Mimo upstream"
        hasUnsupportedModelError = $combined -match "Not supported model"
        hasChatGpt403Warning = $combined -match "403 Forbidden"
        stdoutPreview = (($stdout.Trim() -replace "\s+", " ") | Select-Object -First 1)
        stderrMatchPreview = (($combined -split "`r?`n" | Where-Object {
            $_ -match "DUAL_|usage limit|Mimo upstream|Not supported model|403 Forbidden"
        } | Select-Object -First 5) -join " | ")
        stdoutPath = $Run.Stdout
        stderrPath = $Run.Stderr
        command = $Run.Command
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$workDir = Join-Path $env:TEMP "codex-dual-model-$timestamp"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$codexCommand = Get-Command codex -ErrorAction Stop

$gptArgs = @(
    "exec",
    "--model",
    $OpenAIModel,
    "--dangerously-bypass-approvals-and-sandbox",
    "Reply exactly DUAL_GPT55_OK. Do not use tools."
)

$mimoArgs = @(
    "exec",
    "--profile",
    "mimo",
    "--model",
    $MimoModel,
    "--dangerously-bypass-approvals-and-sandbox",
    "Reply exactly DUAL_MIMO_OK. Do not use tools."
)

$runs = @(
    Start-CodexSmoke -Name "gpt55" -Arguments $gptArgs -Directory $workDir
    Start-CodexSmoke -Name "mimo" -Arguments $mimoArgs -Directory $workDir
)

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
foreach ($run in $runs) {
    while (-not $run.Process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $run.Process.Refresh()
    }

    if (-not $run.Process.HasExited) {
        $run.TimedOut = $true
        Stop-Process -Id $run.Process.Id -Force -ErrorAction SilentlyContinue
    }

    $run.Process.WaitForExit()
    $run.Process.Refresh()
}

$summary = [pscustomobject]@{
    createdAt = (Get-Date).ToString("o")
    workDir = $workDir
    codexCommandType = $codexCommand.CommandType.ToString()
    codexCommandSource = $codexCommand.Source
    spawnMethod = "cmd.exe /d /c codex ..."
    note = "OpenAI may fail with an account usage-limit message; that still proves it did not route through the MiMo proxy when MiMo-specific errors are false."
    runs = @($runs | ForEach-Object { Summarize-Smoke -Run $_ })
}

$summary | ConvertTo-Json -Depth 8
