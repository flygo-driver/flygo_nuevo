import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { logAdminAudit } from "./audit.js";
import { sendMail } from "./mail.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  return r === "administrador" ? "admin" : r;
}

async function getAdminEmails(): Promise<string[]> {
  // Preferimos usuarios.rol; si usan "administrador" también cuenta.
  const snap = await db().collection("usuarios").where("rol", "in", ["admin", "administrador"]).limit(200).get();
  const out = new Set<string>();
  for (const d of snap.docs) {
    const data = (d.data() ?? {}) as AnyMap;
    const email = String(data.email ?? "").trim();
    if (email.includes("@")) out.add(email);
  }
  return Array.from(out);
}

async function countQuery(q: FirebaseFirestore.Query<FirebaseFirestore.DocumentData>): Promise<number> {
  // Firestore aggregate count (no reads).
  const agg = await q.count().get();
  return agg.data().count;
}

function fmtPct(n: number): string {
  if (!Number.isFinite(n)) return "0.0%";
  return `${(n * 100).toFixed(1)}%`;
}

function shortIso(d: Date): string {
  return d.toISOString().replace("T", " ").slice(0, 16) + "Z";
}

export const proactiveAdminAlertsHourly = onSchedule("every 60 minutes", async () => {
  const now = new Date();
  const from1h = new Date(now.getTime() - 60 * 60 * 1000);
  const th30d = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

  const from1hTs = Timestamp.fromDate(from1h);
  const nowTs = Timestamp.fromDate(now);
  const th30dTs = Timestamp.fromDate(th30d);

  // 1) Cancelaciones última hora (aprox por updatedAt)
  const viajesBase = db().collection("viajes").where("updatedAt", ">=", from1hTs).where("updatedAt", "<=", nowTs);
  const viajesTotal = await countQuery(viajesBase);

  const canceladoQ = viajesBase.where("estado", "in", ["cancelado", "canceled"]);
  const completadoQ = viajesBase.where("estado", "in", ["completado", "completed"]);
  const [cancelados, completados] = await Promise.all([
    countQuery(canceladoQ),
    countQuery(completadoQ),
  ]);
  const rateCancel = viajesTotal > 0 ? cancelados / viajesTotal : 0;

  // 2) Bloqueos nuevos por pago semanal (usuarios.tienePagoPendiente==true) última hora
  const bloqueosNuevos = await countQuery(
    db()
      .collection("usuarios")
      .where("tienePagoPendiente", "==", true)
      .where("updatedAt", ">=", from1hTs)
      .where("updatedAt", "<=", nowTs),
  );

  // 3) Comisiones pendientes >30 días (heurística: billetera con comisionPendiente>0 y updatedAt <= th30d)
  // Nota: si el proyecto no tiene índice para esto, capturamos error y lo reportamos.
  let comisionesPendientes30d: number | null = null;
  let comisionesPendientes30dErr: string | null = null;
  try {
    comisionesPendientes30d = await countQuery(
      db()
        .collection("billeteras_taxista")
        .where("comisionPendiente", ">", 0)
        .where("updatedAt", "<=", th30dTs),
    );
  } catch (e) {
    comisionesPendientes30dErr = String(e);
  }

  // Admin recipients (opcional): si no hay, se envía al grupo ALERTS_TO.
  const adminEmails = await getAdminEmails();

  const subject = `RAI Admin Alerts (1h) — ${shortIso(now)}`;
  const lines: string[] = [];
  lines.push("Alertas proactivas (cada 1 hora)");
  lines.push(`Ventana: ${shortIso(from1h)} → ${shortIso(now)}`);
  lines.push("");
  lines.push("1) Viajes (última hora)");
  lines.push(`- total: ${viajesTotal}`);
  lines.push(`- completados: ${completados}`);
  lines.push(`- cancelados: ${cancelados} (${fmtPct(rateCancel)})`);
  lines.push("");
  lines.push("2) Bloqueos nuevos (tienePagoPendiente=true, última hora)");
  lines.push(`- bloqueos nuevos: ${bloqueosNuevos}`);
  lines.push("");
  lines.push("3) Comisiones pendientes >30 días (heurística)");
  if (comisionesPendientes30dErr) {
    lines.push(`- error consultando: ${comisionesPendientes30dErr}`);
  } else {
    lines.push(`- taxistas detectados: ${comisionesPendientes30d ?? 0}`);
  }
  lines.push("");
  lines.push("Admin emails detectados (usuarios.rol in [admin, administrador]):");
  lines.push(adminEmails.length ? adminEmails.join(", ") : "(ninguno con email; se usará ALERTS_TO)");

  // Enviar (best-effort): si no hay SMTP, queda solo en logs.
  await sendMail({ subject, text: lines.join("\n") });

  // Persistir alerta in-app para panel ADM (tiempo real).
  const severidad =
    rateCancel >= 0.35 || (comisionesPendientes30d ?? 0) >= 25
      ? "critical"
      : cancelados > 0 || bloqueosNuevos > 0
        ? "warning"
        : "info";

  await db()
    .collection("admin_alertas")
    .add({
      tipo: "resumen_horario",
      titulo: `Resumen operativo (1h) — ${shortIso(now)}`,
      mensaje: lines.slice(2).join("\n"),
      severidad,
      leida: false,
      metadata: {
        viajesTotal,
        completados,
        cancelados,
        cancelRate: Number(rateCancel.toFixed(4)),
        bloqueosNuevos,
        comisionesPendientes30d,
        comisionesPendientes30dErr,
      },
      windowFrom: from1h.toISOString(),
      windowTo: now.toISOString(),
      createdAt: FieldValue.serverTimestamp(),
    });

  // Alertas puntuales si superan umbrales.
  if (rateCancel >= 0.25 && viajesTotal >= 5) {
    await db()
      .collection("admin_alertas")
      .add({
        tipo: "cancelaciones_alta",
        titulo: "Tasa de cancelación elevada",
        mensaje: `${cancelados}/${viajesTotal} viajes cancelados en la última hora (${fmtPct(rateCancel)}).`,
        severidad: rateCancel >= 0.35 ? "critical" : "warning",
        leida: false,
        metadata: { cancelados, viajesTotal, cancelRate: rateCancel },
        createdAt: FieldValue.serverTimestamp(),
      });
  }

  if (bloqueosNuevos > 0) {
    await db()
      .collection("admin_alertas")
      .add({
        tipo: "bloqueos_nuevos",
        titulo: "Nuevos bloqueos por comisión",
        mensaje: `${bloqueosNuevos} taxista(s) bloqueados por pago pendiente en la última hora.`,
        severidad: bloqueosNuevos >= 5 ? "critical" : "warning",
        leida: false,
        metadata: { bloqueosNuevos },
        createdAt: FieldValue.serverTimestamp(),
      });
  }

  logAdminAudit({
    action: "proactive_admin_alerts_hourly",
    actorUid: "system",
    resourceType: "alerts",
    resourceId: "hourly",
    metadata: {
      windowFrom: from1h.toISOString(),
      windowTo: now.toISOString(),
      viajesTotal,
      completados,
      cancelados,
      cancelRate: Number(rateCancel.toFixed(4)),
      bloqueosNuevos,
      comisionesPendientes30d,
      comisionesPendientes30dErr,
      adminEmailsCount: adminEmails.length,
    },
  });
});

