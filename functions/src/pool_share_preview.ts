import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return 0;
}

function fechaIso(v: unknown): string | null {
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (v && typeof v === "object" && "toDate" in v && typeof (v as Timestamp).toDate === "function") {
    return (v as Timestamp).toDate().toISOString();
  }
  return null;
}

/** Vista previa pública de una gira (sin auth) para /pool?id= en hosting. Sin datos bancarios. */
export const getPoolSharePreview = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "GET") {
      res.status(405).json({ ok: false, error: "method_not_allowed" });
      return;
    }

    const poolId = str(req.query.poolId ?? req.query.id);
    if (!poolId) {
      res.status(400).json({ ok: false, error: "missing_pool_id" });
      return;
    }

    try {
      const snap = await db().collection("viajes_pool").doc(poolId).get();
      if (!snap.exists) {
        res.status(404).json({ ok: false, error: "not_found" });
        return;
      }
      const d = (snap.data() ?? {}) as AnyMap;
      const estado = str(d.estado).toLowerCase();
      if (estado === "cancelado" || estado === "cancelado_por_admin") {
        res.status(410).json({ ok: false, error: "cancelled" });
        return;
      }

      const cap = Math.max(0, Math.floor(num(d.capacidad)));
      const occ = Math.max(0, Math.floor(num(d.asientosReservados)));
      const left = Math.max(0, cap - occ);

      res.status(200).json({
        ok: true,
        poolId,
        origenTown: str(d.origenTown),
        destino: str(d.destino),
        fechaSalida: fechaIso(d.fechaSalida),
        precioPorAsiento: num(d.precioPorAsiento),
        capacidad: cap,
        asientosReservados: occ,
        cuposDisponibles: left,
        estado,
        tipo: str(d.tipo) || "gira",
        sentido: str(d.sentido),
        agenciaNombre: str(d.agenciaNombre) || str(d.taxistaNombre),
        bannerUrl: str(d.bannerUrl),
        bannerVideoUrl: str(d.bannerVideoUrl),
        servicioBadge: str(d.servicioBadge),
        shareLogoUrl: 'https://flygo-rd.web.app/pool/rai-share-card.png',
        ogImageUrl: 'https://flygo-rd.web.app/pool/rai-share-card.png',
      });
    } catch (e) {
      logger.error("[getPoolSharePreview]", poolId, e);
      res.status(500).json({ ok: false, error: "internal" });
    }
  },
);
