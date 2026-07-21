# RAI Corporativo — Modelo de negocio listo para producción

**Versión 1.0 · República Dominicana · Alineado al módulo en plataforma**

Documento maestro para **ventas, contratos y operación**. Define qué se ofrece a las empresas, cómo funciona el dinero, quién hace qué y qué debe estar activo antes del primer viaje.

---

## 1. Qué vendemos (en una frase)

**Transporte recurrente de empleados como servicio contratado:** la empresa define ruta, pasajeros y horario; RAI activa el servicio, asigna un conductor verificado de la plataforma, opera la tecnología y emite **una factura por período**. La empresa **no tiene flota**, **no nombra choferes en nómina** y **no coordina por WhatsApp cada mañana**.

---

## 2. Posicionamiento legal (no negociable)

| RAI es | RAI no es |
|--------|-----------|
| Plataforma tecnológica de intermediación | Empresa de transporte |
| Emisor de factura al cliente corporativo | Empleador del conductor |
| Gestor de contrato, cuenta y liquidación por período | Dueño de vehículos |

| El conductor es | La empresa es |
|-----------------|---------------|
| Independiente registrado en RAI Driver | Cliente del servicio corporativo |
| Quien ejecuta el viaje en calle | Quien define pasajeros, origen y horario |
| Liquidado por RAI según reglas de la plataforma | Quien paga a RAI por el período facturado |

**Mensaje comercial:** *«Usted contrata el servicio con RAI; RAI conecta con un conductor profesional de la red. Usted recibe control y una sola factura.»*

---

## 3. Actores y responsabilidades

| Actor | Herramienta | Responsabilidad |
|-------|-------------|-----------------|
| **Empresa (cliente)** | Contrato + transferencia al corte | Pagar períodos facturados; designar encargado |
| **Encargado corporativo** | App RAI **Cliente** → Centro Corporativo | Crear/editar rutas, pasajeros, horarios; lanzar o dejar publicación automática; compartir código del período; ver cuenta acumulada |
| **RAI (operaciones / admin)** | Panel admin + soporte | Activar contrato, tarifa acordada, **asignar conductor a cada ruta**, contingencias, marcar pagos, e-CF |
| **Conductor independiente** | App RAI **Conductor** | Ejecutar ruta asignada, navegar Maps/Waze, verificar código del período, completar multiparada |
| **Empleados transportados** | Ninguna (piloto) | Presentarse en punto de recogida; avisos vía RRHH de la empresa |

### Lo que el encargado **no** hace (coherencia operativa)

- No asigna conductor en la app (lo hace **RAI** tras validar documentación y disponibilidad).
- No negocia tarifa por viaje en cada corrida (tarifa queda en **contrato + plantilla**).
- No paga al chofer (paga **RAI** al cierre del período).

---

## 4. Flujo operativo de producción

```
FASE A — ALTA (RAI + empresa, 24–48 h)
  Contrato firmado
  → RAI crea empresa en sistema y activa contrato
  → Tarifa por viaje acordada (RD$ según distancia / pasajeros / frecuencia)
  → Encargado habilitado en app Cliente
  → RAI asigna conductor fijo a cada plantilla (teléfono RAI verificado)

FASE B — CONFIGURACIÓN (encargado, una vez por ruta)
  Origen confirmado (mapa / dirección)
  → Pasajeros y destinos (multiparada)
  → Días y hora de recogida
  → Guardar plantilla (tarifa automática según ruta)
  → Estado: «Conductor asignado por RAI» (solo lectura)

FASE C — CADA DÍA LABORABLE
  Publicación automática (X min antes) o «Enviar ahora»
  → Viaje exclusivo al conductor fijo (no pool público)
  → Push al conductor
  → Recogida: encargado dicta CÓDIGO DEL PERÍODO (6 dígitos, válido todo el período)
  → Conductor inicia → ruta multiparada → finaliza
  → Sistema suma tarifa al acumulado del período

FASE D — CORTE Y COBRO
  Fin del período (ej. 15 o 30 días)
  → Encargado ve total en Cuenta + historial
  → RAI emite e-CF / factura global del período
  → Empresa paga a RAI
  → RAI marca período pagado → acumulado en cero → nuevo código de período
  → RAI liquida al conductor según reglas de plataforma (plazo estándar: 24 h hábiles)
```

