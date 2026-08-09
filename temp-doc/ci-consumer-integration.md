# Using git-nest From CI Runners

Personal research notes. NOT committed (temp-doc/ is gitignored).
Companion to `distribution-investigation.md` (packaging/publishing); this
doc covers the reverse direction: how CI systems install git-nest and use it
in pipelines (restore subprojects, verify, build).

## The pattern

Every CI run of a git-nest workspace does the same three things:

1. Check out the outer repository.
2. Install git-nest (from a release tarball/installer, pinned to a version).
3. Run `git-nest restore` (materialize subprojects) and `git-nest verify`
   (confirm reproducibility), then build/test.

Since git-nest is pure shell with no build step, "installation" in CI is
just fetching the release tarball and putting `bin/` on PATH. The generic
POSIX snippet:

```sh
curl -fsSL -o /tmp/git-nest.tar.gz \
  https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
mkdir -p "$HOME/.local/share/git-nest"
tar -xzf /tmp/git-nest.tar.gz -C "$HOME/.local/share/git-nest"
export PATH="$HOME/.local/share/git-nest/bin:$PATH"
git-nest version
```

Always pin a version in CI (never `latest`); reproducibility of the build
starts with reproducibility of the tool.

## Two installation models

There are two fundamentally different ways a CI system can make git-nest
available, and the choice is dictated by whether runners are ephemeral or
long-lived:

### Model A: install-once at the infrastructure level (Jenkins-style)

This is the model familiar from Jenkins: a tool is installed once on the
CI system (plugin, Global Tool Configuration, or the agent image) and is
then available to **every project** without each one fetching it.

For git-nest this means: **bake `bin/` into the agent/runner image** (or
install it once on a long-lived agent). Every job on that agent then has
`git-nest` on PATH and uses it directly -- no per-project install step at
all.

Where it applies:

| System | Mechanism | Ephemeral? |
|--------|-----------|------------|
| Jenkins | Install on the agent (or in the agent Docker image); optionally a thin Shared Library wrapper for pipeline convenience | Long-lived agents: YES, install once |
| Self-hosted Gitea | Bake into the act_runner image, or install on the runner host | Runner host long-lived: YES |
| Azure self-hosted agents | Install into the agent image / agent machine; jobs on that agent pool just use it | Agent machine long-lived: YES |
| GitLab (self-hosted runners) | Put git-nest in the runner's Docker image or the runner host | Long-lived runner: YES |
| GitHub self-hosted runners | Install into the runner image; all jobs on that runner use it | Runner host long-lived: YES |
| GitHub hosted runners / Azure hosted / GitLab SaaS | NOT possible: every job gets a fresh ephemeral VM | Always ephemeral: NO |

With this model, git-nest behaves exactly like a Jenkins plugin or a
provisioned JDK: present on the system, optionally available to all
projects. The `install.sh` script built for release artifacts is exactly
what the image build uses (a `RUN` step in a Dockerfile, or a provisioning
script on the agent host).

**Prototype built**: `docker/agent-image/Dockerfile` (in the repo) builds a
25 MB alpine image with git-nest preinstalled at `/usr/local/bin` (on
PATH), git included, verified end-to-end (init/add/clone/status). Build
once per release, tag as `ghcr.io/f-steff/git-nest-agent:<version>`, and
point Jenkins/Gitea/GitLab/self-hosted agents at it.

**Jenkins specifics (the model you know):** a shell tool like git-nest
does NOT need a Java plugin. The Jenkins-native ways are:
1. **Agent provisioning** (simplest): run `install.sh` once on the agent
   (or `RUN sh install.sh` in the agent Docker image). Every freestyle job
   and pipeline on that agent can call `git-nest` directly.
2. **Global Tool Configuration**: only supports tools with an installer
   mechanism (JDK/Maven-style); git-nest would need a custom tool installer
   (Java code). Overkill for a shell tool.
