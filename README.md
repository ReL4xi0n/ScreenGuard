# ScreenGuard

Windows'ta 1 dakika hareketsiz kalınca ekranın bulanık bir kopyasını üste koyar. Fare ya da klavyeye dokununca bulanıklık ~250 ms'de kaybolur.

- Klavye kilitlemez; sadece görsel gizlilik sağlar.
- Ekran görüntüsü yalnızca RAM'de tutulur, diske yazılmaz.
- İmleç blur sırasında gizlenir, çıkışta geri gelir.

## Kurulum

```powershell
$d = "$env:LOCALAPPDATA\ScreenGuard"
New-Item -ItemType Directory -Force $d | Out-Null
Copy-Item watch.ps1, launch.vbs $d
Copy-Item launch.vbs "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ScreenGuard.vbs"
Start-Process wscript.exe "`"$d\launch.vbs`""
```

## Ayarlar (`watch.ps1` başı)

| Değişken | Varsayılan | Anlamı |
|---|---|---|
| `$IdleLimit` | 60 | Blur için hareketsizlik süresi (sn) |
| `$Poll` | 2 | Kontrol aralığı (sn) |
| `$BlurScale` | 22 | Büyük = daha bulanık |
| `$FadeMs` | 250 | Geçiş animasyonu (ms) |

## Test

```powershell
powershell -ExecutionPolicy Bypass -File watch.ps1 -TestSeconds 5
```

## Kaldırma

Startup klasöründeki `ScreenGuard.vbs`'yi silin ve `watch.ps1` çalıştıran `powershell.exe` işlemini sonlandırın.
