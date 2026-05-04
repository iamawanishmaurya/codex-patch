param(
    [string] $InstallDir = (Join-Path $env:USERPROFILE "bin")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CommandScript = Join-Path $RepoRoot "codex-gui.ps1"

if (-not (Test-Path -LiteralPath $CommandScript)) {
    throw "Missing command script: $CommandScript"
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$CmdShimPath = Join-Path $InstallDir "codex-gui.cmd"
$PsShimPath = Join-Path $InstallDir "codex-gui.ps1"

$cmdShim = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$CommandScript" %*
"@

$psShim = @"
& "$CommandScript" @args
if (`$LASTEXITCODE -ne `$null) { exit `$LASTEXITCODE }
"@

Set-Content -LiteralPath $CmdShimPath -Value $cmdShim -Encoding ASCII
Set-Content -LiteralPath $PsShimPath -Value $psShim -Encoding ASCII

function Normalize-PathText {
    param([string] $PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return ""
    }

    return $PathText.Trim().TrimEnd("\", "/")
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($null -eq $userPath) {
    $userPath = ""
}

$normalizedInstallDir = Normalize-PathText $InstallDir
$pathParts = $userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$alreadyOnPath = $false

foreach ($pathPart in $pathParts) {
    if ((Normalize-PathText $pathPart) -ieq $normalizedInstallDir) {
        $alreadyOnPath = $true
        break
    }
}

if (-not $alreadyOnPath) {
    $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
        $InstallDir
    } else {
        "$userPath;$InstallDir"
    }

    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    $env:Path = "$env:Path;$InstallDir"
}

Write-Host "installed_command=$CmdShimPath"
Write-Host "installed_powershell_shim=$PsShimPath"
Write-Host "path_added=$(-not $alreadyOnPath)"
Write-Host "Run 'codex-gui' from a new terminal, or run '$CmdShimPath' immediately."
