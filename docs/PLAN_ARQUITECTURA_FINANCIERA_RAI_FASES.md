# Plan de implementación — Arquitectura financiera RAI
## Banco Popular · AZUL · Liquidación semanal

**Estado:** Diseño para revisión — **sin implementación**  
**Principio rector:** Dos cajas separadas (prepago efectivo ≠ recaudo digital). No romper navegación, timbre, pool ni cierre en CF.

---

## Visión objetivo (recordatorio)

| Método | Entrada de dinero | Comisión RAI | Salida al conductor |
|--------|-------------------|--------------|---------------------|
| Efectivo | Cliente → conductor (mano) | Prepago al cerrar viaje | N/A (ya cobró en mano) |
| Transferencia | Cliente → cuenta RAI | Retenida en banco | Liquidación semanal ACH (neto) |
| Tarjeta | Cliente → AZUL → cuenta RAI | Retenida | Misma liquidación semanal |

---

## Mapa de fases y dependencias

```
Fase 1 (fix doble pago efectivo)
    │
    ├──► Fase 2 (liquidaciones_semanales)
    │         │
    │         ├──► Fase 7 (ACH conductores)
    │         │
    │         └──► Fase 6 (AZUL) ──► Fase 7
    │
    ├──► Fase 3 (movimientos_banco)
    │         │
    │         └──► Fase 4 (conciliaciones)
    │                   │
    │                   └──► Fase 5 (Popular + referencia)
    │
    └──► Fase 5 puede iniciar UI/referencia en paralelo tras Fase 1
```

**Orden recomendado de ejecución:** 1 → 2 → 3 → 4 → 5 → 6 → 7  
**Paralelo posible:** Fase 5 (UI + referencia) tras Fase 1; Fase 6 (contrato AZUL sandbox) en paralelo con 3–4.

---

# FASE 1 — Corregir doble pago de efectivo

## Objetivo
Evitar que viajes en **efectivo** entren en liquidación semanal (`pagos_taxistas`) o se paguen dos veces (cash en mano + neto semanal).

## Problema actual (confirmado en código)
- `PagosTaxistaRepo.generarPagoSemanal` suma **todos** los viajes `completado` sin filtrar `metodoPago`.
- `functions/src/finance.ts` → `approvePayment` liquida por rango de fechas sin excluir efectivo.
- `netoAPagar` en `PagoTaxista` asume ganancia de todos los viajes de la semana.

## Cambios de diseño (sin código)

### Regla de negocio fija
```
LIQUIDABLE_SEMANAL = metodoPago IN (Transferencia, Tarjeta)
                   AND estadoPago = verificado
                   AND liquidado = false

NO_LIQUIDABLE = metodoPago = Efectivo (comisión ya en prepago)
```

### Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `lib/servicios/pagos_taxista_repo.dart` | `generarPagoSemanal`: filtrar solo viajes liquidables; documentar exclusión efectivo |
| `functions/src/finance.ts` | `approvePayment`: misma query con filtro `metodoPago`; no incluir efectivo en `viajesLiquidados` para pago neto |
| `lib/modelo/pago_taxista.dart` | Campos opcionales: `soloViajesDigitales`, `viajesEfectivoExcluidos` (auditoría) |
| `lib/pantallas/admin/verificar_pagos.dart` | Copy: semanal = solo transferencia/tarjeta |
| `lib/pantallas/taxista/mis_pagos.dart` | Desglose: prepago (efectivo) vs próximo pago semanal (digital) |
| `lib/servicios/billetera_service.dart` | Revisar `calcularSaldoDisponible`: no mezclar ganancia efectivo con retiros digitales |
| `lib/widgets/resumen_pago_taxista.dart` | Query `liquidado==false` debe excluir efectivo o usar flag `elegibleLiquidacionSemanal` |
| `firestore.indexes.json` | Índice compuesto si nueva query por método |

### Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| *(ninguna obligatoria)* | — | Corrección en `approvePayment` y cliente |
| `validarConsistenciaPagosSemanales` | onCall admin (opcional) | Reporte viajes efectivo erróneamente en `pagos_taxistas` históricos |

### Colecciones nuevas
Ninguna en Fase 1.