3. **Shared Library** (Groovy, optional convenience): a small library with
   a `gitNest([version: '0.8.16'])` step that wraps the restore/verify
   calls. This is convenience wrapping, not installation -- the binary
   still comes from the agent or is fetched once and cached.

### Model B: per-project install (ephemeral-runner style)

GitHub-hosted runners, Azure-hosted agents, and GitLab SaaS runners are
ephemeral: every job starts on a fresh VM, so there is nowhere to install
once. Each project must install git-nest per run. The `install.sh` +
release-tarball pattern (or the `setup-git-nest` action / pipeline
template) reduces this to a one-liner, and caching makes it cheap.

A project can keep Model B even on self-hosted infrastructure, but Model A
is strictly better there: zero install step per project, one version
managed centrally by the infrastructure owner.

### Recommendation

- **Self-hosted Jenkins/Gitea/Azure agents**: use Model A -- install once
  on the agent/image. This is what you are used to and it is the right
  fit.
- **Hosted runners (GitHub/Azure/GitLab SaaS)**: Model B with a one-line
  setup step (action or template); there is no alternative.
- **Hybrid**: bake git-nest into self-hosted agent images AND publish the
  `setup-git-nest` action for hosted runs, so both populations get the
  same pinned version from the same release pipeline.

## Per-CI-system recipes

### GitHub Actions

```yaml
steps:
  - uses: actions/checkout@v5
  - name: Install git-nest
    run: |
      curl -fsSL -o /tmp/git-nest.tar.gz \
        https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
      mkdir -p "$HOME/.local/share/git-nest"
      tar -xzf /tmp/git-nest.tar.gz -C "$HOME/.local/share/git-nest"
      echo "$HOME/.local/share/git-nest/bin" >> "$GITHUB_PATH"
  - name: Restore subprojects
    run: git-nest restore
  - name: Verify
    run: git-nest verify
```

Windows runners: use `shell: bash` (Git for Windows is preinstalled and
provides bash). The `.ps1` launcher also works from pwsh.

Options:
- A dedicated `f-steff/setup-git-nest` action (version input, caches the
  install) would make the install step one line:
  `uses: f-steff/setup-git-nest@v1` with `with: { version: 0.8.16 }`.
  Recommend building this -- it is the natural GitHub-native distribution.
- Cache subproject clones between runs with `actions/cache` keyed on
  `.gitnest` to speed up repeated builds.

### Azure Pipelines

```yaml
steps:
  - checkout: self
  - bash: |
      curl -fsSL -o /tmp/git-nest.tar.gz \
        https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
      mkdir -p "$HOME/.local/share/git-nest"
      tar -xzf /tmp/git-nest.tar.gz -C "$HOME/.local/share/git-nest"
      echo "##vso[task.prependpath]$HOME/.local/share/git-nest/bin"
    displayName: Install git-nest
  - bash: git-nest restore
    displayName: Restore subprojects
  - bash: git-nest verify
    displayName: Verify workspace
```

Notes:
- `task.prependpath` makes the PATH change persist for later steps.
- Windows agents: Git for Windows is present; use the Bash task (Git Bash)
  or pwsh with `git-nest.ps1`.
- macOS/Linux hosted agents work with the same snippet.

### GitLab CI

```yaml
image: alpine:3.21
before_script:
  - apk add --no-cache git curl tar
  - curl -fsSL -o /tmp/git-nest.tar.gz \
      https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
  - mkdir -p ~/.local/share/git-nest
  - tar -xzf /tmp/git-nest.tar.gz -C ~/.local/share/git-nest
  - export PATH="$HOME/.local/share/git-nest/bin:$PATH"
script:
  - git-nest restore
  - git-nest verify
```

Notes:
- Pick an image that has bash (or sh) + git; alpine is small but needs the
  apk line. Debian image needs `apt-get install -y git curl`.
- `before_script` lines share state via the shell, so the `export PATH`
  applies to `script`.
