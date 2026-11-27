import { createHash } from "node:crypto";
import path from "node:path";

import { AppError } from "../errors/AppError";
import { ArchivoDanado, limpiarJpeg, limpiarPng, limpiarWebp, revisarPdf, type Limpieza } from "./metadatos";
import type { ArchivoValidado, Proposito, TipoMime } from "./tipos";

/** Tipos aceptados por propósito. Los documentos de identidad, solo imágenes. */
const PERMITIDOS: Record<Proposito, TipoMime[]> = {
  IDENTIDAD: ["image/jpeg", "image/png", "image/webp"],
  COMPROBANTE: ["image/jpeg", "image/png", "image/webp", "application/pdf"],
  EVIDENCIA: ["image/jpeg", "image/png", "image/webp"],
  PERFIL: ["image/jpeg", "image/png", "image/webp"],
};

const EXTENSIONES: Record<TipoMime, { canonica: ArchivoValidado["extension"]; aceptadas: string[] }> = {
  "image/jpeg": { canonica: "jpg", aceptadas: ["jpg", "jpeg"] },
  "image/png": { canonica: "png", aceptadas: ["png"] },
  "image/webp": { canonica: "webp", aceptadas: ["webp"] },
  "application/pdf": { canonica: "pdf", aceptadas: ["pdf"] },
};

const LIMPIEZA: Record<TipoMime, (b: Buffer) => Limpieza> = {
  "image/jpeg": limpiarJpeg,
  "image/png": limpiarPng,
  "image/webp": limpiarWebp,
  "application/pdf": revisarPdf,
};

/** Tipo REAL por la firma de los primeros bytes (no por el nombre ni por lo que dice el cliente). */
export function detectarTipo(b: Buffer): TipoMime | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b.length >= 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png";
  if (b.length >= 12 && b.toString("latin1", 0, 4) === "RIFF" && b.toString("latin1", 8, 12) === "WEBP") return "image/webp";
  if (b.length >= 5 && b.toString("latin1", 0, 5) === "%PDF-") return "application/pdf";
  return null;
}

const NOMBRE_MIME: Record<TipoMime, string> = {
  "image/jpeg": "JPEG",
  "image/png": "PNG",
  "image/webp": "WebP",
  "application/pdf": "PDF",
};

/**
 * Valida un archivo recibido: tamaño, tipo real (firma), extensión y tipo declarado, y que el
 * propósito lo permita. Revisa su estructura y le quita los metadatos (GPS incluido).
 */
export function validarArchivo(
  contenido: Buffer,
  opciones: { proposito: Proposito; nombreOriginal: string; mimeDeclarado?: string; maxBytes: number },
): ArchivoValidado {
  if (!contenido.length) throw new AppError(400, "El archivo está vacío", "ARCHIVO_VACIO");
  if (contenido.length > opciones.maxBytes) {
    throw new AppError(413, `El archivo supera el máximo de ${Math.floor(opciones.maxBytes / 1048576)} MB`, "ARCHIVO_DEMASIADO_GRANDE");
  }

  const permitidos = PERMITIDOS[opciones.proposito];
  const lista = permitidos.map((m) => NOMBRE_MIME[m]).join(", ");
  const mime = detectarTipo(contenido);
  if (!mime || !permitidos.includes(mime)) {
    throw new AppError(415, `Tipo de archivo no permitido. Se aceptan: ${lista}`, "TIPO_NO_PERMITIDO");
  }

  const extension = path.extname(opciones.nombreOriginal).slice(1).toLowerCase();
  if (!EXTENSIONES[mime].aceptadas.includes(extension)) {
    throw new AppError(415, `La extensión del archivo no corresponde a su contenido (${NOMBRE_MIME[mime]})`, "EXTENSION_NO_COINCIDE");
  }

  if (opciones.mimeDeclarado) {
    const declarado = opciones.mimeDeclarado.split(";")[0]!.trim().toLowerCase().replace("image/jpg", "image/jpeg");
    if (declarado !== "application/octet-stream" && declarado !== mime) {
      throw new AppError(415, "El tipo declarado del archivo no corresponde a su contenido", "TIPO_NO_COINCIDE");
    }
  }

  let limpieza: Limpieza;
  try {
    limpieza = LIMPIEZA[mime](contenido);
  } catch (error) {
    if (error instanceof ArchivoDanado) throw new AppError(400, "El archivo está dañado o no es válido", "ARCHIVO_DANADO");
    throw error;
  }

  return {
    contenido: limpieza.contenido,
    mime,
    extension: EXTENSIONES[mime].canonica,
    bytes: limpieza.contenido.length,
    sha256: createHash("sha256").update(limpieza.contenido).digest("hex"),
    metadatosEliminados: limpieza.eliminados,
  };
}
