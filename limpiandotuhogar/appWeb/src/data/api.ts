import type { Sesion } from "./tipos";

// URL del backend. Se configura con VITE_API_URL; en desarrollo, el backend local.
// Debe ser solo el origen (sin "/api" ni barra final): las rutas ya empiezan con "/api/...".
// Se quitan las barras finales para que "http://host/" no genere "http://host//api/...".
export const API_URL: string = (import.meta.env.VITE_API_URL ?? "http://localhost:3000").replace(/\/+$/, "");

// Error de una petición al backend: lleva el mensaje para mostrar, el status y el código.
export class ErrorDeApi extends Error {
  status: number;
  codigo?: string;

  constructor(mensaje: string, status: number, codigo?: string) {
    super(mensaje);
    this.name = "ErrorDeApi";
    this.status = status;
    this.codigo = codigo;
  }
}

// Si cualquier petición responde 401, la cookie de sesión venció o no es válida:
// se avisa con este evento y App vuelve al login.
const EVENTO_SESION_EXPIRADA = "ql:sesion-expirada";

export function alExpirarLaSesion(accion: () => void): () => void {
  window.addEventListener(EVENTO_SESION_EXPIRADA, accion);
  return () => window.removeEventListener(EVENTO_SESION_EXPIRADA, accion);
}

async function leerJson(respuesta: Response): Promise<Record<string, unknown>> {
  const texto = await respuesta.text();
  if (!texto.trim()) return {};
  try {
    return JSON.parse(texto) as Record<string, unknown>;
  } catch {
    throw new ErrorDeApi("Respuesta inválida del servidor", respuesta.status);
  }
}

// Petición al backend con la cookie de sesión. Lanza ErrorDeApi si el servidor no responde
// o si responde con un error (antes devolvía los datos aunque la respuesta fuera un error).
export async function apiFetch<T>(ruta: string, opciones: RequestInit = {}): Promise<T> {
  const headers = new Headers(opciones.headers);
  if (opciones.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  let respuesta: Response;
  try {
    respuesta = await fetch(`${API_URL}${ruta}`, { ...opciones, headers, credentials: "include" });
  } catch {
    throw new ErrorDeApi("No se pudo conectar con el servidor", 0);
  }

  const datos = await leerJson(respuesta);
  if (!respuesta.ok) {
    if (respuesta.status === 401) window.dispatchEvent(new Event(EVENTO_SESION_EXPIRADA));
    const mensaje = typeof datos.mensaje === "string" ? datos.mensaje : "No se pudo completar la operación";
    throw new ErrorDeApi(mensaje, respuesta.status, typeof datos.codigo === "string" ? datos.codigo : undefined);
  }
  return datos as T;
}

// Pregunta al servidor si la cookie de sesión sigue siendo válida.
// Devuelve el usuario, null si no hay sesión (401/403) o lanza ErrorDeApi si no hay conexión.
export async function consultarSesion(): Promise<Sesion | null> {
  let respuesta: Response;
  try {
    respuesta = await fetch(`${API_URL}/api/admin/auth/session`, { credentials: "include" });
  } catch {
    throw new ErrorDeApi("No se pudo conectar con el servidor", 0);
  }
  if (respuesta.status === 401 || respuesta.status === 403) return null;
  const datos = await leerJson(respuesta);
  if (!respuesta.ok) throw new ErrorDeApi("No se pudo comprobar la sesión", respuesta.status);
  return (datos.usuario as Sesion | undefined) ?? null;
}

// Cierra la sesión en el servidor (borra la cookie). Si falla, la web cierra la sesión igual.
export async function cerrarSesionEnServidor(): Promise<void> {
  try {
    await fetch(`${API_URL}/api/admin/auth/logout`, { method: "POST", credentials: "include" });
  } catch {
    // Sin conexión: la cookie vence sola (8 h) y la sesión local se borra de todos modos.
  }
}
