# workflow-actions

Reusable GitHub Actions and workflows for Java and Node (Next.js) projects.

## Actions

### [setup-java-maven](actions/setup-java-maven)

Checks out the repo, installs a JDK (default 21) with Maven dependency
caching, and optionally writes `~/.m2/settings.xml` with one or more
`<server>` credential entries. Servers are given as plain newline-delimited
lists — `server-ids`, `server-usernames`, and `server-passwords` — paired up
by line position, so no JSON is needed even for multiple servers. Pass
`checkout: false` if a prior step in the job already checked the repo out
— see [Chaining multiple actions in one job](#chaining-multiple-actions-in-one-job).

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

### [set-version](actions/set-version)

Validates a human-entered version and writes it into the project's version
file(s) — `package.json` for Node, `pom.xml` (and optionally
`application-release.yaml`'s `app.version` key) for Java. On `develop`/`main`
the version must be strictly greater than the closest existing release tag
reachable from HEAD; other branches skip that comparison but still validate
the version's format. Returns `success`, `error-message`, and
`validated-version` as outputs — the step also fails (non-zero exit) on
invalid input, so add `if: always()` on any later step that needs to read
the outputs after a failure.

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
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: ffbarrie/workflow-actions/actions/setup-java-maven@v1
        with:
          checkout: false
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
