/**
 * Admin RAI: alta de empresas corporativas y activación de contrato de servicio.
 * Modelo tipo giras: servicio contratado, sin pool ni bloqueos de prepago.
 */
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { generarCodigoAccesoPeriodo } from "./corporativo_codigo.js";
import {
  calcularFinPeriodoCobrable,
  diasSemanaCobrablesEmpresa,
} from "./corporativo_periodo.js";
import {
  ejecutarEliminarPlantillaCorporativa,
  ejecutarPropagacionCambioHoraCorporativa,
  ejecutarSincronizacionOperativaPlantilla,
  limpiarAlertaPlantillaSinChofer,
  refrescarChoferOperacionCorporativa,
} from "./corporativo_rutas.js";
import { mensajeCompromisoChoferDesdeConflictos, detectarConflictosHorarioChofer } from "./corporativo_validacion.js";

const ANDROID_CHANNEL = "rai_driver_notifications";

async function pushChoferAsignacion(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  try {
    const tokSnap = await getFirestore().collection("push_tokens").doc(uid).get();
    const raw = tokSnap.data()?.tokens;
    const tokens = Array.isArray(raw)
      ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
      : [];
    if (tokens.length === 0) return false;
    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { ...data, click_action: "FLUTTER_NOTIFICATION_CLICK" },
      android: {
        notification: { channelId: ANDROID_CHANNEL, sound: "default" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });
    return res.successCount > 0;
  } catch (e) {
    logger.warn("pushChoferAsignacion", { uid, e });
    return false;
  }
}

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function emailNorm(raw: string): string {
  return raw.trim().toLowerCase();
}

/** Clave segura para mapa asignacionesRutas (sin puntos que rompan merge). */
function rutaKeySegura(empresaId: string, plantillaId: string): string {
  return `${empresaId}__${plantillaId}`.replace(/\./g, "_");
}

async function snapPlantillasPorChoferUid(choferUid: string) {
  try {
    return await getFirestore()
      .collectionGroup("plantillas_ruta")
      .where("choferPreferidoUid", "==", choferUid)
      .get();
  } catch (e) {
    logger.error("snapPlantillasPorChoferUid", { choferUid, e });
    throw new HttpsError(
      "failed-precondition",
      "No se pudo validar horarios del conductor. Desplegá el índice "
        + "collectionGroup plantillas_ruta + choferPreferidoUid.",
    );
  }
}

async function assertAdmin(uid: string): Promise<void> {
  const db = getFirestore();
  const snap = await db.collection("usuarios").doc(uid).get();
  const data = (snap.data() ?? {}) as AnyMap;
  const rol = str(data.rol).toLowerCase();
  if (rol === "admin" || rol === "administrador") return;
  if (data.isAdmin === true || data.admin === true) return;
  const rSnap = await db.collection("roles").doc(uid).get();
  const rRol = str(rSnap.data()?.rol).toLowerCase();
  if (rRol === "admin" || rRol === "administrador") return;
  throw new HttpsError("permission-denied", "Solo administración RAI");
}

function periodoInicial(cicloDias: number, now: Date): AnyMap {
  const ciclo = Math.max(1, Math.trunc(cicloDias));
  const inicio = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const fin = calcularFinPeriodoCobrable(
    inicio,
    ciclo,
    diasSemanaCobrablesEmpresa({}),
    new Set<string>(),
  );
  return {
    inicio: Timestamp.fromDate(inicio),
    fin: Timestamp.fromDate(fin),
    cicloDiasCobrables: ciclo,
    modoFin: "dias_cobrables",
    viajesCount: 0,
    montoTotalRd: 0,
    porChofer: {},
    codigoAcceso: generarCodigoAccesoPeriodo(),
  };
}

function buildEncargadoPerfil(
  uid: string,
  u: AnyMap,
  extra?: AnyMap,
): AnyMap {
  return {
    uid,
    nombre: str(extra?.nombre) || str(u.nombre) || str(u.displayName),
    cedula: str(extra?.cedula) || str(u.cedula) || str(u.ciTaxista),
    telefono: str(extra?.telefono) || str(u.telefono),
    email: emailNorm(str(extra?.email) || str(u.email)),
  };
}

function buildChoferPerfil(uid: string, u: AnyMap): AnyMap {
  const estadoDocs = str(u.estadoDocumentos).toLowerCase();
  const docsOk =
    u.documentosCompletos === true ||
    u.documentosAprobados === true ||
    estadoDocs === "aprobado";
  return {
    uid,
    nombre: str(u.nombre) || str(u.displayName),
    email: emailNorm(str(u.email) || str(u.correo)),
    telefono: str(u.telefono),
    cedula: str(u.ciTaxista) || str(u.cedula) || str(u.cedulaTaxista),
    placa: str(u.placa).toUpperCase(),
    marca: str(u.vehiculoMarca) || str(u.marca),
    modelo: str(u.vehiculoModelo) || str(u.modelo),
    color: str(u.vehiculoColor) || str(u.color),
    anio: str(u.anio) || str(u.vehiculoAnio),
    tipoVehiculo: str(u.tipoVehiculo) || str(u.vehiculoTipo),
    documentosVerificados: docsOk,
    fotoUrl: str(u.fotoUrl) || str(u.photoURL) || str(u.imagenPerfil),
    asignadoEn: FieldValue.serverTimestamp(),
  };
}

/**
 * Resuelve UID por correo de forma robusta:
 * 1) Firebase Auth (no distingue mayúsculas)
 * 2) Firestore email / correo en minúsculas y tal cual se escribió
 * Si encuentra, normaliza email en usuarios para búsquedas futuras.
 */
async function resolverUidPorEmail(email: string): Promise<string> {
  const raw = email.trim();
  const normalized = emailNorm(raw);
  if (!normalized.includes("@")) {
    throw new HttpsError("invalid-argument", "Correo del encargado inválido");
  }

  const db = getFirestore();
  let uid = "";

  try {
    const authUser = await getAuth().getUserByEmail(normalized);
    uid = authUser.uid;
  } catch {
    // no Auth match — seguir a Firestore
  }

  if (!uid) {
    const variants = [...new Set([normalized, raw].filter((v) => v.length > 0))];
    for (const field of ["email", "correo"]) {
      for (const v of variants) {
        const q = await db.collection("usuarios").where(field, "==", v).limit(3).get();
        if (!q.empty) {
          uid = q.docs[0].id;
          break;
        }
      }
      if (uid) break;
    }
  }

  if (!uid) {
    throw new HttpsError(
      "not-found",
      "No hay usuario RAI con ese correo. Debe haber entrado antes con Google o correo en la app.",
    );
  }

  // Normalizar email en doc para que Admin Buscar no falle por mayúsculas.
  const ref = db.collection("usuarios").doc(uid);
  const snap = await ref.get();
  const u = (snap.data() ?? {}) as AnyMap;
  const emailActual = str(u.email);
  const correoActual = str(u.correo);
  const patch: AnyMap = {};
  if (emailActual !== normalized) patch.email = normalized;
  if (correoActual && correoActual !== emailNorm(correoActual)) {
    patch.correo = emailNorm(correoActual);
  }
  if (!emailActual && !correoActual) patch.email = normalized;
  if (Object.keys(patch).length > 0) {
    patch.actualizadoEn = FieldValue.serverTimestamp();
    await ref.set(patch, { merge: true });
  }

  return uid;
}

/** Admin: busca usuario RAI por correo y devuelve datos de perfil. */
export const adminResolverUsuarioPorEmail = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const email = str(request.data?.email);
  const uid = await resolverUidPorEmail(email);
  const snap = await getFirestore().collection("usuarios").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Usuario sin perfil en RAI");
  }
  const u = (snap.data() ?? {}) as AnyMap;
  return {
    ok: true,
    uid,
    nombre: str(u.nombre) || str(u.displayName),
    cedula: str(u.cedula) || str(u.ciTaxista) || str(u.cedulaTaxista),
    telefono: str(u.telefono) || str(u.whatsapp),
    email: emailNorm(str(u.email) || str(u.correo) || email),
    rol: str(u.rol).toLowerCase(),
  };
});

function mapUsuarioCandidato(uid: string, u: AnyMap, extra?: AnyMap): AnyMap {
  return {
    uid,
    nombre: str(u.nombre) || str(u.displayName) || "Usuario RAI",
    email: emailNorm(str(u.email) || str(u.correo)),
    telefono: str(u.telefono) || str(u.whatsapp),
    cedula: str(u.cedula) || str(u.ciTaxista) || str(u.cedulaTaxista),
    rol: str(u.rol).toLowerCase(),
    ...(extra ?? {}),
  };
}

