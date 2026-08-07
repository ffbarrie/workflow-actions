# How well does the pattern actually fit our repos?

**Status:** Companion to the [adoption proposal](adoption-proposal.md) — evidence for team discussion, not a decision.
**Author:** Fred Barrie
**Scope:** foundry-client, foundry-server, trickle-client, trickle-server, vantage-client, vantage-server, foundry-client-template, foundry-server-template, soundgen-fintech-server, soundgen-fintech-client, soundgen-fintech-client-v01
**Excludes:** `isowave-server`, `isowave-client` — special-cased, out of scope by design.

## Bottom line

The pattern fits directionally, but almost none of these repos would be a drop-in swap. Every real repo reviewed is running a *simpler and less automated* release process than the sandbox repos the proposal was built on — most just push a Docker image when a human manually creates a version tag, with no CI, no develop→main promotion, and (with one exception) no vulnerability scanning at all. Adopting `workflow-actions` would be a genuine capability upgrade for nearly everyone, not a lateral refactor — good news for the pitch, and a fair thing to name up front, because it also means the ask is bigger than "swap your workflow files."

One real architectural gap turned up: four repos build Maven *inside* the Docker build using BuildKit secret mounts, a shape `release-java-application.yml` doesn't support today. That's fixable, not disqualifying — see the proposals below. And `foundry-server` is already running exactly the kind of secret-scanning workflow the team should generalize; that's the clearest, lowest-risk addition to propose.

## Repo-by-repo / family-by-family

### Java server family — needs an engineering ask first
`trickle-server` · `vantage-server` · `soundgen-fintech-server` · `foundry-server-template`

Four near-identical, copy-pasted `docker-build.yml` files. All trigger only on `push: tags: 'v*.*.*'` plus manual dispatch — a human creates and pushes the tag; there's no CI on every push, no develop→main promotion, no automated version bump. All four Dockerfiles build Maven **inside** the image using BuildKit `--mount=type=secret`, reading registry credentials from a mounted file rather than a build-arg — a deliberately more secure pattern, since build-args land in image history and secret mounts don't.

`release-java-application.yml` assumes the opposite shape: `mvn package` runs on the runner first, then a thin Dockerfile just `COPY`s the finished jar in. Migrating any of these four as-is would mean either rewriting the Dockerfile to drop the in-container build (a real, if modest, security regression) or extending `docker-build-scan-push` to pass BuildKit secrets through (see proposal below).

Worth naming as a selling point rather than burying: **none of these four currently run Trivy or any vulnerability scan.** Adopting `docker-build-scan-push` closes that gap for all four in one motion, once the secrets gap is fixed.

`foundry-server-template` is the natural pilot in this family — it's a template with no production traffic riding on it, and getting its CI/CD right has outsized leverage since every future service starts as a copy of it.

### Node client family — same secrets gap, smaller fix
`trickle-client` · `vantage-client` · `soundgen-fintech-client`

Same shape as the Java family — tag-push-triggered Docker build only, no CI, no promotion flow. The good news: these already pass credentials via `docker/build-push-action`'s native `secrets:` input (for `FOUNDRY_NPM_TOKEN` during private-registry `npm install`), not a raw BuildKit mount. That's the exact mechanism `docker-build-scan-push` would need to add anyway for the Java family, so one enhancement unblocks both families.

`soundgen-fintech-client-v01` is excluded from this family deliberately — see below.

### soundgen-fintech-client-v01 — confirm before including
Last pushed 2026-02-21 — over five months stale, versus `soundgen-fintech-client`'s last push two days ago. Only has a `main` branch (no `develop`), and its workflow diverges meaningfully from the rest of the Node family (its own version-derivation step, PR-triggered builds, extra permissions) rather than following the shared template. Reads like a superseded/legacy repo, not an active one. Worth a two-line confirmation with its owning team on whether it should be archived rather than migrated — including it in a rollout without checking risks spending effort on a repo nobody is maintaining.

### foundry-server — distinct model, don't force the application template
The most mature and most different repo in the set — three real workflows instead of one bare Docker build. `build.yml` runs `mvn package` then `mvn deploy` directly on push to `main`: no Docker image, no version tag, no release commit. That's closer in shape to what `release-java-library.yml` targets than `release-java-application.yml`, despite the repo's name — consistent with its actual description as a shared multi-module Java framework, not a deployed service. It's also triggered by `repository_dispatch: [core-test-updated]`, an external cross-repo signal `workflow-actions` has no equivalent of; that would need to stay a repo-owned addition alongside the shared pattern, not something to fold in.

`branch-guard.yml` is a genuinely distinct governance idea worth the team's attention on its own: rather than hard-blocking direct pushes to `main` via a ruleset, it lets the push through, detects it, and posts a Google Chat alert. That's a real alternative to (or complement of) `workflow-actions`' branch-ruleset approach — worth a deliberate decision, not silently dropped when this repo migrates.

One small, concrete data point for the proposal itself: `build.yml` configures `actions/setup-java` with a Maven server id (`github`) that nothing in the file actually uses — the real server id (`foundry`) is set up by a separate, manually-written `settings.xml` a few lines later. It's harmless today, but it's exactly the kind of small drift that accumulates in a hand-maintained workflow with no second reviewer — a live example of the problem the proposal is trying to solve, not a knock on this repo specifically.

### foundry-client — hardest fit, flag honestly, don't oversell
The most sophisticated repo reviewed: a 40-package npm workspaces monorepo with its own semantic-release-style tooling. `ci.yml` itself is a close match to `build-test-node-library.yml`'s job shape (build, type-check, lint, test, plus a custom `verify-versions` gate) — adopting the CI half is low-risk and should work today via the existing command-override inputs.

