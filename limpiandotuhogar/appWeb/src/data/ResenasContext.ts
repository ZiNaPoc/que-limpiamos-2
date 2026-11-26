import { createContext, useContext } from "react";

import type { EstadoDeLasResenas } from "./resenas";

export type ValorDelContextoDeResenas = {
  estado: EstadoDeLasResenas;
  recargarResenas: () => Promise<void>;
};

export const ResenasContext = createContext<ValorDelContextoDeResenas | null>(null);

export function useResenas(): ValorDelContextoDeResenas {
  const valor = useContext(ResenasContext);
  if (!valor) {
    throw new Error("useResenas debe usarse dentro de ResenasProvider");
  }
  return valor;
}
