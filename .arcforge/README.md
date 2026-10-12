# Arc Forge rehearsal fork

`arcforgelabs/openclaw-enterprise` is where Arc Forge rehearses a pull request
before it goes to `openclaw/openclaw-enterprise`. Our own ClawSweeper
(`arc-forge-clawsweeper-review[bot]`) reviews each rehearsal pull request at its
exact head, and Barnacle, the labeler and the command reactions run on it. This
directory and the `arcforge-*` workflows are the only Arc Forge files here. They
never go upstream.

## Branches

| Branch | Content | Rule |
| --- | --- | --- |
| `main` | Exact mirror of upstream `main` | Never commit to it. |
| `master` (default, the rehearsal branch) | Upstream `main` plus one infrastructure commit | Change only `.arcforge/` and `.github/workflows/arcforge-*`. |
| Feature branches | Your change, cut from upstream `main` | Never cut from `master`. |

`master` is the default branch, so `pull_request_target` and issue
workflows read our files from it. Every upstream workflow is disabled in the
fork's Actions settings.

The rehearsal branch is called `master` because the Arc Forge ClawSweeper
publisher reviews only pull requests whose base is `main` or `master`. A
pull request against any other base gets no review. `main` must stay the
upstream mirror, so the rehearsal branch takes the other accepted name.

## Rehearse a pull request

```bash
git fetch upstream main
git switch -c feat/my-change upstream/main
# commit the change
git push arcforge feat/my-change
gh pr create -R arcforgelabs/openclaw-enterprise \
  --base master --head feat/my-change
```

Write the body with the upstream template. The pull request diff shows only
your change, because the merge base is upstream `main`. Wait for the ClawSweeper
comment, fix the findings, and push again; each push gets a new review.

Before you post upstream, make sure that the branch holds no Arc Forge file:

```bash
git diff --name-only upstream/main...feat/my-change | grep -E '^(\.arcforge/|\.github/)' && echo STOP
```

Then push the same branch to the personal fork and open the upstream pull
request from there. GitHub does not allow "Allow edits by maintainers" on a fork
that an organisation owns.

```bash
git push personal feat/my-change
gh pr create -R openclaw/openclaw-enterprise --base main \
  --head IAMSamuelRodda:feat/my-change
```

Close the rehearsal pull request after the upstream one is open.

## Keep the fork current

Run `.arcforge/sync.sh` from any clone. Add `--dry-run` to see what it would do.
It fast-forwards `main` to upstream, rebases the infrastructure commit onto it,
and disables any new upstream workflow. Do not use GitHub's "Sync fork" button:
a new upstream workflow would arrive enabled.

Open rehearsal pull requests keep working after a sync. To review against the
newer upstream, rebase the feature branch onto `upstream/main` and push it.
