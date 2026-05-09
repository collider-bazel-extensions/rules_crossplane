#!/usr/bin/env bash
# Crossplane controller smoke. Strategy:
#
#   1. The install_bin upstream has already applied Crossplane and
#      waited for both Deployments Available. Crossplane's controller
#      installs core CRDs (Composition, CompositeResourceDefinition,
#      Function, Provider) at runtime AFTER the Deployment becomes
#      Ready. Poll for one of those CRDs as a sanity check.
#   2. Apply a real Composition CR and verify the admission webhook
#      accepts it. This proves the controller is fully wired up:
#      CRD registered → webhook serving → validation passes → object
#      stored in etcd.
#
# v0.1's smoke does NOT compose XRs into composed resources end-to-end
# — that requires installing a Function package (which pulls a Docker
# image inside the cluster, not on the host) and an XRD. v0.2
# candidate.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

# Sanity: core CRDs registered. The install wait gates on Deployment
# Available; Crossplane registers CRDs early during pod boot, so by the
# time Available fires the CRDs should be there. Poll briefly to
# tolerate the small remaining race window.
echo "smoke_test: waiting for compositions.apiextensions.crossplane.io CRD"
deadline=$(( $(date +%s) + 60 ))
while (( $(date +%s) < deadline )); do
  if "${KCTL[@]}" get crd compositions.apiextensions.crossplane.io >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if ! "${KCTL[@]}" get crd compositions.apiextensions.crossplane.io >/dev/null 2>&1; then
  echo "smoke_test: FAIL — compositions.apiextensions.crossplane.io CRD never registered" >&2
  echo "---- crds in cluster ----" >&2
  "${KCTL[@]}" get crd 2>&1 | head -40 >&2
  exit 1
fi

echo "smoke_test: core CRDs registered (compositions, providers, functions, ...)"
for crd in \
    providers.pkg.crossplane.io \
    functions.pkg.crossplane.io \
    configurations.pkg.crossplane.io \
    compositeresourcedefinitions.apiextensions.crossplane.io; do
  if ! "${KCTL[@]}" get crd "$crd" >/dev/null 2>&1; then
    echo "smoke_test: FAIL — expected CRD '$crd' not registered" >&2
    exit 1
  fi
done

# Apply a real Composition. The admission webhook validates the spec
# (compositeTypeRef, mode, pipeline shape). A trivial-but-real
# Composition should be accepted; reading it back proves storage.
echo "smoke_test: applying a smoke Composition"
"${KCTL[@]}" apply --server-side -f - <<'EOF'
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: smoke-composition
spec:
  compositeTypeRef:
    apiVersion: smoke.example.com/v1alpha1
    kind: XSmoke
  mode: Pipeline
  pipeline:
    - step: noop
      functionRef:
        name: function-patch-and-transform
EOF

# Read it back. spec.mode should be "Pipeline".
mode=$("${KCTL[@]}" get composition smoke-composition -o jsonpath='{.spec.mode}' 2>/dev/null || true)
if [[ "$mode" != "Pipeline" ]]; then
  echo "smoke_test: FAIL — Composition not stored or spec.mode != Pipeline (got: '$mode')" >&2
  "${KCTL[@]}" get composition smoke-composition -o yaml >&2 || true
  exit 1
fi

# Cleanup.
"${KCTL[@]}" delete composition smoke-composition --ignore-not-found >/dev/null 2>&1 || true

echo "smoke_test: OK — Crossplane installed, core CRDs registered, Composition write+read round-tripped"
