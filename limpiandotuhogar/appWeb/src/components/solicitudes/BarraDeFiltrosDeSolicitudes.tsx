import { ETIQUETA_DE_ESTADO, ETIQUETA_DE_MODO, type EstadoApi, type FiltrosDeSupervision, type ModoApi } from "../../data/solicitudesAdmin";
import { Icono } from "../comunes/Icono";

type BarraDeFiltrosDeSolicitudesProps = {
  filtros: FiltrosDeSupervision;
  total: number;
  visibles: number;
  onCambiarFiltros: (filtros: FiltrosDeSupervision) => void;
  onRestablecerFiltros: () => void;
};

const ESTADOS = Object.keys(ETIQUETA_DE_ESTADO) as EstadoApi[];
const MODOS = Object.keys(ETIQUETA_DE_MODO) as ModoApi[];

// Filtros que se mandan al backend (GET /api/admin/solicitudes): estado, modo, fechas del servicio,
// búsqueda (id, cliente, correo, colaborador, servicio o dirección) y «requieren atención».
export function BarraDeFiltrosDeSolicitudes({ filtros, total, visibles, onCambiarFiltros, onRestablecerFiltros }: BarraDeFiltrosDeSolicitudesProps) {
  const cambiar = <K extends keyof FiltrosDeSupervision>(campo: K, valor: FiltrosDeSupervision[K]) => onCambiarFiltros({ ...filtros, [campo]: valor });
  const hayFiltros = Boolean(filtros.estado || filtros.modo || filtros.busqueda.trim() || filtros.desde || filtros.hasta || filtros.atencion);

  return (
    <div className="surface leaf-sm p-5">
      <div className="flex flex-wrap items-end gap-4">
        <label className="min-w-[14rem] flex-1">
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Buscar</span>
          <span className="relative block">
            <Icono nombre="buscar" className="absolute left-3 top-1/2 -translate-y-1/2 text-slate" />
            <input
              type="search"
              value={filtros.busqueda}
              onChange={(e) => cambiar("busqueda", e.target.value)}
              placeholder="Id, cliente, correo, colaborador, servicio o dirección"
              maxLength={100}
              className="field pl-10"
            />
          </span>
        </label>
        <label>
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Estado</span>
          <select value={filtros.estado} onChange={(e) => cambiar("estado", e.target.value as EstadoApi | "")} className="field">
            <option value="">Todos</option>
            {ESTADOS.map((e) => (
              <option key={e} value={e}>
                {ETIQUETA_DE_ESTADO[e]}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Asignación</span>
          <select value={filtros.modo} onChange={(e) => cambiar("modo", e.target.value as ModoApi | "")} className="field">
            <option value="">Todas</option>
            {MODOS.map((m) => (
              <option key={m} value={m}>
                {ETIQUETA_DE_MODO[m]}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Servicio desde</span>
          <input type="date" value={filtros.desde} onChange={(e) => cambiar("desde", e.target.value)} className="field" />
        </label>
        <label>
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Hasta</span>
          <input type="date" value={filtros.hasta} onChange={(e) => cambiar("hasta", e.target.value)} className="field" />
        </label>
      </div>
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        <label className="inline-flex cursor-pointer items-center gap-2 text-sm font-bold text-navy">
          <input type="checkbox" checked={filtros.atencion} onChange={(e) => cambiar("atencion", e.target.checked)} className="h-4 w-4 accent-[var(--color-navy,#14213d)]" />
          Solo las que requieren atención
        </label>
        <div className="flex items-center gap-3 text-sm text-slate">
          <span>
            {visibles} de {total} solicitudes
          </span>
          {hayFiltros && (
            <button onClick={onRestablecerFiltros} className="btn btn-quiet">
              <Icono nombre="restablecer" /> Quitar filtros
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
