"""Toolchain rule + provider for the `crank` Crossplane CLI binary."""

CrankInfo = provider(
    doc = "Holds the path to the `crank` binary.",
    fields = {
        "crank":   "File: the `crank` executable.",
        "version": "string: the Crossplane version this binary is from.",
    },
)

def _impl(ctx):
    return [
        platform_common.ToolchainInfo(
            crankinfo = CrankInfo(
                crank   = ctx.file.crank,
                version = ctx.attr.version,
            ),
        ),
    ]

crank_toolchain = rule(
    implementation = _impl,
    attrs = {
        "crank":   attr.label(allow_single_file = True, mandatory = True),
        "version": attr.string(mandatory = True),
    },
)
