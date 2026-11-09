param(
    [int]$Games = 3,
    [switch]$BatchFirst
)

# Controlled, sequential multi-episode speed/parity experiment.
# Run from BRWR\brwr. Neither production rules nor neural checkpoint are edited.
$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"

if (!(Test-Path '.\project.godot')) { throw 'Run this script from BRWR\brwr (project.godot)' }
if (!(Test-Path $godot)) { throw ("Godot not found: {0}" -f $godot) }
if (!(Test-Path $python)) { throw ("Python not found: {0}" -f $python) }
if ($Games -lt 1 -or $Games -gt 30) { throw 'Games must be between 1 and 30' }

$protected = @(
    '.\game.gd', '.\game.tscn', '.\ai\ai_native_policy_v4.gd',
    '.\ai\model\brwr_policy_v4.pt'
)
foreach ($p in $protected) {
    if (!(Test-Path $p)) { throw ("Protected file missing: {0}" -f $p) }
}
$hashBefore = @{}
foreach ($p in $protected) { $hashBefore[$p] = (Get-FileHash $p -Algorithm SHA256).Hash }

Write-Host '1/6 Export policy and verify PyTorch/native numerical parity...'
& $python '.\ai\python\export_native_policy_v4.py'
if ($LASTEXITCODE -ne 0) { throw 'Native export failed' }
& $python '.\make_native_worker.py'
if ($LASTEXITCODE -ne 0) { throw 'Native worker generation failed' }
& $godot --headless --path . --script 'res://ai/ai_native_policy_validation.gd'
if ($LASTEXITCODE -ne 0) { throw 'Native numerical parity failed' }

Write-Host '2/6 Generate CURRENT cached/guarded Game and shared-prefix policy...'
& $python '.\build_school_cache_variant.py'
if ($LASTEXITCODE -ne 0) { throw 'School cache Game generation failed' }
& $python '.\prepare_school_cache.py'
if ($LASTEXITCODE -ne 0) { throw 'School manifest build failed' }
& $python '.\build_policy_prefix_variant.py'
if ($LASTEXITCODE -ne 0) { throw 'Prefix policy generation failed' }
& $godot --headless --path . --script 'res://ai/ai_native_policy_prefix_validation.gd'
if ($LASTEXITCODE -ne 0) { throw 'Prefix numerical/choice parity failed' }

Write-Host '3/6 Generate persistent candidate and check GDScript syntax...'
& $python '.\build_persistent_prefix_batch.py'
if ($LASTEXITCODE -ne 0) { throw 'Persistent worker generation failed' }
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
$folder = Join-Path '.\ai\persistent_batch_logs' $stamp
New-Item -ItemType Directory -Force $folder | Out-Null
$checkLog = Join-Path $folder 'godot_syntax.log'
& $godot --headless --path . --check-only --script 'res://ai/ai_policy_prefix_batch_match.gd' *> $checkLog
if ($LASTEXITCODE -ne 0) {
    Get-Content $checkLog -Tail 45
    throw 'Persistent worker GDScript syntax check failed'
}
Write-Host 'PERSISTENT_BATCH_SYNTAX_OK'

$cacheFile = '.\ai\model\playable_schools_cache_v1.json'
if (!(Test-Path $cacheFile)) {
    Write-Host 'Warm school cache outside timed measurements...'
    $warmLog = Join-Path $folder 'cache_warmup.log'
    & $godot --headless --path . --script 'res://ai/ai_policy_school_prefix_match.gd' -- 20270491 4 none apprentice normal *> $warmLog
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $cacheFile)) {
        Get-Content $warmLog -Tail 35
        throw 'Cannot warm school cache'
    }
}

$cases = @(
    @{ seed=20270491; bots=4; avatar='none' },
    @{ seed=20270492; bots=6; avatar='none' },
    @{ seed=20270493; bots=3; avatar='possessed' }
)
$episodes = @()
for ($i=0; $i -lt $Games; $i++) {
    $c = $cases[$i % $cases.Count]
    $offset = 3 * [math]::Floor($i / $cases.Count)
    $episodes += [ordered]@{
        seed=[int]($c.seed + $offset);
        bots=[int]$c.bots;
        avatar=[string]$c.avatar;
        difficulty='apprentice';
        mode='normal'
    }
}
$manifestFile = Join-Path $folder 'episodes_manifest.json'
$manifest = @{ schema_version=1; episodes=$episodes } | ConvertTo-Json -Depth 6
$absoluteManifest = [System.IO.Path]::GetFullPath($manifestFile)
[System.IO.File]::WriteAllText($absoluteManifest, $manifest, ([System.Text.UTF8Encoding]::new($false)))
$relativeFolder = ($folder -replace '^\.\\', '') -replace '\\', '/'
$manifestRes = 'res://' + $relativeFolder + '/episodes_manifest.json'

