import { horarioCubreLaFecha } from "./horarios";
import type { EtapaDeSolicitud, HorarioDeTrabajo, SolicitudListado } from "../data/tipos";
import { estaActivaListado, obtenerEtapaListado } from "./consultasDeSolicitudes";

// Reglas de solicitudes que usan Inicio y Colaboradores.
// Se QUITARON las reglas locales para asignar, cambiar colaborador, confirmar, finalizar y cancelar:
// el administrador no interviene entre cliente y trabajador (D24, docs/backend/25 v2). Esas
// transiciones las hacen el cliente, el trabajador o el sistema, y las valida el backend.

// Calcula la etapa que se muestra, a partir del estado y de si hay colaborador.
export function obtenerEtapa(solicitud: SolicitudListado): EtapaDeSolicitud {
  return obtenerEtapaListado(solicitud);
}

// Activa = todavía en curso (Pendiente, Confirmado o En proceso).
export function estaActiva(solicitud: SolicitudListado): boolean {
  return estaActivaListado(solicitud);
}

// Servicios activos de un colaborador que quedarían fuera de un nuevo horario.
export function buscarServiciosFueraDelHorario(solicitudes: SolicitudListado[], idDelTrabajador: string, horario: HorarioDeTrabajo): SolicitudListado[] {
  return solicitudes.filter((solicitud) => solicitud.idTrabajador === idDelTrabajador && estaActiva(solicitud) && !horarioCubreLaFecha(horario, solicitud.fechaProgramada));
}

// Servicios activos (pendientes o confirmados) de un colaborador.
export function buscarServiciosActivosDelTrabajador(solicitudes: SolicitudListado[], idDelTrabajador: string): SolicitudListado[] {
  return solicitudes.filter((solicitud) => solicitud.idTrabajador === idDelTrabajador && estaActiva(solicitud));
}
