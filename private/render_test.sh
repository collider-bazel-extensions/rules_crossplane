#!/usr/bin/env bash
# Generated launcher for crossplane_render_test.
#
# Resolves the crank binary + inputs out of runfiles, runs
# `crank render`, and asserts the output's `kind:` lines match
# the expected list (and/or matches a golden file).
set -euo pipefail

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi

# Inputs baked in by the rule:
CRANK_REL="{CRANK}"
COMPOSITE_REL="{COMPOSITE}"
COMPOSITION_REL="{COMPOSITION}"
FUNCTIONS_REL=({FUNCTIONS})
EXPECTED_KINDS=({EXPECTED_KINDS})
GOLDEN_REL="{GOLDEN}"

# Resolve runfiles. crank lives in an external repo (e.g.
# `crank_v2_2_1_linux_amd64`); the others typically in `_main`.
_resolve() {
  local rel="$1"
  for cand in \
    "${RUNFILES_DIR}/_main/${rel}" \
    "${RUNFILES_DIR}/${rel}" \
    "${RUNFILES_DIR}/_main/external/${rel}"; do
    [[ -e "$cand" ]] && { echo "$cand"; return 0; }
  done
  # Last resort: search runfiles for the tail filename.
  local tail
  tail="$(basename "$rel")"
  local hit
  hit="$(find "${RUNFILES_DIR}" -name "$tail" -type f 2>/dev/null | head -1)"
  [[ -n "$hit" ]] && { echo "$hit"; return 0; }
  return 1
}

CRANK="$(_resolve "$CRANK_REL")" || { echo "render_test: crank not in runfiles ($CRANK_REL)" >&2; exit 1; }
COMPOSITE="$(_resolve "$COMPOSITE_REL")" || { echo "render_test: composite not in runfiles" >&2; exit 1; }
COMPOSITION="$(_resolve "$COMPOSITION_REL")" || { echo "render_test: composition not in runfiles" >&2; exit 1; }

FUNCTIONS=()
for f in "${FUNCTIONS_REL[@]}"; do
  resolved="$(_resolve "$f")" || { echo "render_test: function not in runfiles: $f" >&2; exit 1; }
  FUNCTIONS+=("$resolved")
done

# Run crank render. Output to stdout; capture for assertion.
echo "render_test: crank render <composite> <composition> <functions...>"
echo "    composite:   $COMPOSITE"
echo "    composition: $COMPOSITION"
for f in "${FUNCTIONS[@]}"; do echo "    function:    $f"; done

OUTPUT="$("$CRANK" render "$COMPOSITE" "$COMPOSITION" "${FUNCTIONS[@]}")" || {
  rc=$?
  echo "render_test: FAIL — crank render exited $rc" >&2
  exit 1
}

# Kind assertions. Each expected kind must appear in the output as
# a `kind: <name>` line. crank emits multiple YAML documents (one
# per rendered resource) separated by `---`.
if [[ "${#EXPECTED_KINDS[@]}" -gt 0 ]]; then
  fail=0
  for k in "${EXPECTED_KINDS[@]}"; do
    if ! grep -qE "^kind: ${k}\$" <<<"$OUTPUT"; then
      echo "render_test: FAIL — expected kind '$k' not found in rendered output" >&2
      fail=1
    fi
  done
  if (( fail )); then
    echo "---- rendered output ----" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
fi

# Golden file diff (optional).
if [[ -n "$GOLDEN_REL" ]]; then
  GOLDEN="$(_resolve "$GOLDEN_REL")" || { echo "render_test: golden not in runfiles" >&2; exit 1; }
  if ! diff -u "$GOLDEN" <(printf '%s\n' "$OUTPUT") >&2; then
    echo "render_test: FAIL — rendered output differs from golden" >&2
    echo "  Update with: bazel run <test>_update_golden  (not yet implemented)" >&2
    echo "  Or manually: bazel test ... and copy stdout into the golden file." >&2
    exit 1
  fi
fi

echo "render_test: OK"
