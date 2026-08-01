# Entregables AZUL — respuesta al banco (RAI DRIVER)

Borrador para responder al correo de certificación. Completar tras `firebase deploy --only hosting`.

---

## Asunto sugerido

**RE: Accesos de pruebas AZUL — entregables RAI DRIVER / OPEN ASK SERVICE SRL**

---

## Cuerpo del correo (plantilla)

Buenos días,

Gracias por los accesos de pruebas. Confirmamos integración por **Página de Pago (Payment Page POST)** — no API ni CSR.

**MerchantName en formulario:** OPEN ASK SERVICE SRL (marca comercial RAI DRIVER).

### 1. Despliegue y logos de marcas aceptadas

Páginas públicas con franja oficial de marcas (Visa, Mastercard, American Express, Discover) y logos 3D Secure:

| Recurso | URL |
|---------|-----|
| Información pagos con tarjeta | https://flygo-rd.web.app/legal/pagos-tarjeta |
| Logos (franja oficial) | https://flygo-rd.web.app/pagos/logos/marcas-pasarela-azul-oficial.png |
| Vista previa logos | https://flygo-rd.web.app/pagos/preview-logos |

La aplicación móvil RAI DRIVER muestra las mismas marcas en el panel de pago con tarjeta antes de redirigir a la Página de Pago AZUL.

### 2. Dirección permanente del comercio (incluye país)

**OPEN ASK SERVICE, S.R.L.** (RAI DRIVER)  
RNC: 1-32-01176-7  
Calle 23 Este No. 39, Ensanche Luperón  
Santo Domingo, Distrito Nacional  
**República Dominicana**  
Correo: ventasopenask@gmail.com · Tel. (809) 420-1481

### 3. Recibo claro y completo en pesos dominicanos (DOP)

Tras cada transacción aprobada, el usuario recibe en la app un **recibo digital** con:

- Nombre del comercio y RNC  
- Dirección del comercio  
- Fecha y hora (AST)  
- Número de orden y referencia AZUL  
- Código de autorización y RRN (cuando AZUL los devuelve)  
- Concepto del servicio e ID de viaje  
- Método de pago (marca y últimos 4 dígitos)  
- **Monto total en RD$ (DOP)**

Ejemplo publicado en: https://flygo-rd.web.app/legal/pagos-tarjeta (sección “Recibo de pago”).

### 4. Política de seguridad para transmisión de datos de tarjetas

Política completa publicada en:

**https://flygo-rd.web.app/legal/seguridad-tarjetas**

Resumen: RAI DRIVER no captura ni almacena PAN, CVV ni fecha de vencimiento. El usuario ingresa los datos únicamente en la **Página de Pago AZUL** (HTTPS/TLS, 3D Secure). Confirmación vía URLs de retorno firmadas (AuthHash) y webhook servidor-a-servidor.

### URLs técnicas de integración

| Endpoint | URL |
|----------|-----|
| Lanzamiento (auto-POST) | https://us-central1-flygo-rd.cloudfunctions.net/azulPaymentLaunch |
| Retorno aprobado | https://us-central1-flygo-rd.cloudfunctions.net/azulReturnApproved |
| Retorno declinado | https://us-central1-flygo-rd.cloudfunctions.net/azulReturnDeclined |
| Retorno cancelado | https://us-central1-flygo-rd.cloudfunctions.net/azulReturnCancel |

Quedamos atentos para coordinar pruebas en sandbox con MerchantID **39038540035**.

Saludos cordiales,  
OPEN ASK SERVICE S.R.L. — RAI DRIVER
