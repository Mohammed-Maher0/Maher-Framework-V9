#!/bin/bash
# ============================================================
# MAHER V9 — PHASE 4: REPORT
# Confidence scoring + clean Markdown + notify
# ============================================================

TARGET=$1
WORK_DIR=$2

[ -z "$TARGET" ] || [ -z "$WORK_DIR" ] && {
    echo -e "\e[31m[!] Usage: ./report.sh <target> <work_dir>\e[0m"; exit 1
}

# ============================================================
# TELEGRAM CONFIG
# ============================================================
TG_TOKEN="${TG_TOKEN:-}"
TG_CHAT="${TG_CHAT:-}"

send_tg() {
    local MSG=$1
    [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT" ] && return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${MSG}" \
        > /dev/null 2>&1
}

send_tg_file() {
    local FILE=$1 CAPTION=$2
    [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT" ] || [ ! -f "$FILE" ] && return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
        -F "chat_id=${TG_CHAT}" \
        -F "document=@${FILE}" \
        -F "caption=${CAPTION}" \
        > /dev/null 2>&1
}

echo -e "\e[36m╔══════════════════════════════════════════╗\e[0m"
echo -e "\e[36m║     📋 REPORT PHASE V9 — FINAL INTEL    ║\e[0m"
echo -e "\e[36m╚══════════════════════════════════════════╝\e[0m"

cd "$WORK_DIR" || exit 1
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
REPORT="REPORT.md"

# ============================================================
# COLLECT STATS
# ============================================================
LIVE_HOSTS=$(wc -l < alive.txt 2>/dev/null || echo 0)
TOTAL_SUBS=$(wc -l < all_valid_subs.txt 2>/dev/null || echo 0)
TOTAL_URLS=$(wc -l < all_urls.txt 2>/dev/null || echo 0)
TOTAL_PARAMS=$(wc -l < all_params.txt 2>/dev/null || echo 0)

# Findings per category
XSS_CONFIRMED=$(grep -c '"type"' vulns/xss_dalfox.json 2>/dev/null || echo 0)
XSS_NUCLEI=$(wc -l < vulns/xss_nuclei.txt 2>/dev/null || echo 0)
SQLI_COUNT=$(wc -l < vulns/sqli_nuclei.txt 2>/dev/null || echo 0)
RCE_COUNT=$(wc -l < vulns/rce_findings.txt 2>/dev/null || echo 0)
SSTI_COUNT=$(wc -l < vulns/ssti_findings.txt 2>/dev/null || echo 0)
OAST_COUNT=$(grep -c '"protocol"' vulns/oast_callbacks.json 2>/dev/null || echo 0)
BLIND_SSRF=$(wc -l < vulns/blind_ssrf.txt 2>/dev/null || echo 0)
BLIND_RCE=$(wc -l < vulns/blind_rce.txt 2>/dev/null || echo 0)
LFI_CONFIRMED=$(wc -l < mining/lfi_confirmed.txt 2>/dev/null || echo 0)
REDIRECT_CONFIRMED=$(wc -l < mining/redirect_confirmed.txt 2>/dev/null || echo 0)
GQL_COUNT=$(wc -l < vulns/graphql_findings.txt 2>/dev/null || echo 0)
JWT_COUNT=$(wc -l < vulns/jwt_tokens.txt 2>/dev/null || echo 0)
CRLF_COUNT=$(wc -l < vulns/crlf_findings.txt 2>/dev/null || echo 0)
HOST_HDR=$(wc -l < vulns/host_header.txt 2>/dev/null || echo 0)
CORS_COUNT=$(wc -l < vulns/cors_findings.txt 2>/dev/null || echo 0)
BYPASS_COUNT=$(wc -l < vulns/bypass_403.txt 2>/dev/null || echo 0)
TAKEOVER_COUNT=$(wc -l < vulns/takeovers.txt 2>/dev/null || echo 0)
JS_SECRETS=$(wc -l < vulns/js_secrets.txt 2>/dev/null || echo 0)
SECRETS_GITHUB=$(grep -c '"SourceMetadata"' osint/trufflehog_github.json 2>/dev/null || echo 0)

TOTAL_CONFIRMED=$((XSS_CONFIRMED + LFI_CONFIRMED + REDIRECT_CONFIRMED + OAST_COUNT))
TOTAL_FINDINGS=$((XSS_CONFIRMED + XSS_NUCLEI + SQLI_COUNT + RCE_COUNT + SSTI_COUNT + \
    OAST_COUNT + BLIND_SSRF + BLIND_RCE + LFI_CONFIRMED + REDIRECT_CONFIRMED + \
    GQL_COUNT + JWT_COUNT + CRLF_COUNT + CORS_COUNT + BYPASS_COUNT + TAKEOVER_COUNT + JS_SECRETS))

# ============================================================
# CONFIDENCE SCORING FUNCTION
# ============================================================
confidence_badge() {
    local COUNT=$1 TYPE=$2
    [ "$COUNT" -eq 0 ] && return
    case "$TYPE" in
        confirmed) echo "🔴 **CONFIRMED** ($COUNT)" ;;
        likely)    echo "🟡 **LIKELY** ($COUNT — verify)" ;;
        possible)  echo "⚪ **POSSIBLE** ($COUNT — manual check)" ;;
    esac
}

