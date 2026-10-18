# Crops store/raw/*.png (phone screenshots) into store/screenshots/: Play
# rejects screenshots longer than twice their width, so the status bar and
# gesture bar are trimmed to reach exactly 2:1.
# Run from the repo root:  powershell -ExecutionPolicy Bypass -File store/crop_screenshots.ps1
Add-Type -AssemblyName System.Drawing
$root = (Get-Location).Path
New-Item -ItemType Directory -Force "$root/store/screenshots" | Out-Null
Get-ChildItem "$root/store/raw/*.png" | ForEach-Object {
    $src = [System.Drawing.Image]::FromFile($_.FullName)
    $w = $src.Width; $h = [Math]::Min($src.Height, 2 * $w)
    $top = [int](($src.Height - $h) / 2)
    $dst = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), (New-Object System.Drawing.Rectangle(0, $top, $w, $h)), [System.Drawing.GraphicsUnit]::Pixel)
    $dst.Save("$root/store/screenshots/$($_.Name)", [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $dst.Dispose(); $src.Dispose()
    Write-Output "$($_.Name): ${w}x$h"
}
