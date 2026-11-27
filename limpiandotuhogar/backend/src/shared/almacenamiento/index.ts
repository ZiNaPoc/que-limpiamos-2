import { almacenamientoConfig } from "../../config/almacenamiento";
import { AlmacenamientoLocal } from "./local";

export type { Almacenamiento, ArchivoValidado, Espacio, ObjetoGuardado, Proposito, TipoMime } from "./tipos";
export { validarArchivo } from "./validacion";
export { AlmacenamientoLocal } from "./local";

let instancia: AlmacenamientoLocal | undefined;

/**
 * El almacenamiento configurado (hoy siempre el local). Para migrar a S3/R2: crear otra clase
 * que implemente `Almacenamiento` y elegirla aquí según ALMACENAMIENTO_DRIVER; el resto del
 * backend usa solo la interfaz y no cambia.
 */
export function almacenamiento(): AlmacenamientoLocal {
  instancia ??= new AlmacenamientoLocal({
    raiz: almacenamientoConfig.directorioLocal,
    secretoFirma: almacenamientoConfig.secretoFirma,
  });
  return instancia;
}

/** Vigencia de las URLs temporales según lo que se entrega (identidad: 60 s; otros: 5 min). */
export function segundosUrlTemporal(tipo: "identidad" | "otros"): number {
  return almacenamientoConfig.segundosUrl[tipo];
}

export function maxBytesArchivo(): number {
  return almacenamientoConfig.maxBytes;
}
