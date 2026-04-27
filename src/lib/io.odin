package lib

import simp "../"
import "core:fmt"

load_io_library :: proc(state: ^simp.State) {
    simp.bind_native_proc(state, "print", fn_print)
}

// print (foor, bar, baz)
fn_print :: proc(instance: ^simp.State, arguments: []simp.Value) {
    for argument, index in arguments {
        if index > 0 {
            fmt.print(" ")
        }

        fmt.print(simp.value_to_string(argument))
    }

    fmt.println()
}
