package lib

import simp "../"
import "core:fmt"
import "core:os"

load_io_library :: proc(state: ^simp.State) {
    simp.bind_native_proc(state, "print", fn_print)
    simp.bind_native_proc(state, "read_file", fn_read_file)
    simp.bind_native_proc(state, "write_file", fn_write_file)
    simp.bind_native_proc(state, "append_file", fn_append_file)
    simp.bind_native_proc(state, "file_exists", fn_file_exists)
    simp.bind_native_proc(state, "delete_file", fn_delete_file)
}

// print(arg1, arg2, ...)
fn_print :: proc(state: ^simp.State, arguments: []simp.Value) {
    for argument, index in arguments {
        if index > 0 {
            fmt.print(" ")
        }

        fmt.print(simp.value_to_string(argument))
    }

    fmt.println()
}

// read_file("path/to/file.txt") -> string
fn_read_file :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if path, ok := simp.pop_string(&args); ok {
        if file_data, read_error := os.read_entire_file(path, context.temp_allocator); read_error == nil {
            return simp.intern_string(state, string(file_data))
        }
    }

    return simp.DEFAULT_RETURN_VALUE
}

// write_file("path/to/file.txt", "File contents") -> bool
fn_write_file :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    path, path_ok := simp.pop_string(&args)
    content, content_ok := simp.pop_string(&args)

    if path_ok && content_ok {
        write_error := os.write_entire_file(path, content)
        return write_error == nil
    }

    return false
}

// append_file("path/to/file.txt", "Appended contents") -> bool
fn_append_file :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    path, path_ok := simp.pop_string(&args)
    content, content_ok := simp.pop_string(&args)

    if path_ok && content_ok {
        if file_handle, err := os.open(path, os.O_APPEND | os.O_CREATE | os.O_WRONLY); err == nil {
            defer os.close(file_handle)

            _, write_error := os.write_string(file_handle, content)

            return write_error == nil
        }
    }

    return false
}

// file_exists("path/to/file.txt") -> bool
fn_file_exists :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if path, ok := simp.pop_string(&args); ok {
        return os.exists(path)
    }

    return false
}

// delete_file("path/to/file.txt") -> bool
fn_delete_file :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if path, ok := simp.pop_string(&args); ok {
        err := os.remove(path)
        return err == nil
    }

    return false
}
