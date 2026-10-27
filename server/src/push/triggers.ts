/**
 * Decides who gets a push notification after a commit, and what it says.
 *
 *   love tap (nudges)            → partner, channel "love"     (always)
 *   chat message                 → partner, channel "messages" (prefs.messages)
 *   ringing call                 → partner, channel "calls"    (always; rings in quiet hours too)
 *   mood change                  → partner, channel "updates"  (prefs.mood)
 *   love note                    → recipient, "updates"        (prefs.messages)
 *   daily question answered      → partner, "updates"          (prefs.dailyQuestion)
 *
 * Nobody is pushed about their own actions. A partner who turned on
 * "mute my partner" gets nothing. In quiet hours (22:00–07:00 in the
 * recipient's time zone) pushes arrive silently, except calls.
 */
import { pool } from "../db.js";
import { adminDelete, adminGet, adminQuery } from "../store.js";
import { isPlainObject, isTs, type Data, type Json } from "../values.js";
import { pushSender } from "./fcm.js";

export interface Change {
  path: string;
  before: Data | null;
  after: Data | null;
}

type Channel = "love" | "messages" | "calls" | "updates";
type Pref = "messages" | "mood" | "dailyQuestion" | null;

interface Push {
  coupleId: string;
  to: string;
  pref: Pref;
  channel: Channel;
  title: string;
  /** Body for the recipient; may use their time zone. */
  body: (timeZone: string | null) => string;
  /** Collapse key: a newer push with the same tag replaces the older one. */
  tag?: string;
  ttlMs: number;
  data: Record<string, string>;
}

const LOVE: Record<string, [string, string]> = {
  thinking: ["is thinking of you", "💭"],
  love: ["sent you love", "❤️"],
  miss: ["misses you", "🥺"],
  hug: ["sent you a hug", "🤗"],
  kiss: ["sent you a kiss", "😘"],
};

const MOODS: Record<string, [string, string]> = {
  happy: ["happy", "😊"],
  loved: ["loved", "🥰"],
  calm: ["calm", "😌"],
  tired: ["tired", "😴"],
  stressed: ["stressed", "😖"],
  sad: ["sad", "🥺"],
  missing: ["like they're missing you", "🫂"],
};

const DAY = 24 * 3600_000;

function str(v: Json | undefined): string | null {
  return typeof v === "string" ? v : null;
}

function tsMs(v: Json | undefined): number | null {
  return isTs(v) ? Date.parse(v.$ts) : null;
}

function short(text: string, max = 120): string {
  const chars = [...text.trim()];
  return chars.length <= max ? chars.join("") : chars.slice(0, max - 1).join("") + "…";
}

function messagePreview(d: Data): string | null {
  switch (str(d.type)) {
    case "text":
      return short(str(d.text) ?? "");
    case "image":
      return "📷 Photo";
    case "video":
      return "🎥 Video";
    case "voice":
      return "🎤 Voice message";
    case "sticker":
      return str(d.text) ? `💌 ${short(str(d.text)!)}` : "💌 Sticker";
    default:
      return null; // call logs, "chat cleared" and other system lines
  }
}

function formatWhen(ms: number, timeZone: string | null): string {
  try {
    return new Intl.DateTimeFormat("en-IN", {
      day: "numeric",
      month: "short",
      hour: "numeric",
      minute: "2-digit",
      timeZone: timeZone ?? "Asia/Kolkata",
    }).format(new Date(ms));
  } catch {
    return new Date(ms).toUTCString();
  }
}

function inQuietHours(timeZone: string | null, now = new Date()): boolean {
  let hour: number;
  try {
    hour = Number(new Intl.DateTimeFormat("en-GB", { hour: "numeric", hourCycle: "h23", timeZone: timeZone ?? "Asia/Kolkata" }).format(now));
  } catch {
    hour = now.getUTCHours();
  }
  return hour >= 22 || hour < 7;
}

/** What each change means as a push (before looking up the people). */
function pushesFor(actor: string, c: Change, now: number): Omit<Push, "title" | "body"> & { kind: string; extra: Data } | null {
  const segs = c.path.split("/");
  if (segs[0] !== "couples" || segs.length !== 4) return null;
  const [, coupleId, col, id] = segs;
  const created = !c.before && !!c.after;
  const a = c.after;
  if (!a) return null;

  switch (col) {
    case "nudges":
      if (!created || a.senderId !== actor) return null;
      return { kind: "love", coupleId, to: "", pref: null, channel: "love", tag: `love-${coupleId}`, ttlMs: DAY, data: { kind: "love", coupleId }, extra: a };
    case "messages":
      if (!created || a.senderId !== actor || !messagePreview(a)) return null;
      return { kind: "message", coupleId, to: "", pref: "messages", channel: "messages", ttlMs: DAY, data: { kind: "message", coupleId }, extra: a };
    case "call": {
      // The app reuses one call document ("current") for every call, so a new
      // call is a new channelName on it, not a new document.
      if (a.status !== "ringing" || a.callerId !== actor) return null;
      const b = c.before;
      if (b && b.status === "ringing" && b.channelName === a.channelName) return null;
      const channel = str(a.channelName) ?? id;
      return { kind: "call", coupleId, to: "", pref: null, channel: "calls", tag: `call-${channel}`, ttlMs: 30_000, data: { kind: "call", coupleId, callId: channel }, extra: a };
    }
    case "moods": {
      if (id !== actor || !str(a.mood) || (c.before && c.before.mood === a.mood)) return null;
      return { kind: "mood", coupleId, to: "", pref: "mood", channel: "updates", tag: `mood-${coupleId}`, ttlMs: DAY, data: { kind: "mood", coupleId }, extra: a };
    }
    case "notes": {
      const to = str(a.recipientId);
      if (!created || a.senderId !== actor || !to || to === actor) return null;
      return { kind: "note", coupleId, to, pref: "messages", channel: "updates", ttlMs: 7 * DAY, data: { kind: "note", coupleId }, extra: a };
    }
    case "dailyQuestions": {
      const after = isPlainObject(a.answers) ? (a.answers as Data) : {};
      const before = c.before && isPlainObject(c.before.answers) ? (c.before.answers as Data) : {};
      if (!(actor in after) || actor in before) return null;
      return { kind: "question", coupleId, to: "", pref: "dailyQuestion", channel: "updates", tag: `question-${coupleId}`, ttlMs: DAY, data: { kind: "question", coupleId }, extra: { answers: after } };
    }
    default:
      void now;
      return null;
  }
}

