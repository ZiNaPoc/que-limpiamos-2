import { crc32 } from "node:zlib";

/**
 * Archivos de prueba construidos en memoria, con metadatos de ubicación (GPS) reales en su
 * estructura: EXIF con el puntero GPSInfo, XMP con exif:GPSLatitude y comentarios.
 */

const segmentoJpeg = (marcador: number, datos: Buffer) => {
  const cabecera = Buffer.from([0xff, marcador, 0, 0]);
  cabecera.writeUInt16BE(datos.length + 2, 2);
  return Buffer.concat([cabecera, datos]);
};

/** EXIF little-endian con Orientation y un IFD de GPS (GPSLatitudeRef = "N"). */
function exifConGps(orientacion: number): Buffer {
  const tiff = Buffer.alloc(56);
  tiff.write("II", 0, "latin1");
  tiff.writeUInt16LE(0x2a, 2);
  tiff.writeUInt32LE(8, 4);
  tiff.writeUInt16LE(2, 8); // IFD0: 2 entradas
  tiff.writeUInt16LE(0x0112, 10); // Orientation
  tiff.writeUInt16LE(3, 12);
  tiff.writeUInt32LE(1, 14);
  tiff.writeUInt16LE(orientacion, 18);
  tiff.writeUInt16LE(0x8825, 22); // GPSInfo → IFD de GPS
  tiff.writeUInt16LE(4, 24);
  tiff.writeUInt32LE(1, 26);
  tiff.writeUInt32LE(38, 30);
  tiff.writeUInt32LE(0, 34); // fin de IFD0
  tiff.writeUInt16LE(1, 38); // IFD GPS: 1 entrada
  tiff.writeUInt16LE(0x0001, 40); // GPSLatitudeRef
  tiff.writeUInt16LE(2, 42);
  tiff.writeUInt32LE(2, 44);
  tiff.write("N\0", 48, "latin1");
  tiff.writeUInt32LE(0, 52);
  return Buffer.concat([Buffer.from("Exif\0\0", "latin1"), tiff]);
}

export const XMP_CON_GPS = "<x:xmpmeta><exif:GPSLatitude>21,10.5N</exif:GPSLatitude></x:xmpmeta>";

export function jpegConMetadatos(opciones: { orientacion?: number; sinExif?: boolean } = {}): Buffer {
  const app0 = Buffer.from([0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  const dqt = Buffer.concat([Buffer.from([0x00]), Buffer.alloc(64, 1)]);
  const sof0 = Buffer.from([8, 0, 1, 0, 1, 1, 1, 0x11, 0]);
  const dht = Buffer.concat([Buffer.from([0x00, 1]), Buffer.alloc(15, 0), Buffer.from([0])]);
  const sos = Buffer.from([1, 1, 0x00, 0, 63, 0]);
  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    segmentoJpeg(0xe0, app0),
    ...(opciones.sinExif ? [] : [segmentoJpeg(0xe1, exifConGps(opciones.orientacion ?? 6))]),
    segmentoJpeg(0xe1, Buffer.concat([Buffer.from("http://ns.adobe.com/xap/1.0/\0", "latin1"), Buffer.from(XMP_CON_GPS)])),
    segmentoJpeg(0xfe, Buffer.from("comentario con ubicacion de la casa")),
    segmentoJpeg(0xdb, dqt),
    segmentoJpeg(0xc0, sof0),
    segmentoJpeg(0xc4, dht),
    segmentoJpeg(0xda, sos),
    Buffer.from([0x00, 0x12, 0x34]),
    Buffer.from([0xff, 0xd9]),
  ]);
}

// PNG 1×1 válido.
const PNG_1X1 = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=",
  "base64",
);

export function bloquePng(tipo: string, datos: Buffer): Buffer {
  const largo = Buffer.alloc(4);
  largo.writeUInt32BE(datos.length);
  const tipoYDatos = Buffer.concat([Buffer.from(tipo, "latin1"), datos]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(tipoYDatos));
  return Buffer.concat([largo, tipoYDatos, crc]);
}

export function pngConMetadatos(): Buffer {
  const iend = PNG_1X1.subarray(PNG_1X1.length - 12);
  return Buffer.concat([
    PNG_1X1.subarray(0, PNG_1X1.length - 12),
    bloquePng("eXIf", exifConGps(6).subarray(6)),
    bloquePng("iTXt", Buffer.from(`XML:com.adobe.xmp\0\0\0\0\0${XMP_CON_GPS}`, "latin1")),
    bloquePng("tEXt", Buffer.from("Comment\0ubicacion de la casa", "latin1")),
    iend,
  ]);
}

const bloqueRiff = (tipo: string, datos: Buffer) => {
  const cabecera = Buffer.alloc(8);
  cabecera.write(tipo, 0, "latin1");
  cabecera.writeUInt32LE(datos.length, 4);
  return Buffer.concat([cabecera, datos, datos.length % 2 ? Buffer.alloc(1) : Buffer.alloc(0)]);
};

export function webpConMetadatos(): Buffer {
  const vp8x = Buffer.alloc(10);
  vp8x[0] = 0x08 | 0x04; // banderas EXIF y XMP
  const cuerpo = Buffer.concat([
    bloqueRiff("VP8X", vp8x),
    bloqueRiff("VP8L", Buffer.from([0x2f, 0, 0, 0, 0])),
    bloqueRiff("EXIF", exifConGps(6).subarray(6)),
    bloqueRiff("XMP ", Buffer.from(XMP_CON_GPS)),
  ]);
  const cabecera = Buffer.alloc(12);
  cabecera.write("RIFF", 0, "latin1");
  cabecera.writeUInt32LE(cuerpo.length + 4, 4);
  cabecera.write("WEBP", 8, "latin1");
  return Buffer.concat([cabecera, cuerpo]);
}

export const PDF_MINIMO = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n", "latin1");

/** ¿Contiene el buffer el tag GPSInfo (0x8825) en little o big endian, o texto de GPS? */
export function tieneRastrosDeGps(b: Buffer): boolean {
  return (
    b.includes(Buffer.from([0x25, 0x88])) ||
    b.includes(Buffer.from([0x88, 0x25])) ||
    b.includes(Buffer.from("GPSLatitude")) ||
    b.includes(Buffer.from("ubicacion"))
  );
}
