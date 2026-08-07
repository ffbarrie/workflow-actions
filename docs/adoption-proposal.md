# Proposal: adopt `workflow-actions` as Foundry's standard CI/CD pattern

**Status:** Draft for team discussion — not a decision, a starting point.
**Author:** Fred Barrie
**Repo under discussion:** [`ffbarrie/workflow-actions`](https://github.com/ffbarrie/workflow-actions), to be transferred to `Foundry-Innovations-PBC`

## Summary

I'd like the team's input on adopting a pattern where every repo's CI/CD is **three thin workflow files** that each `uses:` a shared, versioned reusable workflow — instead of every repo maintaining its own hand-rolled `mvn`/`npm`/Docker/release logic. The shared logic lives in one repo (`workflow-actions`) and gets fixed or improved once, and every repo that references it inherits the fix on its next run with **zero changes on their side**.

This isn't hypothetical — it's been running for real across four sandbox repos (two Java, two Node, one library/app pair each), including full release cycles, a cross-repo dependency round trip, and a live demonstration of the exact "fix once, inherit everywhere" mechanic. Details and evidence below. The open questions — pattern adoption, rollout approach, and public visibility — are for the team, not decided here.

## The pattern: three files, no logic

Each consuming repo gets:

| File | Purpose |
|---|---|
| `ci.yml` | Runs on push/PR to `develop` — build, lint, test |
| `promote-to-main.yml` | Manual trigger — opens a `develop → main` release PR |
| `release-*.yml` | Runs when that PR merges — builds, tags, publishes/deploys, proposes the next dev version back to `develop` |

Each file is a `uses:` reference to a reusable workflow in `workflow-actions@v1` (~15–20 lines, mostly `with:` inputs), for example:

```yaml
# .github/workflows/release.yml, in a consuming repo
on:
  pull_request:
    types: [closed]
    branches: [main]
  workflow_dispatch:

jobs:
  release:
    if: github.event_name == 'workflow_dispatch' || (github.event.pull_request.merged == true && github.event.pull_request.head.ref == 'develop')
    uses: ffbarrie/workflow-actions/.github/workflows/release-java-application.yml@v1
    with:
      image-name: my-app
      registry: registry.internal.example.com
    secrets: inherit
```

No repo owns its own Maven version-bump logic, Docker/Trivy scan logic, or npm publish logic. That all lives once, in `workflow-actions`, covering Java libraries, Java applications, Node libraries, and Node applications.

## Evidence: this has been running for real

Four repos have been running this pattern through complete, repeated release cycles:

- [`sandbox-java-library`](https://github.com/Foundry-Innovations-PBC/sandbox-java-library) → [`sandbox-java-app`](https://github.com/Foundry-Innovations-PBC/sandbox-java-app)
- [`sandbox-node-library`](https://github.com/Foundry-Innovations-PBC/sandbox-node-library) → [`sandbox-node-app`](https://github.com/Foundry-Innovations-PBC/sandbox-node-app)

Each pair demonstrated a **full round trip**: a new function added to the library, released through the pipeline (version tag, artifact published), and consumed by the app — automatically for Node (the app's release pins to the library's latest tag with no version number anywhere in the app's own history) and manually for Java (a human edits one `<version>` in `pom.xml`, deliberately, since nothing automates that yet — see "Known limitations" below).

### The clearest demonstration: one change, zero-touch propagation

Trivy (the container vulnerability scanner every Docker release runs through) needed to move from v0.70.0 to v0.73.0. This took **one line changed in `workflow-actions`**, one PR, one release cycle of that repo. `sandbox-java-app` and `sandbox-node-app` were then re-released with **no changes to either repo** — confirmed directly in their scan logs:

```
aquasecurity/trivy info found version: 0.73.0 for v0.73.0/Linux/64bit
```

That's the actual value proposition, demonstrated rather than asserted: a security-tooling upgrade lands everywhere at once, not per-repo, not per-team, not "whenever someone remembers to bump it."

### Real bugs, fixed once, inherited by everyone

Several genuine defects were found running this in earnest — not hypothetical edge cases — each fixed centrally in `workflow-actions`, each now protecting every consuming repo automatically:

- A release commit step failed outright when the version file was already at the target version (found on `sandbox-java-app`'s actual release history).
- A promote step would silently accept a non-SNAPSHOT `develop` version, producing a confusing downstream failure instead of a clear one — now refuses at the point of promotion with a clear reason.
- A Node app's sibling-library checkout resolved the source but not the built output, breaking the very next step — now builds the sibling before using it.
- A composite action script lost its executable bit in transit and failed with an opaque `Permission denied` — self-CI now checks this on every change.
- A redundant re-release (nothing new to release) failed hard instead of exiting cleanly, and — more seriously — would have tried to re-bump `develop`'s version a second time from a stale point, risking silently reverting real work.

None of these were repo-specific. Every one of them was a shared-logic bug, fixed once, and every consuming repo is safer for it without anyone touching their own workflow files.

## What I'm asking the team to weigh in on

This is not "should we use GitHub Actions" — it's specifically: **should shared release logic live in one reusable-workflow repo that every project references, or should each repo keep owning its own?** Concretely:

1. **Does the three-file pattern fit how our real repos actually release?** The sandbox repos are simple by design. Real repos may have wrinkles (multi-module builds, non-standard registries, different branch models) the current reusable workflows don't cover yet — worth surfacing before a broader rollout, not after.
2. **Rollout approach** — pilot on a small number of active repos first, or open it up for voluntary adoption immediately? I don't have a strong opinion here and would rather the team weigh in.
3. **Governance of `workflow-actions` itself.** Once multiple teams depend on it, who reviews changes to it? Right now `main`/`develop` require a PR (no direct pushes) but **zero required approvals** — any PR merges without a second reviewer, including mine. That was fine as a single-person sandbox; it's worth deciding whether shared infrastructure should require at least one approval before this goes wider.
4. **The floating `@v1` tag.** Every consumer references `@v1`, which moves forward on every change — there's no changelog and no per-repo opt-in. This session alone moved it a dozen-plus times. That's exactly what makes the Trivy story work (automatic propagation), but it's the same mechanism that would propagate a *bad* change just as automatically. Worth a real discussion: is floating-tag-with-review-discipline enough, or do we want a changelog, a slower-moving `@v1-stable` alongside a `@v1-latest`, or something else?

## Public visibility — the specific thing I want input on before transfer

`ffbarrie/workflow-actions` is **already public** (MIT licensed) under my personal account. Every other repo I've checked in `Foundry-Innovations-PBC` is private — the org currently has **zero public repos**. If this transfers into the org and stays public, it becomes the org's first public-facing artifact, associated with the Foundry name directly rather than a personal account.

**Why public matters practically, not just optically:** GitHub reusable workflows referenced across repos (`uses: owner/repo/.github/workflows/x.yml@v1`) need either (a) the source repo to be public, or (b) explicit per-repo access configuration in the source repo's Actions settings for every single private consumer. Keeping it private and allowlisting each repo works but doesn't scale well as an org-wide standard — every new consuming repo needs manual configuration, and it's easy to forget. Public removes that friction entirely, which is a large part of why it's public today.

**What's worth the team's input before transfer:**

- **Content audit.** No secrets have ever been committed (values are always `${{ secrets.X }}` references, never literal), but a deliberate secret-scan pass before/after transfer is warranted rather than assumed. Comments and commit history do reference real internal details — the Foundry Maven/npm/Docker registry hostname (`registry.foundry-pbc.com`), and real incident postmortems from actual releases. None of that is a secret, but it's discoverable and worth a conscious "are we fine with this being public" read-through, not a silent assumption.
- **Staying public vs. going private-with-allowlist.** I'd lean toward staying public given the scaling argument above, but this is exactly the kind of call that shouldn't be made unilaterally for the org's first public repo.
- **Naming.** `workflow-actions` is a fine name for a personal repo; worth deciding whether it should be renamed on transfer (e.g. something more clearly Foundry-branded) since it'll now appear on the org's public profile.
- **External contribution stance.** Public repos sometimes attract outside issues/PRs. Worth a quick, explicit decision — accepted and reviewed, or public-for-visibility-only with contributions closed — so nobody has to improvise an answer the first time it comes up.
- **License review.** MIT is already in place; worth a quick confirmation from whoever normally signs off on licensing that it's the right choice for this kind of tooling repo specifically.

## Where the evidence lives

- [`ffbarrie/workflow-actions`](https://github.com/ffbarrie/workflow-actions) — the repo itself, including its own README documenting every workflow/action and known limitations
- [`sandbox-java-library`](https://github.com/Foundry-Innovations-PBC/sandbox-java-library) / [`sandbox-java-app`](https://github.com/Foundry-Innovations-PBC/sandbox-java-app) — Java round trip, each with an `AGENTS.md` documenting real incidents hit while operating this pattern
- [`sandbox-node-library`](https://github.com/Foundry-Innovations-PBC/sandbox-node-library) / [`sandbox-node-app`](https://github.com/Foundry-Innovations-PBC/sandbox-node-app) — Node round trip, including the automatic dependency-pinning mechanism Java doesn't have (documented as a deliberate, known asymmetry, not an oversight)

I'd rather this proposal generate real objections and edge cases than rubber-stamp agreement — if there's a repo shape this pattern doesn't fit, or a governance model that fits the team better, that's exactly the input I'm looking for.
