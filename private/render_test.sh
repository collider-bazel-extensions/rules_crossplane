#!/usr/bin/env bash
# Generated launcher for crossplane_render_test.
#
# Resolves the crank binary + inputs out of runfiles, runs
# `crank render`, and asserts the output's `kind:` lines match
# the expected list (and/or matches a golden file).
#
# crank runs each Function as a Docker container and does not label
# them, and a killed crank never reaches its own cleanup. So the
# launcher names every Function's container after this run
# (render.crossplane.io/runtime-docker-name), removes the run's
# containers on exit and on SIGTERM/SIGINT/SIGHUP, and at start sweeps
# containers left by runs whose process is gone (SIGKILL).
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
REQUIRED_RESOURCES_REL=({REQUIRED_RESOURCES})
OBSERVED_RESOURCES_REL=({OBSERVED_RESOURCES})
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

WORK="${TEST_TMPDIR:-$(mktemp -d)}/crossplane_render"
rm -rf "$WORK"
mkdir -p "$WORK"

# ---- Function containers ----------------------------------------------------

# The Docker endpoint crank uses (the Docker client's FromEnv default).
# The cleanup CLI is pointed at the same endpoint, whatever its context.
DOCKER_ENDPOINT="${DOCKER_HOST:-unix:///var/run/docker.sock}"
if command -v docker >/dev/null 2>&1; then
  _ctr() { docker -H "$DOCKER_ENDPOINT" "$@"; }
elif command -v podman >/dev/null 2>&1; then
  _ctr() { podman --url "$DOCKER_ENDPOINT" "$@"; }
else
  echo "render_test: WARNING: no docker or podman CLI; function containers will not be cleaned up" >&2
  _ctr() { return 127; }
fi

NAME_PREFIX="rules-crossplane-render"

# Field 22 of /proc/<pid>/stat (start time in clock ticks since boot),
# parsed after the last ")" because comm may contain spaces.
_start_time() {
  local stat fields
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  stat="${stat##*) }"
  read -r -a fields <<<"$stat"
  echo "${fields[19]}"
}

# Run id: boot id + pid namespace + pid + start time. A container whose
# run id names this boot and pid namespace but no live process with that
# start time is a leftover. Without /proc (macOS) there is no sweep.
BOOT="" PIDNS=""
if [[ -r /proc/sys/kernel/random/boot_id && -r "/proc/$$/stat" ]]; then
  BOOT="$(< /proc/sys/kernel/random/boot_id)"
  BOOT="${BOOT//-/}"
  BOOT="${BOOT:0:8}"
  PIDNS="$(readlink "/proc/$$/ns/pid" 2>/dev/null || true)"
  PIDNS="${PIDNS//[!0-9]/}"
fi
if [[ -n "$BOOT" && -n "$PIDNS" ]]; then
  RUN_PREFIX="$NAME_PREFIX-$BOOT-$PIDNS-$$-$(_start_time $$)"
else
  BOOT=""
  RUN_PREFIX="$NAME_PREFIX-x-$$-$(date +%s)$RANDOM"
fi

