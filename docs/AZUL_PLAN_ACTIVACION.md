# Plan de activación AZUL — RAI Driver

**Proyecto Firebase:** `flygo-rd`  
**Comercio:** OPEN ASK SERVICE, S.R.L. (RNC 1-32-01176-7)  
**Cuenta liquidación:** Banco Popular 816104582  
**Versión del plan:** 1.0 — julio 2026  

---

## Propósito

Checklist operativo para **activar pagos con tarjeta (AZUL)** cuando el banco entregue credenciales, **sin romper** lo que ya está estable en Google Play:

- Viajes en **efectivo** + prepago del taxista (transferencia + bauche)
- Viajes en **transferencia** a cuenta RAI
- Liquidación semanal al taxista
- App cliente `com.flygo.rd2` en producción

**Regla de oro:** cableado ya existe; **activación = servidor → sandbox → piloto → flag ON → Play (si hace falta)**.

---

## Estado actual (Fase 0 — NO TOCAR EN PRODUCCIÓN)

| Elemento | Estado esperado |
|----------|-----------------|
| `config/finance.pagosConTarjetaAzulHabilitados` | **`false`** |
| Opción «Tarjeta» al pedir viaje | Oculta (flag OFF) |
| Recarga taxista | Transferencia + bauche + admin (sin AZUL) |
| Páginas web cumplimiento AZUL | Desplegadas en Hosting |
| API real en `azulCreatePaymentSession` | Pendiente conectar con credenciales |
| `AZUL_USE_STUB` en producción | **`false` / no configurar** |

### URLs ya entregables a AZUL

| Página | URL |
|--------|-----|
| Pagos con tarjeta | https://flygo-rd.web.app/legal/pagos-tarjeta |
| Seguridad tarjetas | https://flygo-rd.web.app/legal/seguridad-tarjetas |
| Privacidad | https://flygo-rd.web.app/legal/privacidad |

### Documentos de referencia interna

- `docs/AZUL_MODELO_NEGOCIO_FORMAL.md` — modelo dos circuitos (prepago taxista ≠ cobro cliente)
- `docs/CABLEADO_PAGOS_BANCO.md` — flags, CF, colecciones

---

## Qué activa AZUL (y qué NO)

### Sí activa (Circuito B — cliente paga viaje)

```
Cliente elige Tarjeta → AZUL cobra a OPEN ASK → webhook confirma
→ viaje estadoPago=verificado → neto taxista en liquidación semanal
```

### No activa (sigue igual)

| Flujo | Método |
|-------|--------|
| Prepago comisión taxista (efectivo) | Transferencia + bauche + `approveRecargaComision` |
| Cliente paga transferencia | Cuenta RAI + referencia + verificación |
| Cliente paga efectivo al taxista | Descuento prepago taxista |

**Recarga taxista con tarjeta = Fase 5 (futuro). No mezclar con esta activación.**

---

## Inventario técnico

### Cloud Functions (ya desplegables)

| Función | Tipo | Rol |
|---------|------|-----|
| `azulCreatePaymentSession` | onCall | Crea orden / URL de pago |
| `azulVerifyPayment` | onCall | Consulta estado (poll) |
| `azulWebhook` | HTTPS POST | Confirma captura (idempotente) |
| `azulSimularCapturaStub` | onCall admin | Solo staging con stub |

**Webhook URL (registrar en panel AZUL):**

```
https://us-central1-flygo-rd.cloudfunctions.net/azulWebhook
```

### Secretos / variables de entorno

Configurar en **Firebase Secret Manager** o env de Functions (nunca en el repo ni en la app):

```bash
AZUL_STORE_ID=<entregado por AZUL>
AZUL_AUTH_KEY=<entregado por AZUL>
AZUL_ENV=sandbox          # primero sandbox; luego production
# AZUL_USE_STUB=true      # SOLO entorno de pruebas interno, NUNCA producción
```

### Flag Firestore (`config/finance`)

```json
{
  "pagosConTarjetaAzulHabilitados": false
}
```

**No pasar a `true` hasta completar Fase 2 (sandbox E2E).**

### Colecciones Firestore

| Colección | Uso |
|-----------|-----|
| `pagos_azul/{id}` | Orden AZUL por viaje (solo CF escribe) |
| `webhook_eventos_azul/{id}` | Auditoría webhook (idempotencia) |
| `viajes/{id}` | `payment.*`, `estadoPago`, `pagoAzulId` |

