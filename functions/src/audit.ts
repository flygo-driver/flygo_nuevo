import { FieldValue, getFirestore } from "firebase-admin/firestore";

type AnyMap = Record<string, unknown>;

export type AdminAuditParams = {
  action: string;
  actorUid: string;
  resourceType?: string;
  resourceId?: string;
  metadata?: AnyMap;
};

/**
 * Registro best-effort en `admin_audit`. No lanza: errores solo a Cloud Logging.
 * No bloquea la respuesta de la callable (fire-and-forget).
 */
export function logAdminAudit(params: AdminAuditParams): void {
  void (async () => {
    try {
      await getFirestore().collection("admin_audit").add({
        ts: FieldValue.serverTimestamp(),
        outcome: "success",
        action: params.action,
        actorUid: params.actorUid,
        resourceType: params.resourceType ?? null,
        resourceId: params.resourceId ?? null,
        metadata: params.metadata ?? {},
      });
    } catch (e) {
      console.error("[logAdminAudit]", params.action, e);
    }
  })();
}
