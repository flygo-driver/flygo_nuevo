# RAI Corporativo — Guía operativa para empresas
**República Dominicana · Versión 2.1 (alineada a plataforma en producción)**

RAI Driver es una **plataforma tecnológica** que conecta su empresa con **conductores independientes** registrados en la app. RAI **no opera vehículos**, **no tiene flota propia** ni emplea conductores.

---

## 7. Flujo operativo

### 7.1 Flujo diario (lo que hace la app hoy)

```
Contrato RAI activo + plantilla con chofer fijo registrado
        ↓
Publicación automática (ruta fija) o envío manual «Enviar ahora»
        ↓
Viaje asignado al conductor independiente designado (no pool público)
        ↓
Push al conductor (~40 min antes, si está configurado en la plantilla)
        ↓
Recogida en empresa → encargado dicta CÓDIGO DEL PERÍODO
        ↓
Conductor verifica código e inicia ruta multiparada
        ↓
Dejada empleado por empleado → viaje completado
        ↓
Suma automática a la cuenta del período (pestaña Cuenta)
```

### 7.2 Roles en el flujo

| Actor | Acción |
|-------|--------|
| **Encargado** | Configura rutas, activa/pausa plantillas, envía viajes, comparte el código del período, coordina con RAI ante novedades |
| **Conductor independiente** | Recibe la ruta asignada en su app, ejecuta el viaje, verifica el código del período al iniciar |
| **Empleados** | Presentarse en el punto de recogida; **no usan la app** (avisos vía RRHH o canales acordados con RAI) |
| **RAI (plataforma)** | Contrato, activación del servicio, intermediación, facturación por período, soporte operativo |

---

## 8. Gestión de conductores y disponibilidad

### 8.1 Modalidad vigente en la plataforma: chofer fijo

En la **fase actual** del módulo corporativo, las rutas operan con **conductor independiente designado por RAI**:

- El encargado **no asigna** conductor en la app; ve en la plantilla el estado «Asignado por RAI» cuando corresponda.
- RAI (admin / ejecutivo) vincula el conductor por **teléfono RAI** verificado en la plantilla.
- El conductor debe estar **registrado como taxista** en RAI Driver.
- El viaje se asigna en canal **exclusivo** (`corporativo_fijo`): **no aparece en el pool público** de la app.
- Si la plantilla fija **no tiene chofer** resuelto, **no se publica** el viaje automático.

| Requisito | Detalle |
|-----------|---------|
| Registro | Taxista / conductor en RAI Driver |
| Teléfono | Debe coincidir con el de la plantilla |
| Documentación | Según políticas generales de la plataforma |
| Bloqueos | Sin bloqueos operativos que impidan el servicio corporativo contratado |

### 8.2 Confirmación 24 h y respaldo en pool (compromiso de servicio — no automatizado aún)

**Estándar comercial RAI** (gestión asistida por soporte en piloto):

| Paso | Política RAI | Estado en app |
|------|--------------|---------------|
| T−24 h | El conductor fijo confirma disponibilidad | 🔶 Soporte RAI / coordinación manual |
| Sin confirmación | Publicación al pool de conductores en la zona | 🔶 En desarrollo |
| Sin aceptación en pool | Escalamiento a encargado (SLA sección 14) | ✅ Vía soporte |
| Confirma y no se presenta | Falta grave; RAI notifica al encargado y evalúa continuidad del conductor en la plataforma | 🔶 Política comercial; no automatizada |

> **En piloto:** cualquier cambio de conductor o contingencia se coordina con su ejecutivo RAI por WhatsApp, correo o teléfono (sección 14).

### 8.3 Cambio de conductor

- El **código del período no cambia** (permanece en la cuenta corporativa hasta el corte).
- El nuevo conductor recibe la ruta con la misma información de pasajeros y paradas cuando RAI o el encargado gestionan el cambio.

---

## 9. Código de acceso y facturación

### 9.1 Código del período ✅ (disponible en app)

| Concepto | Detalle |
|----------|---------|
| **Qué es** | PIN de 6 dígitos único por período de liquidación |
| **Uso** | El conductor lo ingresa al iniciar cada viaje corporativo |
| **Ventaja** | No cambia cada mañana; el encargado lo comparte una vez por quincena/mes |
| **Renovación** | Cuando RAI registra el pago del período y reinicia la cuenta |
| **Dónde verlo** | Centro Corporativo → **Cuenta** → copiar código |

El backend acepta el código del período aunque el viaje se haya creado días antes.

