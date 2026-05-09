#!/usr/bin/env bash
# Maintainer flow:
#   1. Edit tools/versions.bzl::CROSSPLANE_CHART_VERSIONS.
#   2. Add a `helm_template` + `sh_binary` block in tools/BUILD.bazel.
#   3. bash tools/render_crossplane.sh <chart-version>
set -euo pipefail

VERSION="${1:?usage: tools/render_crossplane.sh <chart-version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_crossplane] $TARGET"
exec bazel run "$TARGET"
