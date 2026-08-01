# DOCUMENTO TÉCNICO-COMERCIAL
## Modelo de negocio e integración de pagos — RAI Driver

**Destinatario:** Servicios Digitales Popular / AZUL — Equipo de afiliación e integración técnica  
**Solicitante:** OPEN ASK SERVICE, S.R.L.  
**Marca comercial:** RAI Driver  
**Versión del documento:** 1.0  
**Fecha:** 27 de julio de 2026  
**Clasificación:** Uso comercial y técnico — Confidencial

---

## I. IDENTIFICACIÓN DEL COMERCIO

| Campo | Valor |
|-------|-------|
| Denominación social | OPEN ASK SERVICE, S.R.L. |
| Nombre comercial | RAI Driver |
| RNC | 1-32-01176-7 |
| Registro Mercantil | No. 161167SD — Cámara de Comercio y Producción de Santo Domingo |
| Domicilio | Calle 23 Este No. 39, Ensanche Luperón, Santo Domingo, Distrito Nacional, República Dominicana |
| Cuenta bancaria de liquidación | Banco Popular Dominicano — Cuenta Corriente No. **787726249** |
| Titular de cuenta | OPEN ASK SERVICE, S.R.L. |
| Aplicación móvil | RAI Driver — Android/iOS (Flutter) |
| Identificador de paquete (Android) | `com.flygo.rd2` |
| Plataforma tecnológica | Google Firebase (proyecto `flygo-rd`, región `us-central1`) |
| Política de privacidad | https://flygo-rd.web.app/legal/privacidad |
| Términos de uso | https://flygo-rd.web.app/legal/terminos |

**Contacto comercial y técnico:**  
Pablo Rafael Díaz  
Correo: ventasopenask@gmail.com  
Teléfono: (809) 420-1481

---

## II. DESCRIPCIÓN DEL NEGOCIO

RAI Driver es una plataforma tecnológica de intermediación en el sector de movilidad urbana en República Dominicana. La plataforma conecta pasajeros con conductores independientes, gestiona la asignación de viajes, el cierre digital del servicio, la emisión de factura y la liquidación económica entre las partes.

**OPEN ASK SERVICE, S.R.L.** actúa como **comercio afiliado** (merchant of record) en todas las transacciones digitales realizadas por los pasajeros. Los conductores son prestadores de servicio independientes que reciben la liquidación de su neto por parte de RAI mediante procesos internos y transferencias bancarias salientes.

---

## III. MODELO ECONÓMICO — DOS CIRCUITOS FINANCIEROS INDEPENDIENTES

El modelo de negocio de RAI Driver se estructura en **dos circuitos financieros separados e intransferibles**, los cuales no deben confundirse ni mezclarse contablemente.

### 3.1 Circuito A — Prepago operativo del conductor (NO utiliza AZUL)

| Elemento | Descripción |
|----------|-------------|
| **Parte pagadora** | Conductor / taxista registrado en la plataforma |
| **Parte beneficiaria** | OPEN ASK SERVICE, S.R.L. (RAI) |
| **Finalidad** | Adquisición de crédito operativo para cubrir la comisión de plataforma en viajes pagados en efectivo por el pasajero |
| **Método de pago** | Transferencia bancaria a la cuenta corriente No. 787726249, con verificación administrativa del comprobante |
| **Registro contable** | Campo `saldoPrepagoComisionRd` en documento `billeteras_taxista/{uid}` |
| **Monto mínimo operativo** | RD$200,00 (configurable en servidor) |
| **Consecuencia de saldo insuficiente** | Bloqueo automático del conductor para aceptar viajes en efectivo |
| **¿Reembolsable al conductor?** | No. Constituye crédito operativo, no depósito reembolsable |

**Flujo operativo:**

1. El conductor accede a la sección «Mis pagos → Recarga comisión» en la aplicación.
2. Realiza transferencia bancaria a OPEN ASK SERVICE, S.R.L. (cuenta 787726249).
3. Adjunta comprobante de pago (bauche) mediante la aplicación.
4. El administrador de RAI verifica y aprueba la recarga.
5. El sistema acredita el monto en `saldoPrepagoComisionRd`.
6. En viajes con método de pago «Efectivo», el pasajero entrega el monto íntegro al conductor en mano.
7. Al finalizar el viaje, RAI descuenta automáticamente su comisión (aproximadamente 20%) del saldo prepago del conductor.

