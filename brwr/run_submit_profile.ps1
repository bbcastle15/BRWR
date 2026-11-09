param([int]$Games = 3)
$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
if (!(Test-Path '.\project.godot')) { throw 'Run from BRWR\brwr containing project.godot' }
if (!(Test-Path $python)) { throw "Python missing: $python" }
if (!(Test-Path $godot)) { throw "Godot missing: $godot" }
if (!(Test-Path '.\ai\model\brwr_policy_v4.pt')) { throw 'Checkpoint missing' }
if ($Games -lt 1) { throw 'Games must be >= 1' }

$sha = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
function Run-Python([string]$script) {
    & $python $script
    if ($LASTEXITCODE -ne 0) { throw "Python command failed: $script" }
}
Write-Host 'Export weights; rebuild native worker from CURRENT sources; check PyTorch parity...'
Run-Python '.\ai\python\export_native_policy_v4.py'
Run-Python '.\make_native_worker.py'
& $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'Native neural parity failed' }

Write-Host 'Refresh isolated AI school-cache variant and resource manifest...'
Run-Python '.\build_school_cache_variant.py'
Run-Python '.\prepare_school_cache.py'
Run-Python '.\build_submit_profile.py'
Write-Host 'Validate GDScript syntax before running any games...'
& $godot --headless --path . --check-only --script res://ai/game_submit_profile.gd
if ($LASTEXITCODE -ne 0) { throw 'Generated Game GDScript has syntax errors' }
& $godot --headless --path . --check-only --script res://ai/ai_policy_submit_profile.gd
if ($LASTEXITCODE -ne 0) { throw 'Generated worker GDScript has syntax errors' }
Write-Host 'SUBMIT_PROFILE_SYNTAX_OK'

$dir = '.\ai\submit_profile_logs\' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$cases = @(
    @{seed=20270491; bots=4; avatar='none'},
    @{seed=20270492; bots=6; avatar='none'},
    @{seed=20270493; bots=3; avatar='possessed'}
)
function Run-Match([string]$worker, [int]$seed, [int]$bots, [string]$avatar, [string]$tag) {
    $log = Join-Path $dir ("{0}_{1}.log" -f $tag,$seed)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Explicitly capture native tool errors to a log; they are inspected below.
    & $godot --headless --path . --script $worker -- $seed $bots $avatar apprentice normal *> $log
    $exit = $LASTEXITCODE
    $sw.Stop()
    if ($exit -ne 0) {
        Get-Content $log -Tail 35
        throw "Godot error ($tag): $log"
    }
    $ok = Select-String -Path $log -Pattern 'AI_EPISODE_COMPLETE' | Select-Object -Last 1
    $fileline = Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+' | Select-Object -Last 1
    if (!$ok -or !$fileline) { Get-Content $log -Tail 35; throw "Incomplete episode: $log" }
    $path = ($fileline.Line -replace '^AI_EPISODE_FILE\s+','').Trim()
    if (!(Test-Path $path)) { throw "Missing JSONL $path" }
    Write-Host ("{0}: seed={1} wall={2:N2}s {3}" -f $tag,$seed,$sw.Elapsed.TotalSeconds,$ok.Line.Trim())
    return [pscustomobject]@{Log=$log; Episode=$path; Seconds=$sw.Elapsed.TotalSeconds}
}

# A single warm-cache baseline checks that method wrapping does not alter moves.
# A cache miss is warmed up before measuring, and is not included in timings.
$cache = '.\ai\model\playable_schools_cache_v1.json'
if (!(Test-Path $cache)) {
    Write-Host 'Cache missing/invalidated: warm up with one original cached AI game...'
    $null = Run-Match 'res://ai/ai_policy_school_cached_match.gd' 20270491 4 'none' 'cache_warmup'
}
Write-Host 'Run controlled identical-seed parity against cached AI baseline...'
$baseline = Run-Match 'res://ai/ai_policy_school_cached_match.gd' 20270491 4 'none' 'baseline'
$all = @()
for ($k=0; $k -lt $Games; $k++) {
    $s = $cases[$k % $cases.Count]
    $seed = [int]$s.seed + 3 * [int][math]::Floor($k / $cases.Count)
    $r = Run-Match 'res://ai/ai_policy_submit_profile.gd' $seed $s.bots $s.avatar ("profile_{0:D3}" -f ($k+1))
    $all += $r
    if ($k -eq 0) {
        & $python .\check_school_cache_parity.py $baseline.Episode $r.Episode
        if ($LASTEXITCODE -ne 0) { throw 'PROFILE PARITY FAILED: no optimization is safe yet' }
    }
}
if ($all.Count -gt 0) {
    $logArgs = @($all | ForEach-Object { $_.Log })
    & $python .\summarize_submit_profile.py @logArgs
    if ($LASTEXITCODE -ne 0) { throw 'Cannot summarize profiler logs' }
}
$shaAfter = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
if ($sha -ne $shaAfter) { throw 'Checkpoint hash changed unexpectedly' }
Write-Host 'CHECKPOINT_UNCHANGED | SUBMIT_PROFILE_DONE'
