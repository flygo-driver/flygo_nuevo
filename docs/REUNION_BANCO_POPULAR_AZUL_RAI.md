# RAI — Documento para reunión de afiliación  
**Banco Popular Dominicano · AZUL · Toke / API Portal**  
**Empresa:** Open ASK Service SRL (plataforma RAI)  
**Uso:** Solicitud de productos, integración técnica y conciliación  
**Versión:** 1.0 — Junio 2026

---

## 1. Qué es RAI (contexto en 30 segundos)

RAI es una plataforma de movilidad (app cliente + app conductor) en República Dominicana. Los viajes tienen un monto acordado, un conductor asignado y un cierre digital con factura. Necesitamos **cobrar al cliente** y **liquidar al conductor** de forma trazable, con **tres métodos de pago** que no se mezclan entre sí.

---

## 2. Modelo de negocio (lo que el banco debe entender)

### Dos cajas separadas — no intercambiables

| Caja | Origen del dinero | Uso | ¿Se devuelve al taxista? |
|------|-------------------|-----|---------------------------|
| **Prepago comisión** | Recargas que el **conductor** paga a RAI con su propio dinero | Cubrir comisión RAI en viajes **en efectivo** | No — es crédito operativo |
| **Recaudo viajes digitales** | Pagos del **cliente** (transferencia / tarjeta) a **cuenta RAI** | Comisión RAI + neto al conductor | Sí — **liquidación semanal** del neto |

### Reglas por método de pago

| Método | ¿Quién recibe del cliente? | Comisión RAI | Prepago del conductor |
|--------|----------------------------|--------------|------------------------|
| **Efectivo** | Conductor (100% en mano) | Se descuenta del **prepago** al cerrar el viaje | **Obligatorio** para operar en efectivo |
| **Transferencia** | **RAI** (cuenta empresa) | Retenida en RAI; conductor recibe **neto semanal** | **No aplica** |
| **Tarjeta** | **RAI** (comercio afiliado AZUL) | Retenida en RAI; conductor recibe **neto semanal** | **No aplica** |

**Comisión nominal de plataforma:** ~20% del valor del viaje (configurable).  
**Neto al conductor:** 80% (si comisión 20%). Liquidación semanal en batch (ej. viernes) vía **pago a proveedores / ACH** desde cuenta empresarial RAI.

**Importante:** El dinero de transferencias y tarjetas **no** se usa para “recargar” el prepago del conductor. Son circuitos distintos.

---

## 3. Productos que solicitamos al Banco Popular / ecosistema

### Fase 0 — Ya operativo / inmediato
| Producto | Para qué |
|----------|----------|
| **Cuenta corriente empresarial RAI** | Recibir recaudos y pagar liquidaciones |
| **Internet Banking Empresarial / BIZ** | Pagos a proveedores (conductores), ACH, reportes |
| **Recaudos con referencia** | Cliente paga viaje desde App Popular / caja con **número de referencia único por viaje** |

### Fase 1 — Transferencias en app (prioridad)
| Producto | Para qué |
|----------|----------|
| **Recaudo con referencia + conciliación** | Archivo o API de movimientos identificados por referencia |
| **Botón de Pago Popular** (si aplica a app móvil / web) | Cliente paga con cuenta Popular sin reingresar datos |
| **QR AZUL** o integración equivalente | Pago instantáneo escaneando desde App Popular |

### Fase 2 — Tarjeta
| Producto | Para qué |
|----------|----------|
| **AZUL E-Commerce** (afiliación comercio) | Cobro con tarjeta crédito/débito en app RAI |
| **Integración API / Web Services AZUL** | `ProcessPayment`, 3DS, entorno pruebas `pruebas.azul.com.do` |
| **DataVault / tokenización** | No almacenar PAN en servidores RAI; PCI delegado en AZUL |

### Fase 3 — Automatización (escala)
| Producto | Para qué |
|----------|----------|
| **API Portal Popular** (plan Premium, si aplica) | Validación de cuentas, futura iniciación de pagos / open banking |
| **Toke** (evaluar con ejecutivo) | Cobro QR / celular con destino a **cuenta corporativa RAI** y referencia de viaje |

---

## 4. Flujos que debe soportar la integración

### 4.1 Efectivo (sin pasarela de cobro al cliente)
```
Cliente paga 100% al conductor en mano
→ Conductor finaliza viaje en app
→ Sistema descuenta comisión (%) del PREPAGO del conductor
→ Si prepago < mínimo (ej. RD$200): bloqueo automático hasta nueva recarga
```
**Recarga prepago:** conductor transfiere a cuenta RAI → verificación admin → crédito en prepago.  
**Producto banco:** Recaudos (mismo rail que otras recargas empresariales).

### 4.2 Transferencia (cliente → RAI)
```
Cliente confirma viaje con método Transferencia
→ App muestra: cuenta RAI + monto + REFERENCIA única (ej. RAI-VIAJE-ABC123)
→ Cliente paga desde App Popular / LBTR / QR / Botón de Pago
→ Dinero acredita en cuenta RAI
→ Conciliación por referencia → viaje marcado PAGADO_VERIFICADO
→ Conductor finaliza servicio
→ Neto del viaje suma a liquidación semanal del conductor
→ Viernes: RAI paga neto acumulado a cuenta bancaria del conductor (ACH)
```

