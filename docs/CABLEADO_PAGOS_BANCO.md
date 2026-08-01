# Cableado pagos banco — QR Popular + AZUL tarjeta

**Objetivo:** lanzar hoy con **efectivo + transferencia legacy**; activar recaudo RAI, QR y tarjeta solo con flags + credenciales, sin reescribir.

---

## Flags `config/finance` (default OFF)

```json
{
  "transferenciaRecaudoEnCuentaRai": false,
  "qrRecaudoPopularHabilitado": false,
  "conciliacionAutomaticaHabilitada": false,
  "transferenciaExigeVerificadoParaFinalizar": false,
  "pagosConTarjetaAzulHabilitados": false,
  "recargaPrepagoAzulHabilitados": false
}
```

| Flag ON | Qué habilita |
|---------|----------------|
| `transferenciaRecaudoEnCuentaRai` | CF asigna `referenciaRecaudo` + `qrRecaudoPayload` (stub) |
| `qrRecaudoPopularHabilitado` | UI muestra QR en panel/factura |
| `pagosConTarjetaAzulHabilitados` | Método Tarjeta en reserva + botón AZUL (viajes + Bola Ahorro) |
| `recargaPrepagoAzulHabilitados` | Taxista recarga prepago con **tarjeta débito** AZUL (convive con transferencia+bauche) |
| `conciliacionAutomaticaHabilitada` | Propuestas automáticas extracto |

**Lanzamiento inicial recomendado:** todos OFF → igual que hoy.

**Staging recaudo RAI:** `transferenciaRecaudoEnCuentaRai` + `qrRecaudoPopularHabilitado` + conciliación.

**Staging AZUL (sandbox):** `pagosConTarjetaAzulHabilitados` + `recargaPrepagoAzulHabilitados` en `true`. La recarga taxista sigue aceptando **transferencia + bauche** (admin); la tarjeta es opción adicional, no la reemplaza.

---

## Cloud Functions cableadas

| Function | Rol |
|----------|-----|
| `onViajeCreatedAsignarReferenciaRecaudo` | Ref + QR payload stub |
| `importarExtractoPopular` / conciliación | Ya listas |
| `azulCreatePaymentSession` | Inicia pago tarjeta viaje (cliente) |
| `azulCreateRecargaTaxistaSession` | Inicia recarga prepago taxista con tarjeta |
| `azulVerifyPayment` | Poll estado |
| `azulWebhook` | HTTPS (firmar cuando haya credenciales) |
| `azulSimularCapturaStub` | Admin staging con `AZUL_USE_STUB=true` |

---

## Secret Manager / env (sandbox recibido jul 2026)

```bash
AZUL_STORE_ID=39038540035          # MerchantID sandbox (correo AZUL)
AZUL_AUTH_KEY=...                  # Llave Privada — SOLO Secret Manager / .secret.local
AZUL_MERCHANT_NAME=OPEN ASK SERVICE SRL
AZUL_ENV=sandbox                   # o production
# AZUL_USE_STUB=true               # solo sin credenciales; NO usar con sandbox real
```

Guía completa: `docs/AZUL_SANDBOX_ACTIVACION.md` · Respuesta al banco: `docs/AZUL_ENTREGABLES_BANCO.md`

**QR Popular:** reemplazar `buildQrRecaudoPayloadStub` en `functions/src/recaudo_qr.ts` por llamada API banco (mismo campo `qrRecaudoPayload` en viaje).

---

## UI Flutter

| Widget | Dónde |
|--------|--------|
| `DatosTransferenciaRaiPanel` + `RaiRecaudoQrPanel` | Viaje en curso, post-viaje |
| `_FacturaSectionRecaudoRai` | Factura transferencia RAI |
| `RaiPagoTarjetaPanel` | Viaje en curso / factura / Bola Ahorro (cliente) |
| `RaiRecargaTarjetaPanel` | Mis pagos taxista — recarga débito AZUL |
| `AzulPaymentService` | Callables AZUL |

---

## Secuencia al recibir APIs del banco

1. **Transferencia/QR:** sustituir stub en `recaudo_qr.ts` → activar flags recaudo + QR → E2E conciliación.
2. **Tarjeta:** configurar secrets AZUL → quitar stub → activar `pagosConTarjetaAzulHabilitados` → webhook captura → PR2 liquidaciones.

---

## Colecciones nuevas

- `pagos_azul/{id}` — solo CF escribe; cliente/taxista lee su pago.

Campos viaje protegidos en rules: `qrRecaudo*`, `pagoAzulId`, `referenciaRecaudo`, etc.

---

## Cobertura tarjeta AZUL por producto

| Producto | Tarjeta AZUL | Notas |
|----------|--------------|-------|
| Taxi ahora / programado / multiparada / motor / turismo | Sí (flag viaje) | Colección `viajes`, flujo estándar |
| **Bola Ahorro** | Sí (flag viaje) | Método en tablero bola + pago en viaje espejo (`viajeEspejoId`) |
| Recarga prepago taxista | Sí (flag recarga) | `RaiRecargaTarjetaPanel` en Mis pagos |
| Corporativo B2B | No | Empresa liquida con RAI (transferencia/bauche) |
| Giras por cupos | No | Solo `efectivo` \| `transferencia` en `reservePoolSeats` |

Bola Ahorro sincroniza `metodoPago` bola ↔ viaje espejo vía `actualizarMetodoPagoBola`. La captura AZUL en el espejo actualiza `bolas_pueblo.estadoPago`.

---

## Modelo financiero RAI (sagrado)

| Método pasajero | Comisión RAI | Pago al taxista |
|-----------------|--------------|-----------------|
| **Efectivo** | Prepago / billetera (`billeteras_taxista`) | Pasajero paga en mano — **no** liquidación semanal |
| **Transferencia** | Retenida en RAI al verificar | Neto semanal (`liquidaciones_semanales`) |
| **Tarjeta AZUL** | Retenida en RAI al capturar | Neto semanal solo si `estadoPago=verificado` |

**Admin:** Verificar pagos → Recargas prepago (efectivo) · Comisiones semanales (digital) · Tarjetas AZUL (fallos).

**Al aprobar liquidación:** cada viaje `liquidado=true` → sale del acumulado pendiente (idempotente).

---

## Vista previa POST AZUL (para el comercio / banco)

Página estática con el mismo `<form method="post">` y `AuthHash` que genera `azulPaymentLaunch` (clave de demo; AZUL rechazará hasta credenciales reales).

| Dónde | URL |
|-------|-----|
| Hosting (tras deploy) | https://flygo-rd.web.app/azul/preview-post |
| Archivo en repo | `public/azul/preview-post/index.html` |
| Regenerar tras cambios | `cd functions && npm run preview:azul-post` |
