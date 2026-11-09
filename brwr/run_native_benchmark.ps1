param([int]$Games = 3)
$ErrorActionPreference = 'Continue'
$godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe'
$python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
if (!(Test-Path '.\project.godot')) { throw 'Esegui dalla cartella brwr che contiene project.godot' }
if (!(Test-Path $godot)) { throw "Godot non trovato: $godot" }
if (!(Test-Path $python)) { throw "Python non trovato: $python" }
if ($Games -lt 1) { throw 'Games deve essere >= 1' }
$checkpoint = '.\ai\model\brwr_policy_v4.pt'
if (!(Test-Path $checkpoint)) { throw "Checkpoint non trovato: $checkpoint" }

Write-Host 'Export PyTorch checkpoint -> Godot weights and parity probes...'
& $python .\ai\python\export_native_policy_v4.py
if ($LASTEXITCODE -ne 0) { throw 'Model export failed' }
Write-Host 'Generate native runner from local up-to-date Godot worker...'
& $python .\make_native_worker.py
if ($LASTEXITCODE -ne 0) { throw 'Runner generation failed' }
Write-Host 'Validate GDScript BLAKE2 and PyTorch feature/logit parity...'
& $godot --headless --path . --script res://ai/ai_native_policy_validation.gd
if ($LASTEXITCODE -ne 0) { throw 'PARITY TEST FAILED - No benchmark started. Send validation output.' }

$cases = @(
    @{ seed=20270491; bots=4; avatar='none'; difficulty='apprentice' },
    @{ seed=20270492; bots=6; avatar='none'; difficulty='apprentice' },
    @{ seed=20270493; bots=3; avatar='possessed'; difficulty='apprentice' }
)
$logs = '.\ai\native_benchmark_logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$totalDecisions = 0
$watch = [System.Diagnostics.Stopwatch]::StartNew()
for ($k=0; $k -lt $Games; $k++) {
    $s = $cases[$k % $cases.Count]
    # Different seed on repeated 3-case block; configuration remains comparable.
    $seed = $s.seed + 3 * [math]::Floor($k / $cases.Count)
    $log = Join-Path $logs ("native_{0:D3}_seed{1}.log" -f ($k+1), $seed)
    $one = [System.Diagnostics.Stopwatch]::StartNew()
    & $godot --headless --path . --script res://ai/ai_policy_native_match.gd -- $seed $s.bots $s.avatar $s.difficulty normal *> $log
    $code = $LASTEXITCODE
    $one.Stop()
    if ($code -ne 0) { Get-Content $log -Tail 30; throw "Native game failed: $log" }
    $endLine = Select-String -Path $log -Pattern 'AI_EPISODE_COMPLETE' | Select-Object -Last 1
    if (!$endLine) { Get-Content $log -Tail 30; throw "Missing completion marker: $log" }
    $m = [regex]::Match($endLine.Line, 'decisions=(\d+)')
    if (!$m.Success) { throw "Cannot parse decision count from $log" }
    $n = [int]$m.Groups[1].Value
    $totalDecisions += $n
    Write-Host ("Game {0}/{1}: seed={2} bots={3} avatar={4} decisions={5} time={6:N2}s" -f ($k+1),$Games,$seed,$s.bots,$s.avatar,$n,$one.Elapsed.TotalSeconds)
}
$watch.Stop()
$seconds = $watch.Elapsed.TotalSeconds
Write-Host '========== NATIVE POLICY BENCHMARK =========='
Write-Host "Games: $Games | Decisions: $totalDecisions"
Write-Host ("Wall time: {0:N2} s | seconds/game: {1:N2}" -f $seconds,($seconds/$Games))
Write-Host ("ms/decision: {0:N2} | games/hour: {1:N1}" -f (1000*$seconds/[math]::Max(1,$totalDecisions)),(3600*$Games/[math]::Max(0.001,$seconds)))
Write-Host "Logs: $logs"
Write-Host 'Checkpoint unchanged. NOTE: stochastic actions differ from Python replay.'
Write-Host '============================================='
