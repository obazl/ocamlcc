
#####################################################
## reset_cc_config_transition - called only for mustache._tool
# resets to fixed config so mustache will only be built once
# applies to:
# __asm
# config_ml
# domain_state_h
# domainstate_ml
# domainstate_mli
# fail_h
# instruct_h
# jumptbl_h
# opcodes_ml
# opnames_h
# primitives_dat
# primitives_h
# prims_c
# runtimedef_ml
# stdlib_ml
# stdlib_mli

## same config everytime, should mean only one build?
def _reset_cc_config_transition_impl(settings, attr):
    debug = False
    if debug:
        print("reset_cc_config_transition: %s" % attr.name)

    if settings["//runtime"] == "dbg":
        mode = "dbg"
    # if //runtime:DEBUG then mode = ???
    else:
        mode = "opt"

    return {
        "//command_line_option:host_compilation_mode": mode,
        "//command_line_option:compilation_mode"     : mode,

        ## these are not used by cc targets, so we set them to a
        ## unique dummy value so that the transition is always to the
        ## same configuration, so that we only build once.
        "//config/build/protocol" : "null",
        "//config/target/executor": "null",
        "//config/target/emitter" : "null",

        "//toolchain:compiler" : "//boot:ocamlc.boot",
        "//toolchain:ocamlrun" : "//runtime:ocamlrun",
        # "//toolchain:runtime"  : "//runtime:asmrun",
        # "//toolchain:cvt_emit" : "//:BUILD.bazel",
    }

#######################
reset_cc_config_transition = transition(
    implementation = _reset_cc_config_transition_impl,
    inputs = [
        "//runtime",
        "//toolchain:runtime",
        "//toolchain:ocamlrun",
    ],
    outputs = [
        "//command_line_option:host_compilation_mode",
        "//command_line_option:compilation_mode",

        "//config/build/protocol",
        "//config/target/executor",
        "//config/target/emitter",

        "//toolchain:compiler",
        "//toolchain:ocamlrun",
        # "//toolchain:runtime",
    ]
)
