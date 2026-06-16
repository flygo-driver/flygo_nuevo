# Preparación PR2 — liquidaciones semanales

PR2 ya está **implementado en código** (`liquidacion_semanal.ts`, `liquidaciones_semanales` en rules/indexes, UI admin en `verificar_pagos.dart` tab Comisiones semanales).  
**No activar en producción** hasta que la conciliación bancaria (Fase 4) esté estable en staging.

---

## Dependencias cumplidas

| Requisito | Estado |
|-----------|--------|
| Efectivo excluido de pago semanal (PR1) | ✅ `excluirEfectivoDePagoSemanal` default true |
| Viajes transferencia verificados vía conciliación | ✅ Fase 4 CF + admin UI |
| `elegibleLiquidacionSemanal` en viaje al confirmar conciliación | ✅ `aplicarConciliacionConfirmadaTx` |
| Rules: cliente solo lectura en `liquidaciones_semanales` | ✅ |
| Hardening legacy `pagos_taxistas` | ✅ `pr2PagosTaxistasEscrituraDeshabilitada()` en rules |

---

## Secuencia de activación (staging → prod)

### Paso 1 — Validar conciliación (prerrequisito)

1. `transferenciaRecaudoEnCuentaRai: true`
2. `conciliacionAutomaticaHabilitada: true`
3. Flujo completo: viaje → extracto → proponer → confirmar → `estadoPago=verificado`
4. Al menos 2–3 viajes de prueba conciliados sin discrepancias

### Paso 2 — Activar PR2 (solo staging)

```json
{
  "useLiquidacionesSemanales": true,
  "escrituraPagosTaxistasLegacy": false
}
```

### Paso 3 — Smoke PR2

- [ ] Admin: `generarLiquidacionSemanalTaxista` (callable o UI) para taxista con viajes verificados
- [ ] Documento `liquidaciones_semanales/{id}` con líneas y totales netos
- [ ] Viajes marcados `liquidado: true` en la misma transacción CF
- [ ] Admin: `aprobarLiquidacionSemanal` con referencia ACH de prueba
- [ ] Taxista ve liquidación en app (solo lectura)
- [ ] **No** se crean nuevos `pagos_taxistas` para transferencia verificada

### Paso 4 — Prod (cuando staging verde ≥ 1 semana)

1. Deploy mismo bundle que staging validado
2. Activar flags PR2 en horario de bajo tráfico
3. Monitorear primera generación semanal (scheduler o manual admin)
4. Mantener `pagos_taxistas` legacy **solo lectura** para histórico; no reactivar escritura

---

## Cloud Functions PR2 (ya exportadas)

| Callable / trigger | Uso |
|--------------------|-----|
| `generarLiquidacionSemanalTaxista` | Admin o batch por taxista/período |
| `aprobarLiquidacionSemanal` | Marca pagada + referencia ACH |
| `cancelarLiquidacionSemanal` | Revierte borrador |
| `listarLiquidacionesSemanalTaxista` | App taxista / admin |
| Scheduler semanal | Revisar cron en `liquidacion_semanal.ts` antes de prod |

---

## Criterios de elegibilidad (recordatorio)

Un viaje entra en liquidación semanal **solo si**:

- Método **transferencia** o **tarjeta** (nunca efectivo)
- `estadoPago == verificado` (conciliación o validación admin)
- `liquidado != true`
- Viaje completado / cerrado por CF

Fuente: `liquidacion_semanal_viaje.ts` + flag `excluirEfectivoDePagoSemanal`.

---

## Rollback PR2

Si hay incidencia tras activar:

```json
{
  "useLiquidacionesSemanales": false,
  "escrituraPagosTaxistasLegacy": true
}
```

- No borrar documentos `liquidaciones_semanales` ya creados (auditoría)
- Corregir viajes mal liquidados vía admin + soporte (CF manual si aplica)
- Re-deploy **no** necesario para rollback de flags

---

## Próximo después de PR2 estable

- Fase 6 AZUL (tarjeta → misma caja recaudo digital → liquidación semanal)
- Fase 7 ACH real con Banco Popular (referencia ACH en `aprobarLiquidacionSemanal`)
- Deprecación total de `pagos_taxistas` (eliminar colección tras migración histórica)
