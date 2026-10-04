param(
    [string]$Godot = '',
    [int]$SizeLimit = 1280,
    [double]$LossyQuality = 0.72
)

$ErrorActionPreference = 'Stop'

$sourceRoot = Split-Path -Parent $PSScriptRoot
$sourceWebRoot = Join-Path $sourceRoot 'output\web'
$tempRoot = Join-Path $env:TEMP 'BRWR_web_render_optimized'
$tempWebRoot = Join-Path $tempRoot 'output\web'

function Find-Godot {
    param([string]$Requested)

    if ($Requested -and (Test-Path -LiteralPath $Requested -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    $candidate = Get-ChildItem -Path (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2*') -Directory -ErrorAction SilentlyContinue |
        Get-ChildItem -Filter '*console.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($candidate) {
        return $candidate.FullName
    }

    return ''
}

function Set-ImportOption {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )

    $escaped = [Regex]::Escape($Key)
    if ($Content -match "(?m)^$escaped=") {
        return [Regex]::Replace($Content, "(?m)^$escaped=.*$", "$Key=$Value")
    }

    if ($Content -match '(?m)^\[params\]\s*$') {
        return [Regex]::Replace(
            $Content,
            '(?m)^\[params\]\s*$',
            "[params]`r`n$Key=$Value",
            1
        )
    }

    return $Content + "`r`n[params]`r`n$Key=$Value`r`n"
}

function Remove-UnreferencedSourcePhotos {
    param([string]$Root)

    $textExtensions = @('.gd', '.tscn', '.tres', '.json', '.cfg', '.txt')
    $textFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\(\.git|\.godot|output|\.tls|\.multiplayer_relay_backup)\\' -and
            $textExtensions -contains $_.Extension.ToLowerInvariant()
        }

    $corpusBuilder = New-Object System.Text.StringBuilder
    foreach ($file in $textFiles) {
        try {
            [void]$corpusBuilder.AppendLine([IO.File]::ReadAllText($file.FullName))
        } catch {}
    }
    $corpus = $corpusBuilder.ToString()

    $patterns = @(
        'assets\mages\IMG*.jpg',
        'assets\schools\IMG*.jpg'
    )

    foreach ($pattern in $patterns) {
        Get-ChildItem -Path (Join-Path $Root $pattern) -File -ErrorAction SilentlyContinue | ForEach-Object {
            $name = $_.Name
            if ($corpus -notmatch [Regex]::Escape($name)) {
                Write-Host "Escludo dal solo Web build sorgente non referenziata: $($_.FullName.Substring($Root.Length + 1))"
                Remove-Item -LiteralPath $_.FullName -Force
                if (Test-Path -LiteralPath ($_.FullName + '.import')) {
                    Remove-Item -LiteralPath ($_.FullName + '.import') -Force
                }
            } else {
                Write-Warning "Mantengo ${name}: compare nei file del progetto."
            }
        }
    }
}

$Godot = Find-Godot $Godot
if (-not $Godot) {
    throw 'Godot 4.7.2 non trovato. Rilancia con -Godot C:\percorso\Godot_v4.7.2-stable_win64_console.exe'
}

$engineVersion = (& $Godot --version | Out-String).Trim()
if ($engineVersion -notlike '4.7.2.stable*') {
    throw "Richiesto Godot 4.7.2 stable. Trovato: $engineVersion"
}

$template = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable\web_nothreads_release.zip'
if (-not (Test-Path -LiteralPath $template)) {
    throw 'Manca il template Web ufficiale Godot 4.7.2.'
}

if ($SizeLimit -lt 512 -or $SizeLimit -gt 4096) {
    throw 'SizeLimit deve essere tra 512 e 4096.'
}
if ($LossyQuality -lt 0.30 -or $LossyQuality -gt 1.0) {
    throw 'LossyQuality deve essere tra 0.30 e 1.0.'
}

Write-Host ''
Write-Host '=== BRWR WEB OPTIMIZED BUILD ==='
Write-Host "Sorgente intatta: $sourceRoot"
Write-Host "Copia temporanea: $tempRoot"
Write-Host "Texture Web: Lossy, quality=$LossyQuality, max dimension=$SizeLimit"
Write-Host ''

if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

# Copy the project, but never copy build/cache/local-network artefacts.
$null = & robocopy $sourceRoot $tempRoot /MIR /NFL /NDL /NJH /NJS /NP `
    /XD '.git' '.godot' 'output' '.tls' '.multiplayer_relay_backup' `
    /XF 'BRWR_UPNP_*.zip' '*.bak' '*.backup' '*.tmp'

