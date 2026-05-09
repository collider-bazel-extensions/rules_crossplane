"""Pinned `crank` (Crossplane CLI) binaries.

The `crank` binary is published per Crossplane release at
`releases.crossplane.io/stable/<version>/bin/<platform>/crank`. Each
platform binary is sha256-pinned per version. To bump:
  1. Add a new entry under CRANK_VERSIONS.
  2. `curl -sLfo /tmp/crank https://releases.crossplane.io/stable/<v>/bin/<plat>/crank`
     for each platform; `sha256sum /tmp/crank`.
  3. Add the version tag in MODULE.bazel via `crossplane.version()`.
"""

CRANK_VERSIONS = {
    "v2.2.1": {
        "linux_amd64": {
            "url": "https://releases.crossplane.io/stable/v2.2.1/bin/linux_amd64/crank",
            "sha256": "9a1985e5c132433448d10e399b85960acf11ad57d296059ea6bd8f3aa28d6e3d",
        },
        "linux_arm64": {
            "url": "https://releases.crossplane.io/stable/v2.2.1/bin/linux_arm64/crank",
            "sha256": "9be2570ffcbd0cdb481c89980a3102efb65f4d7db97a8921fd34fafd417514ec",
        },
        "darwin_amd64": {
            "url": "https://releases.crossplane.io/stable/v2.2.1/bin/darwin_amd64/crank",
            "sha256": "f8e3975b584a2f42e450b356bb4b293a9c388292d20102e8e055f993d3fb48fd",
        },
        "darwin_arm64": {
            "url": "https://releases.crossplane.io/stable/v2.2.1/bin/darwin_arm64/crank",
            "sha256": "bb731a6f804ffedc676f7b485d738685a6a116cd67f25717d8e10a91e913eece",
        },
    },
}

PLATFORM_CONSTRAINTS = {
    "linux_amd64":  ["@platforms//os:linux",  "@platforms//cpu:x86_64"],
    "linux_arm64":  ["@platforms//os:linux",  "@platforms//cpu:aarch64"],
    "darwin_amd64": ["@platforms//os:macos",  "@platforms//cpu:x86_64"],
    "darwin_arm64": ["@platforms//os:macos",  "@platforms//cpu:aarch64"],
}
