package main

import simp "../src"
import lib "../src/lib"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import db "debug"

// TODO: Actually use proper platform code
when ODIN_OS == .Windows {
    foreign import kernel32 "system:Kernel32.lib"

    @(default_calling_convention = "system")
    foreign kernel32 {
        GetConsoleMode :: proc(hConsoleHandle: rawptr, lpMode: ^u32) -> b32 ---
        SetConsoleMode :: proc(hConsoleHandle: rawptr, dwMode: u32) -> b32 ---
        GetStdHandle :: proc(nStdHandle: u32) -> rawptr ---
    }

    _saved_input_mode: u32
    _saved_output_mode: u32
    _stdin_handle: rawptr
    _stdout_handle: rawptr

    enable_raw_mode :: proc() {
        _stdin_handle = GetStdHandle(0xFFFFFFF6) // STD_INPUT_HANDLE
        GetConsoleMode(_stdin_handle, &_saved_input_mode)

        new_input_mode := _saved_input_mode
        new_input_mode &= ~(u32(0x0001) | u32(0x0002) | u32(0x0004))
        new_input_mode |= 0x0200 // ENABLE_VIRTUAL_TERMINAL_INPUT
        SetConsoleMode(_stdin_handle, new_input_mode)

        _stdout_handle = GetStdHandle(0xFFFFFFF5) // STD_OUTPUT_HANDLE
        GetConsoleMode(_stdout_handle, &_saved_output_mode)
        SetConsoleMode(_stdout_handle, _saved_output_mode | 0x0004) // ENABLE_VIRTUAL_TERMINAL_PROCESSING
    }

    disable_raw_mode :: proc() {
        SetConsoleMode(_stdin_handle, _saved_input_mode)
        SetConsoleMode(_stdout_handle, _saved_output_mode)
    }
} else {
    enable_raw_mode :: proc() {
        libc.system("stty cbreak -echo")
    }

    disable_raw_mode :: proc() {
        libc.system("stty sane")
    }
}

// TODO: Use flags package
print_usage :: proc() {
    fmt.println("SIMP CLI Utility")
    fmt.println("Usage:")
    fmt.println("  simp                    - Open interactive REPL")
    fmt.println("  simp <filename>         - Run a script or bytecode file")
    fmt.println("  simp compile <in> <out> - 'Compile' a script to bytecode")
    fmt.println("  simp help               - Show this help message")
}

cmd_quit :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    os.exit(0)
}

cmd_vars :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    fmt.println("\n--- Global Variables ---")
    global_scope := state.scopes[0]

    if len(global_scope) == 0 {
        fmt.println("[ Empty ]")
    } else {
        for name, value_slot in global_scope {
            fmt.printfln(" (%s) %s = %s", value_slot.is_const ? "C" : "M", name, simp.value_to_string(value_slot.value))
        }
    }

    return simp.DEFAULT_VALUE
}

run_compile_logic :: proc(input_path: string, output_path: string) {
    file_data, read_error := os.read_entire_file(input_path, context.temp_allocator)

    if read_error != nil {
        fmt.printfln("Error: Could not read input file '%s'", input_path)
        return
    }

    fmt.printfln("Serialising %s -> %s...", input_path, output_path)

    bytecode, compilation_success := simp.serialise_script(string(file_data), input_path)

    if compilation_success {
        write_error := os.write_entire_file(output_path, bytecode)

        if write_error != nil {
            fmt.printfln("Error: Could not write to %s", output_path)
        } else {
            fmt.println("Serialisation successful.")
        }

        delete(bytecode)
    }
}

main :: proc() {
    when ODIN_DEBUG {
        context.allocator = db.init_allocator()
        defer db.unload_allocator()
    } else {
        _ :: db
    }

    state: simp.State
    simp.init_interpreter(&state)
    defer simp.destroy_interpreter(&state)

    simp.register_native_proc(&state, "quit", cmd_quit)
    simp.register_native_proc(&state, "exit", cmd_quit)
    simp.register_native_proc(&state, "vars", cmd_vars)

    // TODO: Add 'load_standard_library proc'
    lib.load_math_library(&state)
    lib.load_strings_library(&state)
    lib.load_struct_library(&state)
    lib.load_io_library(&state)

    command_line_arguments := os.args

    if len(command_line_arguments) == 1 {
        run_repl(&state)
        return
    }

    subcommand := command_line_arguments[1]
    switch subcommand {
    case "help", "-h", "--help":
        print_usage()

    case "compile":
        if len(command_line_arguments) < 3 {
            fmt.println("Error: 'compile' requires input file.")
            os.exit(1)
        }

        output_file: string
        if len(command_line_arguments) >= 4 {
            output_file = command_line_arguments[3]
        } else {
            output_file = fmt.tprintf("%s.sbin", filepath.short_stem(command_line_arguments[2]))
        }

        run_compile_logic(command_line_arguments[2], output_file)

    case:
        file_path := subcommand

        if os.is_file(file_path) {
            simp.execute_script_from_file(&state, file_path)
        } else {
            fmt.printfln("Error: Unknown command or file '%s'", file_path)
            print_usage()
            os.exit(1)
        }
    }
}

