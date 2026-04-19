package lib

import simp "../"

load_standard_library :: proc(state: ^simp.State) {
    load_io_library(state)
    load_math_library(state)
    load_strings_library(state)
    load_struct_library(state)
}
