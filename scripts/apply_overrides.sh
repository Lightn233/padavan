#!/usr/bin/env bash
# scripts/apply_overrides.sh
# Usage: ./scripts/apply_overrides.sh <PRODUCT>
set -eu
product="$1"
root="$(pwd)"
trunk="$root/trunk"
config="$root/.config"

if [ ! -f "$config" ]; then
  echo "Error: $config not found. Copy template to .config first."
  exit 1
fi

# Override files (product-specific then common)
override_dir="$trunk/build"
common_override="$override_dir/common.override"

# Append overrides if present
if [ -f "$common_override" ]; then
  echo "Applying common overrides from $common_override"
  cat "$common_override" >> "$config"
fi


# Normalize .config: remove duplicate CONFIG_* keys, keep last occurrence.
# Implementation: reverse file, emit the first seen key occurrence, then reverse back.
# Requires 'tac' (GNU coreutils). If tac missing, use awk fallback.
tmp="$(mktemp)"
if command -v tac >/dev/null 2>&1; then
  tac "$config" | awk '
    /^CONFIG_[A-Za-z0-9_]+=|^# CONFIG_[A-Za-z0-9_]+ is not set/ {
      # extract config key (handle both "CONFIG_X=..." and "# CONFIG_X is not set")
      line=$0
      if (match(line,/^# CONFIG_([A-Za-z0-9_]+) is not set/)) {
        key="CONFIG_" substr(line, RSTART+2, RLENGTH-12)
      } else if (match(line,/^CONFIG_[A-Za-z0-9_]+=/)) {
        split(line, a, "=")
        key=a[1]
      } else {
        key=""
      }
      if (key != "" && !seen[key]++) {
        print line
      } else if (key == "") {
        # non-CONFIG line, keep once (preserve order heuristically)
        if (!seen_nonline[line]++) print line
      }
      next
    }
    { # other lines (comments/blank)
      if (!seen_nonline[$0]++) print $0
    }
  ' | tac > "$tmp"
else
  # fallback pure awk for systems without tac
  awk '
  { lines[NR]=$0 }
  END {
    for (i=NR;i>=1;i--) {
      line=lines[i]
      if (match(line,/^# CONFIG_([A-Za-z0-9_]+) is not set/)) {
        key="CONFIG_" substr(line, RSTART+2, RLENGTH-12)
        if (!seen[key]++) out[++o]=line
      } else if (match(line,/^CONFIG_[A-Za-z0-9_]+=/)) {
        split(line,a,"=")
        key=a[1]
        if (!seen[key]++) out[++o]=line
      } else {
        if (!seen_nonline[line]++) out[++o]=line
      }
    }
    for (i=o;i>=1;i--) print out[i]
  }
  ' "$config" > "$tmp"
fi

# Replace original .config
mv "$tmp" "$config"
echo "Overrides applied and .config normalized."
