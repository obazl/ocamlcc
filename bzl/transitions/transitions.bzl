load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

##############################################
def tc_target_transitions(settings, attr, debug):
    debug = True
    if debug: print("tc_target_transitions")

    ## we use the CLI string flags in //config/...
    ## to set string settings in //toolchain/...

    config_executor = settings["//config/target/executor"]
    config_emitter  = settings["//config/target/emitter"]
    # target_runtime  = settings["//toolchain:runtime"]

    # compiler = settings["//toolchain:compiler"]
    # lexer = settings["//toolchain:lexer"]

    # build_host  = settings["//command_line_option:host_platform"]
    # extra_execution_platforms = settings["//command_line_option:extra_execution_platforms"]

    # target_host = settings["//command_line_option:platforms"]

    # stage = int(settings["//config/stage"])

    if debug:
        # print("//config/stage: %s" % stage)
        print("//config/target/executor: %s" % settings[
            "//config/target/executor"])
        print("//config/target/emitter:  %s" % settings[
            "//config/target/emitter"])

    # host_compilation_mode = "opt"
    # compilation_mode = "opt"
    # runtime  = "//runtime:ocamlrun"

    ## initial config: config settings passed on cli, toolchain
    ## configs default to unspecified

    if config_executor == "boot":
        # base case - no change
        return config_executor, config_emitter
    elif (config_executor == "baseline"):
        config_executor = "boot"
        config_emitter  = "boot"
    elif (config_executor == "vm" and config_emitter == "vm"):
        config_executor = "baseline"
        config_emitter  = "baseline"
    elif (config_executor == "vm" and config_emitter == "sys"):
        config_executor = "vm"
        config_emitter = "vm"
    elif (config_executor == "sys" and config_emitter == "sys"):
        config_executor = "vm"
        config_emitter  = "sys"
    elif (config_executor == "sys" and config_emitter == "vm"):
        config_executor = "sys"
        config_emitter  = "sys"
    else:
        fail("xxxxxxxxxxxxxxxx %s" % config_executor)

    return (config_executor, config_emitter)

##############################################
# def tc_lexer_out_transition_impl(settings, attr, debug):

#     debug = True
#     if debug: print("tc_lexer_out_transition")

#     config_executor, config_emitter = tc_target_transitions(settings, attr, debug)

#     # compiler = settings["//toolchain:compiler"]
#     # lexer = settings["//toolchain:lexer"]

#     if debug:
#         print("//toolchain:lexer:  %s" % settings["//toolchain:lexer"])

#     if config_executor == "boot":
#         print("lextxn BASE CASE")
#         lexer    = "//boot:ocamllex.boot"
#     # elif (config_executor == "baseline"):
#     #     print("lextxn BASELINE TRANSITION")
#     #     lexer    = "//lex:ocamllex.byte"
#     #     # lexer    = "//boot:ocamllex.boot"
#     else:
#         lexer    = "//lex:ocamllex"

#     # elif (config_executor == "vm" and config_emitter == "vm"):
#     #     print("lextxn VM-VM TRANSITION")
#     #     lexer    = "//lex:ocamllex.byte"
#     # elif (config_executor == "vm" and config_emitter == "sys"):
#     #     print("lextxn VM-SYS TRANSITION")
#     #     lexer    = "//lex:ocamllex.byte"
#     # elif (config_executor == "sys" and config_emitter == "sys"):
#     #     print("lextxn SYS-SYS TRANSITION")
#     #     lexer    = "//lex:ocamllex.byte"
#     # elif (config_executor == "sys" and config_emitter == "vm"):
#     #     print("lextxn SYS-VM TRANSITION")
#     #     lexer    = "//lex:ocamllex.byte"
#     # else:
#     #     fail("xxxxxxxxxxxxxxxx %s" % config_executor)

#     if debug:
#         print("setting //config/target/executor: %s" % config_executor)
#         print("setting //config/target/emitter: %s" % config_emitter)
#         # print("setting //toolchain:compiler %s" % compiler)
#         print("setting //toolchain:lexer %s" % lexer)

#     return {
#         "//config/target/executor": config_executor,
#         "//config/target/emitter" : config_emitter,

#         "//toolchain:compiler": settings["//toolchain:compiler"],
#         "//toolchain:lexer"   : lexer,
#         "//toolchain:runtime" : settings["//toolchain:runtime"],
#         "//toolchain:cvt_emit" : settings["//toolchain:cvt_emit"]
#     }

##############################################
def tc_mustache_transition_impl(settings, attr, debug):
    debug = True

    if debug: print("tc_mustache_transition_impl")

    return {
        # "//command_line_option:host_compilation_mode": "opt",
        # "//command_line_option:compilation_mode": "opt",

        "//config/target/executor": "boot",
        "//config/target/emitter" : "boot",

        "//toolchain:compiler" : "//boot:ocamlc.boot",
        # "//toolchain:lexer"    : "//boot:ocamllex.boot",
        "//toolchain:runtime"  : settings["//toolchain:runtime"]
    }

#####################################################
## reset_config_transition
# reset stage to 0 (_boot) so runtime is only built once
def xreset_config_transition_impl(settings, attr):
    debug = True

    if debug: print("reset_config_transition: %s" % attr.name)

    return {
        "//config/target/executor": "boot",
        "//config/target/emitter" : "boot",

        "//toolchain:compiler" : "//boot:ocamlc.boot",
        # "//toolchain:lexer"    : "//boot:ocamllex.boot",
        "//toolchain:runtime"  : settings["//toolchain:runtime"]
    }

