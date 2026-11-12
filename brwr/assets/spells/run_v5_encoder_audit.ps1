param(
    [string]$Godot = '',
    [string]$Episode = '',
    [switch]$InitV5
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
if (-not (Test-Path $python)) {
    throw "Python environment missing: $python"
}
if (-not (Test-Path '.\ai\python\train.py')) {
    throw 'Missing existing training source ai/python/train.py'
}
Write-Host '1/3 Test isolated v5 Python encoder...'
& $python -m unittest discover -s ai/python -p test_v5_encoder.py -v
if ($LASTEXITCODE -ne 0) { throw 'V5_ENCODER_TESTS_FAILED' }
Write-Host '2/3 Audit actual decision structures (no training)...'
$arguments = @('ai/python/v5_experiment.py', '--probe')
if ($Episode.Trim() -ne '') { $arguments += @('--episode', $Episode) }
& $python @arguments
if ($LASTEXITCODE -ne 0) { throw 'V5_ENCODER_AUDIT_FAILED' }
if ($Godot.Trim() -eq '') {
    $dir = Join-Path $env:USERPROFILE 'Desktop\BRWR-Windows-playtest\godot'
    if (Test-Path $dir) {
        $binary = Get-ChildItem $dir -Filter '*console.exe' -File | Select-Object -First 1
        if ($binary) { $Godot = $binary.FullName }
    }
}
if ($Godot.Trim() -eq '' -or -not (Test-Path $Godot)) {
    if ($InitV5) { throw 'Native v5 encoder validation required before initializing checkpoint. Supply -Godot PATH.' }
    Write-Host 'V5_GODOT_PARITY_SKIPPED Godot binary not found. Use -Godot PATH.'
    exit 0
}
if (-not (Test-Path '.\ai\ai_native_policy_v4.gd')) {
    throw 'Missing v4 native policy; run the existing setup first to generate it.'
}
Write-Host '3/3 Validate semantic encoder parity in Godot (Python versus GDScript)...'
& $Godot --headless --path . --script 'res://ai/ai_v5_encoder_parity.gd'
if ($LASTEXITCODE -ne 0) { throw 'V5_GODOT_ENCODER_PARITY_FAILED; do NOT train v5' }
if ($InitV5) {
    Write-Host 'Initialize separate v5 checkpoint from v4 (no training)...'
    & $python ai/python/v5_experiment.py --init-v5
    if ($LASTEXITCODE -ne 0) { throw 'V5_INITIALIZATION_FAILED' }
}
Write-Host 'V5_PHASE1_COMPLETE old_policy_unchanged=1 no_training=1'