run_repl :: proc(state: ^simp.State) {
    fmt.println("=======================================")
    fmt.println("                SIMP REPL              ")
    fmt.println(" Type 'quit' to exit, 'vars' for state ")
    fmt.println("=======================================")

    command_history := make([dynamic]string)
    defer {
        for command in command_history {
            delete(command)
        }

        delete(command_history)
    }

    script_accumulator := strings.builder_make()
    persistent_definitions := strings.builder_make()

    defer strings.builder_destroy(&script_accumulator)
    defer strings.builder_destroy(&persistent_definitions)

    block_depth := 0

    for !state.should_close {
        indentation_string := ""
        unindent_string := ""

        if block_depth > 0 {
            indentation_string = strings.repeat("    ", block_depth, context.temp_allocator)
            unindent_string = strings.repeat("    ", block_depth - 1, context.temp_allocator)
        }

        prompt_prefix := block_depth == 0 ? "> " : "~ "
        normal_prompt := fmt.tprintf("%s%s", prompt_prefix, indentation_string)
        unindented_prompt := fmt.tprintf("%s%s", prompt_prefix, unindent_string)

        input_line := read_interactive_line(state, normal_prompt, unindented_prompt, &command_history)

        if len(strings.trim_space(input_line)) == 0 {
            if block_depth > 0 {
                strings.write_string(&script_accumulator, "\n")
                continue
            }
            free_all(context.temp_allocator)
            continue
        }

        depth_change := get_block_depth_change(input_line)

        block_depth += depth_change
        if block_depth < 0 {
            block_depth = 0
        }

        strings.write_string(&script_accumulator, input_line)
        strings.write_string(&script_accumulator, "\n")

        if block_depth == 0 {
            full_code := strings.to_string(script_accumulator)
            trimmed_code := strings.trim_space(full_code)

            is_definition := strings.has_prefix(trimmed_code, "function ") || strings.has_prefix(trimmed_code, "function(") || strings.has_prefix(trimmed_code, "import ")

            if is_definition {
                simp.execute_script(state, full_code, "REPL")

                if state.should_close {
                    state.should_close = false
                } else {
                    strings.write_string(&persistent_definitions, full_code)
                    strings.write_string(&persistent_definitions, "\n")
                }
            } else {
                final_script := fmt.tprintf("%s\n%s", strings.to_string(persistent_definitions), full_code)
                simp.execute_script(state, final_script, "REPL")

                if state.should_close {
                    state.should_close = false
                }
            }

            os.flush(os.stdout)
            strings.builder_reset(&script_accumulator)
        }

        free_all(context.temp_allocator)
    }
}

get_block_depth_change :: proc(input_line: string) -> int {
    change := 0
    in_string := false

    char_index := 0
    for char_index < len(input_line) {
        current_char := input_line[char_index]

        if current_char == '"' {
            in_string = !in_string
            char_index += 1
            continue
        }

        if !in_string && ((current_char >= 'a' && current_char <= 'z') || (current_char >= 'A' && current_char <= 'Z')) {
            start_index := char_index
            for char_index < len(input_line) &&
                ((input_line[char_index] >= 'a' && input_line[char_index] <= 'z') || (input_line[char_index] >= 'A' && input_line[char_index] <= 'Z') || (input_line[char_index] >= '0' && input_line[char_index] <= '9') || input_line[char_index] == '_') {
                char_index += 1
            }

            word := input_line[start_index:char_index]
            switch word {
            case "function", "while", "for", "foreach":
                change += 1
            case "if":
                if strings.contains(input_line, "then") {
                    trimmed := strings.trim_space(input_line)
                    if strings.has_suffix(trimmed, "then") {
                        change += 1
                    }
                }
            case "end":
                change -= 1
            }
            continue
        }
        char_index += 1
    }
    return change
}

repl_has_var :: proc(state: ^simp.State, name: string) -> bool {
    if name == "_" {
        return false
    }
    for i := len(state.scopes) - 1; i >= 0; i -= 1 {
        if name in state.scopes[i] {
            return true
        }
    }
    return false
}

