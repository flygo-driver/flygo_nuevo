# RAI Corporativo — Checklist go-live / prueba en teléfono

**Objetivo:** piloto controlado listo para probar encargado (web) + chofer (app).

---

## 1. Antes de la prueba

| # | Quién | Acción |
|---|--------|--------|
| 1 | Admin | Contrato empresa activo + encargado con acceso |
| 2 | Admin | **Tarifas corporativas:** impuesto transferencia **0.20%** + ISR **2%** + comisión **10%** (solo corporativo; no calle/pool) |
| 3 | Encargado | Ruta guardada (origen, pasajeros, hora, L–V) |
| 4 | Admin | Al menos **1 chofer en pool corporativo** (asignar a plantilla es opcional: al publicar auto-asigna / respalda) |
| 5 | Chofer | Instalar APK **RAI Conductor** (flavor `conductor`) con esta build |
| 6 | Encargado | Código del período visible en Cuenta / Rutas |

---

## 2. Prueba en el teléfono (chofer)

1. Abrí **RAI Conductor** → login taxista aprobado corporativo.
2. **Trabajo** o **Servicios → Mis rutas corporativas**.
3. Cuando falten ~90 min a la recogida (o «Enviar ahora» desde encargado): debe aparecer la ruta.
4. Tocá **Waze empresa** / **Maps ruta** · luego **Abrir ruta**.
5. Pedí el **código del período** a empleados/encargado (no sale en tu app).
6. Verificá código → dejá pasajeros uno a uno → completá.
7. Encargado: el viaje debe sumar en **Cuenta**.

**Mañana + noche / dos empresas:** dos plantillas con horas separadas (≥ ~90–120 min) · mismo chofer · Admin asigna ambas · en Mis rutas salen como Mañana / Noche.

---

## 3. Prueba encargado (web)

- https://flygo-rd.web.app/empresas · `Ctrl+Shift+R`
- Calendario ✕ feriado · quitar pasajero · ver chips en la tarjeta
- Pausa total → **Reactivar** (botón aparte) · **Calendario / pausas** siempre abre calendario

---

## 4. Facturación (piloto)

| Paso | Dónde |
|------|--------|
| Bauche / reportar pago | Encargado → Cuenta |
| Validar pago | Admin → Cuentas corporativas |
| Cerrar período / nuevo código | Admin marca cuenta pagada |
| **Liquidación / PDF** | Encargado → Cuenta → descargar liquidación |
| **e-CF (DGII)** | Fase 2: RAI emite y adjunta; no bloquea el piloto ops |

---

## 5. Si algo falla

| Síntoma | Qué hacer |
|---------|-----------|
| Ruta no sale al chofer | ¿Hay choferes en pool corporativo? ¿hora/día/feriado? Ver error en plantilla |
| Error publicación | Admin → empresa → rutas (banner rojo) + Alertas Admin |
| Choque de horario al asignar | Separar horas o confirmar «Asignar igual» |
| App vieja en el tel | Reinstalar APK conductor de esta build |

---

## 6. Mensaje para empleados (copiar/pegar)

> Mañana nos recoge el conductor RAI a las **[HORA]** en **[PUNTO]**.  
> No hace falta app. El encargado tiene el código del período; se lo dan al conductor al subir.  
> Si no laboramos (feriado), RRHH avisa: ese día no hay ruta.

---

## 7. Semana 1 — Deploy piloto (Laboratorio Referencia)

**Empresa piloto:** `5GztuEyAkIm18CfDI4Vu` · **Chofer:** `4CyXCaseJwPkiIj9snV8ABVkcJ92` · **Encargado:** `hRVmsfmCgvfd9UxR3dHbQS6dQhi1`

### Deploy (desde `c:\dev\flygo_nuevo`)

