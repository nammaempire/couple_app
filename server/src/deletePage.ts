/**
 * GET /delete-account: the public page Google Play asks for ("Delete account
 * URL" in the Data safety form). It explains how to delete the account in the
 * app, what is deleted and kept, and how to ask for deletion without the app.
 */
import type { FastifyInstance } from "fastify";
import { config } from "./config.js";
import { COMPANY, esc, page } from "./legal.js";


export function deletePageHtml(supportEmail: string): string {
  const email = supportEmail.trim();
  const request = email
    ? `<p>Can't open the app? Email <a href="mailto:${esc(email)}?subject=Delete%20my%20Us%20account">${esc(email)}</a>
       from the email on your account, or tell us the mobile number you sign in with. We'll confirm it's you
       and delete the account within 30 days.</p>`
    : `<p>Can't open the app? Reinstall it and sign in, then follow the steps above.</p>`;
  return page(
    "Delete your Us account",
    `<h1>Delete your Us account</h1>
<p class="muted">Us — the private app for couples, by ${esc(COMPANY)}.</p>
<nav><a href="/privacy">Privacy policy</a><a href="/terms">Terms of use</a></nav>
<h2>In the app</h2>
<ol>
  <li>Open Us and go to the <b>Us</b> tab.</li>
  <li>Scroll to the bottom and tap <b>Delete my account</b>.</li>
  <li>Type DELETE, confirm it's you (password, Google or an SMS code) and the account is deleted at once.</li>
</ol>
<h2>What is deleted</h2>
<ul>
  <li>Your profile, photo, avatar, phone number lookup and sign-in.</li>
  <li>Your pairing ends, and everything the two of you shared is deleted for both of you: chat, photos,
      videos, voice messages, memories, plans, notes, music, games and the private vault.</li>
  <li>Your notification and security settings on our server.</li>
</ul>
<h2>What is kept</h2>
<ul>
  <li>Records of Google Play purchases (product, date and the account ids involved), which we must keep for
      refunds and tax. They hold no messages, photos or other content.</li>
  <li>Technical server logs, which are deleted automatically after a short time.</li>
</ul>
<h2>Without the app</h2>
${request}`,
  );
}

export async function registerDeletePage(app: FastifyInstance): Promise<void> {
  app.get("/delete-account", async (_req, reply) => {
    reply.header("content-type", "text/html; charset=utf-8");
    reply.header("cache-control", "public, max-age=3600");
    return deletePageHtml(config.supportEmail);
  });
}
