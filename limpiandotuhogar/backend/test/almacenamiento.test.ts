import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, describe, it } from "node:test";

import express from "express";

import { crearRouterDescargas } from "../src/shared/almacenamiento/descargas";
import { AlmacenamientoLocal } from "../src/shared/almacenamiento/local";
import { limpiarJpeg, limpiarPng, limpiarWebp, orientacionJpeg } from "../src/shared/almacenamiento/metadatos";
import { validarArchivo } from "../src/shared/almacenamiento/validacion";
import { crearPeticiones, iniciarServidor } from "./soporte/http";
import { bloquePng, jpegConMetadatos, PDF_MINIMO, pngConMetadatos, tieneRastrosDeGps, webpConMetadatos } from "./soporte/imagenes";

/** Almacenamiento local privado (D5, versión gratuita): validación, metadatos, carpeta y URLs temporales. Sin BD. */

const MAX = 5 * 1024 * 1024;
const RAIZ = path.join(os.tmpdir(), `ql-almacenamiento-pruebas-${randomUUID()}`);
const SECRETO = "secreto-de-pruebas-de-32-caracteres-o-mas";
after(() => rmSync(RAIZ, { recursive: true, force: true }));

const validar = (b: Buffer, nombre: string, extra: Partial<Parameters<typeof validarArchivo>[1]> = {}) =>
  validarArchivo(b, { proposito: "IDENTIDAD", nombreOriginal: nombre, maxBytes: MAX, ...extra });

function codigoDeError(fn: () => unknown): string | undefined {
  try {
    fn();
    return undefined;
  } catch (e) {
    return (e as { codigo?: string }).codigo ?? (e as Error).message;
  }
}

describe("Metadatos: se elimina el GPS y se conserva la imagen", () => {
  it("JPEG: quita EXIF (GPS), XMP y comentarios; conserva SOLO la orientación", () => {
    const original = jpegConMetadatos({ orientacion: 6 });
    assert.ok(tieneRastrosDeGps(original), "el archivo de prueba sí trae GPS");
    const { contenido, eliminados } = limpiarJpeg(original);
    assert.equal(tieneRastrosDeGps(contenido), false);
    assert.equal(orientacionJpeg(contenido), 6, "la foto no debe verse girada");
    assert.deepEqual(eliminados.sort(), ["COMENTARIO", "EXIF", "XMP"]);
    assert.deepEqual([contenido[0], contenido[1]], [0xff, 0xd8]);
    assert.deepEqual(limpiarJpeg(contenido).contenido, contenido, "limpiar dos veces da lo mismo");
  });

  it("JPEG sin orientación: no queda ningún APP1", () => {
    const { contenido } = limpiarJpeg(jpegConMetadatos({ orientacion: 1 }));
    assert.equal(contenido.includes(Buffer.from([0xff, 0xe1])), false);
  });

  it("PNG: quita eXIf, iTXt (XMP) y tEXt; los CRC siguen siendo válidos", () => {
    const original = pngConMetadatos();
    assert.ok(tieneRastrosDeGps(original));
    const { contenido, eliminados } = limpiarPng(original);
    assert.equal(tieneRastrosDeGps(contenido), false);
    for (const tipo of ["eXIf", "iTXt", "tEXt"]) assert.equal(contenido.includes(Buffer.from(tipo)), false, tipo);
    for (const tipo of ["IHDR", "IDAT", "IEND"]) assert.ok(contenido.includes(Buffer.from(tipo)), tipo);
    assert.doesNotThrow(() => limpiarPng(contenido));
    assert.deepEqual(eliminados.sort(), ["EXIF", "TEXTO/XMP"]);
  });

  it("WebP: quita EXIF y XMP, apaga sus banderas y corrige el tamaño RIFF", () => {
    const { contenido } = limpiarWebp(webpConMetadatos());
    assert.equal(tieneRastrosDeGps(contenido), false);
    assert.equal(contenido.includes(Buffer.from("EXIF")), false);
    assert.equal(contenido.includes(Buffer.from("XMP ")), false);
    const vp8x = contenido.indexOf(Buffer.from("VP8X"));
    assert.equal(contenido[vp8x + 8]! & 0x0c, 0);
    assert.equal(contenido.readUInt32LE(4), contenido.length - 8);
  });
});

