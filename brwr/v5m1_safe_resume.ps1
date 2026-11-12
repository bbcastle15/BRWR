param(
    [ValidateSet('Preflight','Smoke','Pilot','Audit')]
    [string]$Stage = 'Preflight',
    [int]$Games = 20,
    [int]$ExpectedGames = -1,
    [string]$Godot = '',
    [int]$RecentEpisodes = 12
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
$checkpoint = Join-Path $PSScriptRoot 'ai\model\brwr_policy_v5_momentumone_reset.pt'
if (-not (Test-Path $python)) { throw ('Python not found: ' + $python) }
if (-not (Test-Path $checkpoint)) { throw ('Checkpoint missing: ' + $checkpoint + ' (stop, never create a fresh reset here)') }

function Get-Games {
    $lines = & $python '.\ai\python\v5m1_training_audit.py' --checkpoint-games
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read checkpoint safely' }
    return [int]($lines | Select-Object -Last 1)
}

function Write-Audit {
    & $python '.\ai\python\v5m1_training_audit.py' --recent-episodes $RecentEpisodes
    if ($LASTEXITCODE -ne 0) { throw 'Read-only audit failed' }
}

$before = Get-Games
Write-Host ('V5M1_SAFE_RESUME stage={0} checkpoint_games={1}' -f $Stage, $before)
if ($ExpectedGames -ge 0 -and $ExpectedGames -ne $before) {
    throw ('SAFETY_STOP expected checkpoint games=' + $ExpectedGames + ' but actual=' + $before)
}
if ($Stage -eq 'Audit') { Write-Audit; exit 0 }

$start = Join-Path $PSScriptRoot 'start_v5_momentumone_reset.ps1'
if (-not (Test-Path $start)) { throw 'V5M1 launcher not found (ZIP extraction incomplete)' }

if ($Stage -eq 'Preflight' -or $Stage -eq 'Smoke') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $start -PrepareOnly
    if ($LASTEXITCODE -ne 0) { throw 'V5M1 preflight failed' }
    if ((Get-Games) -ne $before) { throw 'SAFETY_STOP Preflight unexpectedly changed checkpoint' }
    if ($Stage -eq 'Preflight') { Write-Host 'V5M1_PREFLIGHT_COMPLETE checkpoint_unchanged=1'; exit 0 }
}

if ($Stage -eq 'Pilot' -and ($Games -lt 1 -or $Games -gt 100)) {
    throw 'Pilot range is 1..100 games; use bounded batches for initial testing'
}
$toRun = if ($Stage -eq 'Smoke') { 1 } else { $Games }

$backupDir = Join-Path $PSScriptRoot 'ai\model\backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$backup = Join-Path $backupDir ("brwr_policy_v5_momentumone_reset_manual_before_games{0}_{1}.pt" -f $before, $stamp)
Copy-Item -LiteralPath $checkpoint -Destination $backup -ErrorAction Stop
Write-Host ('V5M1_PRE_RUN_BACKUP ' + $backup)

$logDir = Join-Path $PSScriptRoot 'ai\datasets\v5m1_run_logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("v5m1_{0}_from{1}_{2}.txt" -f $Stage.ToLowerInvariant(), $before, $stamp)
$started = $false
try {
    Start-Transcript -Path $log -ErrorAction Stop | Out-Null
    $started = $true
    $params = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$start,'-Games',[string]$toRun)
    if ($Godot.Trim() -ne '') { $params += @('-Godot',$Godot) }
    # Important: -KeepEpisodes intentionally omitted to protect disk space.
    & powershell @params
    $exitCode = $LASTEXITCODE
} finally {
    if ($started) { Stop-Transcript | Out-Null }
}
$after = Get-Games
Write-Host ('V5M1_RUN_LOG ' + $log)
Write-Host ('V5M1_CHECKPOINT before={0} after={1} requested={2} exit={3}' -f $before,$after,$toRun,$exitCode)
if ($exitCode -ne 0) { throw 'V5M1 run failed: STOP. See log. Checkpoint backup preserved.' }
if ($after -ne $before + $toRun) { throw 'SAFETY_STOP completed games count differs from requested. Inspect logs.' }
Write-Audit
Write-Host 'V5M1_RUN_OK checkpoint_preserved_and_advanced=1'
