#!/bin/bash
# ============================================================
# MAHER V9 — PHASE 1: RECON
# Parallel subdomain enum + smart scope filtering
# ============================================================
export PATH=$PATH:$HOME/go/bin:/usr/local/go/bin

# Catch Ctrl+C to skip current command instead of exiting
trap 'echo -e "\n\e[33m[!] Step skipped by user (Ctrl+C). Continuing to next...\e[0m"' SIGINT

TARGET=$1
WORK_DIR=$2

[ -z "$TARGET" ] || [ -z "$WORK_DIR" ] && {
    echo -e "\e[31m[!] Usage: ./recon.sh <domain> <work_dir>\e[0m"; exit 1
}

HEADER_OPTS=()
[ -n "$CUSTOM_BBP_HEADER" ] && HEADER_OPTS=("-H" "$CUSTOM_BBP_HEADER")

echo -e "\e[31m╔══════════════════════════════════════════╗\e[0m"
echo -e "\e[31m║     🔍 RECON PHASE V9 — DRAGON EYE      ║\e[0m"
echo -e "\e[31m╚══════════════════════════════════════════╝\e[0m"

mkdir -p "$WORK_DIR"/{recon,osint,technologies}
cd "$WORK_DIR" || exit 1

# ============================================================
# PHASE 1A: SUBDOMAIN MODE DETECTION
# ============================================================
if [ "$IS_SUBDOMAIN" = "true" ]; then
    echo -e "\e[33m[~] Subdomain mode → $TARGET (root: $ROOT_DOMAIN)\e[0m"
    echo "$TARGET" > recon/all_subs.txt

    # Siblings من نفس الـ root
    echo "[+] Fetching sibling subdomains..."
    subfinder -d "$ROOT_DOMAIN" -all -silent 2>/dev/null \
        | grep "\.$ROOT_DOMAIN$" >> recon/all_subs.txt &

    wait
    sort -u recon/all_subs.txt -o recon/all_subs.txt
    echo "    > Subs (incl. siblings): $(wc -l < recon/all_subs.txt)"

# ============================================================
# PHASE 1B: FULL DOMAIN — PARALLEL ENUM
# ============================================================
else
    echo "[+] 1. Passive Subdomain Enumeration (PARALLEL)..."
    > recon/all_subs.txt

    # تشغيل كل المصادر بالتوازي
    (subfinder -d "$TARGET" -all -silent 2>/dev/null \
        >> recon/subs_subfinder.txt) &

    (cero "$TARGET" 2>/dev/null \
        | sed 's/^\*\.//' | grep "\.$TARGET$" \
        >> recon/subs_cero.txt) &

    (curl -s --max-time 20 \
        "https://crt.sh/?q=%25.$TARGET&output=json" 2>/dev/null \
        | grep -o '"name_value":"[^"]*"' \
        | sed 's/"name_value":"//;s/"//' \
        | sed 's/^\*\.//' \
        | grep "\.$TARGET$" \
        >> recon/subs_crt.txt) &

    # uncover — Shodan + Censys + Fofa (لو الـ API keys موجودة)
    if command -v uncover &>/dev/null; then
        (uncover -q "ssl:\"$TARGET\"" \
            -e shodan,censys,fofa \
            -silent 2>/dev/null \
            | grep "\.$TARGET$" \
            >> recon/subs_uncover.txt) &
    fi

    # GitHub subdomains
    if command -v github-subdomains &>/dev/null && [ -n "$GITHUB_TOKEN" ]; then
        (github-subdomains -d "$TARGET" -t "$GITHUB_TOKEN" -silent 2>/dev/null \
            >> recon/subs_github.txt) &
    fi

    wait

    # دمج كل المصادر
    cat recon/subs_*.txt 2>/dev/null \
        | sort -u > recon/all_subs.txt

    echo "    > Raw subdomains: $(wc -l < recon/all_subs.txt)"
fi

# ============================================================
# APPLY SCOPE FILTER
# ============================================================
echo "[+] Applying Scope Engine to subdomains..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/scope.sh" ]; then
    source "$SCRIPT_DIR/scope.sh"
    scope_load "$ROOT_DOMAIN"
    scope_filter_file all_valid_subs.txt all_valid_subs_filtered.txt
    mv all_valid_subs_filtered.txt all_valid_subs.txt