**Colección Firestore:** `recargas_comision_taxista`  
**Cloud Function de aprobación:** `approveRecargaComision`

Este circuito **no interviene en la integración AZUL** y no constituye un cobro de pasajero a comercio.

---

### 3.2 Circuito B — Recaudo digital del pasajero (utiliza AZUL para tarjeta)

| Elemento | Descripción |
|----------|-------------|
| **Parte pagadora** | Pasajero / cliente registrado en la aplicación |
| **Parte beneficiaria** | OPEN ASK SERVICE, S.R.L. (comercio afiliado AZUL) |
| **Finalidad** | Pago del servicio de transporte contratado |
| **Métodos habilitados** | Transferencia bancaria (operativo) y tarjeta de crédito/débito vía AZUL (en integración) |
| **Comisión de plataforma** | Aproximadamente 20% del valor del viaje (configurable) |
| **Neto al conductor** | Aproximadamente 80% del valor del viaje |
| **Liquidación al conductor** | Semanal, mediante transferencia bancaria saliente (ACH) desde cuenta RAI |

**Flujo operativo — Transferencia bancaria (vigente):**

1. El pasajero selecciona método de pago «Transferencia» al confirmar el viaje.
2. La aplicación exhibe los datos de la cuenta de OPEN ASK SERVICE, S.R.L. y una referencia única de recaudo (`referenciaRecaudo`).
3. El pasajero transfiere el monto íntegro del viaje a la cuenta 787726249.
4. RAI verifica el pago (manual o conciliación automática).
5. El viaje queda en estado `estadoPago: verificado`.
6. El conductor presta el servicio y finaliza el viaje.
7. El neto correspondiente al conductor se acumula para liquidación semanal.

**Flujo operativo — Tarjeta de crédito/débito (integración AZUL):**

1. El pasajero selecciona método de pago «Tarjeta» al confirmar el viaje.
2. La aplicación invoca la Cloud Function `azulCreatePaymentSession` con el identificador del viaje.
3. El servidor crea un registro en `pagos_azul/{id}` y genera la sesión de pago AZUL.
4. El pasajero es redirigido a la **Página de Pago AZUL** (entorno seguro con autenticación 3D Secure).
5. AZUL procesa el cargo a favor del comercio OPEN ASK SERVICE, S.R.L.
6. AZUL notifica el resultado mediante webhook HTTPS (`azulWebhook`).
7. El sistema actualiza el viaje: `estadoPago: verificado`, `payment.status: captured`.
8. El conductor presta el servicio y finaliza el viaje.
9. El neto correspondiente al conductor se acumula para liquidación semanal.

---

## IV. MATRIZ DE MÉTODOS DE PAGO

| Método de pago | Pagador | Beneficiario inmediato | Comisión RAI | Prepago conductor | Integración AZUL |
|----------------|---------|------------------------|--------------|-------------------|------------------|
| Efectivo | Pasajero | Conductor (en mano) | Descuento de prepago | Obligatorio | No aplica |
| Transferencia | Pasajero | OPEN ASK SERVICE, S.R.L. | Retenida en RAI | No aplica | No aplica |
| Tarjeta | Pasajero | OPEN ASK SERVICE, S.R.L. | Retenida en RAI | No aplica | **Sí** |

---

## V. CONSIDERACIONES PARA LA AFILIACIÓN AZUL

### 5.1 Rol de OPEN ASK SERVICE, S.R.L.

- **Merchant of record:** RAI es el único comercio afiliado ante AZUL.
- **Los conductores no son sub-comercios:** no requieren afiliación individual ante AZUL.
- **Liquidación AZUL:** los fondos deben acreditarse en la cuenta corriente No. 787726249.
- **Liquidación al conductor:** realizada por RAI de forma posterior, fuera del alcance de AZUL.

### 5.2 Características de las transacciones

