import { GoogleAuth } from "google-auth-library";

/**
 * The subset of the Google Play Developer API (androidpublisher v3) we use.
 * Tests inject a fake with setPlayVerifier().
 */
export interface PlayVerifier {
  /** purchases.products.get */
  getProduct(packageName: string, productId: string, token: string): Promise<ProductPurchase>;
  /** purchases.subscriptionsv2.get */
  getSubscription(packageName: string, token: string): Promise<SubscriptionPurchaseV2>;
  /** purchases.products.acknowledge */
  acknowledgeProduct(packageName: string, productId: string, token: string): Promise<void>;
  /** purchases.subscriptions.acknowledge */
  acknowledgeSubscription(packageName: string, subscriptionId: string, token: string): Promise<void>;
}

/** https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products */
export interface ProductPurchase {
  /** 0 purchased, 1 canceled, 2 pending. */
  purchaseState?: number;
  /** 0 not yet acknowledged, 1 acknowledged. */
  acknowledgementState?: number;
  /** 0 not yet consumed, 1 consumed. */
  consumptionState?: number;
  orderId?: string;
  purchaseTimeMillis?: string;
  productId?: string;
  quantity?: number;
}

export type SubscriptionState =
  | "SUBSCRIPTION_STATE_UNSPECIFIED"
  | "SUBSCRIPTION_STATE_PENDING"
  | "SUBSCRIPTION_STATE_ACTIVE"
  | "SUBSCRIPTION_STATE_PAUSED"
  | "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
  | "SUBSCRIPTION_STATE_ON_HOLD"
  | "SUBSCRIPTION_STATE_CANCELED"
  | "SUBSCRIPTION_STATE_EXPIRED"
  | "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED";

/** https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2 */
export interface SubscriptionPurchaseV2 {
  subscriptionState?: SubscriptionState;
  acknowledgementState?: "ACKNOWLEDGEMENT_STATE_UNSPECIFIED" | "ACKNOWLEDGEMENT_STATE_PENDING" | "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
  latestOrderId?: string;
  startTime?: string;
  linkedPurchaseToken?: string;
  lineItems?: Array<{ productId?: string; expiryTime?: string; latestSuccessfulOrderId?: string }>;
}

/** A Play API failure. `status` is the HTTP status (0 for network errors). */
export class PlayApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "PlayApiError";
  }
  /** 400/404/410: the token is unknown or malformed, retrying won't help. */
  get isInvalidToken(): boolean {
    return this.status === 400 || this.status === 404 || this.status === 410;
  }
  /** Worth retrying later (rate limit, server or network error). */
  get isTransient(): boolean {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }
}

const BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";
const enc = encodeURIComponent;

/**
 * REST implementation over google-auth-library (much lighter than `googleapis`).
 * Uses Application Default Credentials: the function's service account in
 * production, or GOOGLE_APPLICATION_CREDENTIALS locally.
 */
export class RestPlayVerifier implements PlayVerifier {
  private readonly auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] });

  private async call<T>(method: "GET" | "POST", url: string): Promise<T> {
    try {
      const client = await this.auth.getClient();
      const res = await client.request<T>({ url, method, ...(method === "POST" ? { data: {} } : {}) });
      return res.data;
    } catch (e) {
      const err = e as { status?: number; response?: { status?: number }; message?: string };
      const status = err.response?.status ?? err.status ?? 0;
      throw new PlayApiError(`Play API ${method} failed (${status}): ${err.message ?? String(e)}`, status);
    }
  }

  getProduct(pkg: string, productId: string, token: string) {
    return this.call<ProductPurchase>("GET", `${BASE}/${enc(pkg)}/purchases/products/${enc(productId)}/tokens/${enc(token)}`);
  }
  getSubscription(pkg: string, token: string) {
    return this.call<SubscriptionPurchaseV2>("GET", `${BASE}/${enc(pkg)}/purchases/subscriptionsv2/tokens/${enc(token)}`);
  }
  async acknowledgeProduct(pkg: string, productId: string, token: string) {
    await this.call("POST", `${BASE}/${enc(pkg)}/purchases/products/${enc(productId)}/tokens/${enc(token)}:acknowledge`);
  }
  async acknowledgeSubscription(pkg: string, subscriptionId: string, token: string) {
    await this.call("POST", `${BASE}/${enc(pkg)}/purchases/subscriptions/${enc(subscriptionId)}/tokens/${enc(token)}:acknowledge`);
  }
}

let verifier: PlayVerifier | undefined;

export function playVerifier(): PlayVerifier {
  return (verifier ??= new RestPlayVerifier());
}

/** Test hook: swap in a fake. Pass undefined to restore the real one. */
export function setPlayVerifier(v: PlayVerifier | undefined): void {
  verifier = v;
}
