/**
 * Prepara build/web para Firebase Hosting (Windows-safe).
 * 1) Si existe salida de `flutter build web`, fusiona public/ encima.
 * 2) Si no, crea build/web solo desde public/ (pool + assetlinks).
 */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const outDir = path.join(root, "build", "web");
const publicDir = path.join(root, "public");

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

if (hadFlutterBuild) {
  console.log("[prepare-hosting] OK: public/ fusionado en build/web (Flutter web existente).");
} else if (
  fs.existsSync(path.join(outDir, "index.html")) ||
  fs.existsSync(path.join(outDir, "pool", "index.html"))
) {
  console.warn(
    "[prepare-hosting] AVISO: build/web sin app Flutter completa. " +
      "Para no perder el admin web en flygo-rd.web.app, ejecutá antes:\n" +
      "  flutter build web --release\n" +
      "y volvé a correr este script. Por ahora se despliega pool/ + .well-known."
  );
  console.log("[prepare-hosting] OK: build/web creado desde public/ (mínimo).");
} else {
  console.error("[prepare-hosting] build/web vacío tras copiar public/");
  process.exit(1);
}
