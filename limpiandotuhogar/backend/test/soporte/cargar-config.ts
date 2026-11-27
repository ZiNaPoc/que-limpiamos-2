/**
 * Carga UNA configuración en un proceso aparte (lo usa test/config.test.ts) y escribe
 * "CARGADO" si no falló. Uso: tsx test/soporte/cargar-config.ts <auth|almacenamiento|entorno-demo>
 */
async function main() {
  const cual = process.argv[2];
  if (cual === "auth") await import("../../src/config/auth.js");
  else if (cual === "almacenamiento") await import("../../src/config/almacenamiento.js");
  else if (cual === "entorno-demo") await import("../../src/scripts/lib/entorno-demo.js");
  else throw new Error(`Configuración desconocida: ${cual}`);
  console.log("CARGADO");
}

main().catch((error: unknown) => {
  console.error((error as Error).message);
  process.exitCode = 1;
});
