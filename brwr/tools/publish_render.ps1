param(
    [string]$Godot = "$env:USERPROFILE\Desktop\BRWR-Windows-playtest\godot\Godot_v4.7.2-stable_win64_console.exe",
    [int]$SizeLimit = 1280,
    [double]$LossyQuality = 0.72,
    [int]$ChunkSizeMB = 40,
    [string]$CommitMessage = "Update BRWR web bundle"
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $projectRoot

$buildScript = Join-Path $PSScriptRoot "build_web_render_optimized.ps1"
$outputRoot = Join-Path $projectRoot "output\web"
$bundleRoot = Join-Path $projectRoot "deploy\web_bundle"

Write-Host ""
Write-Host "============================================"
Write-Host " BRWR -> RENDER PUBLISH"
Write-Host "============================================"
Write-Host "Quality: $LossyQuality"
Write-Host "Size limit: $SizeLimit"
Write-Host "Chunk: $ChunkSizeMB MB"
Write-Host ""

if (!(Test-Path $buildScript)) {
    throw "Manca $buildScript"
}

if (!(Test-Path $Godot)) {
    Write-Warning "Godot non trovato nel percorso predefinito."
    Write-Warning "Provo il rilevamento automatico dello script di build."
    $Godot = ""
}

# ============================================================
# 1. BUILD LOCALE - QUELLA NOTA FUNZIONANTE
# ============================================================

Write-Host "=== 1/4 BUILD WEB LOCALE ==="

$buildArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $buildScript,
    "-SizeLimit", $SizeLimit,
    "-LossyQuality", $LossyQuality
)

if ($Godot) {
    $buildArgs += @("-Godot", $Godot)
}

& powershell @buildArgs

if ($LASTEXITCODE -ne 0) {
    throw "Build Web fallita."
}

foreach ($required in @(
    "index.html",
    "index.js",
    "index.wasm",
    "index.pck",
    "index.js.gz",
    "index.wasm.gz",
    "index.pck.gz"
)) {
    $requiredPath = Join-Path $outputRoot $required

    if (!(Test-Path $requiredPath)) {
        throw "Build incompleta: manca $required"
    }
}

# ============================================================
# 2. RICREA COMPLETAMENTE IL BUNDLE
# ============================================================

Write-Host ""
Write-Host "=== 2/4 CREAZIONE BUNDLE ==="

if (Test-Path $bundleRoot) {
    Remove-Item $bundleRoot -Recurse -Force
}

New-Item -ItemType Directory -Force $bundleRoot | Out-Null

$chunkSize = [int64]$ChunkSizeMB * 1MB

function Split-BRWRFile {
    param(
        [string]$Source,
        [string]$DestinationPrefix,
        [int64]$ChunkSize
    )

    $streamIn = [System.IO.File]::OpenRead($Source)

    try {
        $part = 1
        $buffer = New-Object byte[] $ChunkSize
        $totalWritten = [int64]0

        while (($read = $streamIn.Read($buffer, 0, $buffer.Length)) -gt 0) {

            $partPath = "{0}.part{1:D3}" -f $DestinationPrefix, $part
            $streamOut = [System.IO.File]::Create($partPath)

            try {
                $streamOut.Write($buffer, 0, $read)
            }
            finally {
                $streamOut.Dispose()
            }

            $totalWritten += $read
            $part++
        }
    }
    finally {
        $streamIn.Dispose()
    }

    $originalSize = (Get-Item $Source).Length

    if ($totalWritten -ne $originalSize) {
        throw "Errore durante lo split di $Source"
    }
}

Get-ChildItem $outputRoot -File |
Where-Object { $_.Name -notlike "*.import" } |
ForEach-Object {

    $file = $_

    if ($file.Length -le $chunkSize) {

        Copy-Item `
            $file.FullName `
            (Join-Path $bundleRoot $file.Name) `
            -Force

        Write-Host "COPY  $($file.Name)  $([math]::Round($file.Length/1MB,1)) MB"

    } else {

        Write-Host "SPLIT $($file.Name)  $([math]::Round($file.Length/1MB,1)) MB"

        Split-BRWRFile `
            -Source $file.FullName `
            -DestinationPrefix (Join-Path $bundleRoot $file.Name) `
            -ChunkSize $chunkSize
    }
}

# Sicurezza: nessun singolo file deve avvicinarsi a 100 MB
$tooBig = Get-ChildItem $bundleRoot -File |
Where-Object { $_.Length -gt 90MB }

if ($tooBig) {
    Write-Host ""
    Write-Host "FILE TROPPO GRANDI:" -ForegroundColor Red

    $tooBig |
    Select-Object Name,@{N="MB";E={[math]::Round($_.Length/1MB,2)}}

    throw "Bundle non sicuro per GitHub."
}

Write-Host ""
Write-Host "Bundle generato:"

Get-ChildItem $bundleRoot -File |
Sort-Object Name |
Select-Object Name,@{N="MB";E={[math]::Round($_.Length/1MB,2)}} |
Format-Table -AutoSize

# ============================================================
# 3. GIT - SOLO WEB BUNDLE
# ============================================================

Write-Host ""
Write-Host "=== 3/4 COMMIT BUNDLE ==="

Push-Location $repoRoot

try {

    # -A registra anche i file vecchi da eliminare.
    # -f permette i chunk anche se una regola gitignore li intercetta.
    git add -A -f -- brwr/deploy/web_bundle

    git diff --cached --quiet -- brwr/deploy/web_bundle

    if ($LASTEXITCODE -eq 0) {

        Write-Host "Il bundle Web non è cambiato: nessun nuovo commit."

    } else {

        git commit -m $CommitMessage -- brwr/deploy/web_bundle

        if ($LASTEXITCODE -ne 0) {
            throw "Commit bundle fallito."
        }
    }

    # ========================================================
    # 4. PUSH - include anche eventuali commit sorgente già fatti
    # ========================================================

    Write-Host ""
    Write-Host "=== 4/4 PUSH ==="

    git push origin master

    if ($LASTEXITCODE -ne 0) {
        throw "Push fallito."
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " BRWR PUBBLICATO PER RENDER" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Render può ora eseguire l'Auto-Deploy."