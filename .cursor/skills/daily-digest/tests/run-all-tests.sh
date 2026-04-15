#!/bin/bash
# Run all pre-commit tests for daily-digest skill

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
DIGEST_DIR="$SKILL_DIR/digests"

echo "🧪 Running Daily Digest Tests"
echo "=============================="
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test 1: Check internal links
echo "1️⃣  Checking internal links..."
if bash "$SCRIPT_DIR/check-links.sh"; then
  echo "   ✅ PASSED"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo "   ❌ FAILED"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Test 2: Validate digest JSON files (sample)
echo "2️⃣  Validating digest JSON schemas..."
if [ -d "$DIGEST_DIR" ]; then
  SAMPLE_DIGESTS=$(find "$DIGEST_DIR" -name "*.json" -not -path "*/.*" | sort -r | head -3)
  if [ -z "$SAMPLE_DIGESTS" ]; then
    echo "   ⚠️  No digest files found to validate"
  else
    DIGEST_ERRORS=0
    for digest in $SAMPLE_DIGESTS; do
      filename=$(basename "$digest")
      if node "$SCRIPT_DIR/validate-digest.js" "$digest" > /dev/null 2>&1; then
        echo "   ✅ $filename"
      else
        echo "   ❌ $filename"
        DIGEST_ERRORS=$((DIGEST_ERRORS + 1))
      fi
    done

    if [ $DIGEST_ERRORS -eq 0 ]; then
      echo "   ✅ PASSED"
      PASSED_TESTS=$((PASSED_TESTS + 1))
    else
      echo "   ❌ FAILED ($DIGEST_ERRORS digest(s) invalid)"
      FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  fi
else
  echo "   ⚠️  Digest directory not found"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Test 3: Validate config JSON files
echo "3️⃣  Validating config JSON files..."
CONFIG_ERRORS=0

for config in "$SKILL_DIR"/*.json; do
  if [ -f "$config" ]; then
    filename=$(basename "$config")
    if jq empty "$config" > /dev/null 2>&1; then
      echo "   ✅ $filename"
    else
      echo "   ❌ $filename (invalid JSON)"
      CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
    fi
  fi
done

if [ $CONFIG_ERRORS -eq 0 ]; then
  echo "   ✅ PASSED"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo "   ❌ FAILED ($CONFIG_ERRORS config(s) invalid)"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Test 4: Check for sensitive data
echo "4️⃣  Checking for sensitive data..."
SENSITIVE_PATTERNS=(
  "xoxc-"
  "xoxd-"
  "ATATT"
  "password"
)

SENSITIVE_ERRORS=0
STAGED_FILES=$(git diff --cached --name-only)

if [ -z "$STAGED_FILES" ]; then
  echo "   ⚠️  No staged files to check"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    # Check staged files only, exclude config examples and documentation
    if echo "$STAGED_FILES" | xargs grep -l "$pattern" 2>/dev/null | grep -v "\.example\." | grep -v "tests/README\.md"; then
      echo "   ❌ Found potentially sensitive data: $pattern"
      SENSITIVE_ERRORS=$((SENSITIVE_ERRORS + 1))
    fi
  done

  if [ $SENSITIVE_ERRORS -eq 0 ]; then
    echo "   ✅ PASSED (no sensitive data in staged files)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo "   ❌ FAILED (found $SENSITIVE_ERRORS pattern(s))"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
fi

if [ $SENSITIVE_ERRORS -eq 0 ]; then
  echo "   ✅ PASSED (no sensitive data in staged files)"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo "   ❌ FAILED (found $SENSITIVE_ERRORS pattern(s))"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Test 5: Check HTML validity (basic)
echo "5️⃣  Checking HTML syntax..."
HTML_FILE="$SKILL_DIR/viewer/index.html"
if [ -f "$HTML_FILE" ]; then
  # Basic syntax check - ensure it has basic HTML structure
  if grep -q "<html" "$HTML_FILE" && grep -q "</html>" "$HTML_FILE" && \
     grep -q "<head" "$HTML_FILE" && grep -q "</head>" "$HTML_FILE" && \
     grep -q "<body" "$HTML_FILE" && grep -q "</body>" "$HTML_FILE"; then
    echo "   ✅ PASSED"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo "   ❌ FAILED (missing basic HTML structure)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
else
  echo "   ⚠️  index.html not found"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Summary
echo "=============================="
echo "📊 Test Summary"
echo "=============================="
echo "Total:  $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
