/** Structured one-line JSON logs (like firebase-functions' logger). */
type Level = "info" | "warn" | "error";

function write(level: Level, message: string, fields?: Record<string, unknown>): void {
  if (process.env.FUNCTIONS_LOG === "off") return;
  const line = JSON.stringify({ level, time: new Date().toISOString(), message, ...(fields ?? {}) });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

export const logger = {
  info: (m: string, f?: Record<string, unknown>) => write("info", m, f),
  warn: (m: string, f?: Record<string, unknown>) => write("warn", m, f),
  error: (m: string, f?: Record<string, unknown>) => write("error", m, f),
};
