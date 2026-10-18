param(
    [string]$PublicAddress = '',
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tlsRoot = Join-Path $projectRoot '.tls'
$cert = Join-Path $tlsRoot 'brwr-local.crt'
$key = Join-Path $tlsRoot 'brwr-local.key'
$caCopy = Join-Path $tlsRoot 'brwr-dev-rootCA.crt'

$mkcert = Get-Command mkcert -ErrorAction SilentlyContinue
if (-not $mkcert) {
    # WinGet can install mkcert without updating the current shell's PATH.
    $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
        -Recurse -Filter mkcert.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($candidate) {
        $mkcert = $candidate
    }
}
if (-not $mkcert) {
    throw 'mkcert non trovato. Installalo con: winget install -e --id FiloSottile.mkcert'
}

New-Item -ItemType Directory -Path $tlsRoot -Force | Out-Null
[IO.File]::WriteAllText(
    (Join-Path $tlsRoot '.gitignore'),
    "*`n!.gitignore`n",
    (New-Object System.Text.UTF8Encoding($false))
)

if ((Test-Path $cert) -or (Test-Path $key)) {
    if (-not $Force) {
        throw "Esistono già file TLS in $tlsRoot. Usa -Force per rigenerarli."
    }
    Remove-Item -LiteralPath $cert, $key -Force -ErrorAction SilentlyContinue
}

$mkcertExe = if ($mkcert.Source) { $mkcert.Source } else { $mkcert.FullName }

Write-Host 'Installazione/verifica della CA locale mkcert sul PC host...'
& $mkcertExe -install
if ($LASTEXITCODE -ne 0) { throw 'mkcert -install è fallito.' }

$addresses = @('localhost', '127.0.0.1', '::1')
try {
    $lanIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.AddressState -eq 'Preferred'
        } |
        Select-Object -ExpandProperty IPAddress -Unique
    $addresses += $lanIps
} catch {
    Write-Warning 'Non riesco a leggere automaticamente gli IP LAN.'
}

if ($PublicAddress) {
    $addresses += $PublicAddress.Trim()
}

$addresses = $addresses | Where-Object { $_ } | Select-Object -Unique

Write-Host ('Generazione certificato per: ' + ($addresses -join ', '))
& $mkcertExe -cert-file $cert -key-file $key @addresses
if ($LASTEXITCODE -ne 0) { throw 'Generazione certificato mkcert fallita.' }

$caRoot = (& $mkcertExe -CAROOT | Out-String).Trim()
$rootCa = Join-Path $caRoot 'rootCA.pem'
if (-not (Test-Path -LiteralPath $rootCa)) {
    throw "rootCA.pem non trovato in $caRoot"
}
Copy-Item -LiteralPath $rootCa -Destination $caCopy -Force

Write-Host ''
Write-Host 'TLS BRWR pronto.'
Write-Host "Certificato server: $cert"
Write-Host "Chiave privata:       $key"
Write-Host "CA da dare ai client: $caCopy"
if ($PublicAddress) {
    Write-Host "IP/nome pubblico incluso nel certificato: $PublicAddress"
}
Write-Host ''
Write-Host 'IMPORTANTE: non inviare mai brwr-local.key.'
Write-Host 'Se IP LAN o IP pubblico cambiano, rigenera con -Force.'
