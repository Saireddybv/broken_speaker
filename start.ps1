$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $ProjectDir

if (-not (Test-Path -LiteralPath ".venv\Scripts\python.exe")) {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        Write-Host "Python was not found. Install Python 3.11 or newer from https://www.python.org/downloads/windows/" -ForegroundColor Red
        Write-Host "(keep 'py launcher' ticked in the installer), then run this again."
        exit 1
    }
    Write-Host "First run: creating the local Python environment..."
    py -3 -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw "Could not create the Python environment." }
}

Write-Host "Installing/checking dependencies..."
& ".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed. Check your internet connection and try again." }

Write-Host "`nStarting Broken Speaker. Allow Python through Windows Firewall on Private networks if prompted."
Write-Host "Press Ctrl+C to stop.`n"
& ".venv\Scripts\python.exe" app.py @args
