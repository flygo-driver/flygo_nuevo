/**
 * Distribución del código de período (encargado / inicio de ciclo).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { codigoAccesoDesdePeriodo } from "./corporativo_codigo.js";
import { sendMail } from "./mail.js";
import { registrarHistorialNotificacionCorp } from "./corporativo_notificaciones.js";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function esEncargado(ed: AnyMap, uid: string): boolean {
  const uids = Array.isArray(ed.encargadoUids)
    ? (ed.encargadoUids as string[]).map(String)
    : [];
  return uids.includes(uid);
}

async function destinatariosEmpresa(
  empresaId: string,
  ed: AnyMap,
): Promise<{ uid: string; email: string; telefono: string; nombre: string }[]> {
  const out: { uid: string; email: string; telefono: string; nombre: string }[] = [];
  const vistos = new Set<string>();

  const perfiles = (ed.encargadosPerfil ?? {}) as AnyMap;
  const encargados = Array.isArray(ed.encargadoUids)
    ? (ed.encargadoUids as string[]).map(String)
    : [];

  for (const uid of encargados) {
    if (!uid || vistos.has(uid)) continue;
    vistos.add(uid);
    const p = (perfiles[uid] ?? {}) as AnyMap;
    out.push({
      uid,
      email: str(p.email),
      telefono: str(p.telefono),
      nombre: str(p.nombre) || "Encargado",
    });
  }

  const emailEmp = str(ed.emailEmpresa);
  const telEmp = str(ed.telefonoEmpresa);
  if (emailEmp || telEmp) {
    out.push({
      uid: `empresa_${empresaId}`,
      email: emailEmp,
      telefono: telEmp,
      nombre: str(ed.nombre) || "Empresa",
    });
  }

  const plantillas = await getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .where("activa", "==", true)
    .limit(15)
    .get();

  for (const pl of plantillas.docs) {
    const pasajeros = Array.isArray(pl.data().pasajeros)
      ? (pl.data().pasajeros as AnyMap[])
      : [];
    for (const p of pasajeros) {
      if (p.activo === false) continue;
      const tel = str(p.telefono);
      const email = str(p.email);
      if (!tel && !email) continue;
      const key = `${tel}|${email}`;
      if (vistos.has(key)) continue;
      vistos.add(key);
      out.push({ uid: `pas_${str(p.id)}`, email, telefono: tel, nombre: str(p.nombre) });
    }
  }

  return out;
}

async function distribuirCodigo(
  empresaId: string,
  actorUid: string,
  esAdmin: boolean,
): Promise<{ enviados: number; codigo: string }> {
  const empRef = getFirestore().collection("empresas_corporativas").doc(empresaId);
  const empSnap = await empRef.get();
  if (!empSnap.exists) {
    throw new HttpsError("not-found", "Empresa no encontrada");
  }
  const ed = empSnap.data() as AnyMap;
  if (!esAdmin && !esEncargado(ed, actorUid)) {
    throw new HttpsError("permission-denied", "Sin permiso");
  }

  const periodo = (ed.periodoActual ?? {}) as AnyMap;
  const codigo = codigoAccesoDesdePeriodo(periodo);
  if (codigo.length !== 6) {
    throw new HttpsError("failed-precondition", "No hay código de período vigente");
  }

  const destinos = await destinatariosEmpresa(empresaId, ed);
  let enviados = 0;
  const empresaNombre = str(ed.nombre) || "Empresa";
  const texto =
    `Código de verificación RAI Corporativo (${empresaNombre}): ${codigo}\n` +
    "Dicta este código al conductor al subir al vehículo. Válido hasta el pago del período.";

  for (const d of destinos) {
    let canal: "email" | "sms" | "fcm" = "fcm";
    let ok = false;

    if (d.email.includes("@")) {
      canal = "email";
      try {
        await sendMail({
          subject: `RAI Corporativo — código del período (${empresaNombre})`,
          text: texto,
        });
        ok = true;
      } catch (e) {
        logger.warn("distribuirCodigo email", { e, email: d.email });
      }
    }

    if (!ok && d.uid && !d.uid.startsWith("pas_") && !d.uid.startsWith("empresa_")) {
      const tokSnap = await getFirestore().collection("push_tokens").doc(d.uid).get();
      const raw = tokSnap.data()?.tokens;
      const tokens = Array.isArray(raw)
        ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
        : [];
      if (tokens.length > 0) {
        const { getMessaging } = await import("firebase-admin/messaging");
        await getMessaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "Código RAI Corporativo",
            body: `Código del período: ${codigo}`,
          },
          data: { type: "corporativo_codigo_periodo", empresaId },
        });
        ok = true;
        canal = "fcm";
      }
    }

    await registrarHistorialNotificacionCorp({
      empresaId,
      uidDestino: d.uid,
      canal,
      tipo: "codigo_periodo",
      titulo: "Código del período",
      cuerpo: texto,
      enviado: ok,
    });
    if (ok) enviados += 1;
  }

  await empRef.set(
    {
      ultimoCodigoDistribuidoEn: FieldValue.serverTimestamp(),
      ultimoCodigoDistribuidoPor: actorUid,
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { enviados, codigo };
}

/** Encargado: reenviar código a contactos de la empresa. */
export const encargadoReenviarCodigoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const empresaId = str(request.data?.empresaId);
  if (!empresaId) {
    throw new HttpsError("invalid-argument", "Falta empresaId");
  }
  const res = await distribuirCodigo(empresaId, request.auth.uid, false);
  return { ok: true, ...res };
});

/** Admin: distribuir código (mismo flujo). */
export const adminDistribuirCodigoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const adminSnap = await getFirestore()
    .collection("usuarios")
    .doc(request.auth.uid)
    .get();
  if (String(adminSnap.data()?.rol ?? "").toLowerCase() !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }
  const empresaId = str(request.data?.empresaId);
  if (!empresaId) {
    throw new HttpsError("invalid-argument", "Falta empresaId");
  }
  const res = await distribuirCodigo(empresaId, request.auth.uid, true);
  return { ok: true, ...res };
});
