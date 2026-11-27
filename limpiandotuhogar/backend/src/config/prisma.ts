import { PrismaMariaDb } from "@prisma/adapter-mariadb";
import { PrismaClient } from "../../generated/prisma/client";
import { env } from "./env";

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

function crearPrismaClient() {
  const adapter = new PrismaMariaDb({
    host: env.db.host,
    port: env.db.port,
    user: env.db.user,
    password: env.db.password,
    database: env.db.name,
    connectionLimit: 5,
    connectTimeout: 10_000,
    // TLS siempre, salvo la BD LOCAL de desarrollo/pruebas (env.db.tls solo es false en localhost).
    ...(env.db.tls ? { ssl: { minVersion: "TLSv1.2", rejectUnauthorized: true } } : {}),
  });

  // TiDB Cloud está lejos (latencia por consulta): las transacciones interactivas del ciclo (aceptar, resolver)
  // con su bloqueo FOR UPDATE pueden pasar de los 5 s por defecto de Prisma. Se amplía el margen.
  return new PrismaClient({ adapter, transactionOptions: { maxWait: 10_000, timeout: 20_000 } });
}

export const prisma = globalForPrisma.prisma ?? crearPrismaClient();

// En desarrollo, `tsx watch` recarga módulos: se reutiliza el mismo cliente.
if (!env.esProduccion) {
  globalForPrisma.prisma = prisma;
}
