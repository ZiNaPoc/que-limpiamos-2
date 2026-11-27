import { Prisma } from "../../../generated/prisma/client";

/**
 * Si el error es un UNIQUE violado (P2002), devuelve cuál de los campos indicados chocó
 * (buscándolo en los metadatos del error), o "otro" si no se puede saber. Si no es P2002,
 * devuelve null. Sirve para dar un mensaje claro cuando dos registros llegan a la vez.
 */
export function campoDuplicado<T extends string>(error: unknown, campos: readonly T[]): T | "otro" | null {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") return null;
  const meta = JSON.stringify(error.meta ?? {}).toLowerCase();
  return campos.find((c) => meta.includes(c.toLowerCase())) ?? "otro";
}
