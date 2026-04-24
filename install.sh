#!/bin/bash
# ============================================================
# MAHER FRAMEWORK V9 — INSTALLER
# ============================================================
export PATH=$PATH:$HOME/go/bin:/usr/local/go/bin

echo -e "\e[31m"
cat << 'BANNER'
╔══════════════════════════════════════════════════╗
║   MAHER FRAMEWORK V9 — TOOL INSTALLER           ║
╚══════════════════════════════════════════════════╝
BANNER
echo -e "\e[0m"

# ============================================================
# CHECKS
# ============================================================
if ! command -v go &>/dev/null; then
    echo -e "\e[31m[!] Go not found! Install from: https://go.dev/doc/install\e[0m"
    exit 1
fi
echo -e "\e[32m[✔] Go: $(go version)\e[0m"
mkdir -p "$HOME/tools" "$HOME/.local/bin"

# ============================================================
# HELPERS
# ============================================================
ok()   { echo -e "  \e[32m✅ $1\e[0m"; }
fail() { echo -e "  \e[31m❌ $1\e[0m"; }
info() { echo -e "  \e[33m📦 Installing $1...\e[0m"; }
skip() { echo -e "  \e[36m⏭️  $1 already installed\e[0m"; }

install_go_tool() {
    local NAME=$1 PKG=$2
    command -v "$NAME" &>/dev/null && { skip "$NAME"; return; }
    info "$NAME"
    go install "$PKG" 2>/dev/null && ok "$NAME" || fail "$NAME"
}

install_pip_tool() {
    local NAME=$1 PKG=$2
    command -v "$NAME" &>/dev/null && { skip "$NAME"; return; }
    info "$NAME"
    pip3 install "$PKG" --break-system-packages -q 2>/dev/null \
        && ok "$NAME" || fail "$NAME"
}

# ============================================================
# 1. RECON TOOLS
# ============================================================
echo ""
echo -e "\e[34m[1] Recon Tools\e[0m"
install_go_tool "subfinder"   "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
install_go_tool "cero"        "github.com/glebarez/cero@latest"
install_go_tool "puredns"     "github.com/d3mondev/puredns/v2@latest"
install_go_tool "alterx"      "github.com/projectdiscovery/alterx/cmd/alterx@latest"
install_go_tool "dnsx"        "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
install_go_tool "asnmap"      "github.com/projectdiscovery/asnmap/cmd/asnmap@latest"
install_go_tool "naabu"       "github.com/projectdiscovery/naabu/cmd/naabu@latest"
install_go_tool "httpx"       "github.com/projectdiscovery/httpx/cmd/httpx@latest"
install_go_tool "uncover"     "github.com/projectdiscovery/uncover/cmd/uncover@latest"
install_go_tool "github-subdomains" "github.com/gwen001/github-subdomains@latest"

# ============================================================
# 2. URL MINING TOOLS
# ============================================================
echo ""
echo -e "\e[34m[2] URL Mining Tools\e[0m"
install_go_tool "gau"         "github.com/lc/gau/v2/cmd/gau@latest"
install_go_tool "katana"      "github.com/projectdiscovery/katana/cmd/katana@latest"
install_go_tool "waybackurls" "github.com/tomnomnom/waybackurls@latest"
install_go_tool "anew"        "github.com/tomnomnom/anew@latest"
install_go_tool "qsreplace"   "github.com/tomnomnom/qsreplace@latest"
install_go_tool "tok"         "github.com/tomnomnom/hacks/tok@latest"
install_pip_tool "uro"        "uro"

# ============================================================
# 3. GF PATTERNS (أهم أداة في V9)
# ============================================================
echo ""
echo -e "\e[34m[3] gf Patterns (Smart Param Categorization)\e[0m"
install_go_tool "gf" "github.com/tomnomnom/gf@latest"

GF_DIR="$HOME/.config/gf"
mkdir -p "$GF_DIR"

