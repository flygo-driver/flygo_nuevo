# Instala cliente + conductor (arm64, ~37 MB c/u) en el teléfono de prueba.
# Requiere: USB depuración ON, teléfono desbloqueado, al menos ~1.5 GB libres en /data.

param(
    [string]$DeviceId = "R9PT50FEZ1J"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

Write-Host "=== RAI: instalar apps de prueba (arm64) ===" -ForegroundColor Cyan

adb kill-server | Out-Null
Start-Sleep -Seconds 1
adb start-server | Out-Null
Start-Sleep -Seconds 2

$devices = adb devices 2>&1 | Out-String
if ($devices -notmatch "$DeviceId\s+device") {
    if ($devices -match "$DeviceId\s+unauthorized") {
        Write-Host "ERROR: Teléfono NO autorizado. En el SM A037M aceptá 'Permitir depuración USB' y marcá confiar." -ForegroundColor Red
    } else {
        Write-Host "ERROR: No se ve el dispositivo $DeviceId. Reconectá el cable USB." -ForegroundColor Red
    }
    adb devices
    exit 1
}

$df = adb -s $DeviceId shell df -h /data 2>&1 | Out-String
Write-Host $df
if ($df -match "(\d+)M\s+\d+%") {
    $availMb = [int]$Matches[1]
    if ($availMb -lt 800) {
        Write-Host ""
        Write-Host "ERROR: Almacenamiento interno casi lleno (${availMb} MB libres)." -ForegroundColor Red
        Write-Host "Liberá al menos 1.5 GB en el teléfono:" -ForegroundColor Yellow
        Write-Host "  Ajustes > Almacenamiento > borrar apps/fotos/cache (WhatsApp, etc.)"
        Write-Host "  Reiniciá el teléfono y volvé a ejecutar este script."
        exit 1
    }
}

$ClienteApk = "build\app\outputs\flutter-apk\app-cliente-arm64-v8a-release.apk"
$ConductorApk = "build\app\outputs\flutter-apk\app-conductor-arm64-v8a-release.apk"

if (-not (Test-Path $ClienteApk)) {
    Write-Host "Compilando cliente (arm64)..." -ForegroundColor Yellow
    flutter build apk --release --split-per-abi --flavor cliente -t lib/main.dart --dart-define=FLYGO_SIM_CASA=true
}
if (-not (Test-Path $ConductorApk)) {
    Write-Host "Compilando conductor (arm64)..." -ForegroundColor Yellow
    flutter build apk --release --split-per-abi --flavor conductor -t lib/main.dart --dart-define=FLYGO_SIM_CASA=true
}

Write-Host "Instalando CLIENTE..." -ForegroundColor Green
adb -s $DeviceId install -r $ClienteApk
Write-Host "Instalando CONDUCTOR..." -ForegroundColor Green
adb -s $DeviceId install -r $ConductorApk

Write-Host ""
Write-Host "Instaladas:" -ForegroundColor Cyan
adb -s $DeviceId shell pm list packages | Select-String "flygo"
Write-Host "Listo. Abrí las dos apps en el teléfono." -ForegroundColor Green
