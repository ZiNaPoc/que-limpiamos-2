import app from "./app";
import { env } from "./config/env";
import { prisma } from "./config/prisma";
import { iniciarTareaCiclo } from "./dominio/tarea-ciclo";

const server = app.listen(env.port, () => {
  console.log(`Servidor escuchando en el puerto ${env.port} (${env.nodeEnv})`);
});

// Tarea periódica del ciclo de solicitudes (doc 25 v2): vencimientos y confirmación D54, cada minuto.
const detenerTarea = iniciarTareaCiclo();

// Render envía SIGTERM en cada redeploy: cerrar HTTP y la conexión a la BD.
function cerrar(senal: string) {
  console.log(`${senal} recibido, cerrando servidor...`);
  detenerTarea();
  server.close(async () => {
    await prisma.$disconnect().catch(() => undefined);
    process.exit(0);
  });
  // Si algo se queda colgado, forzar la salida.
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => cerrar("SIGTERM"));
process.on("SIGINT", () => cerrar("SIGINT"));
