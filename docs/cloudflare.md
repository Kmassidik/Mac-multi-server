# Cloudflare setup (for total beginners)

You need **4 values** in `.env`. Two are already filled for you (pulled from your Mac's
tunnel). You only need to get **2 more** from the Cloudflare dashboard. ~5 minutes.

| Key | Status | Where it comes from |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | ✅ filled (`05edb382…`) | pulled from your tunnel token |
| `CLOUDFLARE_TUNNEL_ID` | ✅ filled (`0453e04d…`) | your existing `kurniatech.my.id` tunnel |
| `CLOUDFLARE_ZONE_ID` | ⬜ you get it (Step 1) | dashboard |
| `CLOUDFLARE_API_TOKEN` | ⬜ you create it (Step 2) | dashboard |

Start here: **https://dash.cloudflare.com** (log in).

---

## Step 1 — Zone ID  (30 seconds)

1. On the dashboard home, click your domain **`kurniatech.my.id`**.
2. You're on its **Overview** page. Look at the **right-hand column**, scroll down to the
   **"API"** box.
3. Under **Zone ID** there's a long code like `9f8e7d6c…`. Click **Copy**.
4. Paste it into `.env`:
   ```
   CLOUDFLARE_ZONE_ID=<paste here>
   ```

---

## Step 2 — API Token  (2 minutes)

This lets the platform create `vps1.kurniatech.my.id`, `panel.…`, etc. automatically.
We give it **only** the two permissions it needs — nothing more.

1. Top-right, click your **profile icon → My Profile**.
2. Left menu → **API Tokens** → blue **Create Token** button.
3. Scroll to **"Create Custom Token"** → **Get started**.
4. Fill it in:
   - **Token name:** `mac-multi-server`
   - **Permissions** — add these two rows (click "+ Add more" for the second):
     | | | |
     |---|---|---|
     | **Zone** | **DNS** | **Edit** |
     | **Account** | **Cloudflare Tunnel** | **Edit** |
   - **Zone Resources:** `Include` → `Specific zone` → **kurniatech.my.id**
   - (leave the rest as default)
5. **Continue to summary** → **Create Token**.
6. It shows the token **once** — a long string like `abc123…`. Click **Copy**.
   ⚠️ You can't see it again. If you lose it, just make a new one.
7. Paste it into `.env`:
   ```
   CLOUDFLARE_API_TOKEN=<paste here>
   ```

---

## Step 3 — verify (optional but nice)

Run this on the Mac (or laptop) — swap in your token. If it says `"success": true`, you're set:
```bash
curl -s -H "Authorization: Bearer <YOUR_TOKEN>" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | grep -o '"success":[a-z]*'
```

---

## That's it
Your `.env` Cloudflare block should now look like:
```
CLOUDFLARE_API_TOKEN=abc123…          # Step 2
CLOUDFLARE_ACCOUNT_ID=05edb382d845dd752e4523dceab3971b   # ✅ already done
CLOUDFLARE_ZONE_ID=9f8e7d6c…          # Step 1
CLOUDFLARE_TUNNEL_ID=0453e04d-1bd1-484b-810d-1e96186aea0d # ✅ already done
```
Keep the token secret — `.env` is gitignored so it never leaves your machine. If it ever
leaks, delete it in the dashboard (API Tokens → … → Delete) and make a new one.
