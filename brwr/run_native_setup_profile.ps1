param(
    [int]$Games = 3,
    [switch]$SkipParity
)

# Run from BRWR\brwr, beside project.godot. Checkpoint is never trained or saved.
$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
$checkpoint = '.\ai\model\brwr_policy_v4.pt'

if (!(Test-Path '.\project.godot')) { throw 'Esegui da BRWR\brwr (project.godot).' }
if (!(Test-Path $godot)) { throw "Godot non trovato: $godot" }
if (!(Test-Path $python)) { throw "Python non trovato: $python" }
if (!(Test-Path $checkpoint)) { throw "Checkpoint non trovato: $checkpoint" }
if ($Games -lt 1) { throw 'Games deve essere >= 1' }
$hashBefore = (Get-FileHash $checkpoint -Algorithm SHA256).Hash

Write-Host 'Export saved weights (no model update)...'
& $python .\ai\python\export_native_policy_v4.py
if ($LASTEXITCODE -ne 0) { throw 'Model export failed' }

Write-Host 'Regenerate CURRENT native worker...'
& $python .\make_native_worker.py
if ($LASTEXITCODE -ne 0) { throw 'make_native_worker.py failed' }

if (!$SkipParity) {
    Write-Host 'Check numerical parity before profiling...'
    & $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
    if ($LASTEXITCODE -ne 0) { throw 'Parity check failed; no simulations started' }
}

Write-Host 'Generate ISOLATED setup-profiler worker...'
& $python .\build_native_setup_profiler.py
if ($LASTEXITCODE -ne 0) { throw 'Setup profiler generation failed; originals unchanged' }

$cases = @(
    @{ seed=20270491; bots=4; avatar='none'; difficulty='apprentice' },
    @{ seed=20270492; bots=6; avatar='none'; difficulty='apprentice' },
    @{ seed=20270493; bots=3; avatar='possessed'; difficulty='apprentice' }
)
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$dir = Join-Path '.\ai\native_setup_profile_logs' $runId
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$profiles = @()
$gameRecords = @()
$totalWatch = [Diagnostics.Stopwatch]::StartNew()

for ($k=0; $k -lt $Games; $k++) {
    $case = $cases[$k % $cases.Count]
    $seed = [int]($case.seed + 3 * [math]::Floor($k / $cases.Count))
    $log = Join-Path $dir ('setup_{0:D3}_seed{1}.log' -f ($k+1), $seed)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script res://ai/ai_policy_native_setup_profile.gd -- $seed $case.bots $case.avatar $case.difficulty normal *> $log
    $code = $LASTEXITCODE
    $watch.Stop()
    if ($code -ne 0) {
        Get-Content $log -Tail 50
        throw "Godot exited with code $code; log: $log"
    }
    $marker = Select-String -Path $log -Pattern '^NATIVE_SETUP_PROFILE_JSON ' | Select-Object -Last 1
    $complete = Select-String -Path $log -Pattern '^AI_EPISODE_COMPLETE ' | Select-Object -Last 1
    if (!$marker -or !$complete) {
        Get-Content $log -Tail 50
        throw "Missing successful profile marker: $log"
    }
    try { $p = $marker.Line.Substring('NATIVE_SETUP_PROFILE_JSON '.Length) | ConvertFrom-Json }
    catch { throw "Invalid profiler JSON: $log" }
    $profiles += $p
    $gameRecords += [pscustomobject]@{
        game=($k+1); seed=$seed; bots=$case.bots; avatar=$case.avatar;
        decisions=[int]$p.decisions; process_wall_s=$watch.Elapsed.TotalSeconds;
        setup_s=([double]$p.legacy_setup_ms / 1000.0); log=$log
    }
    Write-Host ('Game {0}/{1}: seed={2} decisions={3} wall={4:N2}s setup={5:N2}s' -f ($k+1),$Games,$seed,$p.decisions,$watch.Elapsed.TotalSeconds,([double]$p.legacy_setup_ms / 1000.0))
}
$totalWatch.Stop()

