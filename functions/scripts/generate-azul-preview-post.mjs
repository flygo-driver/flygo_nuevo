/**
 * Genera public/azul/preview-post/index.html — vista previa del POST AZUL para el comercio.
 * Uso: npm run preview:azul-post  (desde functions/)
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  azulPaymentPageActionUrl,
  buildAzulPaymentFormFields,
} from "../lib/azul_payment_page.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outPath = join(__dirname, "../../public/azul/preview-post/index.html");

const DEMO_AUTH_KEY = process.env.AZUL_AUTH_KEY?.trim() || "demo-auth-key-solo-preview";
const MERCHANT_ID = process.env.AZUL_STORE_ID?.trim() || "39038540035";
const MERCHANT_NAME =
  process.env.AZUL_MERCHANT_NAME?.trim() || "OPEN ASK SERVICE SRL";
const actionUrl = azulPaymentPageActionUrl("sandbox");

const fields = buildAzulPaymentFormFields(
  {
    merchantId: MERCHANT_ID,
    merchantName: MERCHANT_NAME,
    orderNumber: "RAI-DEMO-1234",
    amountCents: 15000,
    itbisCents: 2057,
    approvedUrl: "",
    declinedUrl: "",
    cancelUrl: "",
    customField1Value: "viaje_demo_staging",
  },
  DEMO_AUTH_KEY,
);

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const hiddenInputs = Object.entries(fields)
  .map(
    ([name, value]) =>
      `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(String(value))}" />`,
  )
  .join("\n      ");

const fieldRows = Object.entries(fields)
  .map(
    ([name, value]) =>
      `<tr><th scope="row">${escapeHtml(name)}</th><td><code>${escapeHtml(String(value))}</code></td></tr>`,
  )
  .join("\n        ");

const html = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Vista previa POST AZUL — RAI DRIVER</title>
  <meta name="robots" content="noindex" />
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1117;
      --panel: #161b22;
      --border: #30363d;
      --text: #e6edf3;
      --muted: #8b949e;
      --ok: #7ee787;
      --warn: #f0883e;
      --link: #58a6ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.45;
    }
    main {
      max-width: 760px;
      margin: 0 auto;
      padding: 24px 20px 40px;
    }
    h1 {
      font-size: 1.25rem;
      margin: 0 0 8px;
      color: var(--ok);
    }
    .banner {
      background: var(--panel);
      border: 1px solid var(--border);
      border-left: 4px solid var(--warn);
      border-radius: 8px;
      padding: 14px 16px;
      margin: 16px 0 20px;
      font-size: 0.92rem;
    }
    .banner strong { color: var(--warn); }
    p { margin: 0 0 12px; color: var(--muted); font-size: 0.92rem; }
    .action {
      margin: 12px 0 20px;
      padding: 10px 12px;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      font-size: 0.85rem;
      word-break: break-all;
    }
    .action span { color: var(--muted); }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.82rem;
      margin: 12px 0 24px;
    }
    th, td {
      border: 1px solid var(--border);
      padding: 8px 10px;
      text-align: left;
      vertical-align: top;
    }
    th {
      width: 34%;
      background: var(--panel);
      color: var(--muted);
      font-weight: 600;
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 0.78rem;
      word-break: break-all;
    }
    button {
      appearance: none;
      border: 1px solid #238636;
      background: #238636;
      color: #fff;
      border-radius: 8px;
      padding: 12px 18px;
      font-size: 0.95rem;
      font-weight: 600;
      cursor: pointer;
    }
    button:hover { background: #2ea043; }
    .foot {
      margin-top: 20px;
      font-size: 0.8rem;
      color: var(--muted);
    }
    a { color: var(--link); }
  </style>
</head>
<body>
  <main>
    <h1>RAI DRIVER · Vista previa Payment Page AZUL</h1>
    <div class="banner">
      <strong>Solo demostración.</strong> Mismos campos y <code>AuthHash</code> que genera el servidor en producción
      (<code>azulPaymentLaunch</code>). La clave es de ejemplo; AZUL sandbox rechazará el hash hasta recibir
      <code>MerchantId</code> + <code>AuthKey</code> reales del banco.
    </div>
    <p>Ejemplo: viaje RD$150.00 (15&nbsp;000 centavos) + ITBIS. Orden <code>${escapeHtml(fields.OrderNumber)}</code>.</p>
    <div class="action">
      <span>POST → </span><code>${escapeHtml(actionUrl)}</code>
    </div>
    <table>
      <thead>
        <tr><th colspan="2">Campos del formulario (method=&quot;post&quot;)</th></tr>
      </thead>
      <tbody>
        ${fieldRows}
      </tbody>
    </table>
    <form id="azulPay" method="post" action="${escapeHtml(actionUrl)}">
      ${hiddenInputs}
      <button type="submit">Enviar POST a AZUL sandbox</button>
    </form>
    <p class="foot">
      En la app real no se muestra esta página al usuario: el navegador abre
      <code>azulPaymentLaunch?order=…</code>, que devuelve HTML con auto-envío (como el manual del banco).
      Regenerar: <code>cd functions &amp;&amp; npm run preview:azul-post</code>.
      · <a href="/azul/resultado">Página de resultado</a>
    </p>
  </main>
</body>
</html>
`;

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, html, "utf8");
console.log(`OK: ${outPath}`);