highlight_simp_code :: proc(state: ^simp.State, input: string) -> string {
    builder := strings.builder_make(context.temp_allocator)
    index := 0

    paren_depth := 0
    bracket_depth := 0

    expecting_declaration := false

    for index < len(input) {
        character := input[index]

        // Strings (Green)
        if character == '"' {
            strings.write_string(&builder, "\033[32m")
            strings.write_byte(&builder, character)
            index += 1
            for index < len(input) {
                current_char := input[index]
                strings.write_byte(&builder, current_char)

                if current_char == '"' && input[index - 1] != '\\' {
                    index += 1
                    break
                }
                index += 1
            }
            strings.write_string(&builder, "\033[0m")
            continue
        }

        // Comments (Gray)
        if character == '/' && index + 1 < len(input) && input[index + 1] == '/' {
            strings.write_string(&builder, "\033[90m")
            for index < len(input) {
                strings.write_byte(&builder, input[index])
                index += 1
            }
            strings.write_string(&builder, "\033[0m")
            continue
        }

        // Numbers (Yellow) and Invalid Numbers (Red)
        if character >= '0' && character <= '9' {
            start_num := index
            dot_count := 0

            for index < len(input) && ((input[index] >= '0' && input[index] <= '9') || input[index] == '.') {
                if input[index] == '.' {
                    dot_count += 1
                }
                index += 1
            }

            if dot_count > 1 {
                // Syntax Error: Invalid Number (Red)
                strings.write_string(&builder, "\033[31m")
                strings.write_string(&builder, input[start_num:index])
                strings.write_string(&builder, "\033[0m")
            } else {
                // Valid Number (Yellow)
                strings.write_string(&builder, "\033[33m")
                strings.write_string(&builder, input[start_num:index])
                strings.write_string(&builder, "\033[0m")
            }
            continue
        }

        is_alpha :: proc(c: u8) -> bool {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
        }
        is_alphanum :: proc(c: u8) -> bool {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
        }

        if is_alpha(character) {
            start := index
            for index < len(input) && is_alphanum(input[index]) {
                index += 1
            }
            word := input[start:index]

            color := ""
            switch word {
            case "while", "for", "foreach", "in", "break", "continue", "function", "end", "then", "else", "if", "to", "step", "return", "and", "or", "not":
                color = "\033[36m" // Cyan for Control Flow
                expecting_declaration = false
            case "let", "const":
                color = "\033[36m" // Cyan for Declarations
                expecting_declaration = true
            case "import", "put", "sleep", "delete":
                color = "\033[35m" // Magenta for Directives
                expecting_declaration = false
            case "true", "false", "null", "object", "array", "int", "float", "string", "bool", "len", "type":
                color = "\033[34m" // Blue for Core Types, Constants, and Casts
                expecting_declaration = false
            case:
                if expecting_declaration {
                    if repl_has_var(state, word) {
                        color = "\033[31m" // RED (Redeclaration error!)
                    }
                    expecting_declaration = false
                } else {
                    // Check if it's a function call (followed by '(' )
                    lookahead := index
                    for lookahead < len(input) && (input[lookahead] == ' ' || input[lookahead] == '\t') {
                        lookahead += 1
                    }
                    if lookahead < len(input) && input[lookahead] == '(' {
                        color = "\033[33m" // Yellow for Functions
                    }
                }
            }

            if color != "" {
                strings.write_string(&builder, color)
                strings.write_string(&builder, word)
                strings.write_string(&builder, "\033[0m")
            } else {
                strings.write_string(&builder, word) // Default color
            }
            continue
        }

        if character != ' ' && character != '\t' {
            expecting_declaration = false
        }

        // --- SYNTAX ERRORS (BRIGHT RED) ---
        if character == '(' {
            paren_depth += 1
        } else if character == ')' {
            paren_depth -= 1
            if paren_depth < 0 {
                strings.write_string(&builder, "\033[31m)\033[0m")
                paren_depth = 0
                index += 1
                continue
            }
        } else if character == '[' {
            bracket_depth += 1
        } else if character == ']' {
            bracket_depth -= 1
            if bracket_depth < 0 {
                strings.write_string(&builder, "\033[31m]\033[0m")
                bracket_depth = 0
                index += 1
                continue
            }
        } else if character == '@' || character == '#' || character == '^' || character == '&' || character == '`' || character == '~' {
            strings.write_string(&builder, "\033[31m")
            strings.write_byte(&builder, character)
            strings.write_string(&builder, "\033[0m")
            index += 1
            continue
        }

        strings.write_byte(&builder, character)
        index += 1
    }

    return strings.to_string(builder)
}