function detectarTipoBusquedaUsuario(q: string): "email" | "telefono" | "cedula" | "nombre" {
  const raw = q.trim();
  if (raw.includes("@")) return "email";
  const digits = raw.replace(/\D/g, "");
  if (digits.length >= 10 && /^[\d\s+\-()]+$/.test(raw)) return "telefono";
  if (digits.length >= 9 && digits.length <= 11 && digits === raw.replace(/[\s-]/g, "")) {
    return "cedula";
  }
  return "nombre";
}

async function buscarUsuariosPorNombre(term: string): Promise<AnyMap[]> {
  const t = term.trim();
  if (t.length < 2) return [];
  const db = getFirestore();
  const needle = t.toLowerCase();
  const seen = new Set<string>();
  const out: AnyMap[] = [];
  const variants = [t, t.toLowerCase(), t.toUpperCase()];
  if (t.length > 0) {
    variants.push(t.charAt(0).toUpperCase() + t.slice(1).toLowerCase());
  }
  for (const field of ["nombre", "displayName"]) {
    for (const v of [...new Set(variants)]) {
      const q = await db
        .collection("usuarios")
        .where(field, ">=", v)
        .where(field, "<=", `${v}\uf8ff`)
        .limit(15)
        .get();
      for (const doc of q.docs) {
        if (seen.has(doc.id)) continue;
        const u = (doc.data() ?? {}) as AnyMap;
        const nombre = str(u.nombre) || str(u.displayName);
        if (!nombre.toLowerCase().includes(needle)) continue;
        seen.add(doc.id);
        out.push(mapUsuarioCandidato(doc.id, u));
        if (out.length >= 12) return out;
      }
    }
  }
  return out;
}

async function buscarUsuariosPorTelefono(digitsRaw: string): Promise<AnyMap[]> {
  const clave = telefonoClave(digitsRaw);
  if (clave.length < 10) return [];
  const db = getFirestore();
  const variants = [...new Set([digitsRaw.replace(/\D/g, ""), clave, `1${clave}`, `+1${clave}`])];
  const seen = new Set<string>();
  const out: AnyMap[] = [];
  for (const field of ["telefono", "whatsapp"]) {
    for (const v of variants) {
      if (v.length < 10) continue;
      const q = await db
        .collection("usuarios")
        .where(field, ">=", v)
        .where(field, "<=", `${v}\uf8ff`)
        .limit(12)
        .get();
      for (const doc of q.docs) {
        if (seen.has(doc.id)) continue;
        const u = (doc.data() ?? {}) as AnyMap;
        const tel = str(u.telefono) || str(u.whatsapp);
        if (!telefonosCoinciden(tel, clave)) continue;
        seen.add(doc.id);
        out.push(mapUsuarioCandidato(doc.id, u));
        if (out.length >= 10) return out;
      }
    }
  }
  return out;
}

async function buscarUsuariosPorCedula(cedula: string): Promise<AnyMap[]> {
  const norm = cedula.replace(/\D/g, "");
  if (norm.length < 9) return [];
  const db = getFirestore();
  const seen = new Set<string>();
  const out: AnyMap[] = [];
  for (const field of ["cedula", "ciTaxista", "cedulaTaxista"]) {
    for (const value of [norm, cedula.trim()]) {
      if (!value) continue;
      const q = await db.collection("usuarios").where(field, "==", value).limit(8).get();
      for (const doc of q.docs) {
        if (seen.has(doc.id)) continue;
        seen.add(doc.id);
        out.push(mapUsuarioCandidato(doc.id, (doc.data() ?? {}) as AnyMap));
      }
    }
  }
  return out.slice(0, 8);
}

async function buscarEmpresasPorTexto(term: string): Promise<AnyMap[]> {
  const t = term.trim();
  if (t.length < 2) return [];
  const db = getFirestore();
  const needle = t.toLowerCase();
  const out: AnyMap[] = [];
  const seen = new Set<string>();

  const variants = [t, t.toLowerCase(), t.toUpperCase()];
  if (t.length > 0) {
    variants.push(t.charAt(0).toUpperCase() + t.slice(1).toLowerCase());
  }
  for (const v of [...new Set(variants)]) {
    const q = await db
      .collection("empresas_corporativas")
      .where("nombre", ">=", v)
      .where("nombre", "<=", `${v}\uf8ff`)
      .limit(15)
      .get();
    for (const doc of q.docs) {
      if (seen.has(doc.id)) continue;
      const d = (doc.data() ?? {}) as AnyMap;
      const nombre = str(d.nombre);
      if (!nombre.toLowerCase().includes(needle) &&
          !str(d.documentoLegal).includes(t.replace(/\D/g, "")) &&
          !str(d.documentoLegal).toLowerCase().includes(needle)) {
        // still accept prefix hits from query
        if (!nombre.toLowerCase().startsWith(v.toLowerCase())) continue;
      }
      seen.add(doc.id);
      const rawUids = Array.isArray(d.encargadoUids)
        ? (d.encargadoUids as unknown[]).map((x) => str(x)).filter(Boolean)
        : [];
      const perfiles = (d.encargadosPerfil as AnyMap) ?? {};
      out.push({
        empresaId: doc.id,
        empresaNombre: nombre || doc.id,
        documentoLegal: str(d.documentoLegal),
        activa: d.activa !== false,
        contratoActivo: d.contratoActivo === true,
        encargados: rawUids.map((uid) => {
          const p = (perfiles[uid] as AnyMap) ?? {};
          return {
            uid,
            nombre: str(p.nombre),
            email: emailNorm(str(p.email)),
            telefono: str(p.telefono),
            cedula: str(p.cedula),
          };
        }),
      });
      if (out.length >= 10) return out;
    }
  }

  // RNC / cédula empresa exacta
  const docDigits = t.replace(/\D/g, "");
  if (docDigits.length >= 9) {
    const qDoc = await db
      .collection("empresas_corporativas")
      .where("documentoLegal", "==", docDigits)
      .limit(5)
      .get();
    for (const doc of qDoc.docs) {
      if (seen.has(doc.id)) continue;
      const d = (doc.data() ?? {}) as AnyMap;
      seen.add(doc.id);
      const rawUids = Array.isArray(d.encargadoUids)
        ? (d.encargadoUids as unknown[]).map((x) => str(x)).filter(Boolean)
        : [];
      const perfiles = (d.encargadosPerfil as AnyMap) ?? {};
      out.push({
        empresaId: doc.id,
        empresaNombre: str(d.nombre) || doc.id,
        documentoLegal: str(d.documentoLegal),
        activa: d.activa !== false,
        contratoActivo: d.contratoActivo === true,
        encargados: rawUids.map((uid) => {
          const p = (perfiles[uid] as AnyMap) ?? {};
          return {
            uid,
            nombre: str(p.nombre),
            email: emailNorm(str(p.email)),
            telefono: str(p.telefono),
            cedula: str(p.cedula),
          };
        }),
      });
    }
  }

  // Empresas cuyo encargado coincide por nombre (no solo prefijo de empresa).
  if (out.length < 10 && t.length >= 3) {
    const encargados = await buscarUsuariosPorNombre(t);
    for (const enc of encargados) {
      const uidEnc = str(enc.uid);
      if (!uidEnc) continue;
      try {
        const qEnc = await db
          .collection("empresas_corporativas")
          .where("encargadoUids", "array-contains", uidEnc)
          .limit(8)
          .get();
        for (const doc of qEnc.docs) {
          if (seen.has(doc.id)) continue;
          const d = (doc.data() ?? {}) as AnyMap;
          seen.add(doc.id);
          const rawUids = Array.isArray(d.encargadoUids)
            ? (d.encargadoUids as unknown[]).map((x) => str(x)).filter(Boolean)
            : [];
          const perfiles = (d.encargadosPerfil as AnyMap) ?? {};
          out.push({
            empresaId: doc.id,
            empresaNombre: str(d.nombre) || doc.id,
            documentoLegal: str(d.documentoLegal),
            activa: d.activa !== false,
            contratoActivo: d.contratoActivo === true,
            encargados: rawUids.map((uid) => {
              const p = (perfiles[uid] as AnyMap) ?? {};
              return {
                uid,
                nombre: str(p.nombre),
                email: emailNorm(str(p.email)),
                telefono: str(p.telefono),
                cedula: str(p.cedula),
              };
            }),
          });
          if (out.length >= 10) return out;
        }
      } catch (e) {
        logger.warn("buscarEmpresasPorTexto encargado", { uidEnc, e });
      }
    }
  }

  return out;
}

