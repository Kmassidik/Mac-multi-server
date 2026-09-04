# Setup

One-time host preparation + Cloudflare config. Everything you fill lands in `.env`.

## 0. Prerequisites
- Apple Silicon Mac (Mac Studio / Mini / etc.), macOS current.
- [Homebrew](https://brew.sh).
- A domain you control, added as a **zone in your Cloudflare account**.

## 1. Host tools
`scripts/setup-host.sh` does this for you, but for reference:
```bash
brew install cirruslabs/cli/tart                 # the hypervisor
brew install hudochenkov/sshpass/sshpass         # first-login key injection
brew install cloudflared                          # ingress tunnel
```

## 2. Firewall (pf) — allow VM DHCP
If your Mac runs a default-deny pf ruleset, VMs can't get an IP until you allow the DHCP
client→server direction. See [networking.md](networking.md). Scripted:
```bash
sudo ./scripts/pf-allow-dhcp.sh
```
Also shorten the DHCP lease for many-VM use:
```bash
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist \
  bootpd -dict DHCPLeaseTimeSecs -int 600
```

## 3. Cloudflare
### 3a. Named tunnel (once)
```bash
cloudflared tunnel login
cloudflared tunnel create mac-multi-server          # note the Tunnel ID
```
Run it as a service so it survives reboot (`cloudflared service install` with the tunnel token).

### 3b. API token (for auto-creating vpsN. routes)
Create a token at dash.cloudflare.com → My Profile → API Tokens with **least privilege**:
- **Zone → DNS → Edit** (your zone only)
- **Account → Cloudflare Tunnel → Edit**

### 3c. IDs you need
- `CLOUDFLARE_ZONE_ID` — Overview page of your domain (right sidebar).
- `CLOUDFLARE_ACCOUNT_ID` — same sidebar / URL.
- `CLOUDFLARE_TUNNEL_ID` — from `cloudflared tunnel create`.

## 4. Fill `.env`
```bash
cp .env.example .env
# edit: DOMAIN, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_ZONE_ID, CLOUDFLARE_TUNNEL_ID
```
`.env` is gitignored — your secrets never leave the machine.

## 5. Go
```bash
./scripts/setup-host.sh                       # verifies tools, pf, tunnel
./scripts/deploy-vps.sh --bundle openclaw     # first VPS
```

## Security notes
- Only **:22** is exposed to the internet (pf drops the rest). VPS are reached via Cloudflare / ProxyJump.
- Scope the Cloudflare token to the single zone; rotate it if it ever leaks.
- Keep `.env` at `chmod 600`.
