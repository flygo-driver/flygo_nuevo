# AZUL — Página de Pago (resumen técnico)

**Fuente:** `docs/azul/Documento-tecnico-Pagina-de-Pago-AZUL.pdf` (SDP / Banco Popular)  
**Uso interno RAI:** implementar `azulCreatePaymentSession` + confirmación de pago.

---

## Modelo de integración

No es una API REST JSON típica: es **formulario HTML POST** a la Página de Pago AZUL con campos ocultos + **AuthHash** (HMAC-SHA512).

| Entorno | URL POST |
|---------|----------|
| **Pruebas** | `https://pruebas.azul.com.do/PaymentPage/` |
| **Producción** | `https://pagos.azul.com.do/PaymentPage/` |

La app Flutter debe abrir un **WebView** (o navegador) que haga POST con los campos firmados, o una página intermedia en Hosting/CF que auto-envíe el form.

---

## Campos del POST (orden del manual)

| Campo | Ejemplo doc | RAI |
|-------|-------------|-----|
| `MerchantId` | `99999999999` | `AZUL_STORE_ID` (Secret) |
| `MerchantName` | `Comercio prueba` | `OPEN ASK SERVICE SRL` o nombre afiliación |
| `MerchantType` | `ECommerce` | `ECommerce` |
| `CurrencyCode` | `$` | `$` (DOP) |
| `OrderNumber` | `1234` | `azulOrderId` determinístico por viaje |
| `Amount` | `15000` | Monto en **centavos** (confirmar con prueba sandbox) |
| `ITBIS` | `2057` | ITBIS en centavos (0 si no aplica) |
| `ApprovedUrl` | URL comercio | CF HTTPS: pago aprobado |
| `DeclinedUrl` | URL comercio | CF HTTPS: declinado |
| `CancelUrl` | URL comercio | CF HTTPS: cancelado |
| `UseCustomField1` | `0` | Opcional (`viajeId` en CustomField1) |
| `CustomField1Label` / `Value` | | |
| `UseCustomField2` | `0` | |
| `CustomField2Label` / `Value` | | |
| `AuthHash` | hash hex | Calculado en servidor (nunca en app) |

`AuthKey` **no viaja** en el POST; solo se usa para firmar.

---

## AuthHash — solicitud (ida a AZUL)

Concatenar **en este orden** (sin separadores):

```
MerchantId + MerchantName + MerchantType + CurrencyCode + OrderNumber + Amount + ITBIS
+ ApprovedUrl + DeclinedUrl + CancelUrl
+ UseCustomField1 + CustomField1Label + CustomField1Value
+ UseCustomField2 + CustomField2Label + CustomField2Value
+ AuthKey
```

- Codificación: **UTF-16 LE** (`Unicode` en C#, `mb_convert_encoding(..., 'UTF-16LE')` en PHP).
- Algoritmo: **HMAC-SHA512**.
- Salida: **hex minúscula** (`{0:x2}` por byte).

Implementar en `functions/src/azul_payment_page.ts` (nuevo módulo).

---

## AuthHash — respuesta (vuelta desde AZUL)

AZUL redirige al comercio (`ApprovedUrl` / `DeclinedUrl` / `CancelUrl`) con **query string**, por ejemplo:

```
OrderNumber, Amount, Itbis, AuthorizationCode, DateTime, ResponseCode, IsoCode,
ResponseMessage, ErrorDescription, RRN, AuthHash, CardNumber (enmascarado),
AzulOrderId, DataVaultToken, ...
```

Validar respuesta concatenando:

```
OrderNumber + Amount + AuthorizationCode + DateTime + ResponseCode + ISOCode
+ ResponseMessage + ErrorDescription + RRN + AuthKey
```

→ UTF-16 LE → HMAC-SHA512 → comparar con `AuthHash` recibido.

Si `IsoCode=00` y hash válido → marcar viaje `estadoPago=verificado`.

---

## URLs de retorno RAI (propuesta)

| Ruta CF | Uso |
|---------|-----|
| `azulReturnApproved` | `ApprovedUrl` |
| `azulReturnDeclined` | `DeclinedUrl` |
| `azulReturnCancel` | `CancelUrl` |

Base: `https://us-central1-flygo-rd.cloudfunctions.net/`

Registrar estas URLs en AZUL / probar en sandbox.

El `azulWebhook` POST actual puede coexistir si AZUL también notifica por servidor; el PDF enfatiza **redirect con query params** — priorizar validación en return URLs.

---

## Secretos Firebase

```bash
AZUL_STORE_ID=        # MerchantId
AZUL_AUTH_KEY=        # AuthKey (firmar AuthHash)
AZUL_MERCHANT_NAME=   # MerchantName (ej. OPEN ASK SERVICE SRL)
AZUL_ENV=sandbox      # sandbox | production
```

---

## Flujo app (cuando flag ON)

```
1. Cliente → azulCreatePaymentSession(viajeId)
2. CF calcula AuthHash + devuelve { actionUrl, fields } o HTML auto-post
3. App abre WebView → POST a pruebas.azul.com.do / pagos.azul.com.do
4. Usuario paga en página AZUL (3DS)
5. AZUL redirige a ApprovedUrl/DeclinedUrl/CancelUrl
6. CF valida AuthHash → actualiza viaje + pagos_azul
7. App poll azulVerifyPayment o deep link de vuelta
```

---

## Pendiente del banco (además del PDF)

- [ ] `MerchantId` real (sandbox)
- [ ] `AuthKey` real (sandbox)
- [ ] `MerchantName` exacto registrado en afiliación
- [ ] Confirmar si `Amount` es centavos enteros sin decimal
- [ ] ITBIS: ¿siempre `0` en transporte o hay que desglosar?
- [ ] Tarjetas de prueba sandbox

---

## Implementación en repo

| Archivo | Acción |
|---------|--------|
| `functions/src/azul_payment_page.ts` | **Nuevo** — hash + build form |
| `functions/src/azul.ts` | Usar módulo real en `azulCreatePaymentSession` |
| `functions/src/azul_return.ts` | **Nuevo** — Approved/Declined/Cancel |
| `lib/.../azul_payment_service.dart` | WebView POST o URL intermedia |
| `docs/AZUL_PLAN_ACTIVACION.md` | Fase 1 actualizada con este doc |

**No activar flag** hasta E2E sandbox con credenciales reales.
