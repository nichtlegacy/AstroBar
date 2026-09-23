#!/usr/bin/env bash
# Assemble the landing page into _site/ for GitHub Pages.
#
# Everything the page serves already lives under site/ in its final form — the
# web copies of the screenshots come from scripts/build_images.py, the social
# preview from scripts/build_og.py. This step only copies and fills in the
# version, so the Pages runner needs no image tooling at all.
#
#   scripts/build_site.sh            # build _site/
#   scripts/build_site.sh --serve    # build, then serve on 0.0.0.0:8000
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/_site"

# shellcheck source=/dev/null
VERSION="$(grep '^MARKETING_VERSION=' "$ROOT/version.env" | cut -d= -f2 | tr -d '[:space:]')"
[ -n "$VERSION" ] || { echo "no MARKETING_VERSION in version.env" >&2; exit 1; }

# Full W3C datetime: Google reads <lastmod> for scheduling, date-only is coarser.
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

rm -rf "$OUT"
mkdir -p "$OUT"

cp "$ROOT"/site/*.css "$ROOT"/site/*.js "$ROOT"/site/*.svg "$ROOT"/site/*.png \
   "$ROOT"/site/*.ico "$OUT/"
cp "$ROOT/site/CNAME" "$ROOT/site/robots.txt" "$OUT/"
cp -R "$ROOT/site/screenshots" "$OUT/screenshots"
cp -R "$ROOT/site/fonts" "$OUT/fonts"

# index.html carries both placeholders: the version in the copy and in the
# structured data, and the build time as the page's dateModified.
sed -e "s/__VERSION__/$VERSION/g" -e "s|__BUILD_DATE__|$BUILD_DATE|g" \
    "$ROOT/site/index.html" > "$OUT/index.html"
sed "s/__VERSION__/$VERSION/g" "$ROOT/site/404.html" > "$OUT/404.html"
sed "s|__BUILD_DATE__|$BUILD_DATE|g" "$ROOT/site/sitemap.xml" > "$OUT/sitemap.xml"

# Any placeholder left behind would ship to production, so fail loudly instead.
if grep -rq "__VERSION__\|__BUILD_DATE__" "$OUT"; then
  echo "unsubstituted placeholder left in _site" >&2
  exit 1
fi

# A file referenced but never copied would 404 in production, where nobody looks.
missing=0
while read -r asset; do
  [ -z "$asset" ] && continue
  [ -f "$OUT/$asset" ] || { echo "referenced but missing: $asset" >&2; missing=1; }
done < <(grep -ho '\(src\|href\)="[^":#]*"' "$OUT/index.html" "$OUT/404.html" \
         | sed 's/.*="//; s/"$//; s|^/||' | sort -u)
[ "$missing" -eq 0 ] || exit 1

echo "built _site for version $VERSION ($(du -sh "$OUT" | cut -f1))"

if [ "${1:-}" = "--serve" ]; then
  port="${2:-8000}"
  echo "serving on http://0.0.0.0:$port"
  cd "$OUT"
  exec python3 -m http.server "$port" --bind 0.0.0.0
fi
