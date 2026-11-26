import { useState, type ReactNode } from "react";
import { CampoDeFormulario } from "../comunes/CampoDeFormulario";
import { VentanaModal } from "../comunes/VentanasModales";

const MAX_MOTIVO = 500;

type VentanaDeMotivoProps = {
  titulo: string;
  descripcion: string;
  etiquetaDelMotivo?: string;
  etiquetaDeConfirmar: string;
  peligrosa?: boolean;
  // Campos extra del formulario (p. ej. la calificación nueva). Se dibujan antes del motivo.
  children?: ReactNode;
  // Devuelve null si salió bien, o el mensaje de error del backend.
  onConfirmar: (motivo: string) => Promise<string | null>;
  onCerrar: () => void;
};

// Ventana de moderación: toda acción exige un MOTIVO (queda en la auditoría junto con lo
// anterior y lo nuevo). El backend vuelve a validar todo; aquí solo se evita enviar vacío.
export function VentanaDeMotivo({ titulo, descripcion, etiquetaDelMotivo = "Motivo (queda en la auditoría)", etiquetaDeConfirmar, peligrosa = false, children, onConfirmar, onCerrar }: VentanaDeMotivoProps) {
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function confirmar() {
    const limpio = motivo.trim();
    if (!limpio) {
      setError("Escribe el motivo: es obligatorio y queda registrado.");
      return;
    }
    setEnviando(true);
    setError("");
    const resultado = await onConfirmar(limpio);
    setEnviando(false);
    if (resultado) setError(resultado);
  }

  return (
    <VentanaModal idDelTitulo="titulo-de-moderacion" onCerrar={onCerrar} claseDeAncho="max-w-lg">
      <h2 id="titulo-de-moderacion" className="text-2xl font-extrabold text-navy">
        {titulo}
      </h2>
      <p className="mt-2 text-sm text-slate">{descripcion}</p>
      {children && <div className="mt-5 space-y-4">{children}</div>}
      <div className="mt-5">
        <CampoDeFormulario id="motivo-de-moderacion" etiqueta={etiquetaDelMotivo} error={error}>
          <textarea id="motivo-de-moderacion" rows={3} maxLength={MAX_MOTIVO} value={motivo} onChange={(evento) => setMotivo(evento.target.value)} aria-invalid={Boolean(error)} className="field resize-y" />
        </CampoDeFormulario>
        <p className="mt-1.5 text-right text-xs text-slate">
          {motivo.trim().length}/{MAX_MOTIVO}
        </p>
      </div>
      <div className="mt-5 flex justify-end gap-3">
        <button onClick={onCerrar} className="btn btn-quiet" disabled={enviando}>
          Cancelar
        </button>
        <button onClick={() => void confirmar()} className={`btn btn-primary ${peligrosa ? "bg-err" : ""}`} disabled={enviando}>
          {enviando ? "Guardando…" : etiquetaDeConfirmar}
        </button>
      </div>
    </VentanaModal>
  );
}
