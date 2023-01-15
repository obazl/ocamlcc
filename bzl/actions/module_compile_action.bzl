load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")

load(":BUILD.bzl", "progress_msg", "get_build_executor")

load("//bzl:providers.bzl",
     "BootInfo",
     "DumpInfo",
     "ModuleInfo",
     "SigInfo",
     "NsResolverInfo",
     "DepsAggregator",
     "StdStructMarker",
     "StdlibStructMarker",
     "new_deps_aggregator", "OcamlSignatureProvider")

load("//bzl:functions.bzl", "get_module_name") #, "get_workdir")
load("//bzl/rules/common:DEPS.bzl", "aggregate_deps", "merge_depsets")
load("//bzl/rules/common:impl_common.bzl", "dsorder")
load("//bzl/rules/common:impl_ccdeps.bzl", "dump_CcInfo", "ccinfo_to_string")
load("//bzl/rules/common:options.bzl", "get_options")

################################################################
## Tasks, in order:
# 0. setup - toolchain, options
# a. construct outputs depset
#      outputs do not depend on deps, but we include outputs
#      when we merge deps, so we can later use them in providers
# b. merge deps
# c. construct inputs depset
# d. construct cmd line
# e. run action
# f. construct providers

################################################################
def declare_output_file(ctx, workdir, fname, ext, sibling = None):
    if ctx.attr._rule == "compile_module_test":
        return workdir + fname + ext
    else:
        if sibling:
            return ctx.actions.declare_file(
                workdir + fname + ext,
                sibling = sibling
            )
        else:
            return ctx.actions.declare_file(
                workdir + fname + ext
            )

################################################################
def declare_input_file(ctx, workdir, fname, ext, symlink):
    tmpfile = ctx.actions.declare_file(workdir + fname + ext)
    ctx.actions.symlink(output = tmpfile, target_file = symlink)
    return tmpfile