### App Flutter (cliente)

| Archivo | Rol |
|---------|-----|
| `lib/servicios/pay_config.dart` | Muestra «Tarjeta» solo si flag ON |
| `lib/servicios/pagos/azul_payment_service.dart` | Callables |
| `lib/widgets/rai_pago_tarjeta_panel.dart` | Botón pagar en factura |
| `lib/widgets/rai_recibo_tarjeta_panel.dart` | Recibo post-captura |
| `lib/pantallas/comun/factura_viaje.dart` | Integración UI |

---

## Fase 1 — Al recibir credenciales (sin usuarios reales)

**Objetivo:** configurar servidor; **flag sigue OFF**.

### Checklist

- [ ] Recibir por canal seguro: Store ID, Auth Key, documentación API / Payment Page, tarjetas de prueba sandbox
- [ ] Confirmar con AZUL URL webhook (arriba) y URLs legales
- [ ] Guardar secretos en Firebase (no commitear):

  ```powershell
  cd c:\dev\flygo_nuevo
  firebase functions:secrets:set AZUL_STORE_ID
  firebase functions:secrets:set AZUL_AUTH_KEY
  ```

- [ ] Configurar `AZUL_ENV=sandbox` en deploy de functions
- [ ] **Implementar llamada API real** en `functions/src/azul.ts` → `azulCreatePaymentSession` (hoy crea registro Firestore; falta POST a AZUL según doc del banco)
- [ ] Implementar validación de firma webhook si AZUL la exige (`azulWebhook`)
- [ ] Deploy solo functions (sin tocar flag):

  ```powershell
  cd c:\dev\flygo_nuevo\functions
  npm run build
  cd ..
  firebase deploy --only functions:azulCreatePaymentSession,functions:azulVerifyPayment,functions:azulWebhook,functions:azulSimularCapturaStub
  ```

- [ ] Verificar en logs: `readAzulRuntimeConfig().configured === true`
- [ ] **Confirmar** `pagosConTarjetaAzulHabilitados` sigue `false` en Firestore

### Criterio de salida Fase 1

Servidor acepta credenciales; createSession devuelve URL real de AZUL sandbox (no stub vacío).

---

## Fase 2 — Pruebas sandbox (equipo interno)

**Objetivo:** un viaje de punta a punta; **flag OFF para público** o ON solo en cuenta de prueba.

### Opción A — Flag OFF + stub admin (sin UI tarjeta pública)

1. `AZUL_USE_STUB=true` en entorno de **staging** (no producción)
2. Admin llama `azulSimularCapturaStub` con `viajeId` de prueba
3. Verificar en Firestore: `payment.status=captured`, `estadoPago=verificado`, campos recibo (`azulAuthCode`, etc.)
4. Abrir factura en app: recibo visible

### Opción B — Flag ON temporal (solo dispositivos internos)

1. Crear viaje de prueba con `metodoPago: tarjeta` (admin o cliente test)
2. Poner `pagosConTarjetaAzulHabilitados: true` **solo durante la prueba**
3. Cliente test → Factura → Pagar con tarjeta → página AZUL sandbox
4. Pagar con tarjeta de prueba AZUL
5. Confirmar webhook en `webhook_eventos_azul` (`applied: true`)
6. Confirmar viaje: `estadoPago=verificado`, `elegibleLiquidacionSemanal` coherente
7. **Volver flag a `false` inmediatamente** al terminar

### Pruebas obligatorias

| # | Caso | Resultado esperado |
|---|------|-------------------|
| 1 | Pago exitoso | `captured` + recibo en app |
| 2 | Pago rechazado | No `verificado`; taxista puede completar según reglas |
| 3 | Webhook duplicado | Idempotente; no doble captura |
| 4 | Reintento mismo viaje | `azulCreatePaymentSession` reutiliza sesión pendiente |
| 5 | Viaje ya pagado | `alreadyPaid: true` |
| 6 | Flag OFF | Callables responden `omitido`; webhook responde 200 omitido |

### Criterio de salida Fase 2

3+ pagos sandbox exitosos documentados; rollback probado; sin impacto en viajes efectivo/transferencia.

---

## Fase 3 — Piloto controlado (producción AZUL, pocos usuarios)

**Objetivo:** tarjeta real con volumen mínimo.

