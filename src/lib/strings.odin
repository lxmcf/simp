package lib

import simp "../"
import "core:strings"

load_strings_library :: proc(state: ^simp.State) {
    simp.bind_native_proc(state, "sub", fn_sub)
    simp.bind_native_proc(state, "replace", fn_replace)
    simp.bind_native_proc(state, "upper", fn_upper)
    simp.bind_native_proc(state, "lower", fn_lower)
    simp.bind_native_proc(state, "trim", fn_trim)
    simp.bind_native_proc(state, "contains", fn_contains)
}

// sub(text, start, length) -> "llo"
fn_sub :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    target_string, is_string := simp.pop_string(&args)
    start_index, is_valid_start := simp.pop_int(&args)
    length, is_valid_length := simp.pop_int(&args)

    if is_string && is_valid_start && is_valid_length {
        start_idx := int(start_index)
        len_idx := int(length)

        if start_idx >= 0 && start_idx < len(target_string) {
            end_index := start_idx + len_idx

            if end_index > len(target_string) {
                end_index = len(target_string)
            }

            if end_index >= start_idx {
                return target_string[start_idx:end_index]
            }
        }
    }

    return simp.DEFAULT_VALUE
}

// replace(text, old_str, new_str) -> text with replaced values
fn_replace :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    target_string, is_target_string := simp.pop_string(&args)
    old_string, is_old_string := simp.pop_string(&args)
    new_string, is_new_string := simp.pop_string(&args)

    if is_target_string && is_old_string && is_new_string {
        replaced_value, _ := strings.replace(target_string, old_string, new_string, -1, context.temp_allocator)
        return replaced_value
    }

    return simp.DEFAULT_VALUE
}

// upper(text)
fn_upper :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if target_string, is_string := simp.pop_string(&args); is_string {
        return strings.to_upper(target_string, context.temp_allocator)
    }

    return simp.DEFAULT_VALUE
}

// lower(text)
fn_lower :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments
    if target_string, is_string := simp.pop_string(&args); is_string {
        return strings.to_lower(target_string, context.temp_allocator)
    }
    return simp.DEFAULT_VALUE
}

// trim(text) -> Removes leading and trailing whitespace
fn_trim :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if target_string, is_string := simp.pop_string(&args); is_string {
        return strings.trim_space(target_string)
    }

    return simp.DEFAULT_VALUE
}

// contains(text, search_str) -> true if found
fn_contains :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    target_string, is_target_string := simp.pop_string(&args)
    search_string, is_search_string := simp.pop_string(&args)

    if is_target_string && is_search_string {
        return strings.contains(target_string, search_string)
    }

    return false
}
