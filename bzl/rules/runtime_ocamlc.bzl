load("//bzl:providers.bzl",
     "CompilationModeSettingProvider",
     "OcamlArchiveProvider",
     "OcamlExecutableMarker",
     "OcamlImportMarker",
     "OcamlLibraryMarker",
     "OcamlNsResolverProvider",
     "OcamlModuleMarker",
     "OcamlNsMarker",
     "OcamlProvider",
     "OcamlSignatureProvider",
     "OcamlTestMarker")

load("//bzl:functions.bzl",
     "compile_mode_in_transition",
     "compile_mode_out_transition",
     "runtime_ocamlc_out_transition",
     "config_tc")

load(":impl_ccdeps.bzl", "link_ccdeps", "dump_CcInfo")

load(":impl_common.bzl", "dsorder", "opam_lib_prefix")

load(":options.bzl",
     "options",
     "options_executable",
     "get_options")

# load(":impl_executable.bzl", "impl_executable")

# load("//ocaml/_transitions:transitions.bzl", "executable_in_transition")
# ## load("//ocaml/_transitions:ns_transitions.bzl", "nsarchive_in_transition")

###############################
def _runtime_ocamlc(ctx):

    (mode, tc, tool, tool_args, scope, ext) = config_tc(ctx)

    # tc = ctx.toolchains["//bzl/toolchain:bootstrap"]
    # ##mode = ctx.attr._mode[CompilationModeSettingProvider].value
    # mode = "bytecode"
    # if mode == "bytecode":
    #     tool = tc.ocamlrun
    #     tool_args = [tc.ocamlc]
    # # else:
    # #     tool = tc.ocamlrun.opt
    # #     tool_args = []

    # return impl_executable(ctx, mode, tc.linkmode, tool, tool_args)

    debug = False
    # if ctx.label.name == "test":
        # debug = True

    # print("++ EXECUTABLE {}".format(ctx.label))

    if debug:
        print("EXECUTABLE TARGET: {kind}: {tgt}".format(
            kind = ctx.attr._rule,
            tgt  = ctx.label.name
        ))

    ################
    direct_cc_deps    = {}
    direct_cc_deps.update(ctx.attr.cc_deps)
    indirect_cc_deps  = {}

    ################
    includes  = []
    cmxa_args  = []

    out_exe = ctx.actions.declare_file(scope + ctx.label.name)

    #########################
    args = ctx.actions.args()

    args.add_all(tool_args)

    # if mode == "bytecode":
        ## FIXME: -custom only needed if linking with CC code?
        ## see section 20.1.3 at https://caml.inria.fr/pub/docs/manual-ocaml/intfc.html#s%3Ac-overview
        # args.add("-custom")

    _options = get_options(rule, ctx)
    # print("OPTIONS: %s" % _options)
    # do not uniquify options, it collapses all -I
    args.add_all(_options)

    if "-g" in _options:
        args.add("-runtime-variant", "d") # FIXME: verify compile built for debugging

    ################################################################
    ## deps mgmt
    ## * deps attr
    ##   * linkargs
    ##   * files
    ## * main attr - comes last
    ##   * linkargs
    ##   * file
    ## * cc deps

    ## merge deps and main, to elim dups

    main_deps_list = []
    paths_direct   = []
    paths_indirect = []

    # direct_ppx_codep_depsets = []
    # direct_ppx_codep_depsets_paths = []
    # indirect_ppx_codep_depsets      = []
    # indirect_ppx_codep_depsets_paths = []

    direct_inputs_depsets = []
    direct_linkargs_depsets = []
    direct_paths_depsets = []

    ccInfo_list = []

    for dep in ctx.attr.deps:
        # print("DEP: %s" % dep[OcamlProvider])
        if CcInfo in dep:
            # print("CcInfo dep: %s" % dep)
            ccInfo_list.append(dep[CcInfo])

        direct_inputs_depsets.append(dep[OcamlProvider].inputs)
        direct_linkargs_depsets.append(dep[OcamlProvider].linkargs)
        direct_paths_depsets.append(dep[OcamlProvider].paths)

        direct_linkargs_depsets.append(dep[DefaultInfo].files)

        # ################ PpxAdjunctsProvider ################
        # if PpxAdjunctsProvider in dep:
        #     ppxadep = dep[PpxAdjunctsProvider]
        #     if hasattr(ppxadep, "ppx_codeps"):
        #         if ppxadep.ppx_codeps:
        #             indirect_ppx_codep_depsets.append(ppxadep.ppx_codeps)
        #     if hasattr(ppxadep, "paths"):
        #         if ppxadep.paths:
        #             indirect_ppx_codep_depsets_paths.append(ppxadep.paths)

    ## end ctx.attr.deps handling:

    action_inputs_ccdep_filelist = []

    includes = []
    manifest_list = []

    ################################################################
    #### MAIN ####
    if ctx.attr.main:
        main = ctx.attr.main

        if OcamlProvider in main:
            if hasattr(main[OcamlProvider], "archive_manifests"):
                manifest_list.append(main[OcamlProvider].archive_manifests)

        direct_inputs_depsets.append(main[OcamlProvider].inputs)
        direct_linkargs_depsets.append(main[OcamlProvider].linkargs)
        direct_paths_depsets.append(main[OcamlProvider].paths)

        direct_linkargs_depsets.append(main[DefaultInfo].files)

        paths_indirect.append(main[OcamlProvider].paths)

        if CcInfo in main: # :
            # print("CcInfo main: %s" % main[CcInfo])
            ccInfo_list.append(main[CcInfo]) # [CcInfo])

        ccInfo = cc_common.merge_cc_infos(cc_infos = ccInfo_list)
        [
            action_inputs_ccdep_filelist,
            cc_runfiles
        ] = link_ccdeps(ctx,
                        tc.linkmode,
                        args,
                        ccInfo)


    ## end ctx.attr.main handling

    merged_manifests = depset(transitive = manifest_list)
    archive_filter_list = merged_manifests.to_list()
    # print("Merged manifests: %s" % archive_filter_list)

    ################
    paths_depset  = depset(
        order = dsorder,
        transitive = direct_paths_depsets
    )

    # args.add_all(paths_depset.to_list(), before_each="-I")

    linkargs_depset = depset(
        transitive = direct_linkargs_depsets
    )
    direct_inputs_depset = depset(
        transitive = direct_inputs_depsets
    )


    # for dep in direct_inputs_depset.to_list():
    #     # if dep.extension not in ["a", "o", "cmi", "mli", "cmti"]:
    #     #     if dep.basename != "oUnit2.cmx":  ## FIXME: why?
    #     if dep.extension in ["cmx", "cmxa", "cma"]:
    #         includes.append(dep.dirname)
    #         args.add(dep)


    # args.add("external/ounit2/oUnit2.cmx")

    ## Archives containing deps needed by direct deps or main must be
    ## on cmd line.  FIXME: how to include only those actually needed?
    # args.add_all(includes, before_each="-I", uniquify=True)

    for dep in linkargs_depset.to_list():
    # for dep in direct_inputs_depset.to_list():
        # if dep.extension not in ["a", "o", "cmi", "mli", "cmti"]:
            # if dep.basename != "oUnit2.cmx":  ## FIXME: why?
        if dep not in archive_filter_list:
            # if dep.extension in ["cmx", "cmxa", "cmo", "cma"]:
            # if dep.extension in ["cma"]:
                includes.append(dep.dirname)
                # args.add("-I", dep.dirname)
                # args.add(dep)
        else:
            print("removing double link: %s" % dep)


    ## all direct deps must be on cmd line:
    for dep in ctx.files.deps:
        ## print("DIRECT DEP: %s" % dep)
        includes.append(dep.dirname)
        args.add(dep)

    ## 'main' dep must come last on cmd line
    if ctx.file.main:
        args.add(ctx.file.main)

    # args.add("external/ounit2/oUnit.cmx")

    ## this exposes stdlib, camlheader, etc.
    args.add("-I", ctx.file._stdexit.dirname)

    args.add("-o", out_exe)

    data_inputs = []
    if ctx.attr.data:
        print("DATA: %s" % ctx.files.data)
        data_inputs = [depset(direct = ctx.files.data)]
    # data_inputs.append(depset(direct = [tc.camlheader]))
    # if tc.bootstrap_std_exit:
    #     std_exit = tc.bootstrap_std_exit.files
    # else:
    #     std_exit = []

    # print("LINKARGS: %s" % linkargs_depset)

    inputs_depset = depset(
        direct = [ctx.file._stdexit],
        transitive = [direct_inputs_depset]
        + [linkargs_depset]
        + data_inputs
        + [depset(action_inputs_ccdep_filelist)]
    )

    # for dep in inputs_depset.to_list():
    #     print("XDEP: %s" % dep)

    # if ctx.attr._rule == "ocaml_executable":
    #     mnemonic = "CompileOcamlExecutable"
    # # elif ctx.attr._rule == "ppx_executable":
    # #     mnemonic = "CompilePpxExecutable"
    # elif ctx.attr._rule == "ocaml_test":
    #     mnemonic = "CompileOcamlTest"
    # else:
    #     fail("Unknown rule for executable: %s" % ctx.attr._rule)

    mnemonic = "runtimeOcamlc"

    ################
    ctx.actions.run(
      # env = env,
      executable = tool,
      arguments = [args],
      inputs = inputs_depset,
      outputs = [out_exe],
      tools = [tool] + tool_args,  # [tc.ocamlopt],
      mnemonic = mnemonic,
      progress_message = "{mode} compiling {rule}: {ws}//{pkg}:{tgt}".format(
          mode = mode,
          rule = "runtime_ocamlc",
          ws  = ctx.label.workspace_name if ctx.label.workspace_name else ctx.workspace_name,
          pkg = ctx.label.package,
          tgt = ctx.label.name,
        )
    )
    ################

    #### RUNFILE DEPS ####
    if ctx.attr.strip_data_prefixes:
      myrunfiles = ctx.runfiles(
        files = ctx.files.data,
        symlinks = {dfile.basename : dfile for dfile in ctx.files.data}
      )
    else:
        myrunfiles = ctx.runfiles(
            files = ctx.files.data
        )

    ##########################
    defaultInfo = DefaultInfo(
        executable=out_exe,
        runfiles = myrunfiles
    )

    exe_provider = None
    # if ctx.attr._rule == "ppx_executable":
    #     exe_provider = PpxExecutableMarker(
    #         args = ctx.attr.args
    #     )
    # if ctx.attr._rule == "ocaml_executable":
    #     exe_provider = OcamlExecutableMarker()
    # elif ctx.attr._rule == "ocaml_test":
    #     exe_provider = OcamlTestMarker()
    # else:
    #     fail("Wrong rule called impl_executable: %s" % ctx.attr._rule)

    exe_provider = OcamlExecutableMarker()

    providers = [
        defaultInfo,
        exe_provider
    ]

    return providers

