package simp

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

// -----------------------------------------------------------------------------
// Core types
// -----------------------------------------------------------------------------

DEFAULT_VALUE :: Null_Value{}

EXIT_SUCCESS :: 0
EXIT_FAIL :: 1

Object :: map[string]Value
Array :: [dynamic]Value

// TODO: Add this
//
// NOTE: Mostly intended for io operations or more memory
//       efficient string slicing
@(private)
Buffer :: []u8

Type_Value :: enum {
    Int,
    Float,
    String,
    Bool,
    Object,
    Array,
    // Buffer,
    Pointer,
    Null,
    Function,
    Type,
}

// Effectively a 'nil'
Null_Value :: distinct struct{}

Value :: union {
    Null_Value,
    f64,
    int,
    string,
    bool,
    ^Object,
    ^Array,
    // ^Buffer,
    rawptr, // Intended for better SIMP -> Odin/C interop
    ^f64,
    ^f32,
    ^int,
    ^i32,
    ^string,
    ^bool,
    Type_Value,
}

Variable_Slot :: struct {
    value:    Value,
    is_const: bool,
    decl_pc:  int, // Decleration position
}


Function_Def :: struct {
    arguments: []string,
    position:  int,
}

State :: struct {
    scopes:           [dynamic]map[string]Variable_Slot,
    scope_pool:       [dynamic]map[string]Variable_Slot,
    functions:        map[string]Function_Def,
    native_procs:     map[string]Native_Proc,
    arena:            virtual.Arena,
    allocator:        mem.Allocator,
    string_cache:     map[string]string,
    // -------------------------
    argument_stack:   [dynamic]Value,
    tracked_objects:  map[^Object]bool,
    tracked_arrays:   map[^Array]bool,
    // tracked_buffers:  map[^Buffer]bool,

    // C-FFI Data Transfer
    ffi_args:         []Value,
    ffi_return:       Value,

    // Performance Optimization
    jump_table:       map[int]int,
    break_table:      map[int]int,
    continue_table:   map[int]int,
    imported_scripts: [dynamic]string,
    tokens:           [dynamic]Token,
    position:         int,
    is_sleeping:      bool,
    sleep_timer:      f64,
    should_close:     bool,
    is_exiting:       bool,
    exit_value:       int,
    return_value:     Value,
    is_returning:     bool,

    // Debug
    log_proc:         Log_Proc,
}

// -----------------------------------------------------------------------------
// Core Functions
// -----------------------------------------------------------------------------

get_state_exit_code :: proc(state: ^State) -> int {
    return state.exit_value
}

init_state :: proc(state: ^State) {
    if state.log_proc == nil {
        state.log_proc = default_log_proc
    }

    if mem_error := virtual.arena_init_growing(&state.arena); mem_error != .None {
        message := fmt.tprintf("Failed to initialise state with error: %v", mem_error)
        state.log_proc(.Fatal, message)
        return
    }

    state.allocator = virtual.arena_allocator(&state.arena)

    state.functions = make(map[string]Function_Def, 16, state.allocator)
    state.native_procs = make(map[string]Native_Proc, 16, state.allocator)
    state.string_cache = make(map[string]string, 16, state.allocator)
    state.tracked_objects = make(map[^Object]bool, 16, state.allocator)
    state.tracked_arrays = make(map[^Array]bool, 16, state.allocator)

    // Initialize the root scope
    state.scopes = make([dynamic]map[string]Variable_Slot, 0, 8, state.allocator)
    append(&state.scopes, make(map[string]Variable_Slot, 16, state.allocator))
}

destroy_state :: proc(state: ^State) {
    for scope in state.scopes { delete(scope) }
    delete(state.scopes)

    for scope in state.scope_pool { delete(scope) }
    delete(state.scope_pool)

    for _, function in state.functions {
        for argument in function.arguments { delete(argument) }
        delete(function.arguments)
    }
    delete(state.functions)
    delete(state.native_procs)

    delete(state.argument_stack)

    delete(state.jump_table)
    delete(state.break_table)
    delete(state.continue_table)

    for tracked_object in state.tracked_objects {
        delete(tracked_object^)
        free(tracked_object)
    }
    delete(state.tracked_objects)

    for tracked_array in state.tracked_arrays {
        delete(tracked_array^)
        free(tracked_array)
    }
    delete(state.tracked_arrays)

    delete(state.string_cache)
    virtual.arena_destroy(&state.arena)

    if state.tokens != nil { delete(state.tokens) }

    for script in state.imported_scripts { delete(script) }
    delete(state.imported_scripts)
}

shutdown_state :: proc(state: ^State, exit_code: int = EXIT_SUCCESS) {
    state.should_close = true
    state.is_exiting = true
    state.exit_value = exit_code
}

