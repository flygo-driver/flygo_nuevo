# Checklist deploy staging — finanzas RAI (pool + banco + conciliación + PR2)

**Proyecto staging:** `flygo-9abd2` / `flygo-rd` (confirmar cuál usás para pruebas).  
**Principio:** todos los flags en `config/finance` **OFF** hasta terminar smoke tests por fase.

---

## 0. Pre-requisitos infra

- [ ] Billing activo en el proyecto Firebase
- [ ] ADC local: `gcloud auth application-default login`
- [ ] Secret `GEMINI_API_KEY` en Secret Manager (si el deploy de functions lo exige)
- [ ] Node 20+ en CI/local para `functions/`

---

## 1. Commit y artefactos incluidos

Verificar que el deploy incluye al menos:

| Área | Archivos clave |
|------|----------------|
| CF pool/finanzas | `finance.ts`, `taxista_operacion_gate.ts`, `banco_movimientos.ts`, `conciliacion.ts`, `viaje_referencia.ts`, `liquidacion_semanal.ts` |
| CF index | `functions/src/index.ts` exporta todos los módulos |
| Rules | `firestore.rules` (pool, billetera admin-only, movimientos_banco, conciliaciones) |
| Indexes | `firestore.indexes.json` (movimientos_banco, conciliaciones, viajes.referenciaRecaudo) |
| Flutter | `viajes_repo.dart`, `finance_config_service.dart`, `conciliacion_banco_repo.dart`, `verificar_pagos.dart` (tab conciliación) |
| Tests | `npm test` en `functions/` → 29/29 |

---

## 2. Deploy orden recomendado

```bash
cd functions && npm run build && npm test
cd ..
firebase deploy --only firestore:rules,firestore:indexes --project <PROJECT_ID>
firebase deploy --only functions --project <PROJECT_ID>
# App Flutter: build web/APK según canal de staging
```

- [ ] Rules desplegadas sin error
- [ ] Indexes en estado **Building** → esperar **Enabled** en consola (10–30 min)
- [ ] Functions list incluye: `onViajeCreatedAsignarReferenciaRecaudo`, `importarExtractoPopular`, `proponerConciliacionesAutomaticas`, `confirmarConciliacion`, `rechazarConciliacion`, `generarLiquidacionSemanalTaxista`, `aprobarLiquidacionSemanal`

---

## 3. Flags `config/finance` — activación por fases

**Estado inicial (prod-like, cero impacto):**

```json
{
  "excluirEfectivoDePagoSemanal": true,
  "useLiquidacionesSemanales": false,
  "escrituraPagosTaxistasLegacy": true,
  "transferenciaRecaudoEnCuentaRai": false,
  "conciliacionAutomaticaHabilitada": false,
  "transferenciaExigeVerificadoParaFinalizar": false
}
```

### Fase A — Pool + prepago (sin recaudo RAI)

- [ ] Deploy rules + CF con flags OFF
- [ ] Smoke taxista: claim pool solo si expediente completo
- [ ] Smoke efectivo: finalizar viaje → comisión prepago vía CF (no snackbar falso post-CF)

### Fase B — Referencia RAI (staging)

- [ ] `transferenciaRecaudoEnCuentaRai: true`
- [ ] Crear viaje **Transferencia** → `referenciaRecaudo` aparece en Firestore (CF onCreate, ~2 s)
- [ ] UI cliente muestra panel cuenta RAI + referencia copiable

### Fase C — Extracto + conciliación

- [ ] `conciliacionAutomaticaHabilitada: true`
- [ ] Admin → Verificar pagos → **Conciliación banco** → Importar CSV de prueba
- [ ] **Proponer conciliaciones** → propuesta en `conciliaciones` estado `propuesta`
- [ ] **Confirmar** → viaje `estadoPago=verificado`, movimiento `conciliado`

### Fase D — Endurecer cierre

- [ ] `transferenciaExigeVerificadoParaFinalizar: true`
- [ ] Taxista **no** puede finalizar transferencia RAI sin verificado
- [ ] Tras confirmar conciliación → finalizar OK

### Fase E — PR2 liquidaciones (ver PREPARACION_PR2_LIQUIDACIONES.md)

- [ ] Solo tras Fase C estable
- [ ] `useLiquidacionesSemanales: true` + `escrituraPagosTaxistasLegacy: false`

---

## 4. Smoke admin

| Prueba | Esperado |
|--------|----------|
| Verificar pagos → Recargas prepago | Aprobar/rechazar recarga vía CF |
| Verificar pagos → Comisiones semanales | Lista legacy o PR2 según flag |
| Verificar pagos → Conciliación banco | Import CSV, proponer, confirmar/rechazar |
| Rules: admin lee `movimientos_banco` / `conciliaciones` | OK |
| Rules: taxista lee billetera propia, no escribe | OK |

---

## 5. Smoke taxista / cliente

| Prueba | Esperado |
|--------|----------|
| Pool claim sin docs | Rechazado (rules + CF) |
| Viaje efectivo completar | CF cierra; prepago actualizado |
| Transferencia flag OFF | Panel cuenta conductor (legacy) |
| Transferencia flag ON | Panel RAI + referencia |
| Finalizar transferencia sin verificado (flag D ON) | Error CF claro |

---

## 6. Riesgos operativos (no bloquean deploy con flags OFF)

| Riesgo | Mitigación |
|--------|------------|
| Indexes aún building | Esperar antes de proponer conciliaciones |
| `pago_data.dart` legacy intenta escribir billetera | Rules bloquean; CF es fuente de verdad |
| Doble liquidación PR1/PR2 | No activar `useLiquidacionesSemanales` hasta conciliación estable |
| Taxistas sin expediente post-deploy pool | Comunicar + completar documentos |

---

## 7. GO / NO-GO staging

**GO condicional** si:

1. `npm test` pasa
2. Deploy rules + indexes + functions OK
3. Flags OFF en prod; activación por fases en staging documentada
4. Smoke A (pool + efectivo) verde

**NO-GO** si: billing/ADC bloquean deploy, indexes fallan, o claim pool rompe flujo legacy con flags OFF.
