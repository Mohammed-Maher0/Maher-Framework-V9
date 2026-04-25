#!/bin/bash
# ============================================================
# MAHER V9 — PHASE 2: MINE
# gf patterns + qsreplace pipelines + parallel collection
# ============================================================
export PATH=$PATH:$HOME/go/bin:/usr/local/go/bin

# Catch Ctrl+C to skip current command instead of exiting
trap 'echo -e "\n\e[33m[!] Step skipped by user (Ctrl+C). Continuing to next...\e[0m"' SIGINT

WORK_DIR=$1
[ -z "$WORK_DIR" ] && { echo -e "\e[31m[!] Usage: ./mine.sh <work_dir>\e[0m"; exit 1; }

HEADER_OPTS=()
[ -n "$CUSTOM_BBP_HEADER" ] && HEADER_OPTS=("-H" "$CUSTOM_BBP_HEADER")

echo -e "\e[33m╔══════════════════════════════════════════╗\e[0m"
echo -e "\e[33m║     ⛏️  MINE PHASE V9 — DEEP DIG         ║\e[0m"
echo -e "\e[33m╚══════════════════════════════════════════╝\e[0m"

cd "$WORK_DIR" || exit 1
mkdir -p mining/{params,js,api,discovery}

# ============================================================
# PHASE 1: URL COLLECTION (PARALLEL)
# ============================================================
echo "[+] 1. URL Collection — Parallel (GAU + Katana + Wayback)..."

# GAU
(gau --threads 10 < alive.txt 2>/dev/null \
    > mining/urls_gau.txt) &

# Katana — active crawler
(katana -list alive.txt \
    "${HEADER_OPTS[@]}" \
    -silent \
    -jc \
    -depth "${CRAWL_DEPTH:-5}" \
    -aff \
    2>/dev/null \
    > mining/urls_katana.txt) &

# Wayback
([ -s osint/wayback_urls.txt ] \
    && cp osint/wayback_urls.txt mining/urls_wayback.txt \
    || (cat alive.txt | while read url; do
        domain=$(echo "$url" | sed 's|https\?://||' | cut -d/ -f1)
        waybackurls "$domain" 2>/dev/null
       done > mining/urls_wayback.txt)) &

wait

echo "    > GAU: $(wc -l < mining/urls_gau.txt 2>/dev/null || echo 0)"
echo "    > Katana: $(wc -l < mining/urls_katana.txt 2>/dev/null || echo 0)"
echo "    > Wayback: $(wc -l < mining/urls_wayback.txt 2>/dev/null || echo 0)"

# ============================================================
# PHASE 2: SMART DEDUPLICATION (anew + uro)
# ============================================================
echo "[+] 2. Smart Deduplication (anew + uro)..."

# استخدام anew بدل sort لتسريع العملية وعدم استهلاك الرامات
cat mining/urls_*.txt 2>/dev/null | anew > mining/urls_raw.txt

if command -v uro &>/dev/null; then
    cat mining/urls_raw.txt | uro 2>/dev/null > all_urls.txt
    echo "    > After uro: $(wc -l < all_urls.txt) (was $(wc -l < mining/urls_raw.txt))"
else
    cp mining/urls_raw.txt all_urls.txt
    echo "    > [!] uro not installed — using anew fallback (install: pip install uro)"
fi

# ============================================================
# PHASE 3: SCOPE ENGINE FILTERING
# ============================================================
echo "[+] 3. Smart Scope Filtering..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/scope.sh" ]; then
    source "$SCRIPT_DIR/scope.sh"
    scope_load "$ROOT_DOMAIN"
    scope_filter_file all_urls.txt all_urls_filtered.txt
    mv all_urls_filtered.txt all_urls.txt
else
    # Fallback لو ملف scope.sh مش موجود
    grep "$ROOT_DOMAIN" all_urls.txt > all_urls_filtered.txt
    mv all_urls_filtered.txt all_urls.txt
fi

# Params فقط
grep "=" all_urls.txt | sort -u > all_params.txt
echo "    > Parameterized URLs: $(wc -l < all_params.txt)"