- [ ] `AZUL_ENV=production` + credenciales producción (cuando AZUL certifique)
- [ ] `pagosConTarjetaAzulHabilitados: true` en Firestore
- [ ] Comunicar solo a grupo piloto (soporte + 2–3 clientes de confianza)
- [ ] Monitorear 48 h: `webhook_eventos_azul`, reclamos, liquidación semanal
- [ ] **No** activar recarga taxista con tarjeta en esta fase

### Rollback rápido (si algo falla)

```json
// config/finance — merge inmediato
{ "pagosConTarjetaAzulHabilitados": false }
```

Efecto en &lt; 1 min (app escucha snapshot):

- Desaparece opción «Tarjeta» en nuevos viajes
- Botón AZUL no se muestra
- Webhook responde omitido
- Efectivo / transferencia / prepago taxista **sin cambios**

No hace falta retirar la app de Play para rollback.

---

## Fase 4 — Producción general + Play Store

**Activar cuando:** Fase 3 sin incidentes + AZUL confirma certificación.

### Checklist

- [ ] `pagosConTarjetaAzulHabilitados: true` (global)
- [ ] Secretos producción verificados (`AZUL_ENV=production`)
- [ ] `AZUL_USE_STUB` **ausente o false**
- [ ] Publicar AAB cliente si la versión en Play **no** incluye UI recibo/tarjeta:

  ```powershell
  cd c:\dev\flygo_nuevo
  flutter build appbundle --flavor cliente --release -t lib/main.dart
  ```

  Salida: `build\app\outputs\bundle\clienteRelease\app-cliente-release.aab`

- [ ] Subir a Play Console; incrementar `versionCode`
- [ ] Actualizar descripción Play si mencionan pagos con tarjeta
- [ ] Capacitar soporte: «el cliente paga a RAI, no al taxista en tarjeta»

### Criterio de éxito Fase 4

Viajes tarjeta con `estadoPago=verificado`; liquidación semanal incluye neto tarjeta; cero regresiones en efectivo/prepago.

---

## Fase 5 — Futuro (opcional, después de estabilizar)

**Recarga prepago taxista con tarjeta** (no incluida en activación inicial):

- Nueva orden AZUL `tipo: recarga_taxista` (no `viajeId`)
- Webhook acredita `saldoPrepagoComisionRd` automático
- Confirmar con AZUL tipo de transacción «crédito operativo»
- Mantener transferencia + bauche como alternativa

**Neteo en liquidación** (escala): descontar comisión efectivo del pago semanal → menos recargas.

---

## Operación mientras esperan credenciales (hoy)

Sin tocar código ni Play:

1. Mantener `pagosConTarjetaAzulHabilitados: false`
2. Taxistas: transferir **desde Popular** a cuenta RAI (menor comisión)
3. Sugerir recargas **RD$500+** (menos frecuencia = menos comisión bancaria)
4. Responder a AZUL con URLs legales; esperar sandbox
5. **No** publicar AAB nuevo solo por AZUL
6. **No** prometer tarjeta en marketing hasta Fase 3

---

## Contactos y datos fijos

| Campo | Valor |
|-------|-------|
| Comercio | OPEN ASK SERVICE, S.R.L. |
| RNC | 1-32-01176-7 |
| Dirección | Calle 23 Este No. 39, Ensanche Luperón, Santo Domingo, DN |
| Cuenta | Banco Popular 816104582 |
| Contacto | ventasopenask@gmail.com · (809) 420-1481 |
| Paquete Android cliente | `com.flygo.rd2` |

---

## Resumen ejecutivo (una página)

```
AHORA     → Flag OFF. Play estable. Esperar credenciales AZUL.
FASE 1    → Secretos + API real en servidor. Flag OFF.
FASE 2    → Sandbox E2E. Flag OFF (o ON temporal interno).
FASE 3    → Piloto producción. Flag ON limitado.
FASE 4    → Flag ON global + AAB si falta UI en Play.
ROLLBACK  → pagosConTarjetaAzulHabilitados: false (inmediato).
FASE 5    → Recarga taxista tarjeta (después, aparte).
```

**Cuando lleguen las credenciales:** abrir este documento y ejecutar Fase 1 → Fase 2 en orden. No saltar a flag ON sin sandbox.

---

*Última actualización: julio 2026 — mantener sincronizado con `functions/src/azul.ts` y `config/finance`.*