| Parámetro | Valor |
|-----------|-------|
| Tipo de transacción | Venta de servicio (transporte de pasajeros) |
| Moneda | DOP (peso dominicano) |
| Monto | Variable por viaje; determinado en servidor (`precio_cents`) |
| Frecuencia | Por evento (no suscripción) |
| Captura de datos de tarjeta | Exclusivamente en Página de Pago AZUL |
| Autenticación | 3D Secure (Visa Secure / MasterCard ID Check) |
| Cumplimiento PCI DSS | Delegado en AZUL; RAI no almacena PAN, CVV ni fecha de vencimiento |

### 5.3 Idempotencia y trazabilidad

- Una orden AZUL por viaje (`azulOrderId` determinístico).
- Colección dedicada: `pagos_azul/{pagoAzulId}`.
- Confirmación asíncrona vía webhook HTTPS.
- Estados normalizados: `pending`, `captured`, `failed`, `refunded`.

---

## VI. ARQUITECTURA TÉCNICA DE INTEGRACIÓN

```
┌─────────────────────┐
│  Aplicación móvil   │  Flutter (cliente) — com.flygo.rd2
│  RAI Driver         │
└──────────┬──────────┘
           │ HTTPS Callable (autenticado)
           ▼
┌─────────────────────┐
│  Cloud Functions    │  azulCreatePaymentSession
│  Firebase           │  azulVerifyPayment
│  us-central1        │  azulWebhook (HTTPS)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Página de Pago     │  Entorno seguro AZUL
│  AZUL (hosted)      │  3D Secure
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Liquidación AZUL   │  Cuenta 787726249
│  OPEN ASK SERVICE   │  Banco Popular Dominicano
└─────────────────────┘
```

### 6.1 Cloud Functions implementadas

| Función | Tipo | Descripción |
|---------|------|-------------|
| `azulCreatePaymentSession` | Callable (auth) | Inicia sesión de pago; crea registro en `pagos_azul` |
| `azulVerifyPayment` | Callable (auth) | Consulta estado del pago |
| `azulWebhook` | HTTPS | Recibe notificaciones de confirmación/rechazo de AZUL |
| `azulSimularCapturaStub` | Callable (admin) | Simulación en entorno de pruebas |

### 6.2 Variables de configuración (Secret Manager)

```
AZUL_STORE_ID=<proporcionado por AZUL>
AZUL_AUTH_KEY=<proporcionado por AZUL>
AZUL_ENV=sandbox | production
```

### 6.3 Flag de activación (Firestore: `config/finance`)

```json
{
  "pagosConTarjetaAzulHabilitados": false
}
```

*Nota: El flag se encuentra desactivado en producción hasta completar la certificación en entorno sandbox.*

### 6.4 Estado actual de la integración

| Componente | Estado |
|------------|--------|
| Arquitectura server-side | Implementada |
| UI del botón de pago (`RaiPagoTarjetaPanel`) | Implementada |
| Webhook receptor | Implementado |
| Llamada API AZUL (`ProcessPayment`) | Pendiente de credenciales |
| Certificación sandbox | Pendiente |
| Producción | Pendiente de afiliación |

---

## VII. MODELO DE DATOS (FIRESTORE)

### 7.1 Documento `viajes/{viajeId}`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `metodoPago` | string | `Efectivo`, `Transferencia` o `Tarjeta` |
| `precio_cents` | number | Monto del viaje en centavos |
| `comision_cents` | number | Comisión RAI |
| `ganancia_cents` | number | Neto del conductor |
| `estadoPago` | string | `pendiente`, `verificado`, `liquidado` |
| `uidCliente` | string | Identificador del pasajero |
| `uidTaxista` | string | Identificador del conductor |
| `referenciaRecaudo` | string | Referencia única (transferencia) |
| `pagoAzulId` | string | Referencia a colección `pagos_azul` |
| `payment.provider` | string | `azul` |
| `payment.status` | string | `pending`, `captured`, `failed` |
| `payment.azulOrderId` | string | Identificador de orden AZUL |
| `liquidado` | boolean | Indica si el neto fue pagado al conductor |
| `liquidacionId` | string | Referencia al batch de liquidación semanal |

