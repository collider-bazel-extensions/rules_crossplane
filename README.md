# rules_crossplane

Hermetic [Crossplane](https://www.crossplane.io/) rules for Bazel
test compositions. Two primitives, mirroring the family pattern:

- **`crossplane_render_test`** — wraps `crank render` (Crossplane's
  CLI) as a hermetic Bazel test. No cluster needed. Operates on
  local files only: takes a Composition + composite (XR) +
  Function YAML(s), runs `crank render`, asserts the rendered
  output's `kind:` lines match the expected list (and/or matches
  a checked-in golden).
- **`crossplane_install`** / **`crossplane_health_check`** — pure
  glue over [`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl).
  Installs the pinned Crossplane helm chart and waits for the
  controller + RBAC manager Deployments. Drops into
  `itest_service.exe` / `.health_check`.

```python
load("@rules_crossplane//:defs.bzl",
     "crossplane_render_test",
     "crossplane_install", "crossplane_health_check")

# Primitive 1 — hermetic Composition rendering, no cluster.
crossplane_render_test(
    name = "tenant_render",
    composite = "//.../testdata:valid-xtenant.yaml",
    composition = "//infra/crossplane/compositions/tenant:composition.yaml",
    functions = ["//tools/crossplane/functions:patch-and-transform.yaml"],
    expected_kinds = ["XTenant", "Object", "Cluster", "ExternalSecret"],
    tags = ["requires-docker", "no-sandbox"],   # crank pulls fn images via Docker
)

# Primitive 2 — full controller on a kind cluster.
crossplane_install(name = "crossplane_install_bin")
crossplane_health_check(name = "crossplane_health_bin")
```

**Pinned versions:** Crossplane `v2.2.1` (chart 2.2.1, app 2.2.1).
The `crank` binary is downloaded per platform from
`releases.crossplane.io/stable/<version>/bin/<platform>/crank` —
`linux_amd64`, `linux_arm64`, `darwin_amd64`, `darwin_arm64`, all
sha256-pinned in [`private/versions.bzl`](private/versions.bzl).
The chart is sha256-pinned in [`tools/versions.bzl`](tools/versions.bzl).

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Primitive 1: `crossplane_render_test`](#primitive-1-crossplane_render_test)
- [Primitive 2: `crossplane_install` / `crossplane_health_check`](#primitive-2-crossplane_install--crossplane_health_check)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Help wanted](#help-wanted)

---

## Installation

```python
bazel_dep(name = "rules_crossplane", version = "0.1.0")
```

Bzlmod-only. Transitively pulls in `rules_kubectl` ≥ 0.2.0 and
`rules_shell`.

The crank binary toolchain auto-registers via the module extension —
no manual `crossplane.version()` call needed unless you want a
non-default version.

---

## Primitive 1: `crossplane_render_test`

Hermetic Composition rendering — no cluster required. Wraps
`crank render <composite> <composition> <functions...>` as a
Bazel test.

```python
crossplane_render_test(
    name = "tenant_namespace_render",
    composite = "//infra/.../testdata:valid-xtenant.yaml",
    composition = "//infra/crossplane/compositions/tenant-namespace:composition.yaml",
    functions = [
        "//tools/crossplane/functions:patch-and-transform.yaml",
    ],
    expected_kinds = [
        "Namespace",
        "Cluster",          # postgresql.cnpg.io
        "Policy",           # vault.crossplane.io
        "AuthBackendRole",  # vault.crossplane.io
        "ExternalSecret",   # external-secrets.io
    ],
    # Composition Functions are pulled + run via Docker by crank.
    tags = ["requires-docker", "no-sandbox"],
)
```

### Attributes

| Attribute | Type | Description |
|---|---|---|
| `composite` | `label` (single `.yaml`) | The XR (composite resource) YAML to render. |
| `composition` | `label` (single `.yaml`) | The Composition YAML. |
| `functions` | `label_list` (`.yaml` files) | Composition Function YAML(s). Each is passed positionally to `crank render`. |
| `expected_kinds` | `string_list` | Optional. Each kind must appear in the rendered output as a `kind: <name>` line. Empty = no kind assertion. |
| `golden` | `label` (single `.yaml`, optional) | If set, full rendered output is diff'd against this file. Combine with `expected_kinds` for both checks. |

### Why Docker

`crank render` pulls each Function's `package` Docker image and
runs it in a container to execute the composition pipeline. The
test needs the host's Docker daemon — tag the rule call
`tags = ["requires-docker", "no-sandbox"]` so Bazel's sandbox
doesn't strip docker access.

For fully-hermetic function execution (no Docker) you can use
crank's `runtime: Development` mode and run the function as a
separate process, but this rule doesn't bundle that flow. v0.2
candidate.

### Bumping the crank version

Default is `v2.2.1`. Override via your MODULE.bazel:

```python
crossplane = use_extension("@rules_crossplane//:extensions.bzl", "crossplane")
crossplane.version(version = "v2.3.0")   # also pin sha256s in private/versions.bzl
use_repo(crossplane,
    "crank_v2_3_0_linux_amd64",
    "crank_v2_3_0_linux_arm64",
    "crank_v2_3_0_darwin_amd64",
    "crank_v2_3_0_darwin_arm64",
)
register_toolchains(
    "@crank_v2_3_0_linux_amd64//:toolchain",
    "@crank_v2_3_0_linux_arm64//:toolchain",
    "@crank_v2_3_0_darwin_amd64//:toolchain",
    "@crank_v2_3_0_darwin_arm64//:toolchain",
)
```

To add the version to `private/versions.bzl`, fetch each platform
binary and compute its sha256:

```bash
for plat in linux_amd64 linux_arm64 darwin_amd64 darwin_arm64; do
  curl -sLfo /tmp/crank "https://releases.crossplane.io/stable/v2.3.0/bin/$plat/crank"
  echo "$plat: $(sha256sum /tmp/crank | awk '{print $1}')"
done
```

---

## Primitive 2: `crossplane_install` / `crossplane_health_check`

Full Crossplane controller on a kind (or any) cluster. Pure glue
over `rules_kubectl`.

```python
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_crossplane//:defs.bzl", "crossplane_install", "crossplane_health_check")

kind_cluster(name = "cluster", k8s_version = "1.32")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

crossplane_install(name = "crossplane_install_bin")
crossplane_health_check(name = "crossplane_health_bin")

sh_binary(name = "crossplane_install_wrapper", srcs = ["install_wrapper.sh"], data = [":crossplane_install_bin"])
sh_binary(name = "crossplane_health_wrapper",  srcs = ["health_wrapper.sh"],  data = [":crossplane_health_bin"])

itest_service(
    name = "crossplane_svc",
    exe = ":crossplane_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":crossplane_health_wrapper",
)
```

The wait shape covers two Deployments — `crossplane` (the
controller) and `crossplane-rbac-manager`. Crossplane's controller
installs core CRDs (`Composition`, `CompositeResourceDefinition`,
`Function`, `Provider`, `Configuration`) at runtime *after* its
Deployment becomes Ready.

> **Race window:** `wait_for_deployments = ["crossplane",
> "crossplane-rbac-manager"]` becomes Available the moment the
> pods pass their readiness check, which fires before the
> controller has finished registering CRDs. Consumers that
> immediately apply Composition CRs after the install can race.
> Add a brief poll on `kubectl get crd
> compositions.apiextensions.crossplane.io` if needed (the smoke
> in `tests/smoke_test.sh` shows the pattern).

### Bumping the chart version

Edit [`tools/versions.bzl`](tools/versions.bzl), add a
`helm_template + sh_binary` block in
[`tools/BUILD.bazel`](tools/BUILD.bazel), then:

```bash
bash tools/render_crossplane.sh <new-version>
```

Commit the refreshed `private/manifests/crossplane.yaml`.

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| `crank` binary | Fully hermetic. URL + sha256 pinned per platform. | |
| Crossplane manifest | Fully hermetic. Chart .tgz + sha256 pinned; rendered + committed. | |
| `kubectl` | Inherited from `rules_kubectl`. | |
| Composition Function images | **Pulled at test time via Docker**. Runs on the test host's Docker daemon. | Tag tests `requires-docker`, `no-sandbox`. |
| Crossplane container image | Pulled at runtime by the cluster (Primitive 2 only). `xpkg.crossplane.io/crossplane/crossplane:v2.2.1`. | Future: pre-load via `kind_cluster.images`. |

---

## Help wanted

- macOS validation
- **End-to-end Composition smoke** — install Crossplane + a
  Function + an XRD + a Composition, apply an XR, assert the
  composed resources reconcile (Provider package would need to
  install too — kubernetes provider is the simplest).
- **`runtime: Development` flow for `crossplane_render_test`** —
  no Docker, function runs as a sibling process. Useful in
  fully-hermetic CI environments.
- **`golden` mode auto-update** — `bazel run :foo_update_golden`
  to regenerate the expected output. Currently the rule just
  diffs and fails; manual update.
- **Pre-load function images via `kind_cluster.images`** so the
  controller smoke can install Functions without per-test image
  pulls.
- Compose with [`rules_certmanager`](https://github.com/collider-bazel-extensions/rules_certmanager)
  for Crossplane's optional cert-manager-issued webhook certs
  (currently the chart self-signs).
