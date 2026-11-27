# 02 — Mapa del schema real

- **Fecha:** 2026-11-24 · **Fase:** 0
- **Fuente:** `Que-Limpiamos/backend/prisma/schema.prisma` (solo lectura, fuente de verdad). Provider `mysql`, cliente `prisma-client` en `../generated/prisma`.

## 1. Diagrama de relaciones

```
usuarios (CLIENTE | ADMIN) ──1:N── inmuebles ──1:N──┐
   │ 1:N documentos_cliente (INE_FRENTE/INE_REVERSO, único por tipo)
   │ 1:N notificaciones ──N:1 (opcional)── solicitudes
   │ 1:N password_reset_tokens
   └─1:N (cliente_id)──────────────────────── solicitudes ──N:1── servicios
                                                │  ├─1:N evidencias_solicitud
                                                │  ├─1:1 resenas
                                                │  └─N:1 (trabajador_id, opcional) trabajadores
trabajadores ──1:N trabajador_horarios (único por dia_semana)
             ──N:M servicios vía trabajador_servicios (PK compuesta)
             ──1:N documentos_trabajador (IDENTIFICACION/COMPROBANTE_DOMICILIO, único por tipo)
```

## 2. Modelos

### usuarios (clientes y administradores)
| Campo | Tipo | Reglas |
|---|---|---|
| id | Int PK autoincrement | |
| rol | `usuarios_rol` | default `CLIENTE`; valores `CLIENTE`, `ADMIN` |
| nombre_completo | VarChar(120) | |
| correo | VarChar(150) | **único** `uq_usuarios_correo` |
| telefono | Char(10)? | **único** `uq_usuarios_telefono`, opcional |
| password_hash | VarChar(255) | nunca devolver |
| foto_url | VarChar(255)? | |
| estado_cuenta | `ACTIVA`/`SUSPENDIDA` | default `ACTIVA` |
| estado_verificacion | `PENDIENTE`/`VERIFICADO`/`RECHAZADO`? | default `PENDIENTE` (INE) |
| created_at | DateTime(0) | default now |

Borrado en cascada hacia: documentos_cliente, inmuebles, notificaciones, password_reset_tokens. **No** en cascada hacia solicitudes (FK sin onDelete → Restrict por defecto en MySQL).

### trabajadores
| Campo | Tipo | Reglas |
|---|---|---|
| id | Int PK | |
| nombre_completo | VarChar(120) | |
| telefono | Char(10) | **único**, obligatorio |
| correo | VarChar(150) | **único**, obligatorio |
| direccion | VarChar(255) | obligatorio |
| foto_url | VarChar(255)? | |
| estado | `ACTIVO`/`INACTIVO` | default `ACTIVO` |
| created_at / updated_at | DateTime(0) | `updated_at` con ON UPDATE en la BD (corregido 2026-11-24: en la BD ya tiene `ON UPDATE CURRENT_TIMESTAMP`; Prisma no lo muestra. En el schema llevará `@updatedAt`) |

⚠ **Sin campo de contraseña.**

### inmuebles
`usuario_id` (FK cascade), `alias?` VarChar(100), `tipo` (`CASA`/`OFICINA`/`DEPARTAMENTO`, default CASA), `direccion` VarChar(255), `habitaciones`/`banos`/`medios_banos` UnsignedTinyInt default 0, `pisos` default 1, timestamps. Índice `idx_inmueble_usuario`. Borrar un inmueble con solicitudes falla (`onDelete: Restrict`).

### servicios
`nombre` VarChar(100) **único**, `descripcion` Text, `precio_base` Decimal(10,2), `duracion_estimada_min` UnsignedSmallInt default 300, `imagen_url?`, `estado` `ACTIVO`/`INACTIVO`, timestamps. FK desde solicitudes sin cascade (no se puede borrar un servicio usado → usar `INACTIVO`).

