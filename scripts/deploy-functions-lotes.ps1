# Despliega Cloud Functions en lotes para no superar cuota CPU de Cloud Run (us-central1).
# Uso:
#   .\scripts\deploy-functions-lotes.ps1
#   .\scripts\deploy-functions-lotes.ps1 -Grupo finanzas
#   .\scripts\deploy-functions-lotes.ps1 -Grupo corporativo-fallidas -TamanoLote 1 -PausaSegundos 90

param(
    [ValidateSet('corporativo-fallidas', 'finanzas')]
    [string]$Grupo = 'corporativo-fallidas',
    [int]$TamanoLote = 2,
    [int]$PausaSegundos = 75
)

$ErrorActionPreference = 'Continue'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$corporativoFallidas = @(
    'scheduledCorporativoAvisosCodigoVencimiento',
    'taxistaRefrescarOperacionCorporativa',
    'encargadoPublicarRutaCorporativaAhora',
    'onCorporativoPlantillaRutaSinChoferAlert',
    'scheduledCorporativoAvisosEscalonados',
    'scheduledCorporativoRecogidaPerdida',
    'scheduledCorporativoSustitutoChofer',
    'scheduledNotifyCorporativoChoferRutaFija'
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

$lista = if ($Grupo -eq 'finanzas') { $finanzas } else { $corporativoFallidas }

Write-Host "=== Deploy functions en lotes ===" -ForegroundColor Cyan
Write-Host "Grupo: $Grupo | Funciones: $($lista.Count) | Lote: $TamanoLote | Pausa: ${PausaSegundos}s"
Write-Host "Directorio: $repoRoot"
Write-Host ""

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
        Write-Host "  FALLÓ" -ForegroundColor Red
        foreach ($f in $lote) { $fallidas.Add($f) }
    } else {
        Write-Host "  OK" -ForegroundColor Green
        $ok += $lote.Count
    }

    if ($i + $TamanoLote -lt $lista.Count) {
        Write-Host "  Pausa ${PausaSegundos}s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $PausaSegundos
    }
}

Write-Host ""
Write-Host "=== Resumen ===" -ForegroundColor Cyan
Write-Host "OK: $ok / $($lista.Count)"
if ($fallidas.Count -gt 0) {
    Write-Host "Fallidas: $($fallidas -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "Grupo '$Grupo' desplegado." -ForegroundColor Green
exit 0
