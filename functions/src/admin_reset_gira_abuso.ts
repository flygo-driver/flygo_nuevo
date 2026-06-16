import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  return r === "administrador" ? "admin" : r;
}

async function assertAdmin(uid: string): Promise<void> {
  const u = await db().collection("usuarios").doc(uid).get();
  const r1 = normalizeRole((u.data() as AnyMap | undefined)?.rol);
  if (r1 === "admin") return;
  const r = await db().collection("roles").doc(uid).get();
  if (normalizeRole((r.data() as AnyMap | undefined)?.rol) === "admin") return;
  throw new HttpsError("permission-denied", "Solo administración");
}

/**
 * Desbloquea al taxista para volver a publicar giras por cupos tras muchas cancelaciones
 * sin iniciar. Solo Admin SDK (callable admin).
 */
export const adminRegularizarGirasTaxista = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const uidTaxista =
    typeof request.data?.uidTaxista === "string" ? request.data.uidTaxista.trim() : "";
  const motivo = String(request.data?.motivo ?? "").trim();
  if (!uidTaxista) throw new HttpsError("invalid-argument", "Falta uidTaxista");
  if (motivo.length < 6) {
    throw new HttpsError("invalid-argument", "Motivo requerido (mínimo 6 caracteres)");
  }

  const userRef = db().collection("usuarios").doc(uidTaxista);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Usuario no encontrado");

  const before = (snap.data() ?? {}) as AnyMap;
  const creadasAntes = Math.max(0, Math.trunc(Number(before.girasCreadasUltimoMes ?? 0)));
  const canceladasAntes = Math.max(
    0,
    Math.trunc(Number(before.girasCanceladasAntesDeIniciar ?? 0)),
  );

  await userRef.set(
    {
      girasCreadasUltimoMes: 0,
      girasCanceladasAntesDeIniciar: 0,
      ultimoReinicioContadorGiras: FieldValue.serverTimestamp(),
      girasAbusoBloqueado: false,
      girasAbusoBloqueadoEn: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  logAdminAudit({
    action: "admin_regularizar_giras_taxista",
    actorUid,
    resourceType: "usuarios",
    resourceId: uidTaxista,
    metadata: {
      motivo,
      girasCreadasAntes: creadasAntes,
      girasCanceladasAntes: canceladasAntes,
    },
  });

  return {
    ok: true,
    uidTaxista,
    girasCreadasAntes: creadasAntes,
    girasCanceladasAntes: canceladasAntes,
  };
});
