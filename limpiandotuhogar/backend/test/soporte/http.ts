import { once } from "node:events";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";

import type { Express } from "express";

/** Levanta la app en un puerto libre de 127.0.0.1 (no publica nada fuera del equipo). */
export async function iniciarServidor(app: Express) {
  const servidor: Server = app.listen(0, "127.0.0.1");
  await once(servidor, "listening");
  const { port } = servidor.address() as AddressInfo;
  return {
    base: `http://127.0.0.1:${port}`,
    cerrar: () => new Promise<void>((resolver) => servidor.close(() => resolver())),
  };
}

export type Respuesta = { status: number; cuerpo: any; texto: string; headers: Headers };
export type OpcionesPeticion = {
  cuerpo?: unknown;
  /** Cuerpo tal cual (para probar JSON mal formado). */
  crudo?: string;
  token?: string;
  cookie?: string;
  origen?: string;
};

export function crearPeticiones(base: string) {
  return async function pedir(metodo: string, ruta: string, opciones: OpcionesPeticion = {}): Promise<Respuesta> {
    const headers: Record<string, string> = {};
    if (opciones.cuerpo !== undefined || opciones.crudo !== undefined) headers["content-type"] = "application/json";
    if (opciones.token) headers.authorization = `Bearer ${opciones.token}`;
    if (opciones.cookie) headers.cookie = opciones.cookie;
    if (opciones.origen) headers.origin = opciones.origen;
    const r = await fetch(base + ruta, {
      method: metodo,
      headers,
      body: opciones.crudo ?? (opciones.cuerpo !== undefined ? JSON.stringify(opciones.cuerpo) : undefined),
    });
    const texto = await r.text();
    let cuerpo: unknown = null;
    try {
      cuerpo = texto ? JSON.parse(texto) : null;
    } catch {
      cuerpo = texto;
    }
    return { status: r.status, cuerpo, texto, headers: r.headers };
  };
}

/** "ql_admin=valor" a partir del Set-Cookie de una respuesta (o null). */
export function cookieDe(respuesta: Respuesta, nombre: string): { par: string; atributos: string } | null {
  for (const linea of respuesta.headers.getSetCookie()) {
    const [par = "", ...atributos] = linea.split(";").map((p) => p.trim());
    if (par.startsWith(`${nombre}=`)) return { par, atributos: atributos.join("; ") };
  }
  return null;
}
