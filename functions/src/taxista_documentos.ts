import { randomUUID } from "node:crypto";

import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const TIPOS_VALIDOS = new Set([
  "licencia",
  "matricula",
  "seguro",
  "fotoVehiculo",
  "placa",
]);

const MAX_BYTES = 10 * 1024 * 1024;

/**
 * Subida de documentos taxista vía Admin SDK.
 * Evita fallos `firebase_storage/unknown` en APK firmado localmente (distinto SHA que Play).
 * No sustituye reglas Storage: el archivo queda en documentos_taxista/{uid}/...
 */
export const subirDocumentoTaxistaSeguro = onCall(
  { timeoutSeconds: 120, memory: "256MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    }

    const tipo = String(request.data?.tipo ?? "").trim();
    if (!TIPOS_VALIDOS.has(tipo)) {
      throw new HttpsError("invalid-argument", "Tipo de documento inválido.");
    }

    const imageBase64 = String(request.data?.imageBase64 ?? "").trim();
    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "Falta la imagen.");
    }

    let buffer: Buffer;
    try {
      buffer = Buffer.from(imageBase64, "base64");
    } catch {
      throw new HttpsError("invalid-argument", "Imagen inválida (base64).");
    }

    if (buffer.length === 0 || buffer.length > MAX_BYTES) {
      throw new HttpsError(
        "invalid-argument",
        "La imagen debe ser mayor que 0 y menor que 10 MB.",
      );
    }

    const db = getFirestore();
    const userSnap = await db.collection("usuarios").doc(uid).get();
    const rol = String(userSnap.data()?.rol ?? "").trim().toLowerCase();
    if (rol !== "taxista" && rol !== "driver") {
      throw new HttpsError("permission-denied", "Solo conductores pueden subir documentos.");
    }

    const ts = Date.now();
    const storagePath = `documentos_taxista/${uid}/${tipo}_${ts}.jpg`;
    const bucket = getStorage().bucket();
    const file = bucket.file(storagePath);
    const downloadToken = randomUUID();

    await file.save(buffer, {
      resumable: false,
      metadata: {
        contentType: "image/jpeg",
        metadata: {
          uid,
          tipo,
          firebaseStorageDownloadTokens: downloadToken,
        },
      },
    });

    const encodedPath = encodeURIComponent(storagePath);
    const url =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}` +
      `?alt=media&token=${downloadToken}`;

    return { ok: true, url, storagePath, tipo };
  },
);
