/**
 * Feriados oficiales República Dominicana (servidor).
 * El encargado solo agrega feriados extra en plantilla.diasPausaFeriado.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function clave(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function soloDia(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function domingoPascua(year: number): Date {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(year, month - 1, day);
}

function observarSiAplica(d: Date, trasladar: boolean): Date {
  if (!trasladar) return soloDia(d);
  switch (d.getDay()) {
    case 2:
      return soloDia(new Date(d.getTime() - 86400000));
    case 3:
      return soloDia(new Date(d.getTime() - 2 * 86400000));
    case 4:
      return soloDia(new Date(d.getTime() + 4 * 86400000));
    default:
      return soloDia(d);
  }
}

/** Feriados oficiales del año (clave yyyy-MM-dd → nombre). */
export function feriadosOficialesRdMap(
  year: number,
  trasladarALunes = true,
): Map<string, string> {
  const pascua = domingoPascua(year);
  const viernesSanto = new Date(pascua.getTime() - 2 * 86400000);
  const corpus = new Date(pascua.getTime() + 60 * 86400000);
  const f = (m: number, d: number) => new Date(year, m - 1, d);

  const raw: { fecha: Date; nombre: string; traslada: boolean }[] = [
    { fecha: f(1, 1), nombre: "Año Nuevo", traslada: false },
    { fecha: f(1, 6), nombre: "Día de Reyes", traslada: true },
    { fecha: f(1, 21), nombre: "Día de la Altagracia", traslada: false },
    { fecha: f(1, 26), nombre: "Día de Duarte", traslada: true },
    { fecha: f(2, 27), nombre: "Independencia Nacional", traslada: false },
    { fecha: viernesSanto, nombre: "Viernes Santo", traslada: false },
    { fecha: f(5, 1), nombre: "Día del Trabajo", traslada: false },
    { fecha: corpus, nombre: "Corpus Christi", traslada: false },
    { fecha: f(8, 16), nombre: "Día de la Restauración", traslada: false },
    { fecha: f(9, 24), nombre: "Día de las Mercedes", traslada: false },
    { fecha: f(11, 6), nombre: "Día de la Constitución", traslada: true },
    { fecha: f(12, 25), nombre: "Navidad", traslada: false },
  ];

  const out = new Map<string, string>();
  for (const item of raw) {
    const obs = observarSiAplica(item.fecha, item.traslada && trasladarALunes);
    out.set(clave(obs), item.nombre);
  }
  return out;
}

export function esFeriadoNacionalRd(
  keyHoy: string,
  year = new Date().getFullYear(),
): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(keyHoy)) return false;
  return feriadosOficialesRdMap(year).has(keyHoy);
}

/** Feriado nacional O feriado extra de la plantilla/empresa. */
export function esDiaNoLaborableCorporativo(args: {
  keyHoy: string;
  feriadosPlantilla?: string[];
  feriadosEmpresa?: string[];
}): { pausa: boolean; motivo: string } {
  const y = Number(args.keyHoy.slice(0, 4)) || new Date().getFullYear();
  const nacional = feriadosOficialesRdMap(y).get(args.keyHoy);
  if (nacional) {
    return { pausa: true, motivo: `Feriado nacional: ${nacional}` };
  }
  const extra = new Set([
  ...(args.feriadosPlantilla ?? []).map(str),
  ...(args.feriadosEmpresa ?? []).map(str),
  ]);
  if (extra.has(args.keyHoy)) {
    return { pausa: true, motivo: "Feriado / pausa de la empresa" };
  }
  return { pausa: false, motivo: "" };
}

/** Admin: publica feriados oficiales en corporativo_feriados/{año}. */
export const adminPublicarFeriadosRdAno = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const db = getFirestore();
  const adminSnap = await db.collection("usuarios").doc(request.auth.uid).get();
  if (String(adminSnap.data()?.rol ?? "").toLowerCase() !== "admin") {
    throw new HttpsError("permission-denied", "Solo administración RAI");
  }
  const year = Math.trunc(Number(request.data?.year) || new Date().getFullYear());
  const map = feriadosOficialesRdMap(year);
  const feriados: AnyMap[] = [];
  for (const [fecha, nombre] of map.entries()) {
    feriados.push({ fecha, nombre, oficial: true });
  }
  await db.collection("corporativo_feriados").doc(String(year)).set(
    {
      year,
      pais: "DO",
      feriados,
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  logger.info("adminPublicarFeriadosRdAno", { year, count: feriados.length });
  return { ok: true, year, count: feriados.length };
});
