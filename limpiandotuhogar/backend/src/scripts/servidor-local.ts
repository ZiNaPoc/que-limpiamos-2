/**
 * Servidor LOCAL para probar las apps en un teléfono de la misma Wi-Fi (doc 24).
 *   npm run servidor:local                    IP privada de la Wi-Fi detectada sola
 *   npm run servidor:local -- --ip=192.168.0.78 --puerto=3000
 *
 *  - BD: quelimpiamos_dev en el TiDB LOCAL; se verifica host, puerto y nombre antes de escuchar.
 *  - Escucha SOLO en 127.0.0.1 y en la IP privada indicada (no en 0.0.0.0): nada fuera de la red
 *    local. Se niega a usar una IP que no sea privada (10/8, 172.16/12, 192.168/16).
 *  - Los datos se conservan entre reinicios (a diferencia de demo:local).
 */
// Primero el entorno: fija la BD local y los secretos antes de cargar la configuración.
import "./lib/entorno-servidor-local";

import type { Server } from "node:http";
import { networkInterfaces } from "node:os";

import app from "../app";
import { almacenamientoConfig } from "../config/almacenamiento";
import { prisma } from "../config/prisma";
import { iniciarTareaCiclo } from "../dominio/tarea-ciclo";
import { verificarDestinoLocal } from "./lib/destino-local";

const argumento = (nombre: string) => process.argv.find((a) => a.startsWith(`--${nombre}=`))?.split("=")[1];
const PUERTO = Number(argumento("puerto") ?? 3000);

function esIpPrivada(ip: string): boolean {
  const p = ip.split(".").map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return false;
  const [a = -1, b = -1] = p;
  return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

/** IPv4 privada de la Wi-Fi (o, si no hay, de la primera interfaz física con 192.168.x.x). */
function ipDeLaRed(): string | undefined {
  const candidatas = Object.entries(networkInterfaces()).flatMap(([nombre, lista]) =>
    (lista ?? []).filter((i) => i.family === "IPv4" && !i.internal && esIpPrivada(i.address)).map((i) => ({ nombre, ip: i.address })),
  );
  const wifi = candidatas.find((c) => /wi-?fi|wlan|inal/i.test(c.nombre));
  return (wifi ?? candidatas.find((c) => c.ip.startsWith("192.168.") && !/vethernet|wsl|virtual/i.test(c.nombre)))?.ip;
}

async function main() {
  if (!Number.isInteger(PUERTO) || PUERTO < 1024 || PUERTO > 65535) throw new Error(`Puerto no válido: ${PUERTO}`);
  const ip = argumento("ip") ?? ipDeLaRed();
  if (!ip) throw new Error("No encontré una IP privada de Wi-Fi; indícala con --ip=");
  if (!esIpPrivada(ip)) throw new Error(`${ip} no es una IP privada: el servidor local no se expone fuera de la red local`);

  const destino = await verificarDestinoLocal();
  console.log(`BD verificada: ${destino.host}:${destino.port} / ${destino.bd} (${destino.tablas} tablas), TiDB local.`);

  const servidores: Server[] = [];
  for (const host of ["127.0.0.1", ip]) {
    await new Promise<void>((listo, fallo) => {
      const s = app.listen(PUERTO, host, () => listo());
      s.once("error", fallo);
      servidores.push(s);
    });
  }
  console.log(`\nServidor local escuchando en:`);
  console.log(`  http://127.0.0.1:${PUERTO}   (esta PC)`);
  console.log(`  http://${ip}:${PUERTO}   (teléfono en la misma Wi-Fi; APK con API_URL=http://${ip}:${PUERTO})`);
  console.log(`Fotos de reportes: ${almacenamientoConfig.directorioLocal}`);
  // Doc 25 v2: vencimientos y confirmación D54, cada minuto (igual que server.ts).
  const detenerTarea = iniciarTareaCiclo();
  console.log("Tarea periódica del ciclo de solicitudes: cada minuto.");
  console.log("Ctrl+C para detener (los datos se conservan).");

  const detener = () => {
    detenerTarea();
    for (const s of servidores) s.close();
    void prisma.$disconnect().finally(() => process.exit(0));
    setTimeout(() => process.exit(0), 5_000).unref();
  };
  process.on("SIGINT", detener);
  process.on("SIGTERM", detener);
}

main().catch(async (error: unknown) => {
  console.error("ERROR:", (error as Error)?.message ?? error);
  await prisma.$disconnect().catch(() => undefined);
  process.exit(1);
});
