param(
    [Parameter(Mandatory=$true)]
    [string]$CaFile
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CaFile -PathType Leaf)) {
    throw "CA non trovata: $CaFile"
}

$resolved = (Resolve-Path -LiteralPath $CaFile).Path
Write-Host "Installazione della CA BRWR nel trust store dell'utente corrente:"
Write-Host $resolved

Import-Certificate -FilePath $resolved -CertStoreLocation 'Cert:\CurrentUser\Root' | Out-Null

Write-Host ''
Write-Host 'CA installata. Chiudi completamente Chrome e riaprilo prima del test.'
Write-Host 'Rimuovi questa CA dal trust store quando non ti serve più per lo sviluppo.'
