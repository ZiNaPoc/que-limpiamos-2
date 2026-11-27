import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import type { Almacenamiento, ArchivoValidado, Espacio, ObjetoGuardado, TipoMime } from "./tipos";

/**
 * Almacenamiento LOCAL privado (desarrollo y demostraciones, sin costo).
 *  - Los archivos viven en una carpeta FUERA del repositorio y de cualquier carpeta pública
 *    (el constructor lo comprueba). No hay ruta estática que los sirva.
 *  - Para verlos, el backend firma una URL TEMPORAL a su propio endpoint
 *    (/api/archivos/temporal/<token>), que equivale a la URL firmada de un proveedor S3.
 *  - ⚠ En Render este disco NO es persistente: no sirve para producción.
 */

const ESPACIOS: readonly Espacio[] = ["identidad", "legal", "evidencias", "perfiles"];
const PATRON_SEGMENTO = /^[a-z0-9_-]{1,40}$/;
const PATRON_CLAVE = /^(identidad|legal|evidencias|perfiles)(\/[a-z0-9_-]{1,40}){0,4}\/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$/;
const MIMES: readonly TipoMime[] = ["image/jpeg", "image/png", "image/webp", "application/pdf"];

/** Carpeta raíz del repositorio git que contiene `desde` (o null). */
function raizDelRepositorio(desde: string): string | null {
  let actual = path.resolve(desde);
  for (;;) {
    if (existsSync(path.join(actual, ".git"))) return actual;
    const padre = path.dirname(actual);
    if (padre === actual) return null;
    actual = padre;
  }
}

const dentroDe = (hijo: string, padre: string) => {
  const relativa = path.relative(padre, hijo);
  return relativa === "" || (!relativa.startsWith("..") && !path.isAbsolute(relativa));
};

export type OpcionesLocal = { raiz: string; secretoFirma: string; ahora?: () => number };

export class AlmacenamientoLocal implements Almacenamiento {
  readonly tipo = "local" as const;
  private readonly raiz: string;
  private readonly secreto: string;
  private readonly ahora: () => number;

  constructor(opciones: OpcionesLocal) {
    this.raiz = path.resolve(opciones.raiz);
    const repositorio = raizDelRepositorio(__dirname);
    if (repositorio && dentroDe(this.raiz, repositorio)) {
      throw new Error(`La carpeta de almacenamiento (${this.raiz}) está dentro del repositorio: debe estar FUERA de git y de carpetas públicas`);
    }
    if (opciones.secretoFirma.length < 32) throw new Error("El secreto de firma debe tener al menos 32 caracteres");
    this.secreto = opciones.secretoFirma;
    this.ahora = opciones.ahora ?? Date.now;
  }

  /** Ruta física de una clave, comprobando que no se salga de la raíz. */
  private ruta(clave: string): string {
    if (!PATRON_CLAVE.test(clave)) throw new Error("Clave de archivo inválida");
    const ruta = path.resolve(this.raiz, ...clave.split("/"));
    if (!dentroDe(ruta, this.raiz)) throw new Error("Clave de archivo fuera del almacenamiento");
    return ruta;
  }

  async guardar(espacio: Espacio, prefijo: string, archivo: ArchivoValidado): Promise<ObjetoGuardado> {
    if (!ESPACIOS.includes(espacio)) throw new Error("Espacio inválido");
    const segmentos = prefijo ? prefijo.split("/") : [];
    if (segmentos.length > 4 || !segmentos.every((s) => PATRON_SEGMENTO.test(s))) throw new Error("Prefijo inválido");
    // Clave aleatoria y sin datos personales.
    const clave = [espacio, ...segmentos, `${randomUUID()}.${archivo.extension}`].join("/");
    const destino = this.ruta(clave);
    await mkdir(path.dirname(destino), { recursive: true, mode: 0o700 });
    const temporal = `${destino}.subiendo-${randomUUID()}`;
    await writeFile(temporal, archivo.contenido, { mode: 0o600, flag: "wx" });
    await rename(temporal, destino); // nunca queda un archivo a medias con el nombre final
    return { clave, mime: archivo.mime, bytes: archivo.bytes, sha256: archivo.sha256 };
  }

  async leer(clave: string): Promise<Buffer> {
    return readFile(this.ruta(clave));
  }

  async existe(clave: string): Promise<boolean> {
    try {
      return (await stat(this.ruta(clave))).isFile();
    } catch {
      return false;
    }
  }

  async eliminar(clave: string): Promise<void> {
    await rm(this.ruta(clave), { force: true });
  }

  /** URL relativa al API: la app le antepone su URL base (igual que con cualquier ruta del API). */
  async urlTemporal(clave: string, opciones: { mime: TipoMime; segundos: number }): Promise<string> {
    this.ruta(clave);
    if (!MIMES.includes(opciones.mime)) throw new Error("Tipo inválido");
    if (!Number.isInteger(opciones.segundos) || opciones.segundos < 1 || opciones.segundos > 900) {
      throw new Error("La vigencia de la URL temporal debe estar entre 1 y 900 segundos");
    }
    const carga = Buffer.from(
      JSON.stringify({ c: clave, m: opciones.mime, e: Math.floor(this.ahora() / 1000) + opciones.segundos }),
    ).toString("base64url");
    return `/api/archivos/temporal/${carga}.${this.firmar(carga)}`;
  }

  /** Clave y tipo de un token válido y vigente; null si es falso, alterado o vencido. */
  resolverToken(token: string): { clave: string; mime: TipoMime } | null {
    const [carga, firma, ...resto] = token.split(".");
    if (!carga || !firma || resto.length) return null;
    const esperada = Buffer.from(this.firmar(carga));
    const recibida = Buffer.from(firma);
    if (esperada.length !== recibida.length || !timingSafeEqual(esperada, recibida)) return null;
    try {
      const datos = JSON.parse(Buffer.from(carga, "base64url").toString("utf8")) as { c?: unknown; m?: unknown; e?: unknown };
      if (typeof datos.c !== "string" || typeof datos.m !== "string" || typeof datos.e !== "number") return null;
      if (datos.e < Math.floor(this.ahora() / 1000)) return null;
      if (!PATRON_CLAVE.test(datos.c) || !MIMES.includes(datos.m as TipoMime)) return null;
      return { clave: datos.c, mime: datos.m as TipoMime };
    } catch {
      return null;
    }
  }

  private firmar(carga: string): string {
    return createHmac("sha256", this.secreto).update(carga).digest("base64url");
  }
}