fi

# ============================================================
# PHASE 2: RESOLVE — تصفية الـ dead subs
# ============================================================
echo "[+] 2. Resolving live subdomains (puredns)..."
wget -q https://raw.githubusercontent.com/trickest/resolvers/main/resolvers-trusted.txt \
    -O recon/resolvers.txt 2>/dev/null || \
    wget -q https://raw.githubusercontent.com/janmasarik/resolvers/master/resolvers.txt \
    -O recon/resolvers.txt 2>/dev/null

puredns resolve recon/all_subs.txt \
    -r recon/resolvers.txt \
    --write recon/resolved.txt \
    -q 2>/dev/null

# Fallback لو puredns فشل
[ ! -s recon/resolved.txt ] && {
    dnsx -l recon/all_subs.txt -silent -resp-only 2>/dev/null \
        > recon/resolved.txt || cp recon/all_subs.txt recon/resolved.txt
}

echo "    > Resolved: $(wc -l < recon/resolved.txt)"

# ============================================================
# PHASE 3: PERMUTATIONS (deep mode فقط)
# ============================================================
if [ "$IS_SUBDOMAIN" = "false" ] && [ "$SKIP_BRUTEFORCE" = "false" ]; then
    echo "[+] 3. Generating Permutations (alterx)..."
    cat recon/resolved.txt \
        | alterx -silent 2>/dev/null \
        > recon/alterx_subs.txt

    puredns resolve recon/alterx_subs.txt \
        -r recon/resolvers.txt \
        --write recon/resolved_alterx.txt \
        -q 2>/dev/null

    cat recon/resolved.txt recon/resolved_alterx.txt \
        | sort -u > recon/all_valid_subs.txt

    echo "    > After permutations: $(wc -l < recon/all_valid_subs.txt)"
else
    cp recon/resolved.txt recon/all_valid_subs.txt
    echo "[~] Skipping permutations (fast/subdomain mode)"
fi

cp recon/all_valid_subs.txt all_valid_subs.txt

# Fallback لو مفيش حاجة
[ ! -s all_valid_subs.txt ] && {
    echo "$TARGET" > all_valid_subs.txt
    echo -e "\e[33m[!] No subs found — running on root domain only\e[0m"
}

# ============================================================
# PHASE 4: DNS DEEP DIVE
# ============================================================
echo "[+] 4. DNS Records (dnsx)..."
dnsx -l all_valid_subs.txt \
    -a -cname -mx -txt \
    -resp -silent 2>/dev/null \
    -o recon/dns_records.txt || true

# CNAME للـ takeover candidates
grep "\[CNAME\]" recon/dns_records.txt 2>/dev/null \
    | awk '{print $1}' > recon/cname_targets.txt || true

echo "    > DNS records: $(wc -l < recon/dns_records.txt 2>/dev/null || echo 0)"
echo "    > CNAME targets: $(wc -l < recon/cname_targets.txt 2>/dev/null || echo 0)"

# ============================================================
# PHASE 5: ASN (deep mode فقط)
# ============================================================
if [ "$IS_SUBDOMAIN" = "false" ] && [ "$MODE" = "deep" ]; then
    echo "[+] 5. ASN Enumeration (asnmap)..."
    asnmap -d "$TARGET" -silent 2>/dev/null > recon/asn_ranges.txt || true
    echo "    > IP Ranges: $(wc -l < recon/asn_ranges.txt 2>/dev/null || echo 0)"

    if [ -s recon/asn_ranges.txt ]; then
        naabu -list recon/asn_ranges.txt \
            -top-ports 100 \
            -rate "${RATE_LIMIT:-500}" \
            -c 30 -silent \
            -o recon/asn_ports.txt 2>/dev/null || true
        echo "    > ASN live hosts: $(wc -l < recon/asn_ports.txt 2>/dev/null || echo 0)"
    fi
fi

# ============================================================
# PHASE 6: PORT SCAN
# ============================================================
echo "[+] 6. Port Scanning (naabu)..."
naabu -l all_valid_subs.txt \
    -top-ports 100 \
    -rate "${RATE_LIMIT:-1000}" \
    -c 50 -silent \
    -o recon/ports.txt 2>/dev/null || true

