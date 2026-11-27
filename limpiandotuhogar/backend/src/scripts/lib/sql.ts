/**
 * Divide un archivo .sql en sentencias. Respeta cadenas ('…', "…", `…`) con escapes,
 * elimina comentarios de línea (-- …) y CONSERVA los comentarios de bloque, porque
 * los de la forma /*T! … *\/ o /*! … *\/ son ejecutables en TiDB/MySQL.
 */
export function dividirSentencias(texto: string): string[] {
  const sentencias: string[] = [];
  let actual = "";
  let comilla: string | null = null;
  let i = 0;
  const n = texto.length;

  while (i < n) {
    const c = texto[i] as string;
    const sig = texto[i + 1];

    if (comilla) {
      actual += c;
      if (c === "\\" && comilla !== "`" && i + 1 < n) {
        actual += texto[i + 1];
        i += 2;
        continue;
      }
      if (c === comilla) {
        if (sig === comilla) {
          actual += sig;
          i += 2;
          continue;
        }
        comilla = null;
      }
      i++;
      continue;
    }

    if (c === "'" || c === '"' || c === "`") {
      comilla = c;
      actual += c;
      i++;
      continue;
    }

    const tras = texto[i + 2];
    if (c === "-" && sig === "-" && (tras === undefined || /\s/.test(tras))) {
      const fin = texto.indexOf("\n", i);
      i = fin === -1 ? n : fin;
      continue;
    }

    if (c === "/" && sig === "*") {
      const fin = texto.indexOf("*/", i + 2);
      const hasta = fin === -1 ? n : fin + 2;
      actual += texto.slice(i, hasta);
      i = hasta;
      continue;
    }

    if (c === ";") {
      if (actual.trim()) sentencias.push(actual.trim());
      actual = "";
      i++;
      continue;
    }

    actual += c;
    i++;
  }

  if (actual.trim()) sentencias.push(actual.trim());
  return sentencias;
}
