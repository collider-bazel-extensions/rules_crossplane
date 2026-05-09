"""Public API for rules_crossplane.

Two primitives:

  Primitive 1 — `crossplane_render_test`: hermetic `crank render`
  test. Wraps the Crossplane CLI as a Bazel test that asserts a
  Composition + composite + functions render to expected output.
  No cluster needed; Composition Functions run via Docker (mark
  the test `tags = ["requires-docker", "no-sandbox"]`).

  Primitive 2 — `crossplane_install` / `crossplane_health_check`:
  pure glue over rules_kubectl. Installs the pinned Crossplane
  helm chart on a kind cluster (or any cluster) and waits for the
  controller Deployment + rbac-manager Deployment to be Available.
  Drops into `itest_service.exe` / `.health_check`.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")
load("//private:render_test.bzl", _crossplane_render_test = "crossplane_render_test")

crossplane_render_test = _crossplane_render_test

# Crossplane chart 2.2.1 emits two Deployments (`crossplane`
# controller + `crossplane-rbac-manager`). CRDs are NOT installed
# by the chart — the controller registers them at runtime as the
# pod boots. wait_for_deployments transitively gates on this since
# the Deployment becomes Available only after the controller's
# CRD-installer step completes.
_CROSSPLANE_DEPLOYS = [
    "crossplane",
    "crossplane-rbac-manager",
]

def crossplane_install(
        name,
        namespace = "crossplane-system",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Crossplane manifest into `namespace` and
    block until both Crossplane Deployments are Available before
    idling.

    Drops into `itest_service.exe`. The chart hardcodes
    `crossplane-system` in cluster-scoped RoleBindings, so changing
    the namespace requires re-rendering. The macro accepts the
    parameter for symmetry but it's not load-bearing here.

    Crossplane's controller installs core CRDs (Composition,
    CompositeResourceDefinition, Function, Provider, …) at runtime
    after the Deployment becomes Ready. Consumers that apply
    Composition CRs IMMEDIATELY after this install completes can
    race the controller — add a brief poll on
    `compositions.apiextensions.crossplane.io` if needed.
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply(
        name = name,
        manifests = ["@rules_crossplane//private/manifests:crossplane.yaml"],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_deployments = list(_CROSSPLANE_DEPLOYS) + list(extra_deploys),
        wait_for_rollouts = list(extra_rollouts),
        wait_for_crds = list(extra_crds),
        wait_timeout = wait_timeout,
        **kwargs
    )

def crossplane_health_check(
        name,
        namespace = "crossplane-system",
        **kwargs):
    """Readiness probe paired with `crossplane_install`."""
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_deployments = list(_CROSSPLANE_DEPLOYS) + list(extra_deploys),
        wait_for_rollouts = list(extra_rollouts),
        wait_for_crds = list(extra_crds),
        **kwargs
    )
