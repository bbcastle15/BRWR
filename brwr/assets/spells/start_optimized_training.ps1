param(
    [int]$Games = 1,
    [string]$Godot = '',
    [switch]$KeepEpisodes,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Test-Path '.\project.godot')) { throw 'Put this script into the BRWR\brwr folder containing project.godot' }

$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
if (!(Test-Path $python)) {
    $found = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $found) { throw 'Python not found. Specify/install Python with PyTorch.' }
    $python = $found.Source
}
if ($Godot -eq '') {
    $options = @(
        (Join-Path $PSScriptRoot '..\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'),
        (Join-Path $PSScriptRoot '..\..\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe')
    )
    foreach ($candidate in $options) {
        if (Test-Path $candidate) { $Godot = (Resolve-Path $candidate).Path; break }
    }
}
if ($Godot -eq '') { throw 'Godot console not found. Use -Godot "C:\path\to\Godot_console.exe"' }
if (!(Test-Path $Godot)) { throw "Godot missing: $Godot" }

$cliArgs = @('.\ai\python\train_optimized_native.py', '--godot', $Godot, '--games', [string]$Games)
if ($KeepEpisodes) { $cliArgs += '--keep-episodes' }
if ($PrepareOnly) { $cliArgs += '--prepare-only' }
Write-Host ("BRWR Optimized Training | games={0} | python={1} | godot={2}" -f $Games,$python,$Godot)
& $python @cliArgs
if ($LASTEXITCODE -ne 0) { throw "Optimized training failed, exit code: $LASTEXITCODE" }
