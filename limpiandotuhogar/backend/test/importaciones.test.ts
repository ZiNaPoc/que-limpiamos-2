import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

/**
 * Regla de arquitectura (03 §1): ningún módulo de audiencia importa de otro, y shared/ no
 * importa de modules/. Prueba estática: no necesita BD.
 */

const SRC = path.resolve(__dirname, "..", "src");
const AUDIENCIAS = ["cliente", "trabajador", "admin"] as const;

function archivos(dir: string): string[] {
  return readdirSync(dir).flatMap((nombre) => {
    const ruta = path.join(dir, nombre);
    return statSync(ruta).isDirectory() ? archivos(ruta) : /\.ts$/.test(nombre) ? [ruta] : [];
  });
}

function importaciones(archivo: string): string[] {
  const texto = readFileSync(archivo, "utf8");
  const patron = /(?:from\s+|import\s*\(\s*|require\(\s*|import\s+)["']([^"']+)["']/g;
  return [...texto.matchAll(patron)].map((m) => m[1] as string);
}

/** Ruta absoluta a la que apunta una importación relativa (o null si es un paquete). */
function destino(archivo: string, especificador: string): string | null {
  return especificador.startsWith(".") ? path.resolve(path.dirname(archivo), especificador) : null;
}

describe("Reglas de importación", () => {
  for (const audiencia of AUDIENCIAS) {
    it(`modules/${audiencia} no importa de las otras audiencias`, () => {
      const otras = AUDIENCIAS.filter((a) => a !== audiencia).map((a) => path.join(SRC, "modules", a));
      const violaciones = archivos(path.join(SRC, "modules", audiencia)).flatMap((archivo) =>
        importaciones(archivo)
          .filter((e) => {
            const d = destino(archivo, e);
            return d !== null && otras.some((o) => d === o || d.startsWith(o + path.sep));
          })
          .map((e) => `${path.relative(SRC, archivo)} → ${e}`),
      );
      assert.deepEqual(violaciones, []);
    });
  }

  it("no hay rutas estáticas: ningún archivo de src usa express.static ni serve-static (D5)", () => {
    const usos = archivos(SRC).filter((archivo) => /express\.static|serve-static|sendFile\(/.test(readFileSync(archivo, "utf8")));
    assert.deepEqual(usos.map((a) => path.relative(SRC, a)), []);
  });

  it("shared/ no importa de modules/", () => {
    const modulos = path.join(SRC, "modules");
    const violaciones = archivos(path.join(SRC, "shared")).flatMap((archivo) =>
      importaciones(archivo)
        .filter((e) => {
          const d = destino(archivo, e);
          return d !== null && (d === modulos || d.startsWith(modulos + path.sep));
        })
        .map((e) => `${path.relative(SRC, archivo)} → ${e}`),
    );
    assert.deepEqual(violaciones, []);
  });
});