/**
 * Admin: búsqueda coherente de usuarios y empresas.
 * Criterios: correo, nombre, teléfono, cédula, nombre/RNC de empresa.
 */
export const adminBuscarCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const busqueda = str(request.data?.busqueda);
  if (busqueda.length < 2) {
    throw new HttpsError("invalid-argument", "Escribe al menos 2 caracteres");
  }
  const tipoForzado = str(request.data?.tipoBusqueda);
  const tipo = tipoForzado && tipoForzado !== "auto"
    ? tipoForzado
    : detectarTipoBusquedaUsuario(busqueda);

  const usuarios: AnyMap[] = [];
  const seenU = new Set<string>();
  const pushU = (list: AnyMap[]) => {
    for (const c of list) {
      const id = str(c.uid);
      if (!id || seenU.has(id)) continue;
      seenU.add(id);
      usuarios.push(c);
    }
  };

  if (tipo === "email" || busqueda.includes("@")) {
    try {
      const uid = await resolverUidPorEmail(busqueda);
      const snap = await getFirestore().collection("usuarios").doc(uid).get();
      if (snap.exists) {
        pushU([mapUsuarioCandidato(uid, (snap.data() ?? {}) as AnyMap)]);
      }
    } catch {
      // sin match de email
    }
  }

  if (tipo === "telefono" || telefonoClave(busqueda).length >= 10) {
    pushU(await buscarUsuariosPorTelefono(busqueda));
  }
  if (tipo === "cedula" || busqueda.replace(/\D/g, "").length >= 9) {
    pushU(await buscarUsuariosPorCedula(busqueda));
  }
  if (tipo === "nombre" || tipo === "auto" || (!busqueda.includes("@") && busqueda.replace(/\D/g, "").length < 9)) {
    pushU(await buscarUsuariosPorNombre(busqueda));
  }

  // Siempre buscar empresas por texto (nombre / RNC) y sumar encargados como candidatos.
  const empresas = await buscarEmpresasPorTexto(busqueda);
  for (const emp of empresas) {
    const encs = Array.isArray(emp.encargados) ? (emp.encargados as AnyMap[]) : [];
    for (const enc of encs) {
      const uid = str(enc.uid);
      if (!uid || seenU.has(uid)) continue;
      // Si el perfil en empresa no tiene email, completar desde usuarios.
      let uData: AnyMap = { ...enc };
      const uSnap = await getFirestore().collection("usuarios").doc(uid).get();
      if (uSnap.exists) {
        uData = { ...(uSnap.data() ?? {}), ...enc };
      }
      seenU.add(uid);
      usuarios.push(
        mapUsuarioCandidato(uid, uData, {
          empresaId: str(emp.empresaId),
          empresaNombre: str(emp.empresaNombre),
          matchPor: "empresa",
        }),
      );
    }
  }

  return {
    ok: true,
    tipoUsado: tipo,
    usuarios: usuarios.slice(0, 15),
    empresas: empresas.slice(0, 10),
  };
});

function cedulaDeUsuario(u: AnyMap): string {
  return str(u.ciTaxista) || str(u.cedula) || str(u.cedulaTaxista);
}

function esChoferRol(u: AnyMap): boolean {
  const rol = str(u.rol).toLowerCase();
  return rol === "taxista" || rol === "driver" || rol === "conductor";
}

function mapChoferCandidato(id: string, u: AnyMap): AnyMap {
  return {
    uid: id,
    nombre: str(u.nombre) || str(u.displayName) || "Conductor RAI",
    email: emailNorm(str(u.email) || str(u.correo)),
    telefono: str(u.telefono),
    cedula: cedulaDeUsuario(u),
    placa: str(u.placa).toUpperCase(),
    marca: str(u.vehiculoMarca) || str(u.marca),
    modelo: str(u.vehiculoModelo) || str(u.modelo),
  };
}

function mapChoferCandidatoCorporativo(id: string, c: AnyMap): AnyMap {
  return {
    uid: id,
    nombre: str(c.nombre) || "Conductor RAI",
    email: emailNorm(str(c.email)),
    telefono: str(c.telefono),
    cedula: str(c.cedula),
    placa: str(c.placa).toUpperCase(),
    marca: str(c.marca),
    modelo: str(c.modelo),
    enPool: true,
  };
}

async function buscarChoferesPorEmail(email: string): Promise<AnyMap[]> {
  const raw = email.trim();
  if (!raw.includes("@")) return [];
  try {
    const uid = await resolverUidPorEmail(raw);
    const snap = await getFirestore().collection("usuarios").doc(uid).get();
    if (!snap.exists) return [];
    const u = (snap.data() ?? {}) as AnyMap;
    if (!esChoferRol(u)) return [];
    const poolSnap = await getFirestore()
      .collection("choferes_corporativos")
      .doc(uid)
      .get();
    const enPool =
      poolSnap.exists &&
      esChoferCorporativoActivo((poolSnap.data() ?? {}) as AnyMap);
    return [{ ...mapChoferCandidato(uid, u), enPool }];
  } catch {
    return [];
  }
}

function esChoferCorporativoActivo(c: AnyMap): boolean {
  const estado = str(c.estado).toLowerCase();
  if (estado !== "aprobado" && estado !== "activo") return false;
  return c.activo !== false;
}

async function assertChoferCorporativoActivo(uid: string): Promise<void> {
  const snap = await getFirestore().collection("choferes_corporativos").doc(uid).get();
  if (!snap.exists || !esChoferCorporativoActivo((snap.data() ?? {}) as AnyMap)) {
    throw new HttpsError(
      "failed-precondition",
      "El conductor no está habilitado en el pool corporativo RAI",
    );
  }
}

/** Últimos 10 dígitos: formato local RD / con o sin 1 de país. */
function telefonoClave(raw: string): string {
  const d = raw.replace(/\D/g, "");
  if (d.length >= 10) return d.slice(-10);
  return d;
}

function telefonosCoinciden(a: string, b: string): boolean {
  const ka = telefonoClave(a);
  const kb = telefonoClave(b);
  return ka.length >= 10 && ka === kb;
}

/** Busca taxista RAI en usuarios por teléfono (no solo pool). */
async function buscarTaxistaUsuarioPorTelefono(telefono: string): Promise<{
  uid: string;
  data: AnyMap;
} | null> {
  const digits = telefono.replace(/\D/g, "");
  const clave = telefonoClave(digits);
  if (clave.length < 10) return null;

  const db = getFirestore();
  const variants = [...new Set([
    digits,
    clave,
    `1${clave}`,
    `+1${clave}`,
    `+${digits}`,
  ])];

  for (const v of variants) {
    if (v.length < 10) continue;
    const q = await db
      .collection("usuarios")
      .where("telefono", ">=", v)
      .where("telefono", "<=", `${v}\uf8ff`)
      .limit(12)
      .get();
    for (const doc of q.docs) {
      const u = (doc.data() ?? {}) as AnyMap;
      if (!esChoferRol(u)) continue;
      if (!telefonosCoinciden(str(u.telefono), clave)) continue;
      return { uid: doc.id, data: u };
    }
  }

  // Fallback: escaneo acotado por prefijo local (índice telefono).
  const q2 = await db
    .collection("usuarios")
    .where("telefono", ">=", clave)
    .where("telefono", "<=", `${clave}\uf8ff`)
    .limit(20)
    .get();
  for (const doc of q2.docs) {
    const u = (doc.data() ?? {}) as AnyMap;
    if (!esChoferRol(u)) continue;
    if (!telefonosCoinciden(str(u.telefono), clave)) continue;
    return { uid: doc.id, data: u };
  }
  return null;
}

/** Habilita (o reactiva) taxista en pool corporativo. Idempotente. */
async function habilitarChoferEnPool(
  choferUid: string,
  adminUid: string,
  fuente = "admin_asignar_ruta",
): Promise<AnyMap> {
  const perfil = await perfilChoferCorporativoDesdeUsuario(choferUid);
  const ref = getFirestore().collection("choferes_corporativos").doc(choferUid);
  const prev = await ref.get();
  const payload: AnyMap = {
    ...perfil,
    estado: "aprobado",
    activo: true,
    disponible: true,
    verificadoPor: adminUid,
    verificadoEn: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
    fuente,
  };
  if (!prev.exists) {
    payload.creadoEn = FieldValue.serverTimestamp();
  }
  await ref.set(payload, { merge: true });
  return payload;
}

