// Fechas de las solicitudes en la hora de Cancún (D18), como las ven el cliente y el colaborador.
const ZONA = "America/Cancun";

const FECHA_Y_HORA = new Intl.DateTimeFormat("es-MX", { timeZone: ZONA, weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const HORA = new Intl.DateTimeFormat("es-MX", { timeZone: ZONA, hour: "2-digit", minute: "2-digit", second: "2-digit" });

export function formatearFechaYHora(iso: string | null | undefined): string {
  return iso ? FECHA_Y_HORA.format(new Date(iso)) : "—";
}

export function formatearHoraExacta(iso: string | null | undefined): string {
  return iso ? HORA.format(new Date(iso)) : "—";
}

// "hace 12 s", "hace 3 min"…
export function haceCuanto(iso: string | null, ahora: Date): string {
  if (!iso) return "sin actualizar";
  const s = Math.max(0, Math.round((ahora.getTime() - new Date(iso).getTime()) / 1000));
  if (s < 60) return `hace ${s} s`;
  const m = Math.round(s / 60);
  if (m < 60) return `hace ${m} min`;
  return `hace ${Math.round(m / 60)} h`;
}