# ============================================================
# PHASE 4: GF PATTERNS — Smart Categorization
# ============================================================
echo "[+] 4. Smart Parameter Categorization (gf patterns)..."

if command -v gf &>/dev/null; then
    cat all_params.txt | gf xss    2>/dev/null | sort -u > mining/xss.txt
    cat all_params.txt | gf sqli   2>/dev/null | sort -u > mining/sqli.txt
    cat all_params.txt | gf ssrf   2>/dev/null | sort -u > mining/ssrf.txt
    cat all_params.txt | gf lfi    2>/dev/null | sort -u > mining/lfi.txt
    cat all_params.txt | gf rce    2>/dev/null | sort -u > mining/rce.txt
    cat all_params.txt | gf idor   2>/dev/null | sort -u > mining/idor.txt
    cat all_params.txt | gf redirect 2>/dev/null | sort -u > mining/redirect.txt
    cat all_params.txt | gf ssti   2>/dev/null | sort -u > mining/ssti.txt
    echo "    > gf patterns applied ✅ (community-curated rules)"
else
    echo "    > [!] gf not installed — falling back to regex"
    grep -iE "[?&](q|s|search|query|input|text|html|lang|keyword|callback|jsonp)=" all_params.txt | sort -u > mining/xss.txt
    grep -iE "[?&](id|page|dir|category|sort|user|item|cat|p|article|product|num|limit|offset|order)=" all_params.txt | sort -u > mining/sqli.txt
    grep -iE "[?&](url|dest|path|uri|domain|site|out|redirect|next|return|go|target|window|location|link|src|href)=" all_params.txt | sort -u > mining/ssrf.txt
    grep -iE "[?&](file|page|dir|doc|folder|path|include|template|layout|load|read|fetch|content)=" all_params.txt | sort -u > mining/lfi.txt
    grep -iE "[?&](cmd|exec|ping|run|do|shell|query|eval|daemon|system|proc|process|execute|command)=" all_params.txt | sort -u > mining/rce.txt
    grep -iE "[?&](id|user_id|account|profile|order|invoice|doc|receipt|bill|ticket|uid|pid|cid)=" all_params.txt | sort -u > mining/idor.txt
    grep -iE "[?&](url|dest|path|uri|domain|redirect|next|return|go|target|location|link|src)=" all_params.txt | sort -u > mining/redirect.txt
    grep -iE "[?&](template|page|view|tpl|layout|render|engine|theme)=" all_params.txt | sort -u > mining/ssti.txt
fi

# ============================================================
# PHASE 5: QSREPLACE PIPELINES — Mass Confirmation
# ============================================================
echo "[+] 5. qsreplace Mass-Testing Pipelines..."

if command -v qsreplace &>/dev/null; then
    # SSRF Pipeline — OAST-ready
    OAST_HOST="${OAST_DOMAIN:-canary.interactsh.com}"
    if [ -s mining/ssrf.txt ]; then
        cat mining/ssrf.txt \
            | qsreplace "http://${OAST_HOST}" \
            | httpx -silent -status-code -no-fallback \
                "${HEADER_OPTS[@]}" 2>/dev/null \
            > mining/ssrf_tested.txt || true
        echo "    > SSRF mass-tested: $(wc -l < mining/ssrf_tested.txt) requests sent"
    fi

    # Open Redirect Pipeline
    if [ -s mining/redirect.txt ]; then
        cat mining/redirect.txt \
            | qsreplace "https://evil.com" \
            | httpx -silent -location \
                "${HEADER_OPTS[@]}" 2>/dev/null \
            | grep -i "evil.com" \
            > mining/redirect_confirmed.txt || true
        REDIRECT_COUNT=$(wc -l < mining/redirect_confirmed.txt)
        echo "    > Open Redirects CONFIRMED: $REDIRECT_COUNT"
        [ "$REDIRECT_COUNT" -gt 0 ] && \
            echo -e "\e[33m    > ⚠️  Check mining/redirect_confirmed.txt\e[0m"
    fi

    # LFI Quick Check
    if [ -s mining/lfi.txt ]; then
        cat mining/lfi.txt \
            | qsreplace "/etc/passwd" \
            | while read url; do
                RESP=$(curl -sk "$url" "${HEADER_OPTS[@]/#/-H}" -m 8 2>/dev/null)
                echo "$RESP" | grep -q "root:x:" && echo "$url"
              done \
            > mining/lfi_confirmed.txt || true
        LFI_COUNT=$(wc -l < mining/lfi_confirmed.txt)
        echo "    > LFI CONFIRMED: $LFI_COUNT"
        [ "$LFI_COUNT" -gt 0 ] && \
            echo -e "\e[31m    > 🚨 LFI FOUND! Check mining/lfi_confirmed.txt\e[0m"
    fi
