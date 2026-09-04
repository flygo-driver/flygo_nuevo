/**
 * Tramo de regreso de los viajes «ida y vuelta».
 *
 * El cliente paga ×1.8 por el regreso, así que el viaje no puede cerrarse en el
 * destino de ida: o el chofer lo lleva de vuelta, o se le devuelve el recargo y
 * el viaje pasa a cobrarse como solo ida. Va en callable con Admin SDK porque
 * `precio`/`precio_cents` son campos protegidos en las reglas.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

/** Recargo del regreso aplicado al cotizar (TarifaServiceUnificado). */
export const FACTOR_IDA_Y_VUELTA = 1.8;

export const ESTADOS_VIAJE_EN_MARCHA = ["en_curso", "a_bordo"] as const;

/**
 * Precio a cobrar cuando el regreso no se hizo: la ida sola.
 * Devuelve `null` si no hay nada que devolver.
 */
export function precioSoloIdaCents(params: {
  precioActualCents: unknown;
  precioSoloIdaGuardadoCents: unknown;
}): number | null {
  const actual = Number(params.precioActualCents);
  if (!Number.isFinite(actual) || actual <= 0) return null;

  const guardado = Number(params.precioSoloIdaGuardadoCents);
  const soloIda =
    Number.isFinite(guardado) && guardado > 0
      ? Math.round(guardado)
      : Math.round(actual / FACTOR_IDA_Y_VUELTA);

  if (soloIda <= 0) return null;
  if (soloIda >= actual) return null;
  return soloIda;
}

function esViajeDelChofer(d: AnyMap, uid: string): boolean {
  const a = String(d.uidTaxista ?? "").trim();
  const b = String(d.taxistaId ?? "").trim();
  return (a !== "" && a === uid) || (b !== "" && b === uid);
}

function enMarcha(d: AnyMap): boolean {
  const estado = String(d.estado ?? "").trim().toLowerCase();
  return (ESTADOS_VIAJE_EN_MARCHA as readonly string[]).includes(estado);
}

export const registrarRegresoIdaVuelta = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");

    const payload = (request.data ?? {}) as AnyMap;
    const viajeId = String(payload.viajeId ?? "").trim();
    const accion = String(payload.accion ?? "").trim();
    if (!viajeId) throw new HttpsError("invalid-argument", "Falta el viaje.");
    if (accion !== "iniciar" && accion !== "cancelar") {
      throw new HttpsError("invalid-argument", "Acción de regreso inválida.");
    }

    const ref = db().collection("viajes").doc(viajeId);

    const resultado = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "Viaje no encontrado.");
      const d = (snap.data() ?? {}) as AnyMap;

      if (!esViajeDelChofer(d, uid)) {
        throw new HttpsError("permission-denied", "Este viaje no es tuyo.");
      }
      if (d.idaYVuelta !== true) {
        throw new HttpsError("failed-precondition", "El viaje no es ida y vuelta.");
      }
      if (d.completado === true) {
        throw new HttpsError("failed-precondition", "El viaje ya está cerrado.");
      }
      if (!enMarcha(d)) {
        throw new HttpsError(
          "failed-precondition",
          "El regreso solo se registra con el viaje en curso.",
        );
      }
      // Reintento del mismo botón: no es error, ya quedó resuelto.
      if (d.regresoPendiente !== true) {
        return { yaResuelto: true, precioCents: null as number | null };
      }

      if (accion === "iniciar") {
        tx.update(ref, {
          regresoPendiente: false,
          regresoEnCurso: true,
          regresoIniciadoEn: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        });
        return { yaResuelto: false, precioCents: null as number | null };
      }

      const actualCents = Number(
        d.precio_cents ?? Math.round(Number(d.precio ?? 0) * 100),
      );
      const soloIda = precioSoloIdaCents({
        precioActualCents: actualCents,
        precioSoloIdaGuardadoCents: d.precioSoloIdaCents,
      });

      const patch: AnyMap = {
        regresoPendiente: false,
        regresoEnCurso: false,
        regresoNoRealizado: true,
        regresoCanceladoEn: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      };
      if (soloIda != null) {
        patch.precio = soloIda / 100;
        patch.precio_cents = soloIda;
        patch.precioAntesRegresoCanceladoCents = actualCents;
      }
      tx.update(ref, patch);
      return { yaResuelto: false, precioCents: soloIda };
    });

    logger.info("[IDA_VUELTA] regreso registrado", {
      viajeId,
      accion,
      uid,
      precioCents: resultado.precioCents,
      yaResuelto: resultado.yaResuelto,
    });

    return {
      ok: true,
      accion,
      precioCents: resultado.precioCents,
    };
  },
);
