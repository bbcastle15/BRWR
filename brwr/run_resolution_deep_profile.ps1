param([int]$Games = 1, [switch]$SummaryOnly)
$ErrorActionPreference = 'Stop'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"

# Summarize the MOST RECENT guarded profile run without starting Godot,
# regenerating scenes, invalidating cache or changing the policy checkpoint.
if ($SummaryOnly) {
    if (!(Test-Path $python)) { throw "Python missing: $python" }
    $folders = @(Get-ChildItem '.\ai\resolution_deep_profile_logs' -Directory -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending)
    if ($folders.Count -eq 0) { throw 'No guarded profile log directory found.' }
    $folder = $folders[0]
    $existingLogs = @(Get-ChildItem $folder.FullName -Filter 'profile_*.log' -File | Sort-Object Name | ForEach-Object { $_.FullName })
    if ($existingLogs.Count -eq 0) { throw "No profiled matches in: $($folder.FullName)" }
    Write-Host ("SUMMARIZE_ONLY folder={0} profile_logs={1} no_new_games=1" -f $folder.FullName, $existingLogs.Count)
    & $python .\summarize_resolution_deep_profile.py @existingLogs
    if ($LASTEXITCODE -ne 0) { throw 'Could not summarize saved guarded profiles (error printed above).' }
    exit 0
}

if (!(Test-Path '.\project.godot')) { throw 'Run from BRWR\brwr (project.godot folder).' }
if (!(Test-Path $python)) { throw "Python missing: $python" }
if (!(Test-Path $godot)) { throw "Godot missing: $godot" }
if (!(Test-Path '.\ai\model\brwr_policy_v4.pt')) { throw 'Checkpoint missing' }
if ($Games -lt 1) { throw 'Games must be >= 1' }
$before = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash

function Invoke-PythonChecked([string]$Script) {
    & $python $Script
    if ($LASTEXITCODE -ne 0) { throw "Python failed: $Script" }
}
function Invoke-GodotCheck([string]$ScriptPath) {
    & $godot --headless --path . --check-only --script $ScriptPath
    if ($LASTEXITCODE -ne 0) { throw "Godot syntax check failed: $ScriptPath" }
}

Write-Host 'Export neural network; regenerate native worker and verify numerical parity...'
Invoke-PythonChecked '.\ai\python\export_native_policy_v4.py'
Invoke-PythonChecked '.\make_native_worker.py'
& $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'Neural parity check failed' }

Write-Host 'Rebuild cached AI game with board refresh guard (must already be installed)...'
Invoke-PythonChecked '.\build_school_cache_variant.py'
Invoke-PythonChecked '.\prepare_school_cache.py'

# Fail closed if the opt-in guard is not present. Old school-cache builder
# regenerates an unguarded Game, which would give misleading measurements.
$cached = [System.IO.File]::ReadAllText((Resolve-Path '.\ai\game_school_cached.gd').Path)
$guardPattern = '(?m)^func refresh_all_player_boards\(\)\s*->\s*void:\r?\n\tif not enable_beta_hud:\r?\n\t\treturn'
if ($cached -notmatch $guardPattern) {
    throw 'AI board refresh guard missing! Run apply_ai_board_refresh_guard.py first; no games launched.'
}
Write-Host 'AI_REFRESH_GUARD_VERIFIED'
$targetedRefresh = '(?ms)^func refresh_player_board\([^)]*\)\s*(?:->\s*void)?\s*:\r?\n\tif not enable_beta_hud:\r?\n\t\treturn'
$targetedDamage = '(?ms)^func _refresh_damage_boards\([^)]*\)\s*(?:->\s*void)?\s*:\r?\n\tif not enable_beta_hud:\r?\n\t\treturn'
if ($cached -notmatch $targetedRefresh -or $cached -notmatch $targetedDamage) {
    throw 'AI targeted UI guards missing. Run apply_ai_targeted_ui_guards_v2.py first; no games launched.'
}
Write-Host 'AI_TARGETED_REFRESH_GUARDS_VERIFIED'


Invoke-PythonChecked '.\build_resolution_deep_profile.py'
Invoke-GodotCheck 'res://ai/game_resolution_deep.gd'
Invoke-GodotCheck 'res://ai/ai_policy_resolution_deep.gd'
Write-Host 'RESOLUTION_DEEP_PROFILE_SYNTAX_OK'