read_interactive_line :: proc(state: ^simp.State, normal_prompt: string, unindented_prompt: string, history: ^[dynamic]string) -> string {
    enable_raw_mode()
    defer disable_raw_mode()

    input_buffer := make([dynamic]u8, context.temp_allocator)
    cursor_position := 0
    history_index := len(history^)

    current_prompt := normal_prompt

    // Initial render does not clear as 'put' directive does not insert a new line by default
    fmt.print(current_prompt)
    os.flush(os.stdout)

    byte_read_buffer: [1]u8
    for {
        bytes_count, read_error := os.read(os.stdin, byte_read_buffer[:])
        if read_error != nil || bytes_count == 0 {
            continue
        }

        character := byte_read_buffer[0]

        // CTRL + C
        if character == 3 {
            disable_raw_mode()
            fmt.println()
            os.exit(0)
        }

        // CTRL + D
        if character == 4 && len(input_buffer) == 0 {
            fmt.println()
            return ""
        }

        if character == '\r' || character == '\n' {
            fmt.println()
            break
        }

        // BACKSPACE
        if character == 127 || character == '\b' {
            if cursor_position > 0 {
                for index := cursor_position - 1; index < len(input_buffer) - 1; index += 1 {
                    input_buffer[index] = input_buffer[index + 1]
                }
                pop(&input_buffer)
                cursor_position -= 1

                trimmed := strings.trim_space(string(input_buffer[:]))
                if trimmed == "end" || trimmed == "else" {
                    current_prompt = unindented_prompt
                } else {
                    current_prompt = normal_prompt
                }

                _render_line(state, current_prompt, input_buffer[:], cursor_position)
            }
            continue
        }

        // ARROW KEYS
        if character == 27 {
            os.read(os.stdin, byte_read_buffer[:])
            if byte_read_buffer[0] == '[' {
                os.read(os.stdin, byte_read_buffer[:])
                direction := byte_read_buffer[0]

                switch direction {
                // Up
                case 'A':
                    if history_index > 0 {
                        history_index -= 1
                        clear(&input_buffer)

                        for char in history^[history_index] {
                            append(&input_buffer, u8(char))
                        }

                        cursor_position = len(input_buffer)

                        trimmed := strings.trim_space(string(input_buffer[:]))
                        if trimmed == "end" || trimmed == "else" {
                            current_prompt = unindented_prompt
                        } else {
                            current_prompt = normal_prompt
                        }

                        _render_line(state, current_prompt, input_buffer[:], cursor_position)
                    }

                // Down
                case 'B':
                    if history_index < len(history^) - 1 {
                        history_index += 1
                        clear(&input_buffer)

                        for char in history^[history_index] {
                            append(&input_buffer, u8(char))
                        }

                        cursor_position = len(input_buffer)

                        trimmed := strings.trim_space(string(input_buffer[:]))
                        if trimmed == "end" || trimmed == "else" {
                            current_prompt = unindented_prompt
                        } else {
                            current_prompt = normal_prompt
                        }

                        _render_line(state, current_prompt, input_buffer[:], cursor_position)
                    } else if history_index == len(history^) - 1 {
                        history_index += 1
                        clear(&input_buffer)
                        cursor_position = 0
                        current_prompt = normal_prompt

                        _render_line(state, current_prompt, input_buffer[:], cursor_position)
                    }

                // Right
                case 'C':
                    if cursor_position < len(input_buffer) {
                        cursor_position += 1
                        _render_line(state, current_prompt, input_buffer[:], cursor_position)
                    }

                // Left
                case 'D':
                    if cursor_position > 0 {
                        cursor_position -= 1
                        _render_line(state, current_prompt, input_buffer[:], cursor_position)
                    }
                }
            }
            continue
        }

        // NORMAL CHARACTERS
        if character >= 32 && character <= 126 {
            append(&input_buffer, 0)

            for index := len(input_buffer) - 1; index > cursor_position; index -= 1 {
                input_buffer[index] = input_buffer[index - 1]
            }

            input_buffer[cursor_position] = character
            cursor_position += 1

            trimmed := strings.trim_space(string(input_buffer[:]))
            if trimmed == "end" || trimmed == "else" {
                current_prompt = unindented_prompt
            } else {
                current_prompt = normal_prompt
            }

            _render_line(state, current_prompt, input_buffer[:], cursor_position)
        }
    }

    result := strings.clone_from_bytes(input_buffer[:], context.temp_allocator)
    if len(result) > 0 {
        if len(history^) == 0 || history^[len(history^) - 1] != result {
            append(history, strings.clone(result))
        }
    }

    return result
}

_render_line :: proc(state: ^simp.State, prompt: string, buffer: []u8, cursor: int) {
    fmt.print("\r\033[2K") // Clear line
    fmt.print(prompt)

    colored_output := highlight_simp_code(state, string(buffer))
    fmt.print(colored_output)

    if cursor < len(buffer) {
        fmt.printf("\033[%dD", len(buffer) - cursor)
    }

    os.flush(os.stdout)
}
