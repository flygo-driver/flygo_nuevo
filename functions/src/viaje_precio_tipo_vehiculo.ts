/**
 * Ajusta el precio del viaje cuando el vehículo que acepta no es del tipo que
 * pidió el cliente.
 *
 * El pool no separa por subtipo (un Carro puede tomar un viaje pedido como
 * Jeepeta), así que sin esto el cliente pagaba la tarifa del vehículo caro y
 * recibía el barato. El ajuste vive en un trigger porque `precio`/`precio_cents`
 * son campos protegidos en las reglas: ni la app del chofer ni la callable de
 * aceptar pueden tocarlos.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

const ANDROID_CHANNEL = "rai_driver_notifications";

/** Nunca bajar de este porcentaje del precio acordado, pase lo que pase. */
export const PISO_AJUSTE_PRECIO_VEHICULO = 0.25;

export const TIPOS_VEHICULO_NORMAL = [
  "Carro",
  "Jeepeta",
  "Minivan",
  "Minibús",
  "AutobusGuagua",
] as const;

/** Mismo criterio que `TarifasTramosConfig.normalizarClaveVehiculo` en la app. */
export function normalizarTipoVehiculo(raw: unknown): string {
  const t = String(raw ?? "").trim();
  if (!t) return "";
  const lower = t.toLowerCase();
  if (lower.includes("motor") || lower.includes("moto")) return "motor";
  if (lower.includes("jeep")) return "Jeepeta";
  if (lower.includes("minivan")) return "Minivan";
  if (lower.includes("minib")) return "Minibús";
  if (
    lower.includes("guagua") ||
    lower.includes("autobus") ||
    lower.includes("autobús") ||
    lower.includes("bus")
  ) {
    return "AutobusGuagua";
  }
  if (lower.includes("carro")) return "Carro";
  return t;
}

function centsDeMapa(mapa: unknown, tipo: string): number | null {
  if (!mapa || typeof mapa !== "object") return null;
  const raw = (mapa as AnyMap)[tipo];
  if (typeof raw !== "number" || !Number.isFinite(raw)) return null;
  const cents = Math.round(raw);
  return cents >= 0 ? cents : null;
}

export type AjustePrecioVehiculo = {
  cents: number;
  tipoSolicitado: string;
  tipoAsignado: string;
};

/**
 * Precio a cobrar cuando llega un vehículo distinto al pedido: el del vehículo
 * real, y nunca más de lo que el cliente aceptó pagar. `null` = sin cambio.
 */
export function ajustePrecioPorVehiculoAsignado(params: {
  tipoSolicitado: unknown;
  tipoAsignado: unknown;
  precioAcordadoCents: unknown;
  preciosPorTipo: unknown;
}): AjustePrecioVehiculo | null {
  const solicitado = normalizarTipoVehiculo(params.tipoSolicitado);
  const asignado = normalizarTipoVehiculo(params.tipoAsignado);
  if (!solicitado || !asignado) return null;
  if (solicitado === asignado) return null;
  if (!TIPOS_VEHICULO_NORMAL.includes(solicitado as never)) return null;
  if (!TIPOS_VEHICULO_NORMAL.includes(asignado as never)) return null;

  const acordado = Number(params.precioAcordadoCents);
  if (!Number.isFinite(acordado) || acordado <= 0) return null;

  const delTipoReal = centsDeMapa(params.preciosPorTipo, asignado);
  if (delTipoReal == null) return null;
  if (delTipoReal >= acordado) return null;

  const piso = Math.round(acordado * PISO_AJUSTE_PRECIO_VEHICULO);
  const cents = Math.max(delTipoReal, piso);
  if (cents >= acordado) return null;

  return { cents, tipoSolicitado: solicitado, tipoAsignado: asignado };
}

function rd(cents: number): string {
  return `RD$${(cents / 100).toFixed(0)}`;
}

async function avisarCliente(
  uidCliente: string,
  viajeId: string,
  ajuste: AjustePrecioVehiculo,
  antesCents: number,
): Promise<void> {
  if (!uidCliente) return;
  try {
    const tokSnap = await db().collection("push_tokens").doc(uidCliente).get();
    const raw = tokSnap.data()?.tokens;
    let tokens = Array.isArray(raw)
      ? raw.filter((t): t is string => typeof t === "string" && t.length > 12)
      : [];
    if (tokens.length === 0) {
      const uSnap = await db().collection("usuarios").doc(uidCliente).get();
      const single = String(uSnap.data()?.pushToken ?? "").trim();
      if (single.length > 12) tokens = [single];
    }
    if (tokens.length === 0) return;

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "Ajustamos tu tarifa",
        body:
          `Te recoge un ${ajuste.tipoAsignado} en vez de ${ajuste.tipoSolicitado}. ` +
          `Pagas ${rd(ajuste.cents)} en lugar de ${rd(antesCents)}.`,
      },
      data: {
        type: "precio_ajustado_vehiculo",
        viajeId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: { notification: { channelId: ANDROID_CHANNEL, sound: "default" } },
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (e) {
    logger.warn("[PRECIO_VEHICULO] push cliente falló", {
      viajeId,
      err: String(e),
    });
  }
}

export const ajustarPrecioViajePorVehiculoAsignado = onDocumentUpdated(
  {
    document: "viajes/{viajeId}",
    region: "us-central1",
  },
  async (event) => {
    const antes = (event.data?.before?.data() ?? {}) as AnyMap;
    const despues = (event.data?.after?.data() ?? {}) as AnyMap;
    if (!event.data?.after?.exists) return;

    const taxistaAntes = String(antes.uidTaxista ?? antes.taxistaId ?? "").trim();
    const taxistaDespues = String(
      despues.uidTaxista ?? despues.taxistaId ?? "",
    ).trim();
    // Solo en el instante de la asignación.
    if (taxistaAntes !== "" || taxistaDespues === "") return;
    if (String(despues.tipoServicio ?? "normal") !== "normal") return;
    if (despues.precioAjustadoPorVehiculoEn != null) return;

    const viajeId = String(event.params.viajeId);
    const acordadoCents = Number(
      despues.precio_cents ?? Math.round(Number(despues.precio ?? 0) * 100),
    );

    const ajuste = ajustePrecioPorVehiculoAsignado({
      tipoSolicitado: despues.tipoVehiculoSolicitado,
      tipoAsignado: despues.tipoVehiculoOriginal,
      precioAcordadoCents: acordadoCents,
      preciosPorTipo: despues.preciosPorTipoVehiculoCents,
    });
    if (!ajuste) return;

    await db()
      .collection("viajes")
      .doc(viajeId)
      .update({
        precio: ajuste.cents / 100,
        precio_cents: ajuste.cents,
        precioAjustadoPorVehiculo: true,
        precioAjustadoPorVehiculoEn: FieldValue.serverTimestamp(),
        precioAntesAjusteVehiculoCents: acordadoCents,
        precioAjusteVehiculoSolicitado: ajuste.tipoSolicitado,
        precioAjusteVehiculoAsignado: ajuste.tipoAsignado,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      });

    logger.info("[PRECIO_VEHICULO] tarifa ajustada al vehículo real", {
      viajeId,
      de: ajuste.tipoSolicitado,
      a: ajuste.tipoAsignado,
      antesCents: acordadoCents,
      ahoraCents: ajuste.cents,
    });

    await avisarCliente(
      String(despues.uidCliente ?? despues.clienteId ?? "").trim(),
      viajeId,
      ajuste,
      acordadoCents,
    );
  },
);
