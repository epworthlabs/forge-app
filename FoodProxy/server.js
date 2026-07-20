import express from "express";

const PORT = process.env.PORT || 3000;
const CLIENT_ID = process.env.FATSECRET_CLIENT_ID;
const CLIENT_SECRET = process.env.FATSECRET_CLIENT_SECRET;
const APP_SHARED_SECRET = process.env.APP_SHARED_SECRET;

if (!CLIENT_ID || !CLIENT_SECRET || !APP_SHARED_SECRET) {
  console.error(
    "Missing required env vars: FATSECRET_CLIENT_ID, FATSECRET_CLIENT_SECRET, APP_SHARED_SECRET"
  );
  process.exit(1);
}

// FatSecret enforces a fixed IP allowlist on OAuth 2.0 requests and expects clients to hold
// credentials server-side rather than embedding them on individual devices — this proxy exists
// so the iOS app never sees the FatSecret Client ID/Secret, and all outbound calls originate from
// this host's static IP (see Render's outbound IP addresses docs) rather than a user's phone.
let cachedToken = null; // { value, expiresAt }

async function getAccessToken() {
  if (cachedToken && cachedToken.expiresAt > Date.now()) {
    return cachedToken.value;
  }

  const credentials = Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString("base64");
  const response = await fetch("https://oauth.fatsecret.com/connect/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials&scope=basic",
  });

  if (!response.ok) {
    throw new Error(`token request failed: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  cachedToken = {
    value: data.access_token,
    expiresAt: Date.now() + (data.expires_in - 60) * 1000,
  };
  return cachedToken.value;
}

const app = express();

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/search", async (req, res) => {
  if (req.header("X-App-Secret") !== APP_SHARED_SECRET) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const query = req.query.q;
  if (!query) {
    return res.status(400).json({ error: "missing q parameter" });
  }
  const maxResults = req.query.max_results || "10";

  try {
    const token = await getAccessToken();
    const url = new URL("https://platform.fatsecret.com/rest/foods/search/v1");
    url.searchParams.set("search_expression", query);
    url.searchParams.set("max_results", maxResults);
    url.searchParams.set("format", "json");

    const upstream = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    const body = await upstream.text();
    res.status(upstream.status).type("application/json").send(body);
  } catch (err) {
    res.status(502).json({ error: "fatsecret_proxy_failure", detail: String(err) });
  }
});

app.listen(PORT, () => console.log(`FatSecret proxy listening on port ${PORT}`));