- The repo's own Docker cross-shell runner image could double as a CI
  image with git-nest preinstalled (recommendation, see below).

### Gitea Actions

Gitea Actions is GitHub-Actions-compatible (act runner). Use the same YAML
as GitHub Actions:

```yaml
runs-on: ubuntu-latest
steps:
  - uses: actions/checkout@v4
  - run: |
      curl -fsSL -o /tmp/git-nest.tar.gz \
        https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
      mkdir -p "$HOME/.local/share/git-nest"
      tar -xzf /tmp/git-nest.tar.gz -C "$HOME/.local/share/git-nest"
      echo "$HOME/.local/share/git-nest/bin" >> "$GITHUB_PATH"
  - run: git-nest restore && git-nest verify
```

Note: `actions/checkout@v4` is mirrored in Gitea's action marketplace; a
self-hosted act runner needs network access to github.com (or a mirror) for
the download. Private Gitea instances should host the release tarball
locally (Gitea has Releases too) and point the URL there.

### Jenkins

Jenkins has two project types: **Pipelines** (the modern, code-as-config
Jenkinsfile) and **freestyle projects** (the classic point-and-click job
type with per-build steps). Both are common in existing Jenkins
installations, so git-nest should work with both.

#### Pipeline (Jenkinsfile, Declarative)

```groovy
pipeline {
  agent any
  stages {
    stage('Install git-nest') {
      steps {
        sh '''
          curl -fsSL -o /tmp/git-nest.tar.gz \
            https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
          mkdir -p "$HOME/.local/share/git-nest"
          tar -xzf /tmp/git-nest.tar.gz -C "$HOME/.local/share/git-nest"
          export PATH="$HOME/.local/share/git-nest/bin:$PATH"
          git-nest restore
          git-nest verify
        '''
      }
    }
  }
}
```

Notes:
- One `sh` block keeps the `export PATH` in scope; separate `sh` steps lose
  it (Jenkins does not persist env between steps unless you use `env` or a
  credentials/environment binding).
- Windows agents: use `bat`/`powershell` steps with the `.bat`/`.ps1`
  launchers.
- A Docker-based agent (`agent { docker { image '...' } }`) with git-nest
  preinstalled is the cleanest option for Jenkins.

#### Freestyle project (legacy, point-and-click)

A freestyle job has build steps instead of a Jenkinsfile. Add one or two
**"Execute shell"** build steps (Unix) or **"Execute Windows batch
command"** steps (Windows):

```sh
# Build step 1: install git-nest and restore
curl -fsSL -o /tmp/git-nest.tar.gz \
  https://github.com/f-steff/git-nest/releases/download/v0.8.16/git-nest-v0.8.16.tar.gz
mkdir -p "$HOME/.local/share/git-nest"
tar -xzf /tmp/git-nest.tar.gz -C "$HOME/.local/share/git-nest"
export PATH="$HOME/.local/share/git-nest/bin:$PATH"
git-nest restore
git-nest verify
```

Freestyle specifics:
- There is no `env`/`export` persistence between build steps either, so
  either keep the install + restore + verify in a single "Execute shell"
  step, or configure the job's **Global properties -> Environment
  variables** (or the workspace PATH) to include
  `$HOME/.local/share/git-nest/bin`.
- Environment variables from the job config (including secrets) are
  available as plain variables in the shell step.
- Git plugin is not needed for subprojects; git-nest calls git directly.

## Credentials for private subproject remotes

Subproject remotes may be private. git-nest delegates to `git`, so
credential handling is standard git behavior; CI just needs to make
credentials available to git:

