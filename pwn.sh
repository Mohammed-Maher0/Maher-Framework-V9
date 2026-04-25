#!/bin/bash
# ============================================================
# MAHER FRAMEWORK V9 — THE PRECISION DRAGON
# Version : 9.0
# Author  : Mohammed Maher
# GitHub  : https://github.com/Mohammed-Maher0/Maher-Framework-V9
# ============================================================
export PATH=$PATH:$HOME/go/bin:/usr/local/go/bin:$HOME/.local/bin

# Catch Ctrl+C to skip current command instead of exiting
trap 'echo -e "\n\e[33m[!] Step skipped by user (Ctrl+C). Continuing to next...\e[0m"' SIGINT

# ============================================================
# 1. FLAGS & DEFAULTS
# ============================================================
TARGET=""
CUSTOM_HEADER=""
MODE="deep"        # fast | deep | stealth
SCOPE_FILE=""
NOTIFY_ONLY=false

usage() {
    echo -e "\e[33mUsage: ./pwn.sh -d <domain.com> [OPTIONS]\e[0m"
    echo ""
    echo "  -d <domain>     Target domain (required)"
    echo "  -m <mode>       Scan mode: fast | deep | stealth (default: deep)"
    echo "  -H <header>     Custom header (e.g. 'X-Bug-Bounty: username')"
    echo "  -s <file>       Scope file (one domain/CIDR per line)"
    echo ""
    echo "  Modes:"
    echo "    fast    ~15 min — recon + high/critical only"
    echo "    deep    ~60 min — full pipeline (default)"
    echo "    stealth ~90 min — WAF-aware, slow rate"
    echo ""
    echo "  Examples:"
    echo "    ./pwn.sh -d target.com"
    echo "    ./pwn.sh -d target.com -m fast -H 'X-BBP: hunter'"
    echo "    ./pwn.sh -d target.com -m deep -s scope.txt"
    exit 0
}

while getopts "d:m:H:s:h" opt; do
    case $opt in
        d) TARGET="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        H) CUSTOM_HEADER="$OPTARG" ;;
        s) SCOPE_FILE="$OPTARG" ;;
        h) usage ;;
        \?) echo -e "\e[31m[!] Unknown option. Use -h for help.\e[0m"; exit 1 ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo -e "\e[31m[!] Target is required. Use -h for help.\e[0m"
    exit 1
fi

if [[ ! "$MODE" =~ ^(fast|deep|stealth)$ ]]; then
    echo -e "\e[31m[!] Invalid mode '$MODE'. Choose: fast | deep | stealth\e[0m"
    exit 1
fi

# ============================================================
# 2. ENVIRONMENT SETUP
# ============================================================
DOT_COUNT=$(echo "$TARGET" | tr -cd '.' | wc -c)
if [ "$DOT_COUNT" -ge 2 ]; then
    IS_SUBDOMAIN=true
    ROOT_DOMAIN=$(echo "$TARGET" | awk -F. '{print $(NF-1)"."$NF}')
else
    IS_SUBDOMAIN=false
    ROOT_DOMAIN="$TARGET"
fi

export IS_SUBDOMAIN ROOT_DOMAIN MODE

[ -n "$CUSTOM_HEADER" ] && export CUSTOM_BBP_HEADER="$CUSTOM_HEADER"

TIMESTAMP=$(date +%F_%H-%M)
WORK_DIR="targets/${TARGET}_V9_${MODE}_${TIMESTAMP}"
mkdir -p "$WORK_DIR"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# حفظ session
cat > "$WORK_DIR/.session" <<EOF
TARGET=$TARGET
ROOT_DOMAIN=$ROOT_DOMAIN
IS_SUBDOMAIN=$IS_SUBDOMAIN
MODE=$MODE
TIMESTAMP=$TIMESTAMP
CUSTOM_HEADER=$CUSTOM_HEADER
SCOPE_FILE=$SCOPE_FILE
EOF

# ============================================================
# 3. BANNER
# ============================================================
echo -e "\e[31m"
cat << 'BANNER'
╔══════════════════════════════════════════════════╗
║    __  __    _    _   _ _____ ____               ║
║   |  \/  |  / \  | | | | ____|  _ \             ║
║   | |\/| | / _ \ | |_| |  _| | |_) |            ║
║   | |  | |/ ___ \|  _  | |___|  _ <             ║
║   |_|  |_/_/   \_\_| |_|_____|_| \_\            ║
║                                                  ║
║         FRAMEWORK V9 — PRECISION DRAGON          ║
╚══════════════════════════════════════════════════╝
BANNER
echo -e "\e[0m"

