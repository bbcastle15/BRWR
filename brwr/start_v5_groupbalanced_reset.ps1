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

Write-Host 'Group-balanced probability, gradient, entropy and learning tests...'
& $python '.\ai\python\test_v5_group_balanced.py'
if ($LASTEXITCODE -ne 0) { throw 'Group-balanced tests failed' }
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
$cli = @('.\ai\python\train_v5_groupbalanced_reset.py', '--games', [string]$Games,
          '--timeout', [string]$Timeout)
if ($PrepareOnly.IsPresent) { $cli += '--prepare-only' }
if ($KeepEpisodes.IsPresent) { $cli += '--keep-episodes' }
if ($Godot.Trim() -ne '') { $cli += @('--godot', $Godot) }
Write-Host ('BRWR V5-GROUP-RESET | prepare_only={0} games={1} python={2}' -f $PrepareOnly.IsPresent,$Games,$python)
& $python @cli
if ($LASTEXITCODE -ne 0) { throw ('V5-GROUP-RESET failed, exit code=' + $LASTEXITCODE) }