### Campos nuevos en `viajes`
| Campo | Tipo | Propósito |
|-------|------|-----------|
| `elegibleLiquidacionSemanal` | bool | Calculado al cerrar: `true` solo transferencia/tarjeta verificada |
| `metodoPagoNormalizado` | string | `efectivo` \| `transferencia` \| `tarjeta` (evita variantes "Efectivo"/"efectivo") |

**Cálculo:** CF `finalizarViajeSeguro` setea al cerrar según `metodoPago` y política de verificación.

### Campos nuevos en `pagos_taxistas`
| Campo | Tipo |
|-------|------|
| `incluyeSoloMetodos` | array | `['transferencia','tarjeta']` |
| `viajesEfectivoExcluidosCount` | number | Auditoría migración |

### Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Pagos semanales históricos ya incluyen efectivo | Script admin one-shot: marcar `pagos_taxistas` legacy; no recalcular sin revisión |
| Conductores esperaban neto semanal por efectivo | Comunicación + UI clara en Mis pagos |
| `BilleteraService` muestra saldo inflado | Alinear con regla Fase 1 antes de Fase 2 |

### Dependencias
- Ninguna (primera fase).
- **Bloquea:** Fase 2, 7 (liquidación correcta).
- **No tocar:** `finalizarViajeSeguro` lógica prepago efectivo; navegación; `claimTripWithReason`.

### Criterios de aceptación
- [ ] `generarPagoSemanal` con 3 viajes (2 efectivo, 1 transferencia verificada) → neto = solo 1 viaje digital.
- [ ] Viajes efectivo nunca aparecen en `viajesLiquidados` de pago semanal.
- [ ] Prepago y bloqueo operativo sin cambios.

---

# FASE 2 — Colección `liquidaciones_semanales`

## Objetivo
Reemplazar gradualmente `pagos_taxistas` como fuente de verdad para **liquidación digital semanal**, con trazabilidad por viaje y estado de pago ACH.

## Diseño de colección

### `liquidaciones_semanales/{id}`
**ID sugerido:** `{uidTaxista}_{periodo}` donde `periodo` = `2026-W23` (ISO week).

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `uidTaxista` | string | Conductor |
| `nombreTaxista` | string | Snapshot |
| `periodo` | string | `YYYY-Www` |
| `periodoInicio` | timestamp | Lunes 00:00 |
| `periodoFin` | timestamp | Domingo 23:59 |
| `estado` | string | `borrador` \| `pendiente_pago` \| `pagado` \| `cancelado` |
| `viajeIds` | array | Solo digital verificada |
| `viajesCount` | number | |
| `totalBrutoCents` | number | Suma precio viajes |
| `comisionRaiCents` | number | Suma comisión RAI |
| `totalNetoCents` | number | Suma ganancia conductor |
| `moneda` | string | `DOP` |
| `generadoEn` | timestamp | Job o admin |
| `generadoPor` | string | `system` \| uid admin |
| `pagadoEn` | timestamp? | |
| `referenciaAch` | string? | Comprobante salida banco |
| `cuentaDestinoSnapshot` | map | banco/cuenta/titular conductor al generar |
| `notaAdmin` | string? | |
| `idempotencyKey` | string | Evita doble generación |

### Subcolección opcional (auditoría)
`liquidaciones_semanales/{id}/lineas/{viajeId}` — copia monto/comisión por viaje al momento del cierre.

## Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `lib/modelo/liquidacion_semanal.dart` | **Nuevo** modelo |
| `lib/servicios/liquidacion_semanal_repo.dart` | **Nuevo** CRUD + streams |
| `lib/servicios/pagos_taxista_repo.dart` | Deprecar `generarPagoSemanal` → delegar a repo nuevo o CF |
| `lib/pantallas/taxista/mis_pagos.dart` | Tab "Próximo pago semanal" desde `liquidaciones_semanales` |
| `lib/pantallas/admin/verificar_pagos.dart` | Nueva pestaña liquidaciones semanales |
| `lib/pantallas/admin/admin_home.dart` | Contador pendientes (si usa dashboard) |
| `lib/servicios/admin_dashboard_service.dart` | Métrica `liquidacionesSemanalesPendiente` |
| `functions/src/finance.ts` | Integrar marcado `viajes.liquidado` al aprobar |
| `functions/src/index.ts` | Export nuevas CF |
| `firestore.rules` | Reglas `liquidaciones_semanales` |
| `firestore.indexes.json` | `(uidTaxista, periodo)`, `(estado, periodoFin)` |

## Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| `generarLiquidacionesSemanales` | scheduled (cron lun 06:00 RD) | Genera docs `borrador`/`pendiente_pago` por taxista con viajes elegibles |
| `aprobarLiquidacionSemanal` | onCall admin | `pendiente_pago` → `pagado`; marca `viajes.liquidado=true`, `liquidacionSemanalId` |
| `cancelarLiquidacionSemanal` | onCall admin | Revierte si no pagado |
| `obtenerLiquidacionSemanalTaxista` | onCall taxista | Lee propia liquidación periodo actual |

## Campos nuevos en `viajes`
| Campo | Tipo |
|-------|------|
| `liquidacionSemanalId` | string? |
| `liquidadoEn` | timestamp? |

## Relación con `pagos_taxistas`
- **Fase 2:** coexistencia; nueva UI lee `liquidaciones_semanales`.
- **Fase 7:** deprecar escritura en `pagos_taxistas` (lectura legacy 90 días).

## Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Doble sistema semanal (pagos_taxistas + nuevo) | Flag `config/finance.useLiquidacionesSemanales=true` |
| Generación duplicada mismo periodo | ID determinístico + transacción |
| Conductor sin cuenta bancaria | No pasar a `pendiente_pago`; alerta admin |

## Dependencias
- **Requiere:** Fase 1 (filtro efectivo).
- **Antes de:** Fase 7 (ACH).
- **Paralelo con:** Fase 3–4 (conciliación entrada).

## Criterios de aceptación
- [ ] Job genera liquidación solo con viajes `elegibleLiquidacionSemanal=true`.
- [ ] Aprobar liquidación marca todos los viajes `liquidado=true` idempotentemente.
- [ ] Taxista ve monto neto y lista de viajes en Mis pagos.

---

# FASE 3 — Colección `movimientos_banco`

## Objetivo
Registrar **entradas y salidas** reales en cuenta RAI (extracto Popular, ACH saliente) como fuente para conciliación.

## Diseño de colección

### `movimientos_banco/{id}`
**ID sugerido:** hash único banco o `{fecha}_{referencia}_{montoCents}`.

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `tipo` | string | `entrada` \| `salida` |
| `origen` | string | `popular_extracto` \| `popular_api` \| `ach_manual` \| `azul_settlement` |
| `fechaValor` | timestamp | Fecha banco |
| `fechaRegistro` | timestamp | Import/creación |
| `montoCents` | number | Positivo |
| `moneda` | string | `DOP` |
| `referenciaBanco` | string | Texto extracto |
| `referenciaNormalizada` | string | Upper, sin espacios (match) |
| `descripcion` | string | Concepto extracto |
| `cuentaRai` | string | Últimos 4 dígitos |
| `estadoConciliacion` | string | `sin_match` \| `conciliado` \| `parcial` \| `discrepancia` |
| `conciliacionId` | string? | FK Fase 4 |
| `viajeId` | string? | Si match 1:1 |
| `liquidacionSemanalId` | string? | Si es salida ACH |
| `importBatchId` | string? | Lote importación |
| `rawPayload` | map? | Línea CSV/API sin procesar |
| `createdAt` | timestamp | |

## Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `lib/modelo/movimiento_banco.dart` | **Nuevo** |
| `lib/servicios/movimientos_banco_repo.dart` | **Nuevo** |
| `lib/pantallas/admin/admin_centro_operaciones.dart` | Vista movimientos / importar |
| `lib/pantallas/admin/verificar_pagos.dart` | Panel conciliación pendiente |
| `functions/src/banco_movimientos.ts` | **Nuevo** módulo CF |
| `functions/src/index.ts` | Export |
| `firestore.rules` | Solo admin read/write |
| `firestore.indexes.json` | `(estadoConciliacion, fechaValor)`, `(referenciaNormalizada)` |

## Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| `importarExtractoPopular` | onCall admin | CSV/JSON → batch `movimientos_banco` |
| `registrarMovimientoBancoManual` | onCall admin | Entrada/salida manual |
| `listarMovimientosSinConciliar` | onCall admin | Cola trabajo |

