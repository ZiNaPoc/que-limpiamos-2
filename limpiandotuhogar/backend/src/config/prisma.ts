import "dotenv/config";
import { PrismaMariaDb } from "@prisma/adapter-mariadb";
import { PrismaClient } from "../../generated/prisma/client";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Falta la variable ${name}`);
  return value;
}

const rawPort = process.env.DATABASE_PORT;
const port = rawPort ? Number(rawPort) : 4000;
if (!Number.isInteger(port) || port <= 0) {
  throw new Error(`DATABASE_PORT inválido: ${rawPort}`);
}

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

function createPrismaClient() {
  const adapter = new PrismaMariaDb({
    host: requireEnv("DATABASE_HOST"),
    port,
    user: requireEnv("DATABASE_USER"),
    password: requireEnv("DATABASE_PASSWORD"),
    database: requireEnv("DATABASE_NAME"),
    connectionLimit: 5,
    connectTimeout: 10_000,
    ssl: { minVersion: "TLSv1.2", rejectUnauthorized: true },
  });

  return new PrismaClient({ adapter });
}

export const prisma = globalForPrisma.prisma ?? createPrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
