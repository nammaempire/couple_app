import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

// One admin app per instance. On Cloud Functions, FIREBASE_CONFIG supplies the
// project id and default bucket; on the emulators the *_EMULATOR_HOST env vars
// redirect the SDK automatically.
function app() {
  return getApps()[0] ?? initializeApp();
}

export function db(): Firestore {
  return getFirestore(app());
}

export function bucket() {
  return getStorage(app()).bucket();
}
