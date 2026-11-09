# BRWR profiling benchmark; PowerShell 5.1 compatible, non-training.
# Copy this script and both profile_*.py files into the project root (brwr).
# Example: powershell -ExecutionPolicy Bypass -File .\run_profiling.ps1 -Games 3
param(
    [ValidateRange(1, 20)][int]$Games = 3,
    [int]$Seed = 20280101,
    [string]$Godot = 'C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$Python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'project.godot'))) {
    throw "Metti gli script nella cartella brwr contenente project.godot: $ProjectRoot"
}
if (!(Test-Path -LiteralPath $Python)) { throw "Python non trovato: $Python" }
if (!(Test-Path -LiteralPath $Godot)) { throw "Godot non trovato: $Godot" }
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'ai\model\brwr_policy_v4.pt'))) {
    throw 'Checkpoint non trovato: ai\model\brwr_policy_v4.pt'
}
Write-Host 'Profiling isolato: NON allena la rete; NON modifica il checkpoint o training_history.csv.'
Write-Host 'Non eseguire contemporaneamente un altro trainer: i file IPC sono condivisi.'
Push-Location $ProjectRoot
try {
    & $Python -u '.\profile_worker_patch.py'
    if ($LASTEXITCODE -ne 0) { throw "Impossibile generare worker profilato: exit $LASTEXITCODE" }
    $env:PYTHONUNBUFFERED = '1'
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Python -u '.\profile_simulation.py' --godot "$Godot" --games $Games --seed $Seed
        $code = $LASTEXITCODE
    } finally {
        $watch.Stop()
        Write-Host ('Wall time PowerShell: {0:N2} s' -f $watch.Elapsed.TotalSeconds)
    }
    if ($code -ne 0) { throw "Profiling non completato: exit $code" }
} finally {
    Pop-Location
}
