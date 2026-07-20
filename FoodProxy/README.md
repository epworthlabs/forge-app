# Forge Food Proxy

A minimal Express server that stands between the Forge iOS app and FatSecret's Platform API.

**Why this exists:** FatSecret enforces a fixed IP allowlist on OAuth 2.0 token requests and
expects the Client ID/Secret to live on a server, not on individual devices — see
[their OAuth 2.0 guide](https://platform.fatsecret.com/docs/guides/authentication/oauth2). A
mobile app calling FatSecret directly can't satisfy either constraint: each user's phone has a
different, changing IP, and any secret embedded in the app binary can be extracted. This proxy
holds the real credentials, calls FatSecret from one fixed, allowlisted IP, and exposes a single
`/search` endpoint gated by a shared secret the app already knows.

## Local development

```
cp .env.example .env   # fill in FATSECRET_CLIENT_ID, FATSECRET_CLIENT_SECRET, APP_SHARED_SECRET
npm install
npm start
```

Then: `curl -H "X-App-Secret: <your APP_SHARED_SECRET>" "http://localhost:3000/search?q=chicken+breast"`

## Deploying to Render (free tier)

1. Push this repo to GitHub (Render deploys from a connected Git repo).
2. In the Render dashboard: **New +** → **Blueprint**, point it at the repo. `render.yaml` in this
   folder configures the service automatically (free plan, `FoodProxy/` as the root).
3. When prompted, fill in the three env vars: `FATSECRET_CLIENT_ID`, `FATSECRET_CLIENT_SECRET`
   (from the FatSecret dashboard), and `APP_SHARED_SECRET` (make up any long random string — it
   just needs to match what's in the iOS app's `Secrets.swift`).
4. Once deployed, open the service's **Connect** tab in Render and copy its **Outbound IP
   Addresses** (a small fixed list, shared by region — see
   [Render's docs](https://render.com/docs/outbound-ip-addresses)).
5. In the FatSecret dashboard, add those IPs to your application's IP allowlist.
6. Put the deployed service's URL (e.g. `https://forge-food-proxy.onrender.com`) into the app's
   `Secrets.swift` as `fatSecretProxyBaseURL`.

Free tier sleeps after 15 minutes idle — the first search after a gap can take 30–60s to wake it.
If that's noticeable in practice, Render's cheapest paid plan (~$7/mo) keeps it always-on.
