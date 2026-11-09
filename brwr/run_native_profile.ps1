param([int]$Games = 3, [switch]$SkipParity)

$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"

if (!(Test-Path '.\project.godot')) { throw 'Esegui dalla cartella brwr (project.godot).' }
if (!(Test-Path $godot)) { throw "Godot non trovato: $godot" }
if (!(Test-Path $python)) { throw "Python non trovato: $python" }
if ($Games -lt 1) { throw 'Games deve essere >= 1' }
$checkpoint = '.\ai\model\brwr_policy_v4.pt'
if (!(Test-Path $checkpoint)) { throw "Checkpoint non trovato: $checkpoint" }
$checkpointSha = (Get-FileHash $checkpoint -Algorithm SHA256).Hash

Write-Host 'Export checkpoint weights (no training)...'
& $python .\ai\python\export_native_policy_v4.py
if ($LASTEXITCODE -ne 0) { throw 'Model export failed' }

Write-Host 'Generate native worker from CURRENT ai_policy_match.gd...'
& $python .\make_native_worker.py
if ($LASTEXITCODE -ne 0) { throw 'Native worker generation failed' }

if (!$SkipParity) {
    Write-Host 'Verify native / PyTorch numerical parity...'
    & $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
    if ($LASTEXITCODE -ne 0) { throw 'PARITY FAILED: profiling not started' }
}

Write-Host 'Generate separate INSTRUMENTED worker, policy and bridge...'
& $python .\build_native_profiler.py
if ($LASTEXITCODE -ne 0) { throw 'Profiler build failed: originals unchanged' }

$cases = @(
    @{ seed=20270491; bots=4; avatar='none'; difficulty='apprentice' },
    @{ seed=20270492; bots=6; avatar='none'; difficulty='apprentice' },
    @{ seed=20270493; bots=3; avatar='possessed'; difficulty='apprentice' }
)
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = Join-Path '.\ai\native_profile_logs' $runId
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$records = @()
$profiles = @()
$totalWatch = [Diagnostics.Stopwatch]::StartNew()