# دمج كل الأهداف
cat all_valid_subs.txt recon/ports.txt recon/asn_ports.txt 2>/dev/null \
    | sort -u > recon/final_targets.txt

echo "    > Total targets: $(wc -l < recon/final_targets.txt)"

# ============================================================
# PHASE 7: HTTPX — TECH DETECTION
# ============================================================
echo "[+] 7. HTTP Probing + Tech Detection (httpx)..."
httpx -l recon/final_targets.txt \
    "${HEADER_OPTS[@]}" \
    -silent \
    -sc \
    -title \
    -td \
    -server \
    -favicon \
    -rl "${RATE_LIMIT:-50}" \
    -t "${THREADS:-20}" \
    -o recon/live_tech.txt 2>/dev/null

[ ! -s recon/live_tech.txt ] && {
    echo -e "\e[31m[!] No live hosts found. Aborting.\e[0m"
    exit 1
}

awk '{print $1}' recon/live_tech.txt > alive.txt
echo "    > Live hosts: $(wc -l < alive.txt)"

# 403/401
httpx -l recon/final_targets.txt "${HEADER_OPTS[@]}" \
    -silent -mc 403,401 \
    -o recon/forbidden.txt 2>/dev/null || true

# Login pages
grep -iE "login|signin|admin|dashboard|portal|auth" recon/live_tech.txt 2>/dev/null \
    | awk '{print $1}' > login_pages.txt || true

echo "    > Forbidden: $(wc -l < recon/forbidden.txt 2>/dev/null || echo 0)"
echo "    > Login pages: $(wc -l < login_pages.txt 2>/dev/null || echo 0)"

# ============================================================
# PHASE 8: TECH DATABASE
# ============================================================
echo "[+] 8. Building Tech Database..."
for tech in wordpress php react angular vue nginx apache tomcat nodejs spring django laravel jenkins grafana; do
    grep -i "$tech" recon/live_tech.txt 2>/dev/null \
        | awk '{print $1}' > "technologies/${tech}.txt" || true
done

# ============================================================
# PHASE 9: OSINT — GitHub + Cloud (parallel)
# ============================================================
echo "[+] 9. OSINT (GitHub + Cloud + Wayback) [parallel]..."
mkdir -p osint

(
    # GitHub Secrets
    if command -v trufflehog &>/dev/null; then
        ORG=$(echo "$ROOT_DOMAIN" | cut -d'.' -f1)
        trufflehog github --org="$ORG" \
            --only-verified \
            --concurrency=3 \
            --no-update \
            --json 2>/dev/null \
            > osint/trufflehog_github.json || true
        SECRETS=$(grep -c '"SourceMetadata"' osint/trufflehog_github.json 2>/dev/null || echo 0)
        [ "$SECRETS" -gt 0 ] && \
            echo -e "\e[31m    > 🚨 SECRETS LEAKED! osint/trufflehog_github.json\e[0m"
    fi
) &

(
    # Wayback URLs
    if command -v waybackurls &>/dev/null; then
        echo "$ROOT_DOMAIN" | waybackurls 2>/dev/null \
            > osint/wayback_urls.txt || true
        echo "    > Wayback URLs: $(wc -l < osint/wayback_urls.txt)"
    fi
) &

(
    # Google Dorks
    cat > osint/google_dorks.txt <<EOF
# ===== GOOGLE DORKS: $ROOT_DOMAIN =====

site:$ROOT_DOMAIN ext:env OR ext:config OR ext:yml OR ext:yaml
site:$ROOT_DOMAIN ext:sql OR ext:db OR ext:backup OR ext:bak
site:$ROOT_DOMAIN inurl:admin OR inurl:login OR inurl:dashboard
site:$ROOT_DOMAIN "api_key" OR "api_secret" OR "password" OR "token"
site:$ROOT_DOMAIN inurl:api/v1 OR inurl:api/v2 OR inurl:graphql
site:github.com "$ROOT_DOMAIN" password OR secret OR key OR token
site:pastebin.com "$ROOT_DOMAIN"
EOF
) &

wait

echo -e "\e[32m[✔] Recon Phase Completed!\e[0m"
echo "    > Total live hosts: $(wc -l < alive.txt)"
