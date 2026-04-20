# VPS Security Hardening

A systematic approach to hardening an Ubuntu 24.04 VPS for production use — covering firewall configuration, service isolation, intrusion prevention, and zero-trust principles.

## 🎯 Project Goals

- **Defense in depth** — Layer multiple security controls so no single failure exposes the system
- **Service isolation** — Each service accessible only from where it's needed
- **Reproducible** — Every step documented and scriptable; rebuild from scratch in minutes
- **Auditable** — Weekly automated security audits with email reporting

## 🏗️ Architecture Overview

```
                        ┌─────────────────────────────────────────────┐
                        │              Internet                       │
                        └─────────────┬───────────────────────────────┘
                                      │
                              ┌───────▼───────┐
                              │   UFW Firewall │
                              │  (default deny) │
                              └───┬───┬───┬───┘
                                  │   │   │
                    ┌─────────────┘   │   └──────────────┐
                    │                 │                    │
              ┌─────▼─────┐   ┌─────▼─────┐      ┌──────▼──────┐
              │  SSH :2222 │   │ Caddy     │      │  Tailscale  │
              │ (key-only) │   │ :80/:443  │      │  (mesh VPN) │
              │            │   │ :8443    │      │             │
              └────────────┘   └─────┬─────┘      └──────┬──────┘
                                     │                    │
                              ┌──────▼──────┐      ┌────▼────┐
                              │  Portfolio  │      │  All    │
                              │  API        │      │  internal│
                              │  (localhost)│      │  services│
                              └─────────────┘      └─────────┘
```

### Network Segmentation

| Service | Port | Binding | Access |
|---------|------|---------|--------|
| SSH | 2222 | 0.0.0.0 | Public (key-only + fail2ban) |
| Caddy (HTTP) | 80 | 0.0.0.0 | Public → redirect to HTTPS |
| Caddy (HTTPS) | 443 | 0.0.0.0 | Public → trevorsteinke.com |
| Caddy (API) | 8443 | 0.0.0.0 | Public → Caddy → localhost:3456 |
| Portfolio API | 3456 | **127.0.0.1** | Localhost only (Caddy proxy) |
| qBittorrent WebUI | 8080 | **127.0.0.1** | Localhost only (Tailscale) |
| qBittorrent BT | 2984 | Tailscale + eth0 | BitTorrent protocol |
| Ollama | 11434 | **127.0.0.1** | Localhost only |
| OpenClaw Gateway | 18789 | **127.0.0.1** | Localhost only (Tailscale Serve) |

## 🔧 Hardening Steps

### 1. UFW Firewall — Default Deny

Install and configure UFW with a whitelist-only approach:

```bash
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow only what's needed
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw allow 8443/tcp comment 'Portfolio API'
sudo ufw allow in on tailscale0 comment 'Tailscale traffic'

echo "y" | sudo ufw enable
```

**Principle:** Every port that doesn't need to be public, isn't. Internal services bind to `127.0.0.1` and are accessed via Tailscale or Caddy reverse proxy.

### 2. Service Isolation — Localhost Binding

Services that don't need direct internet access are bound to localhost only:

**qBittorrent WebUI** — Changed from `0.0.0.0:8080` to `127.0.0.1:8080`:
```ini
# ~/.config/qBittorrent/qBittorrent.conf
WebUI\Address=127.0.0.1
```

> ⚠️ **Gotcha:** qBittorrent overwrites its config file on shutdown. Always `systemctl stop` the service before editing the config, then `systemctl start` it. If you edit while running, your changes will be lost.

**Portfolio API** — Changed from `0.0.0.0:3456` to `127.0.0.1:3456`:
```javascript
// Before:
app.listen(PORT, () => { ... })

// After:
app.listen(PORT, '127.0.0.1', () => { ... })
```

Caddy reverse-proxies the API over TLS:
```
api.trevorsteinke.com:8443 {
    encode gzip
    route /api/* {
        reverse_proxy localhost:3456
    }
}
```

### 3. SSH Hardening

Already configured before this project (verified via audit):

- **Key-only authentication** — `PasswordAuthentication no`
- **Root login disabled** — `PermitRootLogin no`
- **Non-standard port** — `Port 2222` (reduces automated scan noise)
- **No failed logins in 7 days** — Indicates effective key-only policy

### 4. Intrusion Prevention with fail2ban

```bash
sudo apt-get install -y fail2ban
```

Configuration (`/etc/fail2ban/jail.local`):
```ini
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 2222
backend = systemd
```

This bans any IP that fails 5 SSH attempts within 10 minutes for 1 hour. Since SSH is key-only, legitimate failures are rare — any pattern of failures likely indicates a brute-force attempt.

### 5. Automated Security Audits

A weekly cron job runs a comprehensive security audit and emails findings:

- Open ports and binding addresses
- Failed login attempts
- Firewall status
- Pending package updates
- Running processes and suspicious activity
- Tailscale connectivity
- Service health checks

Results are emailed to the admin for review, creating a continuous security posture monitoring loop.

### 6. System Updates

```bash
# One-time full upgrade
sudo apt-get update && sudo apt-get upgrade -y

# Ongoing: unattended-upgrades is already enabled for security updates
```

## 📋 Before & After

| Control | Before | After |
|---------|--------|-------|
| Firewall | ❌ None installed | ✅ UFW (default deny) |
| qBittorrent WebUI | ❌ Exposed on 0.0.0.0:8080 | ✅ Localhost only |
| Portfolio API | ❌ Exposed on 0.0.0.0:3456 | ✅ Localhost only (Caddy proxy) |
| Intrusion Prevention | ❌ No fail2ban | ✅ fail2ban (SSH jail) |
| SSH Hardening | ✅ Already hardened | ✅ Maintained |
| Security Audits | ❌ None | ✅ Weekly automated |
| System Updates | ⚠️ 22 packages pending | ✅ Up to date |

## 🚀 Quick Start

To apply this hardening to a fresh Ubuntu 24.04 VPS:

```bash
# Clone this repo
git clone https://github.com/tsteinke11306/vps-security-hardening.git
cd vps-security-hardening

# Run the full hardening script (review it first!)
sudo bash scripts/harden.sh
```

> ⚠️ **Always review scripts before running them as root.** This repo documents MY setup — adapt it to yours.

## 🔮 Roadmap

Planned improvements:

- [ ] **Ansible playbook** — Reproducible infrastructure as code
- [ ] **Wazuh SIEM** — Centralized log collection, analysis, and alerting
- [ ] **Suricata IDS** — Network intrusion detection feeding into Wazuh
- [ ] **Automated backup system** — rsync + rotation + integrity checks
- [ ] **Docker containerization** — Isolate services in hardened containers
- [ ] **Tailscale ACL documentation** — Formalize zero-trust network policies
- [ ] **Certificate monitoring** — Auto-renewal + expiry alerting

## 📚 References

- [CIS Ubuntu 24.04 Benchmark](https://www.cisecurity.org/cis-benchmarks)
- [NIST SP 800-123: Guide to General Server Security](https://csrc.nist.gov/publications/detail/sp/800-123/final)
- [Tailscale Zero Trust Architecture](https://tailscale.com/kb/1018/security-whitepaper)
- [fail2ban Documentation](https://fail2ban.readthedocs.io/)

## 📜 License

MIT — Use this as a reference for your own hardening. No warranty implied.

---

*Documenting security work is as important as doing it. A hardened system that nobody can verify is hardened is no better than an unhardened one.*