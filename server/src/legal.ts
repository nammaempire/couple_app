/**
 * The public legal pages Google Play (and later the App Store) ask for:
 *   GET /privacy         privacy policy
 *   GET /terms           terms of use
 *   GET /delete-account  how to delete an account (deletePage.ts)
 *
 * Written for what the app actually does; update them when that changes
 * (a new kind of data, a new service provider). The contact email, address
 * and Grievance Officer come from SUPPORT_EMAIL, COMPANY_ADDRESS and
 * GRIEVANCE_OFFICER.
 */
import type { FastifyInstance } from "fastify";
import { config } from "./config.js";

export const COMPANY = "Reset95 Private Limited";
export const APP = "Us";
/** When the current versions of the policy and terms took effect. */
export const EFFECTIVE_DATE = "2 November 2026";

export interface LegalContact {
  email: string;
  address: string;
  grievanceOfficer: string;
}

export const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function contactFromConfig(): LegalContact {
  return { email: config.supportEmail, address: config.companyAddress, grievanceOfficer: config.grievanceOfficer };
}

/** The email as a link, or a fallback when none is configured. */
function emailLink(c: LegalContact, subject: string): string {
  const e = c.email.trim();
  return e
    ? `<a href="mailto:${esc(e)}?subject=${encodeURIComponent(subject)}">${esc(e)}</a>`
    : "the contact option in the app (Us tab)";
}

