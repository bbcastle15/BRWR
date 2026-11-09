param([int]$Games = 1, [switch]$SummaryOnly)
$ErrorActionPreference = 'Stop'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"

if (!(Test-Path $python)) { throw "Python not found: $python" }

if ($SummaryOnly) {
    $dirs = @(Get-ChildItem '.\ai\runtime_breakdown_logs' -Directory -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending)
    if ($dirs.Count -eq 0) { throw 'No runtime benchmark folders found' }
    $files = @(Get-ChildItem $dirs[0].FullName -Filter 'sidecar_*.txt' -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw 'No saved sidecar references found' }
    $reports = @($files | ForEach-Object { (Get-Content $_.FullName -Raw).Trim() })
    Write-Host "SUMMARY_ONLY no_new_games=1 folder=$($dirs[0].FullName)"
    & $python .\summarize_runtime_breakdown.py @reports
    if ($LASTEXITCODE -ne 0) { throw 'Runtime summary failed' }
    exit 0
}

if (!(Test-Path '.\project.godot')) { throw 'Run from BRWR\brwr directory' }
if (!(Test-Path $godot)) { throw "Godot not found: $godot" }
if (!(Test-Path '.\ai\model\brwr_policy_v4.pt')) { throw 'Policy checkpoint missing' }
if ($Games -lt 1) { throw 'Games must be >= 1' }
$checkpointBefore = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
function RunPython([string]$script) {
    & $python $script
    if ($LASTEXITCODE -ne 0) { throw "Python script failed: $script" }
}
Write-Host 'Export policy and verify native/PyTorch inference...'
RunPython '.\ai\python\export_native_policy_v4.py'
RunPython '.\make_native_worker.py'
& $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'Native/PyTorch parity failure' }

Write-Host 'Rebuild CURRENT cached, UI-guarded worker (source Game remains unchanged)...'
RunPython '.\build_school_cache_variant.py'
RunPython '.\prepare_school_cache.py'
$cached = [System.IO.File]::ReadAllText((Resolve-Path '.\ai\game_school_cached.gd').Path)
if ($cached -notmatch '(?m)^func refresh_all_player_boards\(\)\s*->\s*void:\r?\n\tif not enable_beta_hud:\r?\n\t\treturn') { throw 'Missing original board refresh guard; benchmark aborted.' }
if ($cached -notmatch '(?ms)^func refresh_player_board\([^)]*\)\s*(?:->\s*void)?\s*:\r?\n\tif not enable_beta_hud:\r?\n\t\treturn') { throw 'Missing targeted player board guard; benchmark aborted.' }
if ($cached -notmatch '(?ms)^func _refresh_damage_boards\([^)]*\)\s*(?:->\s*void)?\s*:\r?\n\tif not enable_beta_hud:\r?\n\t\treturn') { throw 'Missing targeted damage board guard; benchmark aborted.' }
Write-Host 'ALL_THREE_UI_GUARDS_VERIFIED'
RunPython '.\build_runtime_breakdown.py'
& $godot --headless --path . --check-only --script res://ai/ai_policy_runtime_breakdown.gd
if ($LASTEXITCODE -ne 0) { throw 'Runtime breakdown worker syntax error' }
Write-Host 'RUNTIME_BREAKDOWN_SYNTAX_OK'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$folder = '.\ai\runtime_breakdown_logs\' + $stamp
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$cases = @(
    @{ seed=20270491; bots=4; avatar='none' },
    @{ seed=20270492; bots=6; avatar='none' },
    @{ seed=20270493; bots=3; avatar='possessed' }
)
function Invoke-Match([string]$worker, [int]$seed, [int]$bots, [string]$avatar, [string]$tag, [bool]$profiled) {
    $log = Join-Path $folder ("{0}_{1}.log" -f $tag, $seed)
    $started = [DateTime]::UtcNow
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $godot --headless --path . --script $worker -- $seed $bots $avatar apprentice normal *> $log
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldEAP
        $watch.Stop()
    }
    if ($exitCode -ne 0) {
        Get-Content $log -Tail 25
        throw "Match failed ($tag): $log"
    }
    $done = Select-String -Path $log -Pattern 'AI_EPISODE_COMPLETE' | Select-Object -Last 1
    $episodeLine = Select-String -Path $log -Pattern '^AI_EPISODE_FILE\s+' | Select-Object -Last 1
    if (!$done -or !$episodeLine) { Get-Content $log -Tail 25; throw "Incomplete match: $log" }
    $episode = ($episodeLine.Line -replace '^AI_EPISODE_FILE\s+', '').Trim()
    if (!(Test-Path $episode)) { throw "Dataset missing: $episode" }
    $sidecar = $null
    if ($profiled) {
        $sidecar = "$episode.runtime_profile.json"
        if (!(Test-Path $sidecar)) { throw "Runtime report missing: $sidecar" }
        if ((Get-Item $sidecar).LastWriteTimeUtc -lt $started.AddSeconds(-2)) { throw "Runtime report is stale: $sidecar" }
        $sidecarRef = Join-Path $folder ("sidecar_{0}_{1}.txt" -f $tag, $seed)
        [System.IO.File]::WriteAllText((Join-Path (Get-Location).Path $sidecarRef), $sidecar, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host ("{0}: seed={1} wall={2:N2}s {3}" -f $tag, $seed, $watch.Elapsed.TotalSeconds, $done.Line.Trim())
    return [pscustomobject]@{ Log=$log; Episode=$episode; Sidecar=$sidecar; Wall=$watch.Elapsed.TotalSeconds }
}

if (!(Test-Path '.\ai\model\playable_schools_cache_v1.json')) {
    Write-Host 'Warming cold school cache outside measurement...'
    $null = Invoke-Match 'res://ai/ai_policy_school_cached_match.gd' 20270491 4 'none' 'warmup' $false
}
Write-Host 'Parity: guarded cached worker versus isolated runtime profiler...'
$baseline = Invoke-Match 'res://ai/ai_policy_school_cached_match.gd' 20270491 4 'none' 'baseline' $false
$all = @()
for ($k = 0; $k -lt $Games; $k++) {
    $c = $cases[$k % $cases.Count]
    $seed = [int]$c.seed + 3 * [int][math]::Floor($k / $cases.Count)
    $tag = 'profile_{0:D3}' -f ($k + 1)
    $entry = Invoke-Match 'res://ai/ai_policy_runtime_breakdown.gd' $seed $c.bots $c.avatar $tag $true
    $all += $entry
    if ($k -eq 0) {
        & $python .\check_school_cache_parity.py $baseline.Episode $entry.Episode
        if ($LASTEXITCODE -ne 0) { throw 'Runtime instrumentation changed actions/state: FAIL' }
    }
}
$reports = @($all | ForEach-Object { $_.Sidecar })
& $python .\summarize_runtime_breakdown.py @reports
if ($LASTEXITCODE -ne 0) { throw 'Runtime summary failed (sidecar files still available)' }
$after = (Get-FileHash '.\ai\model\brwr_policy_v4.pt' -Algorithm SHA256).Hash
if ($checkpointBefore -ne $after) { throw 'Checkpoint was modified!' }
$sumWall = [double](($all | Measure-Object -Property Wall -Sum).Sum)
Write-Host ("RUNTIME_WALL games={0} seconds={1:N2} seconds_per_game={2:N2}" -f $Games,$sumWall,($sumWall/$Games))
Write-Host 'RUNTIME_BREAKDOWN_PARITY_OK | CHECKPOINT_UNCHANGED'
