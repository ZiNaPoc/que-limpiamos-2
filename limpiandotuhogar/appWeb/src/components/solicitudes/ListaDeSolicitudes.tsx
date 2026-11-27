import { ETIQUETA_DE_ALERTA, ETIQUETA_DE_ESTADO, ETIQUETA_DE_MODO, type EstadoApi, type SolicitudEnLista } from "../../data/solicitudesAdmin";
import { formatearFechaYHora } from "../../utils/fechasDeSolicitudes";

const BORDE_POR_ESTADO: Record<EstadoApi, string> = {
  PENDIENTE: "border-ochre",
  CONFIRMADO: "border-lagoon",
  EN_PROCESO: "border-steel",
  REALIZADO: "border-sage",
  CANCELADO: "border-frost",
  RECHAZADO: "border-err",
};

export function InsigniaDeEstadoDeSolicitud({ estado }: { estado: EstadoApi }) {
  return <span className="inline-flex whitespace-nowrap rounded-full bg-moon px-3 py-1 text-xs font-bold text-navy">{ETIQUETA_DE_ESTADO[estado]}</span>;
}

export function InsigniasDeAlerta({ alertas }: { alertas: SolicitudEnLista["alertas"] }) {
  if (!alertas.length) return null;
  return (
    <span className="flex flex-wrap gap-1.5">
      {alertas.map((a) => (
        <span key={a} className="inline-flex whitespace-nowrap rounded-full bg-err/10 px-2.5 py-0.5 text-xs font-bold text-err">
          {ETIQUETA_DE_ALERTA[a]}
        </span>
      ))}
    </span>
  );
}

function Colaborador({ s }: { s: SolicitudEnLista }) {
  if (s.trabajador) return <span className="font-bold text-navy">{s.trabajador.nombre}</span>;
  if (s.modo === "BOLSA") return <span className="text-slate">En la bolsa</span>;
  if (s.invitaciones.pendientes > 0) return <span className="text-slate">Invitación pendiente</span>;
  if (s.invitaciones.rechazadas > 0) return <span className="font-bold text-clay">Invitación rechazada</span>;
  return <span className="text-slate">—</span>;
}

type ListaDeSolicitudesProps = { solicitudes: SolicitudEnLista[]; onAbrir: (id: number) => void };

// Solicitudes REALES. Al hacer clic se abre su detalle (solo lectura, más la resolución).
export function ListaDeSolicitudes({ solicitudes, onAbrir }: ListaDeSolicitudesProps) {
  return (
    <div className="surface leaf-sm overflow-x-auto">
      <table className="w-full min-w-[56rem] text-left text-sm">
        <thead className="bg-moon/60 text-xs uppercase tracking-wider text-slate">
          <tr>
            <th scope="col" className="px-5 py-4 font-bold">Id</th>
            <th scope="col" className="px-4 py-4 font-bold">Cliente</th>
            <th scope="col" className="px-4 py-4 font-bold">Servicio</th>
            <th scope="col" className="px-4 py-4 font-bold">Programada</th>
            <th scope="col" className="px-4 py-4 font-bold">Asignación</th>
            <th scope="col" className="px-4 py-4 font-bold">Colaborador</th>
            <th scope="col" className="px-5 py-4 font-bold">Estado</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-mist/70">
          {solicitudes.map((s) => (
            <tr key={s.id} onClick={() => onAbrir(s.id)} className="cursor-pointer transition hover:bg-sky/25">
              <td className={`border-l-4 px-5 py-4 ${BORDE_POR_ESTADO[s.estado]}`}>
                <button onClick={() => onAbrir(s.id)} className="rounded-full bg-navy px-3 py-1 text-xs font-bold text-white" aria-label={`Abrir la solicitud ${s.id}`}>
                  {s.id}
                </button>
              </td>
              <td className="px-4 py-4">
                <span className="block font-bold text-navy">{s.cliente.nombre}</span>
                <span className="block text-xs text-slate">{s.cliente.telefono ?? s.cliente.correo}</span>
              </td>
              <td className="px-4 py-4">
                <span className="block text-navy">{s.servicio}</span>
                <span className="block max-w-[16rem] truncate text-xs text-slate" title={s.direccion}>
                  {s.direccion}
                </span>
              </td>
              <td className="whitespace-nowrap px-4 py-4 text-navy">{formatearFechaYHora(s.fechaProgramada)}</td>
              <td className="px-4 py-4 text-slate">{ETIQUETA_DE_MODO[s.modo]}</td>
              <td className="px-4 py-4">
                <Colaborador s={s} />
              </td>
              <td className="space-y-1.5 px-5 py-4">
                <InsigniaDeEstadoDeSolicitud estado={s.estado} />
                <InsigniasDeAlerta alertas={s.alertas} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
