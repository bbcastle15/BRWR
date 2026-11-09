# BRWR -- resume RL training with wall-clock benchmark (Windows PowerShell 5.1).
# Run from the project folder containing project.godot.
# Example: powershell -ExecutionPolicy Bypass -File .\run_timed_training.ps1 -Games 10
param(
    [ValidateRange(1, 1000000)][int]$Games = 10,
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$Godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$Python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'project.godot'))) { throw "Eseguire dalla cartella brwr (project.godot assente): $ProjectRoot" }
if (!(Test-Path -LiteralPath $Godot)) { throw "Godot non trovato: $Godot" }
if (!(Test-Path -LiteralPath $Python)) { throw "Python non trovato: $Python" }
$checkpoint = Join-Path $ProjectRoot 'ai\model\brwr_policy_v4.pt'
if (!(Test-Path -LiteralPath $checkpoint)) { throw "Checkpoint --resume non trovato: $checkpoint" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $ProjectRoot ("ai\timed_train_{0}_{1}.log" -f $Games, $stamp)
$backup = Join-Path $ProjectRoot ("ai\model\brwr_policy_v4_pre_timed_{0}.pt" -f $stamp)
Copy-Item -LiteralPath $checkpoint -Destination $backup -ErrorAction Stop
Write-Host "Training: $Games partite, --resume --apprentice-only"
Write-Host "Checkpoint salvato: $backup"
Write-Host "Log: $log"
$env:PYTHONUNBUFFERED = '1'
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$exitCode = -1
try {
    Push-Location $ProjectRoot
    try {
        # PowerShell 5.1 may treat native stderr as a PowerShell error record.
        # The command output and stderr are still captured in the log.
        $oldErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Python -u '.\ai\python\train.py' --godot "$Godot" --games $Games --apprentice-only --resume *> $log
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorAction
        }
    } finally {
        Pop-Location
    }
} finally {
    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed.TotalSeconds
    $completed = 0
    if (Test-Path -LiteralPath $log) {
        $content = [System.IO.File]::ReadAllText($log)
        $completed = ([regex]::Matches($content, '(?m)^\s*complete:\s*decisions=')).Count
    }
    $avg = if ($completed -gt 0) { $elapsed / $completed } else { 0 }
    $hourly = if ($elapsed -gt 0) { 3600.0 * $completed / $elapsed } else { 0 }
    $summary = @(
        ''
        '========== TRAINING TIME =========='
        ('Games requested:  {0}' -f $Games)
        ('Games completed:  {0}' -f $completed)
        ('Wall time:        {0:N2} seconds' -f $elapsed)
        ('Minutes:          {0:N2}' -f ($elapsed / 60.0))
        ('Seconds/game:     {0:N2}' -f $avg)
        ('Games/hour:       {0:N1}' -f $hourly)
        ('TRAIN_EXIT={0}' -f $exitCode)
        '=================================='
    )
    if (Test-Path -LiteralPath $log) {
        Write-Host 'Ultime righe del trainer:'
        Get-Content -LiteralPath $log -Tail 8
        $summary | Add-Content -LiteralPath $log
    }
    $summary | ForEach-Object { Write-Host $_ }
}
if ($exitCode -ne 0) { exit $exitCode }