## Colecciones nuevas
- `movimientos_banco`
- `import_batches_banco/{id}` (opcional: metadata importación)

## Campos nuevos
Solo en colección nueva (+ opcional `config/empresa.cuentaRaiUltimos4`).

## Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Duplicados en re-import | ID determinístico + skip exists |
| Formato extracto cambia | Parser versionado `importVersion` |
| Datos sensibles en `rawPayload` | No guardar datos personales cliente; solo ref |

## Dependencias
- **Requiere:** Fase 1 (concepto separación cajas).
- **Antes de:** Fase 4 (conciliaciones).
- **Alimenta:** Fase 5, 7 (salidas ACH).

## Criterios de aceptación
- [ ] Admin importa CSV de prueba → N movimientos `sin_match`.
- [ ] Re-import mismo archivo no duplica.
- [ ] Salida ACH Fase 7 crea movimiento `salida` vinculado.

---

# FASE 4 — Colección `conciliaciones`

## Objetivo
Vincular explícitamente **movimiento bancario ↔ viaje(s) ↔ liquidación**, con estados y resolución de discrepancias.

## Diseño de colección

### `conciliaciones/{id}`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `tipo` | string | `viaje_entrada` \| `liquidacion_salida` \| `ajuste` |
| `estado` | string | `propuesta` \| `confirmada` \| `rechazada` |
| `movimientoBancoId` | string | FK |
| `viajeId` | string? | Entrada cliente |
| `liquidacionSemanalId` | string? | Salida conductor |
| `montoEsperadoCents` | number | Desde viaje/liquidación |
| `montoRealCents` | number | Desde banco |
| `diferenciaCents` | number | |
| `referenciaRecaudo` | string? | Del viaje |
| `matchScore` | number? | 0–1 automático |
| `matchReglas` | array | `ref_exacta`, `monto_exacto`, etc. |
| `resueltoPor` | string | uid admin o `system` |
| `resueltoEn` | timestamp | |
| `nota` | string? | |
| `createdAt` | timestamp | |

## Flujo de estados

```
movimiento_banco (sin_match)
    → job/auto match por referenciaRecaudo + monto
    → conciliacion (propuesta)
    → admin confirma → viaje.estadoPago=verificado, movimiento.conciliado
    → o rechaza → disputa manual
```

## Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `lib/modelo/conciliacion.dart` | **Nuevo** |
| `lib/servicios/conciliacion_repo.dart` | **Nuevo** |
| `lib/pantallas/admin/verificar_pagos.dart` | UI confirmar/rechazar matches |
| `lib/pantallas/admin/admin_centro_operaciones.dart` | Dashboard discrepancias |
| `functions/src/conciliacion.ts` | **Nuevo** módulo |
| `functions/src/finance.ts` | Al confirmar: actualizar `viajes.estadoPago` (no desde cliente) |
| `firestore.rules` | Admin only |
| `firestore.indexes.json` | `(estado, createdAt)`, `(viajeId)` |

## Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| `proponerConciliacionesAutomaticas` | scheduled / onCall | Match ref+monto |
| `confirmarConciliacion` | onCall admin | Cierra loop viaje/movimiento |
| `rechazarConciliacion` | onCall admin | |
| `conciliarViajeConMovimiento` | onCall admin | Manual 1:1 |

## Campos nuevos en `viajes`
| Campo | Tipo |
|-------|------|
| `conciliacionId` | string? |
| `conciliacionEstado` | string? |
| `movimientoBancoEntradaId` | string? |

## Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Match falso (mismo monto, ref distinta) | Requerir ref exacta o admin |
| Un movimiento → varios viajes | Tipo `ajuste` + split manual |
| Viaje verificado sin dinero | No permitir `elegibleLiquidacionSemanal` hasta conciliación confirmada (política Fase 5) |

## Dependencias
- **Requiere:** Fase 3 (`movimientos_banco`).
- **Antes de:** Fase 5 (verificación automática), Fase 7 (conciliar salidas ACH).
- **Relaciona con:** Fase 2 (liquidaciones salida).

