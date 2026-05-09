"""Per-platform `crank` binary repos.

Each repo downloads one `crank` binary, marks it executable, and
exposes it via a toolchain. The toolchain's `target_compatible_with`
matches the platform constraints so Bazel auto-selects the right
binary at build time.
"""

load("//private:versions.bzl", "CRANK_VERSIONS", "PLATFORM_CONSTRAINTS")

_BUILD_TMPL = """\
load("@rules_crossplane//private:crank_toolchain.bzl", "crank_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["crank"])

crank_toolchain(
    name = "crank_impl",
    crank = ":crank",
    version = "{version}",
)

toolchain(
    name = "toolchain",
    toolchain_type = "@rules_crossplane//:crank_toolchain_type",
    target_compatible_with = {compat},
    toolchain = ":crank_impl",
)
"""

def _impl(rctx):
    version = rctx.attr.version
    platform = rctx.attr.platform
    if version not in CRANK_VERSIONS:
        fail("rules_crossplane: unknown crank version '{}'. Known: {}".format(
            version,
            sorted(CRANK_VERSIONS.keys()),
        ))
    if platform not in PLATFORM_CONSTRAINTS:
        fail("rules_crossplane: unknown platform '{}'. Known: {}".format(
            platform,
            sorted(PLATFORM_CONSTRAINTS.keys()),
        ))
    pin = CRANK_VERSIONS[version][platform]
    rctx.download(
        url = pin["url"],
        sha256 = pin["sha256"],
        executable = True,
        output = "crank",
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD_TMPL.format(
        version = version,
        compat = repr(PLATFORM_CONSTRAINTS[platform]),
    ))

crank_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "version":  attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)
