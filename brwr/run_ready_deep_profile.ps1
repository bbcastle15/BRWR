param(
    [int]$Games = 3,
    [switch]$SkipParity
)

$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
$checkpoint = '.\ai\model\brwr_policy_v4.pt'
if (!(Test-Path '.\project.godot')) { throw 'Esegui dalla cartella BRWR\brwr, contenente project.godot.' }
if (!(Test-Path $godot)) { throw "Godot non trovato: $godot" }
if (!(Test-Path $python)) { throw "Python non trovato: $python" }
if (!(Test-Path $checkpoint)) { throw "Checkpoint non trovato: $checkpoint" }
if ($Games -lt 1) { throw '-Games deve essere >= 1' }
$before = (Get-FileHash $checkpoint -Algorithm SHA256).Hash

Write-Host 'Export model weights and regenerate native worker...'
& $python .\ai\python\export_native_policy_v4.py
if ($LASTEXITCODE -ne 0) { throw 'Export failed' }
& $python .\make_native_worker.py
if ($LASTEXITCODE -ne 0) { throw 'Native worker generation failed' }
if (!$SkipParity) {
    & $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
    if ($LASTEXITCODE -ne 0) { throw 'Parity failed' }
}
Write-Host 'Build isolated game.gd and game.tscn copies with detailed _ready() timing...'
& $python .\build_ready_deep_profile.py
if ($LASTEXITCODE -ne 0) { throw 'Profiler build failed; originals untouched' }
# Check the generated GDScript syntax BEFORE running a simulation.
# This catches mixed tab/space indentation immediately instead of hanging.
$parseLog = '.\ai\ready_deep_profile_syntax.log'
& $godot --headless --path . --script res://ai/game_ready_deep_profile.gd --check-only *> $parseLog
$parseExit = $LASTEXITCODE
$parseErrors = @(Select-String -Path $parseLog -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script' -ErrorAction SilentlyContinue)
if ($parseExit -ne 0 -or $parseErrors.Count -gt 0) {
    Get-Content $parseLog -Tail 35
    throw "Generated GDScript syntax check failed (exit=$parseExit). No games launched."
}
Write-Host 'READY_DEEP_SYNTAX_OK'

$cases = @(
    @{seed=20270491; bots=4; avatar='none'; difficulty='apprentice'},
    @{seed=20270492; bots=6; avatar='none'; difficulty='apprentice'},
    @{seed=20270493; bots=3; avatar='possessed'; difficulty='apprentice'}
)
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = Join-Path '.\ai\ready_deep_profile_logs' $runId
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$allStages = @()
$allRoots = @()
$allGames = @()
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
for ($k = 0; $k -lt $Games; $k++) {
    $config = $cases[$k % $cases.Count]
    $seed = [int]($config.seed + 3 * [math]::Floor($k / $cases.Count))
    $log = Join-Path $logDir ('ready_{0:D3}_seed{1}.log' -f ($k+1), $seed)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script res://ai/ai_policy_native_ready_deep_profile.gd -- $seed $config.bots $config.avatar $config.difficulty normal *> $log
    $exit = $LASTEXITCODE
    $sw.Stop()
    if ($exit -ne 0) { Get-Content $log -Tail 50; throw "Godot failed (exit=$exit): $log" }
    $bad = Select-String -Path $log -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:' | Select-Object -First 1
    if ($bad) { Get-Content $log -Tail 40; throw "Godot script error: $log" }
    $complete = Select-String -Path $log -Pattern '^AI_EPISODE_COMPLETE ' | Select-Object -Last 1
    $rootLine = Select-String -Path $log -Pattern '^BRWR_READY_DEEP_ROOT_JSON ' | Select-Object -Last 1
    $stageLines = @(Select-String -Path $log -Pattern '^BRWR_READY_DEEP_STAGE_JSON ')
    if (!$complete -or !$rootLine -or $stageLines.Count -lt 20) {
        Get-Content $log -Tail 50
        throw "Missing profile/completion markers: $log"
    }
    $rootData = $rootLine.Line.Substring('BRWR_READY_DEEP_ROOT_JSON '.Length) | ConvertFrom-Json
    $rootData | Add-Member -NotePropertyName seed -NotePropertyValue $seed
    $allRoots += $rootData
    foreach ($l in $stageLines) {
        $stage = $l.Line.Substring('BRWR_READY_DEEP_STAGE_JSON '.Length) | ConvertFrom-Json
        $allStages += [pscustomobject]@{seed=$seed; stage=$stage.stage; duration_ms=[double]$stage.duration_ms}
    }
    $match = [regex]::Match($complete.Line, 'decisions=(\d+)')
    $decisions = if ($match.Success) { [int]$match.Groups[1].Value } else { -1 }
    $allGames += [pscustomobject]@{seed=$seed; decisions=$decisions; wall_s=$sw.Elapsed.TotalSeconds; log=$log}
    Write-Host ('Game {0}/{1}: seed={2} decisions={3} wall={4:N2}s root.add_child={5:N2}s' -f ($k+1),$Games,$seed,$decisions,$sw.Elapsed.TotalSeconds,([double]$rootData.root_add_ms/1000.0))
}
$swTotal.Stop()

Write-Host '================ BRWR _READY DEEP PROFILE ================'
Write-Host ('Games: {0}; wall: {1:N2}s; {2:N2}s/game' -f $Games,$swTotal.Elapsed.TotalSeconds,($swTotal.Elapsed.TotalSeconds/$Games))
$rootTotal = ($allRoots | Measure-Object -Property root_add_ms -Sum).Sum
$beforeTotal = ($allRoots | Where-Object { $_.before_game_ready_ms -ge 0 } | Measure-Object -Property before_game_ready_ms -Sum).Sum
$preAwaitTotal = ($allRoots | Where-Object { $_.game_ready_to_first_await_ms -ge 0 } | Measure-Object -Property game_ready_to_first_await_ms -Sum).Sum
Write-Host ('root.add_child overall: {0:N3}s; before game._ready: {1:N3}s; game._ready until first await: {2:N3}s' -f ($rootTotal/1000.0),($beforeTotal/1000.0),($preAwaitTotal/1000.0))
Write-Host '--- _ready phases, largest first ---'
$stageGroups = $allStages | Group-Object stage | ForEach-Object {
    $sum = ($_.Group | Measure-Object -Property duration_ms -Sum).Sum
    [pscustomobject]@{stage=$_.Name; total_s=$sum/1000.0; per_game_s=$sum/1000.0/$Games}
} | Sort-Object total_s -Descending
$stageGroups | Select-Object -First 18 | Format-Table stage, @{L='Total_s';E={'{0:N3}' -f $_.total_s}}, @{L='Seconds_per_game';E={'{0:N3}' -f $_.per_game_s}} -AutoSize
$summary = [pscustomobject]@{games=$allGames; roots=$allRoots; stages=$allStages; grouped_stages=$stageGroups; process_wall_s=$swTotal.Elapsed.TotalSeconds}
$summaryPath = Join-Path $logDir 'summary.json'
$summary | ConvertTo-Json -Depth 15 | Set-Content -Path $summaryPath -Encoding UTF8
$after = (Get-FileHash $checkpoint -Algorithm SHA256).Hash
if ($after -ne $before) { throw 'CHECKPOINT MODIFIED: investigate immediately!' }
Write-Host "Summary: $summaryPath"
Write-Host 'READY_DEEP_PROFILE_COMPLETE | checkpoint SHA256 unchanged'
Write-Host '==========================================================='
