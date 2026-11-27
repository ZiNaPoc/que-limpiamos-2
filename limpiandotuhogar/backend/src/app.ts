import express from "express";
import cors from "cors";

import { env } from "./config/env";
import { prisma } from "./config/prisma";
import { manejarErrores, rutaNoEncontrada } from "./middleware/error.middleware";
import { adminRouter } from "./modules/admin";
import { adminAuthRouter } from "./modules/admin/auth/routes";
import { clienteRouter } from "./modules/cliente";
import { trabajadorRouter } from "./modules/trabajador";
import { almacenamiento } from "./shared/almacenamiento";
import { crearRouterDescargas } from "./shared/almacenamiento/descargas";

const app = express();

// Render (y la mayoría de hostings) ponen un proxy delante: confiar en el primero
// para que req.ip / req.secure reflejen al cliente real.
app.set("trust proxy", 1);
app.disable("x-powered-by");

// Health check sin BD: lo usa Render para saber si el proceso está vivo.
app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

// Health check con BD (SELECT 1, solo lectura).
app.get("/health/db", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true, db: "ok" });
  } catch (error) {
    console.error("[health/db]", error);
    res.status(503).json({ ok: false, db: "error" });
  }
});

app.use(
  cors({
    origin: env.corsOrigins,
    credentials: true,
  }),
);

app.use(express.json({ limit: "100kb" }));

// Módulos por audiencia, aislados entre sí (secreto y `aud` propios en cada uno).
app.use("/api/cliente", clienteRouter);
app.use("/api/trabajador", trabajadorRouter);
app.use("/api/admin", adminRouter);
// Alias temporal (D7): el panel llama hoy a /api/auth/admin/*. Quitar al actualizar el panel.
app.use("/api/auth/admin", adminAuthRouter);
// Descargas con URL TEMPORAL firmada (almacenamiento local privado). No hay rutas estáticas:
// los archivos solo salen con un token que emite un endpoint que ya autorizó a quien lo pide.
app.use("/api/archivos", crearRouterDescargas(almacenamiento()));

app.use(rutaNoEncontrada);
app.use(manejarErrores);

export default app;