echo -e "\e[32m  🎯 TARGET  : \e[1m$TARGET\e[0m"
echo -e "\e[32m  🌐 MODE    : \e[1m$MODE\e[0m"
echo -e "\e[32m  📁 OUTPUT  : \e[1m$WORK_DIR\e[0m"
[ "$IS_SUBDOMAIN" = "true" ] && echo -e "\e[33m  🔍 ROOT    : $ROOT_DOMAIN (subdomain mode)\e[0m"
[ -n "$CUSTOM_HEADER" ] && echo -e "\e[36m  🛡️  HEADER  : $CUSTOM_HEADER\e[0m"
[ -n "$SCOPE_FILE" ]   && echo -e "\e[36m  📋 SCOPE   : $SCOPE_FILE\e[0m"
echo ""

# ============================================================
# 4. MODE CONFIG
# ============================================================
case "$MODE" in
    fast)
        export NUCLEI_SEVERITY="high,critical"
        export RATE_LIMIT=100
        export THREADS=30
        export CRAWL_DEPTH=3
        export SKIP_BRUTEFORCE=true
        echo -e "\e[33m[⚡] FAST MODE: ~15 min — High/Critical findings only\e[0m"
        ;;
    stealth)
        export NUCLEI_SEVERITY="medium,high,critical"
        export RATE_LIMIT=10
        export THREADS=5
        export CRAWL_DEPTH=5
        export SKIP_BRUTEFORCE=false
        echo -e "\e[34m[🥷] STEALTH MODE: ~90 min — WAF-aware, slow rate\e[0m"
        ;;
    deep|*)
        export NUCLEI_SEVERITY="medium,high,critical"
        export RATE_LIMIT=50
        export THREADS=20
        export CRAWL_DEPTH=5
        export SKIP_BRUTEFORCE=false
        echo -e "\e[31m[🐉] DEEP MODE: ~60 min — Full precision pipeline\e[0m"
        ;;
esac

# ============================================================
# LOAD SCOPE ENGINE
# ============================================================
if [ -f "$SCRIPT_DIR/scope.sh" ]; then
    source "$SCRIPT_DIR/scope.sh"
    scope_load "$ROOT_DOMAIN"
    scope_summary
fi

echo ""
START_TIME=$(date +%s)

# ============================================================
# 5. PIPELINE
# ============================================================
run_phase() {
    local PHASE_NAME=$1
    local SCRIPT=$2
    shift 2
    echo -e "\e[34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "\e[34m[>] $PHASE_NAME\e[0m"
    echo -e "\e[34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    if ! "$SCRIPT_DIR/$SCRIPT" "$@"; then
        echo -e "\e[31m[!] $PHASE_NAME failed — check logs\e[0m"
        return 1
    fi
}

run_phase "PHASE 1: RECON"  "recon.sh"  "$TARGET" "$WORK_DIR" || exit 1
run_phase "PHASE 2: MINE"   "mine.sh"   "$WORK_DIR"
run_phase "PHASE 3: ATTACK" "attack.sh" "$WORK_DIR"
run_phase "PHASE 4: REPORT" "report.sh" "$TARGET"  "$WORK_DIR"

# ============================================================
# 6. FINAL SUMMARY
# ============================================================
END_TIME=$(date +%s)
DURATION=$(( (END_TIME - START_TIME) / 60 ))

echo ""
echo -e "\e[32m╔══════════════════════════════════════════╗\e[0m"
echo -e "\e[32m║           MISSION COMPLETE ✅             ║\e[0m"
echo -e "\e[32m╠══════════════════════════════════════════╣\e[0m"
printf "\e[32m║  %-22s : %-13s ║\e[0m\n" "Target"    "$TARGET"
printf "\e[32m║  %-22s : %-13s ║\e[0m\n" "Mode"      "$MODE"
printf "\e[32m║  %-22s : %-13s ║\e[0m\n" "Duration"  "${DURATION} minutes"
printf "\e[32m║  %-22s : %-13s ║\e[0m\n" "Results"   "$WORK_DIR"
printf "\e[32m║  %-22s : %-13s ║\e[0m\n" "Report"    "REPORT.md"
echo -e "\e[32m╚══════════════════════════════════════════╝\e[0m"
