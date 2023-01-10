################
## Bazel version 5
# BootInfo = provider(
#     doc = "foo",
#     fields = {
#         "sigs"          : "Depset of .cmi files. always added to inputs, never to cmd line.",
#         "cli_link_deps" : "Depset of cm[x]a and cm[x|o] files to be added to inputs and link cmd line (executables and archives).",
#         "afiles"        : "Depset of the .a files that go with .cmxa files",
#         "archived_cmx"  : "Depset of archived .cmx and .o files. always added to inputs, never to cmd line.",
#         "paths"         : "string depset, for efficiency",
#         # "ofiles"        :    "depset of the .o files that go with .cmx files",
#         # "archives"      :  "depset of .cmxa and .cma files",
#         # "cma"           :       "depset of .cma files",
#         # "cmxa"          :       "depset of .cmxa files",
#         # "astructs"      :  "depset of archived structs, added to link depgraph but not command line.",
#         # "cmts"          :      "depset of cmt/cmti files",
#     },
# )

################################################################
def _ModuleInfo_init(*,
                     sig = None,
                     sig_src = None,
                     cmti = None,
                     struct = None,
                     struct_src = None,
                     cmt = None,
                     ofile = None,
                     files = None):
    return {
        "sig" : sig,
        "sig_src": sig_src,
        "cmti": cmti,
        "struct": struct,
        "struct_src": struct_src,
        "cmt": cmt,
        "ofile": ofile,
        "files": files
    }

ModuleInfo, _new_moduleinfo = provider(
    doc = "foo",
    fields = {
        "sig"   : "One .cmi file",
        "sig_src"   : "One .mli file",
        "cmti"  : "One .cmti file",
        "struct": "One .cmo or .cmx file",
        "struct_src": "One .ml file",
        "cmt"  : "One .cmt file",
        "ofile" : "One .o file if struct is .cmx",
        "files": "Depset of the above"
    },
    init = _ModuleInfo_init
)

################################################################
def _SigInfo_init(*,
                  cmi  = None,
                  cmti = None,
                  ##FIXME: rename sig_src, for consistency with ModuleInfo
                  mli  = None):
    return {
        "cmi"  : cmi,
        "cmti" : cmti,
        "mli"  : mli,
    }

SigInfo, _new_siginfo = provider(
    doc = "OCaml signature provider",
    fields = {
        "cmi"   : "One .cmi file",
        "cmti"  : "One .cmti file",
        "mli"  : "One .mli file",
    },
    init = _SigInfo_init
)

################################################################
def _DumpInfo_init(*, dump = None):
    return { "dump": dump }

DumpInfo, _new_dumpinfo = provider(
    fields = { "dump": "Dump file generated by e.g. -dlambda" },
    init = _DumpInfo_init
)

##############################################################
def _NsResolverInfo_init(*, sigs = None, structs = None):
    return { "sigs" : sigs, "structs": structs }

NsResolverInfo, _new_nsresolverinfo = provider(
    fields = {
        "sigs"   : "depset of .cmi files",
        "structs": "depsetof .cmo or .cmx files",
    },
    init = _NsResolverInfo_init
)


##########################
def _BootInfo_init(*,
                   sigs          = [],
                   structs       = [],
                   cli_link_deps = [],
                   afiles        = [],
                   ofiles        = [],
                   archived_cmx  = [],
                   mli           = [],
                   paths         = [],
                   # ofiles      = [],
                   # archives    = [],
                   # astructs    = [],
                   # cmts        = [],
                        ):
    return {
        "sigs"          : sigs,
        "structs"       : structs,
        "cli_link_deps" : cli_link_deps,
        "afiles"        : afiles,
        "ofiles"        : ofiles,
        "archived_cmx"  : archived_cmx,
        "mli"           : mli,
        "paths"         : paths,
    }

BootInfo, _new_ocamlbootinfo = provider(
    doc = "foo",
    fields = {
        "sigs"          : "Depset of .cmi files. always added to inputs, never to cmd line.",
        "structs"       : "Depset of unarchived .cmo or .cmx files.",
        "cli_link_deps" : "Depset of cm[x]a and cm[x|o] files to be added to inputs and link cmd line (executables and archives).",
        "afiles"        : "Depset of the .a files that go with .cmxa files",
        "ofiles"        : "Depset of the .o files that go with .cmx files",
        "archived_cmx"  : "Depset of archived .cmx and .o files. always added to inputs, never to cmd line.",
        "mli"           : ".mli files needed for .ml compilation",
        "paths"         : "string depset, for efficiency",
        # "ofiles"        :    "depset of the .o files that go with .cmx files",
        # "archives"      :  "depset of .cmxa and .cma files",
        # "cma"           :       "depset of .cma files",
        # "cmxa"          :       "depset of .cmxa files",
        # "astructs"      :  "depset of archived structs, added to link depgraph but not command line.",
        # "cmts"          :      "depset of cmt/cmti files",
    },
    init = _BootInfo_init
)

