import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const rules = readFileSync(join(repoRoot, "firestore.rules"), "utf8");
const viajesRepo = readFileSync(
  join(repoRoot, "lib", "servicios", "viajes_repo.dart"),
  "utf8",
);

/** Cuerpo de una función de reglas `function nombre() { ... }`. */
function cuerpoFuncionReglas(nombre) {
  const inicio = rules.indexOf(`function ${nombre}()`);
  if (inicio < 0) return null;
  const abre = rules.indexOf("{", inicio);
  let nivel = 0;
  for (let i = abre; i < rules.length; i++) {
    if (rules[i] === "{") nivel++;
    if (rules[i] === "}") {
      nivel--;
      if (nivel === 0) return rules.slice(abre, i + 1);
    }
  }
  return null;
}

/** Bloque `allow update:` de `match /viajes/{viajeId}`. */
function bloqueUpdateViajes() {
  const matchIdx = rules.indexOf("match /viajes/{");
  assert.ok(matchIdx > 0, "falta match /viajes/{viajeId}");
  const updateIdx = rules.indexOf("allow update:", matchIdx);
  assert.ok(updateIdx > 0, "falta allow update en viajes");
  const finIdx = rules.indexOf("allow delete:", updateIdx);
  assert.ok(finIdx > updateIdx, "falta allow delete tras allow update");
  return rules.slice(updateIdx, finIdx);
}

/** Separa las ramas `||` de primer nivel (ignora los `||` anidados). */
function ramasTopLevel(expr) {
  const ramas = [];
  let nivel = 0;
  let desde = 0;
  for (let i = 0; i < expr.length; i++) {
    const c = expr[i];
    if (c === "(" || c === "[") nivel++;
    else if (c === ")" || c === "]") nivel--;
    else if (nivel === 0 && c === "|" && expr[i + 1] === "|") {
      ramas.push(expr.slice(desde, i));
      desde = i + 2;
      i++;
    }
  }
  ramas.push(expr.slice(desde));
  return ramas;
}

/** Ramas del `allow update` de viajes que autorizan a un chofer. */
function ramasChoferUpdateViajes() {
  return ramasTopLevel(bloqueUpdateViajes()).filter(
    (rama) =>
      rama.includes("resource.data.uidTaxista == request.auth.uid") ||
      rama.includes("request.resource.data.uidTaxista == request.auth.uid"),
  );
}

/** La rama no puede producir `estado == en_curso`. */
function ramaBloqueaEnCurso(rama) {
  if (rama.includes("viajeNoPasaAEnCurso()")) return true;
  const m = rama.match(/request\.resource\.data\.estado in \[([^\]]*)\]/);
  if (!m) return false;
  return !/en_?curso/i.test(m[1]);
}

test("app manipulada del chofer no puede escribir el PIN al marcar abordo", () => {
  const cuerpo = cuerpoFuncionReglas("taxistaFlujoPickupAbordoOk");
  assert.ok(cuerpo, "falta taxistaFlujoPickupAbordoOk");
  assert.ok(
    !cuerpo.includes("codigoVerific"),
    "pickup/abordo no debe permitir escribir codigoVerificacion/codigoVerificado",
  );
  assert.ok(cuerpo.includes("clienteAbordo"), "abordo sigue permitido");
  assert.ok(
    cuerpo.includes("pickupConfirmadoEn"),
    "confirmación de pickup sigue permitida",
  );
});

test("ninguna regla deja al chofer autoverificar el PIN", () => {
  assert.equal(
    cuerpoFuncionReglas("taxistaFlujoEnCursoOk"),
    null,
    "taxistaFlujoEnCursoOk permitía iniciar viaje sin backend",
  );
  assert.ok(
    !rules.includes("request.resource.data.codigoVerificado == true"),
    "nadie puede marcar codigoVerificado = true desde la app",
  );
});