## Criterios de aceptación
- [ ] Match automático ref+monto crea `propuesta`.
- [ ] Confirmar actualiza viaje + movimiento sin doble escritura.
- [ ] Discrepancia monto visible en admin.

---

# FASE 5 — Integración Banco Popular (referencia única por viaje)

## Objetivo
Cliente paga a **cuenta RAI** con referencia única; dejar de orientar transferencia al conductor.

## Diseño funcional

### Generación de referencia (al crear viaje transferencia)
```
Formato: RAI-V-{viajeId8}-{checksum2}
Ejemplo: RAI-V-A1B2C3D4-7F
```
- Única por viaje; indexada en Firestore.
- Mostrada en factura, post-viaje, push recordatorio.

### UI cliente (sin cambiar navegación)
- Reemplazar `DatosTransferenciaConductorPanel` por **`DatosTransferenciaRaiPanel`** cuando `metodoPago=Transferencia`.
- Datos desde `PayConfig` / futuro `config/empresa` (no hardcode en release).
- Instrucciones: App Popular → Pagos de servicios → beneficiario RAI → referencia.

### Flujo de pago deseado
```
1. Cliente crea viaje Transferencia → referenciaRecaudo asignada
2. Cliente transfiere a cuenta RAI (manual / Botón Pago / QR — fase posterior API)
3. Import extracto (Fase 3) o API Popular (futuro)
4. Conciliación (Fase 4) → estadoPago=verificado
5. Conductor finaliza (o política: finalizar solo si verificado — configurable)
6. Viaje entra en liquidación semanal (Fase 2)
```

### Deprecación controlada
| Componente actual | Acción |
|-------------------|--------|
| `DatosTransferenciaConductorPanel` | Solo legacy viajes antiguos o ocultar |
| `confirmarTransferenciaTaxistaSeguro` | Deprecar como prueba de pago; mantener temporal para viajes legacy |
| `comprobanteTransferenciaUrl` | Opcional: comprobante cliente a RAI (no reemplaza conciliación banco) |
| Snapshot `bancoTaxista` en viaje | Mantener para liquidación **saliente** ACH al conductor |

## Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `lib/servicios/viajes_repo.dart` | `crearViajePendiente`: generar `referenciaRecaudo` si transferencia |
| `lib/servicios/pay_config.dart` | `referenciaViaje(viajeId)`; instrucciones pago |
| `lib/config/recarga_bancaria_config.dart` | Migrar a `config/empresa` lectura |
| `lib/widgets/datos_transferencia_conductor_panel.dart` | Renombrar/split panel RAI |
| `lib/pantallas/comun/factura_viaje.dart` | Cuenta RAI + referencia |
| `lib/pantallas/cliente/post_viaje_cliente_flow.dart` | Idem |
| `lib/pantallas/cliente/viaje_en_curso_cliente.dart` | Idem si transferencia pendiente |
| `lib/servicios/comprobante_transferencia_service.dart` | Copy: comprobante a RAI |
| `functions/src/finance.ts` | `reportarTransferenciaClienteSeguro`: no marcar `estadoPago=pagado` sin conciliación (política) |
| `functions/src/viaje_referencia.ts` | **Nuevo**: generación/validación ref |
| `functions/src/conciliacion.ts` | Match por `referenciaRecaudo` |
| `firestore.rules` | Cliente puede leer `referenciaRecaudo`; no escribir |
| `docs/REUNION_BANCO_POPULAR_AZUL_RAI.md` | Actualizar tras diseño |

## Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| `generarReferenciaRecaudoViaje` | interno / onCall | Idempotente al crear viaje |
| `webhookPopularPago` | HTTPS (futuro) | Si Botón Pago / API Portal Premium |
| *(reusar)* `importarExtractoPopular` | Fase 3 | |
| *(reusar)* `proponerConciliacionesAutomaticas` | Fase 4 | |

## Colecciones nuevas
| Colección | Uso |
|-----------|-----|
| `config/empresa` | cuenta RAI, RNC, titular, instrucciones recaudo |
| `referencias_recaudo/{ref}` (opcional) | Unicidad global ref → viajeId |

## Campos nuevos en `viajes`
| Campo | Tipo |
|-------|------|
| `referenciaRecaudo` | string (unique index) |
| `cuentaDestinoPago` | string | `rai` |
| `recaudoInstruccionesVersion` | number |