load_script :: proc(state: ^State, script_data: string, filename: string, is_snippet: bool = false) -> bool {
    magic_header_length := len(MAGIC_HEADER)
    is_binary := len(script_data) >= magic_header_length && script_data[:magic_header_length] == MAGIC_HEADER

    if is_binary {
        if is_snippet {
            state.log_proc(.Error, "Cannot evaluate bytecode as a snippet!", -1)
            return false
        }

        if state.tokens != nil { delete(state.tokens) }
        for script in state.imported_scripts { delete(script) }
        clear(&state.imported_scripts)

        if state.jump_table != nil {
            delete(state.jump_table)
            delete(state.break_table)
            delete(state.continue_table)
        }

        persistent_binary := strings.clone(script_data, state.allocator)
        append(&state.imported_scripts, persistent_binary)

        _deserialise_bytecode(state, persistent_binary[magic_header_length:])

        state.position = 0
        state.is_sleeping = false
        state.sleep_timer = 0
        state.should_close = false
        state.is_exiting = false
        state.exit_value = 0

        return true
    }

    visited_files := make(map[string]bool, 16, context.temp_allocator)
    temporary_tokens, ok := _tokenise_and_resolve(state, script_data, filename, &visited_files)

    if !ok {
        if !is_snippet {
            state.should_close = true
        }
        return false
    }

    offset := 0

    if !is_snippet {
        if state.tokens != nil { delete(state.tokens) }
        for script in state.imported_scripts { delete(script) }
        clear(&state.imported_scripts)

        if state.jump_table != nil {
            delete(state.jump_table)
            delete(state.break_table)
            delete(state.continue_table)
        }

        state.tokens = make([dynamic]Token, 0, len(temporary_tokens))
        state.jump_table, state.break_table, state.continue_table = _compute_tables(temporary_tokens, state.allocator)
        state.position = 0
    } else {
        if state.tokens == nil {
            state.tokens = make([dynamic]Token, state.allocator)
        }
        offset = len(state.tokens)

        if state.jump_table == nil {
            state.jump_table = make(map[int]int, 16, state.allocator)
            state.break_table = make(map[int]int, 16, state.allocator)
            state.continue_table = make(map[int]int, 16, state.allocator)
        }

        c_jump, c_break, c_continue := _compute_tables(temporary_tokens, context.temp_allocator)
        for key, value in c_jump { state.jump_table[key + offset] = value + offset }
        for key, value in c_break { state.break_table[key + offset] = value + offset }
        for key, value in c_continue { state.continue_table[key + offset] = value + offset }

        state.position = offset
    }

    for t in temporary_tokens {
        append(&state.tokens, t)
    }

    state.is_sleeping = false
    state.sleep_timer = 0
    state.should_close = false
    state.is_exiting = false
    state.exit_value = 0

    return true
}

run_state :: proc(state: ^State) {
    for step_state(state, 0.016, 10_000_000) {
        if state.is_sleeping && state.sleep_timer > 0 {
            sleep_duration := time.Duration(state.sleep_timer * f64(time.Millisecond))
            time.sleep(sleep_duration)

            state.sleep_timer = 0
            state.is_sleeping = false
        }
    }
}

execute_script :: proc(state: ^State, script_data: string, filename: string) {
    if load_script(state, script_data, filename, false) {
        run_state(state)
    }
}

execute_file :: proc(state: ^State, filename: string) {
    data, err := os.read_entire_file(filename, context.allocator)
    if err != nil {
        message := fmt.tprintf("Failed to read script file: %s", filename)
        state.log_proc(.Fatal, message)
        return
    }

    defer delete(data, context.allocator)

    slash_index := strings.last_index_any(filename, filepath.SEPARATOR_CHARS)
    name := filepath.stem(filename[slash_index + 1:])

    execute_script(state, string(data), name)
}

execute_snippet :: proc(state: ^State, script_data: string, filename: string = "eval") {
    old_position := state.position
    old_is_sleeping := state.is_sleeping
    old_sleep_timer := state.sleep_timer
    old_should_close := state.should_close
    old_len := len(state.tokens)

    defer {
        if old_position >= old_len {
            state.position = len(state.tokens)
        } else {
            state.position = old_position
        }
        state.is_sleeping = old_is_sleeping
        state.sleep_timer = old_sleep_timer

        if !state.is_exiting {
            state.should_close = old_should_close
        }
    }

    if load_script(state, script_data, filename, true) {
        run_state(state)
    }
}

step_state :: proc(state: ^State, delta_time: f64, max_operations: int = 256) -> bool {
    if state.should_close || state.position >= len(state.tokens) {
        return false
    }

    if state.is_sleeping {
        state.sleep_timer -= delta_time

        if state.sleep_timer <= 0 {
            state.is_sleeping = false
        } else {
            return true
        }
    }

    parser := Parser {
        tokens   = state.tokens[:],
        position = state.position,
    }
    operations_this_frame := 0

    for parser.position < len(parser.tokens) && !state.should_close {
        operations_this_frame += 1

        if operations_this_frame > max_operations {
            state.is_sleeping = true
            state.sleep_timer = 0
            state.position = parser.position
            return true
        }

        next_token_type := _peek_ahead(&parser).type
        if next_token_type == .Newline || next_token_type == .Colon {
            _advance(&parser)
            continue
        }

        message, ok := _parse_statement(state, &parser)
        if !ok {
            error_token := _peek_ahead(&parser)
            state.log_proc(.Fatal, message, error_token.line)
            state.should_close = true
            return false
        }

        if state.is_sleeping {
            state.position = parser.position
            return true
        }
    }

    state.position = parser.position

    return false
}