function wordingFor(kind: string, name: string, extra: Data, recipient: string, now: number): { title: string; body: (tz: string | null) => string } {
  switch (kind) {
    case "love": {
      const [text, emoji] = LOVE[str(extra.kind) ?? "thinking"] ?? LOVE.thinking;
      return { title: `${name} ${text} ${emoji}`, body: () => "Tap to send some love back." };
    }
    case "message":
      return { title: name, body: () => messagePreview(extra) ?? "New message" };
    case "call":
      return { title: name, body: () => (extra.type === "video" ? "📹 Incoming video call" : "📞 Incoming voice call") };
    case "mood": {
      const [label, emoji] = MOODS[str(extra.mood) ?? ""] ?? ["something new", "💭"];
      return { title: `${name} is feeling ${label} ${emoji}`, body: () => (str(extra.note) ? short(str(extra.note)!) : "Tap to check in.") };
    }
    case "note": {
      const at = tsMs(extra.deliverAt);
      if (at === null || at <= now + 60_000) {
        return { title: `💌 ${name} sent you a love note`, body: () => "Tap to read it." };
      }
      return { title: `💌 ${name} sealed a love note for you`, body: (tz) => `It opens ${formatWhen(at, tz)}.` };
    }
    case "question": {
      const answers = extra.answers as Data;
      const mine = recipient in answers;
      return {
        title: `${name} answered today's question`,
        body: () => (mine ? "See what they said 💬" : "Your turn! ✍️"),
      };
    }
    default:
      return { title: name, body: () => "" };
  }
}

/** Runs after a successful commit by a user. Never throws. */
export async function pushAfterCommit(actor: string, changes: Change[]): Promise<void> {
  const now = Date.now();
  for (const c of changes) {
    try {
      const p = pushesFor(actor, c, now);
      if (!p) continue;
      const couple = await adminGet(pool, `couples/${p.coupleId}`);
      if (!couple.exists) continue;
      const members = Array.isArray(couple.data!.memberIds) ? (couple.data!.memberIds as Json[]).filter((m): m is string => typeof m === "string") : [];
      if (!members.includes(actor)) continue;
      const recipients = p.to ? [p.to] : members.filter((m) => m !== actor);
      const sender = await adminGet(pool, `users/${actor}`);
      for (const to of recipients) {
        if (!members.includes(to) || to === actor) continue;
        const user = await adminGet(pool, `users/${to}`);
        if (!user.exists || user.data!.coupleId !== p.coupleId) continue;
        if (user.data!.mutePartner === true) continue;
        const prefs = isPlainObject(user.data!.notificationPrefs) ? (user.data!.notificationPrefs as Data) : {};
        if (p.pref && prefs[p.pref] === false) continue;
        const nicknames = isPlainObject(couple.data!.nicknames) ? (couple.data!.nicknames as Data) : {};
        const name =
          str(nicknames[to])?.trim() || str(sender.data?.nickname)?.trim() || str(sender.data?.displayName)?.trim() || "Your partner";
        const { title, body } = wordingFor(p.kind, name, p.extra, to, now);
        await deliver(to, { ...p, to, title, body }, prefs.quietHours === true);
      }
    } catch (e) {
      console.error("Push: could not handle", c.path, (e as Error).message);
    }
  }
}

async function deliver(uid: string, push: Push, quietHours: boolean): Promise<void> {
  const tokens = await adminQuery(pool, { collection: `users/${uid}/pushTokens`, limit: 20 });
  // One send per time zone, so quiet hours and dates follow each phone.
  type Group = { tz: string | null; tokens: string[]; paths: Map<string, string> };
  const byZone = new Map<string, Group>();
  for (const t of tokens) {
    const token = str(t.data?.token);
    if (!token) continue;
    const tz = str(t.data?.timeZone);
    const key = tz ?? "";
    const g: Group = byZone.get(key) ?? { tz, tokens: [], paths: new Map<string, string>() };
    g.tokens.push(token);
    g.paths.set(token, t.path);
    byZone.set(key, g);
  }
  for (const g of byZone.values()) {
    const silent = quietHours && push.channel !== "calls" && inQuietHours(g.tz);
    const dead = await pushSender().send(g.tokens, {
      notification: { title: push.title, body: push.body(g.tz) },
      data: push.data,
      android: {
        priority: "high",
        ttl: push.ttlMs,
        collapseKey: push.tag,
        notification: {
          channelId: silent ? "quiet" : push.channel,
          tag: push.tag,
          visibility: "private",
          ...(silent ? {} : { defaultSound: true, defaultVibrateTimings: true }),
        },
      },
    });
    // Phones that uninstalled the app or reset their token.
    for (const token of dead) {
      const path = g.paths.get(token);
      if (!path) continue;
      const c = await pool.connect();
      try {
        await adminDelete(c, path);
      } finally {
        c.release();
      }
    }
  }
}