if [ ! -f "$GF_DIR/xss.json" ]; then
    info "gf patterns (community)"
    git clone --quiet https://github.com/1ndianl33t/Gf-Patterns.git \
        /tmp/gf-patterns 2>/dev/null && \
    cp /tmp/gf-patterns/*.json "$GF_DIR/" 2>/dev/null && \
    rm -rf /tmp/gf-patterns && ok "gf patterns" || fail "gf patterns"
else
    skip "gf patterns"
fi

# ============================================================
# 4. ATTACK TOOLS
# ============================================================
echo ""
echo -e "\e[34m[4] Attack Tools\e[0m"
install_go_tool "nuclei"            "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
install_go_tool "dalfox"            "github.com/hahwul/dalfox/v2@latest"
install_go_tool "ffuf"              "github.com/ffuf/ffuf/v2@latest"
install_go_tool "interactsh-client" "github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest"
install_go_tool "crlfuzz"           "github.com/dwisiswant0/crlfuzz/cmd/crlfuzz@latest"
install_go_tool "notify"            "github.com/projectdiscovery/notify/cmd/notify@latest"

# sqlmap
if command -v sqlmap &>/dev/null; then
    skip "sqlmap"
else
    info "sqlmap"
    sudo apt-get install -y sqlmap -qq 2>/dev/null || \
        pip3 install sqlmap --break-system-packages -q 2>/dev/null
    command -v sqlmap &>/dev/null && ok "sqlmap" || fail "sqlmap (install manually: sudo apt install sqlmap)"
fi

# Arjun
install_pip_tool "arjun" "arjun"

# x8 — fast param fuzzer
if ! command -v x8 &>/dev/null; then
    info "x8"
    X8_URL="https://github.com/Sh1Yo/x8/releases/latest/download/x86_64-linux-x8"
    curl -sL "$X8_URL" -o "$HOME/.local/bin/x8" 2>/dev/null && \
        chmod +x "$HOME/.local/bin/x8" && ok "x8" || fail "x8"
else
    skip "x8"
fi

# ============================================================
# 5. API TOOLS
# ============================================================
echo ""
echo -e "\e[34m[5] API Discovery Tools\e[0m"

# Kiterunner
if ! command -v kr &>/dev/null; then
    info "kiterunner"
    mkdir -p "$HOME/tools/kiterunner"
    KR_URL="https://github.com/assetnote/kiterunner/releases/latest/download/kiterunner_linux_amd64.tar.gz"
    curl -sL "$KR_URL" | tar -xz -C "$HOME/tools/kiterunner" 2>/dev/null && \
        ln -sf "$HOME/tools/kiterunner/kr" "$HOME/.local/bin/kr" && \
        ok "kiterunner" || fail "kiterunner"

    # Download wordlist
    info "kiterunner wordlist"
    curl -sL "https://wordlists-cdn.assetnote.io/data/kiterunner/routes-large.kite.tar.gz" \
        -o "$HOME/tools/kiterunner/routes-large.kite.tar.gz" 2>/dev/null && \
        tar -xzf "$HOME/tools/kiterunner/routes-large.kite.tar.gz" \
        -C "$HOME/tools/kiterunner/" 2>/dev/null && \
        ok "kiterunner wordlist" || fail "kiterunner wordlist"
else
    skip "kiterunner"
fi

# ============================================================
# 6. OSINT TOOLS
# ============================================================
echo ""
echo -e "\e[34m[6] OSINT Tools\e[0m"

# TruffleHog
if ! command -v trufflehog &>/dev/null; then
    info "trufflehog"
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
        | sudo sh -s -- -b /usr/local/bin 2>/dev/null && \
        ok "trufflehog" || fail "trufflehog"
else
    skip "trufflehog"
fi

# cloud_enum
install_pip_tool "cloud_enum" "cloud-enum"

# ============================================================
# 7. JWT TOOL
# ============================================================
echo ""
echo -e "\e[34m[7] JWT Tool\e[0m"
if [ ! -f "$HOME/tools/jwt_tool/jwt_tool.py" ]; then
    info "jwt_tool"
    git clone --quiet https://github.com/ticarpi/jwt_tool.git \
        "$HOME/tools/jwt_tool" 2>/dev/null && \
        pip3 install termcolor cprint pycryptodomex requests \
            --break-system-packages -q 2>/dev/null && \
        chmod +x "$HOME/tools/jwt_tool/jwt_tool.py" && \
        ln -sf "$HOME/tools/jwt_tool/jwt_tool.py" "$HOME/.local/bin/jwt_tool" 2>/dev/null && \
        ok "jwt_tool" || fail "jwt_tool"
else
    skip "jwt_tool"
fi

# ============================================================
# 8. NUCLEI SETUP
# ============================================================
echo ""
echo -e "\e[34m[8] Nuclei Templates\e[0m"
echo "  📦 Updating templates..."
nuclei -update-templates -silent 2>/dev/null && ok "nuclei templates" || fail "nuclei templates"

# ============================================================
# 9. WORDLISTS
# ============================================================
echo ""
echo -e "\e[34m[9] Wordlists (SecLists)\e[0m"
SECLISTS="/usr/share/seclists"
if [ ! -d "$SECLISTS" ]; then
    info "SecLists"
    sudo apt-get install -y seclists -qq 2>/dev/null || \
        git clone --quiet --depth=1 \
            https://github.com/danielmiessler/SecLists.git \
            "$SECLISTS" 2>/dev/null
    [ -d "$SECLISTS" ] && ok "SecLists" || fail "SecLists"
else
    skip "SecLists ($SECLISTS)"
fi

# ============================================================
# 10. PERMISSIONS
# ============================================================
echo ""
echo -e "\e[34m[10] Setting Permissions\e[0m"
chmod +x pwn.sh recon.sh mine.sh attack.sh report.sh install.sh 2>/dev/null
ok "Permissions set"

# ============================================================
# DONE
# ============================================================
echo ""
echo -e "\e[32m╔══════════════════════════════════════════════╗\e[0m"
echo -e "\e[32m║   ✅ MAHER V9 — Installation Complete!      ║\e[0m"
echo -e "\e[32m╠══════════════════════════════════════════════╣\e[0m"
echo -e "\e[32m║  OPTIONAL ENV VARS:                          ║\e[0m"
echo -e "\e[32m║  export GITHUB_TOKEN=ghp_xxx                 ║\e[0m"
echo -e "\e[32m║  export TG_TOKEN=xxx                         ║\e[0m"
echo -e "\e[32m║  export TG_CHAT=xxx                          ║\e[0m"
echo -e "\e[32m║  export SHODAN_API_KEY=xxx                   ║\e[0m"
echo -e "\e[32m╠══════════════════════════════════════════════╣\e[0m"
echo -e "\e[32m║  USAGE:                                      ║\e[0m"
echo -e "\e[32m║  ./pwn.sh -d target.com                      ║\e[0m"
echo -e "\e[32m║  ./pwn.sh -d target.com -m fast              ║\e[0m"
echo -e "\e[32m║  ./pwn.sh -d target.com -m deep -s scope.txt ║\e[0m"
echo -e "\e[32m║  ./pwn.sh -d target.com -m stealth           ║\e[0m"
echo -e "\e[32m╚══════════════════════════════════════════════╝\e[0m"
