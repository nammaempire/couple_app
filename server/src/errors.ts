/** Errors the API returns: { error: { code, message, details? } } with an HTTP status. */
export type ErrorCode =
  | "invalid-argument"
  | "unauthenticated"
  | "permission-denied"
  | "not-found"
  | "already-exists"
  | "aborted"
  | "failed-precondition"
  | "resource-exhausted"
  | "unavailable"
  | "internal";

const STATUS: Record<ErrorCode, number> = {
  "invalid-argument": 400,
  unauthenticated: 401,
  "permission-denied": 403,
  "not-found": 404,
  "already-exists": 409,
  aborted: 409,
  "failed-precondition": 412,
  "resource-exhausted": 429,
  unavailable: 503,
  internal: 500,
};

export class ApiError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
  }
  get status(): number {
    return STATUS[this.code];
  }
  toJSON() {
    return { error: { code: this.code, message: this.message, ...(this.details === undefined ? {} : { details: this.details }) } };
  }
}
