import { crc32 } from "node:zlib";

/**
 * Revisión ESTRUCTURAL de imágenes y PDF y eliminación de metadatos, sin dependencias.
 *
 *  - JPEG: se quitan EXIF, XMP (APP1), IPTC (APP13), comentarios (COM) y los APPn no
 *    necesarios para mostrar la imagen. Se conserva SOLO la orientación (si la había) en un
 *    EXIF mínimo nuevo, para que la foto no se vea girada. Así se elimina el GPS.
 *  - PNG: se quitan los bloques eXIf, tEXt, zTXt e iTXt (donde va el XMP). Se verifican los CRC.
 *  - WebP: se quitan los bloques EXIF y "XMP " y se apagan sus banderas en VP8X.
 *  - PDF: solo se comprueba la estructura mínima (no lleva GPS de cámara; no se modifica).
 * Si el archivo no tiene la estructura esperada, se lanza ArchivoDanado.
 */

export class ArchivoDanado extends Error {}

export type Limpieza = { contenido: Buffer; eliminados: string[] };

const danado = (motivo: string): never => {
  throw new ArchivoDanado(motivo);
};

// ── JPEG ────────────────────────────────────────────────────────────────────

/** Orientación (1–8) del EXIF de un segmento APP1, o undefined. */
function leerOrientacion(datos: Buffer): number | undefined {
  if (datos.length < 14 || datos.toString("latin1", 0, 6) !== "Exif\0\0") return undefined;
  const tiff = datos.subarray(6);
  const orden = tiff.toString("latin1", 0, 2);
  if (orden !== "II" && orden !== "MM") return undefined;
  const le = orden === "II";
  const u16 = (o: number) => (o + 2 <= tiff.length ? (le ? tiff.readUInt16LE(o) : tiff.readUInt16BE(o)) : undefined);
  const u32 = (o: number) => (o + 4 <= tiff.length ? (le ? tiff.readUInt32LE(o) : tiff.readUInt32BE(o)) : undefined);
  if (u16(2) !== 0x2a) return undefined;
  const ifd0 = u32(4);
  const n = ifd0 === undefined ? undefined : u16(ifd0);
  if (ifd0 === undefined || n === undefined) return undefined;
  for (let k = 0; k < n; k++) {
    const e = ifd0 + 2 + k * 12;
    if (e + 12 > tiff.length) break;
    if (u16(e) === 0x0112 && u16(e + 2) === 3) {
      const valor = u16(e + 8);
      return valor && valor >= 1 && valor <= 8 ? valor : undefined;
    }
  }
  return undefined;
}

/** Segmento APP1 con un EXIF que solo contiene la orientación. */
function exifSoloOrientacion(orientacion: number): Buffer {
  const d = Buffer.alloc(32);
  d.write("Exif\0\0", 0, "latin1");
  d.write("MM", 6, "latin1");
  d.writeUInt16BE(0x2a, 8);
  d.writeUInt32BE(8, 10); // IFD0 a 8 bytes del inicio del TIFF
  d.writeUInt16BE(1, 14); // una entrada
  d.writeUInt16BE(0x0112, 16); // Orientation
  d.writeUInt16BE(3, 18); // SHORT
  d.writeUInt32BE(1, 20);
  d.writeUInt16BE(orientacion, 24);
  d.writeUInt32BE(0, 28); // no hay más IFD
  const cabecera = Buffer.from([0xff, 0xe1, 0, 0]);
  cabecera.writeUInt16BE(d.length + 2, 2);
  return Buffer.concat([cabecera, d]);
}

const ES_SOF = (m: number) => m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc;
/** APPn que se conservan: APP0 (JFIF), APP2 (perfil de color ICC), APP14 (Adobe, color). */
const APP_CONSERVADOS = new Set([0xe0, 0xe2, 0xee]);

