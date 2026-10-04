param(
    [string]$Godot = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $projectRoot 'output/web'

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

$engineVersion = (& $Godot --version | Out-String).Trim()
if ($engineVersion -notlike '4.7.2.stable*') {
    throw "Richiesto Godot 4.7.2 stable. Trovato: $engineVersion"
}

$template = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable/web_nothreads_release.zip'
if (-not (Test-Path -LiteralPath $template)) {
    throw 'Manca il template Web ufficiale Godot 4.7.2.'
}

New-Item -ItemType Directory -Path $webRoot -Force | Out-Null

Write-Host 'Esporto BRWR Web per Render...'
$buildLog = Join-Path $projectRoot 'output/web-render-export.log'
& $Godot --headless --path $projectRoot --editor --export-release Web (Join-Path $webRoot 'index.html') *> $buildLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $buildLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
    Get-Content -LiteralPath $buildLog -Tail 60
    throw "Esportazione fallita. Log: $buildLog"
}

foreach ($name in @('index.js', 'index.wasm', 'index.pck')) {
    $path = Join-Path $webRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "File export mancante: $path" }
    $source = [IO.File]::OpenRead($path)
    $target = [IO.File]::Create($path + '.gz')
    $gzip = New-Object IO.Compression.GZipStream($target, [IO.Compression.CompressionLevel]::Optimal)
    try { $source.CopyTo($gzip) }
    finally { $gzip.Dispose(); $target.Dispose(); $source.Dispose() }
}

$tooLarge = Get-ChildItem -LiteralPath $webRoot -Recurse -File | Where-Object { $_.Length -gt 95MB }
if ($tooLarge) {
    Write-Warning 'Uno o più file dell export superano 95 MB. GitHub può rifiutarli senza LFS:'
    $tooLarge | ForEach-Object { Write-Warning ("  {0}  {1:N1} MB" -f $_.FullName, ($_.Length / 1MB)) }
}

Write-Host "Web build pronto: $webRoot"
Write-Host 'Per pubblicarlo su Render: git add -f output/web && git commit && git push'
