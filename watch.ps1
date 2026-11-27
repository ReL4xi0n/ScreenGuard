# ScreenGuard v7 (blur): 1 dk hareketsizlikte ekranin bulanik kopyasini uste koyar.
# Cikis: herhangi bir hareket -> bulanik katman ~250ms'de seffaflasarak kaybolur (netlesme hissi).
# Klavye kilidi YOK. Ekran goruntusu sadece RAM'de, diske yazilmaz.
# -TestSeconds N : test modu; N sn sonra kendiliginden kapanir.

param([int]$TestSeconds = 0)

$IdleLimit  = 60    # saniye (hareketsizlik esigi)
$Poll       = 2     # saniye (kontrol araligi)
$BlurScale  = 22    # buyuk = daha bulanik
$FadeMs     = 250   # cikis animasyonu suresi (ms)
$Base       = "$env:LOCALAPPDATA\ScreenGuard"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Native {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")] static extern uint GetTickCount();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetSystemCursor(IntPtr hcur, uint id);
    [DllImport("user32.dll")] static extern IntPtr CreateCursor(IntPtr hInst, int x, int y, int w, int h, byte[] andMask, byte[] xorMask);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint p1, IntPtr p2, uint flags);
    static readonly uint[] Ids = { 32512, 32513, 32514, 32515, 32516, 32642, 32643, 32644, 32645, 32646, 32648, 32649, 32650, 32651 };
    // Tum sistem imleclerini seffaf imlecle degistir
    public static void HideCursors() {
        byte[] andMask = new byte[128]; byte[] xorMask = new byte[128];
        for (int i = 0; i < 128; i++) { andMask[i] = 0xFF; xorMask[i] = 0x00; }
        foreach (uint id in Ids) {
            IntPtr blank = CreateCursor(IntPtr.Zero, 0, 0, 32, 32, andMask, xorMask);
            SetSystemCursor(blank, id);
        }
    }
    // Kullanicinin imlec semasini geri yukle
    public static void RestoreCursors() { SystemParametersInfo(0x0057, 0, IntPtr.Zero, 0); }
    public static uint IdleSeconds() {
        LASTINPUTINFO l = new LASTINPUTINFO();
        l.cbSize = (uint)Marshal.SizeOf(l);
        if (!GetLastInputInfo(ref l)) return 0;
        return (GetTickCount() - l.dwTime) / 1000;
    }
}
'@

try { [Native]::SetProcessDPIAware() | Out-Null } catch {}
try { [Native]::RestoreCursors() } catch {}   # onceki calisma yarim kaldiysa imlecleri geri getir

function Get-BlurredScreen {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $sharp = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
    $g = [System.Drawing.Graphics]::FromImage($sharp)
    $g.CopyFromScreen($vs.X, $vs.Y, 0, 0, $sharp.Size)
    $g.Dispose()

    # Kenarlar beyaz/net kalmasin diye kenar piksellerini aynala
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)

    $sw = [Math]::Max(1, [int]($vs.Width / $BlurScale))
    $sh = [Math]::Max(1, [int]($vs.Height / $BlurScale))
    $small = New-Object System.Drawing.Bitmap $sw, $sh
    $gs = [System.Drawing.Graphics]::FromImage($small)
    $gs.InterpolationMode = 'HighQualityBilinear'
    $gs.DrawImage($sharp, (New-Object System.Drawing.Rectangle 0,0,$sw,$sh), 0, 0, $sharp.Width, $sharp.Height, 'Pixel', $attr)
    $gs.Dispose()
    $sharp.Dispose()

    $out = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
    $go = [System.Drawing.Graphics]::FromImage($out)
    $go.InterpolationMode = 'HighQualityBilinear'
    $go.PixelOffsetMode   = 'Half'
    $go.DrawImage($small, (New-Object System.Drawing.Rectangle 0,0,$vs.Width,$vs.Height), 0, 0, $sw, $sh, 'Pixel', $attr)
    $go.Dispose()
    $small.Dispose()
    $attr.Dispose()
    return $out, $vs
}

function Show-Blur {
    param([int]$AutoCloseSec = 0)
    $img, $vs = Get-BlurredScreen

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition   = 'Manual'
    $f.Bounds          = $vs
    $f.TopMost         = $true
    $f.ShowInTaskbar   = $false
    $f.BackgroundImage = $img
    $f.BackgroundImageLayout = 'None'
    $f.Opacity         = 0.0     # gorunmez acilir; resim arkada cizilir, satir satir render gorunmez
    # Cift tampon: resim tek seferde basilsin
    try {
        $dbProp = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance')
        $dbProp.SetValue($f, $true, $null)
    } catch {}

    $MaxOp = 0.995
    $script:closing = $false
    $script:elapsed = 0
    $script:phase   = 'in'      # in = belirme, out = kaybolma
    $script:fromOp  = 0.0
    $sw = New-Object System.Diagnostics.Stopwatch

    # Giris ve cikis: zamana gore opaklik gecisi (sure sabit, akici)
    $anim = New-Object System.Windows.Forms.Timer
    $anim.Interval = 10
    $anim.Add_Tick({
        try {
            $t = [Math]::Min(1.0, $sw.Elapsed.TotalMilliseconds / $FadeMs)
            $ease = $t * $t * (3 - 2 * $t)          # smoothstep
            if ($script:phase -eq 'in') {
                $f.Opacity = $MaxOp * $ease
                if ($t -ge 1.0) { $f.Opacity = $MaxOp; $anim.Stop() }
            } else {
                if ($t -ge 1.0) { $anim.Stop(); $f.Close(); return }
                $f.Opacity = $script:fromOp * (1 - $ease)
            }
        } catch { try { $f.Close() } catch {} }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100
    $timer.Add_Tick({
        try {
            if ($script:closing) { return }
            $script:elapsed += 0.1
            $trigger = ([Native]::IdleSeconds() -lt 2) -or ($AutoCloseSec -gt 0 -and $script:elapsed -ge $AutoCloseSec)
            if ($trigger) {
                $script:closing = $true
                $timer.Stop()
                [Native]::RestoreCursors()
                $script:fromOp = $f.Opacity          # giris yarim kaldiysa oradan sonsun
                $script:phase  = 'out'
                $sw.Restart()
                $anim.Start()
            }
        } catch { try { $f.Close() } catch {} }
    })

    $f.Add_Shown({
        try {
            $f.Activate(); $f.Refresh()               # gorunmezken tamamen ciz
            [Native]::HideCursors()
            $script:phase = 'in'
            $sw.Restart(); $anim.Start()              # yumusak belirme
            $timer.Start()
        } catch {}
    })
    $f.Add_FormClosed({ try { $timer.Stop(); $anim.Stop(); [Native]::RestoreCursors() } catch {} })

    [void]$f.ShowDialog()
    $timer.Dispose(); $anim.Dispose(); $f.Dispose()
    $img.Dispose()
}

if ($TestSeconds -gt 0) {
    Show-Blur -AutoCloseSec $TestSeconds
    "TEST OK: bulanik ekran acildi ve kapandi." | Set-Content "$Base\test.txt" -Encoding UTF8
    exit
}

while ($true) {
    try {
        if ([Native]::IdleSeconds() -ge $IdleLimit) { Show-Blur }
    } catch {
        try { [Native]::RestoreCursors() } catch {}
    }
    Start-Sleep -Seconds $Poll
}
