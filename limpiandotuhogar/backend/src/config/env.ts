import "dotenv/config";

/**
 * Lectura y validación centralizada de variables de entorno.
 * Si falta una variable obligatoria, el proceso falla al arrancar
 * (mejor un deploy fallido que un servidor a medias).
 */

function requerida(nombre: string): string {
  const valor = process.env[nombre];
  if (!valor || !valor.trim()) {
    throw new Error(`Falta la variable de entorno ${nombre}`);
  }
  return valor.trim();
}

function entero(nombre: string, porDefecto: number): number {
  const crudo = process.env[nombre];
  if (crudo === undefined || crudo.trim() === "") return porDefecto;
  const valor = Number(crudo);
  if (!Number.isInteger(valor) || valor <= 0) {
    throw new Error(`La variable ${nombre} debe ser un entero positivo`);
  }
  return valor;
}

function lista(nombre: string, porDefecto: string): string[] {
  return (process.env[nombre] ?? porDefecto)
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
}

const nodeEnv = process.env.NODE_ENV?.trim() || "development";

// BD LOCAL (TiDB en Docker, doc 22): solo en 127.0.0.1/localhost se permite conectar sin TLS
// (DATABASE_TLS=false) y sin contraseña. Con cualquier otro host el TLS es obligatorio.
const hostBd = requerida("DATABASE_HOST");
const bdEsLocal = ["127.0.0.1", "localhost", "::1"].includes(hostBd);
const tlsBd = process.env.DATABASE_TLS?.trim().toLowerCase() !== "false";
if (!tlsBd && !bdEsLocal) {
  throw new Error("DATABASE_TLS=false solo se permite con una BD local (127.0.0.1/localhost)");
}

export const env = {
  nodeEnv,
  esProduccion: nodeEnv === "production",
  port: entero("PORT", 3000),
  corsOrigins: lista("CORS_ORIGINS", "http://localhost:5173"),
  db: {
    host: hostBd,
    port: entero("DATABASE_PORT", 4000),
    user: requerida("DATABASE_USER"),
    password: bdEsLocal ? (process.env.DATABASE_PASSWORD ?? "") : requerida("DATABASE_PASSWORD"),
    name: requerida("DATABASE_NAME"),
    esLocal: bdEsLocal,
    tls: tlsBd,
  },
} as const;