describe("Validación: tamaño, tipo REAL, extensión y tipo declarado", () => {
  it("acepta JPEG, PNG y WebP de identidad y devuelve el archivo ya limpio", () => {
    for (const [b, nombre, mime] of [
      [jpegConMetadatos(), "ine.JPEG", "image/jpeg"],
      [pngConMetadatos(), "ine.png", "image/png"],
      [webpConMetadatos(), "ine.webp", "image/webp"],
    ] as const) {
      const r = validar(b, nombre, { mimeDeclarado: mime });
      assert.equal(r.mime, mime);
      assert.equal(tieneRastrosDeGps(r.contenido), false, nombre);
      assert.equal(r.bytes, r.contenido.length);
      assert.match(r.sha256, /^[0-9a-f]{64}$/);
    }
  });

  it("rechaza vacío (400), demasiado grande (413) y tipos desconocidos (415)", () => {
    assert.equal(codigoDeError(() => validar(Buffer.alloc(0), "a.jpg")), "ARCHIVO_VACIO");
    assert.equal(codigoDeError(() => validar(jpegConMetadatos(), "a.jpg", { maxBytes: 50 })), "ARCHIVO_DEMASIADO_GRANDE");
    assert.equal(codigoDeError(() => validar(Buffer.from("<html>hola</html>"), "a.jpg")), "TIPO_NO_PERMITIDO");
    assert.equal(codigoDeError(() => validar(Buffer.from("MZ\x90\x00 ejecutable"), "a.exe")), "TIPO_NO_PERMITIDO");
  });

  it("la extensión y el tipo declarado deben coincidir con el contenido real", () => {
    assert.equal(codigoDeError(() => validar(pngConMetadatos(), "foto.jpg")), "EXTENSION_NO_COINCIDE");
    assert.equal(codigoDeError(() => validar(jpegConMetadatos(), "foto")), "EXTENSION_NO_COINCIDE");
    assert.equal(codigoDeError(() => validar(jpegConMetadatos(), "foto.jpg", { mimeDeclarado: "image/png" })), "TIPO_NO_COINCIDE");
    assert.doesNotThrow(() => validar(jpegConMetadatos(), "foto.jpg", { mimeDeclarado: "image/jpg" }));
  });

  it("PDF solo donde el propósito lo permite (comprobante sí, identidad no)", () => {
    assert.equal(codigoDeError(() => validar(PDF_MINIMO, "ine.pdf")), "TIPO_NO_PERMITIDO");
    assert.equal(validar(PDF_MINIMO, "comprobante.pdf", { proposito: "COMPROBANTE" }).mime, "application/pdf");
  });

  it("archivos dañados → 400 ARCHIVO_DANADO (JPEG truncado, PNG con CRC alterado, WebP sin imagen)", () => {
    const jpeg = jpegConMetadatos();
    assert.equal(codigoDeError(() => validar(jpeg.subarray(0, jpeg.length - 10), "a.jpg")), "ARCHIVO_DANADO");
    const png = Buffer.from(pngConMetadatos());
    const posicion = png.indexOf(Buffer.from("IDAT")) + 6;
    png[posicion] = (png[posicion] ?? 0) ^ 0xff;
    assert.equal(codigoDeError(() => validar(png, "a.png")), "ARCHIVO_DANADO");
    const soloCabecera = Buffer.concat([Buffer.from("RIFF"), Buffer.from([4, 0, 0, 0]), Buffer.from("WEBP")]);
    assert.equal(codigoDeError(() => validar(Buffer.concat([soloCabecera, Buffer.alloc(8)]), "a.webp")), "ARCHIVO_DANADO");
    assert.equal(codigoDeError(() => validar(Buffer.concat([pngConMetadatos().subarray(0, 33), bloquePng("IEND", Buffer.alloc(0))]), "a.png")), "ARCHIVO_DANADO");
  });
});