if ($LASTEXITCODE -gt 7) {
    throw "Robocopy fallito con codice $LASTEXITCODE"
}

Remove-UnreferencedSourcePhotos $tempRoot

$assetsRoot = Join-Path $tempRoot 'assets'
if (-not (Test-Path -LiteralPath $assetsRoot)) {
    throw "Cartella assets non trovata nella copia temporanea."
}

$sourceImages = Get-ChildItem -LiteralPath $assetsRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension.ToLowerInvariant() -in @('.png', '.jpg', '.jpeg', '.webp') }

$edited = 0
$missingImport = 0

foreach ($img in $sourceImages) {
    $importPath = $img.FullName + '.import'
    if (-not (Test-Path -LiteralPath $importPath)) {
        $missingImport++
        continue
    }

    $content = [IO.File]::ReadAllText($importPath)

    # Web-only copy: large 2D artwork is imported as lossy WebP, which Godot
    # explicitly recommends for large 2D assets when file size matters.
    $content = Set-ImportOption $content 'compress/mode' '1'
    $qualityText = $LossyQuality.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    $content = Set-ImportOption $content 'compress/lossy_quality' $qualityText
    $content = Set-ImportOption $content 'process/size_limit' $SizeLimit.ToString()

    [IO.File]::WriteAllText($importPath, $content, (New-Object Text.UTF8Encoding($false)))
    $edited++
}

Write-Host "Import texture ottimizzati nella copia temporanea: $edited"
if ($missingImport -gt 0) {
    Write-Warning "$missingImport immagini non hanno un .import esistente: Godot userà le impostazioni predefinite per quelle."
}

New-Item -ItemType Directory -Path $tempWebRoot -Force | Out-Null

$buildLog = Join-Path $tempRoot 'web-render-export.log'
Write-Host ''
Write-Host 'Importo ed esporto la copia Web...'

& $Godot --headless --path $tempRoot --editor --export-release Web (Join-Path $tempWebRoot 'index.html') *> $buildLog

if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $buildLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
    Get-Content -LiteralPath $buildLog -Tail 80
    throw "Esportazione fallita. Log temporaneo: $buildLog"
}

foreach ($name in @('index.js', 'index.wasm', 'index.pck')) {
    $path = Join-Path $tempWebRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "File export mancante: $path"
    }

    $source = [IO.File]::OpenRead($path)
    $target = [IO.File]::Create($path + '.gz')
    $gzip = New-Object IO.Compression.GZipStream(
        $target,
        [IO.Compression.CompressionLevel]::Optimal
    )
    try {
        $source.CopyTo($gzip)
    }
    finally {
        $gzip.Dispose()
        $target.Dispose()
        $source.Dispose()
    }
}

$pck = Join-Path $tempWebRoot 'index.pck'
$pckGz = $pck + '.gz'
$pckMb = [math]::Round((Get-Item -LiteralPath $pck).Length / 1MB, 1)
$pckGzMb = [math]::Round((Get-Item -LiteralPath $pckGz).Length / 1MB, 1)

Write-Host ''
Write-Host "index.pck    : $pckMb MB"
Write-Host "index.pck.gz : $pckGzMb MB"

if (Test-Path -LiteralPath $sourceWebRoot) {
    Remove-Item -LiteralPath $sourceWebRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $sourceWebRoot -Force | Out-Null
$null = & robocopy $tempWebRoot $sourceWebRoot /MIR /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -gt 7) {
    throw "Copia finale output/web fallita con codice $LASTEXITCODE"
}

Write-Host ''
if ((Get-Item -LiteralPath (Join-Path $sourceWebRoot 'index.pck')).Length -gt 95MB -or
    (Get-Item -LiteralPath (Join-Path $sourceWebRoot 'index.pck.gz')).Length -gt 95MB) {
    Write-Warning 'Il PCK è ancora troppo grande per GitHub.'
    Write-Warning 'Riprova senza toccare il progetto, per esempio:'
    Write-Warning '  powershell -ExecutionPolicy Bypass -File .\tools\build_web_render_optimized.ps1 -SizeLimit 1024 -LossyQuality 0.68'
} else {
    Write-Host 'OK: i file principali sono sotto la soglia GitHub di 95 MB.'
    Write-Host 'Ora puoi pubblicare output/web.'
}

Write-Host ''
Write-Host "Build Web finale: $sourceWebRoot"
Write-Host 'Il progetto e gli asset originali NON sono stati modificati.'
