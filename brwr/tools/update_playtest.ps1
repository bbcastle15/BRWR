param(
    [string]$GodotExecutable,
    [string]$Repository = 'https://github.com/bbcastle15/BRWR.git',
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'BRWR/playtest'),
    [switch]$UpdateOnly
)
$ErrorActionPreference = 'Stop'
function Invoke-GitChecked {
    param([string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Aggiornamento Git fallito. Controlla connessione e accesso al repository.' }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Installa Git per Windows, poi riapri Gioca.cmd.'
}
if (-not $UpdateOnly -and -not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw 'Eseguibile Godot non trovato. Estrai tutto lo ZIP prima di avviare Gioca.cmd.'
}
$InstallDirectory = [IO.Path]::GetFullPath($InstallDirectory)
New-Item -ItemType Directory -Force -Path (Split-Path $InstallDirectory) | Out-Null
# Keep the lock until the game exits: another launcher must not update a running game.
$lock = $null
try {
    $lock = [IO.File]::Open(($InstallDirectory + '.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (-not (Test-Path -LiteralPath $InstallDirectory)) {
        Invoke-GitChecked -Arguments @('clone', '--single-branch', '--branch', 'master', $Repository, $InstallDirectory)
    } else {
        $root = Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'rev-parse', '--show-toplevel')
        if ([IO.Path]::GetFullPath($root).TrimEnd('\', '/') -ne $InstallDirectory.TrimEnd('\', '/')) { throw 'La directory non e un clone dedicato del playtest.' }
        $remote = Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'remote', 'get-url', 'origin')
        if ($remote -ne $Repository) { throw 'Repository inatteso nella cartella del playtest.' }
        $branch = Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'branch', '--show-current')
        if ($branch -ne 'master') { throw 'Il playtest deve usare il branch master.' }
        $changes = Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'status', '--porcelain')
        if ($changes) { throw 'Il clone del playtest contiene modifiche locali. Non verranno sovrascritte.' }
        Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'fetch', 'origin', 'master')
        $ahead = Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'rev-list', '--count', 'origin/master..HEAD')
        if ([int]$ahead -gt 0) { throw 'Il clone contiene commit locali. Aggiornamento interrotto.' }
        Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'merge', '--ff-only', 'origin/master')
    }
    $revision = Invoke-GitChecked -Arguments @('-C', $InstallDirectory, 'rev-parse', '--short', 'HEAD')
    Write-Host "BRWR aggiornato: $revision"
    if (-not $UpdateOnly) {
        $project = Join-Path $InstallDirectory 'brwr'
        $engine = [IO.Path]::GetFullPath($GodotExecutable)
        $import = Start-Process -FilePath $engine -ArgumentList "--path `"$project`" --editor --headless --import" -WindowStyle Hidden -Wait -PassThru
        if ($import.ExitCode -ne 0) { throw 'Importazione Godot fallita.' }
        $log = Join-Path (Split-Path $InstallDirectory) 'playtest.log'
        Start-Process -FilePath $engine -ArgumentList "--path `"$project`" --rendering-method gl_compatibility --log-file `"$log`"" -WindowStyle Hidden -Wait
    }
} finally {
    if ($lock) { $lock.Dispose() }
}
