import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { Firestore, GeoPoint, Timestamp } from "firebase-admin/firestore";
import {
  ArgError,
  cleanString,
  convertDoc,
  convertMetadata,
  convertValue,
  genericPath,
  parseArgs,
  parseStorageUrl,
  rewriteString,
  serverAcceptsPath,
  type ConvertCtx,
} from "../scripts/import-lib.js";

const BUCKET = "together-48033.firebasestorage.app";

function ctx() {
  const warnings: string[] = [];
  const rewrites: string[] = [];
  const foreign: string[] = [];
  const c: ConvertCtx = {
    sourceBucket: BUCKET,
    toUrl: (p) => `https://api.example.com/f/${p}?t=sig`,
    warn: (m) => warnings.push(m),
    onRewrite: (p) => rewrites.push(p),
    onForeignUrl: (u) => foreign.push(u),
  };
  return { c, warnings, rewrites, foreign };
}

const fbUrl = (path: string, bucket = BUCKET) =>
  `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=1b2c-3d4e`;

describe("convertValue", () => {
  it("converts Firestore types", () => {
    const { c, warnings } = ctx();
    const db = new Firestore({ projectId: "demo" });
    const when = new Date("2025-02-03T04:05:06.789Z");
    const out = convertDoc(
      {
        s: "hi",
        n: 3.5,
        b: true,
        nul: null,
        ts: Timestamp.fromDate(when),
        date: when,
        geo: new GeoPoint(12.97, 77.59),
        ref: db.doc("users/u1"),
        bytes: Buffer.from("hello"),
        nested: { list: [1, { at: Timestamp.fromMillis(0) }, [true]], deeper: { x: "y" } },
      },
      c,
      "users/u1",
    );
    assert.deepEqual(out, {
      s: "hi",
      n: 3.5,
      b: true,
      nul: null,
      ts: { $ts: "2025-02-03T04:05:06.789Z" },
      date: { $ts: "2025-02-03T04:05:06.789Z" },
      geo: { latitude: 12.97, longitude: 77.59 },
      ref: "users/u1",
      bytes: Buffer.from("hello").toString("base64"),
      nested: { list: [1, { at: { $ts: "1970-01-01T00:00:00.000Z" } }, [true]], deeper: { x: "y" } },
    });
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /users\/u1 bytes: bytes stored as a base64 string/);
  });

  it("drops $ fields (at any depth) with a warning", () => {
    const { c, warnings } = ctx();
    const out = convertDoc({ ok: 1, $ts: "x", m: { $sv: "delete", keep: 2 } }, c, "d/1");
    assert.deepEqual(out, { ok: 1, m: { keep: 2 } });
    assert.equal(warnings.length, 2);
    assert.ok(warnings.some((w) => w.includes("m.$sv")));
  });

  it("turns non-finite numbers into null and drops unknown objects", () => {
    const { c, warnings } = ctx();
    assert.equal(convertValue(NaN, c, "f"), null);
    assert.equal(convertValue(Infinity, c, "f"), null);
    class Weird {}
    assert.equal(convertValue(new Weird(), c, "f"), undefined);
    assert.deepEqual(convertDoc({ a: [new Weird(), 1] }, c, "d/1"), { a: [1] });
    assert.equal(warnings.length, 4);
  });

  it("cleans characters Postgres rejects", () => {
    const { c, warnings } = ctx();
    assert.equal(cleanString("a\u0000b", c, "f"), "ab");
    assert.equal(cleanString("x\ud83dy", c, "f"), "x�y");
    assert.equal(cleanString("ok 😀", c, "f"), "ok 😀");
    assert.equal(warnings.length, 2);
  });
});

