# Bitácora piloto en calle — RAI (RD)

Usar durante el piloto cerrado (conductores + clientes reales).  
**Una fila por intento** (viaje, recarga, turismo, etc.). Si algo falla 3+ veces, sube prioridad de arreglo.

---

## Cómo registrar

| Campo | Qué anotar |
|-------|------------|
| **ID** | Correlativo del día (`P-001`, `P-002`…) |
| **Fecha / hora** | Hora local RD |
| **Rol** | Cliente / Conductor / ADM |
| **Flujo** | Ver lista abajo |
| **Dispositivo** | Marca, modelo, Android, versión APK |
| **Red** | WiFi / 4G / 3G / mala |
| **Resultado** | OK / Falló / Confuso |
| **Severidad** | S1 bloqueante · S2 molesto · S3 cosmético |
| **Qué pasó** | 1–2 frases concretas |
| **Evidencia** | Captura, `viajeId`, uid (últimos 4), mensaje error |
| **Acción** | Código / Ops ADM / Nada / Repetir prueba |

---

## Flujos a cubrir (checklist mínimo)

Marcar cuando al menos **1 prueba OK** en calle:

### Conductor
- [ ] Pool **Ahora** — aceptar → viaje en curso
- [ ] Pool **Programados** — aceptar → viaje en curso
- [ ] Pool **Turismo** — aceptar → viaje en curso (también vía Detalles)
- [ ] **Motor** — pool y aceptar
- [ ] **Bola** — oferta → acordar → operativo → finalizar
- [ ] **Finalizar** viaje → vuelta pool o cola siguiente
- [ ] **Prepago** — bloqueo → Mis pagos → ADM aprueba → desbloqueo
- [ ] **Ubicación** — banner verde → rojo → Abrir ajustes
- [ ] **Timbre** — solo en pestaña activa del pool
- [ ] **Giras** — publicar salida (si aplica piloto cupos)

### Cliente
- [ ] Viaje **ahora** normal — pedir → asignación → en curso
- [ ] **Programado** futuro — confirmación (no en curso antes de tiempo)
- [ ] **Multiparada** (si se usa en piloto)
- [ ] **Turismo** — espera → chofer del pool → en curso
- [ ] **Cancelar** — vuelve al home sin pantalla colgada
- [ ] **Post-viaje** / factura / calificación
- [ ] **Ubicación** — un solo aviso (sin duplicado mapa + SnackBar)

### ADM
- [ ] Liberar viaje turismo al **pool**
- [ ] Aprobar **recarga comisión**
- [ ] Torre / viajes en vivo carga sin error

---

## Plantilla por fila (copiar/pegar)

```
ID: P-___
Fecha/hora:
Rol: Cliente | Conductor | ADM
Flujo: (ej. Pool turismo → Aceptar)
APK: cliente ___ / conductor ___ (build fecha ___)
Dispositivo:
Red:
Resultado: OK | Falló | Confuso
Severidad: S1 | S2 | S3
Qué pasó:
viajeId / recargaId (si aplica):
Mensaje en pantalla (exacto):
Acción: Código | Ops | Repetir | —
Quién sigue:
```

---

## Registro de pruebas

| ID | Fecha | Rol | Flujo | Disp. | Red | OK? | Sev. | Resumen | viajeId / nota | Acción |
|----|-------|-----|-------|-------|-----|-----|------|---------|----------------|--------|
| P-001 | | | | | | | | | | |
| P-002 | | | | | | | | | | |
| P-003 | | | | | | | | | | |
| P-004 | | | | | | | | | | |
| P-005 | | | | | | | | | | |
| P-006 | | | | | | | | | | |
| P-007 | | | | | | | | | | |
| P-008 | | | | | | | | | | |
| P-009 | | | | | | | | | | |
| P-010 | | | | | | | | | | |

*(Agregar filas en la misma tabla o en hoja de cálculo compartida.)*

---

## Criterios de severidad

| Nivel | Definición | Ejemplo |
|-------|------------|---------|
| **S1** | No se puede completar el negocio | Aceptar no abre en curso; cobro mal; bloqueo incorrecto |
| **S2** | Se completa con fricción o reintento | Tarda >30 s en navegar; hay que salir y entrar |
| **S3** | Texto, color, orden visual | SnackBar duplicado, typo, botón poco claro |

**Regla de prioridad:** mismo problema **≥3 veces** en bitácora → arreglo en siguiente build.

---

## Métricas simples (fin de semana piloto)

Contar y anotar al cierre:

| Métrica | Meta piloto | Real |
|---------|-------------|------|
| Viajes completados | | |
| % aceptar → en curso &lt; 10 s | ≥ 90% | |
| Recargas ADM aprobadas &lt; 30 min | ≥ 80% | |
| Cancelaciones sin pantalla colgada | 100% | |
| Crashes reportados | 0 S1 | |

---

## Builds de referencia

Anotar al inicio del piloto:

```text
APK cliente:  flutter build apk --flavor cliente --release -t lib/main.dart --dart-define=APP_FLAVOR=cliente
APK conductor: flutter build apk --flavor conductor --release -t lib/main.dart --dart-define=APP_FLAVOR=conductor
Admin web:    https://flygo-rd.web.app/login_admin
Fecha build:  _______________
Versión / commit (opcional): _______________
```

---

## Contacto rápido piloto

| Rol | Nombre | WhatsApp / tel |
|-----|--------|----------------|
| Ops ADM recargas | | |
| Ops ADM turismo | | |
| Dev / soporte app | | |

---

*Plantilla v1 — piloto RD. Actualizar filas y checklist según lo que active el rollout.*
