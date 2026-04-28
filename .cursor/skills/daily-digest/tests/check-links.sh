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
    # Extract markdown links: [text](url)
    while [[ "$line" =~ \[([^\]]+)\]\(([^\)]+)\) ]]; do
      link="${BASH_REMATCH[2]}"
      # Remove the matched part to find next link
      line="${line#*\[*\](*\)}"

      # Skip external URLs, anchors, and anything with backticks or special chars
      if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^# ]] || [[ "$link" =~ \` ]] || [[ "$link" =~ \* ]]; then
        continue
      fi

      # Strip anchor fragment if present
      file_path="${link%%#*}"

      # Check if file exists
      if [[ "$file_path" =~ ^/ ]]; then
        # Absolute path
        if [[ ! -e "$file_path" ]]; then
          echo "  ❌ Broken link: $link"
          ERRORS=$((ERRORS + 1))
        fi
      else
        # Relative path
        target="$SKILL_DIR/$file_path"
        if [[ ! -e "$target" ]]; then
          echo "  ❌ Broken link: $link"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done
  done < "$SKILL_DIR/SKILL.md"
fi

# Check README.md references
echo ""
echo "Checking README.md..."
if [ -f "$SKILL_DIR/README.md" ]; then
  while IFS= read -r line; do
    # Extract markdown links: [text](url)
    while [[ "$line" =~ \[([^\]]+)\]\(([^\)]+)\) ]]; do
      link="${BASH_REMATCH[2]}"
      # Remove the matched part to find next link
      line="${line#*\[*\](*\)}"

      # Skip external URLs, anchors, and anything with backticks or special chars
      if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^# ]] || [[ "$link" =~ \` ]] || [[ "$link" =~ \* ]]; then
        continue
      fi

      # Strip anchor fragment if present
      file_path="${link%%#*}"

      # Check if file exists
      if [[ "$file_path" =~ ^/ ]]; then
        # Absolute path
        if [[ ! -e "$file_path" ]]; then
          echo "  ❌ Broken link: $link"
          ERRORS=$((ERRORS + 1))
        fi
      else
        # Relative path
        target="$SKILL_DIR/$file_path"
        if [[ ! -e "$target" ]]; then
          echo "  ❌ Broken link: $link"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    done
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
