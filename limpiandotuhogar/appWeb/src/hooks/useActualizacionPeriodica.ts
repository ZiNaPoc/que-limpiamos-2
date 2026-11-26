import { useEffect, useRef } from "react";

// Llama a `actualizar` cada `intervaloMs` SOLO mientras la página está visible (docs/backend/25 v2:
// panel cada 20 s). Al volver a la pestaña, actualiza enseguida. No se solapa consigo misma.
// Con `inmediato`, también actualiza al activarse (en vez de esperar el primer intervalo).
export function useActualizacionPeriodica(actualizar: () => Promise<void>, intervaloMs: number, activa = true, inmediato = false) {
  const funcion = useRef(actualizar);
  useEffect(() => {
    funcion.current = actualizar;
  });

  useEffect(() => {
    if (!activa) return;
    let enCurso = false;
    let temporizador: number | undefined;

    const paso = async () => {
      if (enCurso || document.visibilityState !== "visible") return;
      enCurso = true;
      try {
        await funcion.current();
      } finally {
        enCurso = false;
      }
    };
    const programar = () => {
      window.clearInterval(temporizador);
      if (document.visibilityState === "visible") temporizador = window.setInterval(() => void paso(), intervaloMs);
    };
    const alCambiarVisibilidad = () => {
      programar();
      if (document.visibilityState === "visible") void paso();
    };

    programar();
    if (inmediato) void paso();
    document.addEventListener("visibilitychange", alCambiarVisibilidad);
    return () => {
      window.clearInterval(temporizador);
      document.removeEventListener("visibilitychange", alCambiarVisibilidad);
    };
  }, [intervaloMs, activa, inmediato]);
}