################
def construct_outputs(ctx, _options, tc, workdir, ext,
                      # from_name,
                      module_name ## may be changed
                      ):
    debug = False

    if debug:
        print("contruct_outputs: %s" % ctx.label)

    outputs = {
        "cmi": None,
        "sigfile": None,
        "cmti": None,

        "cmstruct": None,
        "cmt": None,
        "structfile": None,
        "ofile": None,
        "logfile": None,
        "workdir": None,
    }

    # Two kinds of ModuleInfo outputs:
    # ** action outputs produced by this rule
    # ** provider outputs passed on from deps.
    # In particular, we always provide a .cmi file, but
    # this could be either an action output or a provider output.

    # Action outputs for ModuleInfo:
    #   a. a .cmi file if 'sig' attr is empty or a src file
    #   b. a .cmt file if -bin-annot AND .cmi is an action output
    #   c. a .cmo or a .cmx file
    #   d. possibly a .o file
    #   e. a .cmt file if -bin-annot

    # Provider outputs for ModuleInfo:
    #   a. a .cmi file if passed via 'sig' attr
    #   b. a .cmti file if passed via 'sig' attr

    # ModuleInfo also to contain .ml src file and .mli if we have one
    # Remaining deps output via BootInfo provider

    # Tasks:
    # A. prep input src files, possibly renaming, & symlinking to workdir
    #   a. handle sig: declare outfiles, symlink to workdir
    #   b. derive module name: fixed if we got .cmi,
    #      otherwise maybe ns prefixed etc.
    #   c. handle struct - rename if namespaced, link src to workdir
    #      i.e. derive in_structfile
    # B. declare output files

    # pack_ns = False
    # if hasattr(ctx.attr, "_pack_ns"):
    #     if ctx.attr._pack_ns:
    #         if ctx.attr._pack_ns[BuildSettingInfo].value:
    #             pack_ns = ctx.attr._pack_ns[BuildSettingInfo].value
    #             # print("GOT PACK NS: %s" % pack_ns)

    ################
    # default_outputs    = [] # .cmo or .cmx+.o, for DefaultInfo
    action_outputs   = [] # .cmx, .cmi, .o

    # direct_linkargs = []
    # old_cmi = None

    ## module name is derived from sigfile name, so start with sig
    # if we have an input cmi, we will pass it on as Provider output,
    # but it is not an output of this action- do NOT add incoming cmi
    # to action outputs.

    # WARNING: When both .mli and .ml are inputs, '-o' is unavailable:
    # ocaml will write the output to the directory containing the
    # source files. This will NOT be the directory for output files
    # made with declare_file. There is no way that I know of to tell
    # the compiler to write outputs to some other directory. So if
    # both .mli and .ml are inputs, we need to copy/move/link the
    # output files to the correct (Bazel) output dir. Sadly, the
    # compile action will fail before we can do that, since it's
    # outputs will be in the wrong place.

    mlifile = None
    cmifile = None
    sig_src = None
    # sig_inputs = []

    # provider_output_cmi: never an input
    #   may be action output, if sig attr is empty or src file
    #   always a provider output
    # provider_output_cmi = None

    # If sig attr non-empty, it must be either a src file or sig target
    if ctx.attr.sig:
        if OcamlSignatureProvider in ctx.attr.sig:
            ## cmi already compiled
            # in case sig was compiled into a tmp dir (e.g. _build) to avoid nameclash,
            # symlink here
            sigProvider = ctx.attr.sig[OcamlSignatureProvider]
            # provider_output_cmi = sigProvider.cmi
            # outputs["cmi"]      = sigProvider.cmi

            # provider_output_mli = sigProvider.mli
            # outputs["sigfile"]  = sigProvider.mli

            # sig_inputs.append(provider_output_cmi)
            # sig_inputs.append(provider_output_mli)

            mli_dir = paths.dirname(sigProvider.mli.short_path)
            # mli_dir = paths.dirname(provider_output_mli.short_path)
            ## force module name to match compiled cmi
            extlen = len(ctx.file.sig.extension)
            module_name = ctx.file.sig.basename[:-(extlen + 1)]

        ## else sig is a src file, either is_source or generated
        elif ctx.file.sig.is_source:
            # need to symlink .mli, to match symlink of .ml
            sig_src = declare_output_file(ctx, workdir, module_name, ".mli")
            outputs["sigfile"] = sig_src
            # sig_inputs.append(sig_src)
            ctx.actions.symlink(output = sig_src,
                                target_file = ctx.file.sig)

            action_output_cmi = declare_output_file(ctx, workdir, module_name, ".cmi")
            # action_output_cmi = ctx.actions.declare_file(workdir + module_name + ".cmi")
            action_outputs.append(action_output_cmi)
            # provider_output_cmi = action_output_cmi
            outputs["cmi"] = action_output_cmi
            mli_dir = None
        else:
            # generated sigfile, e.g. by cp, rename, link
            # need to symlink .mli, to match symlink of .ml
            sig_src = declare_input_file(ctx, workdir, module_name, ".mli", ctx.file.sig)
            # sig_src = ctx.actions.declare_file(
            #     workdir + module_name + ".mli"
            # )
            # ctx.actions.symlink(output = sig_src,
            #                     target_file = ctx.file.sig)
            outputs["sigfile"] = sig_src

            # sig_inputs.append(sig_src)

            action_output_cmi = declare_output_file(ctx, workdir, module_name, ".cmi")
            # action_output_cmi = ctx.actions.declare_file(workdir + module_name + ".cmi")
            action_outputs.append(action_output_cmi)
            outputs["cmi"] = action_output_cmi
            mli_dir = None
    else: ## sig attr empty
        # compiler will generate .cmi
        # put src in workdir as well
        action_output_cmi = declare_output_file(ctx, workdir, module_name, ".cmi")
        # action_output_cmi = ctx.actions.declare_file(workdir + module_name + ".cmi")
        action_outputs.append(action_output_cmi)
        outputs["cmi"] = action_output_cmi
        mli_dir = None

    # direct_inputs = [in_structfile]

    if ctx.attr._rule == "compile_module_test":
        out_cm_ = module_name + ext
    else:
        out_cm_ = declare_output_file(ctx, workdir, module_name, ext)

    # out_cm_ = ctx.actions.declare_file(workdir + module_name + ext)
    if debug: print("OUT_CM_: %s" % out_cm_.path)
    action_outputs.append(out_cm_)
    outputs["cmstruct"] = out_cm_
    # direct_linkargs.append(out_cm_)
    # default_outputs.append(out_cm_)

    out_cmt = None
    if ( ("-bin-annot" in _options)
         or ("-bin-annot" in tc.copts) ):
        out_cmt = declare_output_file(ctx, workdir, module_name, ".cmt")
        # out_cmt = ctx.actions.declare_file(workdir + module_name + ".cmt")
        action_outputs.append(out_cmt)
        outputs["cmt"] = out_cmt
        # default_outputs.append(out_cmt)

    # moduleInfo_ofile = None
    if ext == ".cmx":
        # if not ctx.attr._rule.startswith("bootstrap"):
        out_o = declare_output_file(ctx, workdir, module_name, ".o")
        # out_o = ctx.actions.declare_file(workdir + module_name + ".o")
                                         # sibling = out_cm_)
        action_outputs.append(out_o)
        outputs["ofile"] = out_o
        # default_outputs.append(out_o)
        # moduleInfo_ofile = out_o
        # print("OUT_O: %s" % out_o)
        # direct_linkargs.append(out_o)
    else:
        out_o = None

    out_logfile = None
    if ((hasattr(ctx.attr, "dump") and len(ctx.attr.dump) > 0)
        or hasattr(ctx.attr, "_lambda_expect_test")):

        out_logfile = declare_output_file(ctx,
            "", out_cm_.basename, ".dump", ## sfx fixed by compiler
            sibling = out_cm_
        )
        # out_logfile = ctx.actions.declare_file(
        #     ## Suffix .dump is fixed by compiler
        #     out_cm_.basename + ".dump",
        #     sibling = out_cm_,
        # )
        action_outputs.append(out_logfile)
        outputs["logfile"] = out_logfile

    # construct_outputs:
    return (outputs,
            module_name,
            # action_outputs,
            # default_outputs,
            # out_cm_,
            # out_o,
            # out_cmt,
            # out_logfile,
            # provider_output_cmi,
            # in_structfile,
            # direct_inputs,  ## in_structfile
            # sig_inputs,
            # includes,
            # sig_src
            )