_sweep_stale_containers() {
  [[ -n "$BOOT" ]] || return 0
  local n stale=()
  while IFS= read -r n; do
    n="${n#/}"
    [[ "$n" =~ ^$NAME_PREFIX-([0-9a-f]{8})-([0-9]+)-([0-9]+)-([0-9]+)-[0-9]+$ ]] || continue
    [[ "${BASH_REMATCH[1]}" == "$BOOT" && "${BASH_REMATCH[2]}" == "$PIDNS" ]] || continue
    [[ "$(_start_time "${BASH_REMATCH[3]}" 2>/dev/null)" == "${BASH_REMATCH[4]}" ]] && continue
    stale+=("$n")
  done < <(_ctr ps -a --filter "name=^$NAME_PREFIX-" --format '{{.Names}}' 2>/dev/null || true)
  if (( ${#stale[@]} )); then
    echo "render_test: removing ${#stale[@]} function container(s) left by earlier runs" >&2
    _ctr rm -f "${stale[@]}" >/dev/null 2>&1 || true
  fi
}

_remove_run_containers() {
  local ids
  ids="$(_ctr ps -aq --filter "name=^$RUN_PREFIX-" 2>/dev/null)" || return 0
  [[ -n "$ids" ]] || return 0
  # shellcheck disable=SC2086 # one id per word
  _ctr rm -f $ids >/dev/null 2>&1 || true
}

CRANK_PID=""
_cleanup() {
  if [[ -n "$CRANK_PID" ]] && kill -0 "$CRANK_PID" 2>/dev/null; then
    # Stop crank first so it cannot start a container after the removal.
    kill -TERM "$CRANK_PID" 2>/dev/null || true
    for _ in $(seq 50); do
      kill -0 "$CRANK_PID" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$CRANK_PID" 2>/dev/null || true
    wait "$CRANK_PID" 2>/dev/null || true
  fi
  _remove_run_containers
}
trap _cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

_sweep_stale_containers

# Copy the Function YAML into $WORK/functions, setting on every
# `kind: Function` document
#   render.crossplane.io/runtime-docker-name:    <RUN_PREFIX>-<n>
#   render.crossplane.io/runtime-docker-cleanup: Remove
# (replacing any value already set). metadata and annotations must be
# block-style mappings; an empty `annotations: {}` is accepted.
_annotate_functions() {
  awk -v prefix="$RUN_PREFIX" -v idx="$1" -v file="$2" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function content(s) { return s !~ /^[ \t]*(#.*)?$/ }
    function sp(k,   s) { s = ""; while (k-- > 0) s = s " "; return s }
    function die(msg) {
      printf "render_test: %s: %s\n", file, msg > "/dev/stderr"
      failed = 1
      exit 1
    }
    function flush(   i, j, m, mi, a, ai, end, fn, rest, at, ins) {
      if (n == 0) return
      m = 0; fn = 0
      for (i = 1; i <= n; i++) {
        if (buf[i] ~ /^metadata:[ \t]*(#.*)?$/) m = i
        else if (buf[i] ~ /^metadata:/) die("metadata must be a block mapping to set function annotations")
        if (buf[i] ~ /^kind:[ \t]*["\047]?Function["\047]?[ \t]*(#.*)?$/) fn = 1
      }
      if (fn && !m) die("Function document has no metadata")
      if (fn) {
        mi = 0
        for (j = m + 1; j <= n; j++) {
          if (!content(buf[j])) continue
          if (indent(buf[j]) == 0) break
          if (!mi) mi = indent(buf[j])
        }
        end = j - 1
        if (!mi) mi = 2
        a = 0
        for (j = m + 1; j <= end; j++)
          if (indent(buf[j]) == mi && substr(buf[j], mi + 1) ~ /^annotations:/) { a = j; break }
        idx++
        ins = "render.crossplane.io/runtime-docker-name: \"" prefix "-" idx "\""
        rest = "render.crossplane.io/runtime-docker-cleanup: \"Remove\""
        if (a) {
          at = substr(buf[a], mi + 1)
          if (at ~ /^annotations:[ \t]*\{[ \t]*\}[ \t]*(#.*)?$/) buf[a] = sp(mi) "annotations:"
          else if (at !~ /^annotations:[ \t]*(#.*)?$/) die("metadata.annotations must be a block mapping")
          ai = 0
          for (j = a + 1; j <= end; j++) {
            if (!content(buf[j])) continue
            if (indent(buf[j]) <= mi) break
            if (!ai) ai = indent(buf[j])
            if (buf[j] ~ /^[ \t]*["\047]?render\.crossplane\.io\/runtime-docker-(name|cleanup)["\047]?[ \t]*:/) drop[j] = 1
          }
          if (!ai) ai = 2 * mi
          at = a
          ins = sp(ai) ins "\n" sp(ai) rest
        } else {
          at = m
          ins = sp(mi) "annotations:\n" sp(2 * mi) ins "\n" sp(2 * mi) rest
        }
      }
      for (i = 1; i <= n; i++) {
        if (!drop[i]) print buf[i]
        if (fn && i == at) print ins
      }
      n = 0
      split("", drop)
    }
    /^---/ { flush(); print; next }
    { buf[++n] = $0 }
    END { if (!failed) flush() }
  '
}

mkdir -p "$WORK/functions"
i=0
for f in "${FUNCTIONS_REL[@]}"; do
  resolved="$(_resolve "$f")" || { echo "render_test: function not in runfiles: $f" >&2; exit 1; }
  i=$((i + 1))
  out="$WORK/functions/$(printf '%03d' "$i")-$(basename "$resolved")"
  # Container numbers continue across files.
  n="$(cat "$WORK"/functions/* 2>/dev/null | grep -c "runtime-docker-name: \"$RUN_PREFIX-" || true)"
  _annotate_functions "$n" "$f" <"$resolved" >"$out" || exit 1
done

# crank takes one path for each of these; several files go in a directory.
_stage() {
  local dir="$WORK/$1" i=0 f resolved
  shift
  mkdir -p "$dir"
  for f in "$@"; do
    resolved="$(_resolve "$f")" || { echo "render_test: not in runfiles: $f" >&2; return 1; }
    i=$((i + 1))
    cp "$resolved" "$dir/$(printf '%03d' "$i")-$(basename "$resolved")"
  done
}

CRANK_FLAGS=()
if (( ${#REQUIRED_RESOURCES_REL[@]} )); then
  _stage required_resources "${REQUIRED_RESOURCES_REL[@]}"
  CRANK_FLAGS+=("--required-resources=$WORK/required_resources")
fi
if (( ${#OBSERVED_RESOURCES_REL[@]} )); then
  _stage observed_resources "${OBSERVED_RESOURCES_REL[@]}"
  CRANK_FLAGS+=("--observed-resources=$WORK/observed_resources")
fi
# The test's `args` are passed through to crank.
CRANK_FLAGS+=("$@")

# Run crank render. Output to a file; captured for assertion.
echo "render_test: crank render <composite> <composition> <functions> ${CRANK_FLAGS[*]}"
echo "    composite:   $COMPOSITE"
echo "    composition: $COMPOSITION"
for f in "${FUNCTIONS_REL[@]}"; do echo "    function:    $f"; done
echo "    containers:  $RUN_PREFIX-<n>"

# In the background so a signal reaches the trap while crank runs.
"$CRANK" render "$COMPOSITE" "$COMPOSITION" "$WORK/functions" "${CRANK_FLAGS[@]}" \
  >"$WORK/output.yaml" </dev/null &
CRANK_PID=$!
rc=0
wait "$CRANK_PID" || rc=$?
CRANK_PID=""
if (( rc != 0 )); then
  echo "render_test: FAIL — crank render exited $rc" >&2
  exit 1
fi
OUTPUT="$(< "$WORK/output.yaml")"

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