| CI | Mechanism |
|----|-----------|
| GitHub Actions | `GITHUB_TOKEN` works for github.com remotes: `git config --global credential.helper "!f() { echo username=x-access-token; echo password=${GITHUB_TOKEN}; }; f"` (scope: contents: read on the subproject repos) |
| Azure Pipelines | `System.AccessToken` or a PAT stored as a secret; configure a git credential helper or use `extraheader` on http.extraheader |
| GitLab | `CI_JOB_TOKEN` (own instance) or deploy tokens; `git config` credential helper |
| Jenkins | Credentials Binding plugin: `withCredentials([usernamePassword(credentialsId:'x', usernameVariable:'U', passwordVariable:'P')])` + git credential helper (Pipeline); in freestyle jobs, add the credential as an environment variable in the job config |
| Gitea | Token in `GITEA_TOKEN` secret + credential helper, or a `.netrc` written by the pipeline |

A generic approach that works almost everywhere: write a `.netrc` from
secrets before restore (git reads `~/.netrc` for https remotes):

```sh
printf 'machine github.com\nlogin x-access-token\npassword %s\n' "$TOKEN" > ~/.netrc
chmod 600 ~/.netrc
```

## Recommended distribution artifacts for CI

To make these snippets one-liners and robust:

1. **`setup-git-nest` GitHub Action** (f-steff/setup-git-nest) -- version
   input, installs into the runner, optionally caches. The primary
   GitHub-native distribution for consumers.
2. **CI-ready Docker image** (e.g. `ghcr.io/f-steff/git-nest:0.8.16` and
   `:latest`) with git-nest preinstalled on a small image (alpine + git).
   Usable by GitLab (`image:`), Jenkins docker agents, and Gitea runners
   alike. Tags per version = reproducible CI.
3. **Versioned tarball naming convention**:
   `git-nest-<version>.tar.gz` (already proposed) with a matching
   `SHA256SUMS` so CI can pin + verify:
   ```sh
   curl -fsSL .../SHA256SUMS | grep git-nest-v0.8.16.tar.gz | sha256sum -c -
   ```
4. **Windows note**: the tarball installs fine on Windows runners via Git
   Bash (`tar` is present in Git for Windows); the `.ps1` launcher covers
   pwsh-only agents.

## Code signing (shell tool) for CI agents

CI agents are **not users**: they do not click through SmartScreen or
Gatekeeper, and they run unattended. Signing requirements therefore differ
from end-user distribution:

- **GitHub/Azure/GitLab-hosted agents**: download the tarball over HTTPS
  and verify `SHA256SUMS`; no signing is needed. The pinned version +
  checksum is the trust model.
- **Self-hosted agents (Jenkins, private Gitea, corporate runners)**: the
  agent image is pre-built by your team; git-nest is either baked into the
  image (trust comes from your image pipeline) or installed per-run over
  HTTPS with checksum verification. No executable signing applies to the
  shell payload.
- **Docker image**: the image digest (sha256) is the trust anchor
  (`ghcr.io/f-steff/git-nest@sha256:...`). Pinning the digest is stronger
  than a tag and is the CI-recommended practice. No signature required;
  GHCR optionally supports cosign signing if you want supply-chain
  attestation (nice-to-have, not required by any CI).
- Bottom line: **agents need zero code signing** for the shell tool; the
  discipline is pinned versions + checksum/digest verification.

## Open questions

- Should the Docker image be `alpine` (small, needs git) or `debian`?
  Alpine saves ~100 MB; git + git-nest fit easily.
- Do consumers prefer a versioned image tag per release, or just
  `latest` + the action? Recommend both (tag + latest).
- Should `setup-git-nest` support Gitea self-hosted (custom base URL)?
  Nice-to-have; keep the GitHub URL configurable.
- Caching strategy for subproject clones in each CI system (actions/cache,
  GitLab cache:, Azure pipeline cache task, Jenkins stash) -- document
  per-system recipes once the action exists.
- Supply-chain attestation: is cosign signing of the Docker image and/or
  a SLSA provenance attestation on releases worth it for CI consumers?
  (No CI requires it today; only matters for high-trust environments.)
- Agent pre-baking: should we publish a "git-nest agent image" variant
  (git-nest + git + minimal shells) for Jenkins/Gitea self-hosted users,
  separate from the end-user image?
