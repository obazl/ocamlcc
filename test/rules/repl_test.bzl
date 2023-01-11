load("@bazel_skylib//lib:paths.bzl", "paths")

load("//bzl:providers.bzl", "BootInfo", "ModuleInfo")

load("//bzl/actions:module_impl.bzl", "module_impl")

# load("//bzl/actions:lambda_expect_impl.bzl", "lambda_expect_impl")

load("//bzl/attrs:executable_attrs.bzl", "executable_attrs")

# load("//bzl/transitions:tc_transitions.bzl", "reset_config_transition")

load("//bzl/transitions:dev_transitions.bzl",
     "dev_tc_compiler_out_transition")

################################################################
# cmd generated by ocamltest:

# /Users/gar/obazl-repository/ocamlcc/.baseline/bin/ocamlrun \
#    /Users/gar/obazl-repository/ocamlcc/ocaml \
#    -noinit -no-version -noprompt \
#    -nostdlib -I ...path...
#    -I bazel-bin/config/camlheaders \
#    -I /Users/gar/obazl-repository/ocamlcc/testsuite/lib \
#    -I /Users/gar/obazl-repository/ocamlcc/toplevel \
#    -w -a lib.cmo
#    t010-const0.ml

##############################
def _repl_test_impl(ctx):

    runner = ctx.actions.declare_file(ctx.file.script.basename + ".test_runner.sh")

    # for rf in ctx.attr._repl[DefaultInfo].default_runfiles.files.to_list():
    #     print("RF: %s" % rf)

    ## Is the repl executable always vm?
    ocamlrun = ctx.attr._repl[DefaultInfo].default_runfiles.files.to_list()[0]

    exe = ctx.attr._repl[DefaultInfo].files_to_run.executable
    print("EXE %s" % exe)

    # _stdlib dirname won't work, we need the short path
    stdlib_dir = paths.dirname(ctx.files._stdlib[0].short_path)
    print("STDLIB path: %s" % stdlib_dir)

    lib_dir = paths.dirname(ctx.file._test_lib.short_path)
    print("LIB path: %s" % lib_dir)

    cmd = "\n".join([
        # "echo SCRIPT path: {};".format(ctx.file.script.path),
        # /Users/gar/obazl-repository/ocamlcc/.baseline/bin/ocamlrun \
        "{} \\".format(ocamlrun.path),
        #    /Users/gar/obazl-repository/ocamlcc/ocaml \
        "{} \\".format(ctx.file._repl.short_path),
        "-noinit -no-version -noprompt \\",
        "-nostdlib \\",
        "-I {} \\".format(stdlib_dir),
        "-I {} \\".format(ctx.files._camlheaders[0].dirname),
        "-I {} \\".format(ctx.file._test_lib.dirname),
        # "-I testsuite/lib/_dev_boot \\",
        "-I {} \\".format(lib_dir),
        "-I {} \\".format(ctx.file._repl.dirname),
        "-I testsuite/lib/_dev_boot \\",
        "-w -a \\",
        # "lib.cmo \\",
        "{} \\".format(ctx.file._test_lib.basename),
        "{}".format(ctx.file.script.path)
    ])

    ctx.actions.write(
        output  = runner,
        content = cmd,
        is_executable = True
    )

    # print("BootInfo: %s" % ctx.attr._stdlib[BootInfo])
    print("LIB: %s" % ctx.attr._test_lib[ModuleInfo].sig)

    myrunfiles = ctx.runfiles(
        files = [
            ctx.file._repl,
            ctx.file.script,
        ],
        transitive_files =  depset(
            transitive = [
                ctx.attr._repl[DefaultInfo].default_runfiles.files,
                ctx.attr._stdlib[BootInfo].cli_link_deps,
                ctx.attr._stdlib[BootInfo].sigs,
                ctx.attr._camlheaders[DefaultInfo].files,
                depset([
                    ctx.attr._test_lib[ModuleInfo].sig,
                    ctx.attr._test_lib[ModuleInfo].struct,
                ])
            ]
        )
    )

    runparams = ""
    for k,v in ctx.attr.runparams.items():
        runparams = runparams + k + "=" + v + ","
    # print("RPS: %s" % runparams)
    env = { "OCAMLRUNPARAM": runparams }

    runEnv = RunEnvironmentInfo(
        environment = env
    )

    defaultInfo = DefaultInfo(
        executable=runner,
        runfiles = myrunfiles
    )

    return [defaultInfo, runEnv]

#######################
repl_test = rule(
    implementation = _repl_test_impl,
    doc = "Compile and test an OCaml program.",
    attrs = dict(
        script = attr.label(
            mandatory = True,
            allow_single_file = True,
        ),

        _repl    = attr.label(
            allow_single_file = True,
            default = "//toplevel:ocaml.byte",
            executable = True,
            cfg = "exec"
        ),

        runparams = attr.string_dict(
            doc = "Parms to be added to OCAMLRUNPARAM"
        ),

        _test_lib = attr.label(
            allow_single_file = True,
            default = "//testsuite/lib:Lib",
            executable = False,
            # so that this lib will be built with same config as repl:
            cfg = "exec"
        ),

        deps = attr.label_list(
            doc = "List of OCaml dependencies.",
            # providers = [[OcamlArchiveProvider],
            #              [OcamlLibraryMarker],
            #              [ModuleInfo],
            #              [CcInfo]],
            # cfg = exe_deps_out_transition,
        ),
        expect = attr.label( # not needed?
            allow_single_file = True,
        ),
        opts             = attr.string_list( ),
        nocopts = attr.bool(
            doc = "to disable use toolchain's copts"
        ),
        _verbose = attr.label(default = "//config/ocaml/link:verbose"),
        warnings         = attr.string_list(
            doc          = "List of OCaml warning options. Will override configurable default options."
        ),

        _runtime = attr.label(
            allow_single_file = True,
            default = "//toolchain:runtime",
            executable = False,
            # cfg = reset_cc_config_transition ## only build once
            # default = "//config/runtime" # label flag set by transition
        ),

        _stdlib = attr.label(
            doc = "Stdlib",
            default = "//stdlib", # archive, not resolver
            # allow_single_file = True, # won't work with boot_library
            cfg = "exec" ## to match _tool_lib and _repl
            # cfg = exe_deps_out_transition,
        ),

        _camlheaders = attr.label(
            doc = "camlheaders",
            default = "//config/camlheaders",
            # allow_single_file = True, # won't work with boot_library
            # cfg = exe_deps_out_transition,
        ),

        _rule = attr.string( default = "repl_test" ),
        # _allowlist_function_transition = attr.label(
        #     default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        # ),
    ),
    # cfg = reset_config_transition,
    # cfg = "exec",
    # cfg = dev_tc_compiler_out_transition,
    test = True,
    fragments = ["cpp"],
    toolchains = ["//toolchain/type:ocaml",
                  ## //toolchain/type:profile,",
                  "@bazel_tools//tools/cpp:toolchain_type"]
)