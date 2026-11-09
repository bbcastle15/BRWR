param([int]$Games = 1)
$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
if (!(Test-Path '.\project.godot')) { throw 'Run from the BRWR\brwr folder containing project.godot' }
if (!(Test-Path $godot)) { throw "Godot missing: $godot" }
if (!(Test-Path $python)) { throw "Python missing: $python" }
if ($Games -lt 1) { throw 'Games must be >= 1' }
$protected = @('.\game.gd', '.\game.tscn', '.\ai\ai_native_policy_v4.gd', '.\ai\model\brwr_policy_v4.pt')
foreach ($p in $protected) { if (!(Test-Path $p)) { throw "Missing protected file: $p" } }
$hashBefore = @{}
foreach ($p in $protected) { $hashBefore[$p] = (Get-FileHash $p -Algorithm SHA256).Hash }

Write-Host 'Regenerate checkpoint export, native worker and validate original network...'
& $python .\ai\python\export_native_policy_v4.py
if ($LASTEXITCODE -ne 0) { throw 'Export failed' }
& $python .\make_native_worker.py
if ($LASTEXITCODE -ne 0) { throw 'Native worker build failed' }
& $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'Original policy neural parity failed' }

Write-Host 'Rebuild guarded cached AI worker and verify school manifest...'
& $python .\build_school_cache_variant.py
if ($LASTEXITCODE -ne 0) { throw 'Cached game build failed' }
& $python .\prepare_school_cache.py
if ($LASTEXITCODE -ne 0) { throw 'School cache fingerprint failed' }

Write-Host 'Generate isolated candidate policy and verify numerical/choice parity...'
& $python .\build_policy_prefix_variant.py
if ($LASTEXITCODE -ne 0) { throw 'Prefix variant build failed' }
& $godot --headless --path . --script res://ai/ai_native_policy_prefix_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'PREFIX POLICY PARITY FAILED: no benchmark started' }

$cacheFile = '.\ai\model\playable_schools_cache_v1.json'
if (!(Test-Path $cacheFile)) {
    Write-Host 'Warming school cache once, OUTSIDE timed A/B results...'
    $warmLog = '.\ai\policy_prefix_cache_warmup.log'
    & $godot --headless --path . --script res://ai/ai_policy_school_cached_match.gd -- 20270491 4 none apprentice normal *> $warmLog
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $cacheFile)) {
        Get-Content $warmLog -Tail 30
        throw 'School cache warmup failed; cannot run fair A/B'
    }
}

$cases = @(
    @{ seed=20270491; bots=4; avatar='none' },
    @{ seed=20270492; bots=6; avatar='none' },
    @{ seed=20270493; bots=3; avatar='possessed' }
)
$folder = '.\ai\policy_prefix_logs\' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force $folder | Out-Null
function Invoke-Worker($scriptName, $seed, $bots, $avatar, $label) {
    $log = Join-Path $folder ("{0}_seed{1}.log" -f $label, $seed)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script $scriptName -- $seed $bots $avatar apprentice normal *> $log
    $exit = $LASTEXITCODE
    $sw.Stop()
    if ($exit -ne 0) { Get-Content $log -Tail 30; throw "Godot failed for ${label}: $log" }
    $completed = Select-String -Path $log -Pattern '^AI_EPISODE_COMPLETE\s' | Select-Object -Last 1
    $out = Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+' | Select-Object -Last 1
    if (!$completed -or !$out) { Get-Content $log -Tail 30; throw "Incomplete $label" }
    $path = ($out.Line -replace '^AI_EPISODE_FILE\s+', '').Trim()
    if (!(Test-Path $path)) { throw "Missing episode $path" }
    $decisions = [int]([regex]::Match($completed.Line, 'decisions=(\d+)').Groups[1].Value)
    Write-Host ("{0}: seed={1} decisions={2} wall={3:N2}s" -f $label,$seed,$decisions,$sw.Elapsed.TotalSeconds)
    return [pscustomobject]@{Time=$sw.Elapsed.TotalSeconds; Decisions=$decisions; File=$path}
}

$referenceTotal = 0.0
$fastTotal = 0.0
$decisionsTotal = 0
for ($i=0; $i -lt $Games; $i++) {
    $c = $cases[$i % $cases.Count]
    $seed = $c.seed + 3 * [math]::Floor($i / $cases.Count)
    # Alternate run order on successive seeds to reduce systematic A/B warming bias.
    if ($i % 2 -eq 0) {
        $a = Invoke-Worker 'res://ai/ai_policy_school_cached_match.gd' $seed $c.bots $c.avatar ("reference_{0:D3}" -f ($i+1))
        $b = Invoke-Worker 'res://ai/ai_policy_school_prefix_match.gd' $seed $c.bots $c.avatar ("prefix_{0:D3}" -f ($i+1))
    } else {
        $b = Invoke-Worker 'res://ai/ai_policy_school_prefix_match.gd' $seed $c.bots $c.avatar ("prefix_{0:D3}" -f ($i+1))
        $a = Invoke-Worker 'res://ai/ai_policy_school_cached_match.gd' $seed $c.bots $c.avatar ("reference_{0:D3}" -f ($i+1))
    }
    & $python .\check_school_cache_parity.py $a.File $b.File
    if ($LASTEXITCODE -ne 0) { throw "POLICY PREFIX EPISODE PARITY FAILED seed $seed; optimization rejected" }
    $referenceTotal += $a.Time
    $fastTotal += $b.Time
    $decisionsTotal += $a.Decisions
}
foreach ($p in $protected) {
    if ($hashBefore[$p] -ne (Get-FileHash $p -Algorithm SHA256).Hash) { throw "Protected source changed: $p" }
}
Write-Host '========== BRWR POLICY PREFIX A/B =========='
Write-Host ("Games: {0} | Decisions: {1}" -f $Games,$decisionsTotal)
Write-Host ("Original policy: {0:N2}s total | {1:N2}s/game" -f $referenceTotal,($referenceTotal/$Games))
Write-Host ("Prefix policy:   {0:N2}s total | {1:N2}s/game" -f $fastTotal,($fastTotal/$Games))
Write-Host ("Wall speedup:    {0:N3}x (positive means faster)" -f ($referenceTotal/[math]::Max(0.00001,$fastTotal)))
Write-Host "Detailed logs: $folder"
Write-Host 'POLICY_PREFIX_BENCHMARK_COMPLETE | all full-episode parity passed | original game and checkpoint unchanged'
Write-Host '============================================'