---

## 5. Flujo económico (tres capas)

```
EMPRESA                          RAI                           CONDUCTOR
   │                              │                                │
   │  Paga factura del período    │                                │
   │  (viajes × tarifa acordada)  │                                │
   ├─────────────────────────────►│                                │
   │                              │  Liquida neto del viaje        │
   │                              │  (tarifa − comisión plataforma)│
   │                              ├───────────────────────────────►│
   │                              │                                │
   │  Ve: total período,          │  Retiene: comisión             │  Ve: precio viaje,
   │  viajes, por chofer          │  de intermediación             │  comisión, ganancia neta
   │  NO ve nómina del chofer     │                                │  en app al finalizar
```

| Concepto | Regla de producción |
|----------|---------------------|
| **Tarifa al cliente (Precio_Base)** | Precio acordado por viaje o cálculo dinámico (km + tiempo); mínimo configurable en Admin |
| **Impuesto transferencia 0.20%** | `Precio_Base × 0.002` → se **suma** a la factura que paga la empresa (`tasa_impuesto_transferencia`) |
| **Total factura empresa** | `Precio_Base + impuesto transferencia` |
| **Retención ISR 2%** | Sobre `Precio_Base` (transporte exento ITBIS). Retiene el cliente; **no** se suma a la factura |
| **Comisión plataforma 10%** | Sobre `Precio_Base` (visible al conductor al cerrar; **no** se descuenta del prepago en corporativo) |
| **Pago al conductor 90%** | Sobre `Precio_Base`; RAI → conductor; plazo comercial 24 h hábiles |
| **Acumulado** | Cada viaje **completado** suma al `período actual` de la empresa |
| **Ciclo de cobro** | 15 o 30 días (configurable al alta) |
| **Comprobante empresa** | e-CF / factura global del período emitida por RAI (fuera de app o canal acordado) |

**Alcance (importante):** esta lógica Ley 30-26 (0.20% + ISR 2% + factura B2B) aplica **solo a RAI Corporativo**.  
**No aplica** a viaje de calle, pool de pasajeros ni giras de consumidor: ahí siguen comisión / efectivo / transferencia al chofer como el resto de la app.

**Caso de control (Admin → Tarifas corporativas):** base RD$10,000 → impuesto RD$20 → factura RD$10,020 · ISR RD$200 · comisión RD$1,000 · chofer RD$9,000.

---

## 6. Modelo comercial para cotizar a empresas

### 6.1 Variables de precio

| Variable | Cómo se define |
|----------|----------------|
| Distancia y paradas | Origen → empleado 1 → empleado 2 → … |
| Nº de pasajeros activos | Multiparada en una sola corrida |
| Frecuencia | Días/semana (L–V, personalizado, interdiario) |
| Horario | Pico mañana / noche / fin de semana |
| Zona | Disponibilidad de conductores RAI en el corredor |

### 6.2 Fórmula transparente (propuesta al cliente)

```
Costo período ≈ (tarifa por viaje acordada) × (días laborables en el período) × (nº de rutas activas)
```

**Ejemplo ilustrativo**

| Dato | Valor |
|------|-------|
| Ruta | Los Alcarrizos → Zona franca (8 pasajeros, multiparada) |
| Tarifa acordada | RD$4,500 / viaje |
| Frecuencia | L–V (22 días hábiles / mes) |
| **Estimado mensual** | RD$4,500 × 22 = **RD$99,000** / ruta |
| Facturación | Una factura RAI al corte (quincenal o mensual) |

> Comparativo de venta: *una van media vacía + chofer + seguro + combustible suele superar este monto con menos flexibilidad.*