### 9.2 Facturación empresa ↔ RAI

| Concepto | Detalle |
|----------|---------|
| **Ciclo** | Según contrato (ej. 15 o 30 días; default 15 al alta) |
| **Acumulado** | Viajes completados × tarifa acordada en plantilla / contrato |
| **Corte** | Al vencer el período; deuda pendiente se archiva si no se pagó |
| **Pago** | Empresa paga a RAI según condiciones comerciales |
| **Factura** | RAI emite **e-CF** por canal fiscal (**fuera de la app** en piloto). En Cuenta: resumen CSV/HTML. |
| **Reinicio** | Admin RAI marca cuenta pagada → acumulado en cero → **nuevo código** |

### 9.3 Desglose en Cuenta ✅ (disponible en app)

- Total de viajes del período  
- Monto total en RD$  
- Desglose por **conductor independiente**  
- Fechas de inicio y fin del período  
- Historial de liquidaciones archivadas (pagadas / pendientes de cobro)  

---

## 10. Pagos al conductor independiente

La prestación del transporte la ejecuta el **conductor independiente**. RAI liquida según las reglas de la plataforma (comisión).

| Concepto | Política estándar |
|----------|-------------------|
| **Plazo RAI → conductor** | 24 horas hábiles tras finalizar el viaje (salvo feriados o retenciones documentadas) |
| **Base** | Tarifa del viaje menos comisión de plataforma (contrato del conductor con RAI) |
| **Visibilidad empresa** | Acumulado agregado por período; **no** nómina ni pagos individuales al chofer |
| **Visibilidad conductor** | Detalle del viaje completado en su app de taxista |

> **Empresa paga a RAI; RAI liquida al conductor.** Son flujos distintos.

---

## 11. Gestión de incidencias

### 11.1 Canales vigentes en piloto

| Relación | Canal | Estado |
|----------|-------|--------|
| **Empresa ↔ RAI** | WhatsApp corporativo, correo, teléfono | ✅ Operativo |
| **Conductor ↔ Empresa** | Teléfono / coordinación en sitio; chat general del viaje si aplica | ⚠️ Parcial |
| **Conductor ↔ RAI** | Soporte conductor / operaciones RAI | ✅ Operativo |

### 11.2 Tipos de incidencia

| Tipo | Ejemplo | Reporte en piloto |
|------|---------|-------------------|
| Retraso | Conductor > 15 min | Encargado → soporte RAI |
| No llegada | Conductor no se presentó | Encargado → soporte RAI (P2) |
| Accidente / emergencia | Incidente vial | Conductor → RAI inmediato (P1) |
| Pasajero ausente | Empleado no en recogida | Conductor ↔ encargado |
| Facturación | Discrepancia en cuenta | Encargado → ejecutivo RAI (P4) |

### 11.3 Flujo de reporte

**Hoy (piloto):**

1. Encargado o conductor contacta a **soporte RAI** (sección 14) con nombre de empresa, ruta, fecha y hora.  
2. RAI abre seguimiento con referencia.  
3. Resolución comunicada al encargado; viaje queda en **Historial** con estado completado o nota operativa.

**Próxima fase (app):** botón «Reportar incidencia» en Centro Corporativo y en viaje activo del conductor.

### 11.4 Escalamiento (SLA)

| Severidad | Ejemplo | Primera respuesta RAI |
|-----------|---------|------------------------|
| **P1 — Crítica** | Accidente, riesgo a pasajeros | ≤ 30 minutos |
| **P2 — Alta** | Conductor no llegó; ruta en riesgo | ≤ 30 minutos |
| **P3 — Media** | Retraso > 15 min | ≤ 2 horas |
| **P4 — Baja** | Facturación, informes | 1 día hábil |

**Fuera de horario (solo P1):** línea de emergencia RAI: **WhatsApp ejecutivo asignado** *(completar número comercial antes de entregar al cliente)*.

---

## 12. Comunicación con empleados (sin app)

Los empleados **no instalan RAI Driver**. En la fase actual:

| Canal | Estado |
|-------|--------|
| Avisos por la empresa (RRHH, grupo interno) | ✅ Recomendado en piloto |
| SMS / correo / WhatsApp automáticos desde RAI | 🔶 Según contrato; configuración con ejecutivo RAI |

### Mensajes tipo (cuando la integración esté activa)

