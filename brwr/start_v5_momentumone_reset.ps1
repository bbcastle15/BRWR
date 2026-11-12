param(
    [int]$Games = 1,
    [string]$Godot = '',
    [switch]$PrepareOnly,
    [switch]$KeepEpisodes,
    [int]$Timeout = 300
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Test-Path '.\project.godot')) { throw 'project.godot missing: extract into BRWR\brwr' }
$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
if (-not (Test-Path $python)) { throw ('Python venv missing: ' + $python) }

Write-Host 'Momentum-One hierarchical sampling, gradient and entropy tests...'
& $python '.\ai\python\test_v5_momentum_one.py'
if ($LASTEXITCODE -ne 0) { throw 'Momentum-One tests failed' }
Write-Host 'Room-generated Cast provenance tests...'
& $python '.\ai\python\test_v5m1_roomcast_receipts.py'
if ($LASTEXITCODE -ne 0) { throw 'V5M1 room-cast provenance tests failed' }
Write-Host 'V5M1 triggered reaction selection provenance tests...'
& $python '.\ai\python\test_v5m1_reaction_selection_receipts.py'
if ($LASTEXITCODE -ne 0) { throw 'V5M1 reaction-selection provenance tests failed' }
Write-Host 'Unchanged R3 local Momentum shaping tests...'
& $python '.\ai\python\test_v5_r3_momentum.py'
if ($LASTEXITCODE -ne 0) { throw 'Momentum tests failed' }
Write-Host 'Unchanged R3 terminal reward tests...'
& $python '.\ai\python\test_v5_reward_v3.py'
if ($LASTEXITCODE -ne 0) { throw 'R3 reward tests failed' }

if (-not $PrepareOnly.IsPresent -and $Godot.Trim() -eq '') {
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
if (-not $PrepareOnly.IsPresent -and -not (Test-Path $Godot)) {
    throw 'Godot console not found; pass -Godot "C:\path\to\Godot_console.exe"'
}
$cli = @('.\ai\python\train_v5_momentumone_reset.py', '--games', [string]$Games,
          '--timeout', [string]$Timeout)
if ($PrepareOnly.IsPresent) { $cli += '--prepare-only' }
if ($KeepEpisodes.IsPresent) { $cli += '--keep-episodes' }
if ($Godot.Trim() -ne '') { $cli += @('--godot', $Godot) }
Write-Host ('BRWR V5-MOMENTUM-ONE-RESET | prepare_only={0} games={1} python={2}' -f $PrepareOnly.IsPresent,$Games,$python)
& $python @cli
if ($LASTEXITCODE -ne 0) { throw ('V5-MOMENTUM-ONE-RESET failed, exit code=' + $LASTEXITCODE) }