async function perfilChoferCorporativoDesdeUsuario(uid: string): Promise<AnyMap> {
  const db = getFirestore();
  const uSnap = await db.collection("usuarios").doc(uid).get();
  if (!uSnap.exists) {
    throw new HttpsError("not-found", "Usuario taxista no encontrado");
  }
  const u = (uSnap.data() ?? {}) as AnyMap;
  if (!esChoferRol(u)) {
    throw new HttpsError("failed-precondition", "El usuario no es taxista RAI");
  }
  const estadoDocs = str(u.estadoDocumentos).toLowerCase();
  const docsOk =
    u.documentosCompletos === true ||
    u.documentosAprobados === true ||
    estadoDocs === "aprobado";
  return {
    uid,
    nombre: str(u.nombre) || str(u.displayName),
    email: str(u.email),
    telefono: str(u.telefono),
    cedula: cedulaDeUsuario(u),
    placa: str(u.placa).toUpperCase(),
    marca: str(u.vehiculoMarca) || str(u.marca),
    modelo: str(u.vehiculoModelo) || str(u.modelo),
    color: str(u.vehiculoColor) || str(u.color),
    anio: str(u.anio) || str(u.vehiculoAnio),
    tipoVehiculo: str(u.tipoVehiculo) || str(u.vehiculoTipo),
    documentosVerificados: docsOk,
    fotoUrl: str(u.fotoUrl) || str(u.photoURL) || str(u.imagenPerfil),
    estado: "aprobado",
    activo: true,
    disponible: true,
    viajesCorporativos: 0,
    actualizadoEn: FieldValue.serverTimestamp(),
  };
}

function detectarTipoBusquedaChofer(
  busqueda: string,
): "telefono" | "cedula" | "nombre" | "email" {
  const raw = busqueda.trim();
  if (raw.includes("@")) return "email";
  const compact = raw.replace(/\s/g, "");
  const digits = raw.replace(/\D/g, "");
  if (digits.length === 11 && /^[\d-]+$/.test(compact)) return "cedula";
  if (digits.length >= 10 && /^[\d\s+\-()]+$/.test(raw)) return "telefono";
  if (digits.length >= 9 && digits.length <= 11 && digits === compact.replace(/-/g, "")) {
    return "cedula";
  }
  return "nombre";
}

async function buscarChoferesPorTelefono(digits: string): Promise<AnyMap[]> {
  if (digits.length < 10) return [];
  const db = getFirestore();
  const seen = new Set<string>();
  const out: AnyMap[] = [];

  const q = await db
    .collection("choferes_corporativos")
    .where("telefono", ">=", digits)
    .where("telefono", "<=", `${digits}\uf8ff`)
    .limit(12)
    .get();
  for (const doc of q.docs) {
    const c = (doc.data() ?? {}) as AnyMap;
    if (!esChoferCorporativoActivo(c) || seen.has(doc.id)) continue;
    seen.add(doc.id);
    out.push({
      ...mapChoferCandidatoCorporativo(doc.id, c),
      enPool: true,
    });
  }

  // También taxistas RAI por teléfono (aún no en pool): admin puede elegirlos.
  const found = await buscarTaxistaUsuarioPorTelefono(digits);
  if (found && !seen.has(found.uid)) {
    out.push({
      ...mapChoferCandidato(found.uid, found.data),
      enPool: false,
    });
  }

  return out.slice(0, 12);
}

async function buscarChoferesPorCedula(cedula: string): Promise<AnyMap[]> {
  const norm = cedula.replace(/\D/g, "");
  if (norm.length < 9) return [];
  const db = getFirestore();
  const seen = new Set<string>();
  const out: AnyMap[] = [];
  for (const value of [norm, cedula.trim()]) {
    if (!value) continue;
    const q = await db.collection("choferes_corporativos").where("cedula", "==", value).limit(8).get();
    for (const doc of q.docs) {
      const c = (doc.data() ?? {}) as AnyMap;
      if (!esChoferCorporativoActivo(c) || seen.has(doc.id)) continue;
      seen.add(doc.id);
      out.push(mapChoferCandidatoCorporativo(doc.id, c));
    }
  }
  return out.slice(0, 8);
}

async function buscarChoferesPorNombre(term: string): Promise<AnyMap[]> {
  const t = term.trim();
  if (t.length < 3) return [];
  const db = getFirestore();
  const needle = t.toLowerCase();
  const seen = new Set<string>();
  const out: AnyMap[] = [];
  const variants = [t, t.toLowerCase(), t.toUpperCase()];
  if (t.length > 0) {
    variants.push(t.charAt(0).toUpperCase() + t.slice(1).toLowerCase());
  }
  for (const v of [...new Set(variants)]) {
    try {
      const q = await db
        .collection("choferes_corporativos")
        .where("nombre", ">=", v)
        .where("nombre", "<=", `${v}\uf8ff`)
        .limit(12)
        .get();
      for (const doc of q.docs) {
        const c = (doc.data() ?? {}) as AnyMap;
        if (!esChoferCorporativoActivo(c) || seen.has(doc.id)) continue;
        const nombre = str(c.nombre);
        if (!nombre.toLowerCase().includes(needle)) continue;
        seen.add(doc.id);
        out.push({
          ...mapChoferCandidatoCorporativo(doc.id, c),
          enPool: true,
        });
        if (out.length >= 8) return out;
      }
    } catch (e) {
      logger.warn("buscarChoferesPorNombre pool", { v, e });
    }
  }

  // Fallback: taxistas por nombre (prefijo) si el pool no alcanzó 8.
  if (out.length < 8) {
    const v0 = variants[0];
    try {
      const uq = await db
        .collection("usuarios")
        .where("nombre", ">=", v0)
        .where("nombre", "<=", `${v0}\uf8ff`)
        .limit(20)
        .get();
      for (const doc of uq.docs) {
        if (seen.has(doc.id) || out.length >= 8) break;
        const u = (doc.data() ?? {}) as AnyMap;
        const rol = str(u.rol).toLowerCase();
        if (rol !== "taxista" && rol !== "conductor") continue;
        const nombre = str(u.nombre) || str(u.displayName);
        if (!nombre.toLowerCase().includes(needle)) continue;
        seen.add(doc.id);
        out.push({
          ...mapChoferCandidato(doc.id, u),
          enPool: false,
        });
      }
    } catch {
      /* índice nombre opcional */
    }
  }
  return out;
}

async function buscarChoferesCandidatos(
  busqueda: string,
  tipoRaw = "auto",
): Promise<AnyMap[]> {
  const q = busqueda.trim();
  if (q.length < 3) return [];
  const tipo = tipoRaw === "auto" ? detectarTipoBusquedaChofer(q) : tipoRaw;
  if (tipo === "email" || q.includes("@")) {
    return buscarChoferesPorEmail(q);
  }
  if (tipo === "telefono") {
    return buscarChoferesPorTelefono(q.replace(/\D/g, ""));
  }
  if (tipo === "cedula") {
    return buscarChoferesPorCedula(q);
  }
  return buscarChoferesPorNombre(q);
}

async function resolverChoferPorTelefono(telefono: string): Promise<string> {
  const candidatos = await buscarChoferesPorTelefono(telefono.replace(/\D/g, ""));
  if (candidatos.length === 0) {
    throw new HttpsError("not-found", "Conductor no encontrado en RAI con ese teléfono");
  }
  return str(candidatos[0].uid);
}

/**
 * Resuelve conductor RAI. Con autoHabilitar:
 * 1) pool activo → uid
 * 2) taxista en usuarios por tel → habilita pool → uid
 */
