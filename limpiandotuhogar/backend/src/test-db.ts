import { prisma } from "./config/prisma";

async function main() {
  const result = await prisma.$queryRaw`SELECT 1 AS ok`;
  console.log("Conexión exitosa:", result);
}

main()
  .catch((err: any) => {
    console.error("Error de conexión:", err?.message ?? err);
    if (err?.meta?.driverAdapterError?.cause) {
      console.error("Causa del driver:", err.meta.driverAdapterError.cause);
    }
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });