# RAI — Flujos por rol (referencia interna)

## Entrada única

- App móvil/web: `lib/main.dart` → `AuthGatePublic` → `RaiIdentityRouter.buildGateForUsuarioData`.
- Atajo post-login: `/auth_check` → `AuthCheck` → `RaiIdentityRouter.buildDestinationForAuthCheck`.
- Legacy (no usar en rutas nuevas): `RoleGate` en `role_gate.dart` delega al mismo router.
- Admin escritorio: `flutter run -d chrome -t lib/main.dart --route=/login_admin` (no usar `main_desktop.dart`).

Orden: sesión → términos → flavor/rol → admin | taxista (`puedeTrabajar` + email) | cliente (email).

## Taxista

```
Login → RaiTaxistaAccessGate (deuda prepago)
     → VerifyEmailGate
     → TaxistaEntry (registro → vehículo → documentos → contrato)
     → TaxistaShell (TaxistaRegistroGate + TaxistaDocumentosGate)
     → Viaje → finalizarViajeSeguro (CF) → Factura → PostViajeTaxistaFlow
```

Rutas nombradas `/viaje_disponible` y `/taxista_entry` usan `RaiTaxistaAccessGate` (misma puerta que el home).

## Cliente

```
Login → VerifyEmailGate → ClienteShell (+ ClienteRegistroGate si perfil incompleto y sin viaje activo)
     → Viaje → post-viaje / factura
```

`registroClienteCompleto == false` no bloquea si hay `viajeActivoId` o overlay post-viaje.

## Admin

Drawer agrupado: **Finanzas**, **Conductores**, **Salidas por cupos · Turismo**, tiempo real.

Cola desbloqueo: `AdminRegularizarGirasTaxista` (abuso cancelaciones en pools).

## No tocar sin revisión de negocio

| Área | Archivos |
|------|----------|
| Comisión pool finalize/cancel | `functions/src/pool_finance.ts` |
| Ledger / bloqueo prepago CF | `functions/src/finance.ts` |
| Umbrales app taxista | `lib/servicios/pagos_taxista_repo.dart` (solo lectura salvo bug) |
| Reserva cliente pool | flujo booking cliente |

## Deploy checklist

1. `firebase deploy --only firestore:rules,firestore:indexes,functions` (solo funciones tocadas en tu cambio).
2. `flutter run --release --flavor conductor -t lib/main.dart`
3. ADM: `flutter run -d chrome -t lib/main.dart --route=/login_admin`

## Prueba manual rápida

- Taxista con deuda → `BloqueadoPorPagos` antes del shell.
- Taxista Google nuevo → onboarding, no shell vacío.
- Cliente con viaje activo + perfil incompleto → entra al shell (no prompt).
- ADM → cola “Desbloquear salidas por cupos” operativa.
