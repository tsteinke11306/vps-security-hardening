# VPS Security Hardening — Change Log

All notable changes to this VPS hardening configuration.

## [1.1.1] - 2026-04-20

### Changed
- Censored all IP addresses (Tailscale IPs → `100.x.x.x`, tailnet domain → `<tailnet>.ts.net`, admin email → `<admin-email>`)
- Updated Tailscale device inventory (removed offline `ts0689dt01`, added `ts0689dt1` as secondary workstation)
- Updated network architecture diagram to include 4 devices

## [1.1.0] - 2026-04-20

### Added
- Zero Trust / Tailscale section in README
  - Network architecture diagram showing mesh VPN overlay
  - Tailnet device inventory with IPs and roles
  - Tailscale Serve configuration documentation
  - Service access matrix (public vs Tailscale vs localhost)
  - Security properties analysis (encryption, key rotation, P2P)
  - Future improvements roadmap (ACLs, Tailscale SSH, device auth, tailnet lock)
- Updated main architecture diagram to show Tailscale mesh and private services
- Updated before/after table with zero trust row

## [1.0.0] - 2026-04-20

### Added
- UFW firewall with default-deny incoming policy
  - Allow: SSH (2222), HTTP (80), HTTPS (443), API (8443), Tailscale interface
- fail2ban intrusion prevention
  - SSH jail on port 2222: 5 retries / 10 min window → 1 hour ban
- Automated weekly security audit (cron, Monday 7:00 AM EST)
- This repository with documentation and scripts

### Changed
- **qBittorrent WebUI** binding: `0.0.0.0:8080` → `127.0.0.1:8080` (localhost only)
- **Portfolio Contact API** binding: `0.0.0.0:3456` → `127.0.0.1:3456` (localhost only, Caddy proxy)
- System timezone: `Europe/Berlin` → `America/New_York` (matches admin's timezone)

### Pre-existing (verified)
- SSH key-only authentication (`PasswordAuthentication no`)
- SSH root login disabled (`PermitRootLogin no`)
- SSH on non-standard port (2222)
- Unattended-upgrades enabled for security updates
- Tailscale mesh VPN active

### Lessons Learned
- qBittorrent overwrites `qBittorrent.conf` on shutdown — always stop the service before editing the config file
- Services with `app.listen(PORT)` (no host arg) default to `0.0.0.0` — always specify `'127.0.0.1'` explicitly
- Cron jobs without explicit timezone default to system timezone — always set `tz` in schedule