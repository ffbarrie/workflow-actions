# workflow-actions

Reusable GitHub Actions and workflows for Java and Node (Next.js) projects.

**Consuming repos:** reference this repo as `ffbarrie/workflow-actions@v1` (workflows and composite actions). Pin to `@v1` or a specific tag/SHA — do not use `@develop`. Changes to composite actions on `develop` are not exercised by reusable-workflow runs until `v1` is updated (or a new tag like `v2` is cut).

GitHub Free private organizations cannot call reusable workflows from another private repo. A private org copy exists at `Foundry-Innovations-PBC/workflows-actions`, but private Foundry consumers must `uses:` **this public repo** until the org repo is public or the org is on GitHub Team.

Setting up a new repo? [`examples/`](examples) has complete, ready-to-copy
`.github/workflows/` for all four repo shapes this covers — Java/Node ×
library/application — rather than assembling one from the snippets below.
Each shape is five wrappers: `ci.yml`, `promote.yml`, `release.yml`,
`secret-scan.yml`, and `branch-guard.yml`.

## Actions

### [setup-java-maven](actions/setup-java-maven)

Checks out the repo, installs a JDK (default 21) with Maven dependency
caching, and optionally writes `~/.m2/settings.xml` with one or more
`<server>` credential entries. Servers are given as plain newline-delimited
lists — `server-ids`, `server-usernames`, and `server-passwords` — paired up
by line position, so no JSON is needed even for multiple servers. This
write is authoritative — it replaces the whole file, including
`actions/setup-java`'s own default `github` server entry (it writes one
using `GITHUB_ACTOR`/`GITHUB_TOKEN` whether or not you asked for it); the
example below includes `github` explicitly for exactly that reason. Pass
`checkout: false` if a prior step in the job already checked the repo out
— see [Chaining multiple actions in one job](#chaining-multiple-actions-in-one-job).
`fetch-depth` (default `1`, passed straight through to `actions/checkout`)
only needs to be `0` when a later step needs full tag history — e.g.
[set-version](#set-version)'s closest-tag comparison.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: ffbarrie/workflow-actions/actions/setup-java-maven@v1
        with:
          server-ids: |
            github
            internal-releases
          server-usernames: |
            ${{ github.actor }}
            ${{ secrets.MAVEN_USER }}
          server-passwords: |
            ${{ secrets.GITHUB_TOKEN }}
            ${{ secrets.MAVEN_PASSWORD }}
      - run: mvn -B verify
```

### [setup-node](actions/setup-node)

Checks out the repo, installs Node.js (default 24) and the requested
package manager (npm, pnpm, or yarn) with dependency caching, and runs a
deterministic install (`npm ci` / `pnpm install --frozen-lockfile` /
`yarn install --immutable`), or a full `install-command` override for
cases like an out-of-sync lockfile or extra flags (e.g.
`npm install --legacy-peer-deps`). Optionally writes `~/.npmrc` for private
registry auth, either via `registry-url`/`scope` for the common single-scope
case, or a full `npmrc` escape hatch for anything more involved (multiple
registries/scopes — that's plain `.npmrc` text, so it needs no special
handling here). Pass `checkout: false` if a prior step in the job already
checked the repo out — see
[Chaining multiple actions in one job](#chaining-multiple-actions-in-one-job).
`fetch-depth` (default `1`, passed straight through to `actions/checkout`)
only needs to be `0` when a later step needs full tag history — e.g.
[set-version](#set-version)'s closest-tag comparison. `checkout-path`
(empty by default, checkout at `$GITHUB_WORKSPACE` root as before) checks
the repo out into a named subdirectory instead — distinct from
`working-directory` (which subdirectory holds the manifest to install);
set this when the repo itself needs to land next to another repo checked
out alongside it, e.g. via [checkout-sibling](#checkout-sibling).

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: ffbarrie/workflow-actions/actions/setup-node@v1
        with:
          package-manager: pnpm
          registry-url: https://npm.pkg.github.com
          scope: "@myorg"
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - run: pnpm build
```

### [checkout-sibling](actions/checkout-sibling)

Checks out another repo into a directory alongside the primary checkout
(both relative to `$GITHUB_WORKSPACE`) — for consumer apps whose
`file:../other-repo/...` dependencies expect a sibling repo present on
disk, the same layout tools like `deps-pin-from-siblings.mjs` /
`deps-unpin-to-file.mjs` expect locally. See
[release-node-application.yml](#release-node-applicationyml)'s
`sibling-repo` input for the full pin/unpin lifecycle this exists to
support.

Requires a `token` with read access to the sibling repo — `GITHUB_TOKEN`
is scoped only to the repo the workflow is running in, even within the
same org, so it can't check out a sibling on its own. Pass a PAT or
GitHub App installation token instead.

`ref` left empty (the default) resolves to the sibling's **latest tag**,
not its default branch HEAD — deliberately. This repo's own
`release-*.yml` workflows never push the release commit to `main`
itself, only to the tag it points to (`main` stays branch-protected), so
`main`'s HEAD can be a stale/dev-suffixed version even right after a
real release. The latest tag is the only ref guaranteed to hold a fully
released version. When used for the release-time pin step, "always
resolves to latest" has a real consequence worth reading about — see
[Node auto-updates a sibling dependency on release; Java doesn't](#node-auto-updates-a-sibling-dependency-on-release-java-doesnt).

```yaml
- uses: ffbarrie/workflow-actions/actions/checkout-sibling@v1
  with:
    repository: my-org/my-library
    path: my-library
    token: ${{ secrets.SIBLING_CHECKOUT_TOKEN }}
```

### [docker-build-scan-push](actions/docker-build-scan-push)

Checks out the repo, builds a Docker image, scans it with
[Trivy](https://github.com/aquasecurity/trivy), and pushes it only if the
scan passes — the image is built locally first (`push: false, load: true`),
scanned there, and only pushed afterward, so a vulnerable image is never
pushed. By default any HIGH or CRITICAL finding fails the job and blocks
the push (`severity`/`fail-on-scan-findings` are overridable for a
report-only rollout period). `push` defaults to `false` so PR/validation
runs build and scan without pushing.

**Single-platform only** — local pre-push scanning needs a
docker-loadable image, and Docker can't load a multi-platform manifest
into the local daemon. Because this is a composite action (not a reusable
workflow), it can't set job-level `permissions:` or use a `secrets:`
block, so the calling workflow must itself grant
`permissions: packages: write` (when pushing to GHCR) and pass registry
credentials as plain inputs.

This is typically the *last* action in a job, run after the app is
already built — pass `checkout: false` in that case, since
`actions/checkout`'s default `git clean` would otherwise delete whatever
that build produced. See
[Chaining multiple actions in one job](#chaining-multiple-actions-in-one-job).

```yaml
permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: ffbarrie/workflow-actions/actions/docker-build-scan-push@v1
        with:
          image-name: my-app
          registry: ghcr.io
          tags: latest,${{ github.sha }}
          push: ${{ github.ref == 'refs/heads/main' }}
          registry-username: ${{ github.actor }}
          registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### [get-version](actions/get-version)

Read-only: reads the project's current version from its version file —
`pom.xml` for Java, `package.json` for Node — and reports it as `version`
(raw, e.g. `1.1.0-SNAPSHOT` or `1.1.0-dev`), `base-version` (dev suffix
stripped, e.g. `1.1.0`), and `is-snapshot`. Makes no changes and compares
against nothing — it's the shared "what does the file currently say"
building block behind both halves of a release: computing the release
version from develop's current dev version, and re-deriving that same
version on `main` right after the promote PR merges (which carries the
dev-suffixed value over as-is).

Same assumptions as `set-version`: no checkout of its own, and language
tooling already set up by a prior step.

```yaml
- uses: ffbarrie/workflow-actions/actions/setup-java-maven@v1
- uses: ffbarrie/workflow-actions/actions/get-version@v1
  id: current
- run: echo "Releasing ${{ steps.current.outputs.base-version }}"
```

### [set-version](actions/set-version)

Validates a human-entered version and writes it into the project's version
file(s) — `package.json` for Node, `pom.xml` (and optionally
`src/main/resources/application-release.yaml`'s `app.version` and
`app.build` keys, following the standard Maven/Spring Boot resources
layout — `app.build` is a UTC build timestamp, `yyyy-MM-ddTHH:mm:ssZ`,
matching the existing PowerShell release scripts' convention) for Java.

For Node, also forces every non-private `packages/*/package.json` to the
same version as root — lockstep monorepo versioning, not independent
per-package versions. A no-op when there's no `packages/` directory.

On `main`, the version must be strictly greater than the closest existing
release tag reachable from HEAD. On `develop`, a hardcoded per-language
dev suffix is appended to the applied version — `-SNAPSHOT` for Java,
`-dev` for Node — and the comparison relaxes to greater-than-or-*equal*
— right after a release resync, `develop` legitimately holds the
just-tagged version as a bare number (tag `v1.1.0`, file says `1.1.0`),
and the next dev version based on that same number (`1.1.0-SNAPSHOT` or
`1.1.0-dev`) is exactly what continues development. Other branches skip
the tag comparison entirely but still validate the version's format.

Returns `success`, `error-message`, and `validated-version` (the version
actually applied, including any dev suffix) as outputs — the step
also fails (non-zero exit) on invalid input, so add `if: always()` on any
later step that needs to read the outputs after a failure.

Unlike the other actions here, `set-version` never checks out the repo
itself — it always assumes a prior step already did, **with
`fetch-depth: 0`** (full tag history is required for the comparison), and
that Node/npm or Java/Maven tooling is already set up. It also doesn't
commit, tag, or push anything; that's left to later steps in the calling
workflow.

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: ffbarrie/workflow-actions/actions/setup-java-maven@v1
        with:
          fetch-depth: 0
          java-version: "21"
      - uses: ffbarrie/workflow-actions/actions/set-version@v1
        id: version
        with:
          language: java
          version: ${{ github.event.inputs.version }}
      - run: mvn -B -Prelease deploy
```

## Chaining multiple actions in one job

Each action above checks out the repo by default, since each also works
standalone as the first step in a job. But these are composite actions,
not reusable workflows — their steps run inside your job, on the same
runner and filesystem as everything else in it. Chain two or more of
them (or run one after your own build step) without disabling checkout
on all but the first, and `actions/checkout`'s default `git clean -ffdx`
will delete whatever the earlier steps produced, since generated build
output is untracked and gitignored.

Set `checkout: false` on every one of these actions after the first in
the job:

```yaml
permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: ffbarrie/workflow-actions/actions/setup-node@v1
        with:
          package-manager: pnpm
      - run: pnpm build
      - uses: ffbarrie/workflow-actions/actions/docker-build-scan-push@v1
        with:
          checkout: false
          image-name: my-app
          registry: ghcr.io
          tags: latest,${{ github.sha }}
          push: ${{ github.ref == 'refs/heads/main' }}
          registry-username: ${{ github.actor }}
          registry-password: ${{ secrets.GITHUB_TOKEN }}
```

## Workflows

### Bootstrapping a new repo

GitHub only dispatches `pull_request`, `workflow_dispatch`, and `schedule`
triggers for workflow files that **already exist on the default branch** —
a wrapper introduced in the very PR that's supposed to trigger it can't
fire on that PR, since the default branch doesn't have the file yet at
evaluation time. The symptom is a run that fails instantly with zero jobs
and "This run likely failed because of a workflow file issue" — not a
build, deploy, or secrets problem, just this bootstrap gap. It hits every
wrapper below (`promote-to-main.yml`'s `workflow_dispatch` included) the
first time a repo adopts them, and resolves itself from the next real
event onward. Nothing is lost when it happens — merge the wrapper files
to `main` via a normal PR first, and the next natural develop → main
promote will trigger correctly.

Each release wrapper example below also includes `workflow_dispatch` as a
second trigger alongside `pull_request`, specifically so a human has a
manual way to complete that first bootstrap (or recover from any missed
automatic trigger) without waiting on another real PR merge. Note the
job's `if:` — it has to explicitly allow `workflow_dispatch` through,
since `github.event.pull_request` doesn't exist on that trigger and would
otherwise evaluate the merged/head-ref checks as false.

### The sync-back PR's CI check may need a manual nudge

Every `release-*.yml`'s last step opens the "bump develop" sync-back PR
using `github.token` (`git push` + `gh pr create`). GitHub Actions has a
platform-level behavior where activity performed with the default
`GITHUB_TOKEN` doesn't reliably auto-trigger *other* workflow runs the
way a human- or PAT-authenticated push would — so the sync-back PR's own
`pull_request`-triggered CI check (`build-test-*.yml`) may not
automatically appear, needing a human to manually trigger or approve it
before the PR can merge (confirmed in real-world testing: the PR is
authored by `app/github-actions`, and its CI check needed manual
authorization to run).

This is a real, known limitation across all four release workflows, not
a bug specific to one of them — left as-is for now since a manual gate
before merging an auto-generated version-bump PR isn't unreasonable on
its own. If it becomes real friction, the fix is swapping `github.token`
for a PAT or GitHub App installation token in that one step, which would
let the sync-back PR's CI run automatically like any human-created PR.

### Node auto-updates a sibling dependency on release; Java doesn't

A consumer app's release picks up a new version of a sibling dependency
completely differently depending on language, and this is worth knowing
up front rather than discovering by surprise:

- **Node** (`release-node-application.yml`'s `sibling-repo`): `pin-command`
  reads whatever version [checkout-sibling](#checkout-sibling) resolved
  — the sibling's **latest tag**, by default — and writes it straight
  into `package.json`. This happens automatically, with no human
  decision, on **every single release**. Two releases of the exact same
  app commit, run at two different times, can produce two different
  images if the library tagged a new release in between — there's no
  version pin in the app's own git history to make that reproducible,
  and no changelog review or opt-in gate before the new library version
  ships. (This is the same shape of risk as `workflow-actions`' own
  floating `@v1` tag, one layer down — see this repo's own commit
  history for how many times `@v1` moved during a single working
  session.)
- **Java** (Maven `pom.xml` dependencies): there is no equivalent
  mechanism anywhere in this repo. Picking up a newer library version
  requires a human to explicitly edit the `<version>` in `pom.xml` on
  `develop` and commit that change — deliberate, reviewable, and fully
  reproducible (the exact dependency version is pinned in git history),
  but also entirely manual: nothing here notices or nudges when a
  dependency has a newer release available, so it can drift arbitrarily
  stale with no automatic signal.

Neither behavior is strictly "correct" — automatic-latest trades
reproducibility and review for zero maintenance burden; manual-pin trades
zero automatic drift-detection for needing a human to remember. They're
just different, and currently different **by accident of how each was
built** (`checkout-sibling` was designed for Node's `file:`-dependency
convenience-on-`develop` pattern; nothing equivalent has been built for
Maven). If Java apps end up needing the same "always build against the
library's latest release" behavior, that would need new, separate work —
Maven has no `file:`-path dependency concept to mirror, so it'd look
different in shape, not just a port of `checkout-sibling`.

### [promote-to-main.yml](.github/workflows/promote-to-main.yml)

Reusable workflow, not a composite action — it's the first half of a
release: computes the release version from `develop`'s current dev
version (via `get-version`) and opens the `develop` → `main` promote PR. It
doesn't build, test, publish, commit, or tag anything; the actual release
work happens on `main`, triggered by that PR's merge, which re-derives
the same version independently rather than trusting anything carried over
from this run.

It has no trigger of its own — the calling repo needs a thin
`workflow_dispatch` wrapper so a human explicitly kicks off a release from
`develop`, rather than this firing automatically on every push. Fails
loudly if triggered from any branch other than `develop`. Deliberately a
*separate* file from the release wrapper below (`promote.yml`, not
`release.yml`) — combining them would mean two `on:`/`jobs:` blocks
colliding in one file, since the release wrapper's own `workflow_dispatch`
means something different (a recovery path, not "start a new release").

Also fails loudly if `develop`'s version isn't a SNAPSHOT (Java) or
`-dev` (Node) version. A bare release version on `develop` (e.g.
hand-committed `1.0.0` instead of `1.0.1-SNAPSHOT`) would otherwise
promote fine, then leave the release workflow on `main` with nothing to
commit — no tag, no develop sync-back PR, discovered only after the
fact. This check has no override input by design: if a bare version
genuinely needs promoting, open the `develop` → `main` PR by hand
instead of dispatching this workflow (e.g. `gh pr create --base main
--head develop --title "Promote develop into main for version X"`) —
merging it still triggers the release workflow the same way, since that
trigger only checks the merged PR's head ref, not who or what opened it.

```yaml
# .github/workflows/promote.yml, in the consuming repo
on:
  workflow_dispatch:

jobs:
  promote:
    uses: ffbarrie/workflow-actions/.github/workflows/promote-to-main.yml@v1
    with:
      language: java
```

### [release-java-library.yml](.github/workflows/release-java-library.yml)

Second half of the release, for Java library repos that publish jars via
`mvn deploy`. Runs on `main` right after `promote-to-main.yml`'s PR
merges: re-derives the release version independently (`get-version` +
`set-version`, not trusting anything carried over from that PR), builds
and `mvn deploy`s the library, then tags the release — then proposes the
next `develop` SNAPSHOT (a minor version bump) as a PR back to `develop`,
for a human to edit before merging if a different bump is wanted.

The release commit is never pushed to the `main` branch ref itself, only
as the tag it points to — `main` is typically branch-protected, and a
plain branch push would be rejected, while a tag push needs no special
bypass configuration in the calling repo. `pull_request`'s `github.ref` is
the PR's merge ref, not the target branch, and that ref is gone once the
PR closes — so every checkout here is pinned to an explicit `ref: main`.

Like `promote-to-main.yml`, this has no trigger of its own:

Optional GPG signing: pass `gpg-sign: true` and provide `gpg-private-key` /
`gpg-passphrase` secrets. Secrets cannot appear in step `if` conditions, so
signing is gated by this input instead.

```yaml
# .github/workflows/release.yml, in the consuming repo
on:
  pull_request:
    types: [closed]
    branches: [main]
  workflow_dispatch:

jobs:
  release:
    if: github.event_name == 'workflow_dispatch' || (github.event.pull_request.merged == true && github.event.pull_request.head.ref == 'develop')
    uses: ffbarrie/workflow-actions/.github/workflows/release-java-library.yml@v1
    secrets:
      maven-server-ids: github
      maven-server-usernames: ${{ github.actor }}
      maven-server-passwords: ${{ secrets.GITHUB_TOKEN }}
```

### [release-java-application.yml](.github/workflows/release-java-application.yml)

Same shape as `release-java-library.yml` — runs on `main` after
`promote-to-main.yml`'s PR merges, re-derives the release version, tags
the release the same tag-only way, and proposes the next `develop`
SNAPSHOT — but for Java applications that ship as a container instead of
a published jar. Builds the jar (`build-command`, default `mvn -B
package`) and then builds/scans/pushes the image via
`docker-build-scan-push`, tagged with both the release version and
`latest`. No GPG signing step — that's a Maven Central concern, not a
Docker one.

`docker-build-scan-push`'s own checkout is disabled here too, for the
same `pull_request` ref-pinning reason as everywhere else in this
workflow, and also because its default `git clean` would otherwise wipe
out the jar the build step just produced — see
[Chaining multiple actions in one job](#chaining-multiple-actions-in-one-job).

```yaml
# .github/workflows/release.yml, in the consuming repo
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
    secrets:
      registry-username: ${{ secrets.NEXUS_USERNAME }}
      registry-password: ${{ secrets.NEXUS_PASSWORD }}
```

### [release-node-library.yml](.github/workflows/release-node-library.yml)

Same shape as the Java release workflows — runs on `main` after
`promote-to-main.yml`'s PR merges, re-derives the release version, tags
the release the same tag-only way — but for Node libraries publishing a
tarball (`publish-command`, default `npm publish`). The proposed next
develop version gets `-dev` appended (Node's hardcoded dev suffix,
mirroring Java's `-SNAPSHOT`), e.g. `1.2.0-dev`.

**Monorepo child packages get the root version in lockstep.** `set-version`
writes the release version into root `package.json`, then forces every
non-private package under `packages/*` to that same version — not
independent per-package versions (no Changesets). Internal `@scope/*`
dependency ranges are assumed to already be `workspace:*`/range, not
exact-pinned, so no dependency-string rewriting happens, only each
package's own `version` field. Packages outside `packages/`, or marked
`"private": true`, are left alone.

```yaml
# .github/workflows/release.yml, in the consuming repo
on:
  pull_request:
    types: [closed]
    branches: [main]
  workflow_dispatch:

jobs:
  release:
    if: github.event_name == 'workflow_dispatch' || (github.event.pull_request.merged == true && github.event.pull_request.head.ref == 'develop')
    uses: ffbarrie/workflow-actions/.github/workflows/release-node-library.yml@v1
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}
```

### [release-node-application.yml](.github/workflows/release-node-application.yml)

Same shape as `release-java-application.yml` — runs on `main` after
`promote-to-main.yml`'s PR merges, re-derives the release version, tags
the release the same tag-only way, and proposes the next develop version
— but for Node applications that ship as a container. Builds
(`build-command`, default `npm run build`) and then builds/scans/pushes
the image via `docker-build-scan-push`, tagged with both the release
version and `latest`. The proposed next develop version gets `-dev`
appended, same as `release-node-library.yml`.

`docker-build-scan-push`'s own checkout is disabled here too, for the
same `pull_request` ref-pinning reason as everywhere else in this
workflow, and also because its default `git clean` would otherwise wipe
out the build output the build step just produced — see
[Chaining multiple actions in one job](#chaining-multiple-actions-in-one-job).

**`sibling-repo`**: for consumer apps whose `file:../other-repo/...`
dependencies expect a sibling repo present on disk on `develop`, for
developer convenience. When set, this workflow [checks out that sibling
at its latest tag](#checkout-sibling) (not `main` — see that section for
why) **automatically, on every release, with no human decision or pin in
the app's own git history** (see
[Node auto-updates a sibling dependency on release; Java doesn't](#node-auto-updates-a-sibling-dependency-on-release-java-doesnt)
if that's surprising), runs `pin-command` (default `npm run deps:pin`) before the build
so the release commit carries real semver instead of `file:` links, and
runs `unpin-command` (default `npm run deps:unpin`) on the develop
sync-back branch so `develop` goes back to `file:` links afterward. Set
`checkout-path` (and `working-directory` to match) to a subdirectory
name so this repo lands as a true sibling of `sibling-path` on disk —
both empty (the default) skip all of this and behave exactly as before.
`sibling-build-command` (default `npm ci && npm run build`) runs in the
sibling's checkout first — `file:` deps copy whatever's currently on
disk there as-is, so an unbuilt TypeScript/build-step sibling (source
only, no `dist/`) fails to resolve at this repo's own install time.

```yaml
# .github/workflows/release.yml, in the consuming repo
on:
  pull_request:
    types: [closed]
    branches: [main]
  workflow_dispatch:

jobs:
  release:
    if: github.event_name == 'workflow_dispatch' || (github.event.pull_request.merged == true && github.event.pull_request.head.ref == 'develop')
    uses: ffbarrie/workflow-actions/.github/workflows/release-node-application.yml@v1
    with:
      image-name: my-app
      registry: registry.internal.example.com
      checkout-path: my-app
      working-directory: my-app
      sibling-repo: my-org/my-library
      sibling-path: my-library
    secrets:
      registry-username: ${{ secrets.NEXUS_USERNAME }}
      registry-password: ${{ secrets.NEXUS_PASSWORD }}
      sibling-token: ${{ secrets.SIBLING_CHECKOUT_TOKEN }}
```

### [build-test-java.yml](.github/workflows/build-test-java.yml)

Regular CI — `mvn verify` — shared by both Java library and application
repos, since compiling and testing doesn't care which the artifact
eventually becomes; that only matters at release time. `build-image` is
an application-repo opt-in: a validation-only `docker build` (no push)
that catches Dockerfile problems in CI instead of at release time.
Libraries have no Dockerfile and leave it at the default `false`.

```yaml
# .github/workflows/ci.yml, in the consuming repo
on:
  push:
    branches: [develop]
  pull_request:
    branches: [develop]

jobs:
  ci:
    uses: ffbarrie/workflow-actions/.github/workflows/build-test-java.yml@v1
    secrets: inherit
```

### [build-test-node-library.yml](.github/workflows/build-test-node-library.yml) and [build-test-node-application.yml](.github/workflows/build-test-node-application.yml)

Regular CI for Node — lint/build/test — kept as two separate workflows
rather than one branching on both package-manager *and*
monorepo-vs-single-package. `build-test-node-library.yml` is
workspace-aware (`pnpm --recursive`, `yarn workspaces foreach`, etc.) for
the monorepo case; `build-test-node-application.yml` uses plain
single-package commands and adds the same `build-image` Dockerfile
validation opt-in as `build-test-java.yml`. Set `lint-command: ""` to
skip linting.

`build-test-node-application.yml` also takes the same `sibling-repo`
input as [release-node-application.yml](#release-node-applicationyml),
for consumer apps whose `file:../other-repo/...` deps expect a sibling
repo on disk. Here `sibling-ref` defaults to `develop` rather than the
release workflow's latest-tag default — CI on `develop` should test
against the sibling's current in-progress code, not its last release.
Same `sibling-build-command` too (default `npm ci && npm run build`,
run in the sibling's checkout before this repo's own install) — a
build-step sibling with no `dist/` yet fails `file:` resolution
otherwise.

```yaml
# .github/workflows/ci.yml, in the consuming repo
on:
  push:
    branches: [develop]
  pull_request:
    branches: [develop]

jobs:
  ci:
    uses: ffbarrie/workflow-actions/.github/workflows/build-test-node-application.yml@v1
    with:
      package-manager: pnpm
      checkout-path: my-app
      working-directory: my-app
      sibling-repo: my-org/my-library
      sibling-path: my-library
    secrets:
      sibling-token: ${{ secrets.SIBLING_CHECKOUT_TOKEN }}
```

### [scan-secrets.yml](.github/workflows/scan-secrets.yml)

Language-agnostic gitleaks scan of the working tree — not bundled into
`build-test-*.yml` because it has a different trigger shape (PRs plus
pushes to both `develop` and `main`) and a different failure policy.
Default is **blocking** so new adopters get a strict scan from day one.
Repos with known, tracked findings pass `blocking: false` and stay
advisory until they can flip it. If `config-path` (default
`.gitleaks.toml`) is missing, the scan still runs with gitleaks' default
rules.

```yaml
# .github/workflows/secret-scan.yml, in the consuming repo
on:
  pull_request:
  push:
    branches: [develop, main]
  workflow_dispatch:

jobs:
  scan:
    uses: ffbarrie/workflow-actions/.github/workflows/scan-secrets.yml@v1
    with:
      blocking: true
```

### [branch-guard-main.yml](.github/workflows/branch-guard-main.yml)

After-the-fact detector for a direct push to `main` (anything that is
not a PR merge). **GitHub Free private organizations cannot use branch
protection / rulesets to hard-block those pushes**, so this cannot
prevent the commit from landing — it fails the Actions run for
visibility and optionally posts to a chat webhook (`chat-webhook`
secret, e.g. `GCHAT_WEBHOOK`) so someone notices. Empty webhook skips
notification; the job still fails.

Compatible with this repo's tag-only release model: `release-*.yml`
never pushes a commit to the `main` branch ref, so a legitimate promote
is a PR merge (allowed) and a human `git push` to `main` is what this
catches. Not bundled into `build-test-*.yml` — that workflow never
runs on `main`.

```yaml
# .github/workflows/branch-guard.yml, in the consuming repo
on:
  push:
    branches: [main]

jobs:
  guard:
    uses: ffbarrie/workflow-actions/.github/workflows/branch-guard-main.yml@v1
    secrets:
      chat-webhook: ${{ secrets.GCHAT_WEBHOOK }}
```

## Validating this repo itself

Unlike every other workflow above, [`self-ci.yml`](.github/workflows/self-ci.yml)
isn't reusable — it's this repo's own CI, running on every push/PR to
`develop`/`main`. It automates checks that were previously done by hand,
ad hoc, during development, so a regression gets caught on the next PR
instead of the next real-world integration:

- Executable bits on every `actions/**/*.sh` — a real failure, not a hypothetical: `checkout-latest-tag.sh` was committed `100644` instead of `100755` (a Write-tool artifact, never `chmod`'d before the original commit) and nothing caught it until a real release run hit `Permission denied`. bats invokes scripts via `bash "$SCRIPT"`, which bypasses the shebang/exec-bit mechanism entirely — full bats coverage wouldn't have caught this class of bug, so it's checked directly instead.
- `scripts/validate-yaml.rb` — every `action.yml` and workflow file parses as YAML
- [`actionlint`](https://github.com/rhysd/actionlint) — GitHub Actions semantics for `.github/workflows/*.yml`, including its own shellcheck pass on `run:` steps there
- `scripts/shellcheck-actions.sh` — shellchecks every composite action's script files directly, since actionlint's schema doesn't understand `action.yml` and gives those zero coverage otherwise

Run any of these locally the same way CI does:

```bash
ruby scripts/validate-yaml.rb
actionlint                          # requires actionlint on PATH
bash scripts/shellcheck-actions.sh  # requires shellcheck on PATH
```

Every composite action's logic lives in real `.sh` files alongside its
`action.yml` (e.g. `actions/set-version/validate-version.sh`), invoked via
`run: ${{ github.action_path }}/script-name.sh` rather than embedded
inline — a standard pattern for composite actions with real logic, and
what makes `shellcheck-actions.sh` able to check actual files instead of
text extracted out of YAML. It's also what makes that logic unit-testable
at all; see [Testing the core logic](#testing-the-core-logic).

`shellcheck-actions.sh` gates on `--severity=warning` — info/style
findings are suppressed rather than shown, since they're not worth
blocking a build over. A genuinely new `error`/`warning` finding still
fails it.

### Testing the core logic

[`tests/`](tests) holds a [bats-core](https://github.com/bats-core/bats-core)
suite covering the scripts with real logic of their own — `set-version`'s
comparison/dev-suffix rules and per-language file updates,
`get-version`'s suffix stripping, `checkout-sibling`'s latest-tag
resolution, `docker-build-scan-push`'s tag-list construction and push
loop, `setup-java-maven`'s server-list validation, and `setup-node`'s
install-command case statement and `.npmrc` writer. It mirrors
`actions/`'s structure (`tests/set-version/validate-version.bats` tests
`actions/set-version/validate-version.sh`, and so on) and persists what
was, until this point in the repo's history, only ever manual, ad hoc
verification run by hand during development — every case in this suite
was checked at least once that way before being written down here.
Two scripts are deliberately left untested — `update-pom-xml.sh` and
`show-versions.sh` are one-line passthroughs to `mvn`/`java` with no
branching logic of their own; a test would just be testing Maven, not
this repo.

```bash
bats -r tests/                                    # requires bats-core on PATH
bats tests/set-version/validate-version.bats       # a single file
```

Each `.bats` file invokes its target script directly (`bash
actions/X/script.sh`, with inputs set via environment variables the same
way the composite action's own `env:` block would) rather than going
through an actual GitHub Actions run — fast, and no network/runner
dependency, at the cost of not exercising the actual `${{ github.action_path }}`
invocation mechanism itself (the self-ci executable-bit check above
closes one specific instance of that gap — a missing `+x` bit — but not
the general case). That's only fully verifiable by an actual run on
GitHub Actions, same as everything else in this repo that depends on
real GitHub Actions runtime behavior.
