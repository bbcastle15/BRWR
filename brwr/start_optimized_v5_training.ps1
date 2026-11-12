param(
    [int]$Games = 1,
    [string]$Godot = '',
    [switch]$KeepEpisodes,
    [switch]$PrepareOnly,
    [int]$Timeout = 300
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Test-Path '.\project.godot')) { throw 'Run from BRWR\brwr (project.godot missing)' }
$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
if (-not (Test-Path $python)) { throw "Python venv missing: $python" }
if ($Godot.Trim() -eq '') {
    $dirs = @(
        (Join-Path $env:USERPROFILE 'Desktop\BRWR-Windows-playtest\godot'),
        (Join-Path $PSScriptRoot '..\playtest\godot'),
        (Join-Path $PSScriptRoot '..\..\playtest\godot')
    )
    foreach ($dir in $dirs) {
        if (Test-Path $dir) {
            $match = Get-ChildItem $dir -Filter '*console.exe' -File | Select-Object -First 1
            if ($null -ne $match) { $Godot = $match.FullName; break }
        }
    }
}
if (-not (Test-Path $Godot)) { throw 'Godot console not found; use -Godot "C:\path\to\godot_console.exe"' }
$cli = @('.\ai\python\train_optimized_v5.py', '--godot', $Godot, '--games', [string]$Games, '--timeout', [string]$Timeout)
if ($KeepEpisodes) { $cli += '--keep-episodes' }
if ($PrepareOnly) { $cli += '--prepare-only' }
Write-Host ("BRWR V5 SEMANTIC | games={0} prepare_only={1} python={2} godot={3}" -f $Games,$PrepareOnly.IsPresent,$python,$Godot)
& $python @cli
if ($LASTEXITCODE -ne 0) { throw ("V5 optimized training failed, code={0}" -f $LASTEXITCODE) }
