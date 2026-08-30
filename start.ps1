$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $ProjectDir

if (-not (Test-Path -LiteralPath ".venv\Scripts\python.exe")) {
    Write-Host "Creating the local Python environment..."
    py -3 -m venv .venv
}

Write-Host "Installing/checking dependencies..."
& ".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r requirements.txt

Write-Host "`nStarting Audio Bridge. Allow Python through Windows Firewall if prompted."
& ".venv\Scripts\python.exe" app.py