/** One page in the shared style. */
export function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>
  :root{--ink:#2a2124;--muted:#6d5f63;--accent:#c2185b;--bg:#fffafb;--rule:#f0dfe4}
  @media (prefers-color-scheme: dark){:root{--ink:#f4e9ec;--muted:#b9a8ad;--accent:#ff7fae;--bg:#1b1416;--rule:#3a2a2f}}
  body{font:16px/1.65 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:720px;margin:0 auto;padding:24px 16px 48px;color:var(--ink);background:var(--bg)}
  h1{font-size:28px;line-height:1.25;margin:0 0 6px} h2{font-size:19px;margin:32px 0 8px;padding-top:12px;border-top:1px solid var(--rule)}
  h3{font-size:16px;margin:18px 0 4px} li{margin:4px 0} a{color:var(--accent)} .muted{color:var(--muted);font-size:14px}
  .box{background:rgba(194,24,91,.06);border:1px solid var(--rule);border-radius:12px;padding:12px 16px;margin:16px 0}
  nav{font-size:14px;margin-top:8px} nav a{margin-right:14px}
</style></head><body>
${body}
<p class="muted" style="margin-top:40px">${esc(APP)} is made by ${esc(COMPANY)}.</p>
</body></html>`;
}

const nav = `<nav><a href="/privacy">Privacy policy</a><a href="/terms">Terms of use</a><a href="/delete-account">Delete your account</a></nav>`;

function companyBlock(c: LegalContact): string {
  const addr = c.address.trim();
  return `${esc(COMPANY)}${addr ? `<br>${esc(addr)}` : ""}<br>Email: ${emailLink(c, "Us app")}`;
}

export function privacyHtml(c: LegalContact = contactFromConfig()): string {
  const officer = c.grievanceOfficer.trim();
  return page(
    `${APP} — Privacy policy`,
    `<h1>Privacy policy</h1>
<p class="muted">${esc(APP)} by ${esc(COMPANY)} · Effective ${EFFECTIVE_DATE}</p>
${nav}

<div class="box">
<b>In short.</b> ${esc(APP)} is a private space for two people. What you share is seen by you and your partner,
not by other users. We keep it on our servers so it reaches both of your phones, we don't sell it, we don't show
ads, and we don't track your location. The Private vault is end-to-end encrypted, so we can't read it. You can
delete your account and your data from the app at any time.
</div>

<h2>1. Who we are</h2>
<p>${esc(COMPANY)} ("we", "us") makes the ${esc(APP)} app and decides how the personal data in it is used. Under
India's Digital Personal Data Protection Act, 2023 we are the Data Fiduciary for that data. Our contact details are
at the end of this policy.</p>

<h2>2. What we collect</h2>
<h3>Your account</h3>
<ul>
  <li><b>Sign-in details</b>, depending on how you sign in: your mobile number; your email address and password
      (stored by Google Firebase, never by us in readable form); or your Google account's name, email and photo.</li>
  <li><b>Profile</b>: your name, nickname, birthday (optional), profile photo (optional) and cartoon avatar.</li>
  <li><b>Your mobile number lookup</b>: if you signed in with a mobile number, your partner can find you by it to
      pair. A number can be looked up one at a time, never listed.</li>
</ul>
<h3>What you share with your partner</h3>
<ul>
  <li>Chat messages, photos, videos, voice messages, stickers, reactions and pinned messages.</li>
  <li>Memories and albums, love notes (including sealed ones), calendar events, date plans, bucket list, wishlist,
      places, shared expenses, songs and videos you save, moods, daily question answers, love taps and games.</li>
  <li>Memory books you make (PDF files).</li>
  <li><b>Private vault</b>: its photos and private chat are encrypted on your phone before upload, and only your
      approved phones hold the keys. We store only encrypted data we can't open.</li>
</ul>
<h3>Calls</h3>
<p>Voice and video calls go directly between your two phones, encrypted (WebRTC). When a network blocks a direct
connection, the call passes through our relay server, still encrypted; the relay can't hear or see it. We don't
record calls. We keep a call record in your chat (voice or video, answered or missed, and how long).</p>
<h3>Your phones and safety features</h3>
<ul>
  <li><b>Phone name and an app-made phone id</b>, for sign-in protection (so a new phone using your number can be
      checked) and to show you which phones use your account.</li>
  <li><b>Security notices</b>, such as a sign-in from a new phone.</li>
  <li><b>Screenshot alerts</b>: if you take a screenshot while the chat is on screen, a line saying so is added
      to the chat for both of you (Android 14 and later). The app learns only that a screenshot was taken, never
      the image.</li>
  <li><b>Notification token and time zone</b> of each phone, to send you notifications and respect quiet hours.</li>
  <li><b>App lock</b> PIN and fingerprint settings stay on your phone; we never receive your PIN or fingerprint.</li>
</ul>
<h3>Purchases</h3>
<p>Premium, gifts and memory books are bought through Google Play. Google handles the payment; we never see your
card or bank details. We receive and keep the purchase details (product, order id, purchase token, dates, which
couple it is for and who bought it) to give you what you paid for.</p>
<h3>If you contact us</h3>
<p>Your email and what you write to us.</p>

<h2>3. What we don't collect</h2>
<ul>
  <li><b>Your location.</b> Places you save are what you type in.</li>
  <li><b>Your contacts</b>, call history or SMS. (A sign-in code sent by SMS may be read automatically by Android
      to fill it in.)</li>
  <li><b>Your selfie.</b> "Scan my face" for the avatar runs entirely on your phone; the photo is deleted right
      after and is never uploaded. Only the avatar's choices (skin tone, hair and so on) are saved.</li>
  <li><b>Your gallery.</b> The app only gets the photos and videos you pick.</li>
  <li><b>Advertising or tracking data.</b> There are no ads and no third-party analytics or advertising tools.</li>
</ul>

<h2>4. How we use it</h2>
<ul>
  <li>To run the app: deliver what you share to your partner's phone, keep it in sync, and show it back to you.</li>
  <li>To send notifications you allow (messages, love taps, calls, notes, moods, the daily question).</li>
  <li>To keep accounts safe (sign-in protection, security notices) and prevent abuse.</li>
  <li>To give you purchases, and to keep records the law requires.</li>
  <li>To answer you when you contact us, and to fix problems.</li>
</ul>
<p>We use your data only for these purposes, on the basis of your consent when you create an account and use
each feature, and where the law requires us to. You can withdraw consent by deleting your account; this doesn't
affect what was done before.</p>

<h2>5. Who can see your data</h2>
<ul>
  <li><b>Your partner</b> sees what you share in your space. You can't pair with more than one person, and nobody
      else can join your space.</li>
  <li><b>Our service providers</b>, only to run the app for us:
    <ul>
      <li>Railway (Railway Corp.): our servers, database and file storage, in Singapore.</li>
      <li>Google Firebase (Google LLC): sign-in and delivering notifications.</li>
      <li>Google Play (Google LLC): payments.</li>
      <li>The hosting company of our call relay server, which only passes encrypted call traffic through.</li>
    </ul></li>
  <li><b>Other services you open from the app.</b> Songs and videos you save are links to YouTube, Spotify and
      similar services, and places can open in a maps app. Playing a video inside the app uses YouTube's player.
      Those services' own privacy policies apply to what you do there.</li>
  <li><b>Authorities</b>, only when Indian law requires it (for example a valid court order), or to protect someone's
      safety.</li>
</ul>
<p>We don't sell or rent your personal data, and we don't share it for advertising.</p>

<h2>6. Where it's stored</h2>
<p>Our database and files are in Singapore. Google's services may process data in other countries. Wherever data
goes, we keep it protected as this policy describes and as Indian law requires.</p>

<h2>7. How we protect it</h2>
<ul>
  <li>Everything between the app and our servers is encrypted in transit (HTTPS/TLS).</li>
  <li>Every read and write is checked against access rules on the server: only the two members of a couple can see
      that couple's data.</li>
  <li>The Private vault is end-to-end encrypted; calls are encrypted between the phones.</li>
  <li>App lock, sign-in protection for new phones and screenshot alerts add protection on the phone.</li>
</ul>
<p>No system is perfectly secure. If a breach affects your personal data, we will tell you and the authorities as
the law requires.</p>

<h2>8. How long we keep it</h2>
<ul>
  <li>While your account exists, we keep your data so the app works.</li>
  <li><b>Ending a pairing</b> deletes everything the two of you shared, for both of you, when it takes effect
      (14 days after one asks, or 7 days after both agree), or at once with "I need to leave now".</li>
  <li><b>Deleting your account</b> (Us tab → Delete my account) ends your pairing and deletes your profile, your
      shared space, your files and your sign-in at once.</li>
  <li>Purchase records are kept for as long as tax and accounting laws require, then deleted.</li>
  <li>We keep daily backups of the database, encrypted, for 30 days, so deleted data also leaves the backups
      within 30 days.</li>
</ul>

<h2>9. Your rights</h2>
<p>You can:</p>
<ul>
  <li><b>See and correct</b> your data: most of it is in the app, and you can edit your profile at any time.</li>
  <li><b>Delete</b> it: delete single messages and items in the app, end your pairing, or delete your account. You can
      also <a href="/delete-account">ask us to delete it</a>.</li>
  <li><b>Ask</b> what data we hold about you and who we've shared it with.</li>
  <li><b>Withdraw consent</b> by deleting your account, and turn off notifications at any time.</li>
  <li><b>Nominate</b> someone to exercise these rights for you if you die or can't act.</li>
  <li><b>Complain</b> to our Grievance Officer (below). If you're not satisfied, you can go to the Data Protection
      Board of India.</li>
</ul>
<p>Write to ${emailLink(c, "Privacy request")}. We'll answer within 30 days (we may need to confirm it's you).</p>

<h2>10. Age</h2>
<p>${esc(APP)} is for adults only. You must be 18 or older to use it. We don't knowingly collect data from anyone
under 18; if we learn we have, we delete the account.</p>

<h2>11. Changes</h2>
<p>When we change this policy, we'll update the date at the top and, for important changes, tell you in the app
before they apply.</p>

<h2>12. Contact and Grievance Officer</h2>
<p>${companyBlock(c)}</p>
<p>Grievance Officer${officer ? `: ${esc(officer)}` : ""}, at the email above. We acknowledge complaints within
24 hours and resolve them within 30 days.</p>`,
  );
}

export function termsHtml(c: LegalContact = contactFromConfig()): string {
  return page(
    `${APP} — Terms of use`,
    `<h1>Terms of use</h1>
<p class="muted">${esc(APP)} by ${esc(COMPANY)} · Effective ${EFFECTIVE_DATE}</p>
${nav}

<div class="box">
<b>In short.</b> Be 18 or older, be kind and lawful, share only what's yours to share, and respect your partner's
privacy. Your content stays yours. Either of you can end the pairing, and that deletes your shared space for both.
Paid features are sold through Google Play.
</div>

<h2>1. These terms</h2>
<p>These terms are an agreement between you and ${esc(COMPANY)} ("we", "us") for using the ${esc(APP)} app and its
services. By creating an account or using ${esc(APP)}, you agree to them and to our
<a href="/privacy">privacy policy</a>. If you don't agree, please don't use ${esc(APP)}.</p>

<h2>2. Who can use ${esc(APP)}</h2>
<ul>
  <li>You must be <b>18 or older</b> and able to make a binding agreement.</li>
  <li>One person per account. Give true details, and keep your sign-in safe: you're responsible for what happens
      on your account. Tell us if you think someone else has used it.</li>
</ul>

<h2>3. Your shared space</h2>
<ul>
  <li>${esc(APP)} pairs exactly two people. Pair only with someone who wants to pair with you.</li>
  <li>Your partner sees what you share there, and can keep copies (for example by saving a photo or taking a
      screenshot). Screenshot alerts can tell you about screenshots, but can't prevent every copy. Share only what
      you're comfortable with your partner keeping.</li>
  <li><b>Ending a pairing</b>: either partner can end it. It takes effect 14 days after one asks, or 7 days after
      both agree, or at once with "I need to leave now". Then everything the two of you shared is deleted for both
      of you, and can't be recovered. Save anything you want to keep before then.</li>
</ul>

<h2>4. Your content</h2>
<ul>
  <li>What you post stays yours. You give us a limited licence to store, copy, process and show it, only to run
      ${esc(APP)} for you and your partner (for example to deliver it, make thumbnails, or build a memory book you
      ask for). This licence ends when the content is deleted.</li>
  <li>Only share content you have the right to share, and never anything about someone else that they haven't agreed
      to.</li>
</ul>

<h2>5. What's not allowed</h2>
<p>Don't use ${esc(APP)} to:</p>
<ul>
  <li>break any law, or help anyone else break it;</li>
  <li>harass, threaten, stalk, blackmail or control anyone, including your partner;</li>
  <li>share intimate images of anyone without their consent, or any sexual content involving anyone under 18
      (we report such content to the authorities);</li>
  <li>share content that is hateful, violent, or infringes someone's copyright or privacy;</li>
  <li>pair with or monitor someone without their knowledge;</li>
  <li>attack, overload, probe or reverse-engineer the app or our servers, or get around its security or limits;</li>
  <li>resell ${esc(APP)}, or make accounts with automated tools.</li>
</ul>
<p>If you see misuse, tell us at ${emailLink(c, "Report misuse")}.</p>

<h2>6. The Private vault</h2>
<p>The vault is for adults (both partners 18 or older). It is end-to-end encrypted: the keys are on your phones,
not with us. If both of you lose the phones that hold the keys, we can't recover what's inside.</p>

<h2>7. Calls and notifications</h2>
<p>Calls and notifications depend on your phone, its settings and your network, and may not always connect or
arrive on time. ${esc(APP)} is not a replacement for a phone service: <b>it can't be used to call emergency
services</b>.</p>

<h2>8. Premium, gifts and memory books</h2>
<ul>
  <li>Paid features are sold through Google Play, under Google Play's terms. Prices are shown in the app before you
      buy.</li>
  <li>Premium subscriptions renew automatically until you cancel them in the Google Play Store app. Cancelling stops
      the next renewal; you keep Premium until the end of the period you paid for.</li>
  <li>Premium and gifts belong to your couple's space. They end when the pairing ends or an account is deleted, and
      unused parts aren't refunded except where Google Play's refund policy or the law says so.</li>
  <li>Refunds are handled under Google Play's refund policies and your rights under consumer law.</li>
</ul>

<h2>9. Other services</h2>
<p>Songs and videos are links to services such as YouTube and Spotify. Their terms apply when you use them, and we
aren't responsible for their content.</p>

<h2>10. Changes to ${esc(APP)}</h2>
<p>We keep improving ${esc(APP)}, so features may change, and some may be added or removed. If we stop offering a
paid feature you've paid for, we'll treat you fairly as the law requires.</p>

<h2>11. Ending your use</h2>
<ul>
  <li>You can stop at any time and <a href="/delete-account">delete your account</a> from the app.</li>
  <li>We may suspend or close an account that seriously or repeatedly breaks these terms, or where the law requires
      it. Where we can, we'll tell you why first.</li>
</ul>

<h2>12. Our responsibility</h2>
<ul>
  <li>We work hard to keep ${esc(APP)} working and your data safe, but we provide it "as is", and can't promise it
      will always be available, error-free or that nothing will ever be lost.</li>
  <li>As far as the law allows, we aren't liable for indirect or consequential losses, or for what users share or do.
      Our total liability to you is limited to the amount you paid us in the 12 months before the claim, or ₹1,000 if
      you paid nothing.</li>
  <li>Nothing in these terms limits rights you have under law that can't be limited.</li>
</ul>

<h2>13. Law and disputes</h2>
<p>These terms are governed by the laws of India. Please contact us first, and we'll try to resolve any problem.
Otherwise, the courts at Bengaluru, Karnataka, have jurisdiction.</p>

<h2>14. Changes to these terms</h2>
<p>When we change these terms we'll update the date at the top and, for important changes, tell you in the app
before they apply. If you keep using ${esc(APP)} after that, the new terms apply.</p>

<h2>15. Contact</h2>
<p>${companyBlock(c)}</p>`,
  );
}

export async function registerLegalPages(app: FastifyInstance): Promise<void> {
  const send = (html: () => string) => async (_req: unknown, reply: { header: (k: string, v: string) => unknown }) => {
    reply.header("content-type", "text/html; charset=utf-8");
    reply.header("cache-control", "public, max-age=3600");
    return html();
  };
  app.get("/privacy", send(() => privacyHtml()));
  app.get("/terms", send(() => termsHtml()));
}
