import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentReference,
  type QueryDocumentSnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { logAdminAudit } from "./audit.js";
import { getComisionViajePorcentajeCached } from "./comision_viaje_pct.js";
import { getComisionPrepagoConfig } from "./finance.js";
import {
  fetchGiraAbusoUmbral,
  mergeGiraAbusoBloqueadoSiAplica,
} from "./gira_abuso_util.js";
import { generarReferenciaRecaudoPool } from "./pool_referencia.js";
import {
  UMBRAL_COMISION_LEGACY_RD,
  bloqueoOperativoPorComisionEfectivo,
  comisionPendienteRdFromBilletera,
  saldoDisponiblePrepagoRdFromBilletera,
  saldoPrepagoRdFromBilletera,
  saldoReservadoGirasRdFromBilletera,
} from "./taxista_cola_promote_logic.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function numOr0(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return 0;
}

const MSG_LEGACY_GIRA_SIN_COMISION_ESTIMADA =
  "Esta gira fue creada con una versión anterior del sistema. Por favor, cancélala y crea una nueva.";

function hasComisionGiraEstimadaValida(pool: AnyMap): boolean {
  const raw = pool.comisionGiraEstimadaRd;
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 1e-9) return true;
  if (typeof raw === "string") {
    const n = Number(raw);
    if (Number.isFinite(n) && n > 1e-9) return true;
  }
  return false;
}

function roleFromUserDoc(data: AnyMap | undefined): string {
  if (!data) return "";
  const rol = data.rol;
  return typeof rol === "string" ? rol : "";
}

function normalizeRoleRaw(raw: string): string {
  let r = raw.trim().toLowerCase();
  if (r === "administrador") r = "admin";
  if (r === "driver") r = "taxista";
  if (r === "user") r = "cliente";
  return r;
}

/** Lee `usuarios` + `roles`; prioriza admin/taxista si hay datos mixtos legacy. */
async function getRole(uid: string): Promise<string> {
  const [userSnap, rolSnap] = await Promise.all([
    db().collection("usuarios").doc(uid).get(),
    db().collection("roles").doc(uid).get(),
  ]);
  const fromUser = normalizeRoleRaw(roleFromUserDoc(userSnap.data() as AnyMap | undefined));
  const fromRoles = normalizeRoleRaw(String((rolSnap.data() as AnyMap | undefined)?.rol ?? ""));
  if (fromUser === "admin" || fromRoles === "admin") return "admin";
  if (fromUser === "taxista" || fromRoles === "taxista") return "taxista";
  return fromUser || fromRoles || "";
}

