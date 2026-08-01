# Logos de marcas — requisitos AZUL E-Commerce

## Qué exige AZUL (documentación oficial)

### Obligatorios (mínimo)
- **Visa**
- **Mastercard**

### Adicionales (AZUL procesa vía Web Services)
- American Express
- Discover
- Diners Club

### Si usás 3D Secure (RAI sí lo usa)
- **Visa Secure** (antes “Verified by Visa”)
- **Mastercard ID Check**

Deben aparecer en:
1. Página principal / pagos con tarjeta
2. Política de seguridad de tarjetas
3. Checkout (app: panel de pago)

---

## Archivos en esta carpeta

| Archivo | Uso |
|---------|-----|
| `marcas-pasarela-azul-oficial.png` | **Principal** — franja oficial AZUL (Visa, MC, Amex, Discover) en web y app |
| `visa.svg` | Reserva / 3DS |
| `mastercard.svg` | Reserva / 3DS |
| `amex.svg` | Reserva |
| `discover.svg` | Reserva |
| `visa-secure.svg` | Visa Secure (3DS) — páginas legales |
| `mastercard-id-check.svg` | Mastercard ID Check (3DS) — páginas legales |

La web legal (`pagos-tarjeta`, `seguridad-tarjetas`) usa el PNG oficial en franja negra; los SVG de 3D Secure se mantienen aparte.

Si AZUL envía PNG individuales de mayor resolución, reemplazar `marcas-pasarela-azul-oficial.png` y `assets/pagos/marcas-pasarela-azul-oficial.png`.

---

## Deploy

```powershell
firebase deploy --only hosting --project flygo-rd
```
