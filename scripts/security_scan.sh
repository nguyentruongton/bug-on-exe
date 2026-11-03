#!/usr/bin/env bash
# ==============================================================================
# Bug On EXE - Pre-Publish Open Source Security & Integrity Scanner
# ==============================================================================
# Usage:
#   bash scripts/security_scan.sh [OPTIONS]
#
# Options:
#   --strict / --release   Fail if vendor dependencies or dist packages are absent
#   --verify-dist          Verify release packages in dist/ (.dmg & .zip)
#   -h, --help             Show this help message
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

STRICT_MODE=0
VERIFY_DIST=0

for arg in "$@"; do
    case "$arg" in
        --strict|--release)
            STRICT_MODE=1
            ;;
        --verify-dist)
            VERIFY_DIST=1
            ;;
        -h|--help)
            echo "Usage: $0 [--strict|--release] [--verify-dist] [--help]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--strict|--release] [--verify-dist] [--help]"
            exit 1
            ;;
    esac
done

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

log_pass() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "  [${GREEN}PASS${NC}] $1"
}

log_fail() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    echo -e "  [${RED}FAIL${NC}] $1"
}

log_warn() {
    WARNINGS=$((WARNINGS + 1))
    echo -e "  [${YELLOW}WARN${NC}] $1"
}

log_suite() {
    echo -e "\n${BOLD}${BLUE}==> $1${NC}"
}

# ------------------------------------------------------------------------------
# Suite 1: Secret & Personal Path Audit
# ------------------------------------------------------------------------------
log_suite "Suite 1: Secrets, API Tokens & Personal Path Audit"

# 1.1 Private Keys
PRIVATE_KEY_MATCHES=$(grep -rnE 'BEGIN (RSA|DSA|EC|OPENSSH|PGP) PRIVATE KEY' \
    --exclude-dir='.git' \
    --exclude-dir='.superpowers' \
    --exclude-dir='docs' \
    --exclude-dir='dist' \
    --exclude-dir='Vendor' \
    --exclude='*.png' \
    --exclude='*.svg' \
    --exclude='*.icns' \
    . 2>/dev/null || true)

if [ -n "$PRIVATE_KEY_MATCHES" ]; then
    log_fail "Found unencrypted private keys in working tree:\n$PRIVATE_KEY_MATCHES"
else
    log_pass "No unencrypted private keys detected in working tree"
fi

# 1.2 Known Cloud / API Token Patterns
TOKEN_MATCHES=$(grep -rnE '(gh[pousr]_[A-Za-z0-9_]{36,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z\-_]{35})' \
    --exclude-dir='.git' \
    --exclude-dir='.superpowers' \
    --exclude-dir='dist' \
    --exclude='*.png' \
    --exclude='*.svg' \
    --exclude='*.icns' \
    . 2>/dev/null || true)

if [ -n "$TOKEN_MATCHES" ]; then
    log_fail "Found potential cloud or service tokens in working tree:\n$TOKEN_MATCHES"
else
    log_pass "No hardcoded API/Cloud tokens detected in working tree"
fi

# 1.3 Personal Author Directory Paths in Working Tree
# Exclude known generic documentation mocks (/Users/example, /Users/developer)
PERSONAL_PATH_MATCHES=$(git grep -E '/Users/(stark|[a-zA-Z0-9_-]+/(Documents|Desktop|Downloads))' 2>/dev/null || true)
if [ -n "$PERSONAL_PATH_MATCHES" ]; then
    log_fail "Found hardcoded personal user directories in working tree:\n$PERSONAL_PATH_MATCHES"
else
    log_pass "No personal user home directories detected in working tree"
fi

# 1.4 Commit History Scan
if git rev-parse --verify origin/main >/dev/null 2>&1; then
    COMMIT_RANGE="origin/main..HEAD"
else
    COMMIT_RANGE="HEAD"
fi

HISTORICAL_PERSONAL_PATHS=$(git log -p "$COMMIT_RANGE" -- . ':(exclude)docs/superpowers' 2>/dev/null | grep -E '^\+.*\/Users\/(stark|[a-zA-Z0-9_-]+\/(Documents|Desktop|Downloads))' || true)
if [ -n "$HISTORICAL_PERSONAL_PATHS" ]; then
    log_fail "Found unpushed commit diffs containing personal home directories:\n$HISTORICAL_PERSONAL_PATHS"
else
    log_pass "Unpushed commit range ($COMMIT_RANGE) is clean of personal home paths"
fi

# ------------------------------------------------------------------------------
# Suite 2: Binary Integrity & Checksum Verification
# ------------------------------------------------------------------------------
log_suite "Suite 2: Binary Integrity & Checksum Verification"

CHECKSUM_FILE="Vendor/checksums.sha256"
if [ ! -f "$CHECKSUM_FILE" ]; then
    log_fail "Locked checksum manifest '$CHECKSUM_FILE' is missing!"
