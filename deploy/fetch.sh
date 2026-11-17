#!/usr/bin/env bash
#
# Keeps the F-Droid repository fdroid.synaelle.com serves: the archive on
# this repository's `repo` release, checked against the checksum GitHub
# gives for it, unpacked beside the one in place, then `current` points at
# it. A failed run changes nothing, and a run with nothing new downloads
# nothing.
#
#   fetch.sh <folder>
set -euo pipefail
umask 022

dir=${1:?usage: fetch.sh <folder>}
api=https://api.github.com/repos/Synaelle/fdroid/releases/tags/repo

mkdir -p "$dir"
work=$(mktemp -d "$dir/.fetch.XXXXXX")
trap 'rm -rf "$work"' EXIT

curl -fsS --max-time 30 --retry 2 -H 'accept: application/vnd.github+json' "$api" > "$work/release.json"
IFS=$'\t' read -r url digest < <(jq -r '.assets[] | select(.name == "fdroid-repo.tar.gz")
  | [.browser_download_url, (.digest // "")] | @tsv' "$work/release.json")
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "the archive has no checksum on GitHub" >&2; exit 1; }
sum=${digest#sha256:}
if [[ $(readlink "$dir/current" 2>/dev/null) == "$sum" && -e $dir/$sum/.complete ]]; then
  echo "repository already in place"
  exit 0
fi

echo "downloading the repository"
curl -fsSL --max-time 900 --retry 3 -o "$work/repo.tar.gz" "$url"
echo "$sum  $work/repo.tar.gz" | sha256sum -c --quiet
mkdir "$work/$sum"
tar -xzf "$work/repo.tar.gz" -C "$work/$sum" --no-same-owner --no-same-permissions
test -f "$work/$sum/repo/index-v2.json" && test -f "$work/$sum/repo/entry.jar"
find "$work/$sum" -type d -exec chmod 755 {} + && find "$work/$sum" -type f -exec chmod 644 {} +
touch "$work/$sum/.complete"
rm -rf "${dir:?}/$sum"
mv "$work/$sum" "$dir/$sum"
# the link swapped in one move, the old copy goes after
ln -sfn "$sum" "$dir/.current"
mv -T "$dir/.current" "$dir/current"
for old in "$dir"/*/; do
  name=$(basename "$old")
  [[ $name != "$sum" && $name =~ ^[0-9a-f]{64}$ ]] && rm -rf "$old"
done
echo "repository $sum in place"
