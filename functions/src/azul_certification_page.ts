/** Páginas informativas cuando el banco abre endpoints en el navegador (certificación). */

export type AzulCertPageInput = {
  titulo: string;
  endpoint: string;
  uso: string;
  metodo: string;
  nota: string;
  demoUrl?: string;
  estado?: "ok" | "info";
};

export function buildAzulCertificationInfoHtml(input: AzulCertPageInput): string {
  const color = input.estado === "ok" ? "#7ee787" : "#58a6ff";
  const demo = input.demoUrl
    ? `<p style="margin-top:20px"><a href="${input.demoUrl}">Probar demo sandbox →</a></p>`
    : "";
  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${input.titulo} — RAI DRIVER</title>
  <style>
    body{font-family:system-ui,sans-serif;background:#0d1117;color:#e6edf3;margin:0;padding:24px;line-height:1.5}
    main{max-width:560px;margin:40px auto}
    h1{font-size:1.2rem;color:${color};margin:0 0 12px}
    p{color:#8b949e;margin:0 0 10px;font-size:0.92rem}
    .box{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:16px;margin:16px 0}
    code{font-size:0.82rem;word-break:break-all;color:#e6edf3}
    .ok{color:#7ee787;font-weight:600}
    a{color:#58a6ff}
  </style>
</head>
<body>
  <main>
    <h1>✓ ${input.titulo}</h1>
    <p class="ok">Endpoint activo y desplegado (OPEN ASK SERVICE SRL · RAI DRIVER).</p>
    <div class="box">
      <p><strong>URL:</strong><br /><code>${input.endpoint}</code></p>
      <p><strong>Método:</strong> ${input.metodo}</p>
      <p><strong>Uso:</strong> ${input.uso}</p>
    </div>
    <p>${input.nota}</p>
    ${demo}
    <p style="margin-top:24px;font-size:0.8rem">
      <a href="https://flygo-rd.web.app/legal/pagos-tarjeta">Pagos con tarjeta</a> ·
      <a href="https://flygo-rd.web.app/legal/seguridad-tarjetas">Seguridad</a>
    </p>
  </main>
</body>
</html>`;
}

export const AZUL_DEMO_CERT_URL = "https://flygo-rd.web.app/azul/demo-pago";
