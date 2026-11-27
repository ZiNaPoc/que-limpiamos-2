/**
 * Apunta el proceso a la BD LOCAL de PRUEBAS (quelimpiamos_pruebas, 127.0.0.1:4000). Debe ser el
 * PRIMER import del script, igual que entorno-bd-local.
 */
import { BD_LOCAL_PRUEBAS, usarBdLocal } from "./bd-local";

usarBdLocal(BD_LOCAL_PRUEBAS);