async function resolverChoferRai(params: {
  choferUid?: string;
  busqueda?: string;
  tipoBusqueda?: string;
  telefonoLegacy?: string;
  autoHabilitar?: boolean;
  adminUid?: string;
}): Promise<{ choferUid: string; recienHabilitado: boolean }> {
  const adminUid = str(params.adminUid);
  const auto = params.autoHabilitar === true && !!adminUid;
  const direct = str(params.choferUid);

  if (direct) {
    if (auto) {
      const snap = await getFirestore().collection("choferes_corporativos").doc(direct).get();
      if (!snap.exists || !esChoferCorporativoActivo((snap.data() ?? {}) as AnyMap)) {
        await habilitarChoferEnPool(direct, adminUid, "admin_asignar_ruta");
        return { choferUid: direct, recienHabilitado: true };
      }
      return { choferUid: direct, recienHabilitado: false };
    }
    await assertChoferCorporativoActivo(direct);
    return { choferUid: direct, recienHabilitado: false };
  }

  const busqueda = str(params.busqueda) || str(params.telefonoLegacy);
  if (!busqueda) {
    throw new HttpsError("invalid-argument", "Indica teléfono o UID del conductor");
  }

  const tipo = str(params.tipoBusqueda) || "auto";
  const tipoEfectivo = tipo === "auto" ? detectarTipoBusquedaChofer(busqueda) : tipo;
  const candidatos = await buscarChoferesCandidatos(busqueda, tipo);

  if (candidatos.length === 1) {
    const uid = str(candidatos[0].uid);
    const enPool = candidatos[0].enPool !== false;
    if (auto && !enPool) {
      await habilitarChoferEnPool(uid, adminUid, "admin_asignar_ruta");
      return { choferUid: uid, recienHabilitado: true };
    }
    return { choferUid: uid, recienHabilitado: false };
  }
  if (candidatos.length > 1) {
    throw new HttpsError(
      "failed-precondition",
      "Hay varios conductores con ese criterio. Usa un teléfono más específico.",
    );
  }

  // No está en pool (o inactivo): si es teléfono, buscar taxista y habilitar.
  if (auto && (tipoEfectivo === "telefono" || telefonoClave(busqueda).length >= 10)) {
    const found = await buscarTaxistaUsuarioPorTelefono(busqueda);
    if (!found) {
      throw new HttpsError(
        "not-found",
        "No hay taxista RAI con ese teléfono. Debe tener cuenta taxista en la app.",
      );
    }
    await habilitarChoferEnPool(found.uid, adminUid, "admin_asignar_ruta");
    return { choferUid: found.uid, recienHabilitado: true };
  }

  throw new HttpsError(
    "not-found",
    "Conductor no habilitado en pool corporativo. Asigna por teléfono para habilitarlo al momento.",
  );
}

/** Admin: busca conductores RAI por teléfono, cédula o nombre. */
export const adminBuscarChoferRai = onCall(async (request) => {
  try {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
    await assertAdmin(request.auth.uid);

    const busqueda = str(request.data?.busqueda);
    const tipoBusqueda = str(request.data?.tipoBusqueda) || "auto";
    if (busqueda.length < 3) {
      throw new HttpsError("invalid-argument", "Escribe al menos 3 caracteres");
    }

    const candidatos = await buscarChoferesCandidatos(busqueda, tipoBusqueda);
    return {
      ok: true,
      tipoUsado: tipoBusqueda === "auto" ? detectarTipoBusquedaChofer(busqueda) : tipoBusqueda,
      candidatos,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    logger.error("adminBuscarChoferRai", e);
    const msg = e instanceof Error ? e.message : String(e);
    throw new HttpsError(
      "internal",
      msg.length > 0 ? `Error al buscar chofer: ${msg.slice(0, 180)}` : "Error al buscar chofer",
    );
  }
});

/** Admin: crea empresa corporativa y vincula encargado (contrato pendiente hasta activar). */
export const adminCrearEmpresaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const nombreEmpresa = str(request.data?.nombreEmpresa);
  let encargadoUid = str(request.data?.encargadoUid);
  const encargadoEmail = str(request.data?.encargadoEmail);
  const tipoDocumento = str(request.data?.tipoDocumento) || "rnc";
  const documentoLegal = str(request.data?.documentoLegal);
  const telefonoEmpresa = str(request.data?.telefonoEmpresa);
  const emailEmpresa = str(request.data?.emailEmpresa);
  const direccion = str(request.data?.direccion);
  const cicloDias = Math.min(
    90,
    Math.max(1, Math.trunc(num(request.data?.facturacionCicloDias) || 15)),
  );
  const formaPagoRaw = str(request.data?.formaPagoRai).toLowerCase();
  const formasOk = new Set(["", "transferencia", "deposito", "cheque", "efectivo", "otro"]);
  const formaPagoRai = formasOk.has(formaPagoRaw) ? formaPagoRaw : "transferencia";
  const contratoMeses = Math.max(1, Math.trunc(num(request.data?.contratoMeses) || 12));

  if (nombreEmpresa.length < 2) {
    throw new HttpsError("invalid-argument", "Nombre de empresa inválido");
  }
  if (documentoLegal.length < 9) {
    throw new HttpsError("invalid-argument", "Indica RNC o cédula de la empresa");
  }
  if (!encargadoUid && encargadoEmail) {
    encargadoUid = await resolverUidPorEmail(encargadoEmail);
  }
  if (!encargadoUid) {
    throw new HttpsError("invalid-argument", "Falta encargado (correo o UID)");
  }

  const db = getFirestore();
  const uSnap = await db.collection("usuarios").doc(encargadoUid).get();
  if (!uSnap.exists) {
    throw new HttpsError("not-found", "Usuario encargado no encontrado");
  }
  const u = (uSnap.data() ?? {}) as AnyMap;
  const perfilEncargado = buildEncargadoPerfil(encargadoUid, u, {
    nombre: request.data?.encargadoNombre,
    cedula: request.data?.encargadoCedula,
    telefono: request.data?.encargadoTelefono,
    email: encargadoEmail || request.data?.encargadoEmail,
  });

  const now = new Date();
  const contratoHasta = new Date(now);
  contratoHasta.setMonth(contratoHasta.getMonth() + contratoMeses);

  const ref = db.collection("empresas_corporativas").doc();
  await ref.set({
    nombre: nombreEmpresa,
    encargadoUids: [encargadoUid],
    tipoDocumento,
    documentoLegal,
    ...(telefonoEmpresa ? { telefonoEmpresa } : {}),
    ...(emailEmpresa ? { emailEmpresa } : {}),
    ...(direccion ? { direccion } : {}),
    encargadosPerfil: { [encargadoUid]: perfilEncargado },
    facturacionCicloDias: cicloDias,
    formaPagoRai,
    activa: true,
    contratoActivo: false,
    contratoDesde: null,
    contratoHasta: Timestamp.fromDate(contratoHasta),
    servicioTipo: "ruta_fija_contratada",
    periodoActual: periodoInicial(cicloDias, now),
    creadoEn: FieldValue.serverTimestamp(),
    creadoPorUid: request.auth.uid,
    actualizadoEn: FieldValue.serverTimestamp(),
  });

  await db.collection("usuarios").doc(encargadoUid).set({
    empresaCorporativaId: ref.id,
    empresaCorporativaNombre: nombreEmpresa,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    ok: true,
    empresaId: ref.id,
    contratoActivo: false,
    codigoAcceso: periodoInicial(cicloDias, now).codigoAcceso,
  };
});

/** Admin: actualiza datos de empresa (RNC, contacto, encargados perfil). */
export const adminActualizarEmpresaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  if (!empresaId) throw new HttpsError("invalid-argument", "Falta empresaId");

  const patch: AnyMap = { actualizadoEn: FieldValue.serverTimestamp() };
  const nombre = str(request.data?.nombreEmpresa);
  if (nombre.length >= 2) patch.nombre = nombre;
  const tipoDocumento = str(request.data?.tipoDocumento);
  if (tipoDocumento) patch.tipoDocumento = tipoDocumento;
  const documentoLegal = str(request.data?.documentoLegal);
  if (documentoLegal.length >= 9) patch.documentoLegal = documentoLegal;
  const telefonoEmpresa = str(request.data?.telefonoEmpresa);
  if (telefonoEmpresa) patch.telefonoEmpresa = telefonoEmpresa;
  const emailEmpresa = str(request.data?.emailEmpresa);
  if (emailEmpresa) patch.emailEmpresa = emailEmpresa;
  const direccion = str(request.data?.direccion);
  if (direccion) patch.direccion = direccion;
  const ciclo = Math.trunc(num(request.data?.facturacionCicloDias));
  if (ciclo > 0) {
    patch.facturacionCicloDias = Math.min(90, Math.max(1, ciclo));
  }
  if (request.data?.formaPagoRai !== undefined) {
    const formaPagoRaw = str(request.data?.formaPagoRai).toLowerCase();
    const formasOk = new Set(["", "transferencia", "deposito", "cheque", "efectivo", "otro"]);
    if (formasOk.has(formaPagoRaw)) patch.formaPagoRai = formaPagoRaw;
  }
  if (request.data?.tarifaViajeContratadaRd !== undefined) {
    const tarifa = Math.max(0, Math.trunc(num(request.data?.tarifaViajeContratadaRd)));
    patch.tarifaViajeContratadaRd = tarifa;
  }

  const db = getFirestore();
  const ref = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await ref.get();
  if (!eSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");

  await ref.set(patch, { merge: true });

  if (nombre.length >= 2) {
    const ed = (eSnap.data() ?? {}) as AnyMap;
    const raw = ed.encargadoUids;
    const uids = Array.isArray(raw)
      ? raw.map((u) => str(u)).filter((u) => u.length > 0)
      : [];
    await Promise.all(
      uids.map((uid) =>
        db.collection("usuarios").doc(uid).set({
          empresaCorporativaNombre: nombre,
          actualizadoEn: FieldValue.serverTimestamp(),
        }, { merge: true }),
      ),
    );
  }

  return { ok: true, empresaId };
});