## Integración productos Popular (roadmap dentro de fase)
| Producto | Fase diseño | Implementación |
|----------|-------------|----------------|
| Recaudo con referencia manual | 5a | UI + conciliación CSV |
| Botón de Pago Popular | 5b | WebView/deep link + webhook |
| QR AZUL / App Popular | 5c | QR dinámico monto+ref |
| Toke | 5d | Evaluar con banco |
| API Portal Premium | 5e | Validación cuenta + pagos |

## Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Viajes legacy P2P conductor | `cuentaDestinoPago=taxista` no migrar |
| Cliente omite referencia | Conciliación manual monto+fecha; UI enfática |
| Finalizar sin pago | Flag `config/finance.exigirPagoVerificadoParaFinalizar` |

## Dependencias
- **Requiere:** Fase 1; Fase 3–4 para automatizar verificación.
- **Puede iniciar UI+ref** tras Fase 1 sin esperar 3–4 (comprobante manual interim).
- **Antes de:** Fase 7 (solo liquidar viajes verificados).

## Criterios de aceptación
- [ ] Nuevo viaje transferencia muestra solo cuenta RAI + referencia.
- [ ] Referencia única en Firestore.
- [ ] Viaje verificado solo tras conciliación confirmada (o admin override).

---

# FASE 6 — Integración AZUL

## Objetivo
Cobro con tarjeta a comercio RAI; mismo circuito liquidación semanal que transferencia.

## Diseño arquitectónico

```
Cliente elige Tarjeta
    → App solicita sesión pago (CF azulCreatePaymentSession)
    → AZUL Payment Page o API + 3DS + DataVault token
    → Webhook/return URL → azulWebhook
    → viaje: payment.provider=azul, estadoPago=verificado, elegibleLiquidacionSemanal=true
    → Conductor finaliza viaje (servicio ya pagado)
    → Fase 2 liquidación semanal
```

### PCI
- PAN nunca en Firestore.
- Token AZUL / `payment.azulToken` solo referencia opaca.
- Preferir **Página de Pagos AZUL** (hosted) en v1; API directa en v2.

## Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `lib/servicios/pay_config.dart` | `pagosConTarjetaHabilitados` tras QA |
| `lib/servicios/pagos/payment_gateway.dart` | **Nuevo** `AzulPaymentGateway`; deprecar mock prod |
| `lib/servicios/pagos/azul_payment_gateway.dart` | **Nuevo** |
| `lib/data/pago_data.dart` | Integrar gateway AZUL en autorizar/capturar |
| `lib/widgets/pay_method_selector.dart` | Mostrar tarjeta |
| `lib/pantallas/cliente/confirmar_viaje.dart` / `programar_viaje.dart` | Flujo pago tarjeta pre o post asignación (decisión producto) |
| `lib/pantallas/cliente/viaje_en_curso_cliente.dart` | Estado pago tarjeta pendiente |
| `functions/src/azul.ts` | **Nuevo** módulo |
| `functions/src/finance.ts` | `finalizarViajeSeguro`: tarjeta requiere `payment.status=captured` |
| `functions/src/index.ts` | Export |
| `firestore.rules` | Sin escritura cliente en campos AZUL |
| `.env` / Secret Manager | `AZUL_STORE_ID`, `AZUL_AUTH_KEY`, etc. |

## Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| `azulCreatePaymentSession` | onCall cliente | Crea orden; devuelve URL o client secret |
| `azulWebhook` | HTTPS | Confirma captura; idempotente por `azulOrderId` |
| `azulVerifyPayment` | onCall | Poll estado si webhook lento |
| `azulSettlementImport` | onCall admin | Opcional: conciliar depósito AZUL → `movimientos_banco` |

## Colecciones nuevas
### `pagos_azul/{id}`
| Campo | Tipo |
|-------|------|
| `viajeId` | string |
| `uidCliente` | string |
| `azulOrderId` | string |
| `azulRrn` | string? |
| `montoCents` | number |
| `estado` | `pending` \| `authorized` \| `captured` \| `failed` \| `refunded` |
| `rawResponse` | map (sanitizado) |
| `createdAt` | timestamp |

