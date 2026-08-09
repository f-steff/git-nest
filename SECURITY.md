---
layout: default
title: Security Policy
nav_order: 8
---

# Security Policy

## Supported Versions

Security fixes are provided for the latest released version. Older versions
are not supported -- upgrade to the current release if you need a fix.

The latest release is published on this repository's
[Releases](https://github.com/f-steff/git-nest/releases) page.

## Reporting a Vulnerability

If you discover a security vulnerability in git-nest, please report it
privately. Do **not** open a public issue.

Go to the **Security** tab on this repository and click
**Report a vulnerability**. This opens a private advisory where we can
discuss and resolve the issue safely.

### What to include

- A clear description of the vulnerability and its impact.
- Steps to reproduce -- a minimal manifest, shell command, or environment
  setup that triggers the issue.
- The affected version (run `git nest version`).
- Any suggested fixes, if available.

### What to expect

- **Acknowledgment**: within 48 hours.
- **Assessment**: within one week -- we will confirm the vulnerability and
  its severity.
- **Fix**: a patch release will be published before public disclosure.
  You will be credited in the release notes unless you request anonymity.

## Scope

Security reports are welcome for:

- **Command injection** -- subproject paths, URLs, or manifest fields that
  could execute arbitrary commands.
- **Path traversal** -- escape from the nest root or access files outside
  the workspace.
- **Manifest spoofing** -- crafted `.gitnest` entries that could mislead
  restore, snapshot, or absorb operations.
- **Hook abuse** -- managed Git hooks that could execute unintended code.

Out of scope: issues in third-party tools (Git, tar, Python, zip) that
git-nest delegates to; those should be reported to those projects directly.
