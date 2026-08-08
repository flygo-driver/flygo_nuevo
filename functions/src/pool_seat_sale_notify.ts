/**
 * Notificaciones cuando se reserva o confirma un cupo en giras por cupos.
 * Aviso al organizador + operaciones RAI (push + admin_alertas).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();
const messaging = () => getMessaging();
const ANDROID_CHANNEL = "rai_driver_notifications";

export type PoolSeatEvent = "reserva" | "pagado" | "verificado";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
}

async function adminUids(): Promise<string[]> {
  const [adm, admLegacy] = await Promise.all([
    db().collection("usuarios").where("rol", "==", "admin").limit(80).get(),
    db().collection("usuarios").where("rol", "==", "administrador").limit(80).get(),
  ]);
  const out = new Set<string>();
  for (const snap of [adm, admLegacy]) {
    for (const doc of snap.docs) {
      const uid = doc.id.trim();
      if (uid) out.add(uid);
    }
  }
  return [...out];
}

async function tokensForUser(uid: string): Promise<string[]> {
  const tokSnap = await db().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const fromArr = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 12)
    : [];
  if (fromArr.length > 0) return [...new Set(fromArr)];
  const uSnap = await db().collection("usuarios").doc(uid).get();
  const single = str(uSnap.data()?.pushToken);
  return single.length > 12 ? [single] : [];
}

async function pushTokens(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  if (tokens.length === 0) return;
  try {
    await messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { ...data, click_action: "FLUTTER_NOTIFICATION_CLICK" },
      android: {
        notification: { channelId: ANDROID_CHANNEL, sound: "default" },
      },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    });
  } catch (e) {
    logger.warn("[pool_seat_sale_notify] push falló", { err: String(e) });
  }
}

async function pushUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const tokens = await tokensForUser(uid);
  await pushTokens(tokens, title, body, data);
}

async function pushAdmins(
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const uids = await adminUids();
  for (const uid of uids) {
    const tokens = await tokensForUser(uid);
    await pushTokens(tokens, title, body, data);
  }
}

export async function notifyPoolSeatEvent(args: {
  event: PoolSeatEvent;
  poolId: string;
  reservaId: string;
  seats: number;
  clienteNombre?: string;
  metodoPago?: string;
  referenciaRecaudo?: string;
}): Promise<void> {
  const { event, poolId, reservaId, seats } = args;
  if (!poolId || !reservaId || seats <= 0) return;

  try {
    const poolSnap = await db().collection("viajes_pool").doc(poolId).get();
    if (!poolSnap.exists) return;
    const pool = (poolSnap.data() ?? {}) as AnyMap;

    const origen = str(pool.origenTown) || "Origen";
    const destino = str(pool.destino) || "Destino";
    const owner = str(pool.ownerTaxistaId);
    const cap = Math.max(0, Math.trunc(num(pool.capacidad)));
    const occ = Math.max(0, Math.trunc(num(pool.asientosReservados)));
    const pag = Math.max(0, Math.trunc(num(pool.asientosPagados)));
    const quedan = Math.max(0, cap - occ);
    const cuposRaiTope = Math.max(0, Math.trunc(num(pool.cuposComisionRai)));
    const firmesRai = Math.max(0, Math.trunc(num(pool.asientosFirmesSalida)));
    const agencia = str(pool.agenciaNombre) || str(pool.taxistaNombre) || "Organizador";

    const nombreCliente = str(args.clienteNombre) || "Un cliente";
    const metodo = str(args.metodoPago).toLowerCase();
    const ref = str(args.referenciaRecaudo);

    let tituloOrg = "";
    let bodyOrg = "";
    let tituloAdm = "";
    let bodyAdm = "";
    let severidad: "info" | "warning" = "info";
    let tipoAlerta = "pool_cupo_reservado";

    switch (event) {
      case "reserva":
        tituloOrg = "Nueva reserva en tu gira";
        bodyOrg =
          `${nombreCliente} reservó ${seats} cupo(s) · ${origen} → ${destino}. ` +
          `Quedan ${quedan} de ${cap} cupos.`;
        if (metodo === "transferencia") {
          bodyOrg += " Pago pendiente: RAI verificará la transferencia.";
        }
        tituloAdm = `Gira · reserva ${seats} cupo(s)`;
        bodyAdm =
          `${agencia} · ${origen}→${destino} · ${nombreCliente} · ${seats} cupo(s)` +
          (ref ? ` · Ref ${ref}` : "") +
          ` · Quedan ${quedan}/${cap}`;
        severidad = metodo === "transferencia" ? "warning" : "info";
        tipoAlerta = "pool_cupo_reservado";
        break;
      case "pagado":
        tituloOrg = "Venta confirmada en tu gira";
        bodyOrg =
          `${seats} cupo(s) pagado(s) · ${origen} → ${destino}. ` +
          `Total pagados: ${pag}/${cap}. Vendidos en RAI: ${firmesRai}` +
          (cuposRaiTope > 0 ? ` (tope ${cuposRaiTope})` : "") +
          `.`;
        tituloAdm = `Gira · venta confirmada ${seats} cupo(s)`;
        bodyAdm =
          `${agencia} · ${origen}→${destino} · ${nombreCliente} · ${seats} cupo(s) · pagado`;
        tipoAlerta = "pool_cupo_pagado";
        break;
      case "verificado":
        tituloOrg = "RAI verificó el pago de tu gira";
        bodyOrg =
          `${seats} cupo(s) verificado(s) en cuenta RAI · ${origen} → ${destino}. ` +
          `Pagados: ${pag}/${cap} · Vendidos RAI: ${firmesRai}` +
          (cuposRaiTope > 0 ? `/${cuposRaiTope}` : "") +
          `.`;
        tituloAdm = `Gira · pago verificado RAI (${seats} cupos)`;
        bodyAdm =
          `${agencia} · ${origen}→${destino} · ${nombreCliente} · ${seats} cupo(s)` +
          (ref ? ` · Ref ${ref}` : "") +
          ` · Validar en ADM si aplica`;
        tipoAlerta = "pool_cupo_verificado_rai";
        break;
    }

    const dataPush: Record<string, string> = {
      type: tipoAlerta,
      poolId,
      reservaId,
      event,
    };

    await db().collection("admin_alertas").add({
      tipo: tipoAlerta,
      titulo: tituloAdm,
      mensaje: bodyAdm,
      severidad,
      leida: false,
      metadata: {
        poolId,
        reservaId,
        event,
        seats,
        clienteNombre: nombreCliente,
        ownerTaxistaId: owner,
        referenciaRecaudo: ref || null,
        cuposQuedan: quedan,
        capacidad: cap,
        asientosPagados: pag,
        asientosFirmesSalida: firmesRai,
      },
      createdAt: FieldValue.serverTimestamp(),
    });

    if (owner) {
      await pushUser(owner, tituloOrg, bodyOrg, dataPush);
    }
    await pushAdmins(tituloAdm, bodyAdm, dataPush);

    logger.info("[pool_seat_sale_notify] ok", {
      event,
      poolId,
      reservaId,
      seats,
      owner: owner || "—",
    });
  } catch (e) {
    logger.warn("[pool_seat_sale_notify] error no bloqueante", {
      poolId,
      reservaId,
      err: String(e),
    });
  }
}