################
def construct_inference_outputs(ctx, _options, tc,
                                workdir, ext,
                                module_name):
    debug = False

    if debug:
        print("contruct_inference_outputs: %s" % ctx.label)

    outputs = {
        "cmi": None,
        "sigfile": None,
        "cmti": None,

        "cmstruct": None,
        "cmt": None,
        "structfile": None,
        "ofile": None,
        "logfile": None,
        "workdir": None,
    }

    ################
    action_outputs   = []
    ## ignore ctx.attr.sig, compiler will generate .mli

    # NB: use src file name, not mormalized module name
    action_output_mli = declare_output_file(
        ctx, workdir,
        ##module_name,
        ctx.file.struct.basename,
        "i")
    action_outputs.append(action_output_mli)
    outputs["mli"] = action_output_mli

    return (outputs, module_name)

################################################################
def construct_inputs(ctx, tc, ext, workdir,
                     executor, executor_arg,
                     from_name, module_name,
                     # direct_inputs,  # in_structfile
                     # stdlib_depset,
                     depsets,
                     # sig_inputs, # cmi, mli
                     outputs, # keys: cmi, sigfile, (in)structfile
                     # archived_cmx_depset
                     ):

    debug = False
    debug_suppress_cmis = False

    in_files   = []
    in_depsets = []

    # compiler = tc.compiler[DefaultInfo].files_to_run.executable
    # if compiler.basename.startswith("ocamlc"):
    #     in_files.append(compiler)

    in_files.append(executor)
    if executor_arg:
        in_files.append(executor_arg)

    # if tc.tool_arg:
    #     in_files.append(tc.tool_arg)

    ## Task: determine in_structfile.
    ## may be different than src, either by renaming or if it is
    ## generated into a workdir.

    in_cmi = None
    if ctx.attr.sig:
        if OcamlSignatureProvider in ctx.attr.sig:
            ## WARNING WARNING WARNING!!!

            ## The cmi file is not enough! The compiler will not look
            ## for it first, it will look for the mli file first!
            ## If it does not find the mli file, it will ignore the cmi
            ## file and instead generate an mli file from the ml file.
            ## This is likely to produce an error - for example,
            ## for utils/load_path.ml:

            ## "let auto_include_otheribs =
            ##      ^^^^^^^^^^^^^^^^^^^^^
            ##  The type of this expression
            ##  (string -> unit) ->
            ##  (Dir.t -> '_weak1 -> '_weak2 option) -> '_weak1 -> '_weak2,
            ##  contains type variables that cannot be generalized"

            ## which happens because type inference cannot come up
            ## with the type declared in the mli file:
            ## val auto_include_otherlibs :
            ##   (string -> unit) -> auto_include_callback

            ## UPDATE: the new(ish) -cmi-file option addresses this.
            ## With it, no need for the mli file.

            in_files.append(ctx.attr.sig[SigInfo].cmi)
            # in_files.append(ctx.attr.sig[SigInfo].mli)

            in_cmi = ctx.file.sig

    ## struct: put struct in same dir as mli/cmi, rename if namespaced
    mli_dir = None
    if from_name == module_name:  ## not namespaced
        # if ctx.label.name == "CamlinternalFormatBasics":
            # print("NOT NAMESPACED")
            # print("cmi is_source? %s" % provider_output_cmi.is_source)
        if ctx.file.struct.is_source:
            # structfile in src dir, make sure in same dir as sig

            if ctx.file.sig:
                # if we also have a sig...
                if OcamlSignatureProvider in ctx.attr.sig:
                    sigProvider = ctx.attr.sig[OcamlSignatureProvider]
                    mli_dir = paths.dirname(sigProvider.mli.short_path)
                    # sig file is compiled .cmo
                    # force name of module to match compiled sig
                    extlen = len(ctx.file.sig.extension)
                    module_name = ctx.file.sig.basename[:-(extlen + 1)]
                    in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
                    # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
                    # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)

                elif ctx.file.sig.is_source:
                    in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
                    # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
                    # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)
                else:
                    # generated sigfile
                    in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
                    # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
                    # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)

            else: # sig attr empty
                # no sig - cmi handled above, here link structfile to workdir
                # in_structfile = ctx.file.struct
                in_structfile = declare_input_file(ctx, workdir, ctx.file.struct.basename, "", ctx.file.struct)
                # in_structfile = ctx.actions.declare_file(workdir + ctx.file.struct.basename)
                # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)

        else: # structfile is generated, e.g. by ocamllex or a genrule,
            # so it is not in the original src dir
            # make sure it's in same dir as mli/cmi IF we have ctx.file.sig
            if ctx.file.sig:
                if OcamlSignatureProvider in ctx.attr.sig:
                    # print("xxxxxxxxxxxxxxxx %s" % ctx.label)
                    # force name of module to match compiled sig
                    extlen = len(ctx.file.sig.extension)
                    module_name = ctx.file.sig.basename[:-(extlen + 1)]
                    in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
                    # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
                    # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)
                    # print("lbl: %s" % ctx.label)
                    # print("IN STRUCTFILE: %s" % in_structfile)

                elif ctx.file.sig.is_source:
                    # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
                    # outputs["structfile"] = in_structfile
                    # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)
                    if paths.dirname(ctx.file.struct.short_path) != mli_dir:
                        in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
                        # in_structfile = ctx.actions.declare_file(
                        #     workdir + module_name + ".ml") # ctx.file.struct.basename)
                        # ctx.actions.symlink(
                        #     output = in_structfile,
                        #     target_file = ctx.file.struct)
                        if debug:
                            print("symlinked {src} => {dst}".format(
                                src = ctx.file.struct, dst = in_structfile))
                    else:
                        if debug:
                            print("not symlinking src: {src}".format(
                                src = ctx.file.struct.path))
                        in_structfile = ctx.file.struct
                else: # sig file is generated src
                    fail("Unhandled case: sigfile is generated")
            else:  ## no sig file, will emit cmi, put both in workdir
                in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
                # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
                # ctx.actions.symlink(output = in_structfile, target_file = ctx.file.struct)

    else:  ## we're namespaced
        in_structfile = declare_input_file(ctx, workdir, module_name, ".ml", ctx.file.struct)
        # in_structfile = ctx.actions.declare_file(workdir + module_name + ".ml")
        # ctx.actions.symlink(
        #     output = in_structfile, target_file = ctx.file.struct
        # )

    # outputs["structfile"] = in_structfile
    in_files.append(in_structfile)

    ## FIXME: if sig is src file, add to inputs

    resolver = None
    resolver_deps = []
    ## ns rules used by debugger and dynlink with hand-rolled resolvers
    if hasattr(ctx.attr, "ns"):
        if ctx.attr.ns:
            resolver = ctx.attr.ns[ModuleInfo]
            resolver_deps.append(resolver.sig)
            resolver_deps.append(resolver.struct)
            nsname = resolver.struct.basename[:-4]
            # args.add_all(["-open", nsname])

            # includes.append(ctx.attr.ns[ModuleInfo].sig.dirname)

            # direct_inputs.append(ctx.attr.ns[ModuleInfo].sig)
            # direct_inputs.append(ctx.attr.ns[ModuleInfo].struct)
            in_files.append(ctx.attr.ns[ModuleInfo].sig)
            in_files.append(ctx.attr.ns[ModuleInfo].struct)

    # if hasattr(ctx.attr, "ns"):
    #     if ctx.attr.ns:
    #         includes.append(ctx.attr.ns[ModuleInfo].sig.dirname)

    ## IF we have ctx.attr.suppress_cmi, then we need to reconstruct
    ## our BuildInfo to exclude suppressed cmis. This is required for
    ## one test case. In that cae we need to merge sigs, in order to
    ## filter out suppressed cmis for testing, to emulate the
    ## situation where a cmi file is missing. Rule 'test_module' has
    ## attr 'suppress_cmi', listing cmi deps to be removed from the
    ## inputs to this target.

    ## TODO: see about writing a custom one-off rule+implementation
    ## for that test case.

    if hasattr(ctx.attr, "suppress_cmi"):
        if len(ctx.attr.suppress_cmi) > 0:
            ## TODO: in this case, update depsets.deps (ie. BootInfo)
            merged_sigs = merge_depsets(depsets, "sigs")
            if debug_suppress_cmis:
                print("merged_sigs: %s" % merged_sigs)
            suppressed_cmis = []
            for dep in ctx.attr.suppress_cmi:
                if debug_suppress_cmis:
                    print("SUPPRESS: %s" % dep)
                suppressed_cmis.extend(dep[BootInfo].sigs.to_list())
            if debug_suppress_cmis:
                print("suppressing: %s" % suppressed_cmis)
            msigs = []
            for sig in merged_sigs.to_list():
                if sig not in suppressed_cmis:
                    msigs.append(sig)
            if debug_suppress_cmis:
                print("msigs: %s" % msigs)
            input_sigs_depset = depset(msigs)
            bootInfo = BootInfo(
                # sigs    = msigs,
                sigs    = [input_sigs_depset],
                structs = depsets.deps.structs,
                cli_link_deps = depsets.deps.cli_link_deps,
                afiles = depsets.deps.afiles,
                ofiles = depsets.deps.ofiles,
                archived_cmx = depsets.deps.archived_cmx,
                paths = depsets.deps.paths,
            )
        else:
            bootInfo = depsets.deps
    else:
        bootInfo = depsets.deps
        # else:
        #     input_sigs_depset = merged_sigs
    # else:
    #     input_sigs_depset = merged_sigs

    # merged_input_depsets = [] #[input_sigs_depset]

    # merged_input_depsets.append(merge_depsets(depsets, "cli_link_deps"))
    # if ext == ".cmx":
    #     merged_input_depsets.append(archived_cmx_depset)

    # inputs_depset = depset(
    #     order = dsorder,
    #     direct = []
    #     # + sig_inputs  # cmi, mli - from outfiles
    #     # + direct_inputs # ns sig & struct => in_files
    #     + depsets.deps.mli
    #     + resolver_deps
    #     + [tc.executable]
    #     + ([tc.tool_arg] if tc.tool_arg else [])
    #     # + runtime_deps
    #     ,
    #     transitive = []

    #     ##FIXME: no need to do a prior merge these, just pass the
    #     ##aggregate lists here
    #     + input_sigs_depset
    #     + depsets.deps.cli_link_deps
    #     + (depsets.deps.archived_cmx if ext == ".cmx" else [])
    #     # + merged_input_depsets

    #     # + [tc.compiler[DefaultInfo].default_runfiles.files]
    #     # + stdlib_depset
    #     # + ns_deps
    #     # + bottomup_ns_inputs
    #     ## depend on cc tc - makes bazel stuff accessible to ocaml's
    #     ## cc driver
    #     + [cc_toolchain.all_files]
    # )

    # PROBLEM: in_depsets is just a list of depsets but to construct
    # providers we need to be able to pick out sigs depsets,, afiles,
    # etc.

    # depsets = struct(
    #     sigs = depsets.deps.sigs,
    # )


    # construct_inputs return:
    return struct(structfile = in_structfile,
                  cmi = in_cmi,
                  files = in_files,
                  # depsets = in_depsets,
                  bootinfo  = bootInfo,
                  ccinfo    = depsets.ccinfos,
                  ccinfo_archived = depsets.ccinfos_archived)

