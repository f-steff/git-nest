# Using git-nest In CI Pipelines

This guide is written from the perspective of a DevOps engineer who wants
to build a pipeline that consumes a git-nest workspace: install git-nest,
restore the subprojects, and build. It covers every common CI system.

Every CI run of a git-nest workspace does the same three things:

1. Check out the outer repository.
2. Install git-nest (pinned to a version for reproducible builds).
3. Run `git-nest restore` (materialize the subprojects) and `git-nest
   verify` (confirm the workspace matches the manifest), then build and
   test.

git-nest is pure shell with no build step, so "installation" in CI is
just fetching the release tarball and putting `bin/` on PATH.

## Install One-Liners

For interactive installs the installers append `bin/` to the user's PATH
by default. In CI the pipeline manages PATH itself (e.g. `$GITHUB_PATH`),
so the recipes below install with `--no-add-path` (POSIX) or
`GIT_NEST_ADD_PATH=0` (Windows) and add the prefix's `bin/` to the
pipeline PATH explicitly.

### POSIX runners (Linux, macOS, BSD, Git Bash)

Pinned version (recommended for reproducible builds):

```sh
VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
```

Latest release (default when `VERSION` is unset):

```sh
curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
```

The installer downloads the release tarball, verifies it against the
release's `SHA256SUMS`, and installs into `$HOME/.local/bin`. Add that to
PATH in the pipeline, or install to a known prefix with `--prefix`:

```sh
VERSION=0.8.16 sh <(curl -fsSL .../git-nest-install.sh) --prefix "$RUNNER_TOOL_CACHE/git-nest" --no-add-path
```

### Windows runners (PowerShell 5.1+ or pwsh)

Pinned version:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:VERSION='0.8.16'; $env:GIT_NEST_ADD_PATH='0'; iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex"
```

Latest release:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:GIT_NEST_ADD_PATH='0'; & { iwr -useb https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.ps1 | iex }"
```

The `-ExecutionPolicy Bypass` flag makes the one-liner work regardless of
the machine's execution policy. The installer installs into
`%USERPROFILE%\.local\bin`; set `GIT_NEST_PREFIX` to change the prefix.

Always pin a version in CI -- reproducibility of the build starts with
reproducibility of the tool.

## Two Installation Models

There are two ways a CI system can make git-nest available, dictated by
whether runners are ephemeral or long-lived:

- **Install-once at the infrastructure level** (Jenkins-style): install
  git-nest once on the agent, or bake it into the agent Docker image
  (`RUN curl -fsSL .../git-nest-install.sh | sh -s -- --no-add-path` in the
  image build, with an `ENV PATH` for the install prefix).
  Every job on that agent then has git-nest on PATH. This works on
  long-lived agents: Jenkins agents, self-hosted Gitea/GitLab/GitHub
  runners, Azure self-hosted agents. It behaves exactly like a provisioned
  JDK -- one version managed centrally by the infrastructure owner.
- **Per-project install** (ephemeral-runner style): GitHub-hosted
  runners, Azure-hosted agents, and GitLab SaaS runners give every job a
  fresh VM, so each project must install git-nest per run. The one-liners
  above reduce this to a single line, and caching makes it cheap.

A project can keep the per-project model even on self-hosted
infrastructure, but install-once is strictly better there: zero install
step per project, one version managed centrally.

## Per-CI-System Recipes

### GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v5
  - name: Install git-nest
    run: |
      VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
      echo "$HOME/.local/bin" >> "$GITHUB_PATH"
  - name: Restore subprojects
    run: git-nest restore
  - name: Verify workspace
    run: git-nest verify
```

Windows runners: `shell: bash` works (Git for Windows ships bash), or use
the PowerShell one-liner from a `pwsh` step. Cache subproject clones
between runs with `actions/cache` keyed on the `.gitnest` file to speed up
repeated builds.

### Azure Pipelines

```yaml
steps:
  - checkout: self
  - bash: |
      VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
      echo "##vso[task.prependpath]$HOME/.local/bin"
    displayName: Install git-nest
  - bash: git-nest restore
    displayName: Restore subprojects
  - bash: git-nest verify
    displayName: Verify workspace
```

Notes: `task.prependpath` persists the PATH change for later steps.
Windows agents: use the Bash task (Git Bash) or a PowerShell task with the
Windows one-liner. macOS/Linux hosted agents work with the same snippet.

### GitLab CI

```yaml
image: alpine:3.21
before_script:
  - apk add --no-cache git curl
  - VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
  - export PATH="$HOME/.local/bin:$PATH"
