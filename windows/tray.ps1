param([switch]$Check, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$projectPath = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $projectPath '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) { throw 'Run setup-tray.ps1 first.' }
if ($Check) { Write-Output 'Tray prerequisites OK'; exit 0 }
$mutex = New-Object System.Threading.Mutex($false, 'Local\BrokenSpeakerTray')
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show('Broken Speaker is already available in the notification area. Look under the ^ arrow.', 'Broken Speaker') | Out-Null
    exit
}
$script:server = $null
$script:port = 8000
$script:lastFailure = $null
$script:startTime = $null
$script:qrUrl = $null
$logPath = Join-Path $env:LOCALAPPDATA 'BrokenSpeaker'
New-Item -ItemType Directory -Force -Path $logPath | Out-Null
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Broken Speaker.lnk'

function Get-PhoneLink {
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Connect('1.1.1.1', 80)
        $address = $udp.Client.LocalEndPoint.Address.ToString()
        return "http://${address}:$script:port"
    } catch { return 'No Wi-Fi address found. Connect to your local network.' }
    finally { $udp.Dispose() }
}
function Test-Running { return ($null -ne $script:server -and -not $script:server.HasExited) }
function Update-PhoneQR([string]$url) {
    if ($url -eq $script:qrUrl) { return }
    $qrBox.Visible = $false
    if ($qrBox.Image) { $qrBox.Image.Dispose(); $qrBox.Image = $null }
    $script:qrUrl = $null
    $qrHint.Text = 'Start streaming to show your QR code.'
    if (-not $url.StartsWith('http://')) { return }
    try {
        $pngPath = Join-Path $logPath 'phone-qr.png'
        $qrProcess = Start-Process -FilePath $pythonPath -WorkingDirectory $projectPath -ArgumentList @('-m', 'broken_speaker.qr', ('"' + $url + '"'), ('"' + $pngPath + '"')) -WindowStyle Hidden -PassThru
        if (-not $qrProcess.WaitForExit(5000)) { $qrProcess.Kill(); throw 'QR generation timed out' }
        if ($qrProcess.ExitCode -ne 0) { throw 'QR generation failed' }
        $sourceImage = [System.Drawing.Image]::FromFile($pngPath)
        try { $qrBox.Image = New-Object System.Drawing.Bitmap($sourceImage) } finally { $sourceImage.Dispose() }
        $qrBox.Visible = $true
        $script:qrUrl = $url
        $qrHint.Text = 'Scan with your iPhone camera, then tap the link. Both devices need the same Wi-Fi.'
    } catch { $qrHint.Text = 'QR unavailable. Use the address or run setup-tray.ps1 to repair.' }
}
function Update-Status {
    $active = Test-Running
    if ($null -ne $script:server -and -not $active) {
        $details = Get-Content -LiteralPath (Join-Path $logPath 'server-error.log') -Tail 1 -ErrorAction SilentlyContinue
        $script:lastFailure = "Server exited: $details"
        $script:server = $null
    }
    $startButton.Enabled = -not $active
    $startButton.Text = if ($active) { 'Streaming is on' } else { 'Start streaming' }
    $stopButton.Enabled = $active
    $copyButton.Enabled = $false
    $link.Text = if ($active) { 'Preparing your phone link...' } else { 'Your phone link will appear here' }
    $statusLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#96A9A0')
    if ($active) {
        try {
            $response = Invoke-RestMethod "http://127.0.0.1:$script:port/api/status" -TimeoutSec 1
            $link.Text = Get-PhoneLink
            $copyButton.Enabled = $link.Text.StartsWith('http://')
            $statusLabel.Text = if ($response.error) { "Audio error: $($response.error)" } elseif ($response.clients -gt 0) { "LIVE  /  $($response.clients) connected" } else { 'READY  /  Connect your phone' }
            $statusLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#7DFFAD')
        } catch {
            $statusLabel.Text = 'Starting server...'
            if ($script:startTime -and ((Get-Date) - $script:startTime).TotalSeconds -gt 20) { $statusLabel.Text = 'Startup delayed. Open diagnostics below.' }
        }
    } else {
        $statusLabel.Text = if ($script:lastFailure) { 'START FAILED  /  Open diagnostics below' } else { 'OFFLINE  /  Ready when you are' }
        if ($script:lastFailure) { $link.Text = $script:lastFailure; $statusLabel.ForeColor = [System.Drawing.Color]::Salmon }
    }
    $tray.Text = if ($active) { 'Broken Speaker - streaming available' } else { 'Broken Speaker - stopped' }
    Update-PhoneQR $(if ($copyButton.Enabled) { $link.Text } else { '' })
}
function Start-Audio {
    if (Test-Running) { return }
    try {
        $script:lastFailure = $null
        $script:startTime = Get-Date
        # Do not interrupt another service or an older manually started bridge.
        $selected = $false
        foreach ($candidate in 8000..8010) {
            $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $candidate)
            try { $listener.Start(); $script:port = $candidate; $selected = $true; break }
            catch { }
            finally { $listener.Stop() }
        }
        if (-not $selected) { throw 'Ports 8000-8010 are busy.' }
        $script:server = Start-Process -FilePath $pythonPath -ArgumentList @('-u', '-m', 'broken_speaker', '--port', $script:port) -WorkingDirectory $projectPath -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logPath 'server.log') -RedirectStandardError (Join-Path $logPath 'server-error.log') -PassThru
        Update-Status
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not start audio') | Out-Null }
}
function Stop-Audio {
    # Only stop the exact child process started by this tray instance.
    if (Test-Running) { $script:server.Kill(); $script:server.WaitForExit(3000) | Out-Null }
    $script:server = $null
    $script:lastFailure = $null
    Update-Status
}
function Set-StartupLink {
    if ($startup.Checked) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupLink)
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "' + (Join-Path $PSScriptRoot 'tray.ps1') + '"'
        $shortcut.WorkingDirectory = $projectPath
        $shortcut.WindowStyle = 7
        $shortcut.IconLocation = (Join-Path $PSScriptRoot 'broken-speaker.ico') + ',0'
        $shortcut.Save()
    } elseif (Test-Path -LiteralPath $startupLink) { Remove-Item -LiteralPath $startupLink }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Broken Speaker'