else
    echo "    > [!] qsreplace not found (install: go install github.com/tomnomnom/qsreplace@latest)"
fi

# ============================================================
# PHASE 6: JS ANALYSIS
# ============================================================
echo "[+] 6. Deep JS Analysis..."
grep -iE "\.js(\?.*)?$" all_urls.txt | sort -u > mining/js/js_urls.txt
echo "    > JS files: $(wc -l < mining/js/js_urls.txt)"

# LinkFinder / gf على JS content
if [ -s mining/js/js_urls.txt ]; then
    # استخراج endpoints من JS
    (katana -list mining/js/js_urls.txt -jc -silent 2>/dev/null \
        | grep -iE "^https?://" \
        | sort -u \
        > mining/js/js_endpoints.txt) &

    # AWS Keys من JS
    (cat mining/js/js_urls.txt | while read url; do
        curl -sk "$url" "${HEADER_OPTS[@]/#/-H}" 2>/dev/null
    done | grep -iE "AKIA[0-9A-Z]{16}" > mining/js/aws_keys.txt) &

    # Secrets في JS (gf)
    if command -v gf &>/dev/null; then
        (cat mining/js/js_urls.txt | while read url; do
            curl -sk "$url" "${HEADER_OPTS[@]/#/-H}" 2>/dev/null
        done | gf aws-keys 2>/dev/null > mining/js/gf_aws.txt) &
    fi

    wait
    echo "    > JS endpoints: $(wc -l < mining/js/js_endpoints.txt 2>/dev/null || echo 0)"
fi

# TruffleHog على الـ JS
if command -v trufflehog &>/dev/null && [ -s mining/js/js_urls.txt ]; then
    trufflehog filesystem --directory="." \
        --only-verified --no-update \
        --json 2>/dev/null \
        > mining/js/trufflehog_js.json || true
    SECRETS=$(grep -c '"SourceMetadata"' mining/js/trufflehog_js.json 2>/dev/null || echo 0)
    echo "    > JS Verified Secrets: $SECRETS"
fi

# ============================================================
# PHASE 7: API DISCOVERY (Kiterunner)
# ============================================================
echo "[+] 7. API Discovery (Kiterunner + patterns)..."

# Pattern-based extraction
grep -iE "/api/|/v[0-9]+/|/rest/|/swagger|/openapi" all_urls.txt \
    | sort -u > mining/api/api_endpoints.txt

# GraphQL
grep -iE "/graphql|/gql|/graph" all_urls.txt | sort -u > mining/api/graphql.txt
for gql_path in "/graphql" "/api/graphql" "/gql" "/v1/graphql"; do
    httpx -l alive.txt "${HEADER_OPTS[@]}" \
        -path "$gql_path" -mc 200,400 \
        -silent 2>/dev/null \
        | awk "{print \$1\"${gql_path}\"}" >> mining/api/graphql.txt 2>/dev/null || true
done
sort -u mining/api/graphql.txt -o mining/api/graphql.txt

# Kiterunner — bruteforce API routes
if command -v kr &>/dev/null; then
    KR_WORDLIST="$HOME/tools/kiterunner/routes-large.kite"
    [ ! -f "$KR_WORDLIST" ] && KR_WORDLIST="$HOME/tools/kiterunner/routes-small.kite"
    if [ -f "$KR_WORDLIST" ]; then
        kr scan alive.txt \
            -w "$KR_WORDLIST" \
            -x "${THREADS:-20}" \
            --ignore-length=34 \
            -o mining/api/kiterunner_routes.txt \
            2>/dev/null || true
        echo "    > Kiterunner API routes: $(wc -l < mining/api/kiterunner_routes.txt 2>/dev/null || echo 0)"
    fi