script:
  - git-nest restore
  - git-nest verify
```

Notes: pick an image with sh + git; Alpine needs the `apk add` line,
Debian needs `apt-get install -y git curl`. The `before_script` lines
share shell state, so the `export PATH` applies to `script`.

### Gitea Actions

Gitea Actions is GitHub-Actions-compatible (act runner), so use the same
recipe as GitHub Actions:

```yaml
runs-on: ubuntu-latest
steps:
  - uses: actions/checkout@v5
  - run: |
      VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
      echo "$HOME/.local/bin" >> "$GITHUB_PATH"
  - run: git-nest restore && git-nest verify
```

Private Gitea instances can host the release tarball on their own
(Gitea has Releases too) and point `GIT_NEST_REPO` at their instance and
repository; the install scripts honor that override.

### Jenkins

Jenkins has two project types: **Pipelines** (Jenkinsfile, code-as-config)
and **freestyle projects** (point-and-click). Both work with git-nest.

#### Pipeline (Jenkinsfile, Declarative)

```groovy
pipeline {
  agent any
  stages {
    stage('Build') {
      steps {
        sh '''
          VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
          export PATH="$HOME/.local/bin:$PATH"
          git-nest restore
          git-nest verify
        '''
      }
    }
  }
}
```

Notes: keep the install + restore + verify in one `sh` block so the
`export PATH` stays in scope (Jenkins does not persist environment
between steps unless you use `env` or an environment binding). Windows
agents: use `bat`/`powershell` steps with the Windows one-liner.

#### Freestyle project (classic)

Add one or two **"Execute shell"** build steps (Unix) or **"Execute
Windows batch command"** steps (Windows):

```sh
# Build step 1: install git-nest and restore
VERSION=0.8.16 curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
export PATH="$HOME/.local/bin:$PATH"
git-nest restore
git-nest verify
```

Freestyle specifics: there is no `export` persistence between build steps,
so either keep install + restore + verify in a single step, or add
`$HOME/.local/bin` to the job's **Global properties -> Environment
variables**. Environment variables from the job config (including
secrets) are available as plain variables in the shell step. The Git
plugin is not needed for subprojects; git-nest calls git directly.

## Credentials For Private Subproject Remotes

Subproject remotes may be private. git-nest delegates to `git`, so
credential handling is standard git behavior; CI just needs to make
credentials available to git. The generic approach that works almost
everywhere is a `.netrc` written from a secret before restore (git reads
`~/.netrc` for HTTPS remotes):

```sh
printf 'machine github.com\nlogin x-access-token\npassword %s\n' "$TOKEN" > ~/.netrc
chmod 600 ~/.netrc
```

One `machine` block covers all private subprojects on the same host; add
more `machine` blocks for additional hosts (e.g. github.com + gitlab.com).

Per-system shortcuts:

| CI | Mechanism |
|----|-----------|
| GitHub Actions | `GITHUB_TOKEN` works for github.com remotes (scope: contents: read on the subproject repos) |
| Azure Pipelines | `System.AccessToken` or a PAT as a secret; configure a git credential helper |
| GitLab | `CI_JOB_TOKEN` (own instance) or deploy tokens |
| Jenkins | Credentials Binding plugin: `withCredentials([usernamePassword(credentialsId:'x', usernameVariable:'U', passwordVariable:'P')])` + git credential helper |
| Gitea | Token in `GITEA_TOKEN` + credential helper, or a `.netrc` |

## Docker Agent Images

For self-hosted agents that run jobs in containers, bake git-nest into the
agent image at build time:

```dockerfile
RUN curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
ENV PATH="/root/.local/bin:${PATH}"
```

Pin the version with an ARG for reproducible images:

```dockerfile
ARG GIT_NEST_VERSION=0.8.16
RUN VERSION=$GIT_NEST_VERSION curl -fsSL https://raw.githubusercontent.com/f-steff/git-nest/main/bin/git-nest-install.sh | sh -s -- --no-add-path
ENV PATH="/root/.local/bin:${PATH}"
```

The image digest (sha256) then serves as the trust anchor for every job
that runs on it, and the pinned version makes the image reproducible.

## Security Notes

- CI agents need **zero code signing** for git-nest: the payload is plain
  shell text, and no platform requires a signature on `.sh`/`.ps1` files
  before they run. The trust model is HTTPS + the release `SHA256SUMS`
  (which the install scripts verify automatically), plus the pinned
  version.
- For high-trust environments, pin both the version and the tarball hash
  (verify against the release `SHA256SUMS` yourself) instead of relying on
  the installer's download path.