## Campos nuevos en `viajes`
| Campo | Tipo |
|-------|------|
| `payment.azulOrderId` | string |
| `payment.azulAuthCode` | string? |
| `payment.azulCapturedAt` | timestamp? |
| `pagoAzulId` | string? |

## Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Mock gateway en producción | Feature flag + assert build flavor |
| Webhook spoofing | Firma AZUL + IP allowlist |
| Captura sin viaje asignado | Política: cobrar al confirmar viaje o al inicio |
| Comisión AZUL + comisión RAI | Modelo precio: cliente paga total; RAI retiene neto |

## Dependencias
- **Requiere:** Fase 1, 2 (liquidación digital).
- **Paralelo:** Fase 3–4 (settlement AZUL en banco).
- **Contrato externo:** Afiliación AZUL E-Commerce (sandbox `pruebas.azul.com.do`).
- **No requiere:** Fase 5 para funcionar (circuito independiente).

## Criterios de aceptación
- [ ] Sandbox: pago test → viaje verificado → elegible liquidación.
- [ ] Webhook idempotente.
- [ ] Finalizar bloqueado si tarjeta no captured.

---

# FASE 7 — Liquidación semanal ACH a conductores

## Objetivo
Pago batch semanal del **neto digital** a cuenta bancaria del conductor, con trazabilidad y conciliación saliente.

## Diseño operativo

```
Job generarLiquidacionesSemanales (Fase 2)
    → estado pendiente_pago
    → Admin ejecuta transferencias ACH vía BIZ / Internet Banking Empresarial
    → Admin registra referenciaAch en aprobarLiquidacionSemanal
    → CF crea movimiento_banco salida (Fase 3)
    → CF crea conciliacion tipo liquidacion_salida (Fase 4)
    → Push conductor "Pago semanal depositado"
```

### Pre-requisitos conductor
- Perfil bancario completo (`usuarios`: banco, numeroCuenta, titularCuenta).
- Validación opcional API Portal Popular (validación cuenta).

## Archivos afectados
| Archivo | Cambio |
|---------|--------|
| `functions/src/liquidacion_semanal.ts` | **Nuevo** (o extender finance.ts) |
| `functions/src/finance.ts` | `aprobarLiquidacionSemanal` completo |
| `functions/src/banco_movimientos.ts` | Registrar salida ACH |
| `functions/src/conciliacion.ts` | Match salida |
| `lib/pantallas/admin/verificar_pagos.dart` | Export CSV ACH: uid, monto, cuenta, titular |
| `lib/pantallas/taxista/mis_pagos.dart` | Historial liquidaciones pagadas |
| `lib/servicios/push_service.dart` | Notificación pago semanal |
| `functions/src/scheduled_pool_notify.ts` | Patrón referencia para push |
| `firestore.rules` | Taxista read own `liquidaciones_semanales` |

## Cloud Functions nuevas
| Function | Tipo | Descripción |
|----------|------|-------------|
| `exportLiquidacionesPendientesAch` | onCall admin | CSV para BIZ |
| `marcarLiquidacionPagadaAch` | onCall admin | referenciaAch + movimiento salida |
| `notificarLiquidacionPagada` | trigger / interno | FCM taxista |

## Campos nuevos
En `liquidaciones_semanales` (Fase 2): `referenciaAch`, `movimientoBancoSalidaId`, `pagadoPorAdminUid`.

En `usuarios`:
| Campo | Tipo |
|-------|------|
| `perfilBancarioVerificado` | bool |
| `perfilBancarioVerificadoEn` | timestamp? |

## Riesgos
| Riesgo | Mitigación |
|--------|------------|
| Pagar sin haber conciliado entradas | Política: solo liquidar viajes con conciliación entrada confirmada |
| ACH fallido | Estado `pendiente_pago` reversible; no marcar viajes liquidados hasta confirmar |
| Monto incorrecto | Doble check: suma lineas = totalNetoCents en transacción |
| Límite ACH banco | Batches por monto máximo |

## Dependencias
- **Requiere:** Fase 1, 2, 3, 4 (recomendado), 5 o 6 (viajes verificados en producción).
- **Operativo:** Cuenta empresarial BIZ activa.

