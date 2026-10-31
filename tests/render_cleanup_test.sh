#!/usr/bin/env bash
# Function containers do not outlive crossplane_render_test runs:
#   1. SIGKILLed run (launcher + crank): its containers are left behind,
#      and the next run's start-up sweep removes them.
#   2. SIGTERMed run: the trap removes its containers before it exits.
#   3. Normal run: passes and leaves no containers.
# Runs 1 and 2 use :render_hang, whose render never finishes.
set -euo pipefail

_bin() {
  local f
  f="$(find "${RUNFILES_DIR}" -name "$1.sh" -path '*tests/*' | head -1)"
  [[ -x "$f" ]] || { echo "$1.sh not in runfiles" >&2; exit 1; }
  echo "$f"
}
HANG="$(_bin render_hang)"
RENDER="$(_bin render_smoke)"

DOCKER_ENDPOINT="${DOCKER_HOST:-unix:///var/run/docker.sock}"
if command -v docker >/dev/null 2>&1; then
  ctr() { docker -H "$DOCKER_ENDPOINT" "$@"; }
else
  ctr() { podman --url "$DOCKER_ENDPOINT" "$@"; }
fi

# Names of this host's render containers started by <pid>.
containers_of() {
  ctr ps -a --format '{{.Names}}' | sed 's|^/||' |
    grep -E "^rules-crossplane-render-[0-9a-f]{8}-[0-9]+-$1-[0-9]+-[0-9]+\$" || true
}

wait_for_container() {
  local pid="$1"
  for _ in $(seq 300); do
    [[ -n "$(containers_of "$pid")" ]] && return 0
    kill -0 "$pid" 2>/dev/null || {
      echo "FAIL: run $pid exited before starting a container" >&2
      cat "$TEST_TMPDIR"/*.log >&2
      return 1
    }
    sleep 1
  done
  echo "FAIL: no container for run $pid after 300 s" >&2
  return 1
}

run_dir() { mkdir -p "$TEST_TMPDIR/$1"; echo "$TEST_TMPDIR/$1"; }

# ---- 1. SIGKILL --------------------------------------------------------------
TEST_TMPDIR="$(run_dir killed)" setsid "$HANG" >"$TEST_TMPDIR/killed.log" 2>&1 &
killed=$!
wait_for_container "$killed"
kill -KILL -- "-$killed"
wait "$killed" 2>/dev/null || true
left="$(containers_of "$killed")"
[[ -n "$left" ]] || { echo "FAIL: expected the SIGKILLed run to leave a container" >&2; exit 1; }
echo "PASS: SIGKILLed run $killed left: $left"

# ---- 2. SIGTERM (its start-up sweep also removes run 1's containers) ---------
TEST_TMPDIR="$(run_dir termed)" "$HANG" >"$TEST_TMPDIR/termed.log" 2>&1 &
termed=$!
wait_for_container "$termed"
[[ -z "$(containers_of "$killed")" ]] || { echo "FAIL: sweep left $(containers_of "$killed")" >&2; exit 1; }
echo "PASS: start-up sweep removed run $killed's containers"
kill -TERM "$termed"
rc=0
wait "$termed" || rc=$?
[[ "$rc" == 143 ]] || { echo "FAIL: SIGTERMed run exited $rc, want 143" >&2; cat "$TEST_TMPDIR/termed.log" >&2; exit 1; }
[[ -z "$(containers_of "$termed")" ]] || { echo "FAIL: SIGTERMed run left $(containers_of "$termed")" >&2; exit 1; }
echo "PASS: SIGTERMed run $termed removed its containers"

# ---- 3. Normal run -------------------------------------------------------------
TEST_TMPDIR="$(run_dir normal)" "$RENDER" >"$TEST_TMPDIR/normal.log" 2>&1 &
normal=$!
rc=0
wait "$normal" || rc=$?
[[ "$rc" == 0 ]] || { echo "FAIL: normal run exited $rc" >&2; cat "$TEST_TMPDIR/normal.log" >&2; exit 1; }
[[ -z "$(containers_of "$normal")" ]] || { echo "FAIL: normal run left $(containers_of "$normal")" >&2; exit 1; }
echo "PASS: normal run $normal left no containers"