describe("Almacenamiento local privado", () => {
  const almacen = new AlmacenamientoLocal({ raiz: RAIZ, secretoFirma: SECRETO });

  it("no acepta una carpeta dentro del repositorio (ni, por lo tanto, en carpetas públicas del proyecto)", () => {
    assert.throws(() => new AlmacenamientoLocal({ raiz: path.resolve(__dirname, "..", "archivos"), secretoFirma: SECRETO }), /dentro del repositorio/);
    assert.throws(() => new AlmacenamientoLocal({ raiz: path.resolve(__dirname, "../../appWeb/public/x"), secretoFirma: SECRETO }), /dentro del repositorio/);
  });

  it("guarda con clave aleatoria sin datos personales, fuera del repo, y lee y borra (borrar dos veces no falla)", async () => {
    const archivo = validar(jpegConMetadatos(), "ine-frente.jpg");
    const objeto = await almacen.guardar("identidad", "clientes/12", archivo);
    assert.match(objeto.clave, /^identidad\/clientes\/12\/[0-9a-f-]{36}\.jpg$/);
    const ruta = path.join(RAIZ, ...objeto.clave.split("/"));
    assert.ok(existsSync(ruta));
    assert.deepEqual(readFileSync(ruta), archivo.contenido);
    assert.deepEqual(await almacen.leer(objeto.clave), archivo.contenido);
    assert.equal(await almacen.existe(objeto.clave), true);
    await almacen.eliminar(objeto.clave);
    assert.equal(await almacen.existe(objeto.clave), false);
    await almacen.eliminar(objeto.clave);
  });

  it("rechaza claves y prefijos que intenten salir de la carpeta", async () => {
    for (const clave of ["../secreto.txt", "identidad/../../x.jpg", "identidad/a/b.jpg", "C:/Windows/x.jpg", "identidad/A/0b5a3c1e-0000-4000-8000-000000000000.jpg"]) {
      await assert.rejects(() => almacen.leer(clave), /inválida|fuera/, clave);
    }
    const archivo = validar(jpegConMetadatos(), "a.jpg");
    await assert.rejects(() => almacen.guardar("identidad", "../fuera", archivo), /Prefijo/);
    await assert.rejects(() => almacen.guardar("identidad", "Clientes/12", archivo), /Prefijo/);
  });
});

describe("URL temporal y descarga (sin rutas estáticas)", () => {
  let ahora = Date.now();
  const almacen = new AlmacenamientoLocal({ raiz: RAIZ, secretoFirma: SECRETO, ahora: () => ahora });
  const app = express();
  app.use("/api/archivos", crearRouterDescargas(almacen));

  it("con token vigente entrega el archivo con encabezados privados; alterado, vencido o borrado → 404", async () => {
    const servidor = await iniciarServidor(app);
    const pedir = crearPeticiones(servidor.base);
    try {
      const archivo = validar(pngConMetadatos(), "evidencia.png", { proposito: "EVIDENCIA" });
      const objeto = await almacen.guardar("evidencias", "solicitudes/5", archivo);
      const url = await almacen.urlTemporal(objeto.clave, { mime: objeto.mime, segundos: 60 });
      assert.match(url, /^\/api\/archivos\/temporal\/[\w-]+\.[\w-]+$/);
      assert.ok(!url.includes(objeto.clave), "la URL no expone la ruta del archivo");

      const r = await fetch(servidor.base + url);
      assert.equal(r.status, 200);
      assert.deepEqual(Buffer.from(await r.arrayBuffer()), archivo.contenido);
      assert.equal(r.headers.get("content-type"), "image/png");
      assert.equal(r.headers.get("cache-control"), "no-store, private");
      assert.equal(r.headers.get("x-content-type-options"), "nosniff");

      const [carga, firma] = url.slice("/api/archivos/temporal/".length).split(".");
      const otraCarga = Buffer.from(JSON.stringify({ c: objeto.clave, m: "image/png", e: 9_999_999_999 })).toString("base64url");
      assert.equal((await pedir("GET", `/api/archivos/temporal/${otraCarga}.${firma}`)).status, 404, "carga alterada");
      assert.equal((await pedir("GET", `/api/archivos/temporal/${carga}.AAAA`)).status, 404, "firma alterada");
      assert.equal((await pedir("GET", "/api/archivos/temporal/cualquier-cosa")).status, 404);
      assert.equal((await pedir("GET", `/api/archivos/${objeto.clave}`)).status, 404, "no hay acceso por la ruta del archivo");

      ahora += 61_000;
      assert.equal((await pedir("GET", url)).status, 404, "vencida");
      ahora -= 61_000;
      await almacen.eliminar(objeto.clave);
      assert.equal((await pedir("GET", url)).status, 404, "archivo borrado");
      await assert.rejects(() => almacen.urlTemporal(objeto.clave, { mime: "image/png", segundos: 3600 }), /vigencia/);
    } finally {
      await servidor.cerrar();
    }
  });
});
