#!/usr/bin/env node
/**
 * ONE-OFF — Ejecutar solo manualmente para normalizar rol "administrador" -> "admin".
 *
 * Modo A (prioritario): usa GOOGLE_APPLICATION_CREDENTIALS si está definido.
 * Modo B (automático): usa token del Firebase CLI local (~/.config/configstore/firebase-tools.json).
 *
 * Uso:
 *   cd functions
 *   node scripts/migrate-administrator-to-admin-once.mjs
 *
 * Opcional:
 *   set FIREBASE_PROJECT_ID=flygo-rd
 *   node scripts/migrate-administrator-to-admin-once.mjs
 */
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";

import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";
const baseUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function hasJsonCredentials() {
  const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  return !!(p && p.trim());
}

async function patchWithAdminSdk(collName) {
  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();
  const snap = await db.collection(collName).where("rol", "==", "administrador").get();
  if (snap.empty) {
    console.log(`[${collName}] sin documentos rol==administrador`);
    return 0;
  }
  let count = 0;
  for (const doc of snap.docs) {
    await doc.ref.update({
      rol: "admin",
      updatedAt: FieldValue.serverTimestamp(),
    });
    count++;
    console.log(`[${collName}] ${doc.id} -> admin`);
  }
  return count;
}

async function loadCliAccessToken() {
  const cfgPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
  const raw = await fs.readFile(cfgPath, "utf8");
  const cfg = JSON.parse(raw);
  const token = cfg?.tokens?.access_token;
  if (!token || typeof token !== "string") {
    throw new Error(`No se encontró access_token en ${cfgPath}. Ejecuta 'firebase login' y reintenta.`);
  }
  return token;
}

async function runQueryAdministrador(collName, token) {
  const res = await fetch(`${baseUrl}:runQuery`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: collName }],
        where: {
          fieldFilter: {
            field: { fieldPath: "rol" },
            op: "EQUAL",
            value: { stringValue: "administrador" },
          },
        },
      },
    }),
  });
  if (!res.ok) {
    throw new Error(`[${collName}] runQuery HTTP ${res.status}: ${await res.text()}`);
  }
  const rows = await res.json();
  return rows
    .map((r) => r?.document?.name)
    .filter((n) => typeof n === "string" && n.length > 0);
}

async function patchDocByName(docName, token) {
  const qs = new URLSearchParams();
  qs.append("updateMask.fieldPaths", "rol");
  qs.append("updateMask.fieldPaths", "updatedAt");
  const res = await fetch(`https://firestore.googleapis.com/v1/${docName}?${qs.toString()}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        rol: { stringValue: "admin" },
        updatedAt: { timestampValue: new Date().toISOString() },
      },
    }),
  });
  if (!res.ok) {
    throw new Error(`PATCH ${docName} HTTP ${res.status}: ${await res.text()}`);
  }
}

async function patchWithCliToken(collName, token) {
  const docNames = await runQueryAdministrador(collName, token);
  if (docNames.length === 0) {
    console.log(`[${collName}] sin documentos rol==administrador`);
    return 0;
  }
  let count = 0;
  for (const name of docNames) {
    await patchDocByName(name, token);
    const id = name.split("/").pop();
    console.log(`[${collName}] ${id} -> admin`);
    count++;
  }
  return count;
}

async function main() {
  let u = 0;
  let r = 0;

  if (hasJsonCredentials()) {
    console.log("Modo credenciales JSON/ADC detectado.");
    u = await patchWithAdminSdk("usuarios");
    r = await patchWithAdminSdk("roles");
  } else {
    console.log("Modo Firebase CLI (sin JSON manual).");
    const token = await loadCliAccessToken();
    u = await patchWithCliToken("usuarios", token);
    r = await patchWithCliToken("roles", token);
  }

  console.log(`Listo. usuarios=${u}, roles=${r}, total=${u + r}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
