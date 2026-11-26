/**
 * Solicitudes FICTICIAS para probar la Fase 3b en el teléfono (doc 24 §6). La creación real de
 * solicitudes aún no existe (las apps usan rutas obsoletas).
 *   npm run solicitudes:local     idempotente: crea solo las que falten, nunca duplica
 *
 * Destino: SOLO quelimpiamos_dev en el TiDB LOCAL; se verifica host, puerto y nombre antes de escribir.
 * Requiere antes `npm run datos:local` (servicios y las 2 cuentas ficticias).
 *
 *  S1  REALIZADO hace ~1 día, sin reseñas       → califican el cliente y el trabajador; ambos reportan
 *  S2  REALIZADO hace ~2 días, con la reseña del CLIENTE → el cliente ya no califica; el trabajador sí
 *  S3  CONFIRMADO, hora programada recién pasada, sin iniciar → ambos reportan (con fotos desde la app)
 *
 * Cada solicitud se marca en `notas` con "[prueba-telefono:S1|S2|S3]"; así el script las reconoce y no
 * las duplica. Con REALIZADO se usa realizado_via = AUTOMATICO (D54): nadie confirmó y el pago NO se
 * libera, así que no corresponde ningún movimiento. No crea pagos, adeudos, movimientos,
 * notificaciones, reportes ni fotos, y no modifica registros que ya existían.
 */
// Primero el entorno: fija la BD local antes de cargar la configuración.
import "./lib/entorno-servidor-local";

import { Prisma } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { crearResena, PLAZO_HORAS } from "../dominio/resenas";
import { verificarDestinoLocal } from "./lib/destino-local";

const CORREO_CLIENTE = "cliente.prueba@quelimpiamos.test";
const CORREO_TRABAJADOR = "trabajador.prueba@quelimpiamos.test";
const DIRECCION = "Calle Ficticia 456, Cancún (dato de prueba)";
const MIN = 60_000;
const HORA = 60 * MIN;

type Plan = {
  clave: "S1" | "S2" | "S3";
  servicio: string;
  descripcion: string;
  /** Hora programada relativa a ahora (negativo = en el pasado). */
  programadaHace: number;
  realizado: boolean;
  areas: string[];
};
const PLANES: Plan[] = [
  { clave: "S1", servicio: "Limpieza regular", descripcion: "REALIZADO reciente, sin reseñas", programadaHace: 26 * HORA, realizado: true, areas: ["Cocina", "Sala", "Baños"] },
  { clave: "S2", servicio: "Limpieza profunda", descripcion: "REALIZADO reciente, con la reseña del cliente", programadaHace: 50 * HORA, realizado: true, areas: ["Cocina", "Recámaras", "Baños"] },
  { clave: "S3", servicio: "Limpieza post-obra", descripcion: "CONFIRMADO, hora programada recién pasada, sin iniciar", programadaHace: 20 * MIN, realizado: false, areas: ["Sala", "Áreas comunes"] },
];
const marca = (clave: string) => `[prueba-telefono:${clave}]`;
/** Minutos exactos (las columnas son DATETIME sin fracciones). */
const aMinuto = (ms: number) => new Date(Math.floor(ms / MIN) * MIN);
const dinero = (n: number) => new Prisma.Decimal(n.toFixed(2));

