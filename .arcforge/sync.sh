#!/usr/bin/env bash
# Sync the Arc Forge rehearsal fork with upstream OpenClaw Enterprise.
#
#   fork main           := upstream main (fast-forward only; never our commits)
#   master (rehearsal)  := upstream main + the Arc Forge infrastructure commit
#
# It also disables every workflow in the fork that is not ours and cancels any
# run such a workflow started, before and after the push. A new upstream
# workflow arrives enabled, so never update the fork any other way (not with
# GitHub's "Sync fork" button either).
#
# Usage: .arcforge/sync.sh [--dry-run]
# Run it from any clone of openclaw-enterprise. It does not touch your checkout.
# Needs git, gh (admin on the fork) and jq.
set -euo pipefail

FORK=arcforgelabs/openclaw-enterprise
UPSTREAM=openclaw/openclaw-enterprise
BRANCH=master
OURS='^(\.arcforge/|\.github/workflows/arcforge-)'
# Git URLs can point elsewhere for a local rehearsal of this script.
FORK_URL=${FORK_URL:-https://github.com/$FORK.git}
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/$UPSTREAM.git}
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

die() { printf 'sync: %s\n' "$*" >&2; exit 1; }
log() { printf 'sync: %s\n' "$*" >&2; }
run() { if (( DRY_RUN )); then log "dry run, skipped: $*"; else "$@"; fi; }

git rev-parse --git-dir >/dev/null 2>&1 || die "run inside a clone of $UPSTREAM"

guard_workflows() {
  local id path
  gh api "repos/$FORK/actions/workflows?per_page=100" --jq '.workflows[]
      | select(.state == "active" and (.path | startswith(".github/workflows/")))
      | select(.path | test("^\\.github/workflows/arcforge-") | not)
      | "\(.id) \(.path)"' |
    while read -r id path; do
      log "disabling $path"
      run gh api -X PUT "repos/$FORK/actions/workflows/$id/disable" >/dev/null
    done
  for status in queued in_progress; do
    gh api "repos/$FORK/actions/runs?status=$status&per_page=100" --jq '.workflow_runs[]
        | select(.path | startswith(".github/workflows/"))
        | select(.path | test("^\\.github/workflows/arcforge-") | not)
        | "\(.id) \(.path)"' |
      while read -r id path; do
        log "cancelling run $id ($path)"
        run gh api -X POST "repos/$FORK/actions/runs/$id/cancel" >/dev/null || true
      done
  done
}

git fetch -q "$UPSTREAM_URL" "+refs/heads/main:refs/arcforge-sync/upstream-main"
git fetch -q "$FORK_URL" \
  "+refs/heads/main:refs/arcforge-sync/fork-main" \
  "+refs/heads/$BRANCH:refs/arcforge-sync/rehearsal"
up=$(git rev-parse refs/arcforge-sync/upstream-main)
fork_main=$(git rev-parse refs/arcforge-sync/fork-main)
old=$(git rev-parse refs/arcforge-sync/rehearsal)

git merge-base --is-ancestor "$fork_main" "$up" ||
  die "fork main has commits that upstream lacks; it must stay a mirror (git log $up..$fork_main)"

base=$(git merge-base "$old" "$up")
outside=$(git diff --name-only "$base" "$old" | grep -Ev "$OURS" || true)
[[ -z "$outside" ]] || die "$BRANCH changes files outside the Arc Forge paths: $outside"
[[ -z "$(git rev-list --merges "$base..$old")" ]] || die "$BRANCH holds a merge commit; rebuild it by hand"

if [[ "$base" == "$up" ]]; then
  new=$old
  log "$BRANCH already sits on upstream main ${up:0:12}"
else
  tmp=$(mktemp -d)
  trap 'git worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
  git worktree add -q --detach "$tmp/wt" "$up"
  git -C "$tmp/wt" cherry-pick "$base..$old" >/dev/null ||
    die "the infrastructure commit conflicts with upstream; resolve it in a clone by hand"
  new=$(git -C "$tmp/wt" rev-parse HEAD)
  log "rebased $(git rev-list --count "$base..$old") infrastructure commit(s) onto upstream ${up:0:12}"
fi

outside=$(git diff --name-only "$up" "$new" | grep -Ev "$OURS" || true)
[[ -z "$outside" ]] || die "rebased $BRANCH changes files outside the Arc Forge paths: $outside"

guard_workflows
if [[ "$fork_main" != "$up" ]]; then
  log "fast-forwarding fork main ${fork_main:0:12} -> ${up:0:12}"
  run git push -q "$FORK_URL" "$up:refs/heads/main"
fi
if [[ "$new" != "$old" ]]; then
  log "updating $BRANCH ${old:0:12} -> ${new:0:12}"
  run git push -q --force-with-lease="refs/heads/$BRANCH:$old" \
    "$FORK_URL" "$new:refs/heads/$BRANCH"
fi
# GitHub registers a new workflow file a few seconds after the push.
(( DRY_RUN )) || sleep 20
guard_workflows
log "done: main=${up:0:12} $BRANCH=${new:0:12}"
