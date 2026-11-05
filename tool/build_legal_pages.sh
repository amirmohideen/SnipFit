#!/usr/bin/env bash
# Renders the legal Markdown bundled in the app (assets/legal/*.md) into the
# hosted pages (hosting/public/legal/*.html), so both always say the same.
set -euo pipefail
cd "$(dirname "$0")/.."
for doc in terms privacy biometric-notice ai-disclosure; do
  title=$(grep -m1 '^# ' "assets/legal/$doc.md" | sed 's/^# //')
  pandoc "assets/legal/$doc.md" -f gfm -t html5 --template hosting/template/page.html \
    --metadata title="$title" -o "hosting/public/legal/$doc.html"
done
echo "Legal pages rendered to hosting/public/legal/"