async function main() {
  const destino = await verificarDestinoLocal();
  console.log(`Destino verificado: ${destino.host}:${destino.port} / ${destino.bd} (${destino.tablas} tablas), TiDB local.`);

  const cliente = await prisma.usuarios.findUnique({ where: { correo: CORREO_CLIENTE } });
  const trabajador = await prisma.trabajadores.findUnique({ where: { correo: CORREO_TRABAJADOR } });
  if (!cliente || cliente.rol !== "CLIENTE" || !trabajador) throw new Error("Faltan las cuentas ficticias: ejecuta antes  npm run datos:local");
  if (trabajador.estado !== "ACTIVO" || trabajador.estado_verificacion !== "VERIFICADO") throw new Error("El trabajador de prueba no está ACTIVO y VERIFICADO: ejecuta  npm run datos:local");
  const parametro = await prisma.parametros_negocio.findUnique({ where: { clave: "PORCENTAJE_TRABAJADOR" } });
  if (!parametro) throw new Error("Falta el parámetro PORCENTAJE_TRABAJADOR (viene en el esquema 002)");
  const porcentaje = Number(parametro.valor);

  for (const plan of PLANES) {
    const existente = await prisma.solicitudes.findFirst({ where: { cliente_id: cliente.id, notas: { startsWith: marca(plan.clave) } } });
    let solicitud = existente;
    if (!solicitud) {
      const servicio = await prisma.servicios.findUnique({ where: { nombre: plan.servicio } });
      if (!servicio || servicio.estado !== "ACTIVO") throw new Error(`Falta el servicio activo "${plan.servicio}": ejecuta  npm run datos:local`);
      const exigidas = await prisma.servicio_especialidades.findMany({ where: { servicio_id: servicio.id }, include: { especialidades: true } });
      const areas = await prisma.areas_limpieza.findMany({ where: { nombre: { in: plan.areas } } });

      const ahora = Date.now();
      const programada = aMinuto(ahora - plan.programadaHace);
      const fin = new Date(programada.getTime() + servicio.duracion_estimada_min * MIN);
      const creada = new Date(programada.getTime() - 2 * 24 * HORA);
      const aceptada = new Date(creada.getTime() + 2 * HORA);
      // D54, confirmación automática: T + 30 min se pide confirmar a ambos; 30 min después, REALIZADO.
      const confirmacionSolicitada = new Date(fin.getTime() + 30 * MIN);
      const realizado = new Date(fin.getTime() + 60 * MIN);
      if (plan.realizado && realizado.getTime() > ahora) throw new Error(`${plan.clave}: la finalización quedaría en el futuro`);
      const precio = Number(servicio.precio_base);
      const ganancia = (precio * porcentaje) / 100;

      solicitud = await prisma.$transaction(async (tx) => {
        const s = await tx.solicitudes.create({
          data: {
            cliente_id: cliente.id,
            servicio_id: servicio.id,
            servicio_nombre_aplicado: servicio.nombre,
            inmueble_tipo_aplicado: "CASA",
            habitaciones_aplicado: 2,
            banos_aplicado: 1,
            medios_banos_aplicado: 0,
            pisos_aplicado: 1,
            trabajador_id: trabajador.id,
            fecha_hora_programada: programada,
            duracion_estimada_min: servicio.duracion_estimada_min,
            fecha_hora_fin_estimada: fin,
            direccion_servicio: DIRECCION,
            notas: `${marca(plan.clave)} Solicitud ficticia para probar la Fase 3b: ${plan.descripcion}.`,
            precio_estimado: dinero(precio),
            precio_base_aplicado: dinero(precio),
            precio_tamano_aplicado: dinero(0),
            precio_ajuste_tipo_aplicado: dinero(0),
            precio_extras_aplicado: dinero(0),
            precio_descuento_aplicado: dinero(0),
            porcentaje_trabajador_aplicado: dinero(porcentaje),
            ganancia_trabajador: dinero(ganancia),
            comision_plataforma: dinero(precio - ganancia),
            metodo_pago: "EFECTIVO",
            estado_pago: "PENDIENTE",
            modo_eleccion: "MANUAL",
            estado: plan.realizado ? "REALIZADO" : "CONFIRMADO",
            ...(plan.realizado ? { confirmacion_solicitada_en: confirmacionSolicitada, realizado_en: realizado, realizado_via: "AUTOMATICO" as const } : {}),
            created_at: creada,
            updated_at: plan.realizado ? realizado : aceptada,
          },
        });
        await tx.solicitud_especialidades.createMany({ data: exigidas.map((e) => ({ solicitud_id: s.id, especialidad_id: e.especialidad_id, nombre_aplicado: e.especialidades.nombre })) });
        await tx.solicitud_areas.createMany({ data: areas.map((a) => ({ solicitud_id: s.id, area_id: a.id, nombre_aplicado: a.nombre })) });
        // Selección manual: el cliente invitó al trabajador y este aceptó.
        await tx.solicitud_trabajadores.create({
          data: { solicitud_id: s.id, trabajador_id: trabajador.id, origen: "INVITACION", estado: "ACEPTADA", created_at: creada, respondida_en: aceptada, updated_at: aceptada },
        });
        const historial = [
          { estado_anterior: null, estado_nuevo: "PENDIENTE" as const, actor: "CLIENTE" as const, actor_id: cliente.id, created_at: creada, motivo: "Solicitud ficticia (datos de prueba)" },
          { estado_anterior: "PENDIENTE" as const, estado_nuevo: "CONFIRMADO" as const, actor: "TRABAJADOR" as const, actor_id: trabajador.id, created_at: aceptada, motivo: "Aceptó la invitación" },
          ...(plan.realizado
            ? [
                { estado_anterior: "CONFIRMADO" as const, estado_nuevo: "EN_PROCESO" as const, actor: "TRABAJADOR" as const, actor_id: trabajador.id, created_at: programada, motivo: "Inició el servicio" },
                { estado_anterior: "EN_PROCESO" as const, estado_nuevo: "REALIZADO" as const, actor: "SISTEMA" as const, actor_id: null, created_at: realizado, motivo: "Confirmación automática: nadie respondió (D54); el pago no se libera" },
              ]
            : []),
        ];
        await tx.solicitud_historial.createMany({ data: historial.map((h) => ({ ...h, solicitud_id: s.id })) });
        return s;
      });
      console.log(`${plan.clave}: creada la solicitud ${solicitud.id}.`);
    } else {
      console.log(`${plan.clave}: ya existía (solicitud ${solicitud.id}); no se toca.`);
    }

    // S2: la reseña del CLIENTE, con las reglas reales (crearResena). Solo si aún no existe.
    if (plan.clave === "S2") {
      const previa = await prisma.resenas.findFirst({ where: { solicitud_id: solicitud.id, autor_rol: "CLIENTE" } });
      if (previa) console.log(`S2: la reseña del cliente ya existía (reseña ${previa.id}); no se toca.`);
      else {
        const r = await crearResena({ solicitudId: solicitud.id, autorRol: "CLIENTE", autorId: cliente.id, puntuacion: 5, comentario: "Muy puntual y ordenado. (Reseña ficticia de prueba)" });
        console.log(`S2: creada la reseña ${r.id} del cliente (${r.puntuacion} escobas).`);
      }
    }
  }

  // Resumen, con los mismos criterios que el historial de las apps.
  console.log("\nResumen:");
  for (const plan of PLANES) {
    const s = await prisma.solicitudes.findFirstOrThrow({ where: { cliente_id: cliente.id, notas: { startsWith: marca(plan.clave) } } });
    const resenas = await prisma.resenas.findMany({ where: { solicitud_id: s.id }, select: { autor_rol: true } });
    const hasta = s.realizado_en ? new Date(s.realizado_en.getTime() + PLAZO_HORAS * HORA) : null;
    const vigente = hasta !== null && Date.now() <= hasta.getTime();
    console.log(
      `  ${plan.clave} id ${s.id} · ${s.servicio_nombre_aplicado} · ${s.estado} · programada ${s.fecha_hora_programada.toISOString()}` +
        (s.realizado_en ? ` · realizado ${s.realizado_en.toISOString()} · calificar hasta ${hasta!.toISOString()}${vigente ? "" : " (VENCIDO)"}` : "") +
        ` · reseñas: ${resenas.map((r) => r.autor_rol).join(", ") || "ninguna"}`,
    );
  }
}

main()
  .catch((error: unknown) => {
    console.error("ERROR:", (error as Error)?.message ?? error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
