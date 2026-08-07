# git-nest agent image (Model A: install-once at the infrastructure level)
#
# A small image with git-nest preinstalled for long-lived CI agents:
# Jenkins agents, Gitea act_runner, GitLab runners, or GitHub self-hosted
# runners. Every job on an agent built from this image can call
# `git-nest` directly with no per-project install step.
#
# Build (from the repository root, so install.sh can find bin/):
#   docker build -t git-nest-agent -f docker/agent-image/Dockerfile .
#
# The image contains git-nest 0.8.16 (whatever bin/git_nest.sh reports at
# build time -- the Dockerfile reads it from the checkout, so the image
# version always matches the source it was built from).

FROM alpine:3.21

RUN apk add --no-cache git bash

# Copy the checkout, install git-nest into /usr/local (bin/ on PATH), then
# drop the checkout so the image stays small.
COPY . /tmp/git-nest-src
RUN sh /tmp/git-nest-src/bin/install.sh --prefix /usr/local \
    && rm -rf /tmp/git-nest-src

# Verify the installed tool is usable and on PATH.
RUN git-nest version \
    && git-nest help >/dev/null

ENTRYPOINT ["/bin/sh"]
