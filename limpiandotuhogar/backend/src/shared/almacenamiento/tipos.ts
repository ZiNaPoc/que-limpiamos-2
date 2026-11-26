/**
 * Abstracción de almacenamiento de archivos (D5). Hoy hay una implementación LOCAL para
 * desarrollo y demostración; mañana se puede agregar una compatible con S3 (R2, S3, B2…)
 * que implemente esta misma interfaz, sin tocar la lógica del backend.
 *
 * Reglas comunes a cualquier implementación:
 *  - Nada es público: no hay rutas estáticas ni URLs permanentes.
 *  - La BD guarda solo la CLAVE del objeto (nunca una URL).
 *  - Para ver un archivo, el endpoint que lo pide AUTORIZA primero (guard + permiso) y
 *    después pide una URL TEMPORAL (en S3 sería una URL firmada del proveedor).
 */

export type TipoMime = "image/jpeg" | "image/png" | "image/webp" | "application/pdf";

/** Para qué es el archivo: decide qué tipos se aceptan. */
export type Proposito = "IDENTIDAD" | "COMPROBANTE" | "EVIDENCIA" | "PERFIL";

/** Agrupación física (carpetas locales hoy; buckets separados en la nube mañana). */
export type Espacio = "identidad" | "legal" | "evidencias" | "perfiles";

/** Archivo ya validado (tipo real, extensión, tamaño) y sin metadatos de ubicación. */
export type ArchivoValidado = {
  contenido: Buffer;
  mime: TipoMime;
  extension: "jpg" | "png" | "webp" | "pdf";
  bytes: number;
  sha256: string;
  /** Qué metadatos se quitaron (p. ej. EXIF con GPS, XMP). */
  metadatosEliminados: string[];
};

export type ObjetoGuardado = { clave: string; mime: TipoMime; bytes: number; sha256: string };

export interface Almacenamiento {
  readonly tipo: "local";
  guardar(espacio: Espacio, prefijo: string, archivo: ArchivoValidado): Promise<ObjetoGuardado>;
  leer(clave: string): Promise<Buffer>;
  existe(clave: string): Promise<boolean>;
  /** Idempotente: si no existe, no falla. */
  eliminar(clave: string): Promise<void>;
  /** URL de descarga TEMPORAL. Llamarla solo DESPUÉS de autorizar a quien la pide. */
  urlTemporal(clave: string, opciones: { mime: TipoMime; segundos: number }): Promise<string>;
}
