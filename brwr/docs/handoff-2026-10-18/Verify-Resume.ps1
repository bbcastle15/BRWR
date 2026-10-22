param(
    [string]$Godot = '',
    [ValidateSet('smoke', 'all')][string]$Suite = 'smoke'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $Godot) {
    $found = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $Godot = $found.Source }
    else {
        $downloads = Join-Path $env:USERPROFILE 'Downloads'
        $folders = Get-ChildItem -LiteralPath $downloads -Directory -Filter 'Godot_v4.7.2*' -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            $found = Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*console.exe' | Select-Object -First 1
            if ($found) { $Godot = $found.FullName; break }
        }
    }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Indica Godot: ./docs/handoff-2026-10-18/Verify-Resume.ps1 -Godot C:/percorso/Godot_v4.7.2-stable_win64_console.exe'
}
$Godot = (Resolve-Path -LiteralPath $Godot).Path
$version = (& $Godot --version | Out-String).Trim()
if ($version -notlike '4.7.2.stable*') { throw "Versione richiesta: Godot 4.7.2 stable. Trovata: $version" }
$logRoot = Join-Path $env:TEMP ('BRWR-resume-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $logRoot | Out-Null
Write-Host "Progetto: $projectRoot"
Write-Host "Motore: $version"
Write-Host "Log: $logRoot"

$jsonFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'data') -File -Filter '*.json'
foreach ($file in $jsonFiles) {
    $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
}
$avatarFiles = @('avatar_commands.json', 'avatar_events.json', 'avatars.json')
foreach ($name in $avatarFiles) {
    $items = @(Get-Content -LiteralPath (Join-Path $projectRoot "data/$name") -Raw | ConvertFrom-Json)
    $ids = @($items | ForEach-Object { $_.id })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw "ID duplicati: $name" }
}
$atlas = Get-Content -LiteralPath (Join-Path $projectRoot 'assets/avatars/possessed/atlas.json') -Raw | ConvertFrom-Json
foreach ($entry in $atlas.PSObject.Properties) {
    $image = Join-Path $projectRoot ('assets/avatars/possessed/' + $entry.Value.file)
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "Asset Avatar mancante: $image" }
}
Write-Host "JSON validi: $($jsonFiles.Count); riferimenti atlas Avatar presenti."

function Assert-GodotResult([string]$Log, [int]$Code) {
    if ($Code -ne 0 -or (Select-String -LiteralPath $Log -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet)) {
        Get-Content -LiteralPath $Log -Tail 50 | Write-Host
        throw "Controllo fallito: $Log (exit $Code)"
    }
}

$importLog = Join-Path $logRoot 'import.log'
& $Godot --headless --log-file (Join-Path $logRoot 'import-engine.log') --path $projectRoot --editor --import --quit *> $importLog
Assert-GodotResult $importLog $LASTEXITCODE
$cases = @('avatar_art_hd', 'avatar_smoke', 'avatar_rules', 'avatar_flow', 'avatar_protections', 'avatar_movement', 'avatar_board_ui', 'avatar_playtest_fixes', 'avatar_publication', 'avatar_jinx_playtest', 'avatar_menu', 'presentations', 'avatar_fourth_playtest', 'mist_playtest')
if ($Suite -eq 'all') { $cases += @('playtest', 'schools', 'alternative_rooms', 'alternative_rooms_ui', 'room_families') }
foreach ($case in $cases) {
    $log = Join-Path $logRoot ($case + '.log')
    Write-Host "Eseguo $case..."
    & $Godot --headless --log-file (Join-Path $logRoot ($case + '-engine.log')) --path $projectRoot --script (Join-Path $PSScriptRoot "checks/$case.gd") *> $log
    Assert-GodotResult $log $LASTEXITCODE
    Get-Content -LiteralPath $log -Tail 2 | Write-Host
}
Write-Host "Verifiche concluse. Log: $logRoot"
Write-Host 'Il passaggio degli smoke test NON certifica il completamento di Possessed. Leggi HANDOFF-AVATAR-2026-10-18.md.'
