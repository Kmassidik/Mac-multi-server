# Cloudflare setup (for total beginners)

You need **4 values** in `.env`. Two are already filled for you (pulled from your Mac's
tunnel token). You only need to create **1 API token** — and from that, the platform can
fetch the Zone ID for you automatically.

| Key | Status | Where it comes from |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | ✅ filled | pulled from your tunnel token |
| `CLOUDFLARE_TUNNEL_ID` | ✅ filled | your existing `kurniatech.my.id` tunnel |
| `CLOUDFLARE_API_TOKEN` | ⬜ **you create it (below)** | dashboard |
| `CLOUDFLARE_ZONE_ID` | ⚙️ auto-fetched from the token | (or copy it manually — Step 3) |

Start here: **https://dash.cloudflare.com** → log in.

---

## Create the API token (the only thing you need to do)

1. Top-right **profile icon → My Profile → API Tokens → Create Token**.
2. At the top, under **"Custom token"**, click **Create Custom Token**
   *(don't use the templates below it — none fit).*
3. **Token name:** `mac-multi-server`
4. **Permissions** — each row has **3 dropdowns**: *(group)* · *(permission)* · *(Edit/Read)*.
   Set the first row, then click **+ Add more** for the second:

   | group | permission | access |
   |---|---|---|
   | **Zone** | **DNS** | **Edit** |
   | **Account** | **Cloudflare Tunnel** | **Edit** |

5. **Account Resources:** `Include` → your account (default "All accounts" is fine).
6. **Zone Resources:** `Include` → **Specific zone** → **kurniatech.my.id**.
7. Leave **Client IP Filtering** and **TTL** blank.
8. **Continue to summary** → **Create Token**.
9. It shows the token **once** (a long string). Click **Copy**.
   ⚠️ You can't see it again — if lost, just delete it and make a new one. Don't delete your *other* tokens (they belong to other tunnels/domains).
10. Paste it into `.env`:
    ```
    CLOUDFLARE_API_TOKEN=<paste here>
    ```

That's the whole job. The Account ID and Tunnel ID are already set, and the Zone ID is
fetched automatically the first time the platform runs.

---

## Step 3 — Zone ID (only if you want to set it by hand)
Normally auto-fetched from the token. To copy it manually:
click **kurniatech.my.id** on the dashboard home → **Overview** → right sidebar **API** box →
**Zone ID** → Copy → into `.env` as `CLOUDFLARE_ZONE_ID=`.
⚠️ Make sure it's the **kurniatech.my.id** page — not another domain.

---

## Verify the token (optional)
```bash
curl -s -H "Authorization: Bearer <YOUR_TOKEN>" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | grep -o '"success":[a-z]*'
```
`"success":true` → you're set.

---

Keep the token secret — `.env` is gitignored, so it never leaves your machine. If it leaks,
delete it in the dashboard (API Tokens → … → Delete) and create a new one.