################################################################
## FIXME: do not merge current outputs here, just merge input deps
## current outs should be added when constructing providers -
## current outs in directs fld, these merged in transitive

## in fact we need not merge here at all, inputs depset can take a
## list of depsets

# returns struct with flds: files, depsets
################
def merge_deps(ctx,
               outputs
               # ext,
               # provider_output_cmi,
               # out_cm_,
               # out_o
               ):

    depsets = new_deps_aggregator()

    # if ctx.attr._manifest[BuildSettingInfo].value:
    #     manifest = ctx.attr._manifest[BuildSettingInfo].value
    # else:
    manifest = []

    # if ctx.label.name == "Stdlib":
    #     print("Stdlib manifest: %s" % manifest)
        # fail("X")

    if ctx.attr.sig: #FIXME
        if OcamlSignatureProvider in ctx.attr.sig:
            depsets = aggregate_deps(ctx, ctx.attr.sig, depsets, manifest)
        else:
            # either is_source or generated
            depsets.deps.mli.append(ctx.file.sig)
            # FIXME: add cmi to depsets
            if outputs["cmi"]:
                depsets.deps.sigs.append(depset([outputs["cmi"]]))
            # if provider_output_cmi:
            #     depsets.deps.sigs.append(depset([provider_output_cmi]))

    for dep in ctx.attr.deps:
        depsets = aggregate_deps(ctx, dep, depsets, manifest)
        if ctx.label.name == "Load_path":
            print(depsets.deps.cli_link_deps)
            # fail()

    for dep in ctx.attr.cc_deps:
        depsets = aggregate_deps(ctx, dep, depsets, manifest)

    if hasattr(ctx.attr, "sig_deps"):
        for dep in ctx.attr.sig_deps:
            depsets = aggregate_deps(ctx, dep, depsets, manifest)

    if hasattr(ctx.attr, "stdlib_deps"):
        # if len(ctx.attr.stdlib_deps) > 0:
        #     if not ctx.label.name == "Stdlib":
        #         open_stdlib = True
        for dep in ctx.attr.stdlib_deps:
            depsets = aggregate_deps(ctx, dep, depsets, manifest)
            # if dep.label.name == "Primitives":
            #     stdlib_primitives_target = dep
            # elif dep.label.name == "Stdlib":  ## Stdlib resolver
            #     stdlib_module_target = dep
            # elif dep.label.name.startswith("Stdlib"): ## stdlib submodule
            #     stdlib_module_target = dep
            # elif dep.label.name == "stdlib": ## stdlib archive OR library
            #     stdlib_library_target = dep

    # At this point depsets.deps is our aggregated BootInfo

    # Now what if this module is to be archived, and this dep is a
    # sibling submodule? If it is a sibling it goes in archived_cmx,
    # or if it is a cmo we drop it since it will be archived. If it is
    # not a sibling it goes in cli_link_deps.

    ## The problem is we do not know where whether this module is to
    ## be archived. It is the archive rule that must decide how
    ## to distribute its deps. Which means we have no way of knowing
    ## if this module should go in cli_link_deps.

    ## So we do not include this module in its own BootInfo, only in
    ## DefaultInfo. Clients decide what to do with it. An archive will
    ## put it (but not its cli_link_deps) on the archive cmd line. An
    ## executable will put both it and its cli_link_deps on the cmd
    ## line.

    ## An archive must also filter this module's cli_link_deps to
    ## remove sibling submodules that it archives beside this module.

    ## So this module should put the cli_link_deps of all of its deps
    ## into its own BootInfo.cli_link_deps, and leave it to client
    ## archives and execs to sort them out.

    ## And since clients filter cli_link_deps, we can add this module
    ## to its own BootInfo.cli_link_deps.

    ## It would be better to avoid filtering, but that does not seem
    ## possible, since a sibling dependency could be indirect. The
    ## only way to avoid filtering would be to mark sibling deps in
    ## some way.

    ## We could put a transition on the archive rule and have it
    ## record its manifest in the configuration. Then each module
    ## could check the manifest to decide if it is being archived.

    ## These mergings will be done when we construct providers:
    # sigs_depset = depset(
    #     order=dsorder,
    #     direct = [provider_output_cmi],
    #     transitive = [merge_depsets(depsets, "sigs")])

    # cli_link_deps_depset = depset(
    #     order = dsorder,
    #     direct = [out_cm_],
    #     transitive = [merge_depsets(depsets, "cli_link_deps")]
    # )

    # afiles_depset  = depset(
    #     order=dsorder,
    #     transitive = [merge_depsets(depsets, "afiles")]
    # )

    # if ext == ".cmx":
    #     ofiles_depset  = depset(
    #         order=dsorder,
    #         direct = [out_o],
    #         transitive = [merge_depsets(depsets, "ofiles")]
    #     )
    # else:
    #     ofiles_depset  = depset(
    #         order=dsorder,
    #         transitive = [merge_depsets(depsets, "ofiles")]
    #     )

    # # archived_cmx_depset = depset(
    # #     order=dsorder,
    # #     transitive = [merge_depsets(depsets, "archived_cmx")]
    # # )

    # if len(depsets.ccinfos) > 0:
    #     ccInfo_provider = cc_common.merge_cc_infos(
    #         cc_infos = depsets.ccinfos
    #         # cc_infos = cc_deps_primary + cc_deps_secondary
    #     )
    # else:
    #     ccInfo_provider = None

    # paths_depset  = depset(
    #     order = dsorder,
    #     direct = [out_cm_.dirname],
    #     transitive = [merge_depsets(depsets, "paths")]
    # )

    # deps = DepsAggregator(
    #     deps = BootInfo(
    #         sigs = sigs_depset
    #     ),
    #     ccinfos = ccInfo_provider,
    #     ccinfos_archived = []
    # )

    ## FIXME: put merged depsets into new DepsAggregator
    return (depsets,
            # sigs_depset,
            # cli_link_deps_depset,
            # afiles_depset,
            # ofiles_depset,
            # # archived_cmx_depset,
            # ccInfo_provider,
            # paths_depset)
            )

