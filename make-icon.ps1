# Draw a functional speaker/mute symbol; no external asset downloads needed.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap(64, 64)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = 'AntiAlias'
$graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#0B1511'))
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#7DFFAD'))
$points = [System.Drawing.Point[]]@([System.Drawing.Point]::new(10,25),[System.Drawing.Point]::new(22,25),[System.Drawing.Point]::new(35,14),[System.Drawing.Point]::new(35,50),[System.Drawing.Point]::new(22,39),[System.Drawing.Point]::new(10,39))
$graphics.FillPolygon($brush, $points)
$pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#D5FF71'), 5)
$graphics.DrawLine($pen, 44, 26, 56, 38)
$graphics.DrawLine($pen, 56, 26, 44, 38)
$handle = $bitmap.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($handle)
$file = [System.IO.File]::Create((Join-Path $PSScriptRoot 'broken-speaker.ico'))
try { $icon.Save($file) } finally { $file.Dispose(); $graphics.Dispose(); $bitmap.Dispose(); $pen.Dispose(); $brush.Dispose() }