### 7.2 Colección `pagos_azul/{pagoAzulId}`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `viajeId` | string | Viaje asociado |
| `uidCliente` | string | Pasajero que realiza el pago |
| `azulOrderId` | string | Identificador único para AZUL |
| `montoCents` | number | Monto en centavos DOP |
| `moneda` | string | `DOP` |
| `estado` | string | Estado normalizado del pago |
| `provider` | string | `azul` |
| `environment` | string | `sandbox` o `production` |

### 7.3 Documento `billeteras_taxista/{uid}` (prepago — sin AZUL)

| Campo | Descripción |
|-------|-------------|
| `saldoPrepagoComisionRd` | Crédito operativo para comisión en viajes efectivo |
| `saldoReservadoGirasRd` | Monto reservado en giras por cupos |
| `comisionPendiente` | Deuda legacy en migración |

### 7.4 Colección `recargas_comision_taxista` (prepago — sin AZUL)

Registro de solicitudes de recarga del conductor, con comprobante adjunto y flujo de aprobación administrativa.

---

## VIII. SEGURIDAD Y CUMPLIMIENTO

| Requisito | Implementación |
|-----------|----------------|
| PCI DSS | Datos sensibles de tarjeta procesados exclusivamente por AZUL |
| 3D Secure | Mediante Página de Pago AZUL |
| TLS 1.2+ | Comunicaciones cifradas (Firebase HTTPS) |
| Autenticación | Solo el pasajero titular del viaje puede iniciar el pago |
| Política de privacidad | Publicada y accesible desde la aplicación y Play Store |
| Almacenamiento de tarjeta | No se almacenan PAN, CVV ni fecha de vencimiento en servidores RAI |

---

## IX. ACLARACIONES PARA EL EQUIPO AZUL

1. **El prepago del conductor no es un pago de pasajero.** Constituye un depósito operativo del conductor a RAI para habilitar viajes en efectivo. No utiliza la pasarela AZUL.

2. **El pasajero paga a RAI, no al conductor**, cuando utiliza transferencia bancaria o tarjeta. El conductor recibe su neto mediante liquidación posterior por RAI.

3. **Existe un único comercio afiliado:** OPEN ASK SERVICE, S.R.L. No se requiere afiliación por conductor.

4. **La cuenta de liquidación es única:** Banco Popular Dominicano, Cuenta Corriente No. 787726249.

5. **La integración técnica está preparada** en arquitectura y componentes de software. Se requiere afiliación comercial, entrega de credenciales sandbox y proceso de certificación para activación en producción.

---

## X. SOLICITUD A AZUL

Por medio del presente documento, OPEN ASK SERVICE, S.R.L. solicita:

1. Inicio del proceso de **afiliación como comercio E-Commerce AZUL**.
2. Entrega de **credenciales de entorno sandbox** (Store ID, Auth Key).
3. Definición del **producto recomendado** para aplicación móvil Flutter (Página de Pago AZUL vs. Web Services API).
4. Configuración de **webhook** hacia endpoint Firebase en producción.
5. Información sobre **plazos de liquidación**, **comisiones por transacción** y **política de chargebacks** aplicable al sector transporte/movilidad.
6. Asignación de **ejecutivo comercial** y **contacto técnico de integración**.

---

## XI. DOCUMENTOS DE SOPORTE

| Documento | Ubicación |
|-----------|-----------|
| Reunión Banco Popular / AZUL / Toke | `docs/REUNION_BANCO_POPULAR_AZUL_RAI.md` |
| Solicitud formal Toke y AZUL | `docs/SOLICITUD_BANCO_POPULAR_TOKE_AZUL.md` |
| Cableado técnico de pagos | `docs/CABLEADO_PAGOS_BANCO.md` |

---

**OPEN ASK SERVICE, S.R.L.**  
RAI Driver — Plataforma de Movilidad  
República Dominicana

---

*Documento preparado para presentación ante Servicios Digitales Popular / AZUL. Quedamos a disposición para reunión técnica-comercial y demostración de la plataforma.*
