/**
 * Autenticación para scripts seed → Firestore (flygo-rd).
 *
 * Orden:
 *   1) firebase-admin (ADC / GOOGLE_APPLICATION_CREDENTIALS)
 *   2) gcloud auth print-access-token (OAuth válido para REST Firestore)
 *
 * El token guardado por `firebase login` NO sirve (ACCESS_TOKEN_TYPE_UNSUPPORTED).
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import os from "node:os";

const execFileAsync = promisify(execFile);

function gcloudBin() {
  return os.platform() === "win32" ? "gcloud.cmd" : "gcloud";
}

export function isCredentialError(err) {
  const msg = String(err?.message ?? err);
  return (
    msg.includes("default credentials") ||
    msg.includes("Could not load") ||
    msg.includes("Could not refresh") ||
    (msg.includes("ENOENT") && msg.includes("application_default_credentials"))
  );
}

export async function loadGcloudAccessToken() {
  try {
    const { stdout } = await execFileAsync(
      gcloudBin(),
      ["auth", "print-access-token"],
      { windowsHide: true, shell: os.platform() === "win32" },
    );
    const token = stdout.trim();
    if (token.length > 20) return token;
  } catch {
    // gcloud no instalado o sin login
  }
  return null;
}

export function toFirestoreFields(obj) {
  const fields = {};
  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === "boolean") {
      fields[key] = { booleanValue: value };
    } else if (typeof value === "string") {
      fields[key] = { stringValue: value };
    } else if (typeof value === "number") {
      fields[key] = { doubleValue: value };
    }
  }
  fields.updatedAt = { timestampValue: new Date().toISOString() };
  return fields;
}

export async function patchDocWithOAuthToken({
  projectId,
  docId,
  patch,
  token,
  collection = "config",
}) {
  const docPath = `projects/${projectId}/databases/(default)/documents/${collection}/${docId}`;
  const qs = new URLSearchParams();
  for (const key of Object.keys(patch)) {
    qs.append("updateMask.fieldPaths", key);
  }
  qs.append("updateMask.fieldPaths", "updatedAt");

  const res = await fetch(
    `https://firestore.googleapis.com/v1/${docPath}?${qs.toString()}`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields: toFirestoreFields(patch) }),
    },
  );
  if (!res.ok) {
    const body = await res.text();
    if (res.status === 401) {
      throw new Error(
        `Firestore PATCH ${docId} HTTP 401 (token inválido o expirado).\n${body}\n\n` +
          authHelpText(),
      );
    }
    throw new Error(`Firestore PATCH ${docId} HTTP ${res.status}: ${body}`);
  }
}

export function authHelpText() {
  return (
    "Autenticación requerida (elige UNA opción):\n\n" +
    "  A) gcloud auth application-default login\n" +
    "     (luego: node scripts/seed_config_lanzamiento_produccion.mjs)\n\n" +
    "  B) gcloud auth login\n" +
    "     gcloud config set project flygo-rd\n\n" +
    "  C) set GOOGLE_APPLICATION_CREDENTIALS=ruta\\service-account.json\n\n" +
    "NOTA: `firebase login` solo NO alcanza para estos scripts."
  );
}

/**
 * @param {{ projectId: string, admin: typeof import('firebase-admin'), patches: Record<string, Record<string, unknown>> }} opts
 */
export async function seedConfigDocs({ projectId, admin, patches }) {
  try {
    if (!admin.apps.length) {
      admin.initializeApp({ projectId });
    }
    const db = admin.firestore();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    for (const [docId, patch] of Object.entries(patches)) {
      await db.doc(`config/${docId}`).set({ ...patch, updatedAt: ts }, { merge: true });
    }
    console.log("Modo firebase-admin (ADC / service account).");
    return;
  } catch (e) {
    if (!isCredentialError(e)) throw e;
  }

  console.log("ADC no disponible; probando gcloud auth print-access-token…");
  const token = await loadGcloudAccessToken();
  if (!token) {
    throw new Error(authHelpText());
  }

  for (const [docId, patch] of Object.entries(patches)) {
    await patchDocWithOAuthToken({ projectId, docId, patch, token });
  }
  console.log("Modo gcloud OAuth.");
}

/**
 * Escribe un doc Firestore (merge) con ADC o gcloud OAuth.
 * @param {{ projectId: string, admin: typeof import('firebase-admin'), docPath: string, patch: Record<string, unknown> }} opts
 */
export async function seedFirestoreDoc({ projectId, admin, docPath, patch }) {
  const path = docPath.replace(/^\/+/, "").trim();
  if (!path.includes("/")) {
    throw new Error(`docPath inválido (esperado coleccion/docId): ${docPath}`);
  }

  try {
    if (!admin.apps.length) {
      admin.initializeApp({ projectId });
    }
    const db = admin.firestore();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    await db.doc(path).set({ ...patch, updatedAt: ts }, { merge: true });
    console.log("Modo firebase-admin (ADC / service account).");
    return;
  } catch (e) {
    if (!isCredentialError(e)) throw e;
  }

  console.log("ADC no disponible; probando gcloud auth print-access-token…");
  const token = await loadGcloudAccessToken();
  if (!token) {
    throw new Error(authHelpText());
  }

  const slash = path.indexOf("/");
  const collection = path.slice(0, slash);
  const docId = path.slice(slash + 1);
  await patchDocWithOAuthToken({
    projectId,
    docId,
    patch,
    token,
    collection,
  });
  console.log("Modo gcloud OAuth.");
}
