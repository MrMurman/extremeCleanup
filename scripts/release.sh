#!/bin/sh
# Builds, signs and zips a release; with GITHUB_TOKEN set, attaches the zip to a new draft GitHub release.
# Releases must carry the stable signing identity, or every update asks for Screen Recording again.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
repo="MrMurman/extremeCleanup"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
app="build/ExtremeCleanup.app"
zip="build/ExtremeCleanup-$version.zip"

security find-identity -v -p codesigning | grep -q '"boroda studio"' || { echo "signing identity missing" >&2; exit 1; }
scripts/bundle.sh >/dev/null
codesign --verify --strict "$app"
rm -f "$zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"
echo "$root/$zip"

[ -n "$GITHUB_TOKEN" ] || exit 0
api() { curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }
release=$(api -X POST "https://api.github.com/repos/$repo/releases" -d @- <<JSON
{"tag_name": "v$version", "target_commitish": "main", "name": "Extreme Cleanup $version", "draft": true,
 "body": "Download **ExtremeCleanup-$version.zip**, unzip it and move the app to Applications. See the README for the first launch."}
JSON
)
id=$(printf '%s' "$release" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])')
api -X POST -H "Content-Type: application/zip" --data-binary @"$zip" \
    "https://uploads.github.com/repos/$repo/releases/$id/assets?name=$(basename "$zip")" >/dev/null
echo "draft release $id"