export function limpiarJpeg(b: Buffer): Limpieza {
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) danado("no empieza como JPEG");
  const segmentos: Buffer[] = [];
  const eliminados = new Set<string>();
  let orientacion: number | undefined;
  let tieneSof = false;
  let resto: Buffer | undefined;
  let i = 2;
  while (i < b.length) {
    if (b[i] !== 0xff) danado("falta un marcador JPEG");
    while (b[i] === 0xff) i++; // bytes de relleno
    const m = b[i];
    if (m === undefined) danado("JPEG truncado");
    i++;
    if (m === 0xd9) danado("JPEG sin imagen (fin antes de los datos)");
    if ((m! >= 0xd0 && m! <= 0xd7) || m === 0x01) {
      segmentos.push(Buffer.from([0xff, m!]));
      continue;
    }
    if (i + 2 > b.length) danado("JPEG truncado");
    const largo = b.readUInt16BE(i);
    if (largo < 2 || i + largo > b.length) danado("segmento JPEG inválido");
    const datos = b.subarray(i + 2, i + largo);
    const segmento = Buffer.concat([Buffer.from([0xff, m!]), b.subarray(i, i + largo)]);
    i += largo;
    if (m === 0xda) {
      if (!tieneSof) danado("JPEG sin cabecera de imagen (SOF)");
      segmentos.push(segmento);
      resto = b.subarray(i); // datos de la imagen (y escaneos siguientes), se copian tal cual
      break;
    }
    if (ES_SOF(m!)) tieneSof = true;
    if (m === 0xe1) {
      const o = leerOrientacion(datos);
      if (o) orientacion = o;
      eliminados.add(datos.toString("latin1", 0, 6) === "Exif\0\0" ? "EXIF" : "XMP");
      continue;
    }
    if (m === 0xed) {
      eliminados.add("IPTC");
      continue;
    }
    if (m === 0xfe) {
      eliminados.add("COMENTARIO");
      continue;
    }
    if (m! >= 0xe0 && m! <= 0xef && !APP_CONSERVADOS.has(m!)) {
      eliminados.add(`APP${m! - 0xe0}`);
      continue;
    }
    segmentos.push(segmento);
  }
  if (!resto) danado("JPEG sin datos de imagen");
  let fin = resto!.length;
  while (fin > 0 && resto![fin - 1] === 0x00) fin--;
  if (fin < 2 || resto![fin - 2] !== 0xff || resto![fin - 1] !== 0xd9) danado("JPEG truncado (falta el final)");

  // EXIF mínimo con la orientación, después de APP0 si existe.
  const partes: Buffer[] = [Buffer.from([0xff, 0xd8])];
  const despuesDeApp0 = segmentos[0]?.[1] === 0xe0 ? 1 : 0;
  partes.push(...segmentos.slice(0, despuesDeApp0));
  if (orientacion && orientacion !== 1) partes.push(exifSoloOrientacion(orientacion));
  partes.push(...segmentos.slice(despuesDeApp0), resto!.subarray(0, fin));
  return { contenido: Buffer.concat(partes), eliminados: [...eliminados] };
}

/** Orientación del primer EXIF de un JPEG (para pruebas y diagnóstico). */
export function orientacionJpeg(b: Buffer): number | undefined {
  let i = 2;
  while (i + 4 <= b.length && b[i] === 0xff) {
    const m = b[i + 1]!;
    if (m === 0xda) return undefined;
    const largo = b.readUInt16BE(i + 2);
    if (m === 0xe1) {
      const o = leerOrientacion(b.subarray(i + 4, i + 2 + largo));
      if (o) return o;
    }
    i += 2 + largo;
  }
  return undefined;
}

// ── PNG ─────────────────────────────────────────────────────────────────────

const FIRMA_PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PNG_ELIMINAR = new Set(["eXIf", "tEXt", "zTXt", "iTXt"]);

