import { useCallback, useEffect, useState, type ReactNode } from "react";

import { usePermisos } from "./permisos";
import { ResenasContext } from "./ResenasContext";
import { consultarResenasAdmin, RESENAS_CONECTADAS_AL_BACKEND, type EstadoDeLasResenas } from "./resenas";

// Carga las reseñas de moderación. Solo pide datos si el admin tiene MODERAR_CONTENIDO (si no,
// el backend respondería 403): así el panel no intenta mostrar lo que no le corresponde.
// Incluye las eliminadas (la pantalla decide si las muestra); los promedios las excluyen.
export function ResenasProvider({ children }: { children: ReactNode }) {
  const { cargando: cargandoPermisos, tiene } = usePermisos();
  const puedeModerar = tiene("MODERAR_CONTENIDO");
  const [estado, setEstado] = useState<EstadoDeLasResenas>({ tipo: "cargando" });

  const recargarResenas = useCallback(async () => {
    if (!RESENAS_CONECTADAS_AL_BACKEND) {
      setEstado({ tipo: "pendiente-de-backend" });
      return;
    }
    if (!puedeModerar) {
      setEstado({ tipo: "sin-permiso" });
      return;
    }
    setEstado({ tipo: "cargando" });
    try {
      setEstado({ tipo: "listo", resenas: await consultarResenasAdmin({ incluirEliminadas: true }) });
    } catch (error) {
      setEstado({ tipo: "error", mensaje: error instanceof Error ? error.message : "No se pudieron cargar las reseñas" });
    }
  }, [puedeModerar]);

  // Primera carga, cuando ya se sabe qué permisos tiene el admin.
  useEffect(() => {
    if (cargandoPermisos) return;
    let activo = true;
    const cargar = async () => {
      if (activo) await recargarResenas();
    };
    void cargar();
    return () => {
      activo = false;
    };
  }, [cargandoPermisos, recargarResenas]);

  return <ResenasContext.Provider value={{ estado, recargarResenas }}>{children}</ResenasContext.Provider>;
}
