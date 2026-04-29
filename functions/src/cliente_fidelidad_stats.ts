import * as functions from "firebase-functions/v2";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const db = () => getFirestore();

function str(v: unknown): string {
  if (v == null) return "";
  return String(v).trim();
}

function normEstado(v: unknown): string {
  return str(v).toLowerCase().replace(/\s+/g, "_");
}

function wasCompleted(data: Record<string, unknown> | undefined): boolean {
  if (!data) return false;
  if (data.completado === true) return true;
  const e = normEstado(data.estado);
  return e === "completado" || e === "finalizado";
}

/** Nivel lógico según total de viajes ya completados (después de incrementar). */
function nivelFromTotalCompletados(n: number): string {
  if (n <= 0) return "nuevo";
  if (n <= 2) return "primeros_viajes";
  if (n <= 14) return "frecuente";
  if (n <= 39) return "habitual";
  return "vip";
}

/** Texto que ve el taxista debajo del título (tipo inDrive). */
function etiquetaLarga(n: number, nivel: string): string {
  switch (nivel) {
    case "nuevo":
      return "Sin viajes cerrados en RAI — puede ser su primera vez; buen trato marca la diferencia.";
    case "primeros_viajes":
      return n === 1
        ? "Solo 1 viaje completado antes — todavía conoce el servicio."
        : `${n} viajes completados — pasajero en etapa inicial con la app.`;
    case "frecuente":
      return `${n} viajes en RAI — ya usa la plataforma con regularidad.`;
    case "habitual":
      return `${n} viajes — cliente fijo: suele conocer el flujo y esperar buen servicio.`;
    default:
      return `${n} viajes — cliente premium / muy frecuente en RAI.`;
  }
}

/** Titular grande en la app del taxista. */
function etiquetaCortaNivel(nivel: string): string {
  switch (nivel) {
    case "nuevo":
      return "Primera vez en RAI";
    case "primeros_viajes":
      return "Pocos viajes en la app";
    case "frecuente":
      return "Cliente frecuente";
    case "habitual":
      return "Cliente fijo";
    default:
      return "Cliente premium";
  }
}

/**
 * Al pasar un viaje a completado: incrementa contador del cliente y nivel para que el taxista lo vea en pedidos.
 * Idempotente: solo en la transición a completado (no doble conteo).
 */
export const onViajeCompletadoClienteFidelidad = functions.firestore.onDocumentUpdated(
  "viajes/{viajeId}",
  async (event) => {
    const before = event.data?.before.data() as Record<string, unknown> | undefined;
    const after = event.data?.after.data() as Record<string, unknown> | undefined;
    if (!before || !after) return;

    if (wasCompleted(before)) return;
    if (!wasCompleted(after)) return;

    const uidCliente = str(after.uidCliente) || str(after.clienteId);
    if (!uidCliente) return;

    const uref = db().collection("usuarios").doc(uidCliente);

    await db().runTransaction(async (tx) => {
      const us = await tx.get(uref);
      const raw = us.data()?.clienteViajesCompletados;
      const prev =
        typeof raw === "number" && Number.isFinite(raw) && raw >= 0
          ? Math.trunc(raw)
          : 0;
      const next = prev + 1;
      const nivel = nivelFromTotalCompletados(next);

      const patch: Record<string, unknown> = {
        clienteViajesCompletados: next,
        clienteNivelConductor: nivel,
        clienteNivelConductorCorta: etiquetaCortaNivel(nivel),
        clienteNivelConductorEtiqueta: etiquetaLarga(next, nivel),
        clienteNivelConductorActualizadoEn: FieldValue.serverTimestamp(),
        clienteUltimoViajeCompletadoEn: FieldValue.serverTimestamp(),
      };

      tx.set(uref, patch, { merge: true });
    });
  },
);
