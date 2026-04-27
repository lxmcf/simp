package lib

import simp "../"

load_struct_library :: proc(state: ^simp.State) {
    simp.bind_native_proc(state, "has_key", fn_has_key)
    simp.bind_native_proc(state, "push", fn_push)
    simp.bind_native_proc(state, "pop", fn_pop)
}

// has_key(object_reference, "key")
fn_has_key :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if object_reference, is_object := simp.pop_object(&args); is_object {
        if len(args) > 0 {
            key := simp.value_to_string(args[0])

            return key in object_reference
        }
    }

    return false
}

// push(array_reference, value) -> Appends a value to an array
fn_push :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if array_reference, is_array := simp.pop_array(&args); is_array {
        if len(args) > 0 {
            append(array_reference, args[0])

            return true
        }
    }

    return false
}

// pop(array_reference) -> Removes and returns the last element of an array
fn_pop :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if array_reference, is_array := simp.pop_array(&args); is_array {
        if len(array_reference^) > 0 {
            return pop(array_reference)
        }
    }

    return simp.DEFAULT_VALUE
}
