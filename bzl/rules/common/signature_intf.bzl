#######################
def signature_attrs():

    return dict(

        primitives = attr.label(
            # default = "//runtime:primitives",
            allow_single_file = True,
        ),

        _stage = attr.label(
            doc = "bootstrap stage",
            default = "//bzl:stage"
        ),

        opts             = attr.string_list(
            doc          = "List of OCaml options. Will override configurable default options."
        ),

        warnings = attr.string_list(
            doc = "List of ids, with or without '-' prefix. Do not include '-w'"
        ),

        ## GLOBAL CONFIGURABLE DEFAULTS (all ppx_* rules)
        # _debug           = attr.label(default = "@ocaml//debug"),
        # _cmt             = attr.label(default = "@ocaml//cmt"),
        # _keep_locs       = attr.label(default = "@ocaml//keep-locs"),
        # _noassert        = attr.label(default = "@ocaml//noassert"),
        # _opaque          = attr.label(default = "@ocaml//opaque"),
        # _short_paths     = attr.label(default = "@ocaml//short-paths"),
        # _strict_formats  = attr.label(default = "@ocaml//strict-formats"),
        # _strict_sequence = attr.label(default = "@ocaml//strict-sequence"),
        # _verbose         = attr.label(default = "@ocaml//verbose"),

        # _mode       = attr.label(
        #     default = "@ocaml//mode",
        # ),

        # _sdkpath = attr.label(
        #     default = Label("@ocaml//:sdkpath") # ppx also uses this
        # ),

        src = attr.label(
            doc = "A single .mli source file label",
            allow_single_file = [".mli", ".ml"] #, ".cmi"]
        ),

        ns = attr.label(
            doc = "Bottom-up namespacing",
            allow_single_file = True,
            mandatory = False
        ),

        _pack_ns = attr.label(
            doc = """Namepace name for use with -for-pack. Set by transition function.
""",
            # default = "//config/pack:ns"
        ),

        # pack = attr.string(
        #     doc = "Experimental",
        # ),

        deps = attr.label_list(
            doc = "List of OCaml dependencies. Use this for compiling a .mli source file with deps. See [Dependencies](#deps) for details.",
            # cfg = compile_mode_out_transition,
            providers = [
                # BootInfo,  ## bug

                # [OcamlArchiveProvider],
                # # [OcamlImportMarker],
                # [OcamlLibraryMarker],
                # [OcamlModuleMarker],
                # [OcamlSigMarker],
                # [OcamlNsMarker],
            ],
        ),

        data = attr.label_list(
            allow_files = True
        ),

        _manifest = attr.label(
            default = "//config:manifest"
        ),

        ################################################################
        # _ns_resolver = attr.label(
        #     doc = "Experimental",
        #     providers = [OcamlNsResolverProvider],
        #     # default = "@ocaml//ns:bootstrap",
        #     default = "@ocaml//bootstrap/ns:resolver",
        # ),

        # _ns_submodules = attr.label( # _list(
        #     doc = "Experimental.  May be set by ocaml_ns_library containing this module as a submodule.",
        #     default = "@ocaml//ns:submodules", ## NB: ppx modules use ocaml_signature
        # ),

        ################################################################


        # opts = attr.string_list(doc = "List of OCaml options."),

        # mode       = attr.string(
        #     doc     = "Compilation mode, 'bytecode' or 'native'",
        #     default = "bytecode"
        # ),

        # _debug           = attr.label(default = "@ocaml//debug"),

        ## RULE DEFAULTS
        # _linkall     = attr.label(default = "@ocaml//signature/linkall"), # FIXME: call it alwayslink?
        # _threads     = attr.label(default = "@ocaml//signature/threads"),
        # _warnings  = attr.label(default = "@ocaml//signature:warnings"),

        #### end options ####

        # src = attr.label(
        #     doc = "A single .mli source file label",
        #     allow_single_file = [".mli", ".ml"] #, ".cmi"]
        # ),

        # ns_submodule = attr.label_keyed_string_dict(
        #     doc = "Extract cmi file from namespaced module",
        #     providers = [
        #         [OcamlNsMarker, OcamlArchiveProvider],
        #     ]
        # ),

        # as_cmi = attr.string(
        #     doc = "For use with ns_module only. Creates a symlink from the extracted cmi file."
        # ),

        # pack = attr.string(
        #     doc = "Experimental",
        # ),

        # deps = attr.label_list(
        #     doc = "List of OCaml dependencies. Use this for compiling a .mli source file with deps. See [Dependencies](#deps) for details.",
        #     providers = [
        #         [BootInfo],
        #         [OcamlArchiveProvider],
        #         [OcamlImportMarker],
        #         [OcamlLibraryMarker],
        #         [OcamlModuleMarker],
        #         [OcamlNsMarker],
        #     ],
        #     # cfg = ocaml_signature_deps_out_transition
        # ),

        # data = attr.label_list(
        #     allow_files = True
        # ),

        # _allowlist_function_transition = attr.label(
        #     default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        # ),
    )
