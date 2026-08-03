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