$form.ClientSize = New-Object System.Drawing.Size(850, 510)
$form.AutoScaleMode = 'Dpi'
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B1511')
$form.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F1F7F3')
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$iconPath = Join-Path $PSScriptRoot 'broken-speaker.ico'
$form.Icon = if (Test-Path -LiteralPath $iconPath) { New-Object System.Drawing.Icon($iconPath) } else { [System.Drawing.SystemIcons]::Application }
$eyebrow = New-Object System.Windows.Forms.Label
$eyebrow.Text = 'LOCAL AUDIO  /  BROKEN SPEAKER'
$eyebrow.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$eyebrow.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#7DFFAD')
$eyebrow.SetBounds(30, 26, 500, 24)
$form.Controls.Add($eyebrow)
$heading = New-Object System.Windows.Forms.Label
$heading.Text = 'Your sound. Anywhere nearby.'
$heading.Font = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
$heading.SetBounds(26, 62, 510, 48)
$form.Controls.Add($heading)
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Send laptop audio straight to your phone over Wi-Fi.'
$subtitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#96A9A0')
$subtitle.SetBounds(30, 117, 500, 28)
$form.Controls.Add($subtitle)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$statusLabel.SetBounds(30, 164, 500, 34)
$form.Controls.Add($statusLabel)
$addressCaption = New-Object System.Windows.Forms.Label
$addressCaption.Text = 'TYPE THIS ADDRESS IN SAFARI ON YOUR PHONE'
$addressCaption.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$addressCaption.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#96A9A0')
$addressCaption.SetBounds(30, 211, 500, 24)
$form.Controls.Add($addressCaption)
$link = New-Object System.Windows.Forms.TextBox
$link.SetBounds(30, 245, 500, 36)
$link.Font = New-Object System.Drawing.Font('Segoe UI', 17)
$link.BorderStyle = 'None'
$link.BackColor = $form.BackColor
$link.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#D5FF71')
$link.ReadOnly = $true
$form.Controls.Add($link)
$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = 'Start streaming'
$startButton.SetBounds(30, 308, 218, 48)
$startButton.Add_Click({ Start-Audio })
$form.Controls.Add($startButton)
$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = 'Stop'
$stopButton.SetBounds(260, 308, 90, 48)
$stopButton.Add_Click({ Stop-Audio })
$form.Controls.Add($stopButton)
$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = 'Copy link'
$copyButton.SetBounds(362, 308, 168, 48)
$copyButton.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($link.Text); $statusLabel.Text = 'COPIED  /  Phone link on clipboard' })
$form.Controls.Add($copyButton)
foreach ($button in @($startButton, $stopButton, $copyButton)) {
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#20372C')
    $button.ForeColor = $form.ForeColor
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
}
$startButton.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#7DFFAD')
$startButton.ForeColor = $form.BackColor
$hint = New-Object System.Windows.Forms.Label
$hint.Text = 'Same Wi-Fi. Open the address, then tap Start listening on your phone. Close this window to keep it in the tray.'
$hint.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#96A9A0')
$hint.SetBounds(30, 379, 500, 52)
$form.Controls.Add($hint)
$startup = New-Object System.Windows.Forms.CheckBox
$startup.Text = 'Keep the tray available when I sign in'
$startup.SetBounds(30, 453, 500, 30)
$startup.Checked = Test-Path -LiteralPath $startupLink
$startup.Add_CheckedChanged({ Set-StartupLink })
$form.Controls.Add($startup)
$diagnostics = New-Object System.Windows.Forms.LinkLabel
$diagnostics.Text = 'Open diagnostics'
$diagnostics.LinkColor = [System.Drawing.ColorTranslator]::FromHtml('#96A9A0')
$diagnostics.SetBounds(370, 480, 170, 24)
$diagnostics.Add_LinkClicked({ Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + (Join-Path $logPath 'server-error.log') + '"') })
$form.Controls.Add($diagnostics)
$qrTitle = New-Object System.Windows.Forms.Label
$qrTitle.Text = 'SCAN TO LISTEN'
$qrTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$qrTitle.SetBounds(580, 110, 240, 32)
$form.Controls.Add($qrTitle)
$qrBox = New-Object System.Windows.Forms.PictureBox
$qrBox.SetBounds(580, 154, 232, 232)
$qrBox.SizeMode = 'Zoom'
$qrBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($qrBox)
$qrHint = New-Object System.Windows.Forms.Label
$qrHint.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#96A9A0')
$qrHint.SetBounds(580, 403, 240, 82)
$form.Controls.Add($qrHint)

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $form.Icon
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$showItem = $menu.Items.Add('Open Broken Speaker')
$showItem.Add_Click({ $form.Show(); $form.Activate() })
$startItem = $menu.Items.Add('Start streaming')
$startItem.Add_Click({ Start-Audio; $form.Show(); $form.Activate() })
$stopItem = $menu.Items.Add('Stop streaming')
$stopItem.Add_Click({ Stop-Audio })
$exitItem = $menu.Items.Add('Quit')
$exitItem.Add_Click({ $script:quitting = $true; $form.Close() })
$tray.ContextMenuStrip = $menu
$tray.Add_MouseClick({ param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $form.Show(); $form.Activate() }
})
$script:quitting = $false
$form.Add_FormClosing({ param($sender, $eventArgs)
    if (-not $script:quitting -and $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) { $eventArgs.Cancel = $true; $form.Hide() }
})
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Status })
try {
    Update-Status
    $timer.Start()
    if ($SelfTest) {
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        $startButton.PerformClick()
        Start-Sleep -Seconds 3
        if (-not (Test-Running)) { throw 'Server failed to start. Check server-error.log.' }
        $health = Invoke-RestMethod "http://127.0.0.1:$script:port/health" -TimeoutSec 5
        if ($health.status -ne 'ok') { throw 'Server health check failed.' }
        Update-Status
        if (-not $copyButton.Enabled) { throw 'Phone link was not enabled after startup.' }
        if ($script:qrUrl -ne $link.Text -or -not $qrBox.Visible) { throw 'QR does not match the live phone link.' }
        Update-PhoneQR 'http://192.168.10.20:8001'
        if ($script:qrUrl -ne 'http://192.168.10.20:8001') { throw 'QR did not update for a changed address.' }
        Update-Status
        $copyButton.PerformClick()
        if ([System.Windows.Forms.Clipboard]::GetText() -ne (Get-PhoneLink)) { throw 'Copy link failed.' }
        & $pythonPath (Join-Path $projectPath 'scripts/verify_flow.py') (Get-PhoneLink)
        if ($LASTEXITCODE -ne 0) { throw 'Live audio flow failed.' }
        $form.Close()
        if ($form.Visible) { throw 'Close did not hide the control window.' }
        $showItem.PerformClick()
        if (-not $form.Visible) { throw 'Tray menu failed to reopen the window.' }
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        $preview = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($preview, $form.ClientRectangle)
        $preview.Save((Join-Path $logPath 'tray-preview.png'))
        $preview.Dispose()
        Write-Output ('Server healthy: ' + (Get-PhoneLink))
        $stopButton.PerformClick()
        if (Test-Running) { throw 'Server failed to stop.' }
        Write-Output 'Start/stop lifecycle passed.'
        Write-Output 'Copy link, close-to-tray and tray-menu reopen passed.'
        if ($qrBox.Visible) { throw 'Stopped server left a stale QR visible.' }
        Write-Output 'QR generation, address change and stop clearing passed.'
    } else { [System.Windows.Forms.Application]::Run($form) }
} finally {
    $timer.Stop()
    Stop-Audio
    $tray.Visible = $false
    $tray.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
