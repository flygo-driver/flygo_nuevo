# AZUL Sandbox — activación con credenciales del banco

**Fecha:** julio 2026 · **Comercio:** OPEN ASK SERVICE S.R.L. (RAI DRIVER)

El banco entregó accesos de **pruebas** (Payment Page). La Llave Privada **no va en el repo** — solo en Secret Manager o `.secret.local`.

---

## 1. Credenciales sandbox (del correo AZUL)

| Campo | Valor |
|-------|--------|
| **MerchantID** | `39038540035` |
| **Llave Privada (AuthKey)** | Configurar con `firebase functions:secrets:set AZUL_AUTH_KEY` (valor del correo) |
| **MerchantName** | `OPEN ASK SERVICE SRL` (elegido por el comercio; confirmar con afiliación) |
| **Entorno** | `AZUL_ENV=sandbox` → `https://pruebas.azul.com.do/PaymentPage/` |

### Tarjetas de prueba

| # | PAN (sin espacios) |
|---|---------------------|
| 1 | `5424180279791732` |
| 2 | `4260550061845872` |
| 3 | `4005520000000129` |
| 4 | `5413330089600119` |
| 5 | `4012000033330026` |
| 6 | `6011000990099818` |

- **Expiración:** fecha futura válida, ej. `12/34`
- **CVV:** cualquier CVC de 3 dígitos (4 en Amex)

---

## 2. Configurar secretos (Cloud Functions)

```powershell
cd c:\dev\flygo_nuevo\functions

# Pegar MerchantID cuando lo pida:
firebase functions:secrets:set AZUL_STORE_ID
# → 39038540035

# Pegar Llave Privada del correo (no guardar en git):
firebase functions:secrets:set AZUL_AUTH_KEY
```

Variables de entorno no secretas (deploy / consola Firebase):

```
AZUL_ENV=sandbox
AZUL_MERCHANT_NAME=OPEN ASK SERVICE SRL
```

**No usar** `AZUL_USE_STUB` con credenciales reales — el POST va por `azulPaymentLaunch`.

### Emulador local

```powershell
copy .secret.local.example .secret.local
# Editar .secret.local con MerchantID + Llave Privada
firebase emulators:start --only functions,firestore
```

---

## 3. Activar flags (solo staging / pruebas)

Firestore `config/finance`:

```json
{
  "pagosConTarjetaAzulHabilitados": true
}
```

Opcional recarga taxista:

```json
{
  "recargaPrepagoAzulHabilitados": true
}
```

**Producción Play:** mantener flags `false` hasta certificación.

---

## 4. Desplegar functions AZUL

```powershell
firebase deploy --only functions:azulCreatePaymentSession,functions:azulVerifyPayment,functions:azulWebhook,functions:azulPaymentLaunch,functions:azulReturnApproved,functions:azulReturnDeclined,functions:azulReturnCancel,functions:azulCreateRecargaTaxistaSession
```

---

## 5. Flujo E2E sandbox

1. Viaje con método **Tarjeta** (staging).
2. Cliente → **Pagar con tarjeta**.
3. Navegador → `azulPaymentLaunch?order=…` → POST a `pruebas.azul.com.do`.
4. Tarjeta de prueba + exp `12/34` + CVV `123`.
5. Retorno → `azulReturnApproved` → app muestra recibo en RD$.
6. Verificar Firestore: `pagos_azul` estado `captured`, viaje `estadoPago: verificado`.

---

## 6. URLs registradas en AZUL

| Uso | URL |
|-----|-----|
| Lanzamiento POST | `https://us-central1-flygo-rd.cloudfunctions.net/azulPaymentLaunch` |
| Retorno aprobado | `…/azulReturnApproved` |
| Retorno declinado | `…/azulReturnDeclined` |
| Retorno cancelado | `…/azulReturnCancel` |
| Webhook | `…/azulWebhook` |
| Pagos con tarjeta (legal) | `https://flygo-rd.web.app/legal/pagos-tarjeta` |
| Seguridad tarjetas | `https://flygo-rd.web.app/legal/seguridad-tarjetas` |
| Vista previa POST | `https://flygo-rd.web.app/azul/preview-post` |

---

## 7. Vista previa POST (regenerar con credenciales)

```powershell
cd functions
$env:AZUL_STORE_ID="39038540035"
$env:AZUL_AUTH_KEY="<Llave Privada>"
npm run preview:azul-post
firebase deploy --only hosting
```

---

## 8. Checklist certificación

- [ ] Secretos `AZUL_STORE_ID` + `AZUL_AUTH_KEY` en Firebase
- [ ] `AZUL_USE_STUB` ausente o `false`
- [ ] Flag ON solo en staging
- [ ] Pago aprobado con tarjeta de prueba
- [ ] Recibo en app con monto RD$, autorización, RRN
- [ ] Entregables al banco (`docs/AZUL_ENTREGABLES_BANCO.md`)
- [ ] Hosting desplegado (logos + páginas legales)