# ============================================================
# GENERATE MARKDOWN REPORT
# ============================================================
cat > "$REPORT" <<MDEOF
# 🐉 MAHER FRAMEWORK V9 — HUNT REPORT

| Field | Value |
|---|---|
| **Target** | \`$TARGET\` |
| **Mode** | $MODE |
| **Date** | $TIMESTAMP |
| **Output** | \`$WORK_DIR\` |

---

## 📊 Recon Summary

| Metric | Count |
|---|---|
| Total Subdomains | $TOTAL_SUBS |
| Live Hosts | $LIVE_HOSTS |
| Total URLs | $TOTAL_URLS |
| Parameterized URLs | $TOTAL_PARAMS |

---

## 🚨 Findings — Confidence Scored

### 🔴 CONFIRMED (Exploit-Ready)

MDEOF

# Confirmed findings section
confirmed_section() {
    local COUNT=$1 NAME=$2 FILE=$3 NOTE=$4
    [ "$COUNT" -gt 0 ] && cat >> "$REPORT" <<EOF
#### $NAME — $COUNT findings
- **File:** \`$FILE\`
- **Note:** $NOTE

EOF
}

confirmed_section "$XSS_CONFIRMED" "XSS (Dalfox)" "vulns/xss_dalfox.json" "Browser-confirmed, exploitable"
confirmed_section "$LFI_CONFIRMED" "LFI" "mining/lfi_confirmed.txt" "root:x: pattern matched in response"
confirmed_section "$REDIRECT_CONFIRMED" "Open Redirect" "mining/redirect_confirmed.txt" "evil.com found in Location header"
confirmed_section "$OAST_COUNT" "Blind Vulnerabilities (OAST)" "vulns/oast_callbacks.json" "DNS/HTTP callback received — Blind SSRF/RCE/XSS"

[ "$TOTAL_CONFIRMED" -eq 0 ] && echo "_No confirmed findings in this scan._" >> "$REPORT"

cat >> "$REPORT" <<MDEOF

---

### 🟡 LIKELY (High Confidence — Verify)

| Vulnerability | Count | File |
|---|---|---|
| RCE | $RCE_COUNT | \`vulns/rce_findings.txt\` |
| SSTI | $SSTI_COUNT | \`vulns/ssti_findings.txt\` |
| SQLi (Nuclei) | $SQLI_COUNT | \`vulns/sqli_nuclei.txt\` |
| Blind SSRF | $BLIND_SSRF | \`vulns/blind_ssrf.txt\` |
| Blind RCE | $BLIND_RCE | \`vulns/blind_rce.txt\` |
| GraphQL Introspection | $GQL_COUNT | \`vulns/graphql_findings.txt\` |
| Subdomain Takeover | $TAKEOVER_COUNT | \`vulns/takeovers.txt\` |
| JWT Tokens Found | $JWT_COUNT | \`vulns/jwt_tokens.txt\` |

---

### ⚪ POSSIBLE (Medium — Manual Needed)

| Vulnerability | Count | File |
|---|---|---|
| CORS Misconfig | $CORS_COUNT | \`vulns/cors_findings.txt\` |
| CRLF Injection | $CRLF_COUNT | \`vulns/crlf_findings.txt\` |
| Host Header | $HOST_HDR | \`vulns/host_header.txt\` |
| 403 Bypass | $BYPASS_COUNT | \`vulns/bypass_403.txt\` |
| JS Secrets | $JS_SECRETS | \`vulns/js_secrets.txt\` |
| GitHub Secrets | $SECRETS_GITHUB | \`osint/trufflehog_github.json\` |

---

## 📁 Priority Files — Check These First

MDEOF

# إضافة الملفات الموجودة بس
for pfile in \
    "vulns/rce_findings.txt" \
    "vulns/oast_callbacks.json" \
    "vulns/xss_dalfox.json" \
    "vulns/blind_ssrf.txt" \
    "vulns/blind_rce.txt" \
    "vulns/sqli_nuclei.txt" \
    "vulns/graphql_findings.txt" \
    "vulns/jwt_tokens.txt" \
    "vulns/bypass_403.txt" \
    "vulns/takeovers.txt" \
    "mining/lfi_confirmed.txt" \
    "mining/redirect_confirmed.txt" \
    "vulns/js_secrets.txt" \
    "osint/trufflehog_github.json"; do
    [ -f "$pfile" ] && [ -s "$pfile" ] && {
        COUNT=$(wc -l < "$pfile")
        echo "- \`$pfile\` ($COUNT lines)" >> "$REPORT"
    }
done

cat >> "$REPORT" <<MDEOF

---

## 🖐️ Manual Testing Required

| Task | File/Command |
|---|---|
| IDOR Testing | \`mining/idor.txt\` |
| API Endpoints | \`mining/api/api_endpoints.txt\` |
| GraphQL Deep | \`mining/api/graphql.txt\` — use InQL |
| JWT Analysis | \`vulns/jwt_tokens.txt\` — test alg:none, key confusion |
| Google Dorks | \`osint/google_dorks.txt\` |
| SQLMap (manual) | \`sqlmap -m mining/sqli.txt --batch --level=3 --risk=3\` |
| Param Discovery | \`mining/params/arjun/\` — verify hidden params |

---

## 📈 Total Summary

| | Count |
|---|---|
| 🔴 Confirmed | **$TOTAL_CONFIRMED** |
| 🟡 Likely | **$((RCE_COUNT + SQLI_COUNT + BLIND_SSRF + TAKEOVER_COUNT))** |
| ⚪ Possible | **$((CORS_COUNT + CRLF_COUNT + BYPASS_COUNT + JS_SECRETS))** |
| **Total Findings** | **$TOTAL_FINDINGS** |

---
*Generated by Maher Framework V9 — $TIMESTAMP*
MDEOF

echo "    > Report: $WORK_DIR/$REPORT"

# ============================================================
# TELEGRAM NOTIFICATIONS
# ============================================================
echo "[+] Sending Telegram Notifications..."

if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then

    EMOJI="✅"
    [ "$TOTAL_CONFIRMED" -gt 0 ] && EMOJI="🚨"
    [ "$RCE_COUNT" -gt 0 ] || [ "$OAST_COUNT" -gt 0 ] && EMOJI="💀"

    TG_MSG="${EMOJI} <b>MAHER V9 — HUNT COMPLETE</b>

🎯 Target: <code>$TARGET</code>
⚡ Mode: $MODE
🕒 $TIMESTAMP

📊 Stats:
• Live Hosts: $LIVE_HOSTS
• Total URLs: $TOTAL_URLS
• Total Findings: $TOTAL_FINDINGS

🔴 CONFIRMED:
• XSS: $XSS_CONFIRMED
• LFI: $LFI_CONFIRMED
• Open Redirect: $REDIRECT_CONFIRMED
• OAST Callbacks: $OAST_COUNT

🟡 LIKELY:
• RCE: $RCE_COUNT
• SQLi: $SQLI_COUNT
• Blind SSRF: $BLIND_SSRF
• GraphQL: $GQL_COUNT
• Takeovers: $TAKEOVER_COUNT

📁 Results: $WORK_DIR"

    send_tg "$TG_MSG"
    send_tg_file "$REPORT" "📋 Full Report — $TARGET"

    # Critical alerts
    [ "$RCE_COUNT" -gt 0 ] && \
        send_tg "💀💀 <b>RCE ON $TARGET</b> — $RCE_COUNT findings!%0ACheck: vulns/rce_findings.txt"

    [ "$OAST_COUNT" -gt 0 ] && \
        send_tg "🔥 <b>BLIND VULN CONFIRMED — $TARGET</b>%0AOAST Callbacks: $OAST_COUNT%0ACheck: vulns/oast_callbacks.json"

    [ "$SECRETS_GITHUB" -gt 0 ] && \
        send_tg "🔑 <b>GITHUB SECRETS — $TARGET</b>%0AVerified secrets: $SECRETS_GITHUB%0ACheck: osint/trufflehog_github.json"

    [ "$TAKEOVER_COUNT" -gt 0 ] && \
        send_tg "🏴 <b>SUBDOMAIN TAKEOVER — $TARGET</b>%0A$TAKEOVER_COUNT potential takeovers!%0ACheck: vulns/takeovers.txt"

    echo "    > Telegram notifications sent ✅"
else
    echo "    > [~] Telegram not configured"
    echo "    >     Set: export TG_TOKEN=xxx && export TG_CHAT=xxx"
fi

# ============================================================
# FINAL CONSOLE SUMMARY
# ============================================================
echo ""
echo -e "\e[32m╔════════════════════════════════════════════╗\e[0m"
echo -e "\e[32m║       HUNT STATS — V9 PRECISION            ║\e[0m"
echo -e "\e[32m╠════════════════════════════════════════════╣\e[0m"
printf "\e[32m║  %-24s : %-13s ║\e[0m\n" "Live Hosts"      "$LIVE_HOSTS"
printf "\e[32m║  %-24s : %-13s ║\e[0m\n" "Total Findings"  "$TOTAL_FINDINGS"
echo -e "\e[32m╠════════════════════════════════════════════╣\e[0m"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "🔴 CONFIRMED"    "$TOTAL_CONFIRMED"
printf "\e[33m║  %-24s : %-13s ║\e[0m\n" "🟡 RCE"          "$RCE_COUNT"
printf "\e[33m║  %-24s : %-13s ║\e[0m\n" "🟡 OAST Blind"   "$OAST_COUNT"
printf "\e[33m║  %-24s : %-13s ║\e[0m\n" "🟡 SQLi"         "$SQLI_COUNT"
printf "\e[33m║  %-24s : %-13s ║\e[0m\n" "🟡 Takeovers"    "$TAKEOVER_COUNT"
printf "\e[36m║  %-24s : %-13s ║\e[0m\n" "⚪ CORS"          "$CORS_COUNT"
printf "\e[36m║  %-24s : %-13s ║\e[0m\n" "⚪ 403 Bypassed"  "$BYPASS_COUNT"
echo -e "\e[32m╚════════════════════════════════════════════╝\e[0m"

echo -e "\e[32m[✔] Report Phase Completed!\e[0m"
