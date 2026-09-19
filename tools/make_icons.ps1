# P4 Phase1 icon pipeline:
#  1. Rasterize Mihon launcher icon (background/foreground/monochrome/startIcon) via GDI+
#  2. Copy material-symbols SVGs into app resources as dark/white two-set app icons
# Reference repo is read-only; all output goes into this project.
param(
  [string]$RefRoot = "D:\project\reference\mihon-main",
  [string]$ProjRoot = "D:\project\mihon",
  [int]$LauncherSize = 512
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$EntryMedia = Join-Path $ProjRoot "entry\src\main\resources\base\media"
$AppMedia = Join-Path $ProjRoot "AppScope\resources\base\media"

# ---------- SVG path data -> GDI+ GraphicsPath (M/L/H/V/C/Z, abs+rel, implicit repeats) ----------
function ConvertTo-GraphicsPath {
  param([string]$PathData, [double]$Scale)
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
  $cx = 0.0; $cy = 0.0; $sx = 0.0; $sy = 0.0
  $cmdMatches = [regex]::Matches($PathData, '([MLHVCSQTAZmlhvcsqtaz])([^MLHVCSQTAZmlhvcsqtaz]*)')
  foreach ($m in $cmdMatches) {
    $c = $m.Groups[1].Value
    $upper = $c.ToUpperInvariant()
    $rel = ($c -ceq $c.ToLowerInvariant())
    $nums = @()
    foreach ($nm in [regex]::Matches($m.Groups[2].Value, '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')) {
      $nums += [double]$nm.Value
    }
    if ($upper -eq 'M') {
      for ($i = 0; $i + 1 -lt $nums.Count; $i += 2) {
        $x = $nums[$i]; $y = $nums[$i + 1]
        if ($rel) { $x += $cx; $y += $cy }
        if ($i -eq 0) {
          $gp.StartFigure(); $sx = $x; $sy = $y; $cx = $x; $cy = $y
        } else {
          $gp.AddLine([float]($cx * $Scale), [float]($cy * $Scale), [float]($x * $Scale), [float]($y * $Scale))
          $cx = $x; $cy = $y
        }
      }
    } elseif ($upper -eq 'L') {
      for ($i = 0; $i + 1 -lt $nums.Count; $i += 2) {
        $x = $nums[$i]; $y = $nums[$i + 1]
        if ($rel) { $x += $cx; $y += $cy }
        $gp.AddLine([float]($cx * $Scale), [float]($cy * $Scale), [float]($x * $Scale), [float]($y * $Scale))
        $cx = $x; $cy = $y
      }
    } elseif ($upper -eq 'H') {
      foreach ($v in $nums) {
        $x = $v; if ($rel) { $x += $cx }
        $gp.AddLine([float]($cx * $Scale), [float]($cy * $Scale), [float]($x * $Scale), [float]($cy * $Scale))
        $cx = $x
      }
    } elseif ($upper -eq 'V') {
      foreach ($v in $nums) {
        $y = $v; if ($rel) { $y += $cy }
        $gp.AddLine([float]($cx * $Scale), [float]($cy * $Scale), [float]($cx * $Scale), [float]($y * $Scale))
        $cy = $y
      }
    } elseif ($upper -eq 'C') {
      for ($i = 0; $i + 5 -lt $nums.Count; $i += 6) {
        $x1 = $nums[$i]; $y1 = $nums[$i + 1]; $x2 = $nums[$i + 2]; $y2 = $nums[$i + 3]; $x = $nums[$i + 4]; $y = $nums[$i + 5]
        if ($rel) { $x1 += $cx; $y1 += $cy; $x2 += $cx; $y2 += $cy; $x += $cx; $y += $cy }
        $gp.AddBezier([float]($cx * $Scale), [float]($cy * $Scale), [float]($x1 * $Scale), [float]($y1 * $Scale),
          [float]($x2 * $Scale), [float]($y2 * $Scale), [float]($x * $Scale), [float]($y * $Scale))
        $cx = $x; $cy = $y
      }
    } elseif ($upper -eq 'Z') {
      $gp.CloseFigure(); $cx = $sx; $cy = $sy
    } else {
      throw "Unsupported path command: $c"
    }
  }
  return $gp
}

# ---------- extract <path> elements from Android vector drawable ----------
function Get-VectorPaths {
  param([string]$XmlPath)
  $raw = Get-Content $XmlPath -Raw
  $result = @()
  foreach ($pm in [regex]::Matches($raw, '<path\b[^>]*>')) {
    $tag = $pm.Value
    $pd = [regex]::Match($tag, 'android:pathData\s*=\s*"([^"]*)"').Groups[1].Value
    $fc = [regex]::Match($tag, 'android:fillColor\s*=\s*"([^"]*)"').Groups[1].Value
    if ($fc -eq '' -or $pd -eq '') { continue }
    $ft = [regex]::Match($tag, 'android:fillType\s*=\s*"([^"]*)"').Groups[1].Value
    $result += ,@{ d = $pd; fill = $fc; type = $ft }
  }
  return ,$result
}

function Save-Png {
  param($Bitmap, [string]$Path)
  $dir = Split-Path $Path -Parent
  if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

# ---------- 1. Launcher icons ----------
$drawableDir = Join-Path $RefRoot "app\src\main\res\drawable"
$bgPaths = Get-VectorPaths (Join-Path $drawableDir "ic_launcher_background.xml")
$fgPaths = Get-VectorPaths (Join-Path $drawableDir "ic_launcher_foreground.xml")
$monoPaths = Get-VectorPaths (Join-Path $drawableDir "ic_launcher_monochrome.xml")
if ($bgPaths.Count -lt 1 -or $fgPaths.Count -lt 1 -or $monoPaths.Count -lt 1) { throw "Failed to extract launcher paths" }

$scale = $LauncherSize / 432.0
$bgGps = @()
foreach ($p in $bgPaths) {
  $gp = ConvertTo-GraphicsPath $p.d $scale
  if ($p.type -eq 'evenOdd') { $gp.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate }
  else { $gp.FillMode = [System.Drawing.Drawing2D.FillMode]::Winding }
  $bgGps += ,@{ gp = $gp; brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($p.fill)) }
}
$fgGp = ConvertTo-GraphicsPath $fgPaths[0].d $scale
$fgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($fgPaths[0].fill))
$monoGp = ConvertTo-GraphicsPath $monoPaths[0].d $scale
$monoBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

