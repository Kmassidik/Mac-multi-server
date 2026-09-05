# Setup

One-time host preparation + Cloudflare config. Everything you fill lands in `.env`.

## 0. Prerequisites
- Apple Silicon Mac (Mac Studio / Mini / etc.), macOS current.
- [Homebrew](https://brew.sh).
- A domain you control, added as a **zone in your Cloudflare account**.
- **Clone location matters:** put the repo in your **home dir** (`~/mac-multi-server`), *not*
  `~/Desktop`, `~/Documents`, or `~/Downloads`. Those are TCC-protected, and launchd services
  can't load binaries from them — the panel would hang in dyld and never start. `install.sh`
  refuses a TCC path with instructions to move it.

## 1. Host tools
`./install.sh` does this for you, but for reference:
```bash
brew install cirruslabs/cli/tart                 # the hypervisor
brew install hudochenkov/sshpass/sshpass         # first-login key injection
brew install cloudflared                          # ingress tunnel
```

## 2. Firewall (pf) — allow VM DHCP
If your Mac runs a default-deny pf ruleset, VMs can't get an IP until you allow the DHCP
client→server direction. See [networking.md](networking.md). Scripted:
```bash
sudo ./mms pf-fix
```
Also shorten the DHCP lease for many-VM use:
```bash
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist \
  bootpd -dict DHCPLeaseTimeSecs -int 600
```

## 3. Cloudflare
**👉 Beginner walkthrough: [docs/cloudflare.md](cloudflare.md)** — click-by-click for the 4 `.env` values.

Short version:
- Routes are created via the **Cloudflare API** on your existing token-based tunnel (no local config.yml).
- You need an **API token** (least privilege: **Zone → DNS → Edit** + **Account → Cloudflare Tunnel → Edit**), plus your **Zone ID**, **Account ID**, and **Tunnel ID**.
- `ACCOUNT_ID` and `TUNNEL_ID` can be read from the running tunnel's token; the guide shows how to get the token + Zone ID from the dashboard.

## 4. Fill `.env`
```bash
cp .env.example .env
# edit: DOMAIN, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_ZONE_ID, CLOUDFLARE_TUNNEL_ID
```
`.env` is gitignored — your secrets never leave the machine.

## 5. Go
```bash
./install.sh                       # verifies tools, pf, tunnel
./mms deploy --bundle openclaw     # first VPS
```

## Security notes
- The platform opens **no inbound port** — cloudflared reaches Cloudflare outbound, and VPS are
  reached by domain SSH (`ssh admin@vpsN.$DOMAIN`) through the tunnel, no jump host. pf stays
  default-deny inbound (the `pf-fix` rule only affects the internal VM bridge). See
  [networking.md](networking.md).
- Scope the Cloudflare token to the single zone; rotate it if it ever leaks.
- Keep `.env` at `chmod 600`.
