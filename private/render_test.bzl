"""crossplane_render_test rule: hermetic `crank render` test.

Runs `crank render <composite> <composition> <functions>` in the
test action and asserts the rendered output's `kind:` lines match
the expected list. Optional golden-file mode compares full output
against a checked-in expected.yaml.

Composition Functions are pulled and run via Docker by default
(crank's contract). Tests using this rule must have access to a
Docker daemon — tag the rule call with `tags = ["requires-docker",
"no-sandbox"]` (see README quickstart). The launcher names each
Function's container after the run and removes the run's containers
on exit, on SIGTERM/SIGINT/SIGHUP, and (for SIGKILLed runs) at the
start of a later run.

The test's `args` are passed to `crank render` after the positional
arguments; `$(rootpath ...)` works for labels in `data`. For fully-hermetic
function execution (no Docker), use crank's `runtime: Development`
mode and run the function as a separate process; this rule
doesn't bundle that flow.
"""

def _quoted(items):
    return " ".join(["'" + s.replace("'", "'\\''") + "'" for s in items])

def _impl(ctx):
    tc = ctx.toolchains["@rules_crossplane//:crank_toolchain_type"]
    crank = tc.crankinfo.crank

    # Stage the launcher with the inputs baked in.
    out = ctx.actions.declare_file(ctx.label.name + ".sh")

    function_paths = _quoted([f.short_path for f in ctx.files.functions])
    required_resources = _quoted([f.short_path for f in ctx.files.required_resources])
    observed_resources = _quoted([f.short_path for f in ctx.files.observed_resources])
    expected_kinds = _quoted(ctx.attr.expected_kinds)
    golden_path = ctx.file.golden.short_path if ctx.file.golden else ""

    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = out,
        substitutions = {
            "{CRANK}":          crank.short_path,
            "{COMPOSITE}":      ctx.file.composite.short_path,
            "{COMPOSITION}":    ctx.file.composition.short_path,
            "{FUNCTIONS}":      function_paths,
            "{REQUIRED_RESOURCES}": required_resources,
            "{OBSERVED_RESOURCES}": observed_resources,
            "{EXPECTED_KINDS}": expected_kinds,
            "{GOLDEN}":         golden_path,
        },
        is_executable = True,
    )

    runfiles_files = [
        crank,
        ctx.file.composite,
        ctx.file.composition,
    ] + ctx.files.functions + ctx.files.required_resources + \
        ctx.files.observed_resources + ctx.files.data
    if ctx.file.golden:
        runfiles_files.append(ctx.file.golden)

    return [DefaultInfo(
        executable = out,
        runfiles = ctx.runfiles(files = runfiles_files),
    )]

crossplane_render_test = rule(
    implementation = _impl,
    test = True,
    attrs = {
        "composite": attr.label(
            mandatory = True,
            allow_single_file = [".yaml", ".yml"],
            doc = "The XR (composite resource) YAML to render.",
        ),
        "composition": attr.label(
            mandatory = True,
            allow_single_file = [".yaml", ".yml"],
            doc = "The Composition YAML.",
        ),
        "functions": attr.label_list(
            mandatory = True,
            allow_files = [".yaml", ".yml"],
            doc = "Composition Functions (one or more YAML files). " +
                  "They are copied into one directory, passed to " +
                  "`crank render` after the composition argument, with " +
                  "the `render.crossplane.io/runtime-docker-name` and " +
                  "`runtime-docker-cleanup` annotations set on every " +
                  "Function (`metadata` must be block-style YAML).",
        ),
        "required_resources": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Optional YAML files passed as `--required-resources` " +
                  "(resources Functions request, e.g. EnvironmentConfigs " +
                  "for function-environment-configs). Several files are " +
                  "staged into one directory.",
        ),
        "observed_resources": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Optional YAML files passed as `--observed-resources` " +
                  "(observed state of composed resources).",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Extra runfiles, e.g. files named in `args` with " +
                  "`$(rootpath ...)` (`--xrd`, `--function-credentials`, " +
                  "`--context-files`).",
        ),
        "expected_kinds": attr.string_list(
            doc = "Optional list of expected `kind:` values in the " +
                  "rendered output. The test asserts each appears at " +
                  "least once. Empty list = no kind assertion.",
        ),
        "golden": attr.label(
            allow_single_file = [".yaml", ".yml"],
            doc = "Optional golden file. If set, the full rendered output " +
                  "is diff'd against this file and any difference fails the " +
                  "test. Combine with `expected_kinds` for both checks.",
        ),
        "_launcher": attr.label(
            default = "@rules_crossplane//private:render_test.sh",
            allow_single_file = True,
        ),
    },
    toolchains = ["@rules_crossplane//:crank_toolchain_type"],
)
