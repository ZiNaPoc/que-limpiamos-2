// Prueba de conexión de solo lectura: `npm run db:probar`.
import { prisma } from "../config/prisma";

async function main() {
  const resultado = await prisma.$queryRaw<{ ok: number }[]>`SELECT 1 AS ok`;
  console.log("Conexión exitosa:", resultado);
}

main()
  .catch((err: unknown) => {
    const e = err as { message?: string; meta?: { driverAdapterError?: { cause?: unknown } } };
    console.error("Error de conexión:", e?.message ?? err);
    if (e?.meta?.driverAdapterError?.cause) {
      console.error("Causa del driver:", e.meta.driverAdapterError.cause);
    }
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
