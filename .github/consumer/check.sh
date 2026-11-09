#!/usr/bin/env bash
# Consumer check against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do): tests/ and
# tools/ are not shipped, and @rules_crossplane//... loads and builds for a
# consumer.
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_crossplane"
c="$work/consumer"
rm -rf "$work"; mkdir -p "$src" "$c"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
# rules_kubectl is not in the BCR: pin it as this module does.
kubectl_dep="$(sed -n 's/^bazel_dep(name = "rules_kubectl", version = "\(.*\)")$/\1/p' "$src/MODULE.bazel")"
kubectl_commit="$(grep -A3 'module_name = "rules_kubectl"' "$src/MODULE.bazel" | sed -n 's/.*commit = "\([0-9a-f]*\)".*/\1/p')"
if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
touch "$c/BUILD.bazel"
cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_crossplane")
local_path_override(module_name = "rules_crossplane", path = "$src")
bazel_dep(name = "rules_kubectl", version = "$kubectl_dep")
git_override(
    module_name = "rules_kubectl",
    remote = "https://github.com/collider-bazel-extensions/rules_kubectl",
    commit = "$kubectl_commit",
)
MOD
cd "$c"
bazel query @rules_crossplane//... >/dev/null
echo "PASS: @rules_crossplane//... loads"
bazel build @rules_crossplane//...
echo "PASS: @rules_crossplane//... builds"
