/**
 * Prepara build/web para Firebase Hosting (Windows-safe).
 * 1) Si existe salida de `flutter build web`, fusiona public/ encima.
 * 2) Fuerza favicon RAI (tamaño pestaña, nunca Flutter ~630 B).
 */
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const root = path.join(__dirname, "..");
const outDir = path.join(root, "build", "web");
const publicDir = path.join(root, "public");
const webDir = path.join(root, "web");

function cpR(src, dest) {
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(dest, { recursive: true });
  for (const ent of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, ent.name);
    const to = path.join(dest, ent.name);
    if (ent.isDirectory()) cpR(from, to);
    else fs.copyFileSync(from, to);
  }
}

function cpFile(src, dest) {
  if (!fs.existsSync(src)) return false;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  return true;
}

/** Favicon e iconos PWA = logo RAI pequeño (flutter_launcher_icons). */
function applyRaiWebBranding(out) {
  let favSrc = path.join(webDir, "favicon.png");
  if (!fs.existsSync(favSrc) || fs.statSync(favSrc).size > 200_000) {
    console.log("[prepare-hosting] Regenerando iconos web…");
    execSync("node scripts/sync-web-branding.js", { cwd: root, stdio: "inherit" });
  }

  favSrc = path.join(webDir, "favicon.png");
  if (!fs.existsSync(favSrc)) {
    console.error("[prepare-hosting] Falta web/favicon.png");
    process.exit(1);
  }

  const favBytes = fs.statSync(favSrc).size;
  if (favBytes < 400) {
    console.error(
      `[prepare-hosting] ERROR: favicon.png demasiado pequeño (${favBytes} B) — parece Flutter default.`
    );
    process.exit(1);
  }

  const iconsDir = path.join(out, "icons");
  fs.mkdirSync(iconsDir, { recursive: true });

  cpFile(favSrc, path.join(out, "favicon.png"));
  cpFile(favSrc, path.join(out, "favicon.ico"));
  cpFile(favSrc, path.join(out, "favicon-rai.png"));
  cpFile(favSrc, path.join(iconsDir, "rai-tab.png"));

  for (const name of [
    "Icon-192.png",
    "Icon-512.png",
    "Icon-maskable-192.png",
    "Icon-maskable-512.png",
  ]) {
    cpFile(path.join(webDir, "icons", name), path.join(iconsDir, name));
  }

  console.log(`[prepare-hosting] Favicon RAI → build/web (${favBytes} bytes).`);
}

/** Rompe caché del favicon Flutter (Chrome guarda /favicon.ico años). */
function patchIndexHtmlFaviconCache(out) {
  const indexPath = path.join(out, "index.html");
  const favSrc = path.join(out, "favicon.png");
  if (!fs.existsSync(indexPath) || !fs.existsSync(favSrc)) return;
  const stamp = `rai${Date.now()}`;
  const dataUri = `data:image/png;base64,${fs.readFileSync(favSrc).toString("base64")}`;
  let html = fs.readFileSync(indexPath, "utf8");

  // Inline primero: va dentro de index.html (no-cache) y no depende de favicon.ico cacheado.
  const faviconBlock = `  <!-- RAI_FAVICON_START — icono pestaña navegador (no AppBar) -->
  <link rel="icon" type="image/png" href="${dataUri}">
  <link rel="shortcut icon" type="image/png" href="${dataUri}">
  <link rel="icon" type="image/png" sizes="32x32" href="icons/rai-tab.png?v=${stamp}">
  <link rel="icon" type="image/png" sizes="192x192" href="icons/Icon-192.png?v=${stamp}">
  <link rel="apple-touch-icon" href="icons/Icon-192.png?v=${stamp}">`;

  if (html.includes("RAI_FAVICON_START")) {
    html = html.replace(
      /<!-- RAI_FAVICON_START[\s\S]*?<!-- RAI_FAVICON_END -->/,
      faviconBlock.trimEnd() + "\n  <!-- RAI_FAVICON_END -->"
    );
  } else if (html.includes("<!-- Favicon RAI")) {
    html = html.replace(
      /<!-- Favicon RAI[\s\S]*?(?=\n  <title>)/,
      faviconBlock
    );
  } else {
    html = html.replace("<title>", `${faviconBlock}\n\n  <title>`);
  }

  html = html.replace(/flutter_bootstrap\.js(\?[^\s"']*)?/g, `flutter_bootstrap.js?v=${stamp}`);
  fs.writeFileSync(indexPath, html);
  console.log(
    `[prepare-hosting] index.html favicon inline RAI + icons/rai-tab.png?v=${stamp}`
  );
}

if (!fs.existsSync(publicDir)) {
  console.error("[prepare-hosting] Falta carpeta public/");
  process.exit(1);
}

const hadFlutterBuild =
  fs.existsSync(outDir) &&
  (fs.existsSync(path.join(outDir, "flutter_bootstrap.js")) ||
    fs.existsSync(path.join(outDir, "main.dart.js")) ||
    fs.existsSync(path.join(outDir, "index.html")));

if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}

cpR(publicDir, outDir);
applyRaiWebBranding(outDir);
patchIndexHtmlFaviconCache(outDir);

/**
 * public/empresas es un HTML stub de redirect. Si queda en build/web, Firebase
 * sirve ese archivo (no el rewrite a la SPA) y /empresas no carga Flutter.
 */
function removeEmpresasStub(out) {
  const empresasDir = path.join(out, "empresas");
  if (!fs.existsSync(empresasDir)) return;
  fs.rmSync(empresasDir, { recursive: true, force: true });
  console.log(
    "[prepare-hosting] Quitado stub public/empresas → rewrite SPA /empresas.",
  );
}

/** SPA: Firebase sirve 404.html en rutas sin archivo; copiar index evita página rota. */
function ensureSpa404Fallback(out) {
  const indexPath = path.join(out, "index.html");
  const notFoundPath = path.join(out, "404.html");
  if (!fs.existsSync(indexPath)) return;
  fs.copyFileSync(indexPath, notFoundPath);
  console.log("[prepare-hosting] 404.html ← index.html (SPA admin/web).");
}

removeEmpresasStub(outDir);
ensureSpa404Fallback(outDir);

if (hadFlutterBuild) {
  console.log("[prepare-hosting] OK: public/ fusionado en build/web (Flutter web existente).");
} else if (
  fs.existsSync(path.join(outDir, "index.html")) ||
  fs.existsSync(path.join(outDir, "pool", "index.html"))
) {
  console.warn(
    "[prepare-hosting] AVISO: build/web sin app Flutter completa. Ejecutá:\n" +
      "  node scripts/sync-web-branding.js\n" +
      "  flutter build web --release\n" +
      "  firebase deploy --only hosting"
  );
  console.log("[prepare-hosting] OK: build/web creado desde public/ (mínimo).");
} else {
  console.error("[prepare-hosting] build/web vacío tras copiar public/");
  process.exit(1);
}
