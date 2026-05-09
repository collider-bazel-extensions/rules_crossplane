#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
INSTALL_BIN="${RUNFILES_DIR}/_main/tests/crossplane_install_bin.sh"
[[ -x "$INSTALL_BIN" ]] || { echo "wrapper: crossplane_install_bin not at $INSTALL_BIN" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

on_install_fail() {
  local rc=$?
  echo "===== install_wrapper: install_bin exited $rc — dumping cluster state =====" >&2
  echo "---- pods/deploy (-n crossplane-system) ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n crossplane-system get pods,deploy -o wide >&2 || true
  echo "---- describe deploy/crossplane ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n crossplane-system describe deploy/crossplane >&2 || true
  echo "---- crossplane logs (--tail=200) ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n crossplane-system logs deploy/crossplane --tail=200 >&2 || true
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n crossplane-system logs deploy/crossplane --previous --tail=200 >&2 || true
  echo "---- rbac-manager logs (--tail=80) ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n crossplane-system logs deploy/crossplane-rbac-manager --tail=80 >&2 || true
  exit "$rc"
}
trap on_install_fail ERR

"$INSTALL_BIN"