| Evento | Mensaje ejemplo |
|--------|-----------------|
| Conductor en camino | «Su transporte corporativo está en camino. Hora estimada: [HH:MM].» |
| Conductor llegó | «El conductor llegó al punto de recogida: [referencia].» |
| Retraso | «La ruta se retrasa ~15 min. Nueva hora: [HH:MM].» |
| Cambio de conductor | «Hoy su ruta será atendida por otro conductor de la red RAI.» |

> **Piloto:** el encargado comunica cambios a empleados por los canales internos de la empresa. RAI puede apoyar con aviso masivo bajo solicitud a soporte.

---

## 13. Informes y análisis

### 13.1 Disponible hoy en la app ✅

| Informe | Dónde |
|---------|--------|
| Acumulado del período (viajes, RD$, fechas) | Cuenta |
| Desglose por conductor independiente | Cuenta |
| Historial de viajes (plantilla, estado, chofer) | Historial |
| Liquidaciones archivadas | Cuenta |

### 13.2 En app hoy ✅

| Formato | Contenido |
|---------|-----------|
| **CSV / HTML** | Resumen del período desde Cuenta |

### 13.3 Bajo solicitud a ejecutivo RAI (piloto)

| Formato | Contenido |
|---------|-----------|
| **Excel (.xlsx)** | Detalle por viaje, ruta y conductor |
| **PDF / e-CF** | Resumen + comprobante fiscal (fuera de app) |

Métricas objetivo: gasto por ruta, por período, viajes por conductor, incidencias.

### 13.4 Próxima fase en app

- Exportación Excel/PDF nativa desde **Cuenta**  
- Gasto imputado por empleado  
- Envío automático de resumen al correo del encargado al cierre  

---

## 14. Soporte y SLA

### 14.1 Canales

| Canal | Contacto |
|-------|----------|
| WhatsApp corporativo | Ejecutivo RAI asignado a la cuenta |
| Correo | corporativo@flygo.do |
| Teléfono | Según contrato / ejecutivo |

*(Completar números WhatsApp reales antes de entregar al cliente.)*

### 14.2 Horario

| Día | Horario (AST) |
|-----|---------------|
| Lunes a viernes | 7:00 a.m. – 7:00 p.m. |
| Fines de semana / feriados | Solo P1 (emergencias) |

### 14.3 SLA

| Prioridad | Tiempo máx. primera respuesta |
|-----------|-------------------------------|
| P1 — Crítica | 30 minutos |
| P2 — Alta | 30 minutos |
| P3 — Media | 2 horas |
| P4 — Baja | 1 día hábil |

---

## 15. Cumplimiento legal (RD)

- **INTRANT** — marco de tránsito y transporte terrestre.  
- **Decreto 253-20** — transporte de trabajadores (validar aplicación con asesor jurídico de la empresa).

RAI facilita **trazabilidad** (viajes, conductores, historial). La empresa cumple obligaciones como contratante/empleador. RAI opera la **plataforma de intermediación**, no el transporte.

---

## 16. Capacidades de la plataforma — resumen

| Funcionalidad | Estado |
|---------------|--------|
| Encargado como Cliente + Centro Corporativo | ✅ |
| Contrato activado por admin RAI | ✅ |
| Chofer fijo por teléfono (sin pool público) | ✅ |
| Publicación automática rutas fijas | ✅ |
| Código único por período | ✅ |
| Multiparada (dejadas por empleado) | ✅ |
| Pausar / activar plantillas | ✅ |
| Acumulado y liquidación por período | ✅ |
| Confirmación 24 h + pool respaldo automático | 🔶 Soporte / roadmap |
| Incidencias en app (módulo corporativo) | ✅ Historial + validación Admin |
| SMS / correo / WhatsApp a empleados | 🔶 Según contrato (RRHH) |
| Export CSV/HTML en app | ✅ Cuenta |
| Export Excel / PDF / e-CF en app | 🔶 Roadmap / e-CF fuera de app |
| Múltiples puntos de recogida (hasta 10) | 🔶 Multiparada de dejadas; recogidas múltiples según contrato |

**Leyenda:** ✅ En producción · 🔶 Piloto manual, contrato o roadmap

---

## 17. Checklist de inicio

- [ ] Encargado registrado como **Cliente**  
- [ ] RAI creó empresa y **activó contrato**  
- [ ] Plantilla con origen, pasajeros, horario y **chofer fijo** (teléfono RAI)  
- [ ] Código del período compartido con el conductor  
- [ ] Primer viaje en **Historial** y reflejado en **Cuenta**  
- [ ] Contacto de soporte RAI guardado por el encargado  

---

*RAI Driver — Plataforma de conexión · República Dominicana · Documento confidencial*