function Invoke-SingleReference {
    param([int]$Index)
    $e = $episodes[$Index]
    $label = 'reference_{0:D3}_seed{1}' -f ($Index+1), $e.seed
    $log = Join-Path $folder ($label + '.log')
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script 'res://ai/ai_policy_school_prefix_match.gd' -- $e.seed $e.bots $e.avatar $e.difficulty $e.mode *> $log
    $code = $LASTEXITCODE
    $watch.Stop()
    if ($code -ne 0) {
        Get-Content $log -Tail 40
        throw ("Reference Godot run failed for seed {0}: exit={1}" -f $e.seed,$code)
    }
    $completion = @(Select-String -Path $log -Pattern '^AI_EPISODE_COMPLETE\s')
    $paths = @(Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+')
    if ($completion.Count -ne 1 -or $paths.Count -ne 1) {
        Get-Content $log -Tail 40
        throw ("Reference output incomplete: {0}" -f $log)
    }
    $path = ($paths[0].Line -replace '^AI_EPISODE_FILE\s+', '').Trim()
    if (!(Test-Path $path)) { throw ("Reference JSONL missing: {0}" -f $path) }
    $n = [int]([regex]::Match($completion[0].Line, 'decisions=(\d+)').Groups[1].Value)
    Write-Host ('{0}: seed={1} decisions={2} wall={3:N2}s' -f $label,$e.seed,$n,$watch.Elapsed.TotalSeconds)
    return [pscustomobject]@{ Seed=$e.seed; File=$path; Seconds=$watch.Elapsed.TotalSeconds; Decisions=$n }
}

function Invoke-PersistentBatch {
    $log = Join-Path $folder 'persistent_batch.log'
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script 'res://ai/ai_policy_prefix_batch_match.gd' -- $manifestRes *> $log
    $code = $LASTEXITCODE
    $watch.Stop()
    if ($code -ne 0) {
        Get-Content $log -Tail 70
        throw ("Persistent Godot run failed: exit={0}, log={1}" -f $code,$log)
    }
    $done = @(Select-String -Path $log -Pattern '^BRWR_PERSISTENT_BATCH_COMPLETE\s+')
    $completions = @(Select-String -Path $log -Pattern '^AI_EPISODE_COMPLETE\s')
    $paths = @(Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+')
    $episodeTiming = @(Select-String -Path $log -Pattern '^BRWR_PERSISTENT_EPISODE_OK\s')
    if ($done.Count -ne 1 -or $completions.Count -ne $Games -or $paths.Count -ne $Games -or $episodeTiming.Count -ne $Games) {
        Get-Content $log -Tail 70
        throw ("Persistent worker did not complete exactly {0} episodes" -f $Games)
    }
    $results = @()
    for ($i=0; $i -lt $Games; $i++) {
        $path = ($paths[$i].Line -replace '^AI_EPISODE_FILE\s+', '').Trim()
        if (!(Test-Path $path)) { throw ("Persistent JSONL missing: {0}" -f $path) }
        $seed = [int]([regex]::Match($completions[$i].Line, 'seed=(\d+)').Groups[1].Value)
        $n = [int]([regex]::Match($completions[$i].Line, 'decisions=(\d+)').Groups[1].Value)
        if ($seed -ne [int]$episodes[$i].seed) {
            throw ("Persistent episode order/seed mismatch at index {0}: expected={1} got={2}" -f $i,$episodes[$i].seed,$seed)
        }
        $msMatch = [regex]::Match($episodeTiming[$i].Line, 'wall_ms=([\d\.]+)')
        $duration = 0.0
        if ($msMatch.Success) {
            $duration = [double]::Parse($msMatch.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) / 1000.0
        }
        Write-Host ('persistent_{0:D3}: seed={1} decisions={2} worker={3:N2}s' -f ($i+1),$seed,$n,$duration)
        $results += [pscustomobject]@{ Seed=$seed; File=$path; Decisions=$n; Seconds=$duration }
    }
    Write-Host ('persistent process total={0:N2}s' -f $watch.Elapsed.TotalSeconds)
    return [pscustomobject]@{ Seconds=$watch.Elapsed.TotalSeconds; Files=$results; Log=$log }
}

Write-Host '4/6 Run controlled A/B: same seeds and same frozen prefix policy...'
$reference = @()
$persistent = $null
if ($BatchFirst) {
    $persistent = Invoke-PersistentBatch
    for ($i=0; $i -lt $Games; $i++) { $reference += Invoke-SingleReference -Index $i }
} else {
    for ($i=0; $i -lt $Games; $i++) { $reference += Invoke-SingleReference -Index $i }
    $persistent = Invoke-PersistentBatch
}

Write-Host '5/6 Compare full episode transitions/scores and check protected files...'
$decisionTotal = 0
$refSeconds = 0.0
for ($i=0; $i -lt $Games; $i++) {
    $a = $reference[$i]
    $b = $persistent.Files[$i]
    & $python '.\check_persistent_episode_parity.py' $a.File $b.File
    if ($LASTEXITCODE -ne 0) {
        throw ("PERSISTENT_BATCH_STRICT_PARITY_FAILED seed {0}: do NOT use this worker for training" -f $a.Seed)
    }
    if ($a.Decisions -ne $b.Decisions) { throw ("Decision count mismatch seed {0}" -f $a.Seed) }
    $decisionTotal += $a.Decisions
    $refSeconds += $a.Seconds
}
foreach ($p in $protected) {
    $after = (Get-FileHash $p -Algorithm SHA256).Hash
    if ($hashBefore[$p] -ne $after) { throw ("Protected file changed: {0}" -f $p) }
}

Write-Host '6/6 Summary'
Write-Host '========== BRWR PERSISTENT PREFIX A/B =========='
$orderLabel = 'references first'
if ($BatchFirst) { $orderLabel = 'batch first' }
Write-Host ('Games: {0} | Decisions: {1} | Order: {2}' -f $Games,$decisionTotal,$orderLabel)
Write-Host ('Separate Godot runs:  {0:N2}s total | {1:N2}s/game' -f $refSeconds,($refSeconds/$Games))
Write-Host ('One persistent run:   {0:N2}s total | {1:N2}s/game' -f $persistent.Seconds,($persistent.Seconds/$Games))
Write-Host ('Speedup:              {0:N3}x (measured wall-clock)' -f ($refSeconds/[math]::Max(0.00001,$persistent.Seconds)))
Write-Host ('Logs: {0}' -f $folder)
Write-Host 'PERSISTENT_BATCH_BENCHMARK_COMPLETE | ALL_EPISODE_PARITY_OK | CHECKPOINT_UNCHANGED'
Write-Host '================================================'
