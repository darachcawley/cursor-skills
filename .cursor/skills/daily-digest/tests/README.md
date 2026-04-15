# Daily Digest Tests

Automated tests to ensure digest generation and viewer functionality remain stable.

## Quick Start

Run all tests:
```bash
./tests/run-all-tests.sh
```

Run individual tests:
```bash
# Check internal markdown links
./tests/check-links.sh

# Validate digest JSON schema
node tests/validate-digest.js digests/2026-04-15.json

# Open viewer tests in browser
open tests/test-viewer.html
```

---

## Test Suite

### 1. **Link Validation** (`check-links.sh`)
- Checks all internal links in SKILL.md and README.md
- Ensures referenced files exist
- Catches broken documentation references

**Run:**
```bash
./tests/check-links.sh
```

---

### 2. **Digest Schema Validation** (`validate-digest.js`)
- Validates digest JSON structure
- Ensures required fields are present
- Validates channel IDs, thread links, urgency values
- Checks date formats

**Run:**
```bash
node tests/validate-digest.js digests/YYYY-MM-DD.json
```

**Checks:**
- ✅ All required root fields exist
- ✅ Date format is YYYY-MM-DD
- ✅ Channel IDs start with C or D
- ✅ Thread links contain channel IDs
- ✅ Urgency values are valid (today/this_week/later)
- ✅ All action fields are present

---

### 3. **Config JSON Validation**
- Validates all .json config files are valid JSON
- Catches syntax errors before commit

**Included in:** `run-all-tests.sh`

---

### 4. **Sensitive Data Check**
- Scans staged files for tokens, passwords, emails
- Prevents accidental commit of credentials

**Patterns checked:**
- `xoxc-` / `xoxd-` (Slack tokens)
- `ATATT` (Jira tokens)
- `password`
- Email addresses

**Included in:** `run-all-tests.sh`

---

### 5. **HTML Syntax Check**
- Basic validation that viewer HTML is well-formed
- Checks for required HTML structure tags

**Included in:** `run-all-tests.sh`

---

### 6. **Viewer Functional Tests** (`test-viewer.html`)
- Tests JavaScript functions in the viewer
- Validates date formatting, action keys, linkify
- Mock digest validation

**Run:**
```bash
open tests/test-viewer.html
```

---

## Pre-commit Hook

Install the pre-commit hook to run tests automatically:

```bash
# Create hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Run daily-digest tests before commit

echo "Running daily-digest tests..."
if .cursor/skills/daily-digest/tests/run-all-tests.sh; then
  echo "✅ Tests passed - proceeding with commit"
  exit 0
else
  echo "❌ Tests failed - commit blocked"
  echo "Fix errors or use 'git commit --no-verify' to skip"
  exit 1
fi
EOF

# Make executable
chmod +x .git/hooks/pre-commit
```

To skip tests for a specific commit:
```bash
git commit --no-verify
```

---

## GitHub Actions CI

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
      - name: Run tests
        run: |
          cd .cursor/skills/daily-digest
          ./tests/run-all-tests.sh
```

---

## Manual Smoke Tests

Before major changes, manually verify:

### Digest Generation
1. Generate a digest for a recent date
2. Verify all configured channels appear
3. Check DM fetching works (if enabled)
4. Verify Jira mentions are included
5. Check person search (if used)

### Viewer
1. Open viewer: `npx serve .cursor/skills/daily-digest` → `/viewer/`
2. Navigate between dates
3. Test filters (urgency, owner, channel)
4. Mark actions as done
5. Check feature tracker panel
6. Test close circle view
7. Verify Slack/Jira links open correctly

### Config Changes
1. Add a new channel to `slack_channels_config.json`
2. Add a feature to `feature_watchlist.json`
3. Generate digest and verify changes appear

---

## Extending Tests

### Add New Digest Validation
Edit `validate-digest.js`:
```javascript
// Add new field requirement
REQUIRED_FIELDS.thread.push('new_field');

// Add custom validation
if (thread.custom_field && !isValid(thread.custom_field)) {
  errors.push('Invalid custom_field');
}
```

### Add New Test Script
Create `tests/my-test.sh`:
```bash
#!/bin/bash
# Description of what this tests

# Your test logic here
if [ condition ]; then
  echo "✅ Test passed"
  exit 0
else
  echo "❌ Test failed"
  exit 1
fi
```

Add to `run-all-tests.sh`:
```bash
echo "N️⃣  Running my test..."
if bash "$SCRIPT_DIR/my-test.sh"; then
  echo "   ✅ PASSED"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo "   ❌ FAILED"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
```

---

## Troubleshooting

### `jq: command not found`
Install jq:
```bash
brew install jq
```

### `node: command not found`
Install Node.js:
```bash
brew install node
```

### Tests pass locally but fail in CI
- Check file paths are relative
- Ensure all dependencies are installed in CI
- Verify environment variables aren't required
