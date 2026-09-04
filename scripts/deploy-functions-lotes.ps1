# Despliega Cloud Functions en lotes para no superar cuota CPU de Cloud Run (us-central1).
# Uso:
#   .\scripts\deploy-functions-lotes.ps1
#   .\scripts\deploy-functions-lotes.ps1 -Grupo finanzas
#   .\scripts\deploy-functions-lotes.ps1 -Grupo release-110
#   .\scripts\deploy-functions-lotes.ps1 -Grupo corporativo-fallidas -TamanoLote 1 -PausaSegundos 90

param(
    [ValidateSet('corporativo-fallidas', 'finanzas', 'release-110', 'corporativo-billing', 'endurecimiento-produccion')]
    [string]$Grupo = 'corporativo-fallidas',
    [int]$TamanoLote = 2,
    [int]$PausaSegundos = 75
)

$ErrorActionPreference = 'Continue'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# Lote corporativo: desplegar de a 1–2 (cuota CPU Cloud Run en deploy masivo).
$corporativoFallidas = @(
    'encargadoDarDeBajaEmpresaCorporativa',
    'encargadoEliminarRutaCorporativa',
    'encargadoOcultarViajeHistorialCorporativo',
    'encargadoPublicarRutaCorporativaAhora',
    'onCorporativoPlantillaRutaSinChoferAlert',
    'propagarCambioHoraCorporativa',
    'scheduledAutoClosePoolsPostDeparture',
    'scheduledCleanupExpiredPoolReservations',
    'scheduledCorporativoAvisosCodigoVencimiento',
    'scheduledCorporativoExpirarSinCodigo',
    'scheduledCorporativoRutasFijas',
    'scheduledCorporativoSustitutoChofer',
    'scheduledNotifyCorporativoChoferRutaFija',
    'scheduledNotifyPoolOwnerDepartureDay',
    'sincronizarPlantillaCorporativaEnVivo',
    'taxistaAbrirViajeCorporativoEnCurso',
    'taxistaAsegurarViajeRutaCorporativa',
    'taxistaRefrescarOperacionCorporativa',
    'scheduledCorporativoAvisosEscalonados',
    'scheduledCorporativoRecogidaPerdida'
)

$finanzas = @(
    'setComisionPorcentaje',
    'finalizarViajeSeguro',
    'aprobarLiquidacionSemanal',
    'generarLiquidacionSemanalTaxista',
    'generarLiquidacionesSemanales',
    'cancelarLiquidacionSemanal',
    'obtenerLiquidacionSemanalTaxista'
)

$release110 = @(
    'crearViajePendienteCliente',
    'actualizarMetodoPagoViaje',
    'reservarSiguienteViaje',
    'aceptarViajeSeguro',
    'approveRecargaComision',
    'rejectRecargaComision',
    'promoverSiguienteViaje'
)

$corporativoBilling = @(
    'scheduledCorporativoCortePeriodos',
    'marcarLiquidacionCorporativoPagada',
    'adminValidarPagoCorporativo',
    'scheduledCorporativoRutasFijas'
)

# Prepago estricto + PIN autoritativo + contraofertas Bola.
# Orden intencional: primero las funciones sin acoplamiento, y al final el bloque que
# lee/escribe `usuarios.tienePagoPendiente`, para acortar la ventana en la que una
# función vieja podría desmarcar el bloqueo que otra nueva acaba de poner.
$endurecimientoProduccion = @(
    'enviarPropuestaBolaSegura',
    'updateComisionPrepagoConfig',
    'approveRecargaComision',
    'rejectRecargaComision',
    'sincronizarBloqueoOperativoTaxista',
    'onBilleteraTaxistaWritten',
    'onViajesPoolCommissionWritten',
    'scheduledReconcileBloqueoPrepagoTaxistas',
    'aceptarViajeSeguro',
    'reservarSiguienteViaje',
    'promoverSiguienteViaje',
    'finalizarViajeSeguro',
    'azulCreateRecargaTaxistaSession',
    'azulVerifyRecargaTaxista',
    'crearPoolGira'
)

switch ($Grupo) {
    'endurecimiento-produccion' { $lista = $endurecimientoProduccion }
    'finanzas' { $lista = $finanzas }
    'release-110' { $lista = $release110 }
    'corporativo-billing' { $lista = $corporativoBilling }
    default { $lista = $corporativoFallidas }
}

Write-Host '=== Deploy functions en lotes ===' -ForegroundColor Cyan
Write-Host "Grupo: $Grupo | Funciones: $($lista.Count) | Lote: $TamanoLote | Pausa: ${PausaSegundos}s"
Write-Host "Directorio: $repoRoot"
Write-Host ''

$fallidas = [System.Collections.Generic.List[string]]::new()
$ok = 0

for ($i = 0; $i -lt $lista.Count; $i += $TamanoLote) {
    $end = [Math]::Min($i + $TamanoLote - 1, $lista.Count - 1)
    $lote = $lista[$i..$end]
    $only = ($lote | ForEach-Object { "functions:$_" }) -join ','
    $numLote = [int]($i / $TamanoLote) + 1
    $totalLotes = [Math]::Ceiling($lista.Count / $TamanoLote)

    Write-Host "[$numLote/$totalLotes] $($lote -join ', ')" -ForegroundColor Yellow

    firebase deploy --only $only
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  FALLO' -ForegroundColor Red
        foreach ($f in $lote) { $fallidas.Add($f) }
    } else {
        Write-Host '  OK' -ForegroundColor Green
        $ok += $lote.Count
    }

    if ($i + $TamanoLote -lt $lista.Count) {
        Write-Host "  Pausa ${PausaSegundos}s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $PausaSegundos
    }
}

Write-Host ''
Write-Host '=== Resumen ===' -ForegroundColor Cyan
Write-Host "OK: $ok / $($lista.Count)"
if ($fallidas.Count -gt 0) {
    Write-Host "Fallidas: $($fallidas -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "Grupo $Grupo desplegado." -ForegroundColor Green
exit 0
