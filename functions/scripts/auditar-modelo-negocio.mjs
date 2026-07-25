/**
 * Runner: auditoría completa antes de publicar en Google Play.
 *
 *   node functions/scripts/auditar-modelo-negocio.mjs --config
 *   node functions/scripts/auditar-modelo-negocio.mjs --uid <taxistaUid> [--viaje <viajeId>]
 *   node functions/scripts/auditar-modelo-negocio.mjs --corporativo <viajeId>
 *   node functions/scripts/auditar-modelo-negocio.mjs --repair-bloqueo [--apply]
 *   node functions/scripts/auditar-modelo-negocio.mjs --unit-tests
 *
 * Ejecuta en orden:
 *   1. Tests unitarios prepago (npm test en functions/)
 *   2. Config global prepago + comisión
 *   3. Auditoría taxista (si --uid)
 *   4. Auditoría viaje corporativo (si --corporativo)
 */
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..", "..");
const functionsDir = join(root, "functions");
const node = process.execPath;

const args = process.argv.slice(2);
const runTests = args.includes("--unit-tests") || args.includes("--all");
const configOnly = args.includes("--config") || args.includes("--all");
const uidIdx = args.indexOf("--uid");
const uid = uidIdx >= 0 ? args[uidIdx + 1] : null;
const viajeIdx = args.indexOf("--viaje");
const viaje = viajeIdx >= 0 ? args[viajeIdx + 1] : null;
const corpIdx = args.indexOf("--corporativo");
const corpViaje = corpIdx >= 0 ? args[corpIdx + 1] : null;
const repairBloqueo = args.includes("--repair-bloqueo");
const repairApply = args.includes("--apply");
const projectIdx = args.indexOf("--project");
const project = projectIdx >= 0 ? args[projectIdx + 1] : "flygo-rd";
const projectArgs = ["--project", project];

function run(script, scriptArgs, label) {
  console.log(`\n${"=".repeat(60)}\n▶ ${label}\n${"=".repeat(60)}\n`);
  const r = spawnSync(node, [script, ...scriptArgs], {
    cwd: root,
    stdio: "inherit",
    shell: false,
  });
  if (r.status !== 0) {
    console.error(`\n✗ Falló: ${label} (exit ${r.status ?? 1})`);
    process.exit(r.status ?? 1);
  }
}

if (
  !runTests &&
  !configOnly &&
  !uid &&
  !corpViaje &&
  !repairBloqueo
) {
  console.log(
    "Auditoría modelo de negocio RAI — uso:\n\n" +
      "  node functions/scripts/auditar-modelo-negocio.mjs --all --uid <taxistaUid>\n" +
      "  node functions/scripts/auditar-modelo-negocio.mjs --unit-tests\n" +
      "  node functions/scripts/auditar-modelo-negocio.mjs --config\n" +
      "  node functions/scripts/auditar-modelo-negocio.mjs --uid <taxistaUid> [--viaje <id>]\n" +
      "  node functions/scripts/auditar-modelo-negocio.mjs --corporativo <viajeId>\n" +
      "  node functions/scripts/auditar-modelo-negocio.mjs --repair-bloqueo [--apply]\n",
  );
  process.exit(1);
}

if (runTests) {
  console.log("\n▶ Tests unitarios prepago/comisión\n");
  const r = spawnSync("npm", ["test"], {
    cwd: functionsDir,
    stdio: "inherit",
    shell: true,
  });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

if (configOnly || uid || runTests) {
  run(
    join("functions", "scripts", "auditar-prepago-comision-taxista.mjs"),
    ["--config", ...projectArgs],
    "Config prepago y comisión",
  );
}

if (uid) {
  const prepagoArgs = [uid, ...projectArgs];
  if (viaje) prepagoArgs.push("--viaje", viaje);
  run(
    join("functions", "scripts", "auditar-prepago-comision-taxista.mjs"),
    prepagoArgs,
    `Prepago taxista ${uid}`,
  );
}

if (corpViaje) {
  run(
    join("functions", "scripts", "auditar-viaje-corporativo.mjs"),
    [corpViaje, ...projectArgs],
    `Corporativo viaje ${corpViaje}`,
  );
}

if (repairBloqueo) {
  const repairArgs = repairApply ? ["--apply"] : ["--dry-run"];
  run(
    join("functions", "scripts", "reparar-bloqueo-prepago-taxistas.mjs"),
    [...repairArgs, ...projectArgs],
    repairApply ? "Reparar bloqueo prepago (aplicar)" : "Reparar bloqueo prepago (dry-run)",
  );
}

console.log("\n✓ Auditoría completada sin errores fatales.\n");