function ProfileSum([string]$name) {
    $value = 0.0
    foreach ($p in $profiles) {
        $prop = $p.PSObject.Properties[$name]
        if ($null -ne $prop) { $value += [double]$prop.Value }
    }
    return $value
}
function StageSum([string]$name) {
    $value = 0.0
    foreach ($p in $profiles) {
        if ($null -eq $p.stages_ms) { continue }
        $prop = $p.stages_ms.PSObject.Properties[$name]
        if ($null -ne $prop) { $value += [double]$prop.Value }
    }
    return $value
}

$decisions = ProfileSum 'decisions'
$wall = $totalWatch.Elapsed.TotalSeconds
$legacy = ProfileSum 'legacy_setup_ms'
Write-Host '================ BRWR SETUP PROFILE ================'
Write-Host ('Games: {0}; decisions: {1}; total wall: {2:N2}s; {3:N2}s/game' -f $Games,$decisions,$wall,($wall/$Games))
Write-Host ('Legacy setup: {0:N3}s total = {1:N3}s/game; {2:N1}% of game process wall' -f ($legacy/1000.0), ($legacy/1000.0/$Games), (100.0*$legacy/1000.0/$wall))
Write-Host '--- Breakdown of legacy setup (do not add unrelated measurements) ---'
$stages = @(
    @('scene_load',                   'load(game.tscn)'),
    @('scene_instantiate',            'instantiate scene'),
    @('game_config',                  'configure players/seed'),
    @('root_add_child_and_ready',     'root.add_child(game) / synchronous _ready'),
    @('initial_20_frames',           'initial 20 process_frame waits'),
    @('player_avatar_ready_checks',  'check players and Avatar'),
    @('directories_and_dataset_open','runtime/dataset directory and file open'),
    @('policy_construct',            'construct native policy'),
    @('policy_load_json_and_weights','load policy JSON weights'),
    @('policy_set_seed',             'set policy seed'),
    @('bridge_construct',            'construct AI bridge'),
    @('start_game_flow',             'game.start_game_flow()')
)
foreach ($s in $stages) {
    $ms = StageSum $s[0]
    Write-Host ('  {0,-44} {1,10:N3}s    {2,6:N1}% setup' -f $s[1], ($ms/1000.0), (100.0*$ms/[math]::Max(0.001,$legacy)))
}
$unassigned = ProfileSum 'legacy_setup_unclassified_ms'
Write-Host ('  {0,-44} {1,10:N3}s' -f 'Unclassified setup / profiler overhead', ($unassigned/1000.0))
Write-Host '--- Additional diagnostic (NOT included in legacy setup) ---'
$others = @(
    @('initialize_to_run_ms', 'script initialize -> _run'),
    @('setup_to_first_input_ms', 'setup done -> first input visible'),
    @('setup_to_first_step_ms', 'setup done -> first bridge.step'),
    @('arguments', 'parse command-line arguments'),
    @('episode_start_record', 'write episode_start JSONL')
)
foreach ($s in $others) {
    $ms = if ($s[0] -eq 'arguments' -or $s[0] -eq 'episode_start_record') { StageSum $s[0] } else { ProfileSum $s[0] }
    Write-Host ('  {0,-44} {1,10:N3}s' -f $s[1], ($ms/1000.0))
}
$setupFrames = ProfileSum 'setup_20_frames_count'
Write-Host ('Setup frame count: {0}; average {1:N2}ms/frame' -f $setupFrames, ((StageSum 'initial_20_frames')/[math]::Max(1,$setupFrames)))
Write-Host ('Per-game setup: {0}' -f (($gameRecords | ForEach-Object { '{0}: {1:N2}s' -f $_.seed,$_.setup_s }) -join ' | '))

$summary = [pscustomobject]@{
    games=$Games; decisions=$decisions; process_wall_s=$wall;
    legacy_setup_s=$legacy/1000.0; profiles=$profiles; game_details=$gameRecords
}
$summaryFile = Join-Path $dir 'summary.json'
$summary | ConvertTo-Json -Depth 16 | Set-Content -Path $summaryFile -Encoding UTF8
$hashAfter = (Get-FileHash $checkpoint -Algorithm SHA256).Hash
Write-Host "Summary: $summaryFile"
if ($hashBefore -ne $hashAfter) { throw 'CHECKPOINT MODIFIED - investigate before training!' }
Write-Host 'NATIVE_SETUP_PROFILE_COMPLETE | checkpoint SHA256 unchanged'
Write-Host '===================================================='