### 6.3 Paquetes comerciales estándar

| Paquete | Perfil | Incluye |
|---------|--------|---------|
| **Piloto** | 1 ruta, 3–15 empleados, primer mes | Onboarding guiado, ejecutivo WhatsApp, tarifa preferencial período 1, activación 48 h |
| **Estándar** | 1–3 rutas recurrentes | Todo el módulo corporativo, facturación por período, soporte horario laboral |
| **Multi-sede** | Varias plantas / turnos | Varias plantillas, varios conductores fijos, cuenta consolidada por empresa |
| **Enterprise** | +50 empleados / SLA reforzado | Contrato anual, reportes bajo demanda, línea prioritaria P1/P2 |

### 6.4 Condiciones comerciales mínimas (contrato)

1. Contrato corporativo activado por RAI antes del primer viaje.
2. Encargado designado con usuario en app Cliente.
3. Conductor asignado por RAI (registrado y habilitado en RAI Driver).
4. Tarifa por viaje documentada en contrato o activación admin.
5. Ciclo de facturación y forma de pago acordados (transferencia bancaria).
6. Política de cancelación / pausa de ruta en feriados (coordinación con ejecutivo RAI).

---

## 7. Checklist de activación en producción (48 h)

### RAI (interno) — antes del go-live

- [ ] Empresa creada en `empresas_corporativas`
- [ ] `contratoActivo = true` + `tarifaViajeContratadaRd` si aplica
- [ ] Encargado en `encargadoUids`
- [ ] `clienteCorporativoHabilitado = true` en `config/productos`
- [ ] Conductor asignado a plantilla (`choferPreferidoUid` + nombre)
- [ ] Cloud Functions corporativo desplegadas
- [ ] Reglas Firestore `empresas_corporativas` desplegadas

### Empresa (cliente) — antes del primer viaje

- [ ] Encargado descargó app RAI Cliente e ingresó al Centro Corporativo
- [ ] Empresa configurada (nombre) si aplica auto-registro
- [ ] Plantilla creada: origen, pasajeros, horario, días
- [ ] Estado plantilla: **conductor asignado por RAI**
- [ ] Prueba: un viaje manual «Enviar ahora» o esperar publicación automática
- [ ] Encargado tiene código del período copiado (pestaña Cuenta)

### Conductor — antes del primer viaje

- [ ] App RAI Conductor actualizada
- [ ] Documentación al día en plataforma
- [ ] Recibió push de ruta corporativa asignada
- [ ] Conoce código del período (lo pide al encargado la primera vez)

---

## 8. Qué está en la app hoy vs. gestión RAI (piloto controlado)

| Capacidad | Estado en app | En piloto comercial |
|-----------|---------------|---------------------|
| Crear / editar rutas y pasajeros | ✅ App encargado | Cliente autónomo |
| Tarifa automática por distancia | ✅ Al guardar plantilla | Visible en editor |
| Asignar conductor a plantilla | ✅ Admin **o auto del pool** al publicar | Preferido sticky; si no hay, el sistema elige |
| Publicación automática diaria | ✅ Backend programado | Auto-asigna si hace falta |
| Viaje exclusivo conductor fijo | ✅ Canal `corporativo_fijo` | Sin pool público |
| Maps / Waze conductor | ✅ En viaje activo | — |
| Código período + acumulado cuenta | ✅ Pestaña Cuenta | — |
| Historial de viajes | ✅ App encargado | — |
| Liquidaciones archivadas | ✅ Lista pagado/pendiente | — |
| e-CF / PDF factura global en app | 🔶 En progreso | Export/cuenta hoy; e-CF DGII = fase 2 |
| Confirmación conductor 24 h | 🔶 Manual | Ejecutivo RAI coordina |
| Respaldo pool si falta conductor | ✅ Al publicar | Si el fijo no está elegible → otro del pool |
| SMS/WhatsApp a empleados | 🔶 Bajo solicitud | RRHH empresa + apoyo RAI |

