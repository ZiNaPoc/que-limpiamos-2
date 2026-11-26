# 16 — Almacenamiento de documentos (D5) — v2: local, gratuito y privado

- **Fecha:** 2026-11-24 · **Estado:** **implementado y probado** en el backend (driver local). Todavía no lo usa ningún endpoint: la subida y la consulta llegan con la Fase 3c y la Fase 5.
- **Corrección del usuario (sustituye a la v1):** QueLimpiamos es un proyecto escolar y debe funcionar y poder demostrarse **sin gastos**. **No** se usan proveedores externos (R2, S3…) por ahora:
  - almacenamiento local privado para desarrollo, fuera de carpetas públicas y de git;
  - abstracción para migrar después a S3/R2 sin rehacer el backend;
  - acceso con autenticación y permisos;
  - validar tamaño, tipo real y extensión;
  - quitar el GPS;
  - sin rutas estáticas ni URLs públicas;
  - documentar que en Render no es persistente;
  - sin dependencias de nube y solo dependencias gratuitas.

## 1. Qué se implementó
| Pieza | Archivo | Qué hace |
|---|---|---|
| Interfaz | `src/shared/almacenamiento/tipos.ts` | `Almacenamiento`: `guardar`, `leer`, `existe`, `eliminar` y `urlTemporal`. El resto del backend solo usa esto |
| Driver local | `src/shared/almacenamiento/local.ts` | Guarda en una carpeta **fuera del repositorio** (si está dentro, se niega a arrancar). Usa claves aleatorias (`<espacio>/<prefijo>/<uuid>.<ext>`) sin datos personales, escribe de forma atómica y bloquea claves que intenten salir de la carpeta |
| Validación | `src/shared/almacenamiento/validacion.ts` | Tamaño máximo (5 MB, configurable); **tipo real por su firma** (JPEG, PNG, WebP o PDF, sin fiarse del nombre); la extensión debe corresponder; el tipo declarado también; y lo que acepta cada propósito: identidad, evidencia y perfil **solo imágenes**, el comprobante también PDF |
| Metadatos | `src/shared/almacenamiento/metadatos.ts` | **Sin dependencias.** JPEG: quita EXIF (con el **GPS**), XMP, IPTC y comentarios, y conserva **solo la orientación** para que la foto no se vea girada. PNG: quita eXIf, tEXt, zTXt e iTXt y verifica los CRC. WebP: quita EXIF y XMP. Revisa la estructura: un archivo dañado o truncado se rechaza |
| URL temporal | `local.ts` + `descargas.ts` | El backend **firma** (HMAC-SHA256) un token con la clave, el tipo y el vencimiento (60 s para identidad, 5 min para el resto, 15 min como máximo). `GET /api/archivos/temporal/<token>` entrega el archivo con `no-store`, `nosniff` y `sandbox`. Un token alterado o vencido, o un archivo borrado, da **404** sin decir el motivo |
| Configuración | `src/config/almacenamiento.ts` | `ALMACENAMIENTO_LOCAL_DIR` (por defecto `<home>/.quelimpiamos/almacenamiento`), `ALMACENAMIENTO_FIRMA_SECRETO` (si falta, uno temporal por arranque), `ALMACENAMIENTO_MAX_MB`. En producción avisa de que no es persistente |
| Sin rutas estáticas | `test/importaciones.test.ts` | Una prueba falla si alguien agrega `express.static`, `serve-static` o `sendFile` en `src/` |

**Dependencias nuevas: ninguna** (`node:crypto`, `node:zlib` y `node:fs`).

## 2. Cómo se protege el acceso (regla para las Fases 3c y 5)
1. El endpoint que sube o entrega un archivo va detrás de su guard (`requireCliente`, `requireTrabajador` o `requireAdmin`) y, para documentos de identidad, del **permiso** `REVISAR_DOCUMENTOS_IDENTIDAD` (D66, pendiente en el SQL 003 v2).
2. Solo **después** de autorizar llama a `almacenamiento().urlTemporal(clave, { mime, segundos })` y devuelve esa URL. La app le antepone su `API_URL`.
3. La BD guarda **solo la clave**: la columna existente `archivo_url` pasa a guardar la clave, no una URL.
4. Borrar o reemplazar: archivo nuevo → actualizar la fila en una transacción → `eliminar(claveVieja)`, que no falla si ya no existe.

## 3. ⚠ Render no es persistente
- El disco de un servicio de Render **se borra en cada deploy o reinicio**. El driver local sirve para **desarrollo y demostraciones**, **no** para producción: tras un reinicio, los documentos subidos desaparecen. Al arrancar con `NODE_ENV=production` el backend lo advierte en el registro.
- Si se despliega en Render solo para una demo, hay que asumir que los archivos se pierden.

## 4. Migrar después a un almacenamiento compatible con S3 (R2, S3, B2…)
1. Crear `src/shared/almacenamiento/s3.ts` que implemente `Almacenamiento`:
   - `guardar` → `PutObject`;
   - `leer` → `GetObject`;
   - `eliminar` → `DeleteObject`;
   - `urlTemporal` → URL firmada del proveedor.

   Agregará las dependencias `@aws-sdk/client-s3` y `@aws-sdk/s3-request-presigner`.
2. En `src/shared/almacenamiento/index.ts`, elegir la clase según `ALMACENAMIENTO_DRIVER=s3` y quitar el montaje de `/api/archivos` (ya no hace falta).
3. Copiar los objetos de la carpeta local al bucket con las mismas claves. La BD no cambia.
4. Las alternativas y costos que se compararon (R2, S3 en México, B2, Supabase) quedan como referencia en el historial de este documento (v1).

## 5. Pruebas (`test/almacenamiento.test.ts`, sin BD) — 13 pruebas, OK
- JPEG, PNG y WebP **con GPS**, XMP y comentarios: el resultado no tiene rastros de GPS, el JPEG conserva la orientación y limpiar dos veces da el mismo resultado.
- Rechazos:
  - archivo vacío (400) o demasiado grande (413);
  - HTML o ejecutable disfrazado (415);
  - extensión o tipo declarado que no corresponde (415);
  - PDF como identidad (415);
  - JPEG truncado, PNG con CRC alterado o sin IDAT, y WebP sin imagen (400 `ARCHIVO_DANADO`).
- La carpeta dentro del repositorio se rechaza; las claves con `..`, rutas absolutas o mayúsculas también.
- Guardar, leer y borrar (dos veces sin error).
- URL temporal: entrega el archivo con encabezados privados y no expone la ruta. Da 404 si la carga o la firma están alteradas, si venció, si el archivo se borró o si se pide por la ruta del archivo.

## 6. Decidido y pendiente
- **D66 (decidido):** los documentos de identidad los ven **solo** los admins con el permiso `REVISAR_DOCUMENTOS_IDENTIDAD`, otorgado por el propietario. El permiso se agrega en el SQL 003 v2 (no aplicado).
- **D67 (decidido):** **evidencias de servicio: 12 meses.** **INE: política aparte**, se borran al concluir la revisión (D53), con la red de seguridad de 30 días en el espacio `identidad`. El borrado programado de evidencias será una tarea periódica (Fase 4/6).
- Las tablas de eventos y accesos a documentos (historial de rechazos, quién vio qué) → SQL 003 v2 (`13` §7).
- La subida desde las apps necesita leer `multipart/form-data`: se agregará `busboy` (gratuita, MIT) cuando exista el primer endpoint de subida (Fase 3c).
