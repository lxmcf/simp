package main

import "core:fmt"

import simp "../src"

cmd_vars :: proc(state: ^simp.State, arguments: []simp.Value) {
    fmt.println("\n--- Global Variables ---")
    global_scope := state.scopes[0]

    if len(global_scope) == 0 {
        fmt.println("[ Empty ]")
    } else {
        for name, value_slot in global_scope {
            fmt.printfln(" (%s) %s = %s", value_slot.is_const ? "C" : "M", name, simp.value_to_string(value_slot.value))
        }
    }
}

cmd_help :: proc(state: ^simp.State, arguments: []simp.Value) {
    fmt.print(ANSI_GREEN_BOLD)
    fmt.println("\n--- Native Functions ---")
    fmt.print(ANSI_RESET)

    if len(state.native_procs) == 0 {
        fmt.println("[ Empty ]")
    } else {
        for key in state.native_procs {
            fmt.print(ANSI_YELLOW)
            fmt.printfln(" %s", key)
            fmt.print(ANSI_RESET)
        }
    }

    fmt.print(ANSI_GREEN_BOLD)
    fmt.println("\n--- User Functions ---")
    fmt.print(ANSI_RESET)

    if len(state.functions) == 0 {
        fmt.println("[ Empty ]")
    } else {
        for key, func in state.functions {
            fmt.print(ANSI_YELLOW)
            fmt.printf(" %s ", key)
            fmt.print(ANSI_RESET)

            fmt.printf("(")

            for arg, idx in func.arguments {
                if idx > 0 {
                    fmt.print(", ")
                }

                fmt.print(arg)
            }

            fmt.println(")")
        }
    }
}

cmd_theme :: proc(state: ^simp.State, arguments: []simp.Value) {
    args := arguments

    if theme_name, ok := simp.pop_string(&args); ok {
        switch theme_name {
        case "solarized":
            global_config.theme = SOLARIZED_THEME
        case "dracula":
            global_config.theme = DRACULA_THEME
        case "monokai":
            global_config.theme = MONOKAI_THEME
        case "nord":
            global_config.theme = NORD_THEME
        }
    }
}

register_native_procs :: proc(state: ^simp.State) {
    simp.bind_native_proc(state, "vars", cmd_vars)
    simp.bind_native_proc(state, "help", cmd_help)
    simp.bind_native_proc(state, "set_theme", cmd_theme)
}
