param([int]$Games = 3, [switch]$RebuildCache)
$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
if (!(Test-Path '.\project.godot')) { throw 'Run this from BRWR\brwr (project.godot)' }
if (!(Test-Path $python)) { throw "Python missing: $python" }
if (!(Test-Path $godot)) { throw "Godot missing: $godot" }
if (!(Test-Path '.\ai\model\brwr_policy_v4.pt')) { throw 'Model checkpoint missing' }
if ($Games -lt 1) { throw 'Games must be >= 1' }

$checkpoint = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
Write-Host 'Export weights / validate native inference...'
& $python .\ai\python\export_native_policy_v4.py
if ($LASTEXITCODE -ne 0) { throw 'Model export failed' }
& $python .\make_native_worker.py
if ($LASTEXITCODE -ne 0) { throw 'Native worker build failed' }
& $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'Network parity check failed' }
Write-Host 'Generate isolated school-cache game/scene/workers...'
& $python .\build_school_cache_variant.py
if ($LASTEXITCODE -ne 0) { throw 'School cache variant build failed' }
& $python .\prepare_school_cache.py
if ($LASTEXITCODE -ne 0) { throw 'Cache fingerprint failed' }
$cache = '.\ai\model\playable_schools_cache_v1.json'
if ($RebuildCache -and (Test-Path $cache)) { Remove-Item $cache -Force; Write-Host 'Forced cache rebuild for cold-start timing' }

$folder = '.\ai\school_cache_benchmark_logs\' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$cases = @(
    @{ seed=20270491; bots=4; avatar='none' },
    @{ seed=20270492; bots=6; avatar='none' },
    @{ seed=20270493; bots=3; avatar='possessed' }
)
function Invoke-Match($worker, $seed, $bots, $avatar, $label) {
    $log = Join-Path $folder ("{0}_{1}.log" -f $label,$seed)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script $worker -- $seed $bots $avatar apprentice normal *> $log
    $exit = $LASTEXITCODE
    $sw.Stop()
    if ($exit -ne 0) { Get-Content $log -Tail 30; throw "Godot failed ($label): $log" }
    $end = Select-String -Path $log -Pattern 'AI_EPISODE_COMPLETE' | Select-Object -Last 1
    $fileline = Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+' | Select-Object -Last 1
    if (!$end -or !$fileline) { Get-Content $log -Tail 30; throw "Incomplete game ($label): $log" }
    $episode = ($fileline.Line -replace '^AI_EPISODE_FILE\s+', '').Trim()
    if (!(Test-Path $episode)) { throw "Episode file missing: $episode" }
    $m = [regex]::Match($end.Line, 'decisions=(\d+)')
    if (!$m.Success) { throw "Missing decisions: $($end.Line)" }
    $marker = Select-String -Path $log -Pattern '^BRWR_SCHOOL_CACHE_(HIT|MISS)' | Select-Object -Last 1
    $state = if ($marker) { $marker.Line.Trim() } else { 'original full-validation worker' }
    Write-Host ("{0}: seed={1} decisions={2} wall={3:N2}s {4}" -f $label,$seed,$m.Groups[1].Value,$sw.Elapsed.TotalSeconds,$state)
    return [pscustomobject]@{Time=$sw.Elapsed.TotalSeconds; Decisions=[int]$m.Groups[1].Value; File=$episode; Log=$log}
}

Write-Host 'Controlled parity test: same seed, same model, original vs cached school selection...'
$first = $cases[0]
$reference = Invoke-Match 'res://ai/ai_policy_school_baseline_match.gd' $first.seed $first.bots $first.avatar 'baseline'
$cached_first = Invoke-Match 'res://ai/ai_policy_school_cached_match.gd' $first.seed $first.bots $first.avatar 'cache_first'
& $python .\check_school_cache_parity.py $reference.File $cached_first.File
if ($LASTEXITCODE -ne 0) { throw 'CACHED SCHOOLS NOT EQUIVALENT to baseline; benchmark aborted' }
if (!(Test-Path $cache)) { throw 'Cache was not persisted: cannot benchmark warm-cache' }

$totalSec = 0.0
$totalDecisions = 0
$watch = [System.Diagnostics.Stopwatch]::StartNew()
for ($k=0; $k -lt $Games; $k++) {
    $s = $cases[$k % $cases.Count]
    $seed = $s.seed + 3 * [math]::Floor($k / $cases.Count)
    $run = Invoke-Match 'res://ai/ai_policy_school_cached_match.gd' $seed $s.bots $s.avatar ("warm_{0:D3}" -f ($k+1))
    if ($k -eq 0) {
        & $python .\check_school_cache_parity.py $reference.File $run.File
        if ($LASTEXITCODE -ne 0) { throw 'Warm-cache parity failed; benchmark aborted' }
    }
    $totalSec += $run.Time
    $totalDecisions += $run.Decisions
}
$watch.Stop()
$after = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
if ($checkpoint -ne $after) { throw 'Checkpoint hash changed unexpectedly!' }
Write-Host '========== BRWR SCHOOL CACHE BENCHMARK =========='
Write-Host ("Baseline first game: {0:N2}s" -f $reference.Time)
Write-Host ("Cached first game:   {0:N2}s (cold or pre-existing cache)" -f $cached_first.Time)
Write-Host ("Warm games: {0}; decisions: {1}" -f $Games, $totalDecisions)
Write-Host ("Warm time: {0:N2}s; seconds/game: {1:N2}; ms/decision: {2:N2}" -f $totalSec, ($totalSec/$Games), (1000*$totalSec/[math]::Max(1,$totalDecisions)))
Write-Host ("Speedup vs 30.46s native baseline: {0:N2}x (indicative)" -f (30.46/($totalSec/$Games)))
Write-Host "Detailed logs: $folder"
Write-Host 'SCHOOL_CACHE_BENCHMARK_COMPLETE | parity passed | checkpoint unchanged'
Write-Host '================================================='
