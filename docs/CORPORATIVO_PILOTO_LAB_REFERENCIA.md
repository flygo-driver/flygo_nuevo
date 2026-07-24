# Piloto corporativo — Laboratorio Referencia

Checklist de validación tras deploy functions + APK conductor (build 2033+).

## Datos piloto (producción `flygo-rd`)

| Rol | Valor |
|-----|-------|
| Empresa ID | `5GztuEyAkIm18CfDI4Vu` |
| Chofer UID | `4CyXCaseJwPkiIj9snV8ABVkcJ92` |
| Encargado web | https://flygo-rd.web.app/empresas |
| ADM | https://flygo-rd.web.app/login_admin |
| App conductor | flavor `conductor` (Play: RAI Conductor) |

## Tarea 1 — Functions desplegadas (18 jul 2026)

Callables/triggers actualizados en `flygo-rd`:

- `encargadoPublicarRutaCorporativaAhora`
- `taxistaAbrirViajeCorporativoEnCurso`
- `sincronizarPlantillaCorporativaEnVivo`
- `taxistaRefrescarOperacionCorporativa`
- `onViajeCorporativoOperacionRefresh`
- `onCorporativoPlantillaRutaSinChoferAlert`
- `scheduledCorporativoRutasFijas`
- `adminAsignarChoferPlantilla`

> Nota: `publicarViajeDesdePlantilla`, `asignarChoferCorporativoFijo`, `refrescarChoferOperacionCorporativa` y `ejecutarPromoverViajeCorporativoEnCurso` son **funciones internas** incluidas en los callables anteriores (no se despliegan por nombre).

## Tarea 2 — APK conductor

```powershell
flutter build apk --release --split-per-abi --flavor conductor -t lib/main.dart --build-number=2033
```

APKs esperados:

- `build/app/outputs/flutter-apk/app-armeabi-v7a-conductor-release.apk`
- `build/app/outputs/flutter-apk/app-arm64-v8a-conductor-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-conductor-release.apk`

Instalar en SM A037M (`R9PT50FEZ1J`):

```powershell
adb -s R9PT50FEZ1J install -r build\app\outputs\flutter-apk\app-arm64-v8a-conductor-release.apk
```

Componente clave: `CorporativoAutoAbrirWatcher` en `lib/shell/taxista_shell.dart`.

## Tarea 3 — Prueba E2E (30 min)

### A. Preparación ADM

1. ADM → Empresas corporativas → Laboratorio Referencia: contrato activo, código vigente.
2. ADM → Plantillas → ruta piloto: chofer asignado (`4CyXCaseJwPkiIj9snV8ABVkcJ92`), pasajeros con GPS, hora de recogida ~15 min en el futuro.

### B. Encargado publica

1. Web encargado → plantilla → **Enviar ahora**.
2. Firestore (verificar en consola):
   - `empresas_corporativas/{empresaId}/plantillas_ruta/{plantillaId}` → `ultimoViajeId` actualizado.
   - `viajes/{viajeId}` → `uidTaxista` = chofer, `corporativo: true`.
   - `chofer_operacion/{choferUid}` → `viajesHoy[].listoParaAbrir: true`.
   - `usuarios/{choferUid}` → `viajeActivoId` = viajeId (o `siguienteViajeId` si hay otro activo).

### C. Chofer (app conductor build 2033+)

1. Chofer logueado, sin viaje pool activo.
2. Encargado envía ruta → en **≤30 s** debe abrir **Viaje en curso** (auto) o banner en Mis rutas → **Abrir ruta**.
3. Flujo: Maps/Waze → Cliente a bordo → PIN código período → paradas → Finalizar.

### D. GPS track

Durante el viaje, verificar subcolección:

`viajes/{viajeId}/gps_track/{puntoId}`

Campos esperados: lat, lon, timestamp (ver `corporativo_viaje_gps_tracker.dart`).

### Criterios de éxito piloto

| # | Criterio | OK |
|---|----------|-----|
| 1 | «Enviar ahora» crea viaje con chofer asignado | ☐ |
| 2 | `chofer_operacion` se actualiza en tiempo real | ☐ |
| 3 | App abre viaje en curso sin tap manual (o con un tap en Abrir ruta) | ☐ |
| 4 | PIN corporativo valida | ☐ |
| 5 | Viaje completa y libera chofer | ☐ |
| 6 | `gps_track` tiene puntos durante el recorrido | ☐ |

### Si falla

| Síntoma | Revisar |
|---------|---------|
| No aparece en Mis rutas | `chofer_operacion/{uid}`, pull-to-refresh, callable `taxistaRefrescarOperacionCorporativa` |
| «Aún no es hora» | `publishAt`, `fechaHora`, `corporativoMinutosPublicarAntes` en viaje |
| No auto-abre | APK build ≥2033, `CorporativoAutoAbrirWatcher`, `viajeActivoId` en usuario |
| Sin chofer en viaje | ADM asignar chofer + `adminAsignarChoferPlantilla` |

## Fase 2 (pendiente comercial)

Ver petición comercial: replay GPS, incidencias ADM, auditoría, Excel .xlsx, SMS/WhatsApp empleados, registro self-service.
