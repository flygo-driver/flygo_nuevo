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
  "pagosConTarjetaAzulHabilitados": false
}
```

| Flag ON | Qué habilita |
|---------|----------------|
| `transferenciaRecaudoEnCuentaRai` | CF asigna `referenciaRecaudo` + `qrRecaudoPayload` (stub) |
| `qrRecaudoPopularHabilitado` | UI muestra QR en panel/factura |
| `pagosConTarjetaAzulHabilitados` | Método Tarjeta en reserva + botón AZUL + bloqueo finalizar sin `captured` |
| `conciliacionAutomaticaHabilitada` | Propuestas automáticas extracto |

**Lanzamiento inicial recomendado:** todos OFF → igual que hoy.

**Staging recaudo RAI:** `transferenciaRecaudoEnCuentaRai` + `qrRecaudoPopularHabilitado` + conciliación.

---

## Cloud Functions cableadas

| Function | Rol |
|----------|-----|
| `onViajeCreatedAsignarReferenciaRecaudo` | Ref + QR payload stub |
| `importarExtractoPopular` / conciliación | Ya listas |
| `azulCreatePaymentSession` | Inicia pago tarjeta |
| `azulVerifyPayment` | Poll estado |
| `azulWebhook` | HTTPS (firmar cuando haya credenciales) |
| `azulSimularCapturaStub` | Admin staging con `AZUL_USE_STUB=true` |

---

## Secret Manager / env (cuando el banco entregue API)

```bash
AZUL_STORE_ID=...
AZUL_AUTH_KEY=...
AZUL_ENV=sandbox          # o production
AZUL_USE_STUB=true        # solo staging sin credenciales reales
```

**QR Popular:** reemplazar `buildQrRecaudoPayloadStub` en `functions/src/recaudo_qr.ts` por llamada API banco (mismo campo `qrRecaudoPayload` en viaje).

---

## UI Flutter

| Widget | Dónde |
|--------|--------|
| `DatosTransferenciaRaiPanel` + `RaiRecaudoQrPanel` | Viaje en curso, post-viaje |
| `_FacturaSectionRecaudoRai` | Factura transferencia RAI |
| `RaiPagoTarjetaPanel` | Factura método Tarjeta |
| `AzulPaymentService` | Callables AZUL |

---

## Secuencia al recibir APIs del banco

1. **Transferencia/QR:** sustituir stub en `recaudo_qr.ts` → activar flags recaudo + QR → E2E conciliación.
2. **Tarjeta:** configurar secrets AZUL → quitar stub → activar `pagosConTarjetaAzulHabilitados` → webhook captura → PR2 liquidaciones.

---

## Colecciones nuevas

- `pagos_azul/{id}` — solo CF escribe; cliente/taxista lee su pago.

Campos viaje protegidos en rules: `qrRecaudo*`, `pagoAzulId`, `referenciaRecaudo`, etc.
