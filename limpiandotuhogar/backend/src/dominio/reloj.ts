/**
 * Reloj del dominio (UTC, X8). Las pruebas lo reemplazan para cruzar plazos (168 h de las
 * reseñas, hora programada de los reportes) sin esperar.
 */
export const relojDominio = { ahora: (): Date => new Date() };
