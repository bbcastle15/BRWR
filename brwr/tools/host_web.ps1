param(
    [string]$Godot = '',
    [string]$Cert = '',
    [string]$Key = '',
    [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $projectRoot 'output/web'
$tlsRoot = Join-Path $projectRoot '.tls'

if (-not $Cert) { $Cert = Join-Path $tlsRoot 'brwr-local.crt' }
if (-not $Key) { $Key = Join-Path $tlsRoot 'brwr-local.key' }

if (-not (Test-Path -LiteralPath $Cert -PathType Leaf) -or -not (Test-Path -LiteralPath $Key -PathType Leaf)) {
    throw "Certificato TLS non configurato. Esegui prima: powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\setup_tls.ps1`""
}

# The native host inherits these paths. The files remain outside output/web and
# are never served by web_host.gd.
$env:BRWR_TLS_CERT = (Resolve-Path -LiteralPath $Cert).Path
$env:BRWR_TLS_KEY = (Resolve-Path -LiteralPath $Key).Path

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
    throw 'Indica il motore: ./tools/host_web.ps1 -Godot C:/percorso/Godot_v4.7.2-stable_win64_console.exe'
}
$engineVersion = (& $Godot --version | Out-String).Trim()
if ($engineVersion -notlike '4.7.2.stable*') { throw "Richiesto Godot 4.7.2 stable. Trovato: $engineVersion" }
$template = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable/web_nothreads_release.zip'
if (-not (Test-Path -LiteralPath $template)) {
    throw 'Installa i template ufficiali Godot 4.7.2 da Editor > Gestisci modelli di esportazione, poi riprova.'
}
New-Item -ItemType Directory -Path $webRoot -Force | Out-Null

# Fingerprint the actual working tree, including uncommitted assets. The native
# host below loads this very same exported pack, so it cannot use newer rules
# than the browser bundle served to its guests.
$sources = @(
    Get-ChildItem -LiteralPath $projectRoot -File | Where-Object { $_.Extension -in '.gd', '.tscn', '.tres', '.gdshader', '.godot', '.cfg' }
    Get-ChildItem -Path (Join-Path $projectRoot 'assets'), (Join-Path $projectRoot 'data') -Recurse -File
) | Sort-Object FullName
$hashLines = foreach ($file in $sources) {
    $relative = $file.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    $relative + ':' + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $fingerprint = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($hashLines -join "`n")))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }
$metadata = @{ source = $fingerprint; engine = $engineVersion; built_utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $projectRoot 'web_build.json'), $metadata, $utf8)

Write-Host 'Creazione della versione browser dalle modifiche attuali...'
$buildLog = Join-Path $projectRoot 'output/web-export.log'
& $Godot --headless --path $projectRoot --editor --export-release Web (Join-Path $webRoot 'index.html') *> $buildLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $buildLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
    Get-Content -LiteralPath $buildLog -Tail 50
    throw "Esportazione fallita. Log: $buildLog"
}
foreach ($name in @('index.js', 'index.wasm', 'index.pck')) {
    $source = [IO.File]::OpenRead((Join-Path $webRoot $name))
    $target = [IO.File]::Create((Join-Path $webRoot ($name + '.gz')))
    $gzip = New-Object IO.Compression.GZipStream($target, [IO.Compression.CompressionLevel]::Optimal)
    try { $source.CopyTo($gzip) }
    finally { $gzip.Dispose(); $target.Dispose(); $source.Dispose() }
}
[IO.File]::WriteAllText((Join-Path $webRoot 'build.json'), $metadata, $utf8)
$checkLog = Join-Path $projectRoot 'output/web-export-check.log'
& $Godot --headless --path $webRoot --main-pack (Join-Path $webRoot 'index.pck') --script (Join-Path $PSScriptRoot 'check_web_export.gd') *> $checkLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $checkLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
    Get-Content -LiteralPath $checkLog -Tail 40
    throw "Il pacchetto esportato non supera il controllo: $checkLog"
}
Write-Host "Pronto: $webRoot"
Write-Host "TLS cert: $env:BRWR_TLS_CERT"
if ($BuildOnly) { return }

Write-Host 'Scegli Crea sala PvP. Il link generato sarà HTTPS e il multiplayer userà WSS.'
& $Godot --path $webRoot --main-pack (Join-Path $webRoot 'index.pck') --rendering-method gl_compatibility -- "--web-root=$webRoot"
