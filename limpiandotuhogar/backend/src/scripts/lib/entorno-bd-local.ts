/**
 * Apunta el proceso a la BD LOCAL de desarrollo (quelimpiamos_dev, 127.0.0.1:4000). DEBE ser el
 * PRIMER import de los scripts de la BD local: así src/config/env lee esta conexión y nunca la
 * del clúster remoto de .env.
 */
import { BD_LOCAL_DESARROLLO, usarBdLocal } from "./bd-local";

usarBdLocal(BD_LOCAL_DESARROLLO);
