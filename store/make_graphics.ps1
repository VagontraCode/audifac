# Renders the store graphics from the launcher glyph (five rounded bars on
# #1C1C1E, see android/app/src/main/res/drawable/ic_launcher_foreground.xml):
#   store/icon-512.png        Play Store icon
#   store/feature-graphic.png 1024 x 500 feature graphic
# and the iOS / macOS / web app icons (replacing Flutter's defaults).
# Run from the repo root:  powershell -ExecutionPolicy Bypass -File store/make_graphics.ps1
Add-Type -AssemblyName System.Drawing

$bg = [System.Drawing.Color]::FromArgb(255, 0x1C, 0x1C, 0x1E)
# (ASCII only: Windows PowerShell reads scripts as ANSI.)
# Bars in the 108-unit adaptive-icon viewport: centre x, top, bottom (width 7).
$bars = @(@(30, 44, 64), @(42, 36, 72), @(54, 30, 78), @(66, 39, 69), @(78, 46, 62))

function New-RoundedRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Draws the glyph so the 108-unit viewport maps to a square of $size at ($ox, $oy).
function Draw-Glyph($g, [float]$ox, [float]$oy, [float]$size, $color) {
    $s = $size / 108.0
    $brush = New-Object System.Drawing.SolidBrush($color)
    foreach ($b in $bars) {
        $w = 7 * $s
        $path = New-RoundedRect ($ox + ($b[0] - 3.5) * $s) ($oy + $b[1] * $s) $w (($b[2] - $b[1]) * $s) ($w / 2)
        $g.FillPath($brush, $path)
    }
}

function New-Icon([int]$px, [bool]$rounded, [string]$out) {
    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush($bg)
    if ($rounded) { $g.FillPath($brush, (New-RoundedRect 0 0 $px $px ($px * 0.22))) } else { $g.FillRectangle($brush, 0, 0, $px, $px) }
    # The adaptive glyph lives in the central 72/108 of the canvas: enlarge it a bit for flat icons.
    $size = $px * 1.25
    Draw-Glyph $g (($px - $size) / 2) (($px - $size) / 2) $size ([System.Drawing.Color]::White)
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

$root = (Get-Location).Path
New-Item -ItemType Directory -Force "$root/store" | Out-Null

# Play Store icon: full square (Play applies its own mask).
New-Icon 512 $false "$root/store/icon-512.png"

# Feature graphic.
$fw = 1024; $fh = 500
$bmp = New-Object System.Drawing.Bitmap($fw, $fh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point($fw, $fh)), $bg, [System.Drawing.Color]::FromArgb(255, 0x3A, 0x2A, 0x14))
$g.FillRectangle($grad, 0, 0, $fw, $fh)
Draw-Glyph $g 40 70 360 ([System.Drawing.Color]::FromArgb(255, 0xE8, 0xB0, 0x4B))
$title = New-Object System.Drawing.Font('Segoe UI', 76, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sub = New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('audifac', $title, [System.Drawing.Brushes]::White, 400, 150)
$g.DrawString('Your music, every format, perfectly tuned.', $sub, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 255, 255, 255))), 406, 262)
$dot = [char]0xB7
$g.DrawString("FLAC $dot DSD $dot Hi-Res $dot Equalizer $dot Lyrics", $sub, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 255, 255, 255))), 406, 310)
$bmp.Save("$root/store/feature-graphic.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# iOS app icons (square, no transparency: iOS masks them).
$ios = "$root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
if (Test-Path $ios) {
    Get-ChildItem "$ios/*.png" | ForEach-Object {
        $img = [System.Drawing.Image]::FromFile($_.FullName); $px = $img.Width; $img.Dispose()
        New-Icon $px $false $_.FullName
    }
}
# macOS (rounded) and web icons.
$mac = "$root/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if (Test-Path $mac) {
    Get-ChildItem "$mac/*.png" | ForEach-Object {
        $img = [System.Drawing.Image]::FromFile($_.FullName); $px = $img.Width; $img.Dispose()
        New-Icon $px $true $_.FullName
    }
}
foreach ($f in @('Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png')) {
    $p = "$root/web/icons/$f"
    if (Test-Path $p) { $img = [System.Drawing.Image]::FromFile($p); $px = $img.Width; $img.Dispose(); New-Icon $px $false $p }
}
if (Test-Path "$root/web/favicon.png") { New-Icon 32 $true "$root/web/favicon.png" }
Write-Output 'done'
