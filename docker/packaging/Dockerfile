# git-nest packaging image
#
# A small Alpine image with the tooling needed to build the git-nest
# distribution artifacts. Currently that is the LHA archiver
# (https://github.com/jca02266/lha), used by assemble.sh to create the
# Amiga .lha package. The Alpine `lha` package is built from that
# upstream (lha-1.14.x).
#
# Build (from the repository root):
#   docker build -t git-nest-packaging -f docker/packaging/Dockerfile docker/packaging
#
# assemble.sh builds/uses this image automatically for the Amiga target;
# it replaces the previous per-run `apk add lha` so the tool version is
# pinned by this image and no network install happens on every build.

FROM alpine:3.21

RUN apk add --no-cache lha
