# workflow-actions

Reusable GitHub Actions and workflows for Java and Node (Next.js) projects.

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
[set-version](#set-version)'s closest-tag comparison.

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
(raw, e.g. `1.1.0-SNAPSHOT`), `base-version` (SNAPSHOT suffix stripped,
e.g. `1.1.0`), and `is-snapshot`. Makes no changes and compares against
nothing — it's the shared "what does the file currently say" building
block behind both halves of a release: computing the release version from
develop's current SNAPSHOT, and re-deriving that same version on `main`
right after the promote PR merges (which carries the SNAPSHOT-suffixed
value over as-is).

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

On `main`, the version must be strictly greater than the closest existing
release tag reachable from HEAD. On `develop` with `language: java`
specifically, `-SNAPSHOT` is appended to the applied version and the
comparison relaxes to greater-than-or-*equal* — right after a release
resync, `develop` legitimately holds the just-tagged version as a bare
number (tag `v1.1.0`, file says `1.1.0`), and the next snapshot based on
that same number (`1.1.0-SNAPSHOT`) is exactly what continues development.
Node has no SNAPSHOT concept and is unaffected. Other branches skip the
tag comparison entirely but still validate the version's format.

Returns `success`, `error-message`, and `validated-version` (the version
actually applied, including any `-SNAPSHOT` suffix) as outputs — the step
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

### [promote-to-main.yml](.github/workflows/promote-to-main.yml)

Reusable workflow, not a composite action — it's the first half of a
release: computes the release version from `develop`'s current SNAPSHOT
(via `get-version`) and opens the `develop` → `main` promote PR. It
doesn't build, test, publish, commit, or tag anything; the actual release
work happens on `main`, triggered by that PR's merge, which re-derives
the same version independently rather than trusting anything carried over
from this run.

It has no trigger of its own — the calling repo needs a thin
`workflow_dispatch` wrapper so a human explicitly kicks off a release from
`develop`, rather than this firing automatically on every push. Fails
loudly if triggered from any branch other than `develop`.

```yaml
# .github/workflows/release.yml, in the consuming repo
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
tarball (`publish-command`, default `npm publish`). Node has no SNAPSHOT
convention, so unlike the Java workflows the proposed next develop
version is a plain number, no suffix, applied the same way the release
version is.

**Root `package.json` only for now** — this doesn't address a monorepo's
child packages, which was a deliberate deferral, not an oversight (no
Changesets; child-package versioning via `set-version` is a later
problem).

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
version and `latest`. Node has no SNAPSHOT convention, so the proposed
next develop version is a plain number, no suffix, same as
`release-node-library.yml`.

`docker-build-scan-push`'s own checkout is disabled here too, for the
same `pull_request` ref-pinning reason as everywhere else in this
workflow, and also because its default `git clean` would otherwise wipe
out the build output the build step just produced — see
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
    uses: ffbarrie/workflow-actions/.github/workflows/release-node-application.yml@v1
    with:
      image-name: my-app
      registry: registry.internal.example.com
    secrets:
      registry-username: ${{ secrets.NEXUS_USERNAME }}
      registry-password: ${{ secrets.NEXUS_PASSWORD }}
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
    secrets: inherit
```
