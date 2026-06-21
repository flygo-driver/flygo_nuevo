/**
 * Favicon web = logo RAI en la pestaña del navegador (NO el AppBar de Flutter).
 * 1) flutter_launcher_icons → favicon.png ~3–5 KB (letra R, no logo Flutter ~630 B).
 * 2) Incrusta el PNG en web/index.html (funciona en flygo-rd.web.app Y en flutter run -d chrome).
 */
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const webDir = path.join(root, "web");
const iconsDir = path.join(webDir, "icons");
const indexPath = path.join(webDir, "index.html");

function cp(from, to) {
  if (!fs.existsSync(from)) return false;
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
  return true;
}

function patchIndexHtmlFavicon(favSrc) {
  if (!fs.existsSync(indexPath)) {
    console.error("[sync-web-branding] Falta web/index.html");
    process.exit(1);
  }
  const dataUri = `data:image/png;base64,${fs.readFileSync(favSrc).toString("base64")}`;
  const stamp = Date.now();
  let html = fs.readFileSync(indexPath, "utf8");

  const block = `  <!-- RAI_FAVICON_START — icono pestaña navegador (no AppBar) -->
  <link rel="icon" type="image/png" href="${dataUri}">
  <link rel="shortcut icon" type="image/png" href="${dataUri}">
  <link rel="icon" type="image/png" sizes="32x32" href="icons/rai-tab.png?v=${stamp}">
  <link rel="icon" type="image/png" sizes="192x192" href="icons/Icon-192.png?v=${stamp}">
  <link rel="apple-touch-icon" href="icons/Icon-192.png?v=${stamp}">
  <!-- RAI_FAVICON_END -->`;

  if (html.includes("RAI_FAVICON_START")) {
    html = html.replace(
      /<!-- RAI_FAVICON_START[\s\S]*?<!-- RAI_FAVICON_END -->/,
      block
    );
  } else if (html.includes("<!-- Favicon RAI")) {
    html = html.replace(
      /<!-- Favicon RAI[\s\S]*?(?=\n  <title>)/,
      block
    );
  } else {
    html = html.replace("<title>", `${block}\n\n  <title>`);
  }

  // Quitar apple-touch-icon suelto fuera del bloque (legacy).
  html = html.replace(
    /\n\s*<link rel="apple-touch-icon" href="icons\/Icon-192\.png[^"]*">\s*(?=\n\s*<!-- RAI_FAVICON_START)/,
    "\n"
  );

  fs.writeFileSync(indexPath, html);
  console.log(`[sync-web-branding] web/index.html favicon RAI inline (?v=${stamp})`);
}

console.log("[sync-web-branding] Generando iconos web (flutter_launcher_icons)…");
execSync("dart run flutter_launcher_icons", {
  cwd: root,
  stdio: "inherit",
});

const favicon = path.join(webDir, "favicon.png");
if (!fs.existsSync(favicon)) {
  console.error("[sync-web-branding] No se generó web/favicon.png");
  process.exit(1);
}

const bytes = fs.statSync(favicon).size;
if (bytes < 400) {
  console.error(
    `[sync-web-branding] ERROR: favicon.png=${bytes} B parece icono Flutter default.`
  );
  process.exit(1);
}

cp(favicon, path.join(webDir, "favicon.ico"));
cp(favicon, path.join(webDir, "favicon-rai.png"));
cp(favicon, path.join(iconsDir, "rai-tab.png"));
patchIndexHtmlFavicon(favicon);

console.log(
  `[sync-web-branding] OK favicon RAI (${bytes} B) en web/ + index.html inline`
);
