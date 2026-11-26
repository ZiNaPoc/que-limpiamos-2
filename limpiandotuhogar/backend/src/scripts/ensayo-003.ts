/**
 * Ensayo COMPLETO del SQL 003 (sobre el 002 v10) en una BD de ensayo existente y vacía:
 *   ENSAYO_DATABASE_NAME=queLimpiamos_proyecto npm run db:ensayo-003
 *
 * Producción solo se LEE. Pasos:
 *  1. Respaldo de producción → 2. restaurarlo en la BD de ensayo → 3. comparar
 *  4. Aplicar el 002 (84/84)
 *  5. Datos "heredados" (como si el 002 ya se hubiera usado): notificaciones y un movimiento.
 *     Las guardas del 003 deben detenerlo si hay resoluciones o AJUSTE previos.
 *  6. Aplicar el 003 → 14/14, sin perder datos (las notificaciones reciben 'LEGADO:<id>')
 *  7. Introspección == schema previsto 003
 *  8. Pruebas con el cliente Prisma previsto (D60, D61, D62)
 *  9. Rollback del 003 → idéntico al estado del paso 5; rollback del 002 → idéntico a producción
 * 10. Vaciar la BD de ensayo y comprobar que producción no cambió
 * Reporte: backups/<fecha>-ensayo-003/reporte.json (sin secretos).
 */
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { PrismaMariaDb } from "@prisma/adapter-mariadb";

import { env } from "../config/env";
import { conectar, esBdExistentePermitidaParaEnsayo, ocultarSecretos, urlParaBd } from "./lib/db-directa";
import { compararMapas, diferenciasSchema, esperarErrorPrisma, mensajeDeError, prismaCli } from "./lib/ensayo-utils";
import { verificar002 } from "./lib/objetos-002";
import { verificar003 } from "./lib/objetos-003";
import { estructura, generarRespaldo, huellasDeDatos, listarTablas } from "./lib/respaldo";
import { dividirSentencias } from "./lib/sql";

const RAIZ = process.cwd(); // limpiandotuhogar/backend
const SQL = (archivo: string) => path.resolve(RAIZ, "../../docs/backend/sql", archivo);
const SQL_002 = SQL("002_detalle_solicitud_especialidades_invitaciones.sql");
const SQL_002_ROLLBACK = SQL("002_rollback.sql");
const SQL_003 = SQL("003_notificaciones_unicas_permisos_admin.sql");
const SQL_003_ROLLBACK = SQL("003_rollback.sql");
const SCHEMA_PREVISTO_003 = SQL("003_schema_prisma_previsto.prisma");
const CARPETA_PRISMA_ENSAYO = path.resolve(RAIZ, ".ensayo");

type Paso = { paso: string; ok: boolean; detalle: string };
const pasos: Paso[] = [];
function registrar(paso: string, ok: boolean, detalle = "") {
  pasos.push({ paso, ok, detalle });
  console.log(`${ok ? "✔" : "✘"} ${paso}${detalle ? ` — ${detalle}` : ""}`);
}

async function columnasPorTabla(q: (sql: string) => Promise<{ t: string; c: string }[]>) {
  const mapa: Record<string, string[]> = {};
  for (const r of await q("SELECT TABLE_NAME AS t, COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()")) {
    (mapa[r.t] ??= []).push(r.c);
  }
  return mapa;
}

async function main() {
  const nombreEnsayo = process.env.ENSAYO_DATABASE_NAME?.trim() || "queLimpiamos_proyecto";
  if (!esBdExistentePermitidaParaEnsayo(nombreEnsayo)) throw new Error(`"${nombreEnsayo}" no está permitida como BD de ensayo`);
  const carpeta = path.resolve(RAIZ, "backups", `${new Date().toISOString().replace(/[:.]/g, "-")}-ensayo-003`);
  mkdirSync(carpeta, { recursive: true });
  console.log(`Producción (solo lectura): ${env.db.name}`);
  console.log(`BD del ensayo:             ${nombreEnsayo} (existente, debe estar vacía)\n`);

  const prod = await conectar(env.db.name);
  const estructuraProdInicial = await estructura(prod.consultar);
  const huellasProdInicial = await huellasDeDatos(prod.consultar);
  let temp: Awaited<ReturnType<typeof conectar>> | null = null;
  let tablasPropias = false;
  let prismaEnsayo: { $disconnect: () => Promise<void> } | null = null;

  try {
    // 1–3. Respaldo, restauración y comparación
    const tablasOriginales = await listarTablas(prod.consultar);
    const respaldo = await generarRespaldo(prod.consultar);
    writeFileSync(path.join(carpeta, "restore.sql"), respaldo.contenido, "utf8");
    registrar("1. Respaldo de producción", true, `${tablasOriginales.length} tablas, sha256 ${respaldo.sha256.slice(0, 12)}…`);

    temp = await conectar(nombreEnsayo);
    const [{ bd } = { bd: "" }] = await temp.consultar<{ bd: string }>("SELECT DATABASE() AS bd");
    if (bd !== nombreEnsayo) throw new Error(`La conexión apunta a ${bd}: se aborta`);
    const previas = await listarTablas(temp.consultar);
    if (previas.length) {
      temp = null;
      throw new Error(`${nombreEnsayo} no está vacía (${previas.length} tablas): el ensayo no la toca`);
    }
    tablasPropias = true;
    for (const s of dividirSentencias(respaldo.contenido)) await temp.ejecutar(s);
    const t = temp;
    const difRestore = [
      ...compararMapas(estructuraProdInicial, await estructura(t.consultar, tablasOriginales)),
      ...compararMapas(huellasProdInicial, await huellasDeDatos(t.consultar, tablasOriginales)),
    ];
    registrar("2. Restauración idéntica a producción", difRestore.length === 0, difRestore.join(", ") || `${tablasOriginales.length} tablas iguales`);

    // 4. Aplicar el 002
    for (const s of dividirSentencias(readFileSync(SQL_002, "utf8"))) await t.ejecutar(s);
    const v002 = await verificar002(t.consultar);
    registrar("3. SQL 002 v10 aplicado", v002.estado === "APLICADO COMPLETO", `${v002.presentes}/${v002.total}`);
    const pre = await verificar003(t.consultar);
    registrar("4. Verificación previa del 003", pre.estado === "NO APLICADO" && pre.bloqueos.length === 0, `${pre.presentes}/${pre.total}, bloqueos: ${pre.bloqueos.join("; ") || "ninguno"}`);

    // 5. Datos heredados (como si el 002 ya estuviera en uso)
    const uno = async <T extends Record<string, unknown>>(sql: string, p: unknown[] = []) => (await t.consultar<T>(sql, p))[0] as T;
    const adminId = Number((await uno<{ id: number }>("SELECT id FROM usuarios WHERE rol = 'ADMIN' ORDER BY id LIMIT 1")).id);
    const servicioId = Number((await uno<{ id: number }>("SELECT id FROM servicios ORDER BY id LIMIT 1")).id);
    await t.ejecutar(
      "INSERT INTO usuarios (nombre_completo, correo, telefono, password_hash) VALUES ('Cliente heredado', 'heredado.c@ensayo.test', '9300000001', 'x')",
    );
    const legCliente = Number((await uno<{ id: number }>("SELECT id FROM usuarios WHERE correo = 'heredado.c@ensayo.test'")).id);
    await t.ejecutar(
      "INSERT INTO trabajadores (nombre_completo, telefono, correo, direccion) VALUES ('Trabajador heredado', '9300000002', 'heredado.t@ensayo.test', 'Calle 1')",
    );
    const legTrab = Number((await uno<{ id: number }>("SELECT id FROM trabajadores WHERE correo = 'heredado.t@ensayo.test'")).id);
    await t.ejecutar(
      "INSERT INTO solicitudes (cliente_id, servicio_id, trabajador_id, fecha_hora_programada, direccion_servicio, precio_estimado, notas) VALUES (?, ?, ?, '2030-03-01 15:00:00', 'Calle 1', 1000.00, 'heredada')",
      [legCliente, servicioId, legTrab],
    );
    const legSol = Number((await uno<{ id: number }>("SELECT id FROM solicitudes WHERE notas = 'heredada'")).id);
    for (const titulo of ["Aviso heredado 1", "Aviso heredado 2"]) {
      await t.ejecutar("INSERT INTO notificaciones (usuario_id, solicitud_id, tipo, titulo, mensaje) VALUES (?, ?, 'SERVICIO_CONFIRMADO', ?, 'm')", [legCliente, legSol, titulo]);
      await t.ejecutar("INSERT INTO notificaciones_trabajador (trabajador_id, solicitud_id, tipo, titulo, mensaje) VALUES (?, ?, 'INVITACION_NUEVA', ?, 'm')", [legTrab, legSol, titulo]);
    }
    await t.ejecutar(
      "INSERT INTO trabajador_movimientos (trabajador_id, cuenta, tipo, monto, saldo_resultante, solicitud_id, clave_idempotencia) VALUES (?, 'DEUDA', 'COMISION_EFECTIVO', 150.00, 150.00, ?, 'HEREDADO:COMISION')",
      [legTrab, legSol],
    );
    const legComision = Number((await uno<{ id: number }>("SELECT id FROM trabajador_movimientos WHERE clave_idempotencia = 'HEREDADO:COMISION'")).id);
    const conHeredados = await verificar003(t.consultar);
    registrar("5. Datos heredados: 2 + 2 notificaciones y 1 comisión", conHeredados.bloqueos.length === 0 && conHeredados.notificacionesALegado === 4, `a LEGADO: ${conHeredados.notificacionesALegado}`);

    // 5b. Las guardas del 003 lo detienen si hay resoluciones o AJUSTE previos (sin cambiar nada).
    const sentencias003 = dividirSentencias(readFileSync(SQL_003, "utf8"));
    const esViolacion = (m: string | null) => !!m && /3819|is violated|violat/i.test(m);
    const guarda = async (i: number) => {
      const error = await mensajeDeError(() => t.ejecutar(sentencias003[i] as string));
      if (!error) await t.ejecutar(sentencias003[i + 1] as string); // no falló: quitar el CHECK que agregó
      return error;
    };
    await t.ejecutar("INSERT INTO solicitud_resoluciones (solicitud_id, admin_id, motivo) VALUES (?, ?, 'previa')", [legSol, adminId]);
    const bloqueoRes = (await verificar003(t.consultar)).bloqueos.some((b) => b.includes("resoluciones"));
    const guardaRes = await guarda(0);
    await t.ejecutar("DELETE FROM solicitud_resoluciones");
    await t.ejecutar(
      "INSERT INTO trabajador_movimientos (trabajador_id, cuenta, tipo, monto, saldo_resultante, solicitud_id, movimiento_relacionado_id, clave_idempotencia) VALUES (?, 'DEUDA', 'AJUSTE', -150.00, 0.00, ?, ?, 'HEREDADO:AJUSTE')",
      [legTrab, legSol, legComision],
    );
    const bloqueoAj = (await verificar003(t.consultar)).bloqueos.some((b) => b.includes("AJUSTE"));
    const guardaAj = await guarda(2);
    await t.ejecutar("DELETE FROM trabajador_movimientos WHERE clave_idempotencia = 'HEREDADO:AJUSTE'");
    registrar(
      "5b. Con resoluciones o AJUSTE previos, el verificador lo bloquea y la guarda del 003 falla antes de cambiar nada",
      bloqueoRes && bloqueoAj && esViolacion(guardaRes) && esViolacion(guardaAj),
      `verificador: res=${bloqueoRes} aj=${bloqueoAj} · guarda res: ${guardaRes ?? "NO falló"} · guarda aj: ${guardaAj ?? "NO falló"}`,
    );

    // Foto del estado "002 + datos heredados" (para comparar tras el rollback del 003)
    const tablasPost002 = await listarTablas(t.consultar);
    const estructuraPost002 = await estructura(t.consultar, tablasPost002);
    const huellasPost002 = await huellasDeDatos(t.consultar, tablasPost002);
    const columnasPost002 = await columnasPorTabla(t.consultar as never);

    // 6. Aplicar el 003
    let aplicadas = 0;
    try {
      for (const s of sentencias003) {
        await t.ejecutar(s);
        aplicadas++;
      }
    } catch (e) {
      registrar("6. Aplicar SQL 003", false, `falló la sentencia ${aplicadas + 1}: ${(sentencias003[aplicadas] ?? "").slice(0, 100).replace(/\s+/g, " ")} → ${(e as Error).message}`);
      throw new Error("El 003 falló en la BD de ensayo");
    }
    const v003 = await verificar003(t.consultar);
    const v002b = await verificar002(t.consultar);
    registrar("6. SQL 003 aplicado y verificado", v003.estado === "APLICADO COMPLETO" && v002b.estado === "APLICADO COMPLETO", `${aplicadas} sentencias, 003: ${v003.presentes}/${v003.total}, 002 sigue ${v002b.presentes}/${v002b.total}`);

    const huellasTras003 = await huellasDeDatos(t.consultar, tablasPost002, columnasPost002);
    const cambiadas = compararMapas(huellasPost002, huellasTras003).filter((x) => x !== "parametros_negocio");
    const legados = await uno<{ n: number; m: number }>(
      `SELECT (SELECT COUNT(*) FROM notificaciones WHERE clave_evento = CONCAT('LEGADO:', id)) AS n,
              (SELECT COUNT(*) FROM notificaciones_trabajador WHERE clave_evento = CONCAT('LEGADO:', id)) AS m`,
    );
    const param = await uno<{ v: string }>("SELECT CAST(valor AS CHAR) AS v FROM parametros_negocio WHERE clave = 'HORAS_PLAZO_REPORTE_PAGO'");
    registrar(
      "6b. Ningún dato existente cambió; las notificaciones heredadas conservan todo y reciben 'LEGADO:<id>'",
      cambiadas.length === 0 && Number(legados.n) === 2 && Number(legados.m) === 2 && Number(param?.v) === 24,
      `tablas con datos distintos: [${cambiadas.join(", ")}] · legados ${Number(legados.n)}+${Number(legados.m)} · HORAS_PLAZO_REPORTE_PAGO=${param?.v}`,
    );

    // 7. Introspección vs schema previsto 003
    const pull = prismaCli(RAIZ, ["db", "pull", "--print"], { DATABASE_URL: urlParaBd(nombreEnsayo) });
    if (!pull.ok) registrar("7. Introspección", false, pull.salida.slice(0, 300));
    else {
      writeFileSync(path.join(carpeta, "schema-introspeccionado.prisma"), pull.stdout, "utf8");
      const dif = diferenciasSchema(pull.stdout, readFileSync(SCHEMA_PREVISTO_003, "utf8"));
      registrar("7. Introspección de la BD == schema Prisma previsto 003", dif.length === 0, dif.slice(0, 6).join("; ") || "coinciden");
    }

    // 8. Pruebas con el cliente Prisma previsto 003
    rmSync(CARPETA_PRISMA_ENSAYO, { recursive: true, force: true });
    mkdirSync(CARPETA_PRISMA_ENSAYO, { recursive: true });
    writeFileSync(
      path.join(CARPETA_PRISMA_ENSAYO, "schema.prisma"),
      readFileSync(SCHEMA_PREVISTO_003, "utf8").replace(/output\s*=\s*"\.\.\/generated\/prisma"/, 'output   = "./generated/prisma"'),
      "utf8",
    );
    const gen = prismaCli(RAIZ, ["generate", "--schema", ".ensayo/schema.prisma"]);
    registrar("8a. prisma generate con el schema previsto 003", gen.ok, gen.ok ? "" : gen.salida.slice(0, 300));
    if (!gen.ok) throw new Error("No se pudo generar el cliente previsto");
    const modulo = (await import(pathToFileURL(path.join(CARPETA_PRISMA_ENSAYO, "generated", "prisma", "client.ts")).href)) as {
      PrismaClient: new (o: unknown) => any;
    };
    const db = new modulo.PrismaClient({
      adapter: new PrismaMariaDb({
        host: env.db.host, port: env.db.port, user: env.db.user, password: env.db.password, database: nombreEnsayo,
        connectionLimit: 3, connectTimeout: 15_000, ssl: { minVersion: "TLSv1.2", rejectUnauthorized: true },
      }),
    });
    prismaEnsayo = db;
    const prueba = async (nombre: string, fn: () => Promise<boolean | string>) => {
      try {
        const r = await fn();
        registrar(`8. ${nombre}`, r === true, typeof r === "string" ? r : "");
      } catch (e) {
        registrar(`8. ${nombre}`, false, ocultarSecretos((e as Error).message).slice(0, 300));
      }
    };
    const creados = { usuarios: [] as number[], trabajadores: [] as number[], solicitudes: [] as number[] };
    const nuevoUsuario = async (datos: Record<string, unknown>) => {
      const u = await db.usuarios.create({ data: { password_hash: "x", ...datos } });
      creados.usuarios.push(u.id);
      return u;
    };
    const c2 = await nuevoUsuario({ nombre_completo: "Cliente dos", correo: "c2@ensayo.test", telefono: "9300000011" });
    const t2 = await db.trabajadores.create({ data: { nombre_completo: "Trabajador dos", telefono: "9300000012", correo: "t2@ensayo.test", direccion: "Calle 2" } });
    creados.trabajadores.push(t2.id);

    // D60
    await prueba("D60 — una notificación por (destinatario, evento); eventos distintos y otros destinatarios sí", async () => {
      const base = { tipo: "SERVICIO_CONFIRMADO", titulo: "t", mensaje: "m" };
      await db.notificaciones.create({ data: { ...base, usuario_id: legCliente, clave_evento: "SERVICIO_CONFIRMADO:hist:1" } });
      const mismoEvento = await esperarErrorPrisma(
        () => db.notificaciones.create({ data: { ...base, usuario_id: legCliente, clave_evento: "SERVICIO_CONFIRMADO:hist:1" } }), "P2002");
      await db.notificaciones.create({ data: { ...base, usuario_id: c2.id, clave_evento: "SERVICIO_CONFIRMADO:hist:1" } });
      await db.notificaciones.create({ data: { ...base, usuario_id: legCliente, clave_evento: "SERVICIO_CONFIRMADO:hist:2" } });
      const sinClave = await mensajeDeError(() =>
        t.ejecutar("INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje) VALUES (?, 'SERVICIO_CONFIRMADO', 't', 'm')", [legCliente]));
      const simultaneos = await Promise.allSettled([
        db.notificaciones.create({ data: { ...base, usuario_id: c2.id, clave_evento: "REPORTE_RESUELTO:rep:9" } }),
        db.notificaciones.create({ data: { ...base, usuario_id: c2.id, clave_evento: "REPORTE_RESUELTO:rep:9" } }),
      ]);
      const ganan = simultaneos.filter((x) => x.status === "fulfilled").length;
      const baseT = { tipo: "INVITACION_NUEVA", titulo: "t", mensaje: "m" };
      await db.notificaciones_trabajador.create({ data: { ...baseT, trabajador_id: legTrab, clave_evento: "INVITACION_NUEVA:st:1" } });
      const mismoEventoT = await esperarErrorPrisma(
        () => db.notificaciones_trabajador.create({ data: { ...baseT, trabajador_id: legTrab, clave_evento: "INVITACION_NUEVA:st:1" } }), "P2002");
      await db.notificaciones_trabajador.create({ data: { ...baseT, trabajador_id: t2.id, clave_evento: "INVITACION_NUEVA:st:1" } });
      // Una invitación reabierta es otra ocurrencia: su clave lleva el id de esa ocurrencia.
      await db.notificaciones_trabajador.create({ data: { ...baseT, trabajador_id: legTrab, clave_evento: "INVITACION_NUEVA:st:1:2" } });
      return (mismoEvento && !!sinClave && ganan === 1 && mismoEventoT) || `mismoEvento=${mismoEvento} sinClave=${sinClave} ganan=${ganan} mismoEventoT=${mismoEventoT}`;
    });

    // D61
    await prueba("D61 — pago presumido: plazo de 24 h guardado, aviso único con el plazo, y no se mueve si cambia el parámetro", async () => {
      const s = await db.solicitudes.create({
        data: {
          cliente_id: legCliente, servicio_id: servicioId, trabajador_id: legTrab, estado: "EN_PROCESO",
          fecha_hora_programada: new Date("2030-03-08T15:00:00Z"), direccion_servicio: "Calle 1", precio_estimado: "1000.00",
        },
      });
      creados.solicitudes.push(s.id);
      const ahora = new Date(Math.floor(Date.now() / 1000) * 1000);
      let mensaje = "";
      await db.$transaction(async (tx: any) => {
        const r = await tx.solicitudes.updateMany({
          where: { id: s.id, estado: "EN_PROCESO" },
          data: { estado: "REALIZADO", realizado_via: "AUTOMATICO", realizado_en: ahora },
        });
        if (r.count !== 1) throw new Error("no se confirmó");
        const horas = Number((await tx.parametros_negocio.findUniqueOrThrow({ where: { clave: "HORAS_PLAZO_REPORTE_PAGO" } })).valor);
        const hasta = new Date(ahora.getTime() + horas * 3_600_000);
        await tx.solicitudes.update({
          where: { id: s.id },
          data: { estado_pago: "PAGADO", pago_registrado_en: ahora, pago_registrado_por: "SISTEMA", reporte_pago_hasta: hasta },
        });
        const fecha = hasta.toLocaleString("es-MX", { timeZone: "America/Cancun", dateStyle: "short", timeStyle: "short" });
        mensaje = `Se registró el pago en efectivo de tu servicio y una comisión del 15 %. Si no recibiste el efectivo, repórtalo antes del ${fecha} (${horas} h) en el servicio → Reportar → «No recibí el efectivo».`;
        await tx.notificaciones_trabajador.create({
          data: { trabajador_id: legTrab, solicitud_id: s.id, tipo: "PAGO_EFECTIVO_PRESUMIDO", clave_evento: `PAGO_EFECTIVO_PRESUMIDO:sol:${s.id}`, titulo: "Pago en efectivo registrado", mensaje },
        });
      });
      // Aunque el código intentara avisar otra vez el mismo evento, la BD lo rechaza.
      const avisoDoble = await esperarErrorPrisma(
        () => db.notificaciones_trabajador.create({
          data: { trabajador_id: legTrab, solicitud_id: s.id, tipo: "PAGO_EFECTIVO_PRESUMIDO", clave_evento: `PAGO_EFECTIVO_PRESUMIDO:sol:${s.id}`, titulo: "t", mensaje: "m" },
        }), "P2002");
      const leida = await db.solicitudes.findUniqueOrThrow({ where: { id: s.id } });
      const plazoHoras = (leida.reporte_pago_hasta.getTime() - leida.pago_registrado_en.getTime()) / 3_600_000;
      await db.parametros_negocio.update({ where: { clave: "HORAS_PLAZO_REPORTE_PAGO" }, data: { valor: "48.00" } });
      const despues = await db.solicitudes.findUniqueOrThrow({ where: { id: s.id } });
      await db.parametros_negocio.update({ where: { clave: "HORAS_PLAZO_REPORTE_PAGO" }, data: { valor: "24.00" } });
      const avisos = await db.notificaciones_trabajador.count({ where: { solicitud_id: s.id, tipo: "PAGO_EFECTIVO_PRESUMIDO" } });
      return (
        (plazoHoras === 24 && avisoDoble && avisos === 1 && despues.reporte_pago_hasta.getTime() === leida.reporte_pago_hasta.getTime() &&
          mensaje.length <= 255 && /24 h/.test(mensaje) && /No recibí el efectivo/.test(mensaje)) ||
        `plazo=${plazoHoras}h avisoDoble=${avisoDoble} avisos=${avisos} largo=${mensaje.length}`
      );
    });

    // D62
    const admin2 = await nuevoUsuario({ rol: "ADMIN", nombre_completo: "Admin dos", correo: "a2@ensayo.test" });
    const adminSinPermiso = await nuevoUsuario({ rol: "ADMIN", nombre_completo: "Admin sin permiso", correo: "a3@ensayo.test" });
    const adminSuspendido = await nuevoUsuario({ rol: "ADMIN", nombre_completo: "Admin suspendido", correo: "a4@ensayo.test", estado_cuenta: "SUSPENDIDA" });
    const adminRevocado = await nuevoUsuario({ rol: "ADMIN", nombre_completo: "Admin revocado", correo: "a5@ensayo.test" });
    const permiso = "GESTIONAR_INCIDENCIAS_FINANZAS";
    const otorgar = (usuario_id: number) => db.admin_permisos.create({ data: { usuario_id, permiso, otorgado_por: adminId, motivo: "ensayo" } });

    await prueba("D62 — permisos con historial: uno activo por admin; revocar y volver a otorgar conserva el historial", async () => {
      const g1 = await otorgar(adminId);
      const dobleActivo = await esperarErrorPrisma(() => otorgar(adminId), "P2002");
      await db.admin_permisos.update({ where: { id: g1.id }, data: { revocado_en: new Date(), revocado_por: admin2.id, motivo: "ensayo: revocado" } });
      await otorgar(adminId);
      const historial = await db.admin_permisos.count({ where: { usuario_id: adminId } });
      const activos = await db.admin_permisos.count({ where: { usuario_id: adminId, revocado_en: null } });
      return (dobleActivo && historial === 2 && activos === 1) || `dobleActivo=${dobleActivo} historial=${historial} activos=${activos}`;
    });

    await prueba("D62 — solo un ADMIN ACTIVO con el permiso VIGENTE pasa la comprobación del backend", async () => {
      await otorgar(admin2.id);
      await otorgar(adminSuspendido.id);
      const gr = await otorgar(adminRevocado.id);
      await db.admin_permisos.update({ where: { id: gr.id }, data: { revocado_en: new Date(), revocado_por: adminId } });
      // La BD no puede impedir dar el permiso a un CLIENTE (no hay CHECK entre tablas): lo filtra el backend.
      await otorgar(legCliente);
      // Consulta que usará el backend dentro de la transacción de la resolución (bloquea el permiso).
      const puedeResolver = (usuarioId: number) =>
        db.$transaction(async (tx: any) =>
          (await tx.$queryRawUnsafe(
            `SELECT p.id FROM admin_permisos p JOIN usuarios u ON u.id = p.usuario_id
             WHERE p.usuario_id = ? AND p.permiso = 'GESTIONAR_INCIDENCIAS_FINANZAS' AND p.revocado_en IS NULL
               AND u.rol = 'ADMIN' AND u.estado_cuenta = 'ACTIVA' FOR UPDATE`,
            usuarioId,
          )).length === 1,
        );
      const r = {
        conPermiso: await puedeResolver(adminId),
        otroConPermiso: await puedeResolver(admin2.id),
        sinPermiso: await puedeResolver(adminSinPermiso.id),
        suspendido: await puedeResolver(adminSuspendido.id),
        revocado: await puedeResolver(adminRevocado.id),
        cliente: await puedeResolver(legCliente),
      };
      return (r.conPermiso && r.otroConPermiso && !r.sinPermiso && !r.suspendido && !r.revocado && !r.cliente) || JSON.stringify(r);
    });

    let resolucionId = 0;
    await prueba("D62 — la resolución exige admin y SU permiso (FK compuesta); no se puede borrar ni el admin ni el permiso", async () => {
      const propio = await db.admin_permisos.findFirstOrThrow({ where: { usuario_id: adminId, revocado_en: null } });
      const ajeno = await db.admin_permisos.findFirstOrThrow({ where: { usuario_id: admin2.id, revocado_en: null } });
      const sinPermiso = await mensajeDeError(() =>
        t.ejecutar("INSERT INTO solicitud_resoluciones (solicitud_id, admin_id, motivo) VALUES (?, ?, 'x')", [legSol, adminId]));
      const sinAdmin = await mensajeDeError(() =>
        t.ejecutar("INSERT INTO solicitud_resoluciones (solicitud_id, admin_permiso_id, motivo) VALUES (?, ?, 'x')", [legSol, propio.id]));
      const permisoDeOtro = await esperarErrorPrisma(
        () => db.solicitud_resoluciones.create({ data: { solicitud_id: legSol, admin_id: adminId, admin_permiso_id: ajeno.id, motivo: "x" } }), "P2003");
      const res = await db.solicitud_resoluciones.create({
        data: { solicitud_id: legSol, admin_id: adminId, admin_permiso_id: propio.id, resultado_pago: "NO_PAGADO", motivo: "ensayo" },
      });
      resolucionId = res.id;
      const borrarAdmin = await esperarErrorPrisma(() => db.usuarios.delete({ where: { id: adminId } }), "P2003");
      const borrarPermiso = await esperarErrorPrisma(() => db.admin_permisos.delete({ where: { id: propio.id } }), "P2003");
      return (
        (!!sinPermiso && !!sinAdmin && permisoDeOtro && borrarAdmin && borrarPermiso) ||
        `sinPermiso=${!!sinPermiso} sinAdmin=${!!sinAdmin} permisoDeOtro=${permisoDeOtro} borrarAdmin=${borrarAdmin} borrarPermiso=${borrarPermiso}`
      );
    });

    await prueba("D62 — todo AJUSTE necesita una resolución (CHECK); con resolución sí se registra", async () => {
      const datos = { trabajador_id: legTrab, cuenta: "DEUDA", tipo: "AJUSTE", monto: "-150.00", saldo_resultante: "0.00", solicitud_id: legSol, movimiento_relacionado_id: legComision };
      const sinResolucion = await mensajeDeError(() => db.trabajador_movimientos.create({ data: { ...datos, clave_idempotencia: "AJUSTE:sin-res" } }));
      const conResolucion = await db.trabajador_movimientos.create({ data: { ...datos, resolucion_id: resolucionId, clave_idempotencia: `AJUSTE:res:${resolucionId}` } });
      return (/chk_mov_ajuste_con_resolucion|check constraint/i.test(sinResolucion ?? "") && conResolucion.resolucion_id === resolucionId) || `sinResolucion=${sinResolucion}`;
    });

    await prueba("Las garantías del 002 siguen activas (comisión una vez por solicitud)", async () =>
      esperarErrorPrisma(() => db.trabajador_movimientos.create({
        data: { trabajador_id: legTrab, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "150.00", saldo_resultante: "300.00", solicitud_id: legSol, clave_idempotencia: "COMISION:otra" },
      }), "P2002"),
    );

    await db.$disconnect();
    prismaEnsayo = null;

    // 9. Rollback del 003: primero su guarda (hay una resolución → debe fallar sin cambiar nada)
    const sentenciasRb003 = dividirSentencias(readFileSync(SQL_003_ROLLBACK, "utf8"));
    const guardaRb = await mensajeDeError(() => t.ejecutar(sentenciasRb003[0] as string));
    if (!guardaRb) await t.ejecutar(sentenciasRb003[1] as string);
    registrar("9a. La guarda del rollback 003 lo detiene si hay resoluciones (violación del CHECK)", !!guardaRb && /3819|is violated|violat/i.test(guardaRb), guardaRb ?? "NO falló");

    // Limpiar los datos de las pruebas (los heredados se quedan)
    await t.ejecutar("DELETE FROM notificaciones WHERE clave_evento NOT LIKE 'LEGADO:%'");
    await t.ejecutar("DELETE FROM notificaciones_trabajador WHERE clave_evento NOT LIKE 'LEGADO:%'");
    await t.ejecutar("DELETE FROM trabajador_movimientos WHERE tipo = 'AJUSTE'");
    await t.ejecutar("DELETE FROM trabajador_movimientos WHERE id <> ?", [legComision]);
    await t.ejecutar("DELETE FROM solicitud_resoluciones");
    await t.ejecutar("DELETE FROM admin_permisos");
    const lista = (ids: number[]) => (ids.length ? ids.join(",") : "0");
    await t.ejecutar(`DELETE FROM solicitudes WHERE id IN (${lista(creados.solicitudes)})`);
    await t.ejecutar(`DELETE FROM trabajadores WHERE id IN (${lista(creados.trabajadores)})`);
    await t.ejecutar(`DELETE FROM usuarios WHERE id IN (${lista(creados.usuarios)})`);

    let revertidas = 0;
    try {
      for (const s of sentenciasRb003) {
        await t.ejecutar(s);
        revertidas++;
      }
      registrar("9b. Rollback 003 aplicado", true, `${revertidas} sentencias`);
    } catch (e) {
      registrar("9b. Rollback 003 aplicado", false, `falló la sentencia ${revertidas + 1}: ${(e as Error).message}`);
    }
    const tras003 = await verificar003(t.consultar);
    const tablasTras = await listarTablas(t.consultar);
    const difE = compararMapas(estructuraPost002, await estructura(t.consultar, tablasPost002));
    const difD = compararMapas(huellasPost002, await huellasDeDatos(t.consultar, tablasPost002));
    const sobran = tablasTras.filter((x) => !tablasPost002.includes(x));
    registrar(
      "9c. Tras el rollback 003 la BD es idéntica al estado 002 + datos heredados (las notificaciones siguen intactas)",
      tras003.presentes === 0 && difE.length === 0 && difD.length === 0 && sobran.length === 0,
      `003 ${tras003.presentes}/${tras003.total}; estructura distinta [${difE.join(", ")}]; datos distintos [${difD.join(", ")}]; sobran [${sobran.join(", ")}]`,
    );

    // Rollback del 002 (se quitan antes los datos heredados)
    await t.ejecutar("DELETE FROM notificaciones WHERE usuario_id = ?", [legCliente]);
    await t.ejecutar("DELETE FROM notificaciones_trabajador");
    await t.ejecutar("DELETE FROM trabajador_movimientos");
    await t.ejecutar("DELETE FROM solicitudes WHERE id = ?", [legSol]);
    await t.ejecutar("DELETE FROM trabajadores WHERE id = ?", [legTrab]);
    await t.ejecutar("DELETE FROM usuarios WHERE id = ?", [legCliente]);
    for (const s of dividirSentencias(readFileSync(SQL_002_ROLLBACK, "utf8"))) await t.ejecutar(s);
    const tras002 = await verificar002(t.consultar);
    const difE2 = compararMapas(estructuraProdInicial, await estructura(t.consultar, tablasOriginales));
    const difD2 = compararMapas(huellasProdInicial, await huellasDeDatos(t.consultar, tablasOriginales));
    registrar(
      "9d. Tras el rollback 002 la BD es idéntica a producción",
      tras002.presentes === 0 && difE2.length === 0 && difD2.length === 0,
      `002 ${tras002.presentes}/${tras002.total}; estructura distinta [${difE2.join(", ")}]; datos distintos [${difD2.join(", ")}]`,
    );
  } catch (error) {
    registrar("Ensayo detenido por un error", false, ocultarSecretos((error as Error)?.message ?? String(error)).slice(0, 400));
  } finally {
    if (prismaEnsayo) await prismaEnsayo.$disconnect().catch(() => undefined);
    if (temp) await temp.cerrar().catch(() => undefined);
    if (tablasPropias) {
      try {
        const limpieza = await conectar(nombreEnsayo);
        const [{ bd } = { bd: "" }] = await limpieza.consultar<{ bd: string }>("SELECT DATABASE() AS bd");
        if (bd !== nombreEnsayo || !esBdExistentePermitidaParaEnsayo(bd)) throw new Error(`conexión a ${bd}`);
        await limpieza.ejecutar("SET FOREIGN_KEY_CHECKS = 0");
        for (const x of await listarTablas(limpieza.consultar)) await limpieza.ejecutar(`DROP TABLE \`${x.replace(/`/g, "``")}\``);
        await limpieza.ejecutar("SET FOREIGN_KEY_CHECKS = 1");
        const quedan = await listarTablas(limpieza.consultar);
        await limpieza.cerrar();
        registrar("10a. BD del ensayo vaciada", quedan.length === 0, `${nombreEnsayo}: ${quedan.length} tablas`);
      } catch (e) {
        registrar("10a. Vaciar la BD del ensayo", false, ocultarSecretos((e as Error).message));
      }
    }
    try {
      const tablasFinales = await listarTablas(prod.consultar);
      const difE = compararMapas(estructuraProdInicial, await estructura(prod.consultar, tablasFinales));
      const difD = compararMapas(huellasProdInicial, await huellasDeDatos(prod.consultar, tablasFinales));
      registrar("10b. Producción intacta", difE.length === 0 && difD.length === 0, `${tablasFinales.length} tablas; estructura distinta [${difE.join(", ")}]; datos distintos [${difD.join(", ")}]`);
    } catch (e) {
      registrar("10b. Producción intacta", false, `no se pudo comprobar: ${(e as Error).message}`);
    }
    await prod.cerrar().catch(() => undefined);
    rmSync(CARPETA_PRISMA_ENSAYO, { recursive: true, force: true });
    writeFileSync(path.join(carpeta, "reporte.json"), JSON.stringify({ fecha: new Date().toISOString(), bdEnsayo: nombreEnsayo, pasos }, null, 2), "utf8");
    const fallos = pasos.filter((p) => !p.ok).length;
    console.log(`\nReporte: ${path.join(carpeta, "reporte.json")}`);
    console.log(fallos === 0 ? "ENSAYO 003 OK: todos los pasos pasaron." : `ENSAYO 003 CON ${fallos} FALLO(S).`);
    if (fallos) process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  console.error("El ensayo se detuvo:", ocultarSecretos((error as Error)?.message ?? String(error)));
  process.exitCode = 1;
});
