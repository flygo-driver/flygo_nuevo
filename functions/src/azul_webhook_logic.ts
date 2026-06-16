/**
 * Lógica pura webhook AZUL — dedup, orden de estados, parsing.
 */
import { createHash } from "node:crypto";

type AnyMap = Record<string, unknown>;

export type AzulPagoEstado = "pending" | "authorized" | "captured" | "refunded" | "failed";

export function normalizarEstadoAzul(raw: unknown): AzulPagoEstado | null {
  const s = String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z_]/g, "");
  if (!s) return null;
  if (s === "authorized" || s === "authorised" || s === "auth") return "authorized";
  if (s === "captured" || s === "capture" || s === "approved" || s === "success" || s === "paid") {
    return "captured";
  }
  if (s === "refunded" || s === "refund") return "refunded";
  if (s === "failed" || s === "declined" || s === "error" || s === "rejected" || s === "denied") {
    return "failed";
  }
  if (s === "pending") return "pending";
  return null;
}

export function extraerAzulOrderId(body: AnyMap): string {
  return String(
    body.azulOrderId ??
      body.OrderNumber ??
      body.orderNumber ??
      body.orderId ??
      body.OrderId ??
      "",
  ).trim();
}

export function extraerAzulEventId(body: AnyMap, azulOrderId: string, estado: AzulPagoEstado | null): string {
  const explicit = String(body.eventId ?? body.EventId ?? body.webhookId ?? body.id ?? "").trim();
  if (explicit) return sanitizeEventId(explicit);
  const statusRaw = String(body.status ?? body.Status ?? estado ?? "").trim();
  const payload = JSON.stringify({
    order: azulOrderId,
    status: statusRaw,
    amount: body.amount ?? body.Amount ?? null,
    rrn: body.rrn ?? body.RRN ?? null,
  });
  const hash = createHash("sha256").update(payload).digest("hex").slice(0, 28);
  return `derived_${azulOrderId || "noorder"}_${hash}`;
}

export function sanitizeEventId(raw: string): string {
  return raw.replace(/[^a-zA-Z0-9._-]/g, "").slice(0, 120);
}

/**
 * Decide si aplicar transición de estado en pagos_azul.
 * Ignora duplicados y retrocesos inválidos (p. ej. authorized después de captured).
 */
export function debeAplicarTransicionAzul(
  estadoActual: unknown,
  estadoNuevo: AzulPagoEstado,
): { aplicar: boolean; motivo: string } {
  const cur = normalizarEstadoAzul(estadoActual) ?? "pending";

  if (cur === estadoNuevo) {
    return { aplicar: false, motivo: "duplicado_mismo_estado" };
  }

  if (estadoNuevo === "failed") {
    if (cur === "captured" || cur === "refunded") {
      return { aplicar: false, motivo: "failed_ignorado_post_captured" };
    }
    return { aplicar: true, motivo: "failed" };
  }

  if (estadoNuevo === "refunded") {
    if (cur === "refunded") return { aplicar: false, motivo: "duplicado_refunded" };
    if (cur === "captured" || cur === "authorized") {
      return { aplicar: true, motivo: "refunded" };
    }
    return { aplicar: false, motivo: "refunded_fuera_de_orden" };
  }

  if (estadoNuevo === "captured") {
    if (cur === "captured" || cur === "refunded") {
      return { aplicar: false, motivo: "duplicado_o_final" };
    }
    return { aplicar: true, motivo: "captured" };
  }

  if (estadoNuevo === "authorized") {
    if (cur === "authorized" || cur === "captured" || cur === "refunded") {
      return { aplicar: false, motivo: "authorized_duplicado_o_tarde" };
    }
    return { aplicar: true, motivo: "authorized" };
  }

  return { aplicar: false, motivo: "estado_no_soportado" };
}

/** Order id estable por viaje (evita duplicados en retries de createSession). */
export function buildAzulOrderIdDeterministic(viajeId: string, montoCents: number, useStub: boolean): string {
  const slug = viajeId.replace(/[^a-zA-Z0-9]/g, "").slice(0, 24) || "VIAJE";
  if (useStub) return `STUB-${slug}`;
  const hash = createHash("sha256")
    .update(`${viajeId}|${montoCents}`)
    .digest("hex")
    .slice(0, 16)
    .toUpperCase();
  return `AZUL-${slug}-${hash}`;
}

export function sesionAzulReutilizable(estado: unknown): boolean {
  const raw = String(estado ?? "").trim().toLowerCase();
  if (raw === "pending_configuration") return true;
  const e = normalizarEstadoAzul(estado);
  return e === "pending" || e === "authorized";
}