$logDir = '.\ai\resolution_deep_profile_logs\' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$cases = @(
    @{seed=20270491; bots=4; avatar='none'},
    @{seed=20270492; bots=6; avatar='none'},
    @{seed=20270493; bots=3; avatar='possessed'}
)

function Invoke-Match([string]$Worker, [int]$Seed, [int]$Bots, [string]$Avatar, [string]$Tag, [bool]$Profiled) {
    $log = Join-Path $logDir ("{0}_{1}.log" -f $Tag,$Seed)
    $started = [DateTime]::UtcNow
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    # Use a temporary change of ErrorActionPreference for native output. PowerShell
    # 5.1 may otherwise treat Godot stderr as a terminating exception.
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $godot --headless --path . --script $Worker -- $Seed $Bots $Avatar apprentice normal *> $log
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldEAP
        $watch.Stop()
    }
    if ($exitCode -ne 0) {
        Get-Content $log -Tail 30
        throw "Godot failed, exit=$exitCode : $log"
    }
    $done = Select-String -Path $log -Pattern 'AI_EPISODE_COMPLETE' | Select-Object -Last 1
    $episodeLine = Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+' | Select-Object -Last 1
    if (!$done -or !$episodeLine) {
        Get-Content $log -Tail 30
        throw "Incomplete episode: $log"
    }
    $episode = ($episodeLine.Line -replace '^AI_EPISODE_FILE\s+', '').Trim()
    if (!(Test-Path $episode)) { throw "Episode JSONL missing: $episode" }
    $sidecar = $null
    if ($Profiled) {
        $sidecar = "$episode.submit_profile.json"
        if (!(Test-Path $sidecar)) { throw "Profile sidecar missing: $sidecar" }
        # Ensures the sidecar was newly generated, not left over from a prior run.
        if ((Get-Item $sidecar).LastWriteTimeUtc -lt $started.AddSeconds(-2)) {
            throw "Profile sidecar is stale: $sidecar"
        }
    }
    Write-Host ("{0}: seed={1} wall={2:N2}s {3}" -f $Tag,$Seed,$watch.Elapsed.TotalSeconds,$done.Line.Trim())
    return [pscustomobject]@{Log=$log; Episode=$episode; Sidecar=$sidecar; Seconds=$watch.Elapsed.TotalSeconds}
}

# Ensure cache is warm so validation artwork loading is not counted in timings.
if (!(Test-Path '.\ai\model\playable_schools_cache_v1.json')) {
    Write-Host 'Warm up a cold school cache once (excluded from profile timings)...'
    $null = Invoke-Match 'res://ai/ai_policy_school_cached_match.gd' 20270491 4 'none' 'cache_warmup' $false
}
Write-Host 'Run a same-seed, same-policy parity reference against the GUARDED baseline...'
$baseline = Invoke-Match 'res://ai/ai_policy_school_cached_match.gd' 20270491 4 'none' 'baseline' $false
$all = @()
for ($k = 0; $k -lt $Games; $k++) {
    $config = $cases[$k % $cases.Count]
    $seed = [int]$config.seed + 3 * [int][math]::Floor($k / $cases.Count)
    $tag = 'profile_{0:D3}' -f ($k+1)
    $entry = Invoke-Match 'res://ai/ai_policy_resolution_deep.gd' $seed $config.bots $config.avatar $tag $true
    $all += $entry
    if ($k -eq 0) {
        & $python .\check_school_cache_parity.py $baseline.Episode $entry.Episode
        if ($LASTEXITCODE -ne 0) { throw 'Profiled match differs from guarded baseline' }
    }
}

# Give the summarizer the verified sidecar files DIRECTLY. This avoids
# Windows PowerShell 5.1's UTF-16 log redirection entirely.
$reports = @($all | ForEach-Object { $_.Sidecar })
& $python .\summarize_resolution_deep_profile.py @reports
if ($LASTEXITCODE -ne 0) { throw 'Submit profile summary failed' }
$sum = [double](($all | Measure-Object Seconds -Sum).Sum)
$after = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
if ($before -ne $after) { throw 'Checkpoint changed unexpectedly!' }
Write-Host ('PROFILE_WALL games={0} seconds={1:N2} seconds_per_game={2:N2}' -f $Games,$sum,($sum/$Games))
Write-Host 'RESOLUTION_DEEP_PROFILE_COMPLETE | checkpoint unchanged'