export function limpiarPng(b: Buffer): Limpieza {
  if (b.length < 8 || !b.subarray(0, 8).equals(FIRMA_PNG)) danado("no empieza como PNG");
  const partes: Buffer[] = [FIRMA_PNG];
  const eliminados = new Set<string>();
  let i = 8;
  let primero = true;
  let fin = false;
  let tieneImagen = false;
  while (i < b.length && !fin) {
    if (i + 12 > b.length) danado("PNG truncado");
    const largo = b.readUInt32BE(i);
    const tipo = b.toString("latin1", i + 4, i + 8);
    if (i + 12 + largo > b.length) danado("bloque PNG fuera de rango");
    const tipoYDatos = b.subarray(i + 4, i + 8 + largo);
    if (crc32(tipoYDatos) !== b.readUInt32BE(i + 8 + largo)) danado(`CRC inválido en el bloque ${tipo}`);
    if (primero && (tipo !== "IHDR" || largo !== 13)) danado("PNG sin cabecera IHDR");
    primero = false;
    const bloque = b.subarray(i, i + 12 + largo);
    i += 12 + largo;
    if (tipo === "IEND") fin = true;
    if (tipo === "IDAT") tieneImagen = true;
    if (PNG_ELIMINAR.has(tipo)) {
      eliminados.add(tipo === "eXIf" ? "EXIF" : "TEXTO/XMP");
      continue;
    }
    partes.push(bloque);
  }
  if (!fin) danado("PNG sin fin (IEND)");
  if (!tieneImagen) danado("PNG sin datos de imagen (IDAT)");
  return { contenido: Buffer.concat(partes), eliminados: [...eliminados] };
}

// ── WebP ────────────────────────────────────────────────────────────────────

export function limpiarWebp(b: Buffer): Limpieza {
  if (b.length < 20 || b.toString("latin1", 0, 4) !== "RIFF" || b.toString("latin1", 8, 12) !== "WEBP") danado("no es WebP");
  const tamano = b.readUInt32LE(4);
  if (tamano + 8 > b.length || tamano < 12) danado("WebP con tamaño inválido");
  const fin = tamano + 8;
  const bloques: Buffer[] = [];
  const eliminados = new Set<string>();
  let tieneImagen = false;
  let i = 12;
  while (i < fin) {
    if (i + 8 > fin) danado("WebP truncado");
    const tipo = b.toString("latin1", i, i + 4);
    const largo = b.readUInt32LE(i + 4);
    const total = 8 + largo + (largo % 2);
    if (i + 8 + largo > fin) danado("bloque WebP fuera de rango");
    let bloque = Buffer.from(b.subarray(i, Math.min(i + total, fin)));
    i += total;
    if (tipo === "EXIF" || tipo === "XMP ") {
      eliminados.add(tipo.trim());
      continue;
    }
    if (tipo === "VP8 " || tipo === "VP8L" || tipo === "VP8X") tieneImagen = true;
    if (tipo === "VP8X" && largo >= 10) {
      bloque = Buffer.from(bloque);
      bloque[8] = bloque[8]! & ~(0x08 | 0x04); // apagar banderas de EXIF y XMP
    }
    if (bloque.length < total) bloque = Buffer.concat([bloque, Buffer.alloc(total - bloque.length)]);
    bloques.push(bloque);
  }
  if (!tieneImagen) danado("WebP sin datos de imagen");
  const cuerpo = Buffer.concat(bloques);
  const cabecera = Buffer.alloc(12);
  cabecera.write("RIFF", 0, "latin1");
  cabecera.writeUInt32LE(cuerpo.length + 4, 4);
  cabecera.write("WEBP", 8, "latin1");
  return { contenido: Buffer.concat([cabecera, cuerpo]), eliminados: [...eliminados] };
}

// ── PDF ─────────────────────────────────────────────────────────────────────

export function revisarPdf(b: Buffer): Limpieza {
  if (b.toString("latin1", 0, 5) !== "%PDF-") danado("no empieza como PDF");
  if (!b.subarray(Math.max(0, b.length - 1024)).toString("latin1").includes("%%EOF")) danado("PDF truncado (falta %%EOF)");
  return { contenido: b, eliminados: [] };
}