##########################
DepsAggregator = provider(
    fields = {
        "deps"    : "struct of BootInfo providers",
        "ccinfos" : "list of CcInfo providers",
    }
)

def new_deps_aggregator():
    return DepsAggregator(
        deps = BootInfo(
            sigs          = [],
            structs       = [],
            cli_link_deps = [],
            afiles        = [],
            ofiles        = [],
            archived_cmx  = [],
            mli           = [],
            paths         = [],
            # ofiles      = [],
            # archives    = [],
            # astructs    = [], # archived cmx structs, for linking
            # cmts        = [],
        ),
        ccinfos           = []
    )

################################################################
OcamlArchiveProvider = provider(
    doc = """OCaml archive provider.

Produced only by ocaml_archive, ocaml_ns_archive, ocaml_import.  Archive files are delivered in DefaultInfo; this provider holds deps of the archive, to serve as action inputs.
""",
    fields = {
        "manifest": "Depset of direct deps, i.e. members of the archive",
        "files": "file depset of archive's deps",
        "paths": "string depset"
    }
)

# OcamlNsResolverMarker = provider(doc = "OCaml NsResolver Marker provider.")
OcamlNsResolverProvider = provider(
    doc = "OCaml NS Resolver provider.",
    fields = {
        "files"   : "Depset, instead of DefaultInfo.files",
        "paths":    "Depset of paths for -I params",
        "submodules": "String list of submodules in this ns",
        "resolver_file": "file",
        "resolver": "Name of resolver module",
        "prefixes": "List of alias prefix segs",
        "ns_name": "ns name (joined prefixes)"
    }
)

OcamlSignatureProvider = provider(
    doc = "OCaml interface provider.",
    fields = {
        "mli": ".mli input file",
        "cmi": ".cmi output file",
        "cmti": ".cmti output file",

    }
)

# OcamlArchiveMarker    = provider(doc = "OCaml Archive Marker provider.")
OcamlExecutableMarker = provider(doc = "OCaml Executable Marker provider.")
OcamlImportMarker    = provider(doc = "OCaml Library Marker provider.")
OcamlLibraryMarker   = provider(doc = "OCaml Library Marker provider.")
# OcamlModuleMarker    = provider(doc = "OCaml Module Marker provider.")
OcamlNsMarker        = provider(doc = "OCaml Namespace Marker provider.")
OcamlSignatureMarker = provider(doc = "OCaml Signature Marker provider.")
OcamlTestMarker      = provider(doc = "OCaml Test Marker provider.")

StdLibMarker         = provider(doc = "Std compiler Library Marker provider.")
StdStructMarker      = provider(doc = "Std compiler Struct Marker provider.")
StdSigMarker         = provider(doc = "Std compiler Sig Marker provider.")
# CompilerMarker       = provider(doc = "Compiler Marker provider.")
# CompilerSigMarker    = provider(doc = "Compiler Sig Marker provider.")

StdlibLibMarker   = provider(doc = "Stdlib library Marker provider.")
StdlibStructMarker   = provider(doc = "Stdlib Struct Marker provider.")
StdlibSigMarker      = provider(doc = "Stdlib Sig Marker provider.")
TestExecutableMarker = provider(doc = "Test Executable Marker provider.")

################################################################
################ Config Settings ################
CompilationModeSettingProvider = provider(
    doc = "Raw value of compilation_mode_flag or setting",
    fields = {
        "value": "The value of the build setting in the current configuration. " +
                 "This value may come from the command line or an upstream transition, " +
                 "or else it will be the build setting's default.",
    },
)

################
OcamlVerboseFlagProvider = provider(
    doc = "Raw value of ocaml_verbose_flag",
    fields = {
        "value": "The value of the build setting in the current configuration. " +
                 "This value may come from the command line or an upstream transition, " +
                 "or else it will be the build setting's default.",
    },
)


OcamlVmRuntimeProvider = provider(
    doc = "OCaml VM Runtime provider",
    fields = {
        "kind": "string: dynamic (default), static, or standalone"
    }
)

