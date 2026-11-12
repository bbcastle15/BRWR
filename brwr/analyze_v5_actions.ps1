param([string]$Episode = '')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Join-Path $env:USERPROFILE 'ai-env\Scripts\python.exe'
if (-not (Test-Path $python)) { throw ('Python venv missing: ' + $python) }
$cli = @('.\ai\python\audit_v5_episode_actions.py')
if ($Episode.Trim() -ne '') { $cli += @('--episode', $Episode) }
& $python @cli
if ($LASTEXITCODE -ne 0) { throw ('Action audit failed, code=' + $LASTEXITCODE) }
