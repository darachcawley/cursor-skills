# Testing & Quality Checks for Cursor Skills

Automated tests and checks to prevent breaking changes before committing.

## Quick Start

### Run All Tests
```bash
.cursor/skills/daily-digest/tests/run-all-tests.sh
```

### Install Pre-commit Hook
```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "Running daily-digest tests..."
if .cursor/skills/daily-digest/tests/run-all-tests.sh; then
  exit 0
else
  echo "❌ Tests failed - commit blocked"
  echo "Fix errors or use 'git commit --no-verify' to skip"
  exit 1
fi
EOF

chmod +x .git/hooks/pre-commit
```

---

## Test Suite Overview

The test suite includes **5 automated checks** that run before each commit:

### ✅ 1. Internal Link Validation
- Checks all markdown links in SKILL.md and README.md
- Ensures referenced files exist
- Prevents broken documentation

### ✅ 2. Digest JSON Schema Validation
- Validates digest structure against expected schema
- Checks required fields are present
- Validates data formats (dates, channel IDs, urgency values)
- Ensures thread links contain proper channel IDs

### ✅ 3. Config JSON Validation
- Validates all `.json` config files are valid JSON
- Catches syntax errors before commit
- Checks: `slack_channels_config.json`, `feature_watchlist.json`, etc.

### ✅ 4. Sensitive Data Detection
- Scans staged files for tokens and credentials
- Prevents accidental commit of:
  - Slack tokens (`xoxc-`, `xoxd-`)
  - Jira tokens (`ATATT`)
  - Passwords
- Excludes `.example.` files and test documentation

### ✅ 5. HTML Syntax Check
- Validates viewer HTML is well-formed
- Checks for required HTML structure tags
- Ensures `viewer/index.html` is valid

---

## Test Results

```
🧪 Running Daily Digest Tests
==============================

1️⃣  Checking internal links...
   ✅ PASSED

2️⃣  Validating digest JSON schemas...
   ✅ PASSED

3️⃣  Validating config JSON files...
   ✅ PASSED

4️⃣  Checking for sensitive data...
   ✅ PASSED

5️⃣  Checking HTML syntax...
   ✅ PASSED

==============================
📊 Test Summary
==============================
Total:  5
Passed: 5
Failed: 0

✅ All tests passed!
```

---

## Individual Test Commands

Run specific tests:

```bash
# Check internal links
.cursor/skills/daily-digest/tests/check-links.sh

# Validate a digest file
node .cursor/skills/daily-digest/tests/validate-digest.js \
  .cursor/skills/daily-digest/digests/2026-04-15.json

# Open viewer tests in browser
open .cursor/skills/daily-digest/tests/test-viewer.html
```

---

## Manual Smoke Tests

Before major changes, manually verify:

### 1. Digest Generation
```bash
# In Cursor, ask Claude:
"Give me a daily digest for yesterday"
```
**Check:**
- ✅ All configured channels appear
- ✅ DMs are fetched (if `include_dms: true`)
- ✅ Self-DM appears
- ✅ Jira mentions included
- ✅ Executive summary generated
- ✅ No errors in console

### 2. Viewer Functionality
```bash
# Serve the viewer
npx serve .cursor/skills/daily-digest

# Open http://localhost:3000/viewer/
```
**Test:**
- ✅ Navigate between dates
- ✅ Filter by urgency (today, this week, later)
- ✅ Filter by owner (me, others, team)
- ✅ Mark actions as done
- ✅ View feature tracker panel
- ✅ Check close circle view
- ✅ Click Slack/Jira links (open in new tabs)
- ✅ View person activity reports (if any)

### 3. Config Changes
```bash
# Edit config
vim .cursor/skills/daily-digest/slack_channels_config.json

# Add a channel, then regenerate digest
```
**Verify:**
- ✅ New channel appears in digest
- ✅ Old channels still work
- ✅ No breaking changes

---

## What Gets Checked Before Commit?

| Check | What It Prevents |
|-------|------------------|
| **Link validation** | Broken documentation references |
| **Schema validation** | Malformed digest JSON breaking viewer |
| **Config validation** | Invalid JSON syntax errors |
| **Sensitive data** | Accidental token/credential commits |
| **HTML syntax** | Broken viewer due to HTML errors |

---

## CI/CD Integration (Future)

### GitHub Actions

Create `.github/workflows/test-daily-digest.yml`:

```yaml
name: Daily Digest Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - name: Install jq
        run: sudo apt-get install -y jq
      - name: Run tests
        run: .cursor/skills/daily-digest/tests/run-all-tests.sh
```

---

## Bypassing Tests

If you need to commit without running tests (not recommended):

```bash
git commit --no-verify
```

**When to use:**
- Emergency hotfixes
- Work-in-progress commits on a branch
- When tests are failing due to test bugs (not your code)

---

## Extending the Test Suite

### Add a New Check

1. Create a new test script:
```bash
vim .cursor/skills/daily-digest/tests/my-new-test.sh
chmod +x .cursor/skills/daily-digest/tests/my-new-test.sh
```

2. Add to `run-all-tests.sh`:
```bash
echo "N️⃣  Running my new test..."
if bash "$SCRIPT_DIR/my-new-test.sh"; then
  echo "   ✅ PASSED"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo "   ❌ FAILED"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
```

### Add Digest Schema Validation

Edit `validate-digest.js`:
```javascript
// Add required field
REQUIRED_FIELDS.thread.push('new_required_field');

// Add custom validation
if (thread.custom_field && !isValid(thread.custom_field)) {
  errors.push('Invalid custom_field format');
}
```

---

## Dependencies

Tests require:
- **Node.js** (for JSON validation)
- **jq** (for JSON parsing)
- **Bash** (for test runner)

Install:
```bash
brew install node jq
```

---

## Test Documentation

Detailed test documentation: `.cursor/skills/daily-digest/tests/README.md`

---

## Benefits

✅ **Catch errors early** - Before they reach GitHub  
✅ **Prevent breaking changes** - Schema validation ensures compatibility  
✅ **Security** - No accidental token commits  
✅ **Documentation** - Links stay valid  
✅ **Confidence** - Know your changes work before pushing  
✅ **Fast feedback** - Tests run in ~2 seconds  

---

## Summary

With the test suite in place:
1. **Before commit** - All tests run automatically (if hook installed)
2. **During development** - Run manually to check your work
3. **After changes** - Smoke test the viewer and digest generation
4. **Before major updates** - Run full manual test checklist

**Zero breaking changes shipped to main!** 🎯
