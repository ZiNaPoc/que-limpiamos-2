import { apiFetch } from "./api";

// Módulos del panel con datos REALES (docs/backend/27): resumen, clientes, trabajadores y catálogo.

export type Resumen = {
  actualizadoEn: string;
  solicitudes: { porEstado: Record<string, number>; total: number; requierenAtencion: number; alertas: Record<string, number> };
  clientes: { total: number; verificados: number };
  trabajadores: { total: number; disponibles: number };
  reportesAbiertos: number;
  resenas: number;
};

export type ClienteAdmin = {
  id: number;
  nombre: string;
  correo: string;
  telefono: string | null;
  estadoCuenta: string;
  verificacion: "PENDIENTE" | "VERIFICADO" | "RECHAZADO";
  registradoEn: string;
  solicitudes: { total: number; activas: number; realizadas: number };
  inmueblesGuardados: number;
};

export type TrabajadorAdmin = {
  id: number;
  nombre: string;
  correo: string;
  telefono: string;
  direccion: string;
  estado: "ACTIVO" | "INACTIVO" | "BAJA";
  verificacion: "PENDIENTE" | "VERIFICADO" | "RECHAZADO";
  disponibleParaSolicitudes: boolean;
  registradoEn: string;
  especialidades: string[];
  servicios: { activos: number; realizados: number };
  reputacion: { promedio: number | null; cantidad: number };
};

export type ServicioAdmin = { id: number; nombre: string; descripcion: string; precioBase: number; duracionMin: number; estado: "ACTIVO" | "INACTIVO"; especialidadIds: number[]; solicitudes: number };
export type ExtraAdmin = { id: number; nombre: string; descripcion: string | null; precio: number; duracionMin: number; estado: "ACTIVO" | "INACTIVO" };
export type AreaAdmin = { id: number; nombre: string; orden: number; estado: "ACTIVO" | "INACTIVO" };
export type CatalogoAdmin = { servicios: ServicioAdmin[]; extras: ExtraAdmin[]; areas: AreaAdmin[]; especialidades: { id: number; nombre: string; estado: string }[] };

export const consultarResumen = () => apiFetch<Resumen>("/api/admin/resumen");

export async function consultarClientes(q: string, verificacion: string) {
  const p = new URLSearchParams();
  if (q.trim()) p.set("q", q.trim());
  if (verificacion) p.set("verificacion", verificacion);
  return (await apiFetch<{ clientes: ClienteAdmin[] }>(`/api/admin/clientes?${p.toString()}`)).clientes;
}

export async function consultarTrabajadores(q: string) {
  const p = new URLSearchParams();
  if (q.trim()) p.set("q", q.trim());
  return (await apiFetch<{ trabajadores: TrabajadorAdmin[] }>(`/api/admin/trabajadores?${p.toString()}`)).trabajadores;
}

export const consultarCatalogo = () => apiFetch<CatalogoAdmin>("/api/admin/catalogo");

const enviar = (metodo: "POST" | "PATCH", ruta: string, cuerpo: Record<string, unknown>) => apiFetch<{ id: number }>(`/api/admin/catalogo${ruta}`, { method: metodo, body: JSON.stringify(cuerpo) });

export const catalogo = {
  crearServicio: (c: Record<string, unknown>) => enviar("POST", "/servicios", c),
  editarServicio: (id: number, c: Record<string, unknown>) => enviar("PATCH", `/servicios/${id}`, c),
  crearExtra: (c: Record<string, unknown>) => enviar("POST", "/extras", c),
  editarExtra: (id: number, c: Record<string, unknown>) => enviar("PATCH", `/extras/${id}`, c),
  crearArea: (c: Record<string, unknown>) => enviar("POST", "/areas", c),
  editarArea: (id: number, c: Record<string, unknown>) => enviar("PATCH", `/areas/${id}`, c),
};

export const dinero = (n: number) => n.toLocaleString("es-MX", { style: "currency", currency: "MXN" });