describe("storage URL rewriting", () => {
  it("parses the URL forms the app may have saved", () => {
    const p = "couples/c1/photos/a b+c.jpg";
    assert.deepEqual(parseStorageUrl(fbUrl(p)), { bucket: BUCKET, path: p });
    assert.deepEqual(parseStorageUrl(`https://storage.googleapis.com/${BUCKET}/couples/c1/photos/a%20b%2Bc.jpg`), { bucket: BUCKET, path: p });
    assert.deepEqual(parseStorageUrl(`gs://${BUCKET}/couples/c1/voice/v.m4a`), { bucket: BUCKET, path: "couples/c1/voice/v.m4a" });
    assert.deepEqual(parseStorageUrl(`https://${BUCKET}.storage.googleapis.com/users/u1/profile/p.jpg?x=1`), {
      bucket: BUCKET,
      path: "users/u1/profile/p.jpg",
    });
    assert.equal(parseStorageUrl("https://example.com/a.jpg"), null);
    assert.equal(parseStorageUrl("not a url"), null);
    assert.equal(parseStorageUrl("https://firebasestorage.googleapis.com/v0/b/x/o/%E0%A4%A"), null);
  });

  it("rewrites only whole-string links of the source bucket, anywhere in a document", () => {
    const { c, rewrites, foreign } = ctx();
    const other = fbUrl("couples/c1/photos/x.jpg", "someone-else.appspot.com");
    const out = convertDoc(
      {
        imageUrl: fbUrl("couples/c1/photos/p1.jpg"),
        media: [{ url: `gs://${BUCKET}/couples/c1/videos/v1.mp4`, thumbUrl: fbUrl("couples/c1/photos/t1.jpg") }],
        text: `look ${fbUrl("couples/c1/photos/p1.jpg")}`,
        other,
        plain: "https://example.com/x",
      },
      c,
      "couples/c1/messages/m1",
    );
    assert.equal(out.imageUrl, "https://api.example.com/f/couples/c1/photos/p1.jpg?t=sig");
    assert.deepEqual(out.media, [
      { url: "https://api.example.com/f/couples/c1/videos/v1.mp4?t=sig", thumbUrl: "https://api.example.com/f/couples/c1/photos/t1.jpg?t=sig" },
    ]);
    assert.ok((out.text as string).startsWith("look https://firebasestorage"));
    assert.equal(out.other, other);
    assert.equal(out.plain, "https://example.com/x");
    assert.deepEqual(rewrites, ["couples/c1/photos/p1.jpg", "couples/c1/videos/v1.mp4", "couples/c1/photos/t1.jpg"]);
    assert.deepEqual(foreign, [other]);
  });

  it("leaves already-rewritten links alone", () => {
    const { c, rewrites } = ctx();
    const u = "https://api.example.com/f/couples/c1/photos/p1.jpg?t=sig";
    assert.equal(rewriteString(u, c), u);
    assert.equal(rewrites.length, 0);
  });
});

describe("misc", () => {
  it("convertMetadata lower-cases keys and drops the download token", () => {
    const w: string[] = [];
    assert.deepEqual(
      convertMetadata({ senderId: "u1", firebaseStorageDownloadTokens: "tok", n: 3, "bad key": "x", emoji: "😀" }, (m) => w.push(m), "f"),
      { senderid: "u1", n: "3" },
    );
    assert.equal(w.length, 2);
  });

  it("parseArgs", () => {
    assert.deepEqual(parseArgs(["--dry-run", "--only=storage", "--collection=users,couples", "--collection=invites", "-v"]), {
      dryRun: true,
      only: "storage",
      collections: ["users", "couples", "invites"],
      verbose: true,
      concurrency: 4,
      help: false,
    });
    assert.throws(() => parseArgs(["--only=both"]), ArgError);
    assert.throws(() => parseArgs(["--nope"]), ArgError);
  });

  it("genericPath and serverAcceptsPath", () => {
    assert.equal(genericPath("legacy/a1/items/b2"), "legacy/{id}/items/{id}");
    assert.ok(serverAcceptsPath("couples/c1/photos/x.jpg"));
    assert.ok(!serverAcceptsPath("couples/c1/photos/a b.jpg"));
  });
});
