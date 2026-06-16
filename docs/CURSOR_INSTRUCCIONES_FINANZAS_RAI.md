# Instrucciones para Cursor — Arquitectura financiera RAI

**Usar este bloque al iniciar cualquier tarea de implementación de finanzas (Fases 1–7).**  
**Plan detallado:** `docs/PLAN_ARQUITECTURA_FINANCIERA_RAI_FASES.md`  
**Reunión banco:** `docs/REUNION_BANCO_POPULAR_AZUL_RAI.md`

---

## DECISIONES DE NEGOCIO APROBADAS (obligatorias)

### 1. Efectivo y liquidación semanal
**Sí — efectivo NUNCA entra en liquidación semanal.**
- El pasajero paga 100% al conductor en mano.
- RAI no recibe ese dinero.
- La comisión RAI se descuenta del **prepago** (`billeteras_taxista`) al cerrar el viaje.
- `pagos_taxistas`, `liquidaciones_semanales` y ACH semanal: **solo** viajes Transferencia/Tarjeta verificados.

### 2. Transferencia antes de finalizar
**Sí — no se puede finalizar un viaje por transferencia sin pago verificado.**
- `finalizarViajeSeguro` debe rechazar si `metodoPago=Transferencia` y `estadoPago != verificado` (salvo override admin explícito).
- Verificación = conciliación bancaria confirmada (Fase 4) o confirmación admin.
- No usar `confirmarTransferenciaTaxistaSeguro` como prueba de que RAI recibió el dinero (modelo legacy P2P).

### 3. Deprecación de `pagos_taxistas`
**Sí — deprecar al activar Fase 2 en producción.**
- Fuente de verdad nueva: `liquidaciones_semanales`.
- `pagos_taxistas`: solo lectura legacy durante periodo de transición; no crear docs nuevos ahí.
- Tras validación en prod: eliminar código y colección (migración histórica si aplica).

### 4. Tarjeta AZUL — cuándo cobrar
**Cobrar al finalizar el viaje o justo antes de finalizar** (no al confirmar viaje ni al asignar conductor).
- El monto debe coincidir con el servicio prestado.
- Flujo: servicio completado → cobro AZUL → captura OK → `estadoPago=verificado` → callable finalizar (o finalizar bloqueado hasta captura según UX).
- Evitar autorizaciones/capturas al crear viaje o al claim del taxista.

---

## MODELO DE DOS CAJAS (no mezclar)

| Caja | Entrada | Salida |
|------|---------|--------|
| **Prepago** | Recargas conductor → cuenta RAI | Comisión viajes **efectivo** |
| **Recaudo digital** | Transferencia/Tarjeta → cuenta RAI | Liquidación semanal ACH (neto conductor) |

El dinero de transferencias/tarjetas **no** recarga el prepago del conductor.

---

## ORDEN DE FASES (no saltar sin dependencias)

1. Fix doble pago efectivo en semanal  
2. `liquidaciones_semanales`  
3. `movimientos_banco`  
4. `conciliaciones`  
5. Popular + `referenciaRecaudo` por viaje  
6. AZUL  
7. ACH semanal conductores  

---

## NO ROMPER (todas las fases)

- Navegación: `NavigationService`, `ClienteShell`, `TaxistaShell`, `ActiveTripService`, overlays viaje activo.
- Timbre / `NotificationService` / FCM al aceptar viaje.
- Pool: `ViajeDisponible`, `claimTripWithReason`, bloqueo prepago en claim.
- Cierre viaje: `completarViajePorTaxista` / `finalizarViajeSeguro` (extender, no reemplazar desde cliente).
- Prepago efectivo: `approveRecargaComision`, `BloqueadoPorPagos`, `PagosTaxistaRepo.puedeTrabajar`.
- Producto pool/giras: `pool_finance.ts` — fuera de alcance salvo bugfix.

---

## ALCANCE DE CÓDIGO

- Cambios **mínimos** por fase; un PR por fase cuando sea posible.
- Feature flags en `config/finance` antes de comportamiento irreversible.
- Idempotencia en toda CF que mueva dinero.
- No guardar PAN de tarjeta en Firestore.
- Paridad reglas: cliente (`PagosTaxistaRepo`) ↔ Cloud Functions (`finance.ts`).

---

## REFERENCIA RÁPIDA ARCHIVOS CLAVE

| Área | Archivos |
|------|----------|
| Cierre viaje | `functions/src/finance.ts`, `lib/servicios/viajes_repo.dart` |
| Prepago | `lib/servicios/pagos_taxista_repo.dart`, `functions/src/recarga_admin.ts` |
| Pago semanal legacy | `pagos_taxistas`, `approvePayment` en `finance.ts` |
| Transferencia UI | `datos_transferencia_conductor_panel.dart` → migrar a cuenta RAI |
| Tarjeta | `lib/servicios/pagos/payment_gateway.dart`, `pay_config.dart` |
| Reglas | `firestore.rules` (`viajeCamposFinancierosProtegidos`) |

---

*Copiar este archivo o su contenido al prompt de Cursor antes de programar Fase 1.*
