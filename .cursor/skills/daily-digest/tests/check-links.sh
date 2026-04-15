#!/bin/bash
# Check for broken internal links in markdown files

set -e

SKILL_DIR=".cursor/skills/daily-digest"
ERRORS=0

echo "🔍 Checking internal links in markdown files..."

# Check SKILL.md references
echo ""
echo "Checking SKILL.md..."
if [ -f "$SKILL_DIR/SKILL.md" ]; then
  while IFS= read -r line; do
    if [[ "$line" =~ \[.*\]\((.*)\) ]]; then
      link="${BASH_REMATCH[1]}"
      # Skip external URLs and anchors
      if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^# ]]; then
        continue
      fi
      # Check if file exists
      if [[ "$link" =~ ^/ ]]; then
        # Absolute path
        if [[ ! -e "$link" ]]; then
          echo "  ❌ Broken link: $link"
          ERRORS=$((ERRORS + 1))
        fi
      else
        # Relative path
        target="$SKILL_DIR/$link"
        if [[ ! -e "$target" ]]; then
          echo "  ❌ Broken link: $link (resolved to $target)"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    fi
  done < "$SKILL_DIR/SKILL.md"
fi

# Check README.md references
echo ""
echo "Checking README.md..."
if [ -f "$SKILL_DIR/README.md" ]; then
  while IFS= read -r line; do
    if [[ "$line" =~ \[.*\]\((.*)\) ]]; then
      link="${BASH_REMATCH[1]}"
      if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^# ]]; then
        continue
      fi
      if [[ "$link" =~ ^/ ]]; then
        if [[ ! -e "$link" ]]; then
          echo "  ❌ Broken link: $link"
          ERRORS=$((ERRORS + 1))
        fi
      else
        target="$SKILL_DIR/$link"
        if [[ ! -e "$target" ]]; then
          echo "  ❌ Broken link: $link (resolved to $target)"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    fi
  done < "$SKILL_DIR/README.md"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "✅ All internal links are valid"
  exit 0
else
  echo "❌ Found $ERRORS broken link(s)"
  exit 1
fi
