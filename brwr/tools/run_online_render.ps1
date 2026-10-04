param(
    [string]$Godot = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$config = Join-Path $projectRoot 'online_server_url.txt'

if (-not (Test-Path -LiteralPath $config)) { throw 'Manca online_server_url.txt' }
$serverUrl = (Get-Content -LiteralPath $config -Raw).Trim()
if (-not $serverUrl -or $serverUrl -like '*YOUR-RENDER-SERVICE*') {
    throw 'Inserisci prima l URL reale di Render in online_server_url.txt'
}

if (-not $Godot) {
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $Godot = $command.Source }
    else {
        $candidate = Get-ChildItem -Path (Join-Path $env:USERPROFILE 'Downloads/Godot_v4.7.2*') -Directory -ErrorAction SilentlyContinue |
            Get-ChildItem -Filter '*console.exe' -File | Select-Object -First 1
        if ($candidate) { $Godot = $candidate.FullName }
    }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Indica Godot 4.7.2 con -Godot C:/percorso/Godot_v4.7.2-stable_win64_console.exe'
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build_web_render.ps1') -Godot $Godot
}

$webRoot = Join-Path $projectRoot 'output/web'
$env:BRWR_ONLINE_BASE = $serverUrl
Write-Host "Server BRWR: $serverUrl"
Write-Host 'Crea sala PvP: il PC host e gli altri giocatori useranno solo connessioni WSS in uscita.'
& $Godot --path $webRoot --main-pack (Join-Path $webRoot 'index.pck') --rendering-method gl_compatibility