test("toda rama del chofer restringe los campos de PIN que puede escribir", () => {
  const pinKeys = [
    "codigoVerificado",
    "boardingPin",
    "codigoRespaldoViaje",
    "intentosCodigo",
    "codigoBloqueado",
  ];
  const ramasChofer = ramasChoferUpdateViajes();
  assert.ok(ramasChofer.length >= 2);
  for (const rama of ramasChofer) {
    // O declara exactamente qué campos cambia, o bloquea el PIN explícitamente.
    const listaBlanca = rama.includes("changedOnly([");
    const guardPin =
      rama.includes("viajeNoTocaPinProtegido()") ||
      rama.includes("viajeClaimPinSinAutoverificar()");
    assert.ok(
      listaBlanca || guardPin,
      `rama de chofer sin control de campos PIN: ${rama.trim().slice(0, 140)}`,
    );
    if (listaBlanca && !guardPin) {
      const permitidos = rama.slice(rama.indexOf("changedOnly(["));
      for (const k of pinKeys) {
        assert.ok(
          !permitidos.includes(`"${k}"`),
          `changedOnly de chofer no debe incluir ${k}`,
        );
      }
    }
  }
});

test("el claim del pool no puede autoverificar el PIN", () => {
  const cuerpo = cuerpoFuncionReglas("viajeClaimPinSinAutoverificar");
  assert.ok(cuerpo, "falta viajeClaimPinSinAutoverificar");
  assert.ok(
    cuerpo.includes('request.resource.data.codigoVerificado == false'),
    "al reclamar, el PIN solo puede quedar sin verificar",
  );
  for (const k of ["boardingPin", "codigoRespaldoViaje", "intentosCodigo", "codigoBloqueado"]) {
    assert.ok(cuerpo.includes(`"${k}"`), `el claim debe bloquear ${k}`);
  }
  const claim = ramasChoferUpdateViajes().find((r) =>
    r.includes("request.resource.data.aceptado == true") &&
    r.includes("taxistaSinDeuda(request.auth.uid)") &&
    !r.includes("changedOnly(["),
  );
  assert.ok(claim, "no se encontró la rama de claim sin changedOnly");
  assert.ok(
    claim.includes("viajeClaimPinSinAutoverificar()"),
    "la rama de claim sin changedOnly debe llevar el guard de PIN",
  );
});

test("el chofer no puede pasar el viaje a en_curso desde la app", () => {
  assert.ok(
    cuerpoFuncionReglas("viajeNoPasaAEnCurso"),
    "falta el guard viajeNoPasaAEnCurso",
  );
  const ramas = ramasTopLevel(bloqueUpdateViajes());
  const ramasChofer = ramas.filter(
    (rama) =>
      rama.includes("resource.data.uidTaxista == request.auth.uid") ||
      rama.includes("request.resource.data.uidTaxista == request.auth.uid"),
  );
  assert.ok(ramasChofer.length >= 2, "se esperaban ramas de operación del chofer");
  for (const rama of ramasChofer) {
    assert.ok(
      ramaBloqueaEnCurso(rama),
      `rama de chofer sin guard de en_curso: ${rama.trim().slice(0, 140)}`,
    );
  }
});

test("el pasajero solo puede sembrar un PIN no verificado de 6 dígitos", () => {
  const rama = ramasTopLevel(bloqueUpdateViajes()).find((r) =>
    r.includes("request.resource.data.codigoVerificacion is string"),
  );
  assert.ok(rama, "falta la rama del pasajero que siembra el PIN");
  assert.ok(rama.includes("resource.data.codigoVerificado != true"));
  assert.ok(rama.includes("request.resource.data.codigoVerificado == false"));
  assert.ok(rama.includes("codigoVerificacion.size() == 6"));
  assert.ok(rama.includes("viajeNoPasaAEnCurso()"));
});

test("modo informativo corporativo no se autoconcede para saltar el PIN", () => {
  const cuerpo = cuerpoFuncionReglas("esPatchRutaCorpInformativaChofer");
  assert.ok(cuerpo, "falta esPatchRutaCorpInformativaChofer");
  assert.ok(cuerpo.includes("viajeNoTocaPinProtegido()"));
  assert.ok(
    !cuerpo.includes("request.resource.data.corporativoModoInformativo == true"),
    "el chofer no puede activar el modo informativo y pasar a en_curso en el mismo write",
  );
});

test("ViajesRepo.iniciarViaje no tiene fallback local de PIN", () => {
  assert.ok(
    viajesRepo.includes("_invocarIniciarViajeSeguro"),
    "iniciarViaje debe delegar en iniciarViajeSeguro",
  );
  assert.ok(
    !viajesRepo.includes("_iniciarViajeLocalFallback"),
    "el fallback local que escribía codigoVerificado debe estar eliminado",
  );
  assert.ok(
    !viajesRepo.includes("'estado': EstadosViaje.enCurso"),
    "el cliente Flutter no debe escribir estado en_curso en viajes",
  );
});
