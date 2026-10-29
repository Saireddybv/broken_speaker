$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $projectPath '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) {
    py -3 -m venv (Join-Path $projectPath '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Install Python for Windows, then run setup again.' }
}
& $pythonPath -m pip install --disable-pip-version-check -r (Join-Path $projectPath 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
& $pythonPath -c 'import fastapi, pydantic_core._pydantic_core, pyaudiowpatch, uvicorn'
if ($LASTEXITCODE -ne 0) {
    & $pythonPath -m pip install --force-reinstall --no-cache-dir -r (Join-Path $projectPath 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Dependency repair failed.' }
    & $pythonPath -c 'import fastapi, pydantic_core._pydantic_core, pyaudiowpatch, uvicorn'
    if ($LASTEXITCODE -ne 0) { throw 'Python dependencies are still broken. Setup stopped.' }
}
& (Join-Path $PSScriptRoot 'make-icon.ps1')
$shell = New-Object -ComObject WScript.Shell
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Broken Speaker.lnk'
$shortcut = $shell.CreateShortcut($desktopLink)
$shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "' + (Join-Path $PSScriptRoot 'tray.ps1') + '"'
$shortcut.WorkingDirectory = $projectPath
$shortcut.WindowStyle = 7
$shortcut.IconLocation = (Join-Path $PSScriptRoot 'broken-speaker.ico') + ',0'
$shortcut.Description = 'Control laptop audio streaming from the Windows notification area'
$shortcut.Save()
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Broken Speaker.lnk'
if (Test-Path -LiteralPath $startupLink) {
    $startupShortcut = $shell.CreateShortcut($startupLink)
    # Refresh target too, so sign-in shortcuts from older folder layouts keep working.
    $startupShortcut.TargetPath = $shortcut.TargetPath
    $startupShortcut.Arguments = $shortcut.Arguments
    $startupShortcut.WorkingDirectory = $shortcut.WorkingDirectory
    $startupShortcut.IconLocation = $shortcut.IconLocation
    $startupShortcut.Save()
}
Write-Host 'Ready. Open Broken Speaker on your Desktop. Start streaming when needed.'