**Mensaje honesto al prospecto:** *«La operación diaria es digital: la ruta se publica sola y el sistema asigna o da respaldo desde el pool corporativo. La factura fiscal e-CF (DGII) la cierra RAI al período; el encargado ve totales y bauche en la app.»*

---

## 9. SLA comercial (oferta estándar)

| Severidad | Situación | Primera respuesta RAI |
|-----------|-----------|------------------------|
| **P1** | Accidente, riesgo a pasajeros | ≤ 30 min (24/7 línea emergencia) |
| **P2** | Conductor no llegó; ruta en riesgo | ≤ 30 min (horario laboral extendido) |
| **P3** | Retraso > 15 min | ≤ 2 h |
| **P4** | Facturación, reportes | 1 día hábil |

**Compromiso de servicio (estándar comercial):**

- Si el conductor fijo no puede asistir: RAI coordina reemplazo o reprogramación con el encargado.
- El código del período **no cambia** por cambio de conductor intra-período.
- Pausar ruta en feriado: encargado desactiva plantilla o coordina con RAI.

---

## 10. Propuesta de valor por audiencia

### Para RRHH / operaciones
- Una sola configuración; la ruta se repite sola.
- Mismo conductor conoce a su gente y el recorrido.
- Sin grupo de WhatsApp a las 6 AM.

### Para finanzas / controller
- Una factura por período con total de viajes y monto en RD$.
- Desglose por conductor en app (control, no pago directo).
- Sin activo fijo (van) en balance.

### Para gerencia general
- Costo variable por viaje realizado (pausar en temporadas bajas).
- Trazabilidad: historial, código verificado al inicio, soporte RAI.
- Escalable: más rutas = más plantillas, misma plataforma.

---

## 11. Sectores objetivo (prioridad comercial RD)

| Sector | Ruta típica | Ticket mensual estimado* |
|--------|-------------|--------------------------|
| Zona franca / manufactura | Barrios → planta turno mañana | RD$80k – RD$200k / ruta |
| Call center / BPO | Nocturno fin de semana | RD$60k – RD$150k / ruta |
| Retail / supermercados | Sectores periféricos → tienda | RD$50k – RD$120k / ruta |
| Salud | Personal → clínica / hospital | RD$70k – RD$180k / ruta |
| Hotelería | Personal operativo → hotel | RD$40k – RD$100k / ruta |

*\*Ilustrativo; cotización formal según km, pasajeros y días.*

---

## 12. Script de cierre comercial (30 segundos)

> *«RAI Corporativo le quita la van, el chofer en nómina y el caos del WhatsApp. Usted define quién sube y a qué hora; nosotros activamos el servicio, asignamos un conductor verificado de la red y le mandamos **una sola factura cada quincena**. Sus empleados no instalan nada. En 48 horas puede tener la primera ruta operando.»*

---

## 13. Documentos relacionados

| Documento | Uso |
|-----------|-----|
| `RAI_CORPORATIVO_PROPUESTA_COMERCIAL.md` | Presentación comercial a prospectos |
| `RAI_CORPORATIVO_GUIA_EMPRESA.md` | Manual operativo para encargados |
| Este documento | Modelo de negocio, pricing, activación y roles |

---

## 14. Entrada al servicio (enlaces)

| Rol | Acceso |
|-----|--------|
| Encargado | [RAI Cliente — Play Store](https://play.google.com/store/apps/details?id=com.flygo.rd2) → Centro Corporativo |
| Conductor | [RAI Conductor — Play Store](https://play.google.com/store/apps/details?id=com.flygo.rd2.conductor) |
| RAI Admin | `https://flygo-rd.web.app/#/login_admin` |

**Contacto comercial piloto:** WhatsApp **CORPORATIVO** + nombre de empresa.

---

*RAI Driver · Plataforma de movilidad · República Dominicana*  
*Modelo de negocio v1.0 · Listo para ofrecer en piloto controlado con soporte RAI en asignación de conductores y facturación fiscal.*