### 4.3 Tarjeta (cliente → RAI vía AZUL)
```
Cliente elige Tarjeta al solicitar o antes de finalizar
→ AZUL procesa cobro a comercio RAI (3DS si aplica)
→ Aprobado → viaje PAGADO; comisión retenida en RAI
→ Neto suma a liquidación semanal del conductor (igual que transferencia)
```

---

## 5. Preguntas concretas para el ejecutivo del banco

1. **Recaudo con referencia:** ¿Podemos obtener archivo diario o API con referencia + monto + fecha para conciliación automática?
2. **Botón de Pago / QR / Toke:** ¿El abono puede ir siempre a la **cuenta corporativa única de RAI** con metadata o referencia por transacción?
3. **Toke:** ¿RAI puede actuar como comercio afiliado con cobro por QR/monto fijo por viaje, no a cuenta del conductor?
4. **AZUL:** ¿Una afiliación E-Commerce cubre app móvil Flutter (iOS/Android) + tokenización? ¿Plazo de liquidación AZUL → cuenta RAI?
5. **Liquidación saliente:** ¿Pago masivo semanal a N conductores vía ACH desde BIZ cumple volumen esperado?
6. **API Portal Premium:** ¿Qué APIs de pago o validación están disponibles hoy en producción vs roadmap?
7. **Comisiones:** Tabla de costos por transacción (recaudo, LBTR, AZUL, ACH saliente).

---

## 6. Datos que manejará RAI (referencia técnica — Firestore)

### Documento `viajes/{viajeId}`
| Campo | Descripción |
|-------|-------------|
| `metodoPago` | `Efectivo` \| `Transferencia` \| `Tarjeta` |
| `precio` / `precio_cents` | Monto del viaje |
| `comision_cents` / `ganancia_cents` | Comisión RAI y neto conductor |
| `estadoPago` | `pendiente` \| `verificado` \| `liquidado` |
| `referenciaRecaudo` | Referencia única para Popular (transferencia) |
| `transferenciaConfirmada` / `comprobanteTransferenciaUrl` | Verificación manual o automática |
| `payment.provider` | `cash` \| `transfer` \| `azul` |
| `payment.status` | Estados pasarela (ej. `bank_transfer_validated`, `captured`) |
| `liquidado` / `liquidacionId` | Tras pago semanal al conductor |
| `uidTaxista` | Conductor del viaje |

### Documento `billeteras_taxista/{uid}`
| Campo | Descripción |
|-------|-------------|
| `saldoPrepagoComisionRd` | Solo para comisión de viajes **en efectivo** |
| `comisionPendiente` | Legacy / deuda (migración; objetivo: minimizar) |
| `primerViajeComisionGratisConsumido` | Onboarding |

### Colección `liquidaciones_semanales/{id}` (a implementar / formalizar)
| Campo | Descripción |
|-------|-------------|
| `uidTaxista` | Conductor |
| `periodoInicio` / `periodoFin` | Semana |
| `totalNetoRd` | Suma a pagar |
| `viajeIds[]` | Viajes transferencia + tarjeta incluidos |
| `estado` | `pendiente` \| `pagado` |
| `referenciaPagoAch` | Comprobante pago saliente |

### Colección `recargas_comision_taxista` (existente)
Recargas de prepago por conductores — verificación admin — **no** mezclar con liquidación semanal.

---

## 7. Requisitos legales / operativos RAI (confirmar con banco)

- Empresa registrada **DGII** (Open ASK Service SRL)
- **RNC** y cuenta a nombre de la empresa
- Contrato de afiliación AZUL (persona jurídica): Registro Mercantil, contrato, buró
- Política **PCI**: datos de tarjeta solo en AZUL (token), nunca en Firestore plano
- **e-CF / facturación** según normativa DGII para ingresos RAI

---

## 8. Lo que NO cambia en la app (compromiso interno)

Al integrar banco/AZUL, RAI **mantiene** sin alterar:
- Navegación cliente/conductor (shells, viaje en curso, pool)
- Timbre y notificaciones al aceptar viaje
- Bloqueo por falta de prepago (efectivo) y desbloqueo por admin
- Cierre de viaje vía Cloud Function en servidor
- Estados del viaje: pendiente → aceptado → en curso → completado

Solo se perfeccionan: **destino de cobro**, **conciliación** y **liquidación semanal**.

---

## 9. Contactos útiles (públicos)

| Entidad | Recurso |
|---------|---------|
| API Portal Popular | https://www.apiportal.popularenlinea.com |
| AZUL afiliación | https://www.azul.com.do — 809-544-2985 |
| Documentación desarrollador AZUL | https://dev.azul.com.do |
| Impulsa Popular (PYME digital) | Pagos, recaudos, botón de pago |

---

## 10. Resumen ejecutivo (para cerrar la reunión)

> RAI necesita **recaudar viajes digitales en una sola cuenta empresa** (transferencia y tarjeta), **retener la comisión de plataforma**, y **pagar semanalmente el neto a cada conductor**. Los viajes en **efectivo** no pasan por esa cuenta: el conductor cobra al cliente y RAI cobra su comisión mediante **prepago** que el conductor recarga por **recaudos** al mismo banco. Solicitamos **recaudo con referencia** (fase 1), **AZUL E-Commerce** (tarjeta), y evaluación de **Botón de Pago / QR / Toke** para mejorar la experiencia del cliente sin cambiar el modelo de dos cajas.

---

*Documento preparado para reunión comercial-técnica. Ajustar montos mínimos, % comisión y día de liquidación según acuerdo final con RAI y el banco.*
