param([string]$projectRoot, [string]$engineVersion)

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
return $metadata
