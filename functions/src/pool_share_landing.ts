/**
 * Landing HTML de giras con Open Graph server-side (Facebook, WhatsApp, Instagram, X).
 * Abre la app RAI Pasajero o manda a Google Play si no está instalada.
 */
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

const db = () => getFirestore();
const HOST = "https://flygo-rd.web.app";
const PLAY = "https://play.google.com/store/apps/details?id=com.flygo.rd2";
const DEFAULT_OG = `${HOST}/pool/rai-share-card.png`;

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return 0;
}

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function fechaFmt(iso: string | null): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("es-DO", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

async function loadPool(poolId: string): Promise<AnyMap | null> {
  const snap = await db().collection("viajes_pool").doc(poolId).get();
  if (!snap.exists) return null;
  const d = (snap.data() ?? {}) as AnyMap;
  const estado = str(d.estado).toLowerCase();
  if (estado === "cancelado" || estado === "cancelado_por_admin") return null;
  return d;
}

function buildHtml(args: {
  poolId: string;
  title: string;
  description: string;
  ogImage: string;
  route: string;
  fecha: string;
  precio: number;
  cupos: number;
  bannerUrl: string;
}): string {
  const { poolId, title, description, ogImage, route, fecha, precio, cupos, bannerUrl } = args;
  const pageUrl = `${HOST}/pool?id=${encodeURIComponent(poolId)}`;
  const appScheme = `raidriver://pool?id=${encodeURIComponent(poolId)}`;
  const intentUrl =
    `intent://pool?id=${encodeURIComponent(poolId)}` +
    `#Intent;scheme=raidriver;package=com.flygo.rd2;S.browser_fallback_url=${encodeURIComponent(PLAY)};end`;

  const heroImg = bannerUrl || ogImage;

  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${esc(title)}</title>
  <meta name="description" content="${esc(description)}" />
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="RAI Driver" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:image" content="${esc(ogImage)}" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:url" content="${esc(pageUrl)}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  <meta name="twitter:image" content="${esc(ogImage)}" />
  <meta property="al:android:url" content="${esc(appScheme)}" />
  <meta property="al:android:package" content="com.flygo.rd2" />
  <meta property="al:android:app_name" content="RAI Driver" />
  <meta property="al:web:url" content="${esc(pageUrl)}" />
  <link rel="canonical" href="${esc(pageUrl)}" />
  <style>
    body{margin:0;font-family:system-ui,sans-serif;background:#071018;color:#f8fafc;min-height:100vh}
    .wrap{max-width:440px;margin:0 auto;padding:20px 16px 32px}
    .card{background:rgba(17,24,39,.94);border-radius:20px;overflow:hidden;border:1px solid rgba(0,201,167,.35)}
    img.hero{width:100%;max-height:220px;object-fit:cover;display:block}
    .body{padding:18px 16px 20px}
    h1{margin:0 0 8px;font-size:1.35rem}
    .route{font-weight:800;color:#5bc0be;margin:0 0 12px}
    .meta{color:#94a3b8;font-size:.94rem;line-height:1.5}
    a.btn{display:block;margin-top:12px;padding:14px;text-align:center;font-weight:800;text-decoration:none;border-radius:12px}
    .primary{background:linear-gradient(135deg,#ff7a45,#00c9a7);color:#fff}
    .secondary{background:rgba(127,127,127,.15);color:#f8fafc;border:1px solid rgba(0,201,167,.35)}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      ${bannerUrl ? `<img class="hero" src="${esc(bannerUrl)}" alt="Gira" />` : ""}
      <div class="body">
        <h1>${esc(title)}</h1>
        <p class="route">${esc(route)}</p>
        <p class="meta">
          Salida: ${esc(fecha)}<br>
          Precio: RD$ ${precio.toFixed(0)} por asiento<br>
          Cupos disponibles: ${cupos}
        </p>
        <a id="openApp" class="btn primary" href="${esc(intentUrl)}">Abrir en RAI Pasajero</a>
        <a class="btn secondary" href="${PLAY}">Descargar en Google Play</a>
      </div>
    </div>
  </div>
  <script>
    (function(){
      var isAndroid = /Android/i.test(navigator.userAgent);
      var intent = ${JSON.stringify(intentUrl)};
      var scheme = ${JSON.stringify(appScheme)};
      if (isAndroid) {
        window.location.href = intent;
      } else {
        document.getElementById('openApp').href = scheme;
      }
    })();
  </script>
</body>
</html>`;
}

export const poolShareLanding = onRequest(
  { cors: true, invoker: "public" },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.status(405).send("Method not allowed");
      return;
    }

    const poolId = str(req.query.id ?? req.query.poolId);
    const canonicalUrl = poolId
      ? `${HOST}/pool?id=${encodeURIComponent(poolId)}`
      : `${HOST}/pool`;

    if (!poolId) {
      const html = buildHtml({
        poolId: "",
        title: "Giras por cupos — RAI Pasajero",
        description: "Reservá excursiones y viajes en grupo en RAI Pasajero.",
        ogImage: DEFAULT_OG,
        route: "RAI Driver",
        fecha: "—",
        precio: 0,
        cupos: 0,
        bannerUrl: "",
      });
      res.set("Cache-Control", "public, max-age=300");
      res.status(200).send(html);
      return;
    }

    try {
      const d = await loadPool(poolId);
      if (!d) {
        res.redirect(302, `${HOST}/pool?id=${encodeURIComponent(poolId)}`);
        return;
      }

      const cap = Math.max(0, Math.floor(num(d.capacidad)));
      const occ = Math.max(0, Math.floor(num(d.asientosReservados)));
      const left = Math.max(0, cap - occ);
      const precio = num(d.precioPorAsiento);
      const origen = str(d.origenTown) || "Origen";
      const destino = str(d.destino) || "Destino";
      const route = `${origen} → ${destino}`;
      const badge = str(d.servicioBadge);
      const agencia = str(d.agenciaNombre) || str(d.taxistaNombre) || "Gira RAI";
      const title = badge || `${agencia} · cupos RAI`;
      const fechaRaw = d.fechaSalida;
      let fechaIso: string | null = null;
      if (fechaRaw instanceof Timestamp) fechaIso = fechaRaw.toDate().toISOString();
      const fecha = fechaFmt(fechaIso);
      const description = `${route} · RD$ ${precio.toFixed(0)} por asiento · ${left} cupos · ${fecha}`;
      const bannerUrl = str(d.bannerUrl);
      const ogImage = bannerUrl && bannerUrl.startsWith("http") ? bannerUrl : DEFAULT_OG;

      const html = buildHtml({
        poolId,
        title,
        description,
        ogImage,
        route,
        fecha,
        precio,
        cupos: left,
        bannerUrl,
      });

      res.set("Cache-Control", "public, max-age=120");
      res.set("Link", `<${canonicalUrl}>; rel="canonical"`);
      if (req.method === "HEAD") {
        res.status(200).end();
        return;
      }
      res.status(200).send(html);
    } catch (e) {
      logger.error("[poolShareLanding]", poolId, e);
      res.redirect(302, `${HOST}/pool?id=${encodeURIComponent(poolId)}`);
    }
  },
);