################################################################
def adapt_includes(inc):
    return inc.removeprefix("bazel-out/darwin-fastbuild/bin/")
    # return inc

def construct_args(ctx, tc, _options, cancel_opts,
                   ext,
                   inputs,
                   outputs,
                   depsets,
                   # direct_inputs,
                   # paths_depset,
                   # sig_src,
                   # in_structfile,
                   # out_cm_
                   ):

    includes   = []

    open_stdlib = False
    if hasattr(ctx.attr, "stdlib_deps"):
        if len(ctx.attr.stdlib_deps) > 0:
            if not ctx.label.name == "Stdlib":
                open_stdlib = True
        for dep in ctx.attr.stdlib_deps:
            if (dep.label.name.startswith("Stdlib")
                or dep.label.name == "Primitives"):
                ## dep is either Stdlib resolver or a stdlib submodule
                if ctx.attr._rule == "compile_module_test":
                    inc = paths.dirname(dep[DefaultInfo].files.to_list()[0].short_path)
                else:
                    inc = dep[DefaultInfo].files.to_list()[0].dirname
                includes.append(inc)

            elif dep.label.name == "stdlib":
                ## dep is stdlib library, possibly archived
                if ctx.attr._compilerlibs_archived[BuildSettingInfo].value:
                    stdlib = ctx.expand_location("$(rootpath //stdlib)",
                                                 targets=[dep])
                    includes.append(paths.dirname(stdlib))
                else:
                    stdlibstr = ctx.expand_location("$(rootpaths //stdlib)",
                                         targets=[dep])
                    stdlibs = stdlibstr.split(" ")
                    includes.append(paths.dirname(stdlibs[0]))

    # compiler = tc.compiler[DefaultInfo].files_to_run.executable
    # if compiler.basename.startswith("ocamlc"):
    #     toolarg_input = [compiler]
        # args.add(compiler.path)

    # toolarg = tc.tool_arg
    # if toolarg:
    #     toolarg_input = [toolarg]
    # else:
    #     toolarg_input = []

    merged_paths = depset(transitive = depsets.deps.paths)
    includes.extend(merged_paths.to_list())

    # if pack_ns:
    #     args.add("-for-pack", pack_ns)

    # if sig_src:
    #     includes.append(sig_src.dirname)
    if outputs["sigfile"]:
        includes.append(outputs["sigfile"].dirname)

    # includes.append(tc.runtime.dirname)

    args = ctx.actions.args()

    # if ctx.attr._rule == "compile_module_test":
    #     args.add(tc.ocamlrun.short_path) # executable)

    compiler = tc.compiler[DefaultInfo].files_to_run.executable
    if not ctx.attr._rule == "compile_module_test":
        print("TGT: %s" % ctx.label)
        print("tool compiler: %s" % tc.compiler)
        print("tool exec: %s" % tc.executable)
        print("tool arg: %s" % tc.tool_arg)
        # fail(tc.tool_arg)
        # if tc.tool_arg:
        #     # for vm executors
        #     print("YYYYYYYYYYYYYYYY")

        if compiler.extension not in ["opt", "optx"]:
            args.add(compiler.path)
            if ctx.label.name == "Stdlib.Either":
                print("Either compiler: %s" % compiler)
                # fail(ctx.label)
        # elif compiler.basename.endswith(".boot"):
        #     args.add(tc.tool_arg.path)
    # else:
    #     fail("XXXXXXXXXXXXXXXX")

    # if tc.protocol == "dev":

    if "-pervasives" in _options:
        # default is -nopervasives
        cancel_opts.append("-nopervasives")
        _options.remove("-pervasives")

    # if hasattr(ctx.attr, "_opts"):
    #     args.add_all(ctx.attr._opts)

    tc_opts = []
    if not ctx.attr.nocopts:  ## FIXME: obsolete?
        # for opt in tc.copts:
        #     if opt not in NEGATION_OPTS:
        #         args.add(opt)
        #     else:
        # args.add_all(tc.copts)
        tc_opts.extend(tc.copts)

    tc_opts.extend(tc.structopts)

    for opt in tc_opts:
        if opt not in cancel_opts:
            args.add(opt)

    args.add_all(tc.warnings[BuildSettingInfo].value)

    for w in ctx.attr.warnings:
        args.add_all(["-w",
                      w if w.startswith("+")
                      else w if w.startswith("-")
                      else "-" + w])

    args.add_all(_options)

    if open_stdlib:
        ##NB: -no-alias-deps is about _link_ deps, not compile deps
        args.add("-no-alias-deps") ##FIXME: control this w/flag?
        args.add("-open", "Stdlib")

    # test_module has attr 'dump' for e.g. -dlambda
    #FIXME: rename 'dump' to 'logging'
    #FIXME: make a function for the dump stuff
    if hasattr(ctx.attr, "_lambda_expect_test"):
        for arg in ctx.attr._lambda_expect_test:
            args.add(arg)

    elif hasattr(ctx.attr, "dump"): # test rules w/explicit dump attr
        if len(ctx.attr.dump) > 0:
            args.add("-dump-into-file")
        for d in ctx.attr.dump:
            if d == "source":
                args.add("-dsource")
            if d == "parsetree":
                args.add("-dparsetree")
            if d == "typedtree":
                args.add("-dtypedtree")
            if d == "shape":
                args.add("-dshape")
            if d == "rawlambda":
                args.add("-drawlambda")
            if d == "lambda":
                args.add("-dlambda")
            if d == "rawflambda":
                args.add("-drawflambda")
            if d == "flambda":
                args.add("-dflambda")
            if d == "flambda-let":
                args.add("-dflambda-let")
            if d == "flambda-verbose":
                args.add("-dflambda-verbose")

            if ext == ".cmo":
                if d == "instr":
                    args.add("-dinstr")

            if ext == ".cmx":
                if d == "clambda":
                    args.add("-dclambda")
                if d == "rawclambda":
                    args.add("-drawclambda")
                if d == "cmm":
                    args.add("-dcmm")
                if d == "instruction-selection":
                    args.add("-dsel")

    if ctx.attr._rule == "compile_module_test":
        args.add_all(includes,
                     map_each = adapt_includes,
                     before_each="-I",
                     uniquify = True)
    else:
        args.add_all(includes,
                     before_each="-I",
                     uniquify = True)

    # if sig_src: # not used yet
    #     args.add(sig_src)
    if outputs["sigfile"]:
        args.add(outputs["sigfile"])
        # args.add(in_structfile) # structfile)
        args.add(outputs["structfile"])
    else:
        # args.add("-I", in_structfile.dirname)
        # args.add("-impl", in_structfile) # structfile)
        args.add("-I", inputs.structfile.dirname)
        if inputs.cmi:
            args.add("-cmi-file", inputs.cmi)

        if ctx.attr._rule == "compile_module_test":
            # args.add("-impl", inputs.structfile.short_path)
            # src file not symlinked into workdir:
            # args.add("-I", ctx.file.struct.dirname + "/_BS_vv")
            args.add("-impl", ctx.file.struct.path)
            # fixme: deps dirs also need adjusting
        else:
            args.add("-impl", inputs.structfile.path)

        if ctx.attr._rule == "test_infer_signature":
            args.add("-i")
            # args.add("-o", outputs["mli"])
        else:
            args.add("-c")

            if ctx.attr._rule == "compile_module_test":
                args.add("-o", outputs["cmstruct"])
            else:
                args.add("-o", outputs["cmstruct"])

    return args

