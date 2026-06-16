import { FieldValue } from "firebase-admin/firestore";
import { getFirestore } from "firebase-admin/firestore";

type AnyMap = Record<string, unknown>;

export type GiraAbusoCfg = {
  ratioMax: number;
  minCreadas: number;
  disabled: boolean;
};

const db = () => getFirestore();

export async function fetchGiraAbusoUmbral(): Promise<GiraAbusoCfg> {
  try {
    const snap = await db().collection("configuracion_globals").doc("pruebas").get();
    const d = (snap.data() ?? {}) as AnyMap;
    if (d.abuse_disabled === true || d.gira_abuse_disabled === true) {
      return { ratioMax: 1, minCreadas: 999999, disabled: true };
    }
    let ratio = 0.5;
    const raw = d.abuse_threshold;
    if (typeof raw === "number") {
      ratio = raw;
      if (ratio > 1.001 && ratio <= 100) ratio = ratio / 100;
    }
    ratio = Math.min(0.99, Math.max(0.01, ratio));
    let minC = 3;
    const minRaw = d.abuse_min_creadas;
    if (typeof minRaw === "number") minC = Math.trunc(minRaw);
    return { ratioMax: ratio, minCreadas: Math.min(100, Math.max(1, minC)), disabled: false };
  } catch {
    return { ratioMax: 0.5, minCreadas: 3, disabled: false };
  }
}

export function evaluarBloqueoPorCancelaciones(
  creadas: number,
  canceladas: number,
  cfg: GiraAbusoCfg,
): boolean {
  if (cfg.disabled || creadas < cfg.minCreadas || canceladas <= 0) return false;
  return canceladas / creadas > cfg.ratioMax + 1e-9;
}

/** Marca en usuarios/{uid} para la cola ADM «Desbloquear salidas por cupos». */
export function mergeGiraAbusoBloqueadoSiAplica(
  patch: AnyMap,
  creadas: number,
  canceladas: number,
  cfg: GiraAbusoCfg,
): void {
  if (!evaluarBloqueoPorCancelaciones(creadas, canceladas, cfg)) return;
  patch.girasAbusoBloqueado = true;
  patch.girasAbusoBloqueadoEn = FieldValue.serverTimestamp();
}