The release half is the real gap. `foundry-client`'s internal package dependencies are pinned as literal `"*"` in git, rewritten to real pinned versions only at publish time by its own `publish-workspaces.mjs` script. `release-node-library.yml` was deliberately built around a different assumption — internal deps expressed as `workspace:*` ranges that need no dependency-string rewriting, only each package's own version bumped. That was a conscious scoping decision earlier, not an oversight, but it means `release-node-library.yml` would not correctly publish `foundry-client`'s packages as-is.

Recommend being direct about this rather than glossing over it: propose `ci.yml` as an easy adoption now, and name the release side explicitly as unsolved — either a bespoke reusable workflow generalizing `foundry-client`'s own publish-time rewrite, or leave it hand-rolled until there's appetite to build that. Overselling this one is the fastest way to hand a skeptic a real counterexample.

### foundry-client-template — cleanest possible pilot
A Next.js/TypeScript template repo with **zero CI/CD today** — no workflows directory at all. No legacy behavior to migrate away from, no inconsistent secret names to reconcile, nothing to break. As a template, wiring it correctly once propagates to every repo cloned from it going forward. This is the single lowest-risk, highest-leverage place to demonstrate the pattern working, alongside `foundry-server-template` on the Java side.

## What this confirms about the proposal itself

Several things turned up that are direct, factual evidence for centralizing this logic — worth citing in the team discussion as observed reality, not a hypothetical:

- **Same credentials, three different secret names** across repos referencing the same registry — `ACTION_USER`/`ACTION_TOKEN`, `FOUNDRY_USER`/`FOUNDRY_PASSWORD`, and `FOUNDRY_USER`/`FOUNDRY_TOKEN` all found in copy-pasted, functionally-identical workflow files.
- **Inconsistent action version pins** across those same copy-pasted files — `actions/checkout@v4` vs. `@v7`, `docker/build-push-action@v5` vs. `@v7`, and similar drift on every other action used. This is exactly the failure mode a shared, versioned reusable workflow eliminates.
- **No vulnerability scanning at all** on any of the seven tag-push-triggered Docker repos reviewed — a real, current security gap that adopting `docker-build-scan-push` closes automatically.
- **No CI at all** on those same seven repos — release is the only automated thing that happens today; there's no build/lint/test validation on ordinary pushes or PRs.

**The honest counterweight:** almost none of these repos currently use the develop→main promotion model the three-file pattern assumes — most just tag off whatever branch a human is on. Adopting this pattern is asking these teams to adopt a branching discipline change, not just a workflow-file swap. That's a bigger, fairer ask to name up front than to have surfaced as a surprise objection later.

## Proposal: fold `scan-secrets` into `workflow-actions`

This is the direct answer to "is there another workflow like `scan-secrets` worth adding." `foundry-server` already has one — `secret-scan.yml`, running gitleaks against every PR and every push to `develop`/`main`, uploading a SARIF report as a build artifact. It's currently deliberately **advisory-only** (`--exit-code 0`, so findings are visible but never fail the build) while a specific set of known, tracked findings get remediated — with an explicit intent in the file's own comments to flip it to blocking once that's done.

That's a well-designed, low-risk pattern already proven in production. It doesn't touch release logic, doesn't conflict with any build topology, and applies identically to every Java and Node repo reviewed. Proposed shape for a new `scan-secrets.yml` reusable workflow:

```yaml
on:
  workflow_call:
    inputs:
      blocking:
        description: Fail the job on findings. Default true — new adopters
          get it strict from day one; migrating repos with existing
          findings opt into advisory mode explicitly, not by default.
        type: boolean
        required: false
        default: true
      gitleaks-version:
        type: string
        required: false
        default: "8.18.4"
      config-path:
        type: string
        required: false
        default: ".gitleaks.toml"
```

Every repo in this review — every family, every language, templates included — could adopt this immediately with no architectural conflict. It's the single easiest, most universally applicable addition found in this review, and a strong opening move: "here's a real gap we found across seven production repos, here's how one shared workflow closes it everywhere at once" is a much stronger pitch than the abstract version.

## Proposal: unblock the BuildKit-secrets repos

Second, smaller ask: extend `docker-build-scan-push` with an optional `build-secrets` input (newline-separated `id=value` pairs, mapped straight through to `docker/build-push-action`'s own `secrets:` input, which already supports exactly this). That one change unblocks all four Java-server repos and hardens the credential handling the Node-client repos already use. Without it, the Java-server family can't adopt `release-java-application.yml` without a Dockerfile rewrite that trades away their current, more secure build shape — a real blocker worth fixing before offering them this path, not after.

## Optional third option: a lighter entry point

Nearly every real repo reviewed uses the same minimal shape today: build and push a Docker image when a human pushes a version tag, nothing else automated. A thin reusable workflow that mirrors exactly that — tag-push triggered, calling `docker-build-scan-push` directly, no promote-PR machinery, no develop/main branching requirement — would let any of these repos pick up consistent action pins and Trivy scanning **immediately**, without also committing to the bigger branching-model change. That could be the actual lowest-friction first ask across this whole set, worth raising alongside the other two.

---

Findings gathered by reading each repo's actual workflow files, Dockerfiles, and branch lists directly via the GitHub API — not inferred from the sandbox repos' behavior. Same author, same "surface real objections rather than rubber-stamp agreement" intent as the main proposal.
