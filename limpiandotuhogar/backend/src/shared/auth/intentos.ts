/**
 * Bloqueo temporal PROGRESIVO por intentos fallidos de inicio de sesión (nunca permanente).
 *
 * - Cada clave (p. ej. "cliente:ident:ana@x.com" o "cliente:cuenta:12") acumula fallos.
 * - Pasados los intentos gratis, cada fallo nuevo bloquea por el siguiente escalón
 *   (1, 5, 15, 30, 60 min); el último es el tope.
 * - Un login correcto borra el contador; sin fallos durante `olvidoHoras`, también.
 * - Se aplica IGUAL a correos o teléfonos que no existen: así la respuesta no revela qué
 *   cuentas existen.
 *
 * Los contadores viven en memoria: Render corre una sola instancia y, si se reinicia, se
 * pierden (aceptable). Con varias instancias habría que moverlos a una tabla o a Redis.
 */

/** Reloj sustituible SOLO por las pruebas automatizadas (para no esperar minutos reales). */
export const reloj = { ahora: (): number => Date.now() };

type Estado = { fallos: number; bloqueadoHasta: number; ultimoFallo: number };

export type OpcionesIntentos = { gratis: number; escalonesMin: number[]; olvidoHoras: number; maxClaves?: number };

export class ControlDeIntentos {
  private readonly estados = new Map<string, Estado>();
  private operaciones = 0;

  constructor(private readonly opciones: OpcionesIntentos) {}

  /** Segundos de bloqueo que faltan considerando todas las claves (0 = puede intentar). */
  esperaSegundos(claves: string[]): number {
    const ahora = reloj.ahora();
    let maximo = 0;
    for (const clave of claves) {
      const estado = this.vigente(clave, ahora);
      if (estado && estado.bloqueadoHasta > ahora) maximo = Math.max(maximo, estado.bloqueadoHasta - ahora);
    }
    return Math.ceil(maximo / 1000);
  }

  registrarFallo(claves: string[]): void {
    const ahora = reloj.ahora();
    for (const clave of claves) {
      const estado = this.vigente(clave, ahora) ?? { fallos: 0, bloqueadoHasta: 0, ultimoFallo: 0 };
      estado.fallos += 1;
      estado.ultimoFallo = ahora;
      const exceso = estado.fallos - this.opciones.gratis;
      if (exceso > 0) {
        const escalones = this.opciones.escalonesMin;
        const minutos = escalones[Math.min(exceso - 1, escalones.length - 1)] ?? 60;
        estado.bloqueadoHasta = ahora + minutos * 60_000;
      }
      this.estados.set(clave, estado);
    }
    this.mantenimiento(ahora);
  }

  registrarExito(claves: string[]): void {
    for (const clave of claves) this.estados.delete(clave);
  }

  /** Estado de una clave, o undefined si ya se "olvidó" (sin fallos recientes y sin bloqueo). */
  private vigente(clave: string, ahora: number): Estado | undefined {
    const estado = this.estados.get(clave);
    if (!estado) return undefined;
    const olvidado = ahora - estado.ultimoFallo > this.opciones.olvidoHoras * 3_600_000 && estado.bloqueadoHasta <= ahora;
    if (olvidado) {
      this.estados.delete(clave);
      return undefined;
    }
    return estado;
  }

  /** Limpieza periódica y tope de memoria (el límite por IP ya frena la creación masiva de claves). */
  private mantenimiento(ahora: number): void {
    this.operaciones += 1;
    if (this.operaciones % 500 !== 0 && this.estados.size <= (this.opciones.maxClaves ?? 50_000)) return;
    for (const clave of [...this.estados.keys()]) this.vigente(clave, ahora);
    const maximo = this.opciones.maxClaves ?? 50_000;
    if (this.estados.size > maximo) {
      // Se descartan primero las claves sin bloqueo activo y con el fallo más antiguo.
      const ordenadas = [...this.estados.entries()]
        .filter(([, e]) => e.bloqueadoHasta <= ahora)
        .sort((a, b) => a[1].ultimoFallo - b[1].ultimoFallo);
      for (const [clave] of ordenadas.slice(0, this.estados.size - maximo)) this.estados.delete(clave);
    }
  }
}

/** Claves de un intento: el identificador escrito y, si existe la cuenta, su id. */
export function clavesDeIntento(audiencia: string, identificador: { correo: string } | { telefono: string }, idCuenta?: number): string[] {
  const valor = "correo" in identificador ? `correo:${identificador.correo}` : `telefono:${identificador.telefono}`;
  return idCuenta ? [`${audiencia}:${valor}`, `${audiencia}:cuenta:${idCuenta}`] : [`${audiencia}:${valor}`];
}
