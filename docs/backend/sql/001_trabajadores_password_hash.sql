-- 001 — Credenciales de trabajadores (decisión D1, aprobada por el usuario el 2026-11-24)
-- ESTADO: EJECUTADO el 2026-11-24 con autorización del usuario (vía conexión runtime de la app;
--         `prisma db execute` falló con P1014, ver 08_ESTADO_IMPLEMENTACION.md). Verificado: columna
--         password_hash varchar(255) NULL presente, tabla con 0 filas.
--
-- Motivo: la tabla real `trabajadores` no tiene contraseña, por lo que un trabajador
-- no puede iniciar sesión. Se añade una columna NULL para no afectar filas existentes
-- (al 2026-11-24 la tabla tiene 0 filas). El administrador asigna la contraseña inicial.
--
-- Cómo ejecutar (desde limpiandotuhogar/backend, usa DATABASE_URL del .env):
--   npx prisma db execute --file ../../docs/backend/sql/001_trabajadores_password_hash.sql
-- Después:
--   1) añadir `password_hash String? @db.VarChar(255)` al modelo `trabajadores`
--      en backend/prisma/schema.prisma,
--   2) `npx prisma generate`,
--   3) avisar al equipo de Que-Limpiamos para que actualice su schema de referencia
--      (la BD es compartida).
--
-- Reversión (solo si no hay datos que conservar):
--   ALTER TABLE trabajadores DROP COLUMN password_hash;

ALTER TABLE trabajadores
  ADD COLUMN password_hash VARCHAR(255) NULL AFTER correo;
