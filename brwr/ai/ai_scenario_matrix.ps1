# From the brwr folder containing project.godot:
# powershell -ExecutionPolicy Bypass -File .\ai\ai_scenario_matrix.ps1 -Repetitions 2
param([int]$Repetitions = 2)
$ErrorActionPreference = "Continue"
$godot = "C:\Users\bigba\Desktop\BRWR\playtest\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { throw "Godot not found: $godot" }
if (-not (Test-Path ".\project.godot")) { throw "Run from the brwr folder" }
if ($Repetitions -lt 1) { throw "Repetitions must be positive" }

$scenarios = @()
foreach ($h in 2..6) {
  $scenarios += [pscustomobject]@{ Humans = $h; Avatar = "none"; Difficulty = "apprentice" }
}
foreach ($h in 2..5) {
  foreach ($difficulty in @("apprentice", "master")) {
    $scenarios += [pscustomobject]@{ Humans = $h; Avatar = "possessed"; Difficulty = $difficulty }
  }
}

$rows = foreach ($s in $scenarios) {
  for ($i = 0; $i -lt $Repetitions; $i++) {
    $scenarioId = [array]::IndexOf($scenarios, $s)
    $seed = 20270000 + $scenarioId * 1000 + $i + 1
    $mode = if (($i % 2) -eq 0) { "normal" } else { "swap" }
    $log = & $godot --headless --path . --script res://ai/ai_record_match.gd -- $seed $s.Humans $s.Avatar $s.Difficulty $mode 2>&1
    $exitCode = $LASTEXITCODE
    $complete = $log | Where-Object { "$_" -match '^AI_EPISODE_COMPLETE ' } | Select-Object -Last 1
    $failure = $log | Where-Object { "$_" -match 'AI_EPISODE_STOP|SCRIPT ERROR|Parse Error|Compile Error' } | Select-Object -Last 1
    $status = if ($exitCode -eq 0 -and $complete) { "COMPLETE" } else { "FAILED" }
    $record = [pscustomobject]@{
      Seed = $seed; HumanPlayers = $s.Humans; Avatar = $s.Avatar;
      Difficulty = $s.Difficulty; StyleOrder = $mode; Status = $status;
      ExitCode = $exitCode; Detail = if ($status -eq "COMPLETE") { "$complete" } else { "$failure" }
    }
    Write-Host "$($record.Seed) humans=$($record.HumanPlayers) avatar=$($record.Avatar) difficulty=$($record.Difficulty) mode=$mode $status"
    $record
  }
}
$rows | Export-Csv .\ai\ai_scenario_results.csv -NoTypeInformation -Encoding UTF8
$rows | Group-Object Avatar, Status | Select-Object Name, Count | Format-Table -AutoSize
Write-Host "Wrote ai\ai_scenario_results.csv and episode_*.jsonl in ai\datasets\"
