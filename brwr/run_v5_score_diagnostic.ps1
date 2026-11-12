param([string]$Godot = "")
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
if (-not (Test-Path $python)) { throw "Python venv not found: $python" }
if (-not $Godot) {
    $godotDir = Join-Path $env:USERPROFILE 'Desktop\BRWR-Windows-playtest\godot'
    $found = Get-ChildItem -Path $godotDir -Filter '*console.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $Godot = $found.FullName }
}
if (-not (Test-Path $Godot)) { throw 'Godot console not found. Pass -Godot "C:\path\Godot_console.exe"' }
Write-Host '1/2 Generate full 384-feature diagnostic from existing v5 policy probe (NO TRAINING)...'
& $python '.\diagnose_v5_policy_scores.py'
if ($LASTEXITCODE -ne 0) { throw 'Python full-feature diagnostic preparation failed' }
Write-Host '2/2 Compare full features, score and v4 hashed terms in Godot (NO TRAINING)...'
& $Godot --headless --path . --script 'res://ai/ai_v5_score_diagnostic.gd'
if ($LASTEXITCODE -ne 0) { throw 'Godot diagnostic failed to run' }
Write-Host 'V5_SCORE_DIAG_FINISHED | checkpoint unchanged | no training'