async function ensureIdempotencyStart(
  key: string,
  op: string,
  uid: string,
): Promise<{
  done: boolean;
  result?: AnyMap;
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
}> {
  const ref = db().collection("idempotency_keys").doc(`${op}_${key}`);
  const snap = await ref.get();
  if (snap.exists) {
    const data = (snap.data() ?? {}) as AnyMap;
    if (data.status === "done" && typeof data.result === "object" && data.result) {
      return { done: true, result: data.result as AnyMap, ref };
    }
  }
  await ref.set(
    {
      op,
      uid,
      status: "started",
      startedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { done: false, ref };
}

async function markIdempotencyDone(
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
  result: AnyMap,
): Promise<void> {
  await ref.set(
    {
      status: "done",
      result,
      doneAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function ensurePoolOwnerOrAdmin(role: string, uidActor: string, ownerTaxistaId: string): void {
  if (role === "admin") return;
  if (role !== "taxista" || ownerTaxistaId !== uidActor) {
    throw new HttpsError("permission-denied", "No autorizado para este pool");
  }
}

/** Marca reservas activas al cancelar la gira completa (chofer/admin). Devuelve cantidad cancelada. */
function marcarReservasCanceladasPorGiraTx(
  tx: Transaction,
  reservaDocs: QueryDocumentSnapshot[],
  motivo: string,
): number {
  let n = 0;
  const motivoTxt = motivo.trim() || "cancelacion";
  for (const doc of reservaDocs) {
    const r = (doc.data() ?? {}) as AnyMap;
    const estadoRes = String(r.estado ?? "").trim().toLowerCase();
    if (estadoRes === "cancelado" || estadoRes === "cancelado_cliente" || estadoRes === "cancelado_gira") {
      continue;
    }
    if (estadoRes !== "reservado" && estadoRes !== "pagado") continue;
    tx.update(doc.ref, {
      estado: "cancelado_gira",
      canceladoPor: "chofer",
      canceladoEn: FieldValue.serverTimestamp(),
      motivoCancelacion: motivoTxt,
      updatedAt: FieldValue.serverTimestamp(),
    });
    n += 1;
  }
  return n;
}

/** Contadores del pool a cero cuando la gira se cancela por completo. */
function patchPoolCanceladoGira(motivo: string): AnyMap {
  return {
    estado: "cancelado",
    asientosReservados: 0,
    asientosPagados: 0,
    montoReservado: 0,
    montoPagado: 0,
    asientosFirmesSalida: 0,
    canceladoAt: FieldValue.serverTimestamp(),
    motivoCancelacion: motivo.trim() || "cancelacion",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function poolUsaRecaudoCentral(pool: AnyMap): boolean {
  return String(pool.recaudoModelo ?? "").trim().toLowerCase() === "central";
}

function splitRecaudoReservaTotal(
  total: number,
  pct: number,
): { comisionRaiRd: number; netoOrganizadorRd: number } {
  const bruto = Math.max(0, Number.isFinite(total) ? total : 0);
  const comisionRaiRd = round2(bruto * (pct / 100));
  const netoOrganizadorRd = round2(bruto - comisionRaiRd);
  return { comisionRaiRd, netoOrganizadorRd };
}

/** Mismo % que viajes en efectivo (`config/comision`). */
export async function getComisionGiraPorcientoFromRemote(): Promise<number> {
  return getComisionViajePorcentajeCached();
}

/** Precio por asiento = monto final por persona (sin multiplicar por sentido). */
function priceMultSentido(_sentido: unknown): number {
  return 1;
}

function comisionRealRdFromAsientos(
  pool: AnyMap,
  asientosReales: number,
  pct: number,
): number {
  const mult = priceMultSentido(pool.sentido);
  const precio = Number(pool.precioPorAsiento ?? 0);
  if (!Number.isFinite(precio) || precio < 0) return 0;
  if (!Number.isFinite(asientosReales) || asientosReales <= 0) return 0;
  const base = asientosReales * mult * precio;
  return round2(base * (pct / 100));
}

/** Comisión RAI sumando cada reserva por su `total` (asientos × precio al reservar). */
function comisionRaiRdFromReservaDocs(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
  includeReserva: (r: AnyMap) => boolean,
  pct: number,
): number {
  let sum = 0;
  for (const d of docs) {
    const r = (d.data() ?? {}) as AnyMap;
    if (!includeReserva(r)) continue;
    const total = numOr0(r.total);
    if (total <= 0) continue;
    sum += splitRecaudoReservaTotal(total, pct).comisionRaiRd;
  }
  return round2(sum);
}

function reservaEsEfectivoFirm(r: AnyMap): boolean {
  const e = String(r.estado ?? "").toLowerCase().trim();
  const m = String(r.metodoPago ?? "").toLowerCase().trim();
  return e === "reservado" && m === "efectivo";
}

function reservaEsFirmeParaComision(r: AnyMap): boolean {
  const e = String(r.estado ?? "").toLowerCase().trim();
  const m = String(r.metodoPago ?? "").toLowerCase().trim();
  if (e === "pagado") return true;
  return e === "reservado" && m === "efectivo";
}

/** Cupos que cuentan para salir: pagados + reservas en efectivo (compromiso al abordar). No cuenta transferencia pendiente de comprobante. */
function firmSeatsFromReservaDocs(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
): number {
  let firm = 0;
  for (const d of docs) {
    const r = (d.data() ?? {}) as AnyMap;
    const e = String(r.estado ?? "").toLowerCase().trim();
    const m = String(r.metodoPago ?? "").toLowerCase().trim();
    const s = Number(r.seats ?? 0);
    if (!Number.isFinite(s) || s <= 0) continue;
    if (e === "pagado") firm += s;
    else if (e === "reservado" && m === "efectivo") firm += s;
  }
  return firm;
}

/** Cupos en efectivo reservados en app (comisión RAI vía prepago al iniciar salida central). */
function firmEfectivoSeatsFromReservaDocs(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
): number {
  let firm = 0;
  for (const d of docs) {
    const r = (d.data() ?? {}) as AnyMap;
    const e = String(r.estado ?? "").toLowerCase().trim();
    const m = String(r.metodoPago ?? "").toLowerCase().trim();
    const s = Number(r.seats ?? 0);
    if (!Number.isFinite(s) || s <= 0) continue;
    if (e === "reservado" && m === "efectivo") firm += s;
  }
  return firm;
}

/** Firma después de marcar una reserva como pagada (la reserva sigue en snapshot como reservado hasta el commit). */
function firmSeatsAfterConfirmPayment(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
  confirmedId: string,
): number {
  let firm = 0;
  for (const d of docs) {
    const raw = (d.data() ?? {}) as AnyMap;
    const r = d.id === confirmedId ? { ...raw, estado: "pagado" } : raw;
    const e = String(r.estado ?? "").toLowerCase().trim();
    const m = String(r.metodoPago ?? "").toLowerCase().trim();
    const s = Number(r.seats ?? 0);
    if (!Number.isFinite(s) || s <= 0) continue;
    if (e === "pagado") firm += s;
    else if (e === "reservado" && m === "efectivo") firm += s;
  }
  return firm;
}

function parseDateInput(raw: unknown): Date | null {
  if (typeof raw === "number" && Number.isFinite(raw)) return new Date(raw);
  if (typeof raw === "string" && raw.trim()) {
    const d = new Date(raw);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return null;
}

function cuposReservaComision(
  cuposComisionRai: number,
  minParaConfirmar: number,
  capacidad: number,
): number {
  const cap = capacidad > 0 ? capacidad : 1;
  const minConf = minParaConfirmar > 0 ? minParaConfirmar : cap;
  const tope = Math.min(Math.max(Math.trunc(cuposComisionRai), 1), cap);
  return Math.min(tope, minConf, cap);
}

function taxistaRegistroPerfilCompleto(ud: AnyMap): boolean {
  if (ud.registroTaxistaCompleto === false) return false;
  const nombre = String(ud.nombre ?? "").trim();
  if (nombre.length < 2) return false;
  const telefono = String(ud.telefono ?? "").replace(/\D/g, "");
  if (telefono.length !== 10 && !(telefono.length === 11 && telefono.startsWith("1"))) {
    return false;
  }
  const placa = String(ud.placa ?? "").trim();
  if (!placa) return false;
  const modelo = String(ud.vehiculoModelo ?? ud.modelo ?? "").trim();
  if (!modelo) return false;
  const color = String(ud.vehiculoColor ?? ud.color ?? "").trim();
  if (!color) return false;
  const anioRaw = ud.anio ?? ud.vehiculoAnio;
  const anio = typeof anioRaw === "number" ? anioRaw : Number(anioRaw);
  if (!Number.isFinite(anio) || anio < 1990) return false;
  if (ud.registroTaxistaCompleto === true) return true;
  return false;
}

async function poolRecaudoCentralHabilitado(): Promise<boolean> {
  try {
    const snap = await db().collection("config").doc("finance").get();
    return (snap.data() ?? {}).poolRecaudoCentralHabilitado === true;
  } catch {
    return false;
  }
}

function mensajeGiraAbusoBloqueo(
  creadas: number,
  canceladas: number,
  ratioMax: number,
  diasHastaReinicio: number | null,
): string {
  const pct = creadas > 0 ? Math.round((canceladas / creadas) * 100) : 0;
  const maxPct = Math.round(ratioMax * 100);
  const ventana =
    diasHastaReinicio != null && diasHastaReinicio > 0
      ? ` El contador se reinicia solo en ${diasHastaReinicio} día(s).`
      : "";
  return (
    `Has cancelado muchas salidas por cupos sin confirmar comisión ` +
    `(${canceladas} de ${creadas} en esta ventana, ${pct}% — máximo ${maxPct}%). ` +
    `Contacta a soporte RAI: un administrador debe regularizar tu cuenta ` +
    `para que puedas publicar otra salida.${ventana}`
  );
}

function trimOrNull(raw: unknown): string | null {
  const s = String(raw ?? "").trim();
  return s.length > 0 ? s : null;
}

function stringListOrNull(raw: unknown): string[] | null {
  if (!Array.isArray(raw)) return null;
  const out = raw
    .map((e) => String(e ?? "").trim())
    .filter((e) => e.length > 0);
  return out.length > 0 ? out : null;
}

const TOKEN_ENTRADA_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generarTokenEntradaGira(): string {
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += TOKEN_ENTRADA_CHARS[Math.floor(Math.random() * TOKEN_ENTRADA_CHARS.length)];
  }
  return `RAI-${code}`;
}

function normalizarTokenEntrada(raw: unknown): string | null {
  const t = String(raw ?? "").trim().toUpperCase();
  if (!/^RAI-[A-Z0-9]{6,12}$/.test(t)) return null;
  return t;
}

/** Índice rápido token → reserva (solo Admin SDK escribe). */
function asignarTokenEntradaSiFaltaEnTx(
  tx: Transaction,
  poolId: string,
  reservaId: string,
  res: AnyMap,
  reservaPatch: AnyMap,
): void {
  const existing = trimOrNull(res.tokenEntrada);
  if (existing) return;

  const seats = Math.max(1, Math.trunc(numOr0(res.seats)));
  const token = generarTokenEntradaGira();
  reservaPatch.tokenEntrada = token;
  reservaPatch.tokenGeneradoAt = FieldValue.serverTimestamp();
  reservaPatch.tokenEstado = "activo";
  reservaPatch.tokenAsientosValidados = 0;

  tx.set(db().collection("gira_tickets").doc(token), {
    poolId,
    reservaId,
    uidCliente: String(res.uidCliente ?? ""),
    seats,
    tokenEstado: "activo",
    createdAt: FieldValue.serverTimestamp(),
  });
}

function anularTokenEntradaEnTx(
  tx: Transaction,
  res: AnyMap,
  reservaPatch: AnyMap,
): void {
  const token = trimOrNull(res.tokenEntrada);
  if (!token) return;
  reservaPatch.tokenEstado = "anulado";
  tx.set(
    db().collection("gira_tickets").doc(token),
    {
      tokenEstado: "anulado",
      anuladoAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function ventanaValidacionTokenGira(fechaSalida: Date, now: Date): boolean {
  const ms = fechaSalida.getTime() - now.getTime();
  const h24 = 86_400_000;
  // Desde 24 h antes hasta 6 h después de la salida programada.
  return ms <= h24 && ms >= -6 * h24;
}

/** Campos extendidos de contenido para publicación profesional de giras. */
function mergePoolContenidoExtraFromInput(d: AnyMap): AnyMap {
  const out: AnyMap = {};
  const optionalStrings: Array<[string, unknown]> = [
    ["nombreGira", d.nombreGira],
    ["eslogan", d.eslogan],
    ["provincia", d.provincia],
    ["municipio", d.municipio],
    ["duracionTexto", d.duracionTexto],
    ["direccionExacta", d.direccionExacta],
    ["referenciaLugar", d.referenciaLugar],
    ["noIncluye", d.noIncluye],
    ["queDebeLlevar", d.queDebeLlevar],
    ["reglas", d.reglas],
    ["observaciones", d.observaciones],
  ];
  for (const [key, raw] of optionalStrings) {
    const v = trimOrNull(raw);
    if (v) out[key] = v;
  }
  if (typeof d.ninosPermitidos === "boolean") out.ninosPermitidos = d.ninosPermitidos;
  if (typeof d.mascotasPermitidas === "boolean") out.mascotasPermitidas = d.mascotasPermitidas;
  if (typeof d.edadMinima === "number" && Number.isFinite(d.edadMinima) && d.edadMinima > 0) {
    out.edadMinima = Math.trunc(d.edadMinima);
  }
  if (
    typeof d.maxAsientosPorCompra === "number" &&
    Number.isFinite(d.maxAsientosPorCompra) &&
    d.maxAsientosPorCompra > 0
  ) {
    out.maxAsientosPorCompra = Math.min(99, Math.trunc(d.maxAsientosPorCompra));
  }
  if (Array.isArray(d.itinerario)) {
    const it = d.itinerario
      .map((row) => {
        if (!row || typeof row !== "object") return null;
        const m = row as AnyMap;
        const hora = trimOrNull(m.hora) ?? "";
        const actividad = trimOrNull(m.actividad) ?? "";
        if (!hora && !actividad) return null;
        return { hora, actividad };
      })
      .filter((x): x is { hora: string; actividad: string } => x != null);
    if (it.length > 0) out.itinerario = it;
  }
  return out;
}

async function pushPoolGiraClientes(
  uids: string[],
  title: string,
  body: string,
  poolId: string,
): Promise<void> {
  const unique = [...new Set(uids.filter((u) => u.length > 0))];
  if (unique.length === 0) return;
  const messaging = getMessaging();
  for (const uid of unique) {
    const tokSnap = await db().collection("push_tokens").doc(uid).get();
    const raw = tokSnap.data()?.tokens;
    const tokens = Array.isArray(raw)
      ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
      : [];
    if (tokens.length === 0) continue;
    try {
      await messaging.sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: {
          type: "gira_cupos_actualizada",
          poolId,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            channelId: "rai_giras_cupos_cliente_v1",
            sound: "default",
          },
        },
        apns: { payload: { aps: { sound: "default" } } },
      });
    } catch (e) {
      logger.warn("[pushPoolGiraClientes] fallo uid=" + uid, e);
    }
  }
}

/**
 * Publicar gira por cupos: billetera + contadores + pool + ledger en una transacción (Admin SDK).
 * El cliente ya no escribe `billeteras_taxista` (Firestore rules: solo admin).
 */
export const crearPoolGira = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;

  const userPre = await db().collection("usuarios").doc(uid).get();
  const udPre = (userPre.data() ?? {}) as AnyMap;
  const role = await getRole(uid);
  const perfilTaxistaOk = taxistaRegistroPerfilCompleto(udPre);
  if (role !== "taxista" && role !== "admin" && !perfilTaxistaOk) {
    throw new HttpsError(
      "permission-denied",
      "Debes iniciar sesión como taxista para publicar salidas por cupos.",
    );
  }

  const d = (request.data ?? {}) as AnyMap;
  const tipo = trimOrNull(d.tipo);
  const sentido = trimOrNull(d.sentido) ?? "ida";
  const origenTown = trimOrNull(d.origenTown);
  const destino = trimOrNull(d.destino);
  const fechaSalida = parseDateInput(d.fechaSalida);
  const fechaVueltaRaw = d.fechaVuelta;
  const fechaVuelta =
    fechaVueltaRaw == null || fechaVueltaRaw === ""
      ? null
      : parseDateInput(fechaVueltaRaw);
  const capacidad = Math.trunc(numOr0(d.capacidad));
  const minParaConfirmar = Math.trunc(numOr0(d.minParaConfirmar));
  const cuposComisionRai = Math.trunc(numOr0(d.cuposComisionRai));
  const precioPorAsiento = numOr0(d.precioPorAsiento);
  const depositPct = numOr0(d.depositPct) > 1 ? numOr0(d.depositPct) / 100 : numOr0(d.depositPct);
  const feePct = numOr0(d.feePct) > 1 ? numOr0(d.feePct) / 100 : numOr0(d.feePct);

  if (!tipo || !origenTown || !destino || !fechaSalida) {
    throw new HttpsError("invalid-argument", "Faltan datos obligatorios de la salida.");
  }
  if (capacidad < 1) throw new HttpsError("invalid-argument", "Capacidad inválida.");
  if (precioPorAsiento <= 0) {
    throw new HttpsError("invalid-argument", "Precio por asiento inválido.");
  }
  const cap = capacidad > 0 ? capacidad : 1;
  if (cuposComisionRai < 1 || cuposComisionRai > cap) {
    throw new HttpsError("invalid-argument", `Cupos RAI para comisión debe estar entre 1 y ${cap}.`);
  }
  if (sentido === "ida_y_vuelta" && !fechaVuelta) {
    throw new HttpsError("invalid-argument", "Selecciona la fecha de vuelta.");
  }
  if (fechaVuelta && fechaVuelta.getTime() < fechaSalida.getTime()) {
    throw new HttpsError("invalid-argument", "La vuelta no puede ser antes de la salida.");
  }

  if (!perfilTaxistaOk) {
    throw new HttpsError(
      "failed-precondition",
      "Completá tu registro de conductor en RAI antes de publicar salidas por cupos.",
    );
  }

  const [pct, prepagoCfg, abuso, recaudoCentral] = await Promise.all([
    getComisionGiraPorcientoFromRemote(),
    getComisionPrepagoConfig(),
    fetchGiraAbusoUmbral(),
    poolRecaudoCentralHabilitado(),
  ]);
  const minOperativoRd = prepagoCfg.minimoOperativoRd;
  const mult = priceMultSentido(sentido);
  const cuposReserva = cuposReservaComision(cuposComisionRai, minParaConfirmar, capacidad);
  const comisionObjetivo = round2(cuposReserva * precioPorAsiento * mult * (pct / 100));

  const poolRef = db().collection("viajes_pool").doc();
  const poolId = poolRef.id;
  const billeRef = db().collection("billeteras_taxista").doc(uid);
  const userRef = db().collection("usuarios").doc(uid);
  const taxistaNombre =
    trimOrNull(request.auth.token.name) ??
    trimOrNull(udPre.nombre) ??
    "";

  const pickupPoints = stringListOrNull(d.pickupPoints);
  const incluye = stringListOrNull(d.incluye);

  const result = await db().runTransaction(async (tx) => {
    const [billeSnap, userSnap] = await Promise.all([tx.get(billeRef), tx.get(userRef)]);
    const bille = (billeSnap.data() ?? {}) as AnyMap;
    const ud = (userSnap.data() ?? {}) as AnyMap;
    const disponiblePre = saldoDisponiblePrepagoRdFromBilletera(bille);

    if (ud.tienePagoPendiente === true) {
      throw new HttpsError(
        "failed-precondition",
        "No puedes publicar salidas por cupos: hay un pago pendiente de validación. Revisa Mis pagos.",
      );
    }

    if (!recaudoCentral) {
      if (bloqueoOperativoPorComisionEfectivo(bille, minOperativoRd)) {
        const pend = comisionPendienteRdFromBilletera(bille);
        if (pend >= UMBRAL_COMISION_LEGACY_RD - 1e-6) {
          throw new HttpsError(
            "failed-precondition",
            "No puedes publicar salidas por cupos: comisión en efectivo pendiente ≥ RD$500. " +
              "Deposita y sube comprobante en Mis pagos.",
          );
        }
        const falta = round2(minOperativoRd - disponiblePre);
        throw new HttpsError(
          "failed-precondition",
          `No puedes publicar salidas por cupos: prepago libre RD$${disponiblePre.toFixed(2)}. ` +
            `Necesitas al menos RD$${minOperativoRd.toFixed(0)}. ` +
            `Recarga RD$${falta.toFixed(2)} en Mis pagos → Recarga comisión.`,
        );
      }
    }

    let comisionReservar = 0;
    const prep = saldoPrepagoRdFromBilletera(bille);
    const res = saldoReservadoGirasRdFromBilletera(bille);
    const disponible = disponiblePre;

    if (!recaudoCentral) {
      if (disponible + 1e-9 >= comisionObjetivo) {
        comisionReservar = comisionObjetivo;
      } else if (disponible + 1e-9 >= minOperativoRd) {
        comisionReservar = round2(disponible);
      } else {
        const falta = round2(minOperativoRd - disponible);
        throw new HttpsError(
          "failed-precondition",
          `Prepago libre RD$${disponible.toFixed(2)}. Para publicar salidas por cupos ` +
            `recarga al menos RD$${falta.toFixed(2)} en Mis pagos → Recarga comisión.`,
        );
      }
    }

    const ultimoTs = ud.ultimoReinicioContadorGiras;
    const now = new Date();
    let resetVentana = false;
    if (!ultimoTs || !(ultimoTs instanceof Timestamp)) {
      resetVentana = true;
    } else {
      const diffDays = Math.floor((now.getTime() - ultimoTs.toDate().getTime()) / 86_400_000);
      if (diffDays >= 30) resetVentana = true;
    }

    let creadas = Math.max(0, Math.trunc(numOr0(ud.girasCreadasUltimoMes)));
    let canceladas = Math.max(0, Math.trunc(numOr0(ud.girasCanceladasAntesDeIniciar)));
    if (resetVentana) {
      creadas = 0;
      canceladas = 0;
    } else if (!abuso.disabled && creadas >= abuso.minCreadas) {
      const ratio = canceladas / (creadas > 0 ? creadas : 1);
      if (ratio > abuso.ratioMax + 1e-9) {
        let diasRestantes: number | null = null;
        if (ultimoTs instanceof Timestamp) {
          const dias = Math.floor((now.getTime() - ultimoTs.toDate().getTime()) / 86_400_000);
          diasRestantes = Math.max(0, Math.min(30, 30 - dias));
        }
        const mensaje = mensajeGiraAbusoBloqueo(
          creadas,
          canceladas,
          abuso.ratioMax,
          diasRestantes != null && diasRestantes > 0 ? diasRestantes : null,
        );
        throw new HttpsError("failed-precondition", mensaje, {
          tipo: "gira_abuso",
          creadas,
          canceladas,
          ratioMax: abuso.ratioMax,
          diasHastaReinicio: diasRestantes != null && diasRestantes > 0 ? diasRestantes : null,
        });
      }
    }

    if (resetVentana) {
      tx.set(
        userRef,
        {
          girasCreadasUltimoMes: 1,
          girasCanceladasAntesDeIniciar: 0,
          ultimoReinicioContadorGiras: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    } else {
      tx.set(
        userRef,
        {
          girasCreadasUltimoMes: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    if (!recaudoCentral) {
      const prepNuevo = round2(prep - comisionReservar);
      const resNuevo = round2(res + comisionReservar);
      tx.set(
        billeRef,
        {
          saldoPrepagoComisionRd: prepNuevo,
          saldoReservadoParaGiras: resNuevo,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    const poolData: AnyMap = {
      tipo,
      sentido,
      origenTown,
      destino,
      fechaSalida: Timestamp.fromDate(fechaSalida),
      capacidad,
      minParaConfirmar,
      precioPorAsiento,
      pickupPoints: pickupPoints ?? [`Parque Central de ${origenTown}`],
      depositPct: depositPct > 0 ? depositPct : 0.3,
      feePct: feePct > 0 ? feePct : 0.1,
      asientosReservados: 0,
      asientosPagados: 0,
      montoReservado: 0,
      montoPagado: 0,
      estado: "abierto",
      ownerTaxistaId: uid,
      taxistaNombre,
      createdAt: FieldValue.serverTimestamp(),
      cuposComisionRai,
      comisionGiraEstimadaRd: recaudoCentral ? 0 : comisionReservar,
      comisionGiraObjetivoRd: comisionObjetivo,
      comisionGiraCuposReserva: cuposReserva,
      comisionGiraPctUsado: pct,
      prepagoComisionEtapa: recaudoCentral ? "central_recaudo" : "reservada_creacion",
    };

    if (fechaVuelta) poolData.fechaVuelta = Timestamp.fromDate(fechaVuelta);

    const optionalStrings: Array<[string, unknown]> = [
      ["agenciaNombre", d.agenciaNombre],
      ["agenciaLogoUrl", d.agenciaLogoUrl],
      ["bannerUrl", d.bannerUrl],
      ["bannerVideoUrl", d.bannerVideoUrl],
      ["puntoSalida", d.puntoSalida],
      ["destinoPlaceId", d.destinoPlaceId],
      ["choferTelefono", d.choferTelefono],
      ["choferWhatsApp", d.choferWhatsApp],
      ["bancoNombre", d.bancoNombre],
      ["bancoCuenta", d.bancoCuenta],
      ["bancoTipoCuenta", d.bancoTipoCuenta],
      ["bancoTitular", d.bancoTitular],
      ["servicioBadge", d.servicioBadge],
      ["tipoPersonalizado", d.tipoPersonalizado],
      ["descripcionViaje", d.descripcionViaje],
    ];
    for (const [key, raw] of optionalStrings) {
      const v = trimOrNull(raw);
      if (v) poolData[key] = v;
    }
    if (typeof d.puntoSalidaLat === "number" && typeof d.puntoSalidaLon === "number") {
      poolData.puntoSalidaLat = d.puntoSalidaLat;
      poolData.puntoSalidaLon = d.puntoSalidaLon;
    }
    if (typeof d.destinoLat === "number" && typeof d.destinoLon === "number") {
      poolData.destinoLat = d.destinoLat;
      poolData.destinoLon = d.destinoLon;
    }
    if (incluye) poolData.incluye = incluye;
    Object.assign(poolData, mergePoolContenidoExtraFromInput(d));
    if (recaudoCentral) {
      poolData.recaudoModelo = "central";
      poolData.montoRecaudoPct = 1;
      poolData.montoRecaudadoRaiRd = 0;
      poolData.montoComisionRaiRd = 0;
      poolData.montoNetoOrganizadorRd = 0;
    }

    tx.set(poolRef, poolData);

    if (!recaudoCentral && comisionReservar > 1e-9) {
      const led = db().collection("ledger_giras").doc();
      tx.set(led, {
        tipo: "reserva_comision",
        poolId,
        uidTaxista: uid,
        monto: comisionReservar,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return {
      poolId,
      comisionReservar,
      comisionObjetivo,
      recaudoCentral,
    };
  });

  let aviso: string | null = null;
  if (result.recaudoCentral) {
    aviso = "Recaudo central activo: los clientes pagan el total a RAI por transferencia.";
  } else if (result.comisionReservar + 1e-9 < result.comisionObjetivo) {
    const posibleFalta = round2(result.comisionObjetivo - result.comisionReservar);
    aviso =
      `Reservamos RD$${result.comisionReservar.toFixed(2)} de comisión. ` +
      `Al iniciar con el mínimo de cupos firmes pueden faltar hasta RD$${posibleFalta.toFixed(2)} ` +
      `de prepago libre; si no alcanza, te indicamos cuánto recargar.`;
  }

  logger.info("[crearPoolGira] ok", { uid, poolId: result.poolId, recaudoCentral: result.recaudoCentral });
  return { poolId: result.poolId, aviso };
});

/**
 * Actualiza contenido de una gira publicada sin borrar reservas ni pagos aprobados.
 * Dueño del pool o admin. Notifica pasajeros si cambia fecha, hora o punto de encuentro.
 */
export const actualizarPoolGiraContenido = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  const d = (request.data ?? {}) as AnyMap;
  const poolId = trimOrNull(d.poolId);
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const poolSnap = await poolRef.get();
  if (!poolSnap.exists) throw new HttpsError("not-found", "Gira no encontrada");
  const pool = (poolSnap.data() ?? {}) as AnyMap;

  const role = await getRole(uid);
  const owner = String(pool.ownerTaxistaId ?? "");
  if (role !== "admin" && owner !== uid) {
    throw new HttpsError("permission-denied", "No autorizado para editar esta gira.");
  }

  const estado = String(pool.estado ?? "").toLowerCase();
  if (estado === "finalizado" || estado === "cancelado" || estado === "cancelado_por_admin") {
    throw new HttpsError("failed-precondition", "No se puede editar una gira cerrada o cancelada.");
  }

  const patch: AnyMap = { ...mergePoolContenidoExtraFromInput(d), updatedAt: FieldValue.serverTimestamp() };

  const marketingKeys: Array<[string, unknown]> = [
    ["origenTown", d.origenTown],
    ["agenciaNombre", d.agenciaNombre],
    ["agenciaLogoUrl", d.agenciaLogoUrl],
    ["bannerUrl", d.bannerUrl],
    ["bannerVideoUrl", d.bannerVideoUrl],
    ["puntoSalida", d.puntoSalida],
    ["destino", d.destino],
    ["servicioBadge", d.servicioBadge],
    ["descripcionViaje", d.descripcionViaje],
    ["bancoNombre", d.bancoNombre],
    ["bancoCuenta", d.bancoCuenta],
    ["bancoTipoCuenta", d.bancoTipoCuenta],
    ["bancoTitular", d.bancoTitular],
  ];
  for (const [key, raw] of marketingKeys) {
    const v = trimOrNull(raw);
    if (v) patch[key] = v;
  }

  const incluye = stringListOrNull(d.incluye);
  if (incluye) patch.incluye = incluye;

  if (typeof d.precioPorAsiento === "number" && d.precioPorAsiento > 0) {
    patch.precioPorAsiento = d.precioPorAsiento;
  }
  if (typeof d.capacidad === "number" && d.capacidad > 0) {
    const occ =
      Math.max(0, Math.trunc(numOr0(pool.asientosReservados))) +
      Math.max(0, Math.trunc(numOr0(pool.asientosPagados)));
    if (d.capacidad < occ) {
      throw new HttpsError(
        "failed-precondition",
        `La capacidad no puede ser menor que los asientos ya reservados (${occ}).`,
      );
    }
    patch.capacidad = Math.trunc(d.capacidad);
  }

  const pickupPoints = stringListOrNull(d.pickupPoints);
  if (pickupPoints) patch.pickupPoints = pickupPoints;

  const prevSalida = pool.fechaSalida instanceof Timestamp ? pool.fechaSalida.toMillis() : 0;
  const prevVuelta = pool.fechaVuelta instanceof Timestamp ? pool.fechaVuelta.toMillis() : 0;
  const prevPunto = String(pool.puntoSalida ?? "");
  let scheduleChanged = false;

  const fechaSalida = d.fechaSalida != null ? parseDateInput(d.fechaSalida) : null;
  if (fechaSalida) {
    patch.fechaSalida = Timestamp.fromDate(fechaSalida);
    if (fechaSalida.getTime() !== prevSalida) scheduleChanged = true;
  }
  const fechaVueltaRaw = d.fechaVuelta;
  if (fechaVueltaRaw !== undefined) {
    if (fechaVueltaRaw == null || fechaVueltaRaw === "") {
      if (prevVuelta !== 0) scheduleChanged = true;
      patch.fechaVuelta = FieldValue.delete();
    } else {
      const fv = parseDateInput(fechaVueltaRaw);
      if (fv) {
        patch.fechaVuelta = Timestamp.fromDate(fv);
        if (fv.getTime() !== prevVuelta) scheduleChanged = true;
      }
    }
  }

  const newPunto = trimOrNull(d.puntoSalida);
  if (newPunto && newPunto !== prevPunto) scheduleChanged = true;
  if (pickupPoints) {
    const prevPick = JSON.stringify(pool.pickupPoints ?? []);
    if (JSON.stringify(pickupPoints) !== prevPick) scheduleChanged = true;
  }

  await poolRef.set(patch, { merge: true });

  if (scheduleChanged) {
    const resSnap = await poolRef.collection("reservas").get();
    const uids = resSnap.docs
      .map((doc) => {
        const r = doc.data() as AnyMap;
        if (String(r.estado ?? "").toLowerCase() === "cancelado") return "";
        return String(r.uidCliente ?? "");
      })
      .filter((u) => u.length > 0);
    const nombre = trimOrNull(pool.nombreGira) ?? trimOrNull(pool.servicioBadge) ?? "tu gira";
    await pushPoolGiraClientes(
      uids,
      "Actualización de gira",
      `Se actualizó la fecha u horario de ${nombre}. Revisa los detalles en la app.`,
      poolId,
    );
  }

  logger.info("[actualizarPoolGiraContenido] ok", { uid, poolId });
  return { ok: true, poolId };
});

/** Registro contable `reserva_comision` al crear gira (solo backend; el cliente ya no escribe en `ledger_giras`). */
export const appendLedgerGiraReserva = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "append_ledger_gira_reserva", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;
    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);
    if (!hasComisionGiraEstimadaValida(pool)) {
      throw new HttpsError("failed-precondition", MSG_LEGACY_GIRA_SIN_COMISION_ESTIMADA);
    }
    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (etapa !== "reservada_creacion") {
      throw new HttpsError(
        "failed-precondition",
        "La gira no está en etapa de reserva; no se puede registrar el asiento contable.",
      );
    }
    const reserved = round2(Math.max(0, numOr0(pool.comisionGiraEstimadaRd)));
    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "reserva_comision",
      poolId,
      uidTaxista: ownerTaxistaId,
      monto: reserved,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, monto: reserved };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  logger.info("[PRE_TEST] appendLedgerGiraReserva ok", { uidActor, poolId, result });
  return result;
});

/**
 * Devolución de reserva prepago al marcar pools por pago semanal (misma lógica que el cliente tenía en transacción).
 */
export const refundGiraReservaPagoSemanal = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "refund_gira_reserva_pago_semanal", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const ps = await tx.get(poolRef);
    if (!ps.exists) {
      return { ok: true, poolId, skipped: true, reason: "no_pool" };
    }
    const p = (ps.data() ?? {}) as AnyMap;
    if (p.canceladoPorPagoSemanal !== true) {
      return { ok: true, poolId, skipped: true, reason: "not_pago_semanal_flag" };
    }
    const reserved = Math.max(0, numOr0(p.comisionGiraEstimadaRd));
    const etapa = String(p.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (reserved <= 1e-9 || etapa !== "reservada_creacion") {
      return { ok: true, poolId, skipped: true, reason: "no_reserva_reembolsable" };
    }
    const owner = String(p.ownerTaxistaId ?? "").trim();
    if (!owner) throw new HttpsError("failed-precondition", "Pool sin dueño");
    ensurePoolOwnerOrAdmin(role, uidActor, owner);

    const billeRef = db().collection("billeteras_taxista").doc(owner);
    const bs = await tx.get(billeRef);
    const bille = (bs.data() ?? {}) as AnyMap;
    const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
    const reserv = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
    if (reserv + 1e-9 < reserved) {
      logger.error("[GIRA_PREPAGO] refund pago semanal reserv insuficiente", { poolId, reserv, reserved });
      throw new HttpsError("failed-precondition", "Saldo reservado inconsistente para devolución por pago semanal.");
    }
    tx.set(
      billeRef,
      {
        saldoPrepagoComisionRd: round2(prep + reserved),
        saldoReservadoParaGiras: round2(reserv - reserved),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.update(poolRef, {
      prepagoComisionEtapa: "devuelta_pago_semanal",
      comisionGiraEstimadaRd: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "devolucion_reserva",
      poolId,
      uidTaxista: owner,
      monto: reserved,
      motivo: "pago_semanal_cierra_pool",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, comisionDevuelta: reserved, skipped: false };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  logger.info("[PRE_TEST] refundGiraReservaPagoSemanal", { uidActor, poolId, result });
  return result;
});

type MarcarReservaPagadaTxArgs = {
  tx: Transaction;
  poolId: string;
  reservaId: string;
  uidActor: string;
  pool: AnyMap;
  poolRef: DocumentReference;
  res: AnyMap;
  resRef: DocumentReference;
  allResDocs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[];
  pctRemote: number;
  /** true = admin verificó transferencia en cuenta RAI (recaudo central). */
  aplicarSplitRecaudoCentral: boolean;
};

function marcarReservaPagadaEnTx(args: MarcarReservaPagadaTxArgs): { alreadyProcessed: boolean } {
  const {
    tx,
    poolId,
    reservaId,
    uidActor,
    pool,
    poolRef,
    res,
    resRef,
    allResDocs,
    pctRemote,
    aplicarSplitRecaudoCentral,
  } = args;

  const estadoReserva = String(res.estado ?? "");
  if (estadoReserva === "pagado") {
    return { alreadyProcessed: true };
  }
  if (estadoReserva !== "reservado") {
    throw new HttpsError("failed-precondition", `Estado de reserva no válido: ${estadoReserva}`);
  }

  const metodo = String(res.metodoPago ?? "").trim().toLowerCase();
  if (aplicarSplitRecaudoCentral) {
    if (!poolUsaRecaudoCentral(pool)) {
      throw new HttpsError("failed-precondition", "Esta salida no usa recaudo central RAI");
    }
    if (metodo !== "transferencia") {
      throw new HttpsError("failed-precondition", "Solo transferencias central se verifican en cuenta RAI");
    }
    const estadoPago = String(res.estadoPago ?? "").trim().toLowerCase();
    if (estadoPago === "verificado" || estadoPago === "rechazado") {
      throw new HttpsError(
        "failed-precondition",
        `Estado de pago no verificable: ${estadoPago || "—"}`,
      );
    }
  } else if (poolUsaRecaudoCentral(pool) && metodo === "transferencia") {
    throw new HttpsError(
      "failed-precondition",
      "Recaudo central: la transferencia la verifica RAI (admin), no el operador.",
    );
  }

  const seats = Number(res.seats ?? 0);
  if (!Number.isFinite(seats) || seats <= 0) {
    throw new HttpsError("failed-precondition", "Reserva con seats inválidos");
  }
  const total = Number(res.total ?? 0);
  const pag = Number(pool.asientosPagados ?? 0);
  const minConf = Number(pool.minParaConfirmar ?? 0);
  const estadoPool = String(pool.estado ?? "abierto");
  const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
  const firmSalida = firmSeatsAfterConfirmPayment(allResDocs, reservaId);

  const reservaPatch: AnyMap = {
    estado: "pagado",
    pagadoAt: FieldValue.serverTimestamp(),
    pagadoPor: uidActor,
    updatedAt: FieldValue.serverTimestamp(),
  };

  const poolPatch: AnyMap = {
    asientosPagados: pag + seats,
    montoPagado: Number(pool.montoPagado ?? 0) + (Number.isFinite(total) ? total : 0),
    asientosFirmesSalida: firmSalida,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if ((pag + seats) >= minConf && estadoPool !== "confirmado") {
    poolPatch.estado = "confirmado";
  }

  if (aplicarSplitRecaudoCentral) {
    const pctPool = numOr0(pool.comisionGiraPctUsado);
    const pct = pctPool > 1e-6 ? pctPool : pctRemote;
    const { comisionRaiRd, netoOrganizadorRd } = splitRecaudoReservaTotal(total, pct);
    reservaPatch.estadoPago = "verificado";
    reservaPatch.comisionRaiRd = comisionRaiRd;
    reservaPatch.netoOrganizadorRd = netoOrganizadorRd;
    reservaPatch.verificadoAt = FieldValue.serverTimestamp();
    reservaPatch.verificadoPor = uidActor;
    poolPatch.montoRecaudadoRaiRd = numOr0(pool.montoRecaudadoRaiRd) + total;
    poolPatch.montoComisionRaiRd = numOr0(pool.montoComisionRaiRd) + comisionRaiRd;
    poolPatch.montoNetoOrganizadorRd = numOr0(pool.montoNetoOrganizadorRd) + netoOrganizadorRd;

    const ledRef = db().collection("ledger_pool_reservas").doc(`${reservaId}_recaudo_verificado`);
    tx.set(
      ledRef,
      {
        tipo: "recaudo_verificado",
        poolId,
        reservaId,
        ownerTaxistaId,
        brutoRd: total,
        comisionPct: pct,
        comisionRaiRd,
        netoOrganizadorRd,
        referenciaRecaudo: String(res.referenciaRecaudo ?? ""),
        verificadoPor: uidActor,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  asignarTokenEntradaSiFaltaEnTx(tx, poolId, reservaId, res, reservaPatch);

  tx.update(resRef, reservaPatch);
  tx.update(poolRef, poolPatch);
  return { alreadyProcessed: false };
}

/** Verifica pago central en transacción (admin manual o conciliación banco). */
export async function ejecutarVerificacionPoolRecaudoEnTransaction(
  tx: Transaction,
  poolId: string,
  reservaId: string,
  uidActor: string,
  pctRemote: number,
): Promise<{ alreadyProcessed: boolean }> {
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);
  const poolSnap = await tx.get(poolRef);
  if (!poolSnap.exists) throw new HttpsError("not-found", "Pool no existe");
  const pool = (poolSnap.data() ?? {}) as AnyMap;
  const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));
  const resSnap = await tx.get(resRef);
  if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
  const res = (resSnap.data() ?? {}) as AnyMap;

  return marcarReservaPagadaEnTx({
    tx,
    poolId,
    reservaId,
    uidActor,
    pool,
    poolRef,
    res,
    resRef,
    allResDocs: allResSnap.docs,
    pctRemote,
    aplicarSplitRecaudoCentral: true,
  });
}

export function precioCentsPoolReserva(data: AnyMap): number {
  const total = numOr0(data.total);
  if (total <= 0) return 0;
  return Math.round(total * 100);
}

/** Admin: verifica transferencia del cliente en cuenta RAI y confirma cupos (recaudo central). */
export const verifyPoolReservaRecaudo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin puede verificar pagos pool en cuenta RAI");
  }

  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const reservaId = typeof request.data?.reservaId === "string" ? request.data.reservaId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!reservaId) throw new HttpsError("invalid-argument", "Falta reservaId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "verify_pool_reserva_recaudo", uidActor);
  if (idem.done) return idem.result;

  const pctRemote = await getComisionGiraPorcientoFromRemote();

  const result = await db().runTransaction(async (tx) => {
    const out = await ejecutarVerificacionPoolRecaudoEnTransaction(
      tx,
      poolId,
      reservaId,
      uidActor,
      pctRemote,
    );
    return { ok: true, poolId, reservaId, ...out };
  });

  logAdminAudit({
    action: "verify_pool_reserva_recaudo",
    actorUid: uidActor,
    resourceType: "pool_reserva",
    resourceId: reservaId,
    metadata: { poolId, result: result as AnyMap },
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const confirmPoolReservationPayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const reservaId = typeof request.data?.reservaId === "string" ? request.data.reservaId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!reservaId) throw new HttpsError("invalid-argument", "Falta reservaId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "confirm_pool_reservation_payment", uidActor);
  if (idem.done) return idem.result;

  const pctRemote = await getComisionGiraPorcientoFromRemote();
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  const result = await db().runTransaction(async (tx) => {
    const poolSnap = await tx.get(poolRef);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (poolSnap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));
    const resSnap = await tx.get(resRef);
    if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
    const res = (resSnap.data() ?? {}) as AnyMap;

    const out = marcarReservaPagadaEnTx({
      tx,
      poolId,
      reservaId,
      uidActor,
      pool,
      poolRef,
      res,
      resRef,
      allResDocs: allResSnap.docs,
      pctRemote,
      aplicarSplitRecaudoCentral: false,
    });

    return { ok: true, poolId, reservaId, ...out };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const startPoolTrip = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "start_pool_trip", uidActor);
  if (idem.done) return idem.result;

  logger.info("[PRE_TEST] startPoolTrip llamada", { uidActor, poolId });

  const pctRemote = await getComisionGiraPorcientoFromRemote();
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    if (ownerTaxistaId) {
      const ownerRef = db().collection("usuarios").doc(ownerTaxistaId);
      const ownerSnap = await tx.get(ownerRef);
      const ownerData = (ownerSnap.data() ?? {}) as AnyMap;
      if (ownerData.tienePagoPendiente === true) {
        throw new HttpsError("failed-precondition", "Taxista con pago pendiente no puede iniciar pool");
      }
    }

    const estado = String(pool.estado ?? "abierto");
    const reservados = Number(pool.asientosReservados ?? 0);
    const minConf = Number(pool.minParaConfirmar ?? 0);

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));
    const firmSalida = firmSeatsFromReservaDocs(allResSnap.docs);

    if (estado === "en_ruta") return { ok: true, poolId, alreadyStarted: true };
    if (estado === "cancelado" || estado === "finalizado") {
      throw new HttpsError("failed-precondition", `No se puede iniciar desde estado ${estado}`);
    }
    if (!Number.isFinite(reservados) || reservados <= 0) {
      throw new HttpsError("failed-precondition", "No hay reservas activas en el anuncio");
    }
    if (!Number.isFinite(firmSalida) || firmSalida <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "No hay cupos firmes para salir: se requiere pago verificado (transferencia) o reserva en efectivo.",
      );
    }
    if (Number.isFinite(minConf) && minConf > 0 && firmSalida < minConf) {
      throw new HttpsError(
        "failed-precondition",
        "No alcanza el mínimo de cupos firmes (pagados o efectivo) para iniciar el viaje.",
      );
    }

    if (poolUsaRecaudoCentral(pool)) {
      const etapaCentral = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
      if (etapaCentral !== "central_recaudo" && etapaCentral !== "central_en_ruta") {
        throw new HttpsError(
          "failed-precondition",
          "Estado de recaudo central inconsistente; contactá soporte.",
        );
      }
      if (!ownerTaxistaId) {
        throw new HttpsError("failed-precondition", "Pool sin dueño registrado");
      }

      const asientosEfectivo = firmEfectivoSeatsFromReservaDocs(allResSnap.docs);
      const pctPool = numOr0(pool.comisionGiraPctUsado);
      const pct = pctPool > 1e-6 ? pctPool : pctRemote;
      const comisionEfectivoRd = comisionRaiRdFromReservaDocs(
        allResSnap.docs,
        reservaEsEfectivoFirm,
        pct,
      );

      const poolUpdate: AnyMap = {
        estado: "en_ruta",
        asientosFirmesSalida: firmSalida,
        asientosEfectivoComision: asientosEfectivo,
        prepagoComisionEtapa: "central_en_ruta",
        iniciadoAt: FieldValue.serverTimestamp(),
        comisionEstado:
          asientosEfectivo > 0 && comisionEfectivoRd > 1e-6
            ? "recaudo_central_y_prepago_efectivo"
            : "por_reserva_recaudo",
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (comisionEfectivoRd > 1e-6) {
        const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
        const billeSnap = await tx.get(billeRef);
        const bille = (billeSnap.data() ?? {}) as AnyMap;
        const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
        if (prep + 1e-9 < comisionEfectivoRd) {
          const falta = round2(comisionEfectivoRd - prep);
          throw new HttpsError(
            "failed-precondition",
            `Para iniciar con ${asientosEfectivo} cupo(s) en efectivo faltan RD$${falta.toFixed(2)} de prepago. ` +
              "Recarga en Mis pagos → Recarga comisión (comisión RAI sobre cupos en efectivo al abordar).",
          );
        }
        const descAcum = Math.max(0, numOr0(bille.comisionesDescontadas));
        tx.set(
          billeRef,
          {
            saldoPrepagoComisionRd: round2(prep - comisionEfectivoRd),
            comisionesDescontadas: round2(descAcum + comisionEfectivoRd),
            ultimaComisionGiraPoolId: poolId,
            ultimaComisionGiraRd: comisionEfectivoRd,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const led = db().collection("ledger_giras").doc();
        tx.set(led, {
          tipo: "comision_efectivo_central_inicio",
          poolId,
          uidTaxista: ownerTaxistaId,
          monto: comisionEfectivoRd,
          asientosEfectivo,
          pctUsado: pct,
          createdAt: FieldValue.serverTimestamp(),
        });
        poolUpdate.comisionEfectivoPrepagoRd = comisionEfectivoRd;
      }

      tx.update(poolRef, poolUpdate);
      logger.info("[POOL_RECAUDO] startPoolTrip central", {
        poolId,
        firmSalida,
        asientosEfectivo,
        comisionEfectivoRd,
      });
      return {
        ok: true,
        poolId,
        alreadyStarted: false,
        recaudoCentral: true,
        asientosFirmes: firmSalida,
        asientosEfectivo,
        comisionEfectivoRd,
      };
    }

    if (!hasComisionGiraEstimadaValida(pool)) {
      logger.warn("[PRE_TEST] startPoolTrip bloqueado sin comisionGiraEstimadaRd válida", {
        poolId,
        uidActor,
      });
      throw new HttpsError("failed-precondition", MSG_LEGACY_GIRA_SIN_COMISION_ESTIMADA);
    }
    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (etapa !== "reservada_creacion") {
      logger.warn("[PRE_TEST] startPoolTrip etapa inconsistente", { poolId, uidActor, etapa });
      throw new HttpsError(
        "failed-precondition",
        "Estado de reserva de comisión inconsistente; contactá soporte.",
      );
    }
    if (!ownerTaxistaId) {
      throw new HttpsError("failed-precondition", "Pool sin dueño registrado");
    }

    const cap = Number(pool.capacidad ?? 0);
    // Comisión solo sobre cupos firmes en RAI al iniciar (pagado + efectivo reservado en app).
    // cuposComisionRai limita el prepago apartado al publicar, no las ventas reales en app.
    let asientosReales = firmSalida;
    if (Number.isFinite(cap) && cap > 0) {
      asientosReales = Math.min(asientosReales, Math.trunc(cap));
    }

    const reserved = round2(Math.max(0, numOr0(pool.comisionGiraEstimadaRd)));
    const pctPool = numOr0(pool.comisionGiraPctUsado);
    const pct = pctPool > 1e-6 ? pctPool : pctRemote;
    const comisionReal = comisionRaiRdFromReservaDocs(
      allResSnap.docs,
      reservaEsFirmeParaComision,
      pct,
    );

    const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
    const billeSnap = await tx.get(billeRef);
    const bille = (billeSnap.data() ?? {}) as AnyMap;
    let prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
    const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));

    let reservedEfectiva = reserved;
    const faltanteInicio = round2(comisionReal - reserved);
    if (faltanteInicio > 1e-6) {
      if (prep + 1e-9 < faltanteInicio) {
        const recargarMin = round2(faltanteInicio - prep);
        throw new HttpsError(
          "failed-precondition",
          `Para iniciar esta gira faltan RD$${faltanteInicio.toFixed(2)} de prepago libre. ` +
            `Tienes RD$${prep.toFixed(2)} disponible. Recarga al menos RD$${recargarMin.toFixed(2)} ` +
            `en Mis pagos → Recarga comisión.`,
        );
      }
      prep = round2(prep - faltanteInicio);
      reservedEfectiva = comisionReal;
      tx.update(poolRef, {
        comisionGiraEstimadaRd: comisionReal,
        prepagoComisionTopUpInicioRd: faltanteInicio,
        updatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("[GIRA_PREPAGO] start top-up prepago libre", {
        poolId,
        faltanteInicio,
        comisionReal,
        reserved,
      });
    }

    const excess = round2(reservedEfectiva - comisionReal);
    logger.info("[PRE_TEST] startPoolTrip saldos antes", {
      uidActor,
      poolId,
      prepAntes: prep,
      reservWalletAntes: reservWallet,
      reserved,
      comisionReal,
    });
    if (reservWallet + 1e-9 < reserved) {
      logger.error("[GIRA_PREPAGO] start saldoReservado insuficiente", { poolId, reservWallet, reserved });
      throw new HttpsError(
        "failed-precondition",
        "Saldo reservado insuficiente para confirmar la comisión de esta gira.",
      );
    }
    const descAcum = Math.max(0, numOr0(bille.comisionesDescontadas));
    const prepNuevo = round2(prep + excess);
    const reservNuevo = round2(reservWallet - reserved);
    const descNuevo = round2(descAcum + comisionReal);
    tx.set(
      billeRef,
      {
        saldoPrepagoComisionRd: prepNuevo,
        saldoReservadoParaGiras: reservNuevo,
        comisionesDescontadas: descNuevo,
        ultimaComisionGiraPoolId: poolId,
        ultimaComisionGiraRd: comisionReal,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "confirmacion_comision_inicio",
      poolId,
      uidTaxista: ownerTaxistaId,
      monto: comisionReal,
      montoDevueltoExceso: excess,
      asientosReales,
      pctUsado: pct,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.update(poolRef, {
      estado: "en_ruta",
      asientosFirmesSalida: firmSalida,
      asientosRealesComision: asientosReales,
      comisionGiraRealRd: comisionReal,
      comisionGiraExcesoDevueltoRd: excess,
      prepagoComisionEtapa: "confirmada_inicio",
      iniciadoAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("[GIRA_PREPAGO] startPoolTrip prepago confirmado", {
      poolId,
      comisionReal,
      excess,
      asientosReales,
    });
    logger.info("[PRE_TEST] startPoolTrip saldos después", {
      uidActor,
      poolId,
      prepDespues: prepNuevo,
      reservWalletDespues: reservNuevo,
    });
    return {
      ok: true,
      poolId,
      alreadyStarted: false,
      comisionReal,
      comisionDevuelta: excess,
      asientosReales,
    };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const finalizePoolTrip = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "finalize_pool_trip", uidActor);
  if (idem.done) return idem.result;

  logger.info("[PRE_TEST] finalizePoolTrip llamada", { uidActor, poolId });

  const pctRemote = await getComisionGiraPorcientoFromRemote();
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const abuseCfgFinalize = await fetchGiraAbusoUmbral();
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const estado = String(pool.estado ?? "abierto");
    if (estado === "finalizado") return { ok: true, poolId, alreadyFinalized: true };

    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));

    // Caso borde: finalizar sin haber iniciado → misma lógica que cancelación de reserva.
    if (estado !== "en_ruta") {
      if (reserved > 1e-9 && etapa === "reservada_creacion" && ownerTaxistaId) {
        const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
        const billeSnap = await tx.get(billeRef);
        const bille = (billeSnap.data() ?? {}) as AnyMap;
        const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
        const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
        if (reservWallet + 1e-9 < reserved) {
          throw new HttpsError("failed-precondition", "No se puede devolver reserva: saldo inconsistente");
        }
        tx.set(
          billeRef,
          {
            saldoPrepagoComisionRd: Number((prep + reserved).toFixed(2)),
            saldoReservadoParaGiras: Number((reservWallet - reserved).toFixed(2)),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const uref = db().collection("usuarios").doc(ownerTaxistaId);
        const us = await tx.get(uref);
        const ud = (us.data() ?? {}) as AnyMap;
        const canceladas = Math.max(0, Math.trunc(numOr0(ud.girasCanceladasAntesDeIniciar))) + 1;
        const creadasFin = Math.max(0, Math.trunc(numOr0(ud.girasCreadasUltimoMes)));
        const userCancelPatchFin: AnyMap = {
          girasCanceladasAntesDeIniciar: canceladas,
          updatedAt: FieldValue.serverTimestamp(),
        };
        mergeGiraAbusoBloqueadoSiAplica(userCancelPatchFin, creadasFin, canceladas, abuseCfgFinalize);
        tx.set(uref, userCancelPatchFin, { merge: true });
        tx.update(poolRef, {
          estado: "cancelado",
          prepagoComisionEtapa: "devuelta_finalize_sin_inicio",
          comisionGiraEstimadaRd: 0,
          motivoCancelacion: "Finalización sin inicio: devolución automática de reserva",
          canceladoAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        const led = db().collection("ledger_giras").doc();
        tx.set(led, {
          tipo: "devolucion_reserva",
          poolId,
          uidTaxista: ownerTaxistaId,
          monto: reserved,
          motivo: "finalize_sin_inicio",
          createdAt: FieldValue.serverTimestamp(),
        });
        logger.info("[GIRA_PREPAGO] finalizePoolTrip tratado como cancel refund", { poolId, reserved });
        return { ok: true, poolId, refundedAsCancel: true, comisionDevuelta: reserved };
      }
      throw new HttpsError("failed-precondition", "Solo puedes finalizar un viaje en ruta");
    }

    const montoPagado = Number(pool.montoPagado ?? 0);
    const montoReservado = Number(pool.montoReservado ?? 0);
    const totalGira =
      Number.isFinite(montoPagado) && montoPagado > 0.009
        ? Math.max(0, montoPagado)
        : Number.isFinite(montoReservado)
          ? Math.max(0, montoReservado)
          : 0;

    if (etapa === "confirmada_inicio") {
      const comisionYa = Math.max(0, numOr0(pool.comisionGiraRealRd));
      const pctPool = numOr0(pool.comisionGiraPctUsado);
      const pct = pctPool > 1e-6 ? pctPool : pctRemote;
      tx.update(poolRef, {
        estado: "finalizado",
        finalizadoAt: FieldValue.serverTimestamp(),
        totalGira,
        comisionPctAplicada: pct / 100,
        montoComision: 0,
        montoComisionTotal: comisionYa,
        montoComisionCobradaPrepago: comisionYa,
        montoComisionPendienteAdmin: 0,
        montoNetoTaxista: Math.max(0, totalGira - comisionYa),
        liquidado: true,
        comisionPendientePagoAdmin: false,
        comisionEstado: "descontada_prepago_inicio",
        comisionMetodoPago: "prepago",
        updatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("[GIRA_PREPAGO] finalizePoolTrip sin nuevo descuento (prepago en inicio)", { poolId });
      return { ok: true, poolId, alreadyFinalized: false, prepagoEnInicio: true, comisionYaDescontada: comisionYa };
    }

    if (poolUsaRecaudoCentral(pool)) {
      const netoPend = Math.max(0, numOr0(pool.montoNetoOrganizadorRd));
      const poolUpdate: AnyMap = {
        estado: "finalizado",
        finalizadoAt: FieldValue.serverTimestamp(),
        totalGira,
        liquidacionOrganizadorEstado: netoPend > 1e-6 ? "pendiente_pago" : "sin_saldo",
        liquidacionOrganizadorAt: FieldValue.serverTimestamp(),
        comisionEstado: "por_reserva_recaudo",
        montoNetoTaxista: netoPend,
        liquidado: netoPend <= 1e-6,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (netoPend > 1e-6) {
        const liqRef = db().collection("liquidaciones_pool").doc();
        tx.set(liqRef, {
          poolId,
          ownerTaxistaId,
          netoTotalRd: netoPend,
          montoRecaudadoRaiRd: numOr0(pool.montoRecaudadoRaiRd),
          montoComisionRaiRd: numOr0(pool.montoComisionRaiRd),
          bancoNombre: String(pool.bancoNombre ?? ""),
          bancoCuenta: String(pool.bancoCuenta ?? ""),
          bancoTipoCuenta: String(pool.bancoTipoCuenta ?? ""),
          bancoTitular: String(pool.bancoTitular ?? ""),
          agenciaNombre: String(pool.agenciaNombre ?? pool.taxistaNombre ?? ""),
          destino: String(pool.destino ?? ""),
          estado: "pendiente_pago",
          metodoSalida: "manual_admin",
          createdAt: FieldValue.serverTimestamp(),
        });
        poolUpdate.liquidacionPoolId = liqRef.id;
      }
      tx.update(poolRef, poolUpdate);
      logger.info("[POOL_RECAUDO] finalizePoolTrip central", { poolId, netoPend });
      return { ok: true, poolId, alreadyFinalized: false, recaudoCentral: true, netoOrganizadorPendiente: netoPend };
    }

    const comisionPctAplicada = pctRemote / 100;
    const montoComision = Math.max(0, totalGira * comisionPctAplicada);
    const montoNetoTaxista = Math.max(0, totalGira - montoComision);

    let montoComisionCobradaPrepago = 0;
    let montoComisionPendienteAdmin = montoComision;
    if (ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const saldoAntes = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      montoComisionCobradaPrepago = Math.min(saldoAntes, montoComision);
      montoComisionPendienteAdmin = Math.max(0, montoComision - montoComisionCobradaPrepago);
      const saldoDespues = Number((saldoAntes - montoComisionCobradaPrepago).toFixed(2));
      tx.set(
        billeRef,
        {
          saldoPrepagoComisionRd: saldoDespues,
          ultimaComisionPoolId: poolId,
          ultimaComisionPoolRd: Number(montoComision.toFixed(2)),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    tx.update(poolRef, {
      estado: "finalizado",
      finalizadoAt: FieldValue.serverTimestamp(),
      totalGira,
      comisionPctAplicada,
      montoComision: Number(montoComisionPendienteAdmin.toFixed(2)),
      montoComisionTotal: Number(montoComision.toFixed(2)),
      montoComisionCobradaPrepago: Number(montoComisionCobradaPrepago.toFixed(2)),
      montoComisionPendienteAdmin: Number(montoComisionPendienteAdmin.toFixed(2)),
      montoNetoTaxista,
      liquidado: true,
      comisionPendientePagoAdmin: montoComisionPendienteAdmin > 1e-6,
      comisionEstado:
        montoComisionPendienteAdmin > 1e-6
          ? "pendiente_transferencia_admin"
          : "descontada_prepago",
      comisionMetodoPago:
        montoComisionPendienteAdmin > 1e-6
          ? "transferencia"
          : "prepago",
      updatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("[GIRA_PREPAGO] finalizePoolTrip legacy descuento al finalizar", { poolId });
    return { ok: true, poolId, alreadyFinalized: false, legacy: true };
  });

  await markIdempotencyDone(idem.ref, result);
  logger.info("[PRE_TEST] finalizePoolTrip resultado", { uidActor, poolId, result });
  return result;
});

/** Admin: marca neto de gira central transferido al organizador. */
export const approveLiquidacionPool = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }

  const liquidacionId =
    typeof request.data?.liquidacionId === "string" ? request.data.liquidacionId.trim() : "";
  const referenciaBanco =
    typeof request.data?.referenciaBanco === "string" ? request.data.referenciaBanco.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!liquidacionId) throw new HttpsError("invalid-argument", "Falta liquidacionId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "approve_liquidacion_pool", uidActor);
  if (idem.done) return idem.result;

  const liqRef = db().collection("liquidaciones_pool").doc(liquidacionId);
  const result = await db().runTransaction(async (tx) => {
    const liqSnap = await tx.get(liqRef);
    if (!liqSnap.exists) throw new HttpsError("not-found", "Liquidación no encontrada");
    const liq = (liqSnap.data() ?? {}) as AnyMap;
    const estado = String(liq.estado ?? "").trim().toLowerCase();
    if (estado === "liquidado" || estado === "pagado") {
      return { ok: true, liquidacionId, alreadyProcessed: true };
    }
    if (estado !== "pendiente_pago") {
      throw new HttpsError("failed-precondition", `Estado de liquidación: ${estado || "—"}`);
    }

    const poolId = String(liq.poolId ?? "").trim();
    const neto = numOr0(liq.netoTotalRd);
    tx.update(liqRef, {
      estado: "liquidado",
      pagadoAt: FieldValue.serverTimestamp(),
      pagadoPor: uidActor,
      ...(referenciaBanco ? { referenciaBanco } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (poolId) {
      const poolRef = db().collection("viajes_pool").doc(poolId);
      tx.set(
        poolRef,
        {
          liquidacionOrganizadorEstado: "liquidado",
          liquidacionOrganizadorAt: FieldValue.serverTimestamp(),
          liquidacionOrganizadorPagadoPor: uidActor,
          liquidado: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    return { ok: true, liquidacionId, poolId, netoTotalRd: neto, alreadyProcessed: false };
  });

  logAdminAudit({
    action: "approve_liquidacion_pool",
    actorUid: uidActor,
    resourceType: "liquidacion_pool",
    resourceId: liquidacionId,
    metadata: { referenciaBanco, result: result as AnyMap },
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const cancelPoolTrip = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const motivo = typeof request.data?.motivo === "string" ? request.data.motivo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "cancel_pool_trip", uidActor);
  if (idem.done) return idem.result;

  logger.info("[PRE_TEST] cancelPoolTrip llamada", {
    uidActor,
    poolId,
    motivoLen: motivo.length,
  });

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const abuseCfg = await fetchGiraAbusoUmbral();
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const estado = String(pool.estado ?? "abierto").trim().toLowerCase();
    if (estado === "cancelado" || estado === "cancelado_por_admin") {
      return { ok: true, poolId, alreadyCanceled: true, comisionDevuelta: 0 };
    }
    if (estado === "finalizado") {
      throw new HttpsError("failed-precondition", "No se puede cancelar un viaje finalizado");
    }
    if (estado === "en_ruta") {
      throw new HttpsError("failed-precondition", "No se puede cancelar una gira ya iniciada");
    }

    const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));
    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    const reservasSnap = await tx.get(poolRef.collection("reservas"));
    const reservasCanceladas = marcarReservasCanceladasPorGiraTx(tx, reservasSnap.docs, motivo);

    if (reserved > 1e-9 && etapa === "reservada_creacion" && ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const uref = db().collection("usuarios").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const us = await tx.get(uref);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const ud = (us.data() ?? {}) as AnyMap;
      const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
      const canceladas = Math.max(0, Math.trunc(numOr0(ud.girasCanceladasAntesDeIniciar))) + 1;
      const creadas = Math.max(0, Math.trunc(numOr0(ud.girasCreadasUltimoMes)));
      const userCancelPatch: AnyMap = {
        girasCanceladasAntesDeIniciar: canceladas,
        updatedAt: FieldValue.serverTimestamp(),
      };
      mergeGiraAbusoBloqueadoSiAplica(userCancelPatch, creadas, canceladas, abuseCfg);
      logger.info("[PRE_TEST] cancelPoolTrip saldos antes devolución", {
        uidActor,
        poolId,
        prepAntes: prep,
        reservWalletAntes: reservWallet,
        reserved,
      });
      if (reservWallet + 1e-9 < reserved) {
        logger.error("[GIRA_PREPAGO] cancel saldo reservado insuficiente", { poolId, reservWallet, reserved });
        throw new HttpsError("failed-precondition", "Saldo reservado inconsistente; contactá soporte.");
      }
      tx.set(
        billeRef,
        {
          saldoPrepagoComisionRd: Number((prep + reserved).toFixed(2)),
          saldoReservadoParaGiras: Number((reservWallet - reserved).toFixed(2)),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.set(uref, userCancelPatch, { merge: true });

      const led = db().collection("ledger_giras").doc();
      tx.set(led, {
        tipo: "devolucion_reserva",
        poolId,
        uidTaxista: ownerTaxistaId,
        monto: reserved,
        motivo: motivo || "cancelacion",
        createdAt: FieldValue.serverTimestamp(),
      });

      tx.update(poolRef, {
        ...patchPoolCanceladoGira(motivo),
        prepagoComisionEtapa: "devuelta_cancelacion",
        comisionGiraEstimadaRd: 0,
      });
      logger.info("[GIRA_PREPAGO] cancelPoolTrip devolución reserva", {
        poolId,
        reserved,
        reservasCanceladas,
      });
      const prepDespues = Number((prep + reserved).toFixed(2));
      const reservDespues = Number((reservWallet - reserved).toFixed(2));
      logger.info("[PRE_TEST] cancelPoolTrip saldos después devolución", {
        uidActor,
        poolId,
        prepDespues,
        reservWalletDespues: reservDespues,
        reservasCanceladas,
      });
      return {
        ok: true,
        poolId,
        alreadyCanceled: false,
        comisionDevuelta: reserved,
        reservasCanceladas,
      };
    }

    if (ownerTaxistaId) {
      const uref = db().collection("usuarios").doc(ownerTaxistaId);
      const us = await tx.get(uref);
      const ud = (us.data() ?? {}) as AnyMap;
      const canceladas = Math.max(0, Math.trunc(numOr0(ud.girasCanceladasAntesDeIniciar))) + 1;
      const creadas = Math.max(0, Math.trunc(numOr0(ud.girasCreadasUltimoMes)));
      const userCancelPatch: AnyMap = {
        girasCanceladasAntesDeIniciar: canceladas,
        updatedAt: FieldValue.serverTimestamp(),
      };
      mergeGiraAbusoBloqueadoSiAplica(userCancelPatch, creadas, canceladas, abuseCfg);
      tx.set(uref, userCancelPatch, { merge: true });
    }

    tx.update(poolRef, patchPoolCanceladoGira(motivo));
    logger.info("[GIRA_PREPAGO] cancelPoolTrip sin reserva prepago", { poolId, reservasCanceladas });
    return { ok: true, poolId, alreadyCanceled: false, comisionDevuelta: 0, reservasCanceladas };
  });

  await markIdempotencyDone(idem.ref, result);
  logger.info("[PRE_TEST] cancelPoolTrip resultado", { uidActor, poolId, result });
  return result;
});

/**
 * Solo administración: anula una gira/excursión ya finalizada (corrección operativa,
 * disputa, error de cierre). Quita la comisión pendiente de validación en panel admin.
 */
export const adminVoidFinalizedPool = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const motivo = typeof request.data?.motivo === "string" ? request.data.motivo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const roleRaw = await getRole(uidActor);
  const roleNorm = String(roleRaw ?? "").trim().toLowerCase();
  if (roleNorm !== "admin") {
    throw new HttpsError("permission-denied", "Solo administradores pueden anular giras finalizadas");
  }

  const idem = await ensureIdempotencyStart(idemKey, "admin_void_finalized_pool", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const estado = String(pool.estado ?? "abierto");
    const yaAnulada = pool.anuladaTrasFinalizar === true;
    if (estado === "cancelado" && yaAnulada) {
      return { ok: true, poolId, alreadyVoided: true };
    }
    if (estado === "cancelado" && !yaAnulada) {
      throw new HttpsError(
        "failed-precondition",
        "Esta gira está cancelada por flujo normal; no requiere anulación post-finalizado",
      );
    }
    if (estado !== "finalizado") {
      throw new HttpsError(
        "failed-precondition",
        "Solo se puede usar tras finalizar la gira (estado actual: " + estado + ")",
      );
    }

    tx.update(poolRef, {
      estado: "cancelado",
      anuladaTrasFinalizar: true,
      anuladaTrasFinalizarAt: FieldValue.serverTimestamp(),
      anuladaTrasFinalizarPor: uidActor,
      motivoAnulacionAdmin: motivo || "Anulación administrativa tras cierre",
      comisionPendientePagoAdmin: false,
      comisionEstado: "anulada_admin",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, alreadyVoided: false };
  });

  await markIdempotencyDone(idem.ref, result);
  logAdminAudit({
    action: "admin_void_finalized_pool",
    actorUid: uidActor,
    resourceType: "viajes_pool",
    resourceId: poolId,
    metadata: {
      motivoLen: motivo.length,
      result: result as AnyMap,
    },
  });
  return result;
});

/**
 * Borra el documento del pool y sus reservas (solo si no hay compromisos activos).
 * Evita “basura” en Firestore cuando el operador cancela un anuncio sin cupos vendidos.
 */
export const deletePoolForOwner = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "delete_pool_for_owner", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const poolSnap = await poolRef.get();
  if (!poolSnap.exists) {
    const r = { ok: true, poolId, alreadyDeleted: true };
    await markIdempotencyDone(idem.ref, r);
    return r;
  }

  const pool = (poolSnap.data() ?? {}) as AnyMap;
  const ownerTaxistaId = String(pool.ownerTaxistaId ?? "").trim();
  ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

  const estado = String(pool.estado ?? "").trim().toLowerCase();
  if (estado === "en_ruta" || estado === "finalizado") {
    throw new HttpsError(
      "failed-precondition",
      "No se puede borrar un viaje en curso o ya finalizado",
    );
  }

  const occ = Number(pool.asientosReservados ?? 0);
  const pag = Number(pool.asientosPagados ?? 0);
  const montoPag = Number(pool.montoPagado ?? 0);
  const montoRes = Number(pool.montoReservado ?? 0);
  if (!Number.isFinite(occ) || !Number.isFinite(pag)) {
    throw new HttpsError("failed-precondition", "Datos del pool inconsistentes");
  }
  if (occ > 0 || pag > 0 || montoPag > 0.009 || montoRes > 0.009) {
    throw new HttpsError(
      "failed-precondition",
      "No se puede borrar: hay reservas o montos registrados. Cancelá reservas o usá “Limpiar vencidas”.",
    );
  }

  const resSnap = await poolRef.collection("reservas").get();
  for (const doc of resSnap.docs) {
    const e = String(doc.data()?.estado ?? "").trim().toLowerCase();
    if (e === "pagado" || e === "reservado") {
      throw new HttpsError(
        "failed-precondition",
        "Hay reservas activas en este anuncio; no se puede borrar todavía.",
      );
    }
  }

  if (resSnap.size > 400) {
    throw new HttpsError("resource-exhausted", "Demasiadas reservas; contactá soporte.");
  }

  const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));
  const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();

  await db().runTransaction(async (tx) => {
    const pSnap = await tx.get(poolRef);
    if (!pSnap.exists) return;
    const p = (pSnap.data() ?? {}) as AnyMap;
    const res2 = Math.max(0, numOr0(p.comisionGiraEstimadaRd));
    const et2 = String(p.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (res2 > 1e-9 && et2 === "reservada_creacion" && ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
      if (reservWallet + 1e-9 >= res2) {
        tx.set(
          billeRef,
          {
            saldoPrepagoComisionRd: Number((prep + res2).toFixed(2)),
            saldoReservadoParaGiras: Number((reservWallet - res2).toFixed(2)),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const led = db().collection("ledger_giras").doc();
        tx.set(led, {
          tipo: "devolucion_reserva",
          poolId,
          uidTaxista: ownerTaxistaId,
          monto: res2,
          motivo: "delete_pool_owner",
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
    for (const doc of resSnap.docs) {
      tx.delete(doc.ref);
    }
    tx.delete(poolRef);
  });

  const result = { ok: true, poolId, deletedReservas: resSnap.size, comisionDevuelta: reserved };
  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const reservePoolSeats = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidCliente = request.auth.uid;

  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const metodoPago = typeof request.data?.metodoPago === "string"
    ? request.data.metodoPago.trim().toLowerCase()
    : "";
  const seatsRaw = Number(request.data?.seats ?? 0);
  const seats = Number.isFinite(seatsRaw) ? Math.trunc(seatsRaw) : 0;
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";

  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");
  if (seats <= 0) throw new HttpsError("invalid-argument", "Asientos inválidos");
  if (metodoPago !== "transferencia" && metodoPago !== "efectivo") {
    throw new HttpsError("invalid-argument", "Método de pago inválido");
  }

  const idem = await ensureIdempotencyStart(idemKey, "reserve_pool_seats", uidCliente);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const poolSnap = await tx.get(poolRef);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (poolSnap.data() ?? {}) as AnyMap;

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));

    const estado = String(pool.estado ?? "").trim().toLowerCase();
    const permitido = ["abierto", "preconfirmado", "confirmado", "activo", "disponible", "buscando"];
    if (!permitido.includes(estado)) {
      throw new HttpsError("failed-precondition", "Este viaje no admite nuevas reservas");
    }

    // Refuerzo por pagos semanales:
    // Si el dueño del pool (taxista) tiene una comisión semanal pendiente,
    // rechazamos la reserva aunque el pool esté en estado "abierto".
    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "").trim();
    if (ownerTaxistaId) {
      const ownerRef = db().collection("usuarios").doc(ownerTaxistaId);
      const ownerSnap = await tx.get(ownerRef);
      const ownerData = (ownerSnap.data() ?? {}) as AnyMap;
      const tienePagoPendiente = ownerData.tienePagoPendiente === true;
      if (tienePagoPendiente) {
        throw new HttpsError(
          "failed-precondition",
          "El taxista del viaje tiene pago semanal pendiente. No se puede reservar hasta que se verifique el pago."
        );
      }
    }

    const cap = Number(pool.capacidad ?? 0);
    const occ = Number(pool.asientosReservados ?? 0);
    if (!Number.isFinite(cap) || cap <= 0) {
      throw new HttpsError("failed-precondition", "Capacidad inválida del viaje");
    }
    if (!Number.isFinite(occ) || occ < 0) {
      throw new HttpsError("failed-precondition", "Ocupación inválida del viaje");
    }
    if (occ + seats > cap) throw new HttpsError("failed-precondition", "No hay suficientes cupos");

    const precio = Number(pool.precioPorAsiento ?? 0);
    const depositPctRaw = Number(pool.depositPct ?? 0);
    const depositPct = Number.isFinite(depositPctRaw)
      ? Math.min(1, Math.max(0, depositPctRaw))
      : 0;
    const total = Math.max(0, precio * seats);
    const recaudoCentral = poolUsaRecaudoCentral(pool);
    const deposit = recaudoCentral && metodoPago === "transferencia"
      ? total
      : Math.max(0, total * depositPct);
    const expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000); // 2 horas

    let firmSalida = firmSeatsFromReservaDocs(allResSnap.docs);
    if (metodoPago === "efectivo") firmSalida += seats;

    // Snapshot de contacto del cliente para el dueño del viaje
    const userRef = db().collection("usuarios").doc(uidCliente);
    const userSnap = await tx.get(userRef);
    const ud = (userSnap.data() ?? {}) as AnyMap;
    const clienteNombre = String(ud.nombre ?? "");
    const clienteTelefono = String(ud.telefono ?? "");
    const clienteWhatsApp = String(ud.whatsapp ?? ud.telefono ?? "");
    const clienteEmail = String(ud.email ?? request.auth?.token?.email ?? "");

    const resRef = poolRef.collection("reservas").doc();
    const reservaId = resRef.id;

    const reservaFields: AnyMap = {
      uidCliente,
      seats,
      estado: "reservado",
      metodoPago,
      total,
      deposit,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      clienteNombre,
      clienteTelefono,
      clienteWhatsApp,
      clienteEmail,
    };

    let referenciaRecaudo = "";
    let montoEsperadoRecaudoRd = 0;

    if (recaudoCentral && metodoPago === "transferencia") {
      referenciaRecaudo = generarReferenciaRecaudoPool(poolId, reservaId);
      montoEsperadoRecaudoRd = total;
      Object.assign(reservaFields, {
        referenciaRecaudo,
        recaudoDestino: "rai",
        estadoPago: "pendiente",
        montoEsperadoRecaudoRd,
      });
      const regRef = db().collection("referencias_recaudo").doc(referenciaRecaudo);
      tx.set(regRef, {
        tipo: "pool",
        poolId,
        reservaId,
        referenciaRecaudo,
        recaudoDestino: "rai",
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    tx.set(resRef, reservaFields);

    const nuevoOcc = occ + seats;
    const minConf = Number(pool.minParaConfirmar ?? 0);
    const next: AnyMap = {
      asientosReservados: nuevoOcc,
      montoReservado: Number(pool.montoReservado ?? 0) + total,
      asientosFirmesSalida: firmSalida,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (nuevoOcc >= cap) next.estado = "lleno";
    else if (Number.isFinite(minConf) && minConf > 0 && nuevoOcc >= minConf && estado === "abierto") {
      next.estado = "preconfirmado";
    }
    tx.update(poolRef, next);

    return {
      ok: true,
      poolId,
      reservaId,
      recaudoCentral,
      referenciaRecaudo,
      montoEsperadoRecaudoRd,
    };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

/** Cliente reporta foto/PDF del bauche de transferencia para validar su asiento. */
export const reportPoolReservaComprobante = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidCliente = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const reservaId = typeof request.data?.reservaId === "string" ? request.data.reservaId.trim() : "";
  const comprobanteUrl = String(request.data?.comprobanteUrl ?? "").trim();
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!reservaId) throw new HttpsError("invalid-argument", "Falta reservaId");
  if (!comprobanteUrl || comprobanteUrl.length < 12) {
    throw new HttpsError("invalid-argument", "Falta comprobanteUrl valido");
  }

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  await db().runTransaction(async (tx) => {
    const resSnap = await tx.get(resRef);
    if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
    const r = (resSnap.data() ?? {}) as AnyMap;

    if (String(r.uidCliente ?? "").trim() !== uidCliente) {
      throw new HttpsError("permission-denied", "No autorizado para esta reserva");
    }

    const estadoRes = String(r.estado ?? "").trim().toLowerCase();
    if (estadoRes !== "reservado") {
      throw new HttpsError(
        "failed-precondition",
        "Solo se puede subir comprobante en reservas pendientes de pago",
      );
    }

    const metodo = String(r.metodoPago ?? "").trim().toLowerCase();
    if (metodo !== "transferencia") {
      throw new HttpsError(
        "failed-precondition",
        "Comprobante solo aplica a reservas por transferencia",
      );
    }

    tx.update(resRef, {
      comprobanteUrl,
      comprobanteReportadoAt: FieldValue.serverTimestamp(),
      comprobanteReportadoPor: uidCliente,
      estadoPago: "comprobante_enviado",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, poolId, reservaId };
});

/** Cliente cancela su reserva (`estado: reservado`) antes de que la gira salga en ruta. */
export const cancelPoolReservation = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidCliente = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const reservaId = typeof request.data?.reservaId === "string" ? request.data.reservaId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!reservaId) throw new HttpsError("invalid-argument", "Falta reservaId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "cancel_pool_reservation", uidCliente);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  const result = await db().runTransaction(async (tx) => {
    const poolSnap = await tx.get(poolRef);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const pool = (poolSnap.data() ?? {}) as AnyMap;

    const estadoPool = String(pool.estado ?? "").trim().toLowerCase();
    const poolCerrado = ["en_ruta", "finalizado", "cancelado", "cancelado_por_admin"];
    if (poolCerrado.includes(estadoPool)) {
      throw new HttpsError(
        "failed-precondition",
        "Este viaje ya no admite cancelar reservas (en curso, finalizado o cancelado).",
      );
    }

    const resSnap = await tx.get(resRef);
    if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
    const r = (resSnap.data() ?? {}) as AnyMap;

    if (String(r.uidCliente ?? "").trim() !== uidCliente) {
      throw new HttpsError("permission-denied", "No autorizado para esta reserva");
    }

    const estadoRes = String(r.estado ?? "").trim().toLowerCase();
    if (estadoRes === "cancelado" || estadoRes === "cancelado_cliente") {
      return { ok: true, poolId, reservaId, alreadyCanceled: true };
    }
    if (estadoRes === "pagado") {
      throw new HttpsError(
        "failed-precondition",
        "No se puede cancelar una reserva ya pagada/confirmada. Contactá al operador.",
      );
    }
    if (estadoRes !== "reservado") {
      throw new HttpsError("failed-precondition", "Esta reserva no se puede cancelar ahora");
    }

    const seats = Math.max(0, Math.trunc(numOr0(r.seats)));
    const total = Math.max(0, numOr0(r.total));
    const metodo = String(r.metodoPago ?? "").trim().toLowerCase();

    const occ = Math.max(0, Math.trunc(numOr0(pool.asientosReservados)));
    const newOcc = Math.max(0, occ - seats);
    const montoRes = Math.max(0, numOr0(pool.montoReservado));
    const minConf = Math.max(0, Math.trunc(numOr0(pool.minParaConfirmar)));
    const cap = Math.max(0, Math.trunc(numOr0(pool.capacidad)));

    const poolPatch: AnyMap = {
      asientosReservados: newOcc,
      montoReservado: Math.max(0, Number((montoRes - total).toFixed(2))),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (metodo === "efectivo") {
      const firm = Math.max(0, Math.trunc(numOr0(pool.asientosFirmesSalida)));
      poolPatch.asientosFirmesSalida = Math.max(0, firm - seats);
    }

    if (estadoPool === "lleno" && newOcc < cap) {
      poolPatch.estado = "abierto";
    } else if (
      estadoPool === "preconfirmado" &&
      minConf > 0 &&
      newOcc < minConf
    ) {
      poolPatch.estado = "abierto";
    }

    tx.update(poolRef, poolPatch);
    tx.update(resRef, {
      estado: "cancelado_cliente",
      canceladoPor: "cliente",
      canceladoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { ok: true, poolId, reservaId, alreadyCanceled: false, seatsReleased: seats };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  logger.info("[PRE_TEST] cancelPoolReservation", { uidCliente, poolId, reservaId, result });
  return result;
});

/** Admin: revierte reserva pool ya verificada en recaudo central (reembolso manual). */
export const adminRevertPoolReservaPagada = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }

  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const reservaId = typeof request.data?.reservaId === "string" ? request.data.reservaId.trim() : "";
  const motivo = typeof request.data?.motivo === "string" ? request.data.motivo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!reservaId) throw new HttpsError("invalid-argument", "Falta reservaId");
  if (!motivo) throw new HttpsError("invalid-argument", "Falta motivo");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "admin_revert_pool_reserva_pagada", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  const result = await db().runTransaction(async (tx) => {
    const poolSnap = await tx.get(poolRef);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (poolSnap.data() ?? {}) as AnyMap;
    if (!poolUsaRecaudoCentral(pool)) {
      throw new HttpsError("failed-precondition", "Salida no usa recaudo central");
    }

    const estadoPool = String(pool.estado ?? "").trim().toLowerCase();
    if (["en_ruta", "finalizado", "cancelado", "cancelado_por_admin"].includes(estadoPool)) {
      throw new HttpsError(
        "failed-precondition",
        "No se puede revertir: la salida ya inició, finalizó o está cancelada.",
      );
    }

    const resSnap = await tx.get(resRef);
    if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
    const r = (resSnap.data() ?? {}) as AnyMap;

    const estadoRes = String(r.estado ?? "").trim().toLowerCase();
    if (estadoRes === "cancelado_admin" || estadoRes === "cancelado_cliente") {
      return { ok: true, poolId, reservaId, alreadyReverted: true };
    }
    if (estadoRes !== "pagado") {
      throw new HttpsError("failed-precondition", "Solo reservas pagadas/verificadas");
    }
    if (String(r.estadoPago ?? "").trim().toLowerCase() !== "verificado") {
      throw new HttpsError("failed-precondition", "Reserva sin pago central verificado");
    }

    const seats = Math.max(0, Math.trunc(numOr0(r.seats)));
    const total = Math.max(0, numOr0(r.total));
    const comisionRaiRd = Math.max(0, numOr0(r.comisionRaiRd));
    const netoOrganizadorRd = Math.max(0, numOr0(r.netoOrganizadorRd));
    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));
    const firmSalida = firmSeatsFromReservaDocs(
      allResSnap.docs.filter((d) => d.id !== reservaId),
    );

    const pag = Math.max(0, Math.trunc(numOr0(pool.asientosPagados)));
    const occ = Math.max(0, Math.trunc(numOr0(pool.asientosReservados)));
    const montoRes = Math.max(0, numOr0(pool.montoReservado));
    const minConf = Math.max(0, Math.trunc(numOr0(pool.minParaConfirmar)));
    const cap = Math.max(0, Math.trunc(numOr0(pool.capacidad)));
    const newOcc = Math.max(0, occ - seats);
    const newPag = Math.max(0, pag - seats);

    const poolPatch: AnyMap = {
      asientosReservados: newOcc,
      asientosPagados: newPag,
      montoReservado: Math.max(0, Number((montoRes - total).toFixed(2))),
      montoPagado: Math.max(0, Number((numOr0(pool.montoPagado) - total).toFixed(2))),
      montoRecaudadoRaiRd: Math.max(0, Number((numOr0(pool.montoRecaudadoRaiRd) - total).toFixed(2))),
      montoComisionRaiRd: Math.max(0, Number((numOr0(pool.montoComisionRaiRd) - comisionRaiRd).toFixed(2))),
      montoNetoOrganizadorRd: Math.max(
        0,
        Number((numOr0(pool.montoNetoOrganizadorRd) - netoOrganizadorRd).toFixed(2)),
      ),
      asientosFirmesSalida: firmSalida,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (estadoPool === "confirmado" && minConf > 0 && newPag < minConf) {
      poolPatch.estado = newOcc >= minConf ? "preconfirmado" : "abierto";
    } else if (estadoPool === "lleno" && newOcc < cap) {
      poolPatch.estado = "abierto";
    } else if (estadoPool === "preconfirmado" && minConf > 0 && newOcc < minConf) {
      poolPatch.estado = "abierto";
    }

    tx.update(poolRef, poolPatch);
    const reservaRevertPatch: AnyMap = {
      estado: "cancelado_admin",
      estadoPago: "reembolso_pendiente",
      canceladoPor: uidActor,
      canceladoEn: FieldValue.serverTimestamp(),
      revertidoAt: FieldValue.serverTimestamp(),
      revertidoMotivo: motivo,
      updatedAt: FieldValue.serverTimestamp(),
    };
    anularTokenEntradaEnTx(tx, r, reservaRevertPatch);
    tx.update(resRef, reservaRevertPatch);

    tx.set(
      db().collection("ledger_pool_reservas").doc(`${reservaId}_recaudo_revertido`),
      {
        tipo: "recaudo_revertido",
        poolId,
        reservaId,
        ownerTaxistaId,
        brutoRd: total,
        comisionRaiRd,
        netoOrganizadorRd,
        referenciaRecaudo: String(r.referenciaRecaudo ?? ""),
        revertidoPor: uidActor,
        motivo,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      ok: true,
      poolId,
      reservaId,
      alreadyReverted: false,
      reembolsoPendienteRd: total,
    };
  });

  logAdminAudit({
    action: "admin_revert_pool_reserva_pagada",
    actorUid: uidActor,
    resourceType: "pool_reserva",
    resourceId: reservaId,
    metadata: { poolId, motivo, result: result as AnyMap },
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  return result;
});

/** Cliente (o admin): genera ticket si la reserva está pagada y aún no tiene token. */
export const ensurePoolReservaTicket = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  const poolId = trimOrNull(request.data?.poolId);
  const reservaId = trimOrNull(request.data?.reservaId);
  if (!poolId || !reservaId) {
    throw new HttpsError("invalid-argument", "Faltan poolId o reservaId");
  }

  const role = await getRole(uid);
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  const result = await db().runTransaction(async (tx) => {
    const [poolSnap, resSnap] = await Promise.all([tx.get(poolRef), tx.get(resRef)]);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Gira no encontrada");
    if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
    const pool = (poolSnap.data() ?? {}) as AnyMap;
    const res = (resSnap.data() ?? {}) as AnyMap;

    const uidCliente = String(res.uidCliente ?? "");
    const owner = String(pool.ownerTaxistaId ?? "");
    if (role !== "admin" && uid !== uidCliente && uid !== owner) {
      throw new HttpsError("permission-denied", "No autorizado");
    }

    if (String(res.estado ?? "").trim().toLowerCase() !== "pagado") {
      throw new HttpsError(
        "failed-precondition",
        "El ticket está disponible cuando el pago está confirmado.",
      );
    }

    const reservaPatch: AnyMap = { updatedAt: FieldValue.serverTimestamp() };
    asignarTokenEntradaSiFaltaEnTx(tx, poolId, reservaId, res, reservaPatch);
    if (Object.keys(reservaPatch).length > 1) {
      tx.update(resRef, reservaPatch);
    }

    const token = trimOrNull(res.tokenEntrada) ?? trimOrNull(reservaPatch.tokenEntrada);
    return {
      ok: true,
      poolId,
      reservaId,
      tokenEntrada: token ?? "",
      tokenEstado: String(res.tokenEstado ?? reservaPatch.tokenEstado ?? "activo"),
    };
  });

  return result;
});

/** Admin u operador de la gira: valida token QR/código en el punto de salida. */
export const validarTokenEntradaGira = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const token = normalizarTokenEntrada(request.data?.token);
  if (!token) throw new HttpsError("invalid-argument", "Código de ticket inválido");

  const poolIdHint = trimOrNull(request.data?.poolId);
  const role = await getRole(uidActor);

  const ticketRef = db().collection("gira_tickets").doc(token);
  const ticketSnap = await ticketRef.get();
  if (!ticketSnap.exists) {
    throw new HttpsError("not-found", "Ticket no encontrado");
  }
  const ticket = (ticketSnap.data() ?? {}) as AnyMap;
  const poolId = String(ticket.poolId ?? "");
  const reservaId = String(ticket.reservaId ?? "");
  if (!poolId || !reservaId) {
    throw new HttpsError("failed-precondition", "Ticket sin datos de reserva");
  }
  if (poolIdHint && poolIdHint !== poolId) {
    throw new HttpsError("failed-precondition", "Este ticket no corresponde a esta gira");
  }

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  const result = await db().runTransaction(async (tx) => {
    const [poolSnap, resSnap, ticketSnapTx] = await Promise.all([
      tx.get(poolRef),
      tx.get(resRef),
      tx.get(ticketRef),
    ]);
    if (!poolSnap.exists || !resSnap.exists || !ticketSnapTx.exists) {
      throw new HttpsError("not-found", "Reserva o gira no encontrada");
    }

    const pool = (poolSnap.data() ?? {}) as AnyMap;
    const res = (resSnap.data() ?? {}) as AnyMap;
    const t = (ticketSnapTx.data() ?? {}) as AnyMap;

    const owner = String(pool.ownerTaxistaId ?? "");
    if (role !== "admin" && uidActor !== owner) {
      throw new HttpsError("permission-denied", "Solo RAI u operador de esta gira pueden validar");
    }

    const estadoPool = String(pool.estado ?? "").trim().toLowerCase();
    if (["cancelado", "cancelado_por_admin", "finalizado"].includes(estadoPool)) {
      throw new HttpsError("failed-precondition", "La gira no está activa para validar entradas");
    }

    const estadoRes = String(res.estado ?? "").trim().toLowerCase();
    if (estadoRes !== "pagado") {
      throw new HttpsError("failed-precondition", "Reserva sin pago confirmado");
    }

    const tokenEstado = String(t.tokenEstado ?? res.tokenEstado ?? "").trim().toLowerCase();
    if (tokenEstado === "anulado") {
      throw new HttpsError("failed-precondition", "Ticket anulado");
    }
    if (tokenEstado === "usado") {
      throw new HttpsError("failed-precondition", "Ticket ya utilizado");
    }

    const fechaRaw = pool.fechaSalida;
    let fechaSalida: Date | null = null;
    if (fechaRaw instanceof Timestamp) fechaSalida = fechaRaw.toDate();
    else if (fechaRaw instanceof Date) fechaSalida = fechaRaw;
    if (!fechaSalida || !ventanaValidacionTokenGira(fechaSalida, new Date())) {
      throw new HttpsError(
        "failed-precondition",
        "Fuera de ventana de validación (24 h antes a 6 h después de la salida)",
      );
    }

    const seats = Math.max(1, Math.trunc(numOr0(res.seats)));
    const nombre = trimOrNull(res.clienteNombre) ?? "Pasajero";
    const giraNombre =
      trimOrNull(pool.nombreGira) ??
      trimOrNull(pool.servicioBadge) ??
      trimOrNull(pool.destino) ??
      "Gira RAI";

    const reservaPatch: AnyMap = {
      tokenEstado: "usado",
      tokenAsientosValidados: seats,
      tokenValidadoAt: FieldValue.serverTimestamp(),
      tokenValidadoPor: uidActor,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(resRef, reservaPatch);
    tx.set(
      ticketRef,
      {
        tokenEstado: "usado",
        validadoAt: FieldValue.serverTimestamp(),
        validadoPor: uidActor,
      },
      { merge: true },
    );

    return {
      ok: true,
      valido: true,
      token,
      poolId,
      reservaId,
      pasajero: nombre,
      gira: giraNombre,
      asientos: seats,
      agencia: trimOrNull(pool.agenciaNombre) ?? "",
    };
  });

  logger.info("[validarTokenEntradaGira] ok", { uidActor, poolId: result.poolId, reservaId: result.reservaId });
  return result;
});
