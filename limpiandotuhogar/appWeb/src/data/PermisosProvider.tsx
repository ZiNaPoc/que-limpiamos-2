import { useEffect, useState, type ReactNode } from "react";

import { consultarMisPermisos, PermisosContext, type PermisoDeAdmin } from "./permisos";

// Carga una vez los permisos EFECTIVOS del admin con sesión. Si falla, se asume que no tiene ninguno
// (el backend igual rechaza con 403 lo que no esté permitido).
export function PermisosProvider({ children }: { children: ReactNode }) {
  const [permisos, setPermisos] = useState<PermisoDeAdmin[]>([]);
  const [implicitos, setImplicitos] = useState<PermisoDeAdmin[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let activo = true;
    consultarMisPermisos()
      .then((datos) => {
        if (!activo) return;
        setPermisos(datos.permisos);
        setImplicitos(datos.implicitos);
      })
      .catch((e: unknown) => {
        if (activo) setError(e instanceof Error ? e.message : "No se pudieron consultar tus permisos");
      })
      .finally(() => {
        if (activo) setCargando(false);
      });
    return () => {
      activo = false;
    };
  }, []);

  return (
    <PermisosContext.Provider value={{ cargando, error, permisos, implicitos, tiene: (p) => permisos.includes(p) }}>{children}</PermisosContext.Provider>
  );
}
