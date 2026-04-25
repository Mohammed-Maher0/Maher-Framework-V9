#!/bin/bash
# ============================================================
# MAHER FRAMEWORK V9 — SCOPE ENFORCEMENT ENGINE
# ============================================================
# الاستخدام:
#   source scope.sh          (لتحميل الدوال)
#   is_in_scope "sub.target.com"   → 0=yes, 1=no
#   filter_scope < urls.txt  → يطبع الـ URLs في الـ scope بس
# ============================================================

SCOPE_FILE="${SCOPE_FILE:-}"
SCOPE_DOMAINS=()
SCOPE_WILDCARDS=()
SCOPE_EXCLUDE=()

# ============================================================
# تحميل الـ scope من الملف أو من الـ ROOT_DOMAIN
# ============================================================
scope_load() {
    local ROOT="${1:-$ROOT_DOMAIN}"
    SCOPE_DOMAINS=()
    SCOPE_WILDCARDS=()
    SCOPE_EXCLUDE=()

    if [ -n "$SCOPE_FILE" ] && [ -f "$SCOPE_FILE" ]; then
        # قراءة الملف — كل سطر هو domain أو *.domain أو !exclude
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line//[$'\t\r\n']}"
            line="${line%% *}"
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue

            if [[ "$line" == !* ]]; then
                # exclusion
                SCOPE_EXCLUDE+=("${line:1}")
            elif [[ "$line" == \*.* ]]; then
                # wildcard مثل *.target.com
                SCOPE_WILDCARDS+=("${line:2}")
            else
                # exact domain
                SCOPE_DOMAINS+=("$line")
            fi
        done < "$SCOPE_FILE"
        echo -e "  [SCOPE] Loaded from file: $SCOPE_FILE"
        echo -e "  [SCOPE] Domains: ${#SCOPE_DOMAINS[@]} | Wildcards: ${#SCOPE_WILDCARDS[@]} | Excluded: ${#SCOPE_EXCLUDE[@]}"
    elif [ -n "$ROOT" ]; then
        # fallback: الـ root domain وكل الـ subdomains بتاعته
        SCOPE_WILDCARDS+=("$ROOT")
        echo -e "  [SCOPE] Auto-scope: *.$ROOT"
    else
        echo -e "  [SCOPE] ⚠️  No scope defined — all targets accepted"
        return
    fi
}

# ============================================================
# is_in_scope <domain_or_url>
# Returns: 0 = in scope | 1 = out of scope
# ============================================================
is_in_scope() {
    local TARGET="$1"

    # استخلاص الـ domain من الـ URL
    local DOMAIN
    DOMAIN=$(echo "$TARGET" | sed 's|https\?://||;s|/.*||;s|:.*||')

    # فحص الـ exclusions الأول
    for excl in "${SCOPE_EXCLUDE[@]}"; do
        if [[ "$DOMAIN" == "$excl" ]] || [[ "$DOMAIN" == *".$excl" ]]; then
            return 1
        fi
    done

    # لو مفيش scope محدد = كل حاجة في الـ scope
    if [ ${#SCOPE_DOMAINS[@]} -eq 0 ] && [ ${#SCOPE_WILDCARDS[@]} -eq 0 ]; then
        return 0
    fi

    # فحص الـ exact domains
    for d in "${SCOPE_DOMAINS[@]}"; do
        [[ "$DOMAIN" == "$d" ]] && return 0
    done

    # فحص الـ wildcards
    for w in "${SCOPE_WILDCARDS[@]}"; do
        [[ "$DOMAIN" == "$w" ]] && return 0
        [[ "$DOMAIN" == *".$w" ]] && return 0
    done

    return 1
}

# ============================================================
# filter_scope — قراءة من stdin وطباعة اللي في الـ scope بس
# ============================================================
filter_scope() {
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" ]] && continue
        is_in_scope "$line" && echo "$line"
    done
}

# ============================================================
# scope_filter_file <input> <output>
# ============================================================
scope_filter_file() {
    local INPUT="$1" OUTPUT="$2"
    local TOTAL=0 KEPT=0

    if [ ! -f "$INPUT" ]; then
        touch "$OUTPUT" 2>/dev/null
        return
    fi

    > "$OUTPUT"
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" ]] && continue
        TOTAL=$((TOTAL + 1))
        if is_in_scope "$line"; then
            echo "$line" >> "$OUTPUT"
            KEPT=$((KEPT + 1))
        fi
    done < "$INPUT"

    local REMOVED=$((TOTAL - KEPT))
    echo -e "  [SCOPE] $INPUT: $TOTAL → $KEPT kept, $REMOVED removed (out-of-scope)"
}

# ============================================================
# scope_summary — طباعة ملخص الـ scope
# ============================================================
scope_summary() {
    echo ""
    echo "  ┌─────────────────────────────────┐"
    echo "  │         SCOPE SUMMARY           │"
    if [ -n "$SCOPE_FILE" ]; then
        printf "  │  %-10s : %-20s│\n" "File" "$(basename "$SCOPE_FILE")"
    fi
    printf "  │  %-10s : %-20s│\n" "Domains"  "${#SCOPE_DOMAINS[@]}"
    printf "  │  %-10s : %-20s│\n" "Wildcards" "${#SCOPE_WILDCARDS[@]}"
    printf "  │  %-10s : %-20s│\n" "Excluded" "${#SCOPE_EXCLUDE[@]}"
    echo "  └─────────────────────────────────┘"
    echo ""
}

# ============================================================
# scope.txt example generator
# ============================================================
scope_generate_example() {
    local TARGET="${1:-target.com}"
    cat > scope_example.txt << EOF
# ============================================
# SCOPE FILE — MAHER V9
# ============================================
# Wildcard (كل subdomains):
*.${TARGET}

# Exact domains:
${TARGET}
api.${TARGET}
admin.${TARGET}

# Exclusions (برا الـ scope):
!staging.${TARGET}
!dev.${TARGET}
!test.${TARGET}
# ============================================
EOF
    echo "  [SCOPE] Example generated: scope_example.txt"
}
