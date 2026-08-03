# workflow-actions

Reusable GitHub Actions and workflows for Java and Node (Next.js) projects.

## Actions

### [setup-java-maven](actions/setup-java-maven)

Checks out the repo, installs a JDK (default 21) with Maven dependency
caching, and optionally writes `~/.m2/settings.xml` with one or more
`<server>` credential entries. Servers are given as plain newline-delimited
lists — `server-ids`, `server-usernames`, and `server-passwords` — paired up
by line position, so no JSON is needed even for multiple servers.

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
handling here).

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
