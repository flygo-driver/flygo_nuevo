# Deploy completo piloto corporativo + reglas + hosting empresas
# Uso: .\scripts\deploy_corporativo_piloto.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "== Build functions ==" -ForegroundColor Cyan
Set-Location functions
npm run build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Set-Location ..

$funcs = @(
  "scheduledCorporativoAvisosEscalonados",
  "scheduledCorporativoSustitutoChofer",
  "scheduledCorporativoAvisosCodigoVencimiento",
  "scheduledCorporativoViajesSinFinalizar",
  "scheduledCorporativoRutasFijas",
  "scheduledCorporativoCortePeriodos",
  "scheduledCorporativoRecogidaPerdida",
  "choferConfirmarRutaCorporativa",
  "choferConfirmarAbordajePasajeroCorp",
  "encargadoAsignarSustitutoCorporativo",
  "encargadoReenviarCodigoCorporativo",
  "encargadoPublicarRutaCorporativaAhora",
  "sincronizarPlantillaCorporativaEnVivo",
  "propagarCambioHoraCorporativa",
  "taxistaRefrescarOperacionCorporativa",
  "onViajeCorporativoOperacionRefresh",
  "adminActualizarHoraPlantillaCorporativa",
  "adminDistribuirCodigoCorporativo",
  "adminPublicarFeriadosRdAno",
  "adminAsignarSustitutoUrgenteCorp",
  "adminValidarPagoCorporativo",
  "marcarCuentaCorporativoPagada",
  "adminAsignarChoferPlantilla",
  "validarConflictosChoferCorporativo",
  "adminCalendarioChoferCorporativo",
  "iniciarViajeSeguro",
  "registrarLegMultiparadaSeguro",
  "finalizarViajeSeguro"
) -join ","

Write-Host "== Deploy functions ($($funcs.Split(',').Count)) ==" -ForegroundColor Cyan
firebase deploy --only "functions:$funcs" --project flygo-rd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== Deploy firestore rules ==" -ForegroundColor Cyan
firebase deploy --only firestore:rules --project flygo-rd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== Build web + hosting ==" -ForegroundColor Cyan
flutter build web --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
firebase deploy --only hosting --project flygo-rd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Deploy piloto corporativo OK." -ForegroundColor Green
