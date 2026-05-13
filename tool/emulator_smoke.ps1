# Smoke: tests ligeros (sin datos sensibles). Opcional: emuladores Firebase.
# Uso desde la raíz del repo:
#   pwsh ./tool/emulator_smoke.ps1
# Con Firestore emulator (requiere `firebase` CLI y firebase.json):
#   pwsh ./tool/emulator_smoke.ps1 -UseEmulators

param([switch]$UseEmulators)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if ($UseEmulators) {
  Write-Host "[emulator_smoke] Ejecutando flutter test con Firestore emulator..."
  firebase emulators:exec --only firestore "flutter test test/smoke/rai_utils_test.dart"
} else {
  Write-Host "[emulator_smoke] flutter test (sin emulador)..."
  flutter test test/smoke/rai_utils_test.dart
}