## Criterios de aceptación
- [ ] Liquidación aprobada marca viajes `liquidado=true` una sola vez.
- [ ] Movimiento salida en `movimientos_banco`.
- [ ] Conductor recibe push con monto y periodo.

---

# Resumen transversal

## Colecciones nuevas (todas las fases)

| Colección | Fase |
|-----------|------|
| `liquidaciones_semanales` | 2 |
| `movimientos_banco` | 3 |
| `conciliaciones` | 4 |
| `config/empresa` | 5 |
| `referencias_recaudo` (opcional) | 5 |
| `pagos_azul` | 6 |
| `import_batches_banco` (opcional) | 3 |

## Cloud Functions nuevas (consolidado)

| Function | Fase |
|----------|------|
| `validarConsistenciaPagosSemanales` | 1 (opt) |
| `generarLiquidacionesSemanales` | 2 |
| `aprobarLiquidacionSemanal` | 2, 7 |
| `cancelarLiquidacionSemanal` | 2 |
| `obtenerLiquidacionSemanalTaxista` | 2 |
| `importarExtractoPopular` | 3 |
| `registrarMovimientoBancoManual` | 3 |
| `proponerConciliacionesAutomaticas` | 4 |
| `confirmarConciliacion` | 4 |
| `generarReferenciaRecaudoViaje` | 5 |
| `webhookPopularPago` | 5b (futuro) |
| `azulCreatePaymentSession` | 6 |
| `azulWebhook` | 6 |
| `exportLiquidacionesPendientesAch` | 7 |
| `marcarLiquidacionPagadaAch` | 7 |

## Campos nuevos en `viajes` (consolidado)

| Campo | Fase |
|-------|------|
| `elegibleLiquidacionSemanal` | 1 |
| `metodoPagoNormalizado` | 1 |
| `liquidacionSemanalId` | 2 |
| `liquidadoEn` | 2 |
| `conciliacionId` | 4 |
| `movimientoBancoEntradaId` | 4 |
| `referenciaRecaudo` | 5 |
| `cuentaDestinoPago` | 5 |
| `payment.azul*` | 6 |

## Lo que NO se toca (todas las fases)

- Navegación: `NavigationService`, shells, `ActiveTripService`, timbre, `claimTripWithReason` UX
- Cierre viaje: `completarViajePorTaxista` / `finalizarViajeSeguro` (solo extender campos)
- Prepago efectivo: `billeteras_taxista`, `approveRecargaComision`, bloqueo operativo
- Pool / giras: `pool_finance.ts` (producto separado)
- Estados viaje: `EstadosViaje` transiciones

## Feature flags recomendados (`config/finance`)

| Flag | Fase |
|------|------|
| `excluirEfectivoDePagoSemanal` | 1 |
| `useLiquidacionesSemanales` | 2 |
| `exigirPagoVerificadoParaFinalizar` | 5 |
| `pagosTarjetaAzulHabilitados` | 6 |
| `conciliacionAutomaticaHabilitada` | 4 |

## Estimación relativa (esfuerzo)

| Fase | Esfuerzo | Riesgo negocio |
|------|----------|----------------|
| 1 | S | Alto si no se hace |
| 2 | M | Medio |
| 3 | M | Medio |
| 4 | M | Medio |
| 5 | L | Alto (cambio UX cliente) |
| 6 | L | Medio |
| 7 | M | Alto |

---

# Decisiones aprobadas (stakeholders — junio 2026)

- [x] **Efectivo nunca en liquidación semanal.** El conductor ya cobró en mano; comisión solo vía prepago.
- [x] **Transferencia exige pago verificado antes de finalizar** (manual o automático vía conciliación).
- [x] **Deprecar `pagos_taxistas`** cuando `liquidaciones_semanales` esté estable en producción; luego eliminar.
- [x] **Tarjeta (AZUL): cobrar al finalizar el viaje o justo antes** — no al confirmar ni al asignar conductor.
- [ ] ¿Cuenta RAI en `config/empresa` vs hardcode?
- [ ] ¿Orden de contratación banco: recaudo referencia antes de AZUL?

Ver instrucciones para implementación: `docs/CURSOR_INSTRUCCIONES_FINANZAS_RAI.md`

---

*Documento de diseño. Versión 1.1 — decisiones 1–4 aprobadas.*
