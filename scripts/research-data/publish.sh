#!/usr/bin/env bash
# usage: publish.sh <src dir> <dest subdir on data/research-inputs> <message>
set -e
src="$(realpath "$1")"; sub="$2"; msg="$3"
[ -d "$src" ] || { echo "nothing to publish"; exit 0; }
repo_url="https://x-access-token:${GITHUB_TOKEN:-$GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
for attempt in 1 2 3 4 5 6; do
  work="${RUNNER_TEMP:-/tmp}/pub-$sub"; rm -rf "$work"
  if git ls-remote --heads "$repo_url" data/research-inputs | grep -q data/research-inputs; then
    git clone -q --depth 1 --single-branch --branch data/research-inputs "$repo_url" "$work"
  else
    git init -q -b data/research-inputs "$work"; git -C "$work" remote add origin "$repo_url"
  fi
  rm -rf "$work/$sub"; mkdir -p "$work/$sub"; cp -r "$src"/. "$work/$sub/"
  cd "$work"
  git config user.name "github-actions[bot]"; git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add -A
  git commit -qm "$msg" || { echo "no change"; exit 0; }
  if git push -q origin data/research-inputs; then echo "published $sub"; exit 0; fi
  echo "push raced, retrying ($attempt)"; sleep $((attempt * 5)); cd /
done
exit 1