################################
# rule_options = options("ocaml")
rule_options = options_executable("ocaml")

########################
runtime_ocamlc = rule(
    implementation = _runtime_ocamlc,

    doc = "Generates an OCaml executable binary using the bootstrap toolchain",
    attrs = dict(

        _toolchain = attr.label(
            default = "//bzl/toolchain:tc"
        ),

        ocamlc = attr.label(
            allow_single_file = True,
            default = "//bzl/toolchain:ocamlc"
        ),

        # _boot       = attr.label(
        #     default = "//bzl/toolchain:boot",
        # ),

        opts             = attr.string_list(
            doc          = "List of OCaml options. Will override configurable default options."
        ),

        _mode       = attr.label(
            default = "//bzl/toolchain",
        ),

        mode       = attr.string(
            doc     = "Overrides mode build setting.",
        ),

        exe  = attr.string(
            doc = "By default, executable name is derived from 'name' attribute; use this to override."
        ),
        main = attr.label(
            doc = "Label of module containing entry point of executable. This module will be placed last in the list of dependencies.",
            # cfg = compile_mode_out_transition,
            allow_single_file = True,
            providers = [[OcamlModuleMarker]],
            default = None,
        ),
        data = attr.label_list(
            allow_files = True,
            doc = "Runtime dependencies: list of labels of data files needed by this executable at runtime."
        ),
        strip_data_prefixes = attr.bool(
            doc = "Symlink each data file to the basename part in the runfiles root directory. E.g. test/foo.data -> foo.data.",
            default = False
        ),
        deps = attr.label_list(
            doc = "List of OCaml dependencies.",
            # cfg = runtime_ocamlc_out_transition,
            providers = [[OcamlArchiveProvider],
                         [OcamlImportMarker],
                         [OcamlLibraryMarker],
                         [OcamlModuleMarker],
                         [OcamlNsMarker],
                         [CcInfo]],
        ),

        _stdexit = attr.label(
            # cfg = ocamlc_out_transition,
            default = "//stdlib:Std_exit",
            allow_single_file = True
        ),

        ## FIXME: add cc_linkopts?
        cc_deps = attr.label_keyed_string_dict(
            doc = """Dictionary specifying C/C++ library dependencies. Key: a target label; value: a linkmode string, which determines which file to link. Valid linkmodes: 'default', 'static', 'dynamic', 'shared' (synonym for 'dynamic'). For more information see [CC Dependencies: Linkmode](../ug/cc_deps.md#linkmode).
            """,
            ## FIXME: cc libs could come from LSPs that do not support CcInfo, e.g. rules_rust
            # providers = [[CcInfo]]
        ),

        cc_linkall = attr.label_list(
            ## equivalent to cc_library's "alwayslink"
            doc     = "True: use `-whole-archive` (GCC toolchain) or `-force_load` (Clang toolchain). Deps in this attribute must also be listed in cc_deps.",
            # providers = [CcInfo],
        ),
        cc_linkopts = attr.string_list(
            doc = "List of C/C++ link options. E.g. `[\"-lstd++\"]`.",

        ),

        # _debug           = attr.label(default = "@ocaml//debug"),

        # _rule = attr.string( default  = "ocaml_executable" ),
        # _allowlist_function_transition = attr.label(
        #     default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        # ),
    ),
    ## this is not an ns archive, and it does not use ns ConfigState,
    ## but we need to reset the ConfigState anyway, so the deps are
    ## not affected if this is a dependency of an ns aggregator.

    # cfg = compile_mode_in_transition,
    executable = True,
    toolchains = ["//bzl/toolchain:bootstrap"],
)