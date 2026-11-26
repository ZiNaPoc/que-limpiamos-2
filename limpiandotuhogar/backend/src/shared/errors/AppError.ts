/** Error de negocio con status HTTP. Su `message` se muestra al usuario. */
export class AppError extends Error {
  constructor(
    public status: number,
    message: string,
    public codigo?: string,
  ) {
    super(message);
    this.name = "AppError";
  }
}