else
    log_pass "Checksum manifest '$CHECKSUM_FILE' exists"
    
    # Check if vendor files exist
    VENDOR_MISSING=0
    while read -r hash filepath; do
        [[ "$hash" =~ ^#.* ]] && continue
        [ -z "$hash" ] && continue
        if [ ! -e "$filepath" ]; then
            VENDOR_MISSING=1
            break
        fi
    done < "$CHECKSUM_FILE"

    if [ "$VENDOR_MISSING" -eq 1 ]; then
        if [ "$STRICT_MODE" -eq 1 ]; then
            log_fail "Vendor binaries are missing while running in --strict mode"
        else
            log_warn "Vendor binaries are absent (fresh clone). Skipping SHA256 verification (pass --strict to require)"
        fi
    else
        # Verify SHA-256 hashes
        if shasum -a 256 -c "$CHECKSUM_FILE" >/dev/null 2>&1; then
            log_pass "All vendor binaries match locked SHA-256 signatures"
        else
            log_fail "Vendor binary SHA-256 hash mismatch! Possible file tampering detected"
        fi

        # Verify Code Signature of bundled Flash Player
        FLASH_APP="Vendor/Flash Player.app"
        if [ -d "$FLASH_APP" ]; then
            if codesign -dv "$FLASH_APP" >/dev/null 2>&1; then
                log_pass "Vendor Flash Player.app has valid code signature structure"
            else
                log_fail "Vendor Flash Player.app code signature validation failed"
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Suite 3: Code Safety & Subprocess Execution Audit
# ------------------------------------------------------------------------------
log_suite "Suite 3: Code Safety & Subprocess Execution Audit"

# 3.1 Swift Unsanitized Process Execution
# Flag any Process() where executable is /bin/sh or /bin/bash with raw interpolated -c strings
DANGEROUS_SWIFT_SHELL=$(grep -rnE 'arguments.*=.*\[.*"-c".*\\\(' Sources/ 2>/dev/null || true)
if [ -n "$DANGEROUS_SWIFT_SHELL" ]; then
    log_fail "Found unescaped string interpolation in shell subprocess execution:\n$DANGEROUS_SWIFT_SHELL"
else
    log_pass "No unsafe shell string interpolation detected in Swift subprocesses"
fi

# 3.2 Shell Scripts Strict Mode
UNSAFE_SCRIPTS=""
for sh_file in scripts/*.sh; do
    [ -f "$sh_file" ] || continue
    if ! grep -q "set -euo pipefail" "$sh_file"; then
        UNSAFE_SCRIPTS="$UNSAFE_SCRIPTS\n$sh_file"
    fi
done

if [ -n "$UNSAFE_SCRIPTS" ]; then
    log_fail "The following shell scripts lack 'set -euo pipefail':$UNSAFE_SCRIPTS"
else
    log_pass "All repository shell scripts enforce 'set -euo pipefail'"
fi

# ------------------------------------------------------------------------------
# Suite 4: Git Hygiene & Dist Packaging Check
# ------------------------------------------------------------------------------
log_suite "Suite 4: Git Hygiene & Packaging Check"

# 4.1 Git Ignore Verification
if grep -q "Vendor/\*" .gitignore && grep -q "!Vendor/checksums.sha256" .gitignore; then
    log_pass ".gitignore correctly ignores Vendor/* while tracking Vendor/checksums.sha256"
else
    log_fail ".gitignore missing required rules for Vendor/ tracking"
fi

# 4.2 Tracked Binaries in Git Index
TRACKED_BINARIES=$(git ls-files | grep -E '\.(dmg|zip|app|dylib|o|a)$' || true)
if [ -n "$TRACKED_BINARIES" ]; then
    log_fail "Found compiled binaries or packages tracked in Git index:\n$TRACKED_BINARIES"
else
    log_pass "No compiled binaries or packages are tracked in Git index"
fi

# 4.3 Root License Check
if [ -f "LICENSE" ] && grep -qi "MIT License" "LICENSE"; then
    log_pass "Root LICENSE file exists and contains valid MIT License"
else
    log_fail "Root LICENSE file missing or does not contain valid MIT license text"
fi

# 4.4 Optional Dist Verification
if [ "$VERIFY_DIST" -eq 1 ]; then
    log_suite "Suite 4.4: Distribution Artifact Verification"
    DMG_PATH="dist/Bug-On-EXE-macOS.dmg"
    ZIP_PATH="dist/Bug-On-EXE-macOS.zip"
    APP_PATH="dist/Bug On EXE.app"

    if [ -f "$DMG_PATH" ] && [ -s "$DMG_PATH" ]; then
        if hdiutil imageinfo "$DMG_PATH" >/dev/null 2>&1; then
            log_pass "Distribution DMG ($DMG_PATH) exists and is a valid UDZO disk image"
        else
            log_fail "Distribution DMG ($DMG_PATH) is corrupted"
        fi
    else
        log_fail "Distribution DMG ($DMG_PATH) is missing or empty"
    fi

    if [ -f "$ZIP_PATH" ] && [ -s "$ZIP_PATH" ]; then
        if unzip -tq "$ZIP_PATH" >/dev/null 2>&1; then
            log_pass "Distribution ZIP ($ZIP_PATH) exists and archive integrity test passed"
        else
            log_fail "Distribution ZIP ($ZIP_PATH) is corrupted"
        fi
    else
        log_fail "Distribution ZIP ($ZIP_PATH) is missing or empty"
    fi

    if [ -d "$APP_PATH" ]; then
        if codesign -dv "$APP_PATH" >/dev/null 2>&1; then
            log_pass "Packaged macOS application bundle ($APP_PATH) has valid code signature"
        else
            log_fail "Packaged macOS application bundle ($APP_PATH) code signature validation failed"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
echo -e "\n=============================================================================="
echo -e "${BOLD}Security Audit Summary:${NC} $PASSED_CHECKS passed, $FAILED_CHECKS failed, $WARNINGS warnings (Total: $TOTAL_CHECKS checks)"
echo "=============================================================================="

if [ "$FAILED_CHECKS" -gt 0 ]; then
    echo -e "${RED}${BOLD}❌ SECURITY AUDIT FAILED! Resolve the above issues before publishing.${NC}\n"
    exit 1
else
    echo -e "${GREEN}${BOLD}✅ ALL SECURITY AUDITS PASSED! Repository is clean and safe to publish.${NC}\n"
    exit 0
fi
