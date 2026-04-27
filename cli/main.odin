package main

import simp "../src"
import lib "../src/lib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import db "debug"

// TODO: Make more helpers
ANSI_RESET :: "\033[0m"
ANSI_RED :: "\033[31m"
ANSI_GREEN :: "\033[32m"
ANSI_YELLOW :: "\033[33m"
ANSI_GRAY_ITALIC :: "\033[3;90m"

ANSI_CYAN_BOLD :: "\033[36m\033[1m"
ANSI_MAGENTA_BOLD :: "\033[35m\033[1m"
ANSI_BLUE_BOLD :: "\033[34m\033[1m"
ANSI_GREEN_BOLD :: "\033[32m\033[1m"

ANSI_CLEAR_LINE :: "\r\033[2K"
ANSI_DISABLE_MOUSE :: "\033[?1000l\033[?1006l"

Mode :: enum {
    Run_REPL,
    Run_Script,
    Compile_Script,
    Print_Script,
}

Config :: struct {
    mode:         Mode,
    input_file:   string,
    out_file:     string,
    pretty:       bool,
    no_std:       bool,
    minimal_repl: bool,
}

print_usage :: proc() {
    command := filepath.base(os.args[0])

    fmt.println("SIMP CLI Utility")
    fmt.printfln("Usage: %s [options] [script_file]", command)
    fmt.println("\nOptions:")
    fmt.println("  -h, --help           Show this help message")
    fmt.println("  -c, --compile        Compile the script to bytecode instead of running it")
    fmt.println("  -p, --print          Print the input script to the console instead of running it")
    fmt.println("      --pretty         Syntax highlight the printed script (used with -p)")
    fmt.println("      --no-std         Disables loading the standard library for evaluation")
    fmt.println("  -m  --minimal        Disables the builtin REPL functions (")
    fmt.println("  -o, --out <file>     Specify output file for compilation (default: <script>.sbin)")
}