```powershell
cd functions
npm run build
cd ..

firebase deploy --only functions:scheduledCorporativoAvisosEscalonados,functions:scheduledCorporativoSustitutoChofer,functions:scheduledCorporativoAvisosCodigoVencimiento,functions:scheduledCorporativoViajesSinFinalizar,functions:scheduledCorporativoRutasFijas,functions:scheduledCorporativoCortePeriodos,functions:scheduledCorporativoRecogidaPerdida,functions:choferConfirmarRutaCorporativa,functions:choferConfirmarAbordajePasajeroCorp,functions:encargadoAsignarSustitutoCorporativo,functions:encargadoReenviarCodigoCorporativo,functions:encargadoPublicarRutaCorporativaAhora,functions:sincronizarPlantillaCorporativaEnVivo,functions:propagarCambioHoraCorporativa,functions:taxistaRefrescarOperacionCorporativa,functions:onViajeCorporativoOperacionRefresh,functions:adminActualizarHoraPlantillaCorporativa,functions:adminDistribuirCodigoCorporativo,functions:adminPublicarFeriadosRdAno,functions:adminAsignarSustitutoUrgenteCorp,functions:adminValidarPagoCorporativo,functions:marcarCuentaCorporativoPagada,functions:adminAsignarChoferPlantilla,functions:validarConflictosChoferCorporativo,functions:adminCalendarioChoferCorporativo,functions:iniciarViajeSeguro,functions:registrarLegMultiparadaSeguro,functions:finalizarViajeSeguro --project flygo-rd

# O todo en uno:
# .\scripts\deploy_corporativo_piloto.ps1

firebase deploy --only firestore:rules --project flygo-rd

flutter build web --release
firebase deploy --only hosting --project flygo-rd
```

### Estado deploy (2026-07-21)

| Componente | Estado |
|------------|--------|
| Cloud Functions corporativo (28) | ✅ Desplegadas en `flygo-rd` (batch sync + batch avisos/billing/admin) |
| Firestore rules | ✅ Desplegadas |
| Web hosting `/empresas` | Pendiente: `flutter build web --release` + `firebase deploy --only hosting` |
| App **1.0.9+26** conductor | `flutter build appbundle --flavor conductor` |
| App **1.0.9+26** cliente | `flutter build appbundle --flavor cliente` |
| Limpieza piloto Firestore | `node scripts/reset_piloto_corporativo.mjs` |
| Smoke automático | `node scripts/smoke_corporativo_piloto.mjs` |
| Smoke manual §7 (6 pasos) | Pendiente en dispositivo real tras limpieza |

### Google Play (dos listings)

| App | applicationId | Comando bundle |
|-----|---------------|----------------|
| **RAI Conductor** (piloto corp.) | `com.flygo.rd2.conductor` | `flutter build appbundle --flavor conductor -t lib/main.dart` |
| **RAI Driver** (cliente) | `com.flygo.rd2` | `flutter build appbundle --flavor cliente -t lib/main.dart` |

Subir cada `.aab` a su listing en Play Console (prueba cerrada primero).

### Limpieza antes de demo (pruebas agresivas de hora)

```powershell
gcloud auth application-default login
node scripts/reset_piloto_corporativo.mjs
# Encargado: Guardar ruta o Enviar ahora
node scripts/smoke_corporativo_piloto.mjs
```

### Estado deploy (2026-07-17) — histórico

| Componente | Estado |
|------------|--------|
| Cloud Functions corporativo (24) | ✅ Desplegado en `flygo-rd` |
| Firestore rules (`gps_track`, corp) | ✅ Desplegado |
| Web hosting `/empresas` | ✅ https://flygo-rd.web.app |
| APK conductor | ✅ `build/app/outputs/flutter-apk/app-arm64-v8a-conductor-release.apk` |

**Pendiente manual (Admin):** checklist §1 + feriados 2026 + smoke test §7.

### Smoke test (día 0)

| # | Verificación |
|---|----------------|
| 1 | Encargado entra en `/empresas` → tab Inicio: código, rutas hoy, perfil chofer |
| 2 | Admin asigna chofer sin conflicto (o confirma advertencia) |
| 3 | Encargado «Enviar ahora» o esperar scheduler ~90 min |
| 4 | Chofer: Mis rutas → Abrir ruta → código período → multiparada → completar |
| 5 | Firestore: `viajes/{id}/gps_track` con puntos |
| 6 | Encargado: abordaje en vivo + viaje en Cuenta |

---

*Última actualización: Semana 1 piloto — deploy y Laboratorio Referencia.*
