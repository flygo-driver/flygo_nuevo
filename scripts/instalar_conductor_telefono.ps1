# Instala app Conductor en el SM A037M liberando espacio primero.
# Uso (PowerShell):
#   cd c:\dev\flygo_nuevo
#   .\scripts\instalar_conductor_telefono.ps1

$ErrorActionPreference = "Continue"
$apkDebug = "build\app\outputs\flutter-apk\app-conductor-debug.apk"
$apkArm64 = "build\app\outputs\flutter-apk\app-conductor-release-arm64-v8a.apk"
$apkArm = "build\app\outputs\flutter-apk\app-conductor-release-armeabi-v7a.apk"

Write-Host "== Dispositivos ==" -ForegroundColor Cyan
adb devices -l
$devs = adb devices | Select-String -Pattern "device$" | Where-Object { $_ -notmatch "List of" }
if (-not $devs) {
  Write-Host "ERROR: No hay telefono. Conecta el USB, acepta depuracion USB y vuelve a correr este script." -ForegroundColor Red
  exit 1
}

Write-Host "`n== Espacio en /data ==" -ForegroundColor Cyan
adb shell df -h /data

Write-Host "`n== Desinstalando builds viejos RAI (libera espacio) ==" -ForegroundColor Cyan
adb uninstall com.flygo.rd2.conductor 2>$null
adb uninstall com.flygo.rd2 2>$null
adb shell pm trim-caches 800M 2>$null

Write-Host "`n== Espacio despues de limpiar ==" -ForegroundColor Cyan
adb shell df -h /data

$apk = $null
if (Test-Path $apkArm64) { $apk = $apkArm64 }
elseif (Test-Path $apkArm) { $apk = $apkArm }
elseif (Test-Path $apkDebug) { $apk = $apkDebug }

if (-not $apk) {
  Write-Host "No hay APK. Compilando conductor release arm64..." -ForegroundColor Yellow
  flutter build apk --release --flavor conductor -t lib/main.dart --split-per-abi --dart-define=APP_FLAVOR=conductor
  if (Test-Path $apkArm64) { $apk = $apkArm64 }
  elseif (Test-Path $apkDebug) { $apk = $apkDebug }
}

if (-not $apk) {
  Write-Host "ERROR: no se encontro APK para instalar." -ForegroundColor Red
  exit 1
}

$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
Write-Host "`n== Instalando $apk ($sizeMb MB) ==" -ForegroundColor Cyan
adb install -r -d $apk
if ($LASTEXITCODE -ne 0) {
  Write-Host "`nFallo la instalacion. Causa tipica: telefono sin espacio." -ForegroundColor Red
  Write-Host "En el SM A037M: Ajustes > Almacenamiento > libera hasta ~1.5 GB libres." -ForegroundColor Yellow
  Write-Host "Luego: adb shell df -h /data   (Avail debe ser >= 1.5G)" -ForegroundColor Yellow
  exit 1
}

Write-Host "`nOK. Abriendo app conductor..." -ForegroundColor Green
adb shell monkey -p com.flygo.rd2.conductor -c android.intent.category.LAUNCHER 1
Write-Host "Listo."