##############################################
def gen_compile_script(ctx, executable, args):

    script = ctx.actions.declare_file(ctx.attr.name + ".compile.sh")

    ctx.actions.write(
        output = script,
        content = args,
        is_executable = True
    )

    return script

#####################
def construct_module_compile_action(ctx, module_name):
# def module_impl(ctx, module_name):

    debug = False
    debug_bootstrap = False
    debug_ccdeps = False

    basename = ctx.label.name
    from_name = basename[:1].capitalize() + basename[1:]

    tc = ctx.toolchains["//toolchain/type:ocaml"]

    workdir = tc.workdir

    compiler = tc.compiler[DefaultInfo].files_to_run.executable

    if compiler.extension in ["byte", "boot"]:
        executor = tc.ocamlrun
        executor_arg = compiler
    else:
        executor = compiler
        executor_arg = None

    # if debug:
    #     print("TGT: %s" % ctx.label)
    #     print("tc.build_executor: %s" % tc.build_executor)
    #     print("tc.config_executor: %s" % tc.config_executor)
    #     print("tc.config_emitter: %s" % tc.config_emitter)

    # 'optx' - flambda-built
    # if compiler.stem in ["ocamlc"]:
    if compiler.basename in [
        "ocamlc.byte", "ocamlc.opt", "ocamlc.boot",
        "ocamlc.optx",
    ]:
        ext = ".cmo"
    elif compiler.basename in [
        "ocamlopt.byte",
        "ocamlopt.opt",
        "ocamloptx.byte",
        "ocamloptx.opt",
        "ocamloptx.optx",
    ]:
        ext = ".cmx"
    else:
        fail("bad compiler basename: %s" % compiler.basename)

    (_options, cancel_opts) = get_options(ctx.attr._rule, ctx)

    ################################################################
    ################  OUTPUTS  ################
    if ctx.attr._rule == "test_infer_signature":
        (outputs, module_name) = construct_inference_outputs(ctx, _options, tc,
                                                             workdir, ext,
                                                             module_name)
        print("outputs: %s" % outputs)
    else:
        (outputs,  # includes in_structfile
         module_name,
         # action_outputs,
         # default_outputs,
         # out_cm_,
         # out_o,
         # out_cmt,
         # out_logfile,
         # provider_output_cmi,
         # in_structfile,
         # direct_inputs, ## in_structfile
         # sig_inputs, # cmi, mli
         # includes,
         # sig_src
         ) = construct_outputs(ctx, _options, tc,
                               workdir, ext,
                               module_name)

    ################################################################
    ################  DEPS  ################
    # stdlib_module_target  = None
    # stdlib_primitives_target  = None
    # stdlib_library_target = None
    # stdlib_depset =[]

    # if --//config/ocaml/compiler/libs:archived
    # if hasattr(ctx.attr, "stdlib_primitives"): # test rules
    #     if ctx.attr.stdlib_primitives:
    #         if hasattr(ctx.attr, "_stdlib"):
    #             print("stdlib: %s" % ctx.attr._stdlib[ModuleInfo].files)
    #             includes.append(ctx.file._stdlib.dirname)
    #             stdlib_depset.append(ctx.attr._stdlib[ModuleInfo].files)

    (depsets, # > unmerged aggregated deps excluding current action outs
     ## the rest are the depsets flds merged, with curren outs added
     # sigs_depset,
     # cli_link_deps_depset,
     # afiles_depset,
     # ofiles_depset,
     # # archived_cmx_depset,
     # ccInfo_provider,
     # paths_depset
     ) = merge_deps(ctx,
                    outputs
                    # ext,
                    # provider_output_cmi,
                    # out_cm_,
                    # out_o
                    )

    ## now 'depsets.deps' contains aggregated BootInfo deps

    ################################################################
    #### construct inputs depset
    ## FIXME: inputs = list of file deps of this tgt (e.g. .ml, .cmi)
    ##                 + list of deps depsets
    ## so return struct with files, depsets flds
    # inputs_depset =
    inputs = construct_inputs(ctx, tc, ext, workdir,
                              executor, executor_arg,
                              from_name, module_name,
                              # direct_inputs,
                              # stdlib_depset,
                              depsets,
                              # sig_inputs, # cmi, mli
                              outputs # contains cmi, sigfile
                              # archived_cmx_depset
                              )

    ################################################################
    ################  CMD LINE  ################
    args = construct_args(ctx, tc,
                          _options, cancel_opts,
                          # direct_inputs,
                          ext,
                          inputs,
                          outputs,
                          depsets,
                          # paths_depset,
                          # sig_src,
                          # in_structfile,
                          # out_cm_
                          )

    ## construct_module_compile_action(ctx) return:
    return (inputs,  # => struct, flds: files, depsets
            # action_outputs, # => dictionary 'outputs'
            outputs,
            # tc.ocamlrun, ## executable,
            executor,
            executor_arg,
            workdir,
            args,

            ## NB: we can create providers before running the action

            ## for ModuleInfo provider - put these in outputs dict:
            # in_structfile,
            # provider_output_cmi,
            # out_cm_,
            # out_o,
            # out_cmt,
            # out_logfile,

            ## for BootInfo provider
            # sigs_depset,
            # cli_link_deps_depset,
            # afiles_depset,
            # ofiles_depset,
            # archived_cmx_depset,
            # paths_depset,

            ## for CcInfo provider
            # ccInfo_provider
            )
