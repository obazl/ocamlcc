load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

load("//bzl:providers.bzl",
     "BootInfo",
     "ModuleInfo",
     "new_deps_aggregator",
     "OcamlSignatureProvider")

load("//bzl:functions.bzl", "get_module_name")

load("//bzl/rules/common:options.bzl", "get_options")

load("//bzl/rules/common:impl_common.bzl", "dsorder")

load("//bzl/rules/common:DEPS.bzl", "aggregate_deps", "merge_depsets")

########################
def signature_impl(ctx):

    debug = False
    # if ctx.label.name in ["Pervasives"]
    #     debug = True

    # if "//toolchain/type:boot" in ctx.toolchains:
    #     fail("BOOT")

    stage = ctx.attr._stage[BuildSettingInfo].value
    # print("signature _stage: %s" % stage)

    workdir = "_{}/".format(stage)

    tc = None
    if stage == "boot":
        tc = ctx.exec_groups["boot"].toolchains[
            "//boot/toolchain/type:boot"]
    elif stage == "baseline":
        tc = ctx.exec_groups["baseline"].toolchains[
            "//boot/toolchain/type:baseline"]
    elif stage == "dev":
        #FIXME
        tc = ctx.exec_groups["dev"].toolchains[
            "//boot/toolchain/type:boot"]
    else:
        print("UNHANDLED STAGE: %s" % stage)
        tc = ctx.exec_groups["boot"].toolchains[
            "//boot/toolchain/type:boot"]

    ################
    includes   = []

    sig_src = ctx.file.src
    if debug:
        print("sig_src: %s" % sig_src)

    # if sig_src.extension == "ml":
    #     # extract mli file from ml file

    # add prefix if namespaced. from_name == normalized module name
    # derived from sig_src; module_name == prefixed if ns else same as
    # from_name.

    ns = None
    (from_name, ns, module_name) = get_module_name(ctx, sig_src)
    if debug:
        print("From {src} To: {dst}".format(
            src = from_name, dst = module_name))

    # if False: ## ctx.attr.ppx:
    #     ## mlifile output is generated output of ppx processing
    #     mlifile = impl_ppx_transform("ocaml_signature", ctx,
    #                                  sig_src,
    #                                  module_name + ".mli")
    # else:

    if from_name == module_name:
        # if ctx.label.name == "CamlinternalFormatBasics_cmi":
        #     print("not namespaced")

        ## We need to ensure mli file and cmi file are in the same
        ## place. Since Bazel writes output files into its own dirs
        ## (won't write back into src dir), this means we need to
        ## symlink the source mli file into the same output directory,
        ## so that it will be found when it comes time to compile the
        ## .ml file.

        if debug:
            print("not namespaced")
        if sig_src.is_source:  # i.e. not generated by a preprocessor
            mlifile = ctx.actions.declare_file(workdir + module_name + ".mli") # sig_src.basename)
            ctx.actions.symlink(output = mlifile,
                                target_file = sig_src)
            if debug:
                print("symlinked {src} => {dst}".format(
                    src = sig_src.path, dst = mlifile.path))
        else:
            ## generated file, already in bazel dir
            if debug:
                print("not symlinking {src}".format(
                    src = sig_src))

            mlifile = sig_src

    else:
        # namespaced w/o ppx: symlink sig_src to prefixed name, so
        # that output dir will contain both renamed input mli and
        # output cmi.
        ns_sig_src = module_name + ".mli"
        if debug:
            print("ns_sig_src: %s" % ns_sig_src)
        mlifile = ctx.actions.declare_file(workdir + ns_sig_src)
        ctx.actions.symlink(output = mlifile,
                            target_file = sig_src)
        if debug:
            print("mlifile %s" % mlifile)

    # if sig_src.extension == "ml":  ## wtf?
    #     ofile = workdir + sig_src.basename + "i"
    #     out_cmi = ctx.actions.declare_file(ofile)
    # else:
    ocmi = workdir + module_name + ".cmi"
    # if ctx.label.name == "CamlinternalFormatBasics_cmi":
    #     print("OCMI: %s" % ocmi)

    out_cmi = ctx.actions.declare_file(ocmi)

    if debug:
        print("out_cmi %s" % out_cmi)


    ################################################################
    ################  DEPS  ################
    depsets = new_deps_aggregator()

    # if ctx.attr._manifest[BuildSettingInfo].value:
    #     manifest = ctx.attr._manifest[BuildSettingInfo].value
    # else:
    manifest = []

    # if ctx.label.name == "Stdlib_cmi":
    #     print("Stdlib manifest: %s" % manifest)
        # fail("X")

    for dep in ctx.attr.deps:
        depsets = aggregate_deps(ctx, dep, depsets, manifest)

    if hasattr(ctx.attr, "ns"):
        if ctx.attr.ns:
            # for dep in ctx.attr.ns:
            depsets = aggregate_deps(ctx, ctx.attr.ns, depsets, manifest)

    ## build depsets here, use for OcamlProvider and OutputGroupInfo
    sigs_depset = depset(
        order=dsorder,
        direct = [out_cmi],
        transitive = [merge_depsets(depsets, "sigs")])

    cli_link_deps_depset = depset(
        order = dsorder,
        transitive = [merge_depsets(depsets, "cli_link_deps")]
    )

    afiles_depset  = depset(
        order=dsorder,
        transitive = [merge_depsets(depsets, "afiles")]
    )

    archived_cmx_depset = depset(
        order=dsorder,
        transitive = [merge_depsets(depsets, "archived_cmx")]
    )

    paths_depset  = depset(
        order = dsorder,
        direct = [out_cmi.dirname],
        transitive = [merge_depsets(depsets, "paths")]
    )

    # if ctx.label.name == "CamlinternalFormatBasics_cmi":
    #     print("depsets: %s" % depsets)
    #     fail("x")

    #########################
    args = ctx.actions.args()

    args.add("-nostdlib")

    if hasattr(ctx.attr, "_stdlib_resolver"):
        includes.append(ctx.attr._stdlib_resolver[ModuleInfo].sig.dirname)
        if tc.target_host in ["boot", "vm"]:
            # if stage == bootstrap:
            args.add_all(["-use-prims", tc.primitives])
    else:
        args.add("-nopervasives")

    args.add_all(tc.copts)

    args.add_all(tc.warnings[BuildSettingInfo].value)

    for w in ctx.attr.warnings:
        args.add_all(["-w",
                      w if w.startswith("-")
                      else "-" + w])

    _options = get_options(ctx.attr._rule, ctx)
    args.add_all(_options)

    ccInfo_list = []

    # ns_resolver_depset = []
    # if hasattr(ctx.attr, "ns"):
    #     # print("HAS ctx.attr.ns")
    #     ## Only -open Stdlib if we have a dep on Stdlib.
    #     if ctx.files.deps :
    #         if ctx.attr.ns:
    #             # if BootInfo in ctx.attr.ns:
    #                 # ns_resolver_depset = [ctx.attr.ns[BootInfo].inputs]

    #             # for f in ctx.attr.ns[DefaultInfo].files.to_list():
    #             #     # args.add("-I", f.dirname)
    #             #     includes.append(f.dirname)
    #                 # args.add(f)

    #             args.add("-no-alias-deps")
    #             args.add("-open", ns)
        #     else:
        #         args.add("-nopervasives")
        # else:
        #     args.add("-nopervasives")

    # if ctx.label.name == "Stdlib_cmi":
    #     print("sig depset : %s" % depsets)
        # fail("x")

    # arch_depset = merge_depsets(depsets, "archives")
    # for arch in arch_depset.to_list():
    #     includes.append(arch.dirname)

    # args.add_all(paths_depset.to_list(), before_each="-I")
    includes.extend(paths_depset.to_list())

    args.add_all(includes, before_each="-I", uniquify = True)

    if sig_src.extension == "ml":
        args.add("-i")
        args.add("-o", out_cmi)
    else:
        args.add("-c")
        args.add("-o", out_cmi)

    pack_ns = False
    if hasattr(ctx.attr, "_pack_ns"):
        if ctx.attr._pack_ns:
            if ctx.attr._pack_ns[BuildSettingInfo].value:
                pack_ns = ctx.attr._pack_ns[BuildSettingInfo].value
                # print("GOT PACK NS: %s" % pack_ns)
    if pack_ns:
        args.add("-for-pack", pack_ns)

    args.add("-intf", mlifile)

    direct_inputs = [mlifile]
    if ctx.files.data:
        direct_inputs.extend(ctx.files.data)

    # if ctx.label.name == "Config_cmi":
    #     print("depsets.deps.sigs: %s" % depsets.deps.sigs)
    #     fail("x")

    stdlib_resolver = []
    if hasattr(ctx.attr, "_stdlib_resolver"):
        stdlib_resolver.append(ctx.attr._stdlib_resolver[ModuleInfo].sig)
        stdlib_resolver.append(ctx.attr._stdlib_resolver[ModuleInfo].struct)

    inputs_depset = depset(
        order = dsorder,
        direct = []
        + direct_inputs # + ctx.files._ns_resolver,
        # + [tc.compiler[DefaultInfo].files_to_run.executable],
        # + ctx.files.data if ctx.files.data else [],
        + stdlib_resolver
        ,
        transitive = []## indirect_inputs_depsets
        + [merge_depsets(depsets, "sigs"),
           merge_depsets(depsets, "cli_link_deps")
           ]
        # + depsets.deps.structs
        # + depsets.deps.sigs
        # + depsets.deps.archives
        # + ns_resolver_depset
        # + [tc.compiler[DefaultInfo].default_runfiles.files]
    )

    ##########################################
    ################  ACTION  ################
    ctx.actions.run(
        exec_group = "boot",
        executable = tc.compiler[DefaultInfo].files_to_run,
        arguments = [args],
        inputs = inputs_depset,
        outputs = [out_cmi],
        tools = [
            tc.compiler[DefaultInfo].default_runfiles.files,
            tc.compiler[DefaultInfo].files_to_run
        ],
        # tools = [tc.tool_runner, tc.compiler],
        mnemonic = "CompileOcamlSignature",
        progress_message = "{mode} compiling baseline_signature: {ws}//{pkg}:{tgt}".format(
            mode = tc.build_host + ">" + tc.target_host,
            ws  = ctx.label.workspace_name if ctx.label.workspace_name else "", ## ctx.workspace_name,
            pkg = ctx.label.package,
            tgt=ctx.label.name
        )
    )

    #############################################
    ################  PROVIDERS  ################

    default_depset = depset(
        order = dsorder, direct = [out_cmi]
    )

    defaultInfo = DefaultInfo(
        files = default_depset
    )

    sigProvider = OcamlSignatureProvider(
        mli = mlifile,
        cmi = out_cmi
    )

    bootInfo = BootInfo(
        sigs     = sigs_depset,
        cli_link_deps = cli_link_deps_depset,
        afiles   = afiles_depset,
        archived_cmx  = archived_cmx_depset,
        paths    = paths_depset,

        # ofiles   = ofiles_depset,
        # archives = archives_depset,
        # astructs = astructs_depset,
    )

    providers = [
        defaultInfo,
        bootInfo,
        sigProvider,
    ]

    if ccInfo_list:
        providers.append(
            cc_common.merge_cc_infos(cc_infos = ccInfo_list)
        )

    return providers
