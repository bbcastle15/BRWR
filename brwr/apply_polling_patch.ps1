# BRWR -- polling patch for the CURRENT project files (Windows PowerShell 5.1 compatible).
# Run from the folder containing project.godot:
# powershell -ExecutionPolicy Bypass -File .\apply_polling_patch.ps1
param(
    [string]$ProjectRoot = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$trainPath = Join-Path $ProjectRoot 'ai\python\train.py'
$godotPath = Join-Path $ProjectRoot 'ai\ai_policy_match.gd'

if (!(Test-Path (Join-Path $ProjectRoot 'project.godot'))) { throw "ProjectRoot non contiene project.godot: $ProjectRoot" }
foreach ($f in @($trainPath, $godotPath)) {
    if (!(Test-Path -LiteralPath $f)) { throw "File non trovato: $f" }
}

$pyOld = 'time.sleep(0.02)'
$pyNew = 'time.sleep(0.001)'
$gdOld = 'await create_timer(0.02).timeout'
$gdNew = 'await process_frame'
$pyText = [System.IO.File]::ReadAllText($trainPath)
$gdText = [System.IO.File]::ReadAllText($godotPath)
$pyCount = ([regex]::Matches($pyText, [regex]::Escape($pyOld))).Count
$gdCount = ([regex]::Matches($gdText, [regex]::Escape($gdOld))).Count

if ($pyCount -eq 0 -and $gdCount -eq 0 -and $pyText.Contains($pyNew) -and $gdText.Contains($gdNew)) {
    Write-Host 'La patch risulta gia applicata. Nessun file modificato.'
    exit 0
}
if ($pyCount -ne 2 -or $gdCount -ne 1) {
    throw "Numero di righe inatteso: Python=$pyCount (atteso 2), Godot=$gdCount (atteso 1). Nessuna modifica effettuata."
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pyBak = "$trainPath.before_polling_$stamp.bak"
$gdBak = "$godotPath.before_polling_$stamp.bak"
Copy-Item -LiteralPath $trainPath -Destination $pyBak -ErrorAction Stop
Copy-Item -LiteralPath $godotPath -Destination $gdBak -ErrorAction Stop

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($trainPath, $pyText.Replace($pyOld, $pyNew), $utf8NoBom)
[System.IO.File]::WriteAllText($godotPath, $gdText.Replace($gdOld, $gdNew), $utf8NoBom)

Write-Host 'Patch applicata:'
Write-Host '  train.py: 2 polling sleep da 20ms a 1ms'
Write-Host '  ai_policy_match.gd: attesa Godot al frame successivo'
Write-Host "Backup Python: $pyBak"
Write-Host "Backup Godot:  $gdBak"