cmd_quit :: proc(state: ^simp.State, arguments: []simp.Value) {
    os.exit(0)
}

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
    fmt.println("\n--- Native Functions ---")
    if len(state.native_procs) == 0 {
        fmt.println("[ Empty ]")
    } else {
        for key in state.native_procs {
            fmt.printfln(" %s", key)
        }
    }

    fmt.println("\n--- User Functions ---")
    if len(state.functions) == 0 {
        fmt.println("[ Empty ]")
    } else {
        for key, func in state.functions {
            fmt.printf(" %s (", key)

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

parse_arguments :: proc() -> (config: Config, should_exit: bool) {
    config.mode = .Run_REPL

    for i := 1; i < len(os.args); i += 1 {
        arg := os.args[i]
        switch arg {
        case "-h", "--help":
            print_usage()
            return config, true

        case "-c", "--compile":
            config.mode = .Compile_Script

        case "-p", "--print":
            config.mode = .Print_Script

        case "--pretty":
            config.pretty = true

        case "--no-std":
            config.no_std = true

        case "-m", "--minimal":
            config.minimal_repl = true

        case "-o", "--out":
            if i + 1 < len(os.args) {
                config.out_file = os.args[i + 1]
                i += 1
            } else {
                fmt.println("Error: '-o' or '--out' requires a file path.")
                os.exit(1)
            }

        case:
            if strings.has_prefix(arg, "-") {
                fmt.printfln("Error: Unknown flag '%s'", arg)
                print_usage()
                os.exit(1)
            } else if config.input_file == "" {
                config.input_file = arg
            } else {
                fmt.printfln("Error: Unexpected argument '%s'", arg)
                print_usage()
                os.exit(1)
            }
        }
    }

    if config.input_file != "" && config.mode == .Run_REPL {
        config.mode = .Run_Script
    }

    if config.input_file == "" && (config.mode == .Compile_Script || config.mode == .Print_Script) {
        fmt.println("Error: This mode requires an input script.")
        print_usage()
        os.exit(1)
    }

    if config.pretty && config.mode != .Print_Script {
        fmt.println("Warning: '--pretty' flag is ignored unless used with '-p' or '--print'.")
    }

    return config, false
}

main :: proc() {
    when ODIN_DEBUG {
        context.allocator = db.init_allocator()
        defer db.unload_allocator()
    }

    config, should_exit := parse_arguments()
    if should_exit {
        return
    }

    state: simp.State
    simp.init_state(&state)
    defer simp.destroy_state(&state)

    if !config.minimal_repl {
        simp.bind_native_proc(&state, "quit", cmd_quit)
        simp.bind_native_proc(&state, "vars", cmd_vars)
        simp.bind_native_proc(&state, "help", cmd_help)
    }

    if !config.no_std {
        lib.load_standard_library(&state)
    }

    switch config.mode {
    case .Run_REPL:
        run_repl(&state)

    case .Run_Script:
        if !os.is_file(config.input_file) {
            fmt.printfln("Error: Could not find script '%s'", config.input_file)
            os.exit(1)
        }

        simp.execute_script_from_file(&state, config.input_file)

    case .Compile_Script:
        out := config.out_file
        if out == "" {
            out = fmt.tprintf("%s.sbin", filepath.short_stem(config.input_file))
        }

        run_compile_logic(config.input_file, out)

    case .Print_Script:
        print_script(&state, config.input_file, config.pretty)
    }
}

print_script :: proc(state: ^simp.State, input_file: string, pretty: bool) {
    if !os.is_file(input_file) {
        fmt.printfln("Error: Could not find script '%s'", input_file)
        os.exit(1)
    }

    file_data, read_error := os.read_entire_file(input_file, context.temp_allocator)
    if read_error != nil {
        fmt.printfln("Error: Could not read input file '%s'", input_file)
        os.exit(1)
    }

    if pretty {
        colored_output := highlight_simp_code(state, string(file_data))
        fmt.print(colored_output)
    } else {
        fmt.print(string(file_data))
    }

    if len(file_data) > 0 && file_data[len(file_data) - 1] != '\n' {
        fmt.println()
    }
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

run_repl :: proc(state: ^simp.State) {
    fmt.print(ANSI_GREEN_BOLD)
    fmt.println("=======================================")
    fmt.println("                SIMP REPL              ")
    fmt.println("")
    fmt.println("help (): Print all available functions ")
    fmt.println("vars (): Print all defined variables   ")
    fmt.println("quit (): Exit the REPL")
    fmt.println("=======================================")
    fmt.print(ANSI_RESET)

    fmt.println()

    command_history := make([dynamic]string)
    defer {
        for cmd in command_history {
            delete(cmd)
        }

        delete(command_history)
    }

    script_accumulator := strings.builder_make()
    defer strings.builder_destroy(&script_accumulator)

    block_depth := 0

    for !state.should_close {
        indent_str := block_depth > 0 ? strings.repeat("    ", block_depth, context.temp_allocator) : ""
        unindent_str := block_depth > 0 ? strings.repeat("    ", block_depth - 1, context.temp_allocator) : ""

        prompt_prefix := block_depth == 0 ? "> " : "~ "
        normal_prompt := fmt.tprintf("%s%s", prompt_prefix, indent_str)
        unindented_prompt := fmt.tprintf("%s%s", prompt_prefix, unindent_str)

        input_line := read_interactive_line(state, normal_prompt, unindented_prompt, &command_history)

        if len(strings.trim_space(input_line)) == 0 {
            if block_depth > 0 {
                strings.write_string(&script_accumulator, "\n")
            } else {
                free_all(context.temp_allocator)
            }

            continue
        }

        block_depth += get_block_depth_change(input_line)
        if block_depth < 0 {
            block_depth = 0
        }

        strings.write_string(&script_accumulator, input_line)
        strings.write_string(&script_accumulator, "\n")

        if block_depth == 0 {
            simp.execute_snippet(state, strings.to_string(script_accumulator), os.args[0])
            if state.should_close {
                state.should_close = false
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

        if !in_string && current_char == '/' && char_index + 1 < len(input_line) && input_line[char_index + 1] == '/' {
            break
        }

        if current_char == '"' {
            in_string = !in_string
            char_index += 1
            continue
        }

        if !in_string && is_character(current_char) {
            start_index := char_index
            for char_index < len(input_line) && is_alphanumeric(input_line[char_index]) {
                char_index += 1
            }

            word := input_line[start_index:char_index]
            switch word {
            case "function", "while", "for", "foreach":
                change += 1

            case "if":
                if strings.contains(input_line, "then") && strings.has_suffix(strings.trim_space(input_line), "then") {
                    change += 1
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

is_character :: proc(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

is_alphanumeric :: proc(c: u8) -> bool {
    return is_character(c) || (c >= '0' && c <= '9')
}

highlight_simp_code :: proc(state: ^simp.State, input: string) -> string {
    builder := strings.builder_make(context.temp_allocator)
    index := 0
    paren_depth, bracket_depth := 0, 0
    expecting_declaration := false

    for index < len(input) {
        character := input[index]

        if character == '"' {
            strings.write_string(&builder, ANSI_GREEN)
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

            strings.write_string(&builder, ANSI_RESET)
            continue
        }

        if character == '/' && index + 1 < len(input) && input[index + 1] == '/' {
            strings.write_string(&builder, ANSI_GRAY_ITALIC)

            for index < len(input) {
                current_char := input[index]
                strings.write_byte(&builder, current_char)
                index += 1

                if current_char == '\n' {
                    break
                }
            }

            strings.write_string(&builder, ANSI_RESET)
            continue
        }

        if character >= '0' && character <= '9' {
            start_num := index
            dot_count := 0

            for index < len(input) && ((input[index] >= '0' && input[index] <= '9') || input[index] == '.') {
                if input[index] == '.' {
                    dot_count += 1
                }

                index += 1
            }

            color := dot_count > 1 ? ANSI_RED : ANSI_YELLOW
            strings.write_string(&builder, color)
            strings.write_string(&builder, input[start_num:index])
            strings.write_string(&builder, ANSI_RESET)

            continue
        }

        if is_character(character) {
            start := index

            for index < len(input) && is_alphanumeric(input[index]) {
                index += 1
            }

            word := input[start:index]
            color := ""

            switch word {
            case "while", "for", "foreach", "in", "break", "continue", "function", "end", "then", "else", "if", "to", "step", "return", "and", "or", "not":
                color = ANSI_CYAN_BOLD
                expecting_declaration = false

            case "let", "const":
                color = ANSI_CYAN_BOLD
                expecting_declaration = true

            case "import", "put", "sleep", "delete", "label", "goto", "new":
                color = ANSI_MAGENTA_BOLD
                expecting_declaration = false

            case "true", "false", "null", "object", "array", "int", "float", "string", "bool", "len", "type":
                color = ANSI_BLUE_BOLD
                expecting_declaration = false

            case:
                if expecting_declaration {
                    if repl_has_var(state, word) {
                        color = ANSI_RED
                    }
                    expecting_declaration = false
                } else {
                    lookahead := index

                    for lookahead < len(input) && (input[lookahead] == ' ' || input[lookahead] == '\t') {
                        lookahead += 1
                    }

                    if lookahead < len(input) && input[lookahead] == '(' {
                        color = ANSI_YELLOW
                    }
                }
            }

            if color != "" {
                strings.write_string(&builder, color)
                strings.write_string(&builder, word)
                strings.write_string(&builder, ANSI_RESET)
            } else {
                strings.write_string(&builder, word)
            }

            continue
        }

        if character != ' ' && character != '\t' {
            expecting_declaration = false
        }

        if character == '(' {
            paren_depth += 1
        } else if character == ')' {
            paren_depth -= 1

            if paren_depth < 0 {
                strings.write_string(&builder, ANSI_RED)
                strings.write_byte(&builder, ')')
                strings.write_string(&builder, ANSI_RESET)
                paren_depth, index = 0, index + 1
                continue
            }
        } else if character == '[' {
            bracket_depth += 1
        } else if character == ']' {
            bracket_depth -= 1

            if bracket_depth < 0 {
                strings.write_string(&builder, ANSI_RED)
                strings.write_byte(&builder, ']')
                strings.write_string(&builder, ANSI_RESET)
                bracket_depth, index = 0, index + 1
                continue
            }
        } else if character == '@' || character == '#' || character == '^' || character == '&' || character == '`' || character == '~' {
            strings.write_string(&builder, ANSI_RED)
            strings.write_byte(&builder, character)
            strings.write_string(&builder, ANSI_RESET)
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

    fmt.print(ANSI_DISABLE_MOUSE)
    os.flush(os.stdout)

    input_buffer := make([dynamic]u8, context.temp_allocator)
    cursor_position, history_index := 0, len(history^)
    current_prompt := normal_prompt

    fmt.print(current_prompt)
    os.flush(os.stdout)

    byte_read_buffer: [1]u8
    for {
        bytes_count, read_error := os.read(os.stdin, byte_read_buffer[:])

        if read_error != nil || bytes_count == 0 {
            continue
        }

        character := byte_read_buffer[0]

        if character == 3 {
            disable_raw_mode()
            fmt.println()
            os.exit(0)
        }

        if character == 4 && len(input_buffer) == 0 {
            fmt.println()
            return ""
        }

        if character == '\r' || character == '\n' {
            fmt.println()
            break
        }

        if character == 127 || character == '\b' {
            if cursor_position > 0 {
                ordered_remove(&input_buffer, cursor_position - 1)
                cursor_position -= 1

                trimmed := strings.trim_space(string(input_buffer[:]))
                current_prompt = (trimmed == "end" || trimmed == "else") ? unindented_prompt : normal_prompt
                _render_line(state, current_prompt, input_buffer[:], cursor_position)
            }
            continue
        }

        if character == 27 {
            os.read(os.stdin, byte_read_buffer[:])

            if byte_read_buffer[0] == '[' {
                first_char: u8 = 0
                last_char: u8 = 0
                is_first := true

                for {
                    os.read(os.stdin, byte_read_buffer[:])
                    last_char = byte_read_buffer[0]

                    if is_first {
                        first_char = last_char
                        is_first = false
                    }

                    if last_char >= 0x40 && last_char <= 0x7E {
                        break
                    }
                }

                if first_char == last_char {
                    switch first_char {
                    case 'A':
                        // Up
                        if history_index > 0 {
                            history_index -= 1
                            clear(&input_buffer)
                            for char in history^[history_index] {
                                append(&input_buffer, u8(char))
                            }
                            cursor_position = len(input_buffer)

                            trimmed := strings.trim_space(string(input_buffer[:]))
                            current_prompt = (trimmed == "end" || trimmed == "else") ? unindented_prompt : normal_prompt
                            _render_line(state, current_prompt, input_buffer[:], cursor_position)
                        }

                    case 'B':
                        // Down
                        if history_index < len(history^) - 1 {
                            history_index += 1
                            clear(&input_buffer)
                            for char in history^[history_index] {
                                append(&input_buffer, u8(char))
                            }
                            cursor_position = len(input_buffer)

                            trimmed := strings.trim_space(string(input_buffer[:]))
                            current_prompt = (trimmed == "end" || trimmed == "else") ? unindented_prompt : normal_prompt
                            _render_line(state, current_prompt, input_buffer[:], cursor_position)
                        } else if history_index == len(history^) - 1 {
                            history_index += 1
                            clear(&input_buffer)
                            cursor_position = 0
                            current_prompt = normal_prompt
                            _render_line(state, current_prompt, input_buffer[:], cursor_position)
                        }

                    case 'C':
                        // Right
                        if cursor_position < len(input_buffer) {
                            cursor_position += 1
                            _render_line(state, current_prompt, input_buffer[:], cursor_position)
                        }

                    case 'D':
                        // Left
                        if cursor_position > 0 {
                            cursor_position -= 1
                            _render_line(state, current_prompt, input_buffer[:], cursor_position)
                        }
                    }
                }
            }
            continue
        }

        if character >= 32 && character <= 126 {
            inject_at(&input_buffer, cursor_position, character)
            cursor_position += 1

            trimmed := strings.trim_space(string(input_buffer[:]))
            current_prompt = (trimmed == "end" || trimmed == "else") ? unindented_prompt : normal_prompt
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
    fmt.print("\r\033[2K")
    fmt.print(prompt)

    colored_output := highlight_simp_code(state, string(buffer))
    fmt.print(colored_output)

    if cursor < len(buffer) {
        fmt.printf("\033[%dD", len(buffer) - cursor)
    }

    os.flush(os.stdout)
}
