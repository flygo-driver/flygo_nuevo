/**
 * Publica config/tarifas_tramos usando gcloud auth (sin ADC).
 * Requisito: gcloud auth login (ventasopenask@gmail.com)
 * Uso: node scripts/seed_tarifas_tramos_gcloud.mjs
 */
import { execSync } from "node:child_process";

const projectId = "flygo-rd";
const docPath = "config/tarifas_tramos";

const data = {
  activo: true,
  tramosKm: [40, 80, 140],
  minimoLargaDistanciaRd: 1200,
  promoAplicaSoloTramoLocal: true,
  distanciaMaximaCotizableKm: 800,
  version: 1,
  porVehiculo: {
    Carro: { porKmPorTramo: [22, 40, 53, 63] },
    Jeepeta: { porKmPorTramo: [30, 50, 65, 80] },
    Minivan: { porKmPorTramo: [32, 52, 68, 82] },
    "Minibús": { porKmPorTramo: [35, 55, 70, 85] },
    AutobusGuagua: { porKmPorTramo: [45, 65, 80, 95] },
    motor: { porKmPorTramo: [12, 22, 35, 42] },
    carro: { porKmPorTramo: [22, 40, 53, 63] },
    jeepeta: { porKmPorTramo: [30, 50, 65, 80] },
    minivan: { porKmPorTramo: [35, 55, 70, 85] },
    bus: { porKmPorTramo: [45, 65, 80, 95] },
  },
};

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === "boolean") return { booleanValue: val };
  if (typeof val === "number") {
    return Number.isInteger(val)
      ? { integerValue: String(val) }
      : { doubleValue: val };
  }
  if (typeof val === "string") return { stringValue: val };
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(toFirestoreValue) } };
  }
  if (typeof val === "object") {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  throw new Error(`Tipo no soportado: ${typeof val}`);
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    fields[k] = toFirestoreValue(v);
  }
  return fields;
}

const token = execSync("gcloud auth print-access-token", {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
}).trim();

const url =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  `/databases/(default)/documents/${docPath}?updateMask.fieldPaths=` +
  Object.keys(data)
    .map((k) => encodeURIComponent(k))
    .join("&updateMask.fieldPaths=");

const res = await fetch(url, {
  method: "PATCH",
  headers: {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ fields: toFirestoreFields(data) }),
});

const body = await res.text();
if (!res.ok) {
  console.error("Error HTTP", res.status, body);
  process.exit(1);
}

console.log("OK config/tarifas_tramos activo=true tramosKm=[40,80,140]");