fi

echo "    > API endpoints: $(wc -l < mining/api/api_endpoints.txt)"
echo "    > GraphQL: $(wc -l < mining/api/graphql.txt)"

# ============================================================
# PHASE 8: PARAMETER DISCOVERY (Arjun)
# ============================================================
echo "[+] 8. Hidden Parameter Discovery (Arjun)..."
mkdir -p mining/params/arjun

if command -v arjun &>/dev/null && [ -s alive.txt ]; then
    head -15 alive.txt | while IFS= read -r url; do
        SAFE=$(echo "$url" | md5sum | cut -c1-8)
        arjun -u "$url" \
            -oJ "mining/params/arjun/arjun_${SAFE}.json" \
            --stable -t 2 -d 1 -q \
            2>/dev/null || true
    done
    echo "    > Arjun results in mining/params/arjun/"
else
    echo "    > [!] arjun not found (install: pip install arjun)"
fi

# ============================================================
# PHASE 9: CUSTOM WORDLIST (tok)
# ============================================================
echo "[+] 9. Building Target-Specific Wordlist..."
if command -v tok &>/dev/null; then
    cat all_urls.txt | tok 2>/dev/null \
        | sort | uniq -c | sort -rn \
        | awk '$1 > 2 && length($2) > 3 && length($2) < 25 {print $2}' \
        > mining/custom_wordlist.txt
else
    # Fallback manual
    cat all_urls.txt \
        | awk -F/ '{for(i=3;i<=NF;i++) print $i}' \
        | sed 's/?.*//' | tr "[:punct:]" "\n" \
        | sort -u \
        | grep -v "^[0-9]*$" \
        | awk '{ if (length($0) > 3 && length($0) < 25) print $0 }' \
        > mining/custom_wordlist.txt
fi
echo "    > Custom wordlist: $(wc -l < mining/custom_wordlist.txt) words"

# ============================================================
# PHASE 10: 403 COLLECTION
# ============================================================
echo "[+] 10. Collecting 403/401 Endpoints..."
[ -f recon/forbidden.txt ] && cp recon/forbidden.txt mining/forbidden.txt \
    || touch mining/forbidden.txt
echo "    > Forbidden: $(wc -l < mining/forbidden.txt)"

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo -e "\e[33m╔════════════════════════════════════════╗\e[0m"
echo -e "\e[33m║         MINING SUMMARY V9              ║\e[0m"
echo -e "\e[33m╠════════════════════════════════════════╣\e[0m"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "Total URLs"   "$(wc -l < all_urls.txt)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "Params"       "$(wc -l < all_params.txt)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "XSS targets"  "$(wc -l < mining/xss.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "SQLi targets" "$(wc -l < mining/sqli.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "SSRF targets" "$(wc -l < mining/ssrf.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "LFI targets"  "$(wc -l < mining/lfi.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "RCE targets"  "$(wc -l < mining/rce.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "SSTI targets" "$(wc -l < mining/ssti.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "IDOR targets" "$(wc -l < mining/idor.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "Redirect ✅"  "$(wc -l < mining/redirect_confirmed.txt 2>/dev/null || echo 0) CONFIRMED"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "LFI ✅"       "$(wc -l < mining/lfi_confirmed.txt 2>/dev/null || echo 0) CONFIRMED"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "API Endpts"   "$(wc -l < mining/api/api_endpoints.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "GraphQL"      "$(wc -l < mining/api/graphql.txt 2>/dev/null || echo 0)"
printf "\e[33m║  %-16s : %-19s ║\e[0m\n" "JS Endpoints" "$(wc -l < mining/js/js_endpoints.txt 2>/dev/null || echo 0)"
echo -e "\e[33m╚════════════════════════════════════════╝\e[0m"

echo -e "\e[32m[✔] Mining Phase Completed!\e[0m"
