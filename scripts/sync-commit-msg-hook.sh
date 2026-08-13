#!/usr/bin/env bash
set -euo pipefail

# Installs/refreshes this project's .git/hooks/commit-msg from the pinned policy clone's own
# templates/hooks/commit-msg, so the hook stays current without a developer having to remember to
# re-copy it by hand. This script is meant to be copied into a code repo's own scripts/ folder and
# called as one step inside that project's own ./dev bootstrap, so it runs on every fresh clone and
# every re-pin, not just once.
#
# Guards against a non-conformant commit-msg hook (missing entirely, or installed but stale)
# by making the sync part of every ./dev bootstrap run instead of a one-time manual step.
#
# Scoped to the one hook that exists today (templates/hooks/commit-msg) — not a generic
# templates/hooks/* installer. Generalize only if/when a second hook is ever added.
#
# Resolution logic: this script is copied into <code-repo>/scripts/, so the code repo is exactly
# one level up from this script's own resolved directory, and the umbrella directory is that code
# repo's own parent, confirmed by requiring a sibling policy-clone git checkout to exist there.
script_path="${BASH_SOURCE[0]}"
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"
CODE_REPO_DIR="$(cd -- "$script_dir/.." && pwd)"
UMBRELLA_DIR="$(dirname -- "$CODE_REPO_DIR")"

if [ ! -d "$UMBRELLA_DIR/sw_dev_handbook" ] || [ ! -d "$UMBRELLA_DIR/sw_dev_handbook/.git" ]; then
  echo "sync-commit-msg-hook: could not locate the pinned policy clone — expected a sibling git" >&2
  echo "clone one level above the code repo ($UMBRELLA_DIR), given this script's own resolved" >&2
  echo "location at $script_dir." >&2
  exit 1
fi

reference_file="$UMBRELLA_DIR/sw_dev_handbook/templates/hooks/commit-msg"
hook_file="$CODE_REPO_DIR/.git/hooks/commit-msg"
divergence_file="${hook_file}.divergence-reason"

if [ ! -f "$reference_file" ]; then
  echo "sync-commit-msg-hook: reference hook not found at $reference_file — cannot sync" >&2
  exit 1
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [ ! -f "$hook_file" ]; then
  cp "$reference_file" "$hook_file"
  chmod +x "$hook_file"
  echo "sync-commit-msg-hook: installed .git/hooks/commit-msg"
  exit 0
fi

reference_hash="$(sha256_of "$reference_file")"
hook_hash="$(sha256_of "$hook_file")"

if [ "$reference_hash" = "$hook_hash" ]; then
  exit 0
fi

if [ -f "$divergence_file" ]; then
  exit 0
fi

echo "sync-commit-msg-hook: WARNING — installed .git/hooks/commit-msg diverges from" >&2
echo "templates/hooks/commit-msg and no $divergence_file note documents why. Leaving it" >&2
echo "untouched — if this divergence is intentional, document it by creating that file; if not," >&2
echo "re-run after removing the local file to pick up the current template." >&2
