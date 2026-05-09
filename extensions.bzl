"""Module extension for `crank` binary downloads. Fires for every
`crossplane.version()` tag — root or not, since consumers' tests
need access to the toolchain too.
"""

load("//private:repositories.bzl", "crank_repository")
load("//private:versions.bzl", "CRANK_VERSIONS", "PLATFORM_CONSTRAINTS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _slug(v):
    return v.replace(".", "_").replace("-", "_")

def _impl(mctx):
    seen = {}
    for mod in mctx.modules:
        for tag in mod.tags.version:
            if tag.version in seen:
                continue
            seen[tag.version] = True
            if tag.version not in CRANK_VERSIONS:
                fail("rules_crossplane: unknown crank version '{}'. Known: {}".format(
                    tag.version, sorted(CRANK_VERSIONS.keys()),
                ))
            for platform in PLATFORM_CONSTRAINTS.keys():
                crank_repository(
                    name     = "crank_{}_{}".format(_slug(tag.version), platform),
                    version  = tag.version,
                    platform = platform,
                )

crossplane = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
