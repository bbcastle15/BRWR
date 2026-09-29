param(
    [Parameter(Mandatory = $true)][string]$GodotDirectory,
    [string]$Destination
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Destination) { $Destination = Join-Path $projectRoot 'output/BRWR-Windows-playtest.zip' }
if (Test-Path -LiteralPath $Destination) { throw "Archive already exists: $Destination. Choose a new destination." }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
try {
    $files = & git -C $projectRoot ls-files --cached --others --exclude-standard
    foreach ($relative in ($files | Sort-Object -Unique)) {
        if ($relative -match '^(output|\.godot|\.git)/' -or $relative -match '\.(bak|tmp|log)$' -or $relative -match '\.bak\.') { continue }
        $source = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $source, ('brwr/' + $relative.Replace('\','/')), [IO.Compression.CompressionLevel]::Fastest) | Out-Null
    }
    foreach ($binary in Get-ChildItem -LiteralPath $GodotDirectory -File) {
        if ($binary.Extension -notin @('.exe', '.dll', '.txt')) { continue }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $binary.FullName, ('godot/' + $binary.Name), [IO.Compression.CompressionLevel]::Fastest) | Out-Null
    }
    $entry = $archive.CreateEntry('Gioca.cmd')
    $writer = [IO.StreamWriter]::new($entry.Open())
    try {
        $writer.WriteLine('@echo off')
        $writer.WriteLine('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0brwr\tools\update_playtest.ps1" -GodotExecutable "%~dp0godot\Godot_v4.7.2-stable_win64.exe"')
        $writer.WriteLine('if errorlevel 1 pause')
    } finally { $writer.Dispose() }
} finally { $archive.Dispose() }
Get-Item -LiteralPath $Destination | Select-Object FullName, Length