for ($k=0; $k -lt $Games; $k++) {
    $s = $cases[$k % $cases.Count]
    $seed = [int]($s.seed + 3 * [math]::Floor($k / $cases.Count))
    $log = Join-Path $logDir ("profile_{0:D3}_seed{1}.log" -f ($k+1), $seed)
    $w = [Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script res://ai/ai_policy_native_profile.gd -- $seed $s.bots $s.avatar $s.difficulty normal *> $log
    $exit = $LASTEXITCODE
    $w.Stop()
    if ($exit -ne 0) {
        Get-Content $log -Tail 45
        throw "Godot profiler failed: $log"
    }
    $complete = Select-String -Path $log -Pattern '^AI_EPISODE_COMPLETE' | Select-Object -Last 1
    $matched = Select-String -Path $log -Pattern '^NATIVE_PROFILE_JSON ' | Select-Object -Last 1
    if (!$complete -or !$matched) {
        Get-Content $log -Tail 45
        throw "Missing episode/profile marker: $log"
    }
    $json = $matched.Line.Substring('NATIVE_PROFILE_JSON '.Length)
    try { $profile = $json | ConvertFrom-Json } catch { throw "Malformed profile JSON: $log" }
    $profiles += $profile
    $records += [pscustomobject]@{
        game = $k + 1; seed = $seed; bots = $s.bots; avatar = $s.avatar
        decisions = [int]$profile.decisions; wall_s = $w.Elapsed.TotalSeconds; engine_s = [double]$profile.wall_ms / 1000.0
        log = $log
    }
    Write-Host ("Game {0}/{1}: seed={2} decisions={3} wall={4:N2}s engine={5:N2}s" -f ($k+1), $Games, $seed, $profile.decisions, $w.Elapsed.TotalSeconds, ($profile.wall_ms/1000.0))
}
$totalWatch.Stop()
$wall = $totalWatch.Elapsed.TotalSeconds
$decisions = ($profiles | Measure-Object -Property decisions -Sum).Sum

function SumProfile([string]$name) {
    $total = 0.0
    foreach ($p in $profiles) {
        $prop = $p.PSObject.Properties[$name]
        if ($null -ne $prop) { $total += [double]$prop.Value }
    }
    return $total
}

Write-Host '================ BRWR NATIVE PROFILE ================'
Write-Host ("Games: {0}; decisions: {1}; wall: {2:N2}s; mean: {3:N2}s/game; {4:N2}ms/decision" -f $Games, $decisions, $wall, ($wall/$Games), (1000*$wall/[math]::Max(1,$decisions)))
Write-Host '--- Component totals (do NOT add nested components) ---'
$rows = @(
    @('setup_ms', 'Initial setup/loading'),
    @('decision_ms', 'bridge.decision (external)'),
    @('observation_ms', 'bridge.observation'),
    @('policy_ms', 'Native policy.choose TOTAL'),
    @('policy_encode_ms', '  feature encoding (included)'),
    @('policy_score_ms', '  neural forward (included)'),
    @('step_ms', 'bridge.step TOTAL'),
    @('step_fresh_decision_ms', '  validation: recompute actions'),
    @('step_stage_commit_ms', '  stage update (included)'),
    @('step_game_submit_ms', '  game.submit_beta_input (included)'),
    @('dataset_store_ms', 'JSONL serialize+write'),
    @('dataset_flush_ms', 'Dataset flush'),
    @('frame_wait_ms', 'await process_frame (includes engine)'),
    @('frame_idle_wait_ms', '  game busy / not waiting input'),
    @('frame_active_wait_ms', '  game awaiting input')
)
foreach ($item in $rows) {
    $ms = SumProfile $item[0]
    Write-Host ("  {0,-39} {1,9:N3} s   {2,8:N2} ms/decision" -f $item[1], ($ms/1000.0), ($ms/[math]::Max(1,$decisions)))
}
$frameCount = SumProfile 'frame_count'
$idleFrames = SumProfile 'idle_frame_count'
$actFrames = SumProfile 'active_frame_count'
$encodeCalls = SumProfile 'policy_encode_calls'
$scoreCalls = SumProfile 'policy_score_calls'
$freshCalls = SumProfile 'step_fresh_decision_calls'
$submitCalls = SumProfile 'step_game_submit_calls'
$stagedCalls = SumProfile 'step_stage_commit_calls'
Write-Host ("Frames: {0} ({1:N2}/decision), idle={2}, active={3}; avg wait={4:N2}ms/frame" -f $frameCount, ($frameCount/[math]::Max(1,$decisions)), $idleFrames, $actFrames, ((SumProfile 'frame_wait_ms')/[math]::Max(1,$frameCount)))
Write-Host ("Network forwards: {0}; encoded candidates: {1}; step validations: {2}; game submits: {3}; staged choices: {4}" -f $scoreCalls, $encodeCalls, $freshCalls, $submitCalls, $stagedCalls)

$types = @{}
foreach ($p in $profiles) {
    foreach ($prop in $p.action_types.PSObject.Properties) {
        if (!$types.ContainsKey($prop.Name)) { $types[$prop.Name] = @{count=0; step_us=0} }
        $types[$prop.Name].count += [int]$prop.Value.count
        $types[$prop.Name].step_us += [int64]$prop.Value.step_us
    }
}
Write-Host '--- Slowest bridge.step request types (total time) ---'
$types.GetEnumerator() | Sort-Object { $_.Value.step_us } -Descending | Select-Object -First 8 | ForEach-Object {
    Write-Host ("  {0,-34} count={1,5} total={2,9:N3}s mean={3,8:N2}ms" -f $_.Key, $_.Value.count, ($_.Value.step_us / 1000000.0), ($_.Value.step_us / 1000.0 / [math]::Max(1,$_.Value.count)))
}

$summary = [pscustomobject]@{ games=$Games; decisions=$decisions; wall_s=$wall; component_profiles=$profiles; games_detail=$records }
$summaryFile = Join-Path $logDir 'summary.json'
$summary | ConvertTo-Json -Depth 15 | Set-Content -Path $summaryFile -Encoding UTF8
$hashAfter = (Get-FileHash $checkpoint -Algorithm SHA256).Hash
Write-Host "Detailed profiles: $summaryFile"
if ($hashAfter -ne $checkpointSha) { throw 'CHECKPOINT HASH CHANGED - investigate!' }
Write-Host 'NATIVE_PROFILE_COMPLETE | checkpoint SHA256 unchanged'
Write-Host '====================================================='