function New-Bitmap {
  param([int]$Size)
  return New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

# background.png (opaque)
$bmp = New-Bitmap $LauncherSize
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
foreach ($p in $bgGps) { $g.FillPath($p.brush, $p.gp) }
$g.Dispose()
Save-Png $bmp (Join-Path $EntryMedia "background.png"); $bmp.Dispose()
Copy-Item (Join-Path $EntryMedia "background.png") (Join-Path $AppMedia "background.png") -Force

# foreground.png (transparent, glyph only)
$bmp = New-Bitmap $LauncherSize
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillPath($fgBrush, $fgGp)
$g.Dispose()
Save-Png $bmp (Join-Path $EntryMedia "foreground.png"); $bmp.Dispose()
Copy-Item (Join-Path $EntryMedia "foreground.png") (Join-Path $AppMedia "foreground.png") -Force

# monochrome.png (transparent, white glyph)
$bmp = New-Bitmap $LauncherSize
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillPath($monoBrush, $monoGp)
$g.Dispose()
Save-Png $bmp (Join-Path $EntryMedia "monochrome.png"); $bmp.Dispose()

# startIcon.png (bg + fg composite, opaque)
$bmp = New-Bitmap $LauncherSize
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
foreach ($p in $bgGps) { $g.FillPath($p.brush, $p.gp) }
$g.FillPath($fgBrush, $fgGp)
$g.Dispose()
Save-Png $bmp (Join-Path $EntryMedia "startIcon.png"); $bmp.Dispose()

Write-Output "Launcher icons done ($LauncherSize px): background/foreground/monochrome/startIcon"

# ---------- 2. App-internal icons (material-symbols SVG two-set copy) ----------
$symRoot = Join-Path $RefRoot "icons\material-symbols\src\main\valkyrieResources"
$rounded = @('collections_bookmark', 'new_releases', 'schedule', 'explore', 'more_vert',
  'search', 'filter_list', 'refresh', 'download', 'settings', 'close', 'add', 'delete',
  'delete_sweep', 'share', 'select_all', 'deselect', 'done_all', 'done', 'bookmark',
  'cancel', 'error', 'warning', 'info', 'view_module', 'keyboard_arrow_right',
  'keyboard_arrow_left', 'expand_more', 'expand_less', 'push_pin', 'public', 'query_stats',
  'storage', 'arrow_upward', 'arrow_downward', 'visibility', 'visibility_off', 'cloud_off',
  'file_download_off', 'sync', 'autorenew', 'image', 'content_copy', 'drag_handle',
  'travel_explore', 'palette', 'screen_rotation', 'hourglass_empty', 'photo', 'edit', 'folder')
$autoMirrored = @('arrow_back', 'arrow_forward', 'sort', 'view_list', 'open_in_new', 'label')
$filled = @('bookmark:bookmark_filled', 'check_circle:check_circle', 'pause:pause',
  'play_arrow:play_arrow', 'push_pin:push_pin_filled', 'favorite:favorite')

$jobs = @()
foreach ($n in $rounded) { $jobs += ,@{ file = "$symRoot\rounded\$n.svg"; name = $n } }
foreach ($n in $autoMirrored) { $jobs += ,@{ file = "$symRoot\autoMirroredRounded\$n.svg"; name = $n } }
foreach ($pair in $filled) {
  $srcName = $pair.Split(':')[0]; $dstName = $pair.Split(':')[1]
  $jobs += ,@{ file = "$symRoot\roundedFilled\$srcName.svg"; name = $dstName }
}

$darkColor = '#333333'; $whiteColor = '#FFFFFF'
$count = 0
foreach ($job in $jobs) {
  if (!(Test-Path -LiteralPath $job.file)) { Write-Output "MISSING: $($job.file)"; continue }
  $raw = Get-Content -LiteralPath $job.file -Raw
  $d = [regex]::Match($raw, '<path[^>]*\bd\s*=\s*"([^"]+)"').Groups[1].Value
  if ($d -eq '') { Write-Output "NO PATH DATA: $($job.file)"; continue }
  $vb = [regex]::Match($raw, 'viewBox\s*=\s*"([^"]+)"').Groups[1].Value
  $vbp = $vb -split '[\s,]+'
  $minY = [double]$vbp[1]; $w = [double]$vbp[2]; $h = [double]$vbp[3]
  if ($minY -ne 0) { $w = [double]$vbp[2]; }
  foreach ($variant in @(@{ suffix = ''; color = $darkColor }, @{ suffix = '_w'; color = $whiteColor })) {
    $inner = '<path fill="{0}" d="{1}"/>' -f $variant.color, $d
    $useT = $minY
    if ($minY -ne 0) { $inner = '<g transform="translate(0,{0})">{1}</g>' -f ([string](-$minY)), $inner }
    $out = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 {0} {1}">{2}</svg>' -f $w, $h, $inner
    $outPath = Join-Path $EntryMedia ("ic_{0}{1}.svg" -f $job.name, $variant.suffix)
    [System.IO.File]::WriteAllText($outPath, $out, (New-Object System.Text.UTF8Encoding($false)))
    $count++
  }
}
Write-Output "App icons done: $count svg files written to entry media"
Write-Output "DONE"
