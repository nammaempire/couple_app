/**
 * Dev/test only: starts the server with ALL documents and files open to any
 * signed-in user (test tokens), on PORT. Used by the Dart smoke test.
 */
process.env.AUTH_TEST_MODE = "true";
process.env.NODE_ENV = "test";
process.env.S3_BUCKET = "";
const { setRules } = await import("../src/store.js");
const storage = await import("../src/rules/storage.js");
setRules([{ pattern: "{a}", read: () => true, write: () => true },
  ...["{a}/{b}", "{a}/{b}/{c}/{d}", "{a}/{b}/{c}/{d}/{e}/{f}"].map((pattern) => ({ pattern, read: (c: any) => !!c.auth, write: (c: any) => !!c.auth }))]);
storage.storageRules.push({ pattern: "couples/{c}/photos/{f}", read: (c) => !!c.auth, write: (c) => !!c.auth });
const { migrate } = await import("../src/migrate.js");
await migrate();
const { callables } = await import("../src/functions/index.js");
callables.echo = async (auth, data) => ({ uid: auth.uid, data });
const { buildApp } = await import("../src/app.js");
const app = await buildApp();
await app.listen({ port: Number(process.env.PORT ?? 18080), host: "127.0.0.1" });
console.log("open dev server ready");
