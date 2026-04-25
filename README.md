#  Maher Framework V9 — Precision Dragon

> **Bug Bounty Automation Framework — Quality over Quantity**

[![Version](https://img.shields.io/badge/Version-9.0-red)](https://github.com/Mohammed-Maher0/Maher-Framework-V9)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

---

## 🆚 V9 vs V8 — What Changed?

| Feature | V8 | V9 |
|---|---|---|
| Param categorization | Manual Regex | **gf patterns** (community-curated) |
| Nuclei templates | All tags | **-as auto-select** by tech fingerprint |
| Severity filter | info to critical | **medium, high, critical only** |
| Execution | Sequential | **Parallel** (faster ~3x) |
| Scope control | None | **Scope file + auto-filter** |
| SSRF/LFI testing | Nuclei only | **qsreplace pipelines** (confirmed!) |
| API discovery | katana only | **Kiterunner** + patterns |
| Scan modes | One mode | **fast / deep / stealth** |
| Reporting | .txt | **Markdown with Confidence Scoring** |
| URL discovery | uncover ❌ | **uncover** (Shodan+Censys+Fofa) |
| Deduplication | sort -u | **anew + uro** (smarter) |

---

## 📦 Installation

```bash
git clone https://github.com/Mohammed-Maher0/Maher-Framework-V9
cd Maher-Framework-V9
chmod +x *.sh
./install.sh
```

---

## 🚀 Usage

```bash
# Deep scan (default — ~60 min)
./pwn.sh -d target.com

# Fast scan — High/Critical only (~15 min)
./pwn.sh -d target.com -m fast

# Stealth — WAF-aware (~90 min)
./pwn.sh -d target.com -m stealth

# With scope file + custom header
./pwn.sh -d target.com -m deep -s scope.txt -H "X-Bug-Bounty: username"

# Subdomain mode (auto-detected)
./pwn.sh -d sub.target.com
```

**scope.txt format:**
```
target.com
api.target.com
*.target.com
```

---

## ⚙️ Optional Environment Variables

```bash
export GITHUB_TOKEN=ghp_xxx       # GitHub subdomain hunting
export TG_TOKEN=xxx               # Telegram bot token
export TG_CHAT=xxx                # Telegram chat ID
export SHODAN_API_KEY=xxx         # uncover Shodan integration
```

---

## 🏗️ Pipeline Architecture

```
pwn.sh
├── recon.sh    → Parallel subdomain enum + tech detection + OSINT
├── mine.sh     → gf patterns + qsreplace pipelines + Kiterunner
├── attack.sh   → nuclei -as + Dalfox + OAST + JWT + CRLF
└── report.sh   → Confidence scoring + Markdown + Telegram
```

---

## 📊 Confidence Scoring System

| Badge | Meaning | Action |
|---|---|---|
| 🔴 CONFIRMED | Exploitable proof (response match / OAST callback) | Report immediately |
| 🟡 LIKELY | High confidence nuclei finding | Manual verify → report |
| ⚪ POSSIBLE | Medium severity, needs investigation | Deep manual testing |

---

## 🗂️ Output Structure

```
targets/target.com_V9_deep_2025-XX-XX/
├── alive.txt
├── all_urls.txt
├── all_params.txt
├── all_valid_subs.txt
├── REPORT.md           ← Main report (Markdown)
├── recon/
├── mining/
│   ├── xss.txt         ← gf patterns output
│   ├── sqli.txt
│   ├── ssrf.txt
│   ├── lfi_confirmed.txt   ← ✅ confirmed!
│   ├── redirect_confirmed.txt  ← ✅ confirmed!
│   ├── api/
│   └── js/
├── vulns/
│   ├── nuclei_auto.txt     ← -as scan results
│   ├── xss_dalfox.json     ← confirmed XSS
│   ├── oast_callbacks.json ← blind vulns
│   └── ...
├── osint/
└── technologies/
```

---

## 🔧 New Tools in V9

| Tool | Purpose |
|---|---|
| `gf` | Smart param categorization via grep patterns |
| `qsreplace` | Mass parameter replacement for SSRF/LFI/Redirect |
| `kiterunner` | API endpoint bruteforcer for modern apps |
| `uncover` | Shodan + Censys + Fofa in one command |
| `anew` | Smart deduplication without losing order |
| `tok` | Target-specific wordlist builder from responses |
| `notify` | Real-time Telegram/Discord/Slack notifications |
| `crlfuzz` | CRLF injection scanner |

---

## ⚠️ Legal Notice

This framework is for **authorized security testing and bug bounty programs only**.
Always ensure you have explicit written permission before testing any target.

---

*Made by Mohammed Maher | V9 — Precision Dragon*