/** Admin: activa contrato de servicio (empresa puede publicar rutas). */
export const adminActivarContratoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  const meses = Math.max(1, Math.trunc(num(request.data?.contratoMeses) || 12));
  const tarifaViaje = Math.max(0, Math.trunc(num(request.data?.tarifaViajeContratadaRd) || 0));
  if (!empresaId) throw new HttpsError("invalid-argument", "Falta empresaId");

  const db = getFirestore();
  const ref = db.collection("empresas_corporativas").doc(empresaId);
  const now = new Date();
  const hasta = new Date(now);
  hasta.setMonth(hasta.getMonth() + meses);

  await ref.set({
    contratoActivo: true,
    contratoDesde: Timestamp.fromDate(now),
    contratoHasta: Timestamp.fromDate(hasta),
    activa: true,
    ...(tarifaViaje > 0 ? { tarifaViajeContratadaRd: tarifaViaje } : {}),
    contratoActivadoEn: FieldValue.serverTimestamp(),
    contratoActivadoPorUid: request.auth.uid,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, empresaId, contratoHasta: hasta.toISOString() };
});

/** Admin: agrega encargado a empresa existente. */
export const adminAgregarEncargadoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  let encargadoUid = str(request.data?.encargadoUid);
  const encargadoEmail = str(request.data?.encargadoEmail);
  if (!empresaId) {
    throw new HttpsError("invalid-argument", "Falta empresaId");
  }
  if (!encargadoUid && encargadoEmail) {
    encargadoUid = await resolverUidPorEmail(encargadoEmail);
  }
  if (!encargadoUid) {
    throw new HttpsError("invalid-argument", "Falta encargado (correo o UID)");
  }

  const db = getFirestore();
  const ref = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await ref.get();
  if (!eSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");

  const ed = (eSnap.data() ?? {}) as AnyMap;
  const nombre = str(ed.nombre) || "Empresa";
  const raw = ed.encargadoUids;
  const uids = Array.isArray(raw)
    ? raw.map((u) => str(u)).filter((u) => u.length > 0)
    : [];
  if (!uids.includes(encargadoUid)) uids.push(encargadoUid);

  const uSnap = await db.collection("usuarios").doc(encargadoUid).get();
  if (!uSnap.exists) throw new HttpsError("not-found", "Usuario encargado no encontrado");
  const u = (uSnap.data() ?? {}) as AnyMap;
  const perfil = buildEncargadoPerfil(encargadoUid, u, {
    nombre: request.data?.encargadoNombre,
    cedula: request.data?.encargadoCedula,
    telefono: request.data?.encargadoTelefono,
    email: request.data?.encargadoEmail,
  });
  const perfiles = { ...(ed.encargadosPerfil as AnyMap ?? {}) };
  perfiles[encargadoUid] = perfil;

  await ref.set({
    encargadoUids: uids,
    encargadosPerfil: perfiles,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.collection("usuarios").doc(encargadoUid).set({
    empresaCorporativaId: empresaId,
    empresaCorporativaNombre: nombre,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, empresaId, encargadoUids: uids };
});

/** Admin: refresca encargadosPerfil desde el perfil del usuario RAI. */
export const adminSincronizarEncargadosCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  if (!empresaId) throw new HttpsError("invalid-argument", "Falta empresaId");

  const db = getFirestore();
  const ref = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await ref.get();
  if (!eSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");

  const ed = (eSnap.data() ?? {}) as AnyMap;
  const nombreEmpresa = str(ed.nombre) || "Empresa";
  const raw = ed.encargadoUids;
  const uids = Array.isArray(raw)
    ? raw.map((u) => str(u)).filter((u) => u.length > 0)
    : [];
  if (uids.length === 0) {
    return { ok: true, empresaId, sincronizados: 0, encargados: [] };
  }

  const prevPerfiles = { ...((ed.encargadosPerfil as AnyMap) ?? {}) };
  const perfiles: AnyMap = { ...prevPerfiles };
  const resumen: AnyMap[] = [];

  for (const uid of uids) {
    const uSnap = await db.collection("usuarios").doc(uid).get();
    if (!uSnap.exists) continue;
    const u = (uSnap.data() ?? {}) as AnyMap;
    const prev = (prevPerfiles[uid] as AnyMap) ?? {};
    const perfil = buildEncargadoPerfil(uid, u, {
      // Preferir datos vivos del usuario; si faltan, conservar snapshot previo.
      nombre: str(u.nombre) || str(u.displayName) || str(prev.nombre),
      cedula: cedulaDeUsuario(u) || str(prev.cedula),
      telefono: str(u.telefono) || str(prev.telefono),
      email: str(u.email) || str(prev.email),
    });
    perfiles[uid] = perfil;
    resumen.push(perfil);
    await db.collection("usuarios").doc(uid).set({
      empresaCorporativaId: empresaId,
      empresaCorporativaNombre: nombreEmpresa,
      actualizadoEn: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await ref.set({
    encargadosPerfil: perfiles,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    ok: true,
    empresaId,
    sincronizados: resumen.length,
    encargados: resumen,
  };
});

/** Admin: desactiva empresa (soft delete). Deja de operar; no borra historial. */
export const adminDesactivarEmpresaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  if (!empresaId) throw new HttpsError("invalid-argument", "Falta empresaId");

  const db = getFirestore();
  const ref = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await ref.get();
  if (!eSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");

  await ref.set({
    activa: false,
    contratoActivo: false,
    desactivadaEn: FieldValue.serverTimestamp(),
    desactivadaPorUid: request.auth.uid,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, empresaId, activa: false };
});

/** Admin: reactiva empresa desactivada (contrato sigue pendiente de activar). */
export const adminReactivarEmpresaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  if (!empresaId) throw new HttpsError("invalid-argument", "Falta empresaId");

  const db = getFirestore();
  const ref = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await ref.get();
  if (!eSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");

  await ref.set({
    activa: true,
    reactivadaEn: FieldValue.serverTimestamp(),
    reactivadaPorUid: request.auth.uid,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, empresaId, activa: true };
});

function formatHoraHHmm(minutos: number): string {
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/** Admin: cambia hora de recogida y propaga en tiempo real al chofer y encargado. */
export const adminActualizarHoraPlantillaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  const horaRaw = str(request.data?.horaNueva) || str(request.data?.horaRecogidaGrupo);
  if (!empresaId || !plantillaId || !horaRaw) {
    throw new HttpsError(
      "invalid-argument",
      "Faltan empresaId, plantillaId u hora (HH:mm)",
    );
  }

  const horaNueva = formatHoraHHmm(parseHoraMinutos(horaRaw));

  const db = getFirestore();
  const plRef = db
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId);
  const plSnap = await plRef.get();
  if (!plSnap.exists) {
    throw new HttpsError("not-found", "Ruta no encontrada");
  }
  const pl = plSnap.data() ?? {};
  const horaAnterior =
    str(pl.horaRecogidaGrupo) || str(pl.horaRecogida) || "07:00";

  if (horaAnterior === horaNueva) {
    return {
      ok: true,
      sinCambio: true,
      horaNueva,
      mensaje: "La hora ya era la misma.",
    };
  }

  const forzar = request.data?.forzar === true;
  const choferUid = str(pl.choferPreferidoUid);
  if (choferUid) {
    const plConHoraNueva: AnyMap = {
      ...pl,
      horaRecogidaGrupo: horaNueva,
      horaRecogida: horaNueva,
    };
    const conflictos = await detectarConflictosHorarioChofer({
      choferUid,
      empresaId,
      plantillaId,
      plantilla: plConHoraNueva,
    });
    if (conflictos.length > 0 && !forzar) {
      const uSnap = await db.collection("usuarios").doc(choferUid).get();
      const uData = (uSnap.data() ?? {}) as AnyMap;
      const nombreChofer =
        str(uData.nombre) || str(uData.displayName) || "Este conductor";
      return {
        ok: true,
        sinCambio: true,
        requiereConfirmacion: true,
        conflictos,
        horaNueva,
        mensaje: mensajeCompromisoChoferDesdeConflictos(conflictos, nombreChofer),
      };
    }
  }

  await plRef.set(
    {
      horaRecogidaGrupo: horaNueva,
      horaRecogida: horaNueva,
      horaActualizadaPorAdminUid: request.auth.uid,
      horaActualizadaEn: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (choferUid) {
    const rutaKey = rutaKeySegura(empresaId, plantillaId);
    await db.collection("choferes_corporativos").doc(choferUid).set(
      {
        [`asignacionesRutas.${rutaKey}.hora`]: horaNueva,
        [`asignacionesRutas.${rutaKey}.actualizadoEn`]:
          FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  const propagado = await ejecutarPropagacionCambioHoraCorporativa({
    empresaId,
    plantillaId,
    horaNueva,
    horaAnterior,
  });

  return {
    ok: true,
    empresaId,
    plantillaId,
    horaAnterior,
    horaNueva,
    viajeId: propagado.viajeId,
    pushEnviado: propagado.pushEnviado,
    mensaje:
      `Hora actualizada: ${horaAnterior} → ${horaNueva}. ` +
      "Chofer y encargado ven el cambio en tiempo real.",
  };
});

/** Admin: asigna conductor RAI a plantilla (visible al encargado en tiempo real).
 * Por teléfono: habilita en pool corporativo si hace falta y amarra a esta ruta/empresa.
 * Mismo chofer puede cubrir varias empresas si no chocan horarios.
 */
export const adminAsignarChoferPlantilla = onCall(async (request) => {
  try {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  const choferUid = str(request.data?.choferUid);
  const busqueda = str(request.data?.busqueda);
  const tipoBusqueda = str(request.data?.tipoBusqueda) || "telefono";
  const telefonoChofer = str(request.data?.telefonoChofer);
  const forzar = request.data?.forzar === true;
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }
  if (!choferUid && !busqueda && !telefonoChofer) {
    throw new HttpsError("invalid-argument", "Indica teléfono del conductor");
  }

  const resolved = await resolverChoferRai({
    choferUid,
    busqueda: busqueda || telefonoChofer,
    tipoBusqueda: busqueda || telefonoChofer ? (tipoBusqueda || "telefono") : "auto",
    telefonoLegacy: telefonoChofer,
    autoHabilitar: true,
    adminUid: request.auth.uid,
  });
  const choferId = resolved.choferUid;
  const db = getFirestore();
  const empRef = db.collection("empresas_corporativas").doc(empresaId);
  const plRef = empRef.collection("plantillas_ruta").doc(plantillaId);
  const [empSnap, plSnap] = await Promise.all([empRef.get(), plRef.get()]);
  if (!plSnap.exists) throw new HttpsError("not-found", "Ruta no encontrada");
  const plNueva = plSnap.data() ?? {};
  const prevChoferUid = str(plNueva.choferPreferidoUid);
  const empresaNombre = str(empSnap.data()?.nombre) ||
    str(empSnap.data()?.nombreComercial) ||
    empresaId;
  const plantillaNombre = str(plNueva.nombre) || "Ruta corporativa";
  const pasajerosActivos = Array.isArray(plNueva.pasajeros)
    ? (plNueva.pasajeros as AnyMap[]).filter((p) => p?.activo !== false).length
    : 0;
  const origenLabel = str(plNueva.origenLabel);
  const precioAcordado = Number(plNueva.precioAcordado ?? 0);

  const conflictos = await detectarConflictosHorarioChofer({
    choferUid: choferId,
    empresaId,
    plantillaId,
    plantilla: plNueva,
  });

  if (conflictos.length > 0 && !forzar) {
    const uPrev = await db.collection("usuarios").doc(choferId).get();
    const uPrevData = (uPrev.data() ?? {}) as AnyMap;
    const nombreChofer =
      str(uPrevData.nombre) || str(uPrevData.displayName) || "Este conductor";
    return {
      ok: true,
      asignado: false,
      requiereConfirmacion: true,
      conflictos,
      choferUid: choferId,
      recienHabilitado: resolved.recienHabilitado,
      mensaje: mensajeCompromisoChoferDesdeConflictos(conflictos, nombreChofer),
    };
  }

  const uSnap = await db.collection("usuarios").doc(choferId).get();
  const u = (uSnap.data() ?? {}) as AnyMap;
  const nombre = str(u.nombre) || str(u.displayName) || "Conductor RAI";
  const tel =
    telefonoClave(str(u.telefono)) ||
    telefonoClave(telefonoChofer) ||
    telefonoClave(busqueda);
  const perfil = {
    ...buildChoferPerfil(choferId, u),
    telefono: tel || str(u.telefono),
  };

  const otrasRutas = await listarOtrasRutasChofer({
    choferUid: choferId,
    excludeEmpresaId: empresaId,
    excludePlantillaId: plantillaId,
  });

  const rutaKey = rutaKeySegura(empresaId, plantillaId);
  const vinculo = {
    empresaId,
    empresaNombre,
    plantillaId,
    plantillaNombre,
    hora: str(plNueva.horaRecogidaGrupo) || str(plNueva.horaRecogida) || "07:00",
    choferUid: choferId,
    choferNombre: nombre,
    choferTelefono: tel,
    pasajerosActivos,
    origenLabel,
    precioAcordado,
    asignadoEn: FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(plRef, {
    choferPreferidoUid: choferId,
    choferPreferidoTelefono: tel,
    choferPreferidoNombre: nombre,
    choferAsignadoPerfil: perfil,
    choferAsignadoEnEstaRuta: true,
    choferAsignacion: vinculo,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  const choferPoolRef = db.collection("choferes_corporativos").doc(choferId);
  batch.set(choferPoolRef, {
    estado: "aprobado",
    activo: true,
    disponible: true,
    [`asignacionesRutas.${rutaKey}`]: {
      empresaId,
      empresaNombre,
      plantillaId,
      plantillaNombre,
      hora: vinculo.hora,
      pasajerosActivos,
      origenLabel,
      precioAcordado,
      asignadoEn: FieldValue.serverTimestamp(),
    },
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  // Al cambiar chofer: liberar ruta del conductor anterior.
  if (prevChoferUid && prevChoferUid !== choferId) {
    batch.set(
      db.collection("choferes_corporativos").doc(prevChoferUid),
      {
        [`asignacionesRutas.${rutaKey}`]: FieldValue.delete(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  await batch.commit();

  if (prevChoferUid && prevChoferUid !== choferId) {
    try {
      await refrescarChoferOperacionCorporativa(prevChoferUid);
    } catch (e) {
      logger.warn("adminAsignarChoferPlantilla refresh prev", {
        prevChoferUid,
        e,
      });
    }
  }

  await limpiarAlertaPlantillaSinChofer(empresaId, plantillaId);

  const encargados = Array.isArray(empSnap.data()?.encargadoUids)
    ? (empSnap.data()?.encargadoUids as string[]).map(String)
    : [];

  // Propaga plantilla → choferes_corporativos → viaje de hoy (hora, pasajeros, maps).
  let syncViajeId = "";
  let viajeCreadoEnSync = false;
  let syncPushEnviado = false;
  let syncError = "";
  try {
    const sync = await ejecutarSincronizacionOperativaPlantilla({
      empresaId,
      plantillaId,
      encargadoUid: encargados[0] ?? "",
      operadorUid: request.auth.uid,
      forzarRecogidaHoy: true,
      notificarChoferAsignacion: true,
      enviarPushHora: false,
    });
    syncViajeId = str(sync.viajeId);
    viajeCreadoEnSync = sync.viajeCreado === true;
    syncPushEnviado = sync.pushEnviado === true;
  } catch (e) {
    syncError = e instanceof Error ? e.message : String(e);
    logger.warn("adminAsignarChoferPlantilla sync", {
      empresaId,
      plantillaId,
      choferId,
      e,
    });
    try {
      await refrescarChoferOperacionCorporativa(choferId);
    } catch (e2) {
      logger.warn("adminAsignarChoferPlantilla espejo fallback", { choferId, e2 });
    }
  }

  const horaTxt = str(vinculo.hora) || "07:00";
  let pushOk = syncPushEnviado;
  if (!pushOk) {
    try {
      pushOk = await pushChoferAsignacion(
        choferId,
        viajeCreadoEnSync
          ? "🏢 Ruta corporativa lista"
          : "🏢 Ruta corporativa asignada",
        viajeCreadoEnSync
          ? `${empresaNombre} · ${plantillaNombre}\n` +
            `Recogida a las ${horaTxt}. Abrí Mis rutas corporativas → Abrir ruta.`
          : `${empresaNombre} · ${plantillaNombre}\n` +
            `Recogida a las ${horaTxt}. ` +
            (syncViajeId
              ? "El viaje de hoy ya está en Mis rutas corporativas."
              : "Verás el viaje ~90 min antes de la recogida en Mis rutas."),
        {
          type: viajeCreadoEnSync
            ? "corporativo_asignado"
            : "corporativo_chofer_asignado",
          empresaId,
          plantillaId,
          viajeId: syncViajeId,
          seBusca: "si",
        },
      );
    } catch (e) {
      logger.warn("adminAsignarChoferPlantilla push", { choferId, e });
    }
  }

  const msgBase = resolved.recienHabilitado
    ? `Habilitado en pool y asignado a «${plantillaNombre}» (${empresaNombre}).`
    : `Chofer asignado en esta ruta: «${plantillaNombre}» · ${empresaNombre}.`;

  return {
    ok: true,
    asignado: true,
    choferUid: choferId,
    choferNombre: nombre,
    choferTelefono: tel,
    empresaId,
    empresaNombre,
    plantillaId,
    plantillaNombre,
    recienHabilitado: resolved.recienHabilitado,
    pushEnviado: pushOk,
    viajeId: syncViajeId,
    viajeCreadoEnSync,
    syncError: syncError || undefined,
    conflictos: forzar ? conflictos : [],
    otrasRutasSinChoque: otrasRutas,
    mensaje:
      otrasRutas.length > 0
        ? `${msgBase} También cubre ${otrasRutas.length} ruta(s) en otra(s) empresa(s) sin choque.`
        : msgBase,
  };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    logger.error("adminAsignarChoferPlantilla", e);
    const msg = e instanceof Error ? e.message : String(e);
    const indexIssue =
      msg.includes("index") ||
      msg.includes("FAILED_PRECONDITION") ||
      msg.includes("requires an index");
    throw new HttpsError(
      "failed-precondition",
      indexIssue
        ? "Falta índice Firestore para asignar chofer. Desplegá índices y functions, o reintentá en unos minutos."
        : `No se pudo asignar el chofer: ${msg.slice(0, 180)}`,
    );
  }
});

function parseHoraMinutos(raw: unknown): number {
  const s = str(raw) || "07:00";
  const parts = s.split(":");
  const h = Number(parts[0] ?? 7);
  const m = Number(parts[1] ?? 0);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return 7 * 60;
  return Math.max(0, Math.min(23, Math.trunc(h))) * 60 +
    Math.max(0, Math.min(59, Math.trunc(m)));
}

function diasEfectivosPlantilla(d: AnyMap): number[] {
  const patron = str(d.patronRecurrencia) || "lun_vie";
  const raw = Array.isArray(d.diasSemana)
    ? (d.diasSemana as unknown[]).map((x) => Number(x)).filter((n) => n >= 1 && n <= 7)
    : [];
  if (patron === "lun_vie") return [1, 2, 3, 4, 5];
  if (patron === "diario") return [1, 2, 3, 4, 5, 6, 7];
  if (raw.length > 0) return raw;
  return [1, 2, 3, 4, 5];
}

function bufferOperacionMin(d: AnyMap): number {
  const pasajeros = Array.isArray(d.pasajeros)
    ? (d.pasajeros as AnyMap[]).filter((p) => p.activo !== false).length
    : 3;
  // Recogida + dejar N destinos + margen de traslado entre empresas.
  return Math.max(90, 50 + pasajeros * 25);
}

function diasSeSolapan(a: number[], b: number[]): boolean {
  const setB = new Set(b);
  return a.some((d) => setB.has(d));
}

async function nombreEmpresa(empresaId: string): Promise<string> {
  const snap = await getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .get();
  return str(snap.data()?.nombre) || empresaId;
}

async function listarOtrasRutasChofer(args: {
  choferUid: string;
  excludeEmpresaId: string;
  excludePlantillaId: string;
}): Promise<AnyMap[]> {
  const snap = await snapPlantillasPorChoferUid(args.choferUid);
  const out: AnyMap[] = [];
  for (const doc of snap.docs) {
    const empresaId = doc.ref.parent.parent?.id ?? "";
    if (
      empresaId === args.excludeEmpresaId &&
      doc.id === args.excludePlantillaId
    ) {
      continue;
    }
    const d = doc.data() as AnyMap;
    if (d.activa === false) continue;
    out.push({
      empresaId,
      empresaNombre: await nombreEmpresa(empresaId),
      plantillaId: doc.id,
      plantillaNombre: str(d.nombre) || "Ruta",
      hora: str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00",
      dias: diasEfectivosPlantilla(d),
    });
  }
  return out;
}

/** Admin: quita conductor de plantilla corporativa. */
export const adminDesasignarChoferPlantilla = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }

  const db = getFirestore();
  const plRef = db
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId);
  const plSnap = await plRef.get();
  const plData = (plSnap.data() ?? {}) as AnyMap;
  const prevUid = str(plData.choferPreferidoUid);
  const ultimoViajeId = str(plData.ultimoViajeId);
  const rutaKey = rutaKeySegura(empresaId, plantillaId);

  const batch = db.batch();
  batch.set(plRef, {
    choferPreferidoUid: FieldValue.delete(),
    choferPreferidoTelefono: FieldValue.delete(),
    choferPreferidoNombre: FieldValue.delete(),
    choferAsignadoPerfil: FieldValue.delete(),
    choferAsignadoEnEstaRuta: FieldValue.delete(),
    choferAsignacion: FieldValue.delete(),
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  if (prevUid) {
    batch.set(
      db.collection("choferes_corporativos").doc(prevUid),
      {
        [`asignacionesRutas.${rutaKey}`]: FieldValue.delete(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  await batch.commit();

  if (prevUid) {
    if (ultimoViajeId) {
      try {
        const vRef = db.collection("viajes").doc(ultimoViajeId);
        const vSnap = await vRef.get();
        if (vSnap.exists) {
          const v = (vSnap.data() ?? {}) as AnyMap;
          const asignado =
            str(v.uidTaxista) ||
            str(v.taxistaId) ||
            str(v.corporativoChoferAsignadoUid);
          if (asignado === prevUid && v.completado !== true) {
            await vRef.set(
              {
                uidTaxista: "",
                taxistaId: "",
                corporativoChoferAsignadoUid: FieldValue.delete(),
                corporativoChoferPreferidoUid: FieldValue.delete(),
                corporativoChoferFijoUid: FieldValue.delete(),
                reservadoPor: "",
                estado: "pendiente",
                actualizadoEn: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          }
        }
      } catch (e) {
        logger.warn("adminDesasignarChoferPlantilla viaje", {
          ultimoViajeId,
          prevUid,
          e,
        });
      }
    }
    try {
      await refrescarChoferOperacionCorporativa(prevUid);
    } catch (e) {
      logger.warn("adminDesasignarChoferPlantilla refresh", { prevUid, e });
    }
  }

  return { ok: true };
});

/** Admin: elimina plantilla/ruta corporativa completa (misma lógica que encargado). */
export const adminEliminarRutaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }

  return ejecutarEliminarPlantillaCorporativa({
    empresaId,
    plantillaId,
    operadorUid: request.auth.uid,
    canceladoPor: "admin",
  });
});

/** Admin: habilita taxista en pool corporativo (sin solicitud previa). */
export const adminHabilitarChoferCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  let choferUid = str(request.data?.choferUid);
  const telefono = str(request.data?.telefono);
  if (!choferUid && telefono) {
    const found = await buscarTaxistaUsuarioPorTelefono(telefono);
    if (found) choferUid = found.uid;
  }
  if (!choferUid) {
    throw new HttpsError(
      "invalid-argument",
      "Indica choferUid o teléfono de un taxista RAI registrado",
    );
  }

  const perfil = await habilitarChoferEnPool(
    choferUid,
    request.auth.uid,
    "admin_directo",
  );

  return { ok: true, choferUid, nombre: str(perfil.nombre) };
});

/** Admin: quita taxista del pool corporativo. */
export const adminDeshabilitarChoferCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const choferUid = str(request.data?.choferUid);
  if (!choferUid) throw new HttpsError("invalid-argument", "Falta choferUid");

  await getFirestore().collection("choferes_corporativos").doc(choferUid).set({
    estado: "inactivo",
    activo: false,
    deshabilitadoEn: FieldValue.serverTimestamp(),
    deshabilitadoPorUid: request.auth.uid,
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, choferUid };
});