### solicitudes
| Campo | Tipo | Reglas |
|---|---|---|
| cliente_id | Int → usuarios | obligatorio |
| servicio_id | Int → servicios | obligatorio |
| inmueble_id | Int? → inmuebles | Restrict |
| trabajador_id | Int? → trabajadores | Restrict |
| fecha_hora_programada | DateTime(0) | obligatorio |
| direccion_servicio | VarChar(255) | obligatorio (copia de la dirección al momento de pedir) |
| precio_estimado | Decimal(10,2) | obligatorio |
| estado | `solicitudes_estado` | default `PENDIENTE` |
| created_at / updated_at | DateTime(0) | `updated_at` con ON UPDATE en la BD (corregido 2026-11-24: en la BD ya tiene `ON UPDATE CURRENT_TIMESTAMP`; Prisma no lo muestra. En el schema llevará `@updatedAt`) |

Índices: `(cliente_id, estado)`, `(estado, fecha_hora_programada)`, `(trabajador_id, fecha_hora_programada)`, `inmueble_id`, `servicio_id`.

### trabajador_servicios
PK `(trabajador_id, servicio_id)`. Cascade al borrar trabajador.

### trabajador_horarios
`dia_semana` TinyInt (convención a confirmar: el panel usa 0=domingo…6=sábado), `hora_inicio`/`hora_fin` Time(0). Único `(trabajador_id, dia_semana)`.

### documentos_cliente / documentos_trabajador
`archivo_url` VarChar(255), `tipo` enum, único `(dueño, tipo)` → upsert por tipo.

### evidencias_solicitud
`solicitud_id` (cascade), `archivo_url`, `descripcion?`, `created_at`.

### resenas
`solicitud_id` **único** (1 reseña por solicitud), `puntuacion_servicio` y `puntuacion_trabajador` TinyInt (rango a validar, p. ej. 1–5), `comentario?` Text.

### notificaciones
`usuario_id` → usuarios (cascade), `solicitud_id?`, `tipo` `SERVICIO_CONFIRMADO`/`CALIFICAR_SERVICIO`, `titulo` VarChar(100), `mensaje` VarChar(255). **Sin campo "leída"** y **sin destinatario trabajador**.

### password_reset_tokens
`usuario_id`, `token_hash` Char(64) único (sha256 hex), `expira_en`, `usado` bool. Solo para `usuarios`.

## 3. Máquina de estados (propuesta a validar — D2)

Estados reales: `PENDIENTE`, `CONFIRMADO`, `EN_PROCESO`, `REALIZADO`, `CANCELADO`, `RECHAZADO`.

Lo que ya está implementado/documentado:
- B: el admin solo puede asignar/desasignar trabajador mientras la solicitud está `PENDIENTE`.
- Panel web (`tipos.ts`): "Pendiente sin colaborador = Solicitud enviada; Pendiente con colaborador = Asignando colaborador"; flujo Pendiente → Confirmado → (En proceso) → Realizado; cancelable antes de finalizar.

```
            (admin asigna / trabajador acepta)
PENDIENTE ─────────────────────────────────► PENDIENTE+trabajador
   │  │                                           │  ¿quién confirma? (D2)
   │  └──► RECHAZADO  (¿quién? D2)                ▼
   │                                          CONFIRMADO ──(trabajador inicia)──► EN_PROCESO ──(trabajador termina)──► REALIZADO
   └────────► CANCELADO ◄──── (cliente/admin, antes de EN_PROCESO; D2) ───┘                                              │
                                                                                         cliente califica (resenas) ◄───┘
```

Toda transición se implementará con `updateMany({ where: { id, estado: <previo>, [dueño/trabajador] } })` y comprobación de `count` (patrón atómico ya usado en A), dentro de `$transaction` cuando además cree notificaciones.

Efectos laterales posibles con el schema real:
- → `CONFIRMADO`: crear `notificaciones` tipo `SERVICIO_CONFIRMADO` para el cliente.
- → `REALIZADO`: crear `notificaciones` tipo `CALIFICAR_SERVICIO`; habilitar `resenas`.
