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

Object :: map[string]Value
Array :: [dynamic]Value

Type_Value :: enum {
    Int,
    Float,
    String,
    Bool,
    Object,
    Array,
    Pointer,
    Null,
    Function,
    Type,
}

Null_Value :: distinct struct{}

Value :: union {
    Null_Value,
    f64,
    int,
    string,
    bool,
    ^Object,
    ^Array,
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
    decl_pc:  int, // Declaration position
}

Function_Def :: struct {
    arguments: []string,
    position:  int,
}

State :: struct {
    // Scopes & Memory
    scopes:           [dynamic]map[string]Variable_Slot,
    scope_pool:       [dynamic]map[string]Variable_Slot,
    functions:        map[string]Function_Def,
    native_procs:     map[string]Native_Proc,
    arena:            virtual.Arena,
    allocator:        mem.Allocator,
    string_cache:     map[string]string,

    // Tracked Resources
    argument_stack:   [dynamic]Value,
    tracked_objects:  map[^Object]bool,
    tracked_arrays:   map[^Array]bool,

    // Performance Optimization & AST
    jump_table:       map[int]int,
    break_table:      map[int]int,
    continue_table:   map[int]int,
    imported_scripts: [dynamic]string,
    tokens:           [dynamic]Token,
    position:         int,

    // State Machine
    is_sleeping:      bool,
    sleep_timer:      f64,
    should_close:     bool,
    return_value:     Value,
    is_returning:     bool,

    // Debug
    log_proc:         Log_Proc,
}

// -----------------------------------------------------------------------------
// Lifecycle Management
// -----------------------------------------------------------------------------

state_init :: proc(state: ^State) {
    if state.log_proc == nil {
        state.log_proc = default_log_proc
    }

    if memory_error := virtual.arena_init_growing(&state.arena); memory_error != .None {
        message := fmt.tprintf("Failed to initialise state with error: %v", memory_error)
        state.log_proc(.Fatal, message)
        return
    }

    state.allocator = virtual.arena_allocator(&state.arena)
    append(&state.scopes, make(map[string]Variable_Slot))
}

state_destroy :: proc(state: ^State) {
    for scope in state.scopes {
        delete(scope)
    }
    delete(state.scopes)

    for scope in state.scope_pool {
        delete(scope)
    }
    delete(state.scope_pool)

    for _, function in state.functions {
        for argument in function.arguments {
            delete(argument)
        }
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

    if state.tokens != nil {
        delete(state.tokens)
    }

    for script in state.imported_scripts {
        delete(script)
    }
    delete(state.imported_scripts)
}

// -----------------------------------------------------------------------------
// Source Loading
// -----------------------------------------------------------------------------

state_load_source :: proc(state: ^State, script_data: string, filename: string) -> bool {
    if state.tokens != nil {
        delete(state.tokens)
    }

    for script in state.imported_scripts {
        delete(script)
    }
    clear(&state.imported_scripts)

    if state.jump_table != nil {
        delete(state.jump_table)
        delete(state.break_table)
        delete(state.continue_table)
    }

    magic_header_length := len(MAGIC_HEADER)
    is_binary := len(script_data) >= magic_header_length && script_data[:magic_header_length] == MAGIC_HEADER

    if is_binary {
        persistent_binary := strings.clone(script_data)
        append(&state.imported_scripts, persistent_binary)

        _deserialise_bytecode(state, persistent_binary[magic_header_length:])
    } else {
        visited_files := make(map[string]bool, 16, context.temp_allocator)
        temporary_tokens, tokenisation_success := _tokenise_and_resolve(state, script_data, filename, &visited_files)

        if !tokenisation_success {
            state.should_close = true
            return false
        }

        state.tokens = make([dynamic]Token, len(temporary_tokens))
        copy(state.tokens[:], temporary_tokens)

        computed_jump_table, computed_break_table, computed_continue_table := _compute_tables(state.tokens[:], context.allocator)
        state.jump_table = computed_jump_table
        state.break_table = computed_break_table
        state.continue_table = computed_continue_table
    }

    state.position = 0
    state.is_sleeping = false
    state.sleep_timer = 0
    state.should_close = false

    return true
}

state_load_file :: proc(state: ^State, filename: string) -> bool {
    file_data, read_error := os.read_entire_file(filename, context.allocator)
    if read_error != nil {
        message := fmt.tprintf("Failed to read script file: %s", filename)
        state.log_proc(.Fatal, message)

        return false
    }
    defer delete(file_data, context.allocator)

    slash_index := strings.last_index_any(filename, filepath.SEPARATOR_CHARS)
    name := filepath.stem(filename[slash_index + 1:])

    return state_load_source(state, string(file_data), name)
}

state_append_source :: proc(state: ^State, script_data: string, filename: string) -> bool {
    magic_header_length := len(MAGIC_HEADER)
    is_binary := len(script_data) >= magic_header_length && script_data[:magic_header_length] == MAGIC_HEADER

    if is_binary {
        state.log_proc(.Error, "Cannot append bytecode!", -1)
        return false
    }

    visited_files := make(map[string]bool, 16, context.temp_allocator)
    temporary_tokens, tokenisation_success := _tokenise_and_resolve(state, script_data, filename, &visited_files)

    if !tokenisation_success {
        state.should_close = false
        return false
    }

    if state.tokens == nil {
        state.tokens = make([dynamic]Token, state.allocator)
    }

    offset := len(state.tokens)

    computed_jump_table, computed_break_table, computed_continue_table := _compute_tables(temporary_tokens, context.temp_allocator)

    if state.jump_table == nil {
        state.jump_table = make(map[int]int, 16, state.allocator)
        state.break_table = make(map[int]int, 16, state.allocator)
        state.continue_table = make(map[int]int, 16, state.allocator)
    }

    for key, value in computed_jump_table {
        state.jump_table[key + offset] = value + offset
    }

    for key, value in computed_break_table {
        state.break_table[key + offset] = value + offset
    }

    for key, value in computed_continue_table {
        state.continue_table[key + offset] = value + offset
    }

    for token in temporary_tokens {
        append(&state.tokens, token)
    }

    state.position = offset
    state.is_sleeping = false
    state.sleep_timer = 0
    state.should_close = false

    return true
}

// -----------------------------------------------------------------------------
// Execution
// -----------------------------------------------------------------------------

state_run_source :: proc(state: ^State, script: string, filename: string) {
    if !state_load_source(state, script, filename) {
        return
    }

    _execute_until_completion(state)
}

state_run_file :: proc(state: ^State, filename: string) {
    if !state_load_file(state, filename) {
        return
    }

    _execute_until_completion(state)
}

state_run_snippet :: proc(state: ^State, script: string, filename: string = "eval") {
    old_position := state.position
    old_is_sleeping := state.is_sleeping
    old_sleep_timer := state.sleep_timer
    old_should_close := state.should_close
    old_length := len(state.tokens)

    defer {
        if old_position >= old_length {
            state.position = len(state.tokens)
        } else {
            state.position = old_position
        }
        state.is_sleeping = old_is_sleeping
        state.sleep_timer = old_sleep_timer
        state.should_close = old_should_close
    }

    if !state_append_source(state, script, filename) {
        return
    }

    _execute_until_completion(state)
}

@(private = "file")
_execute_until_completion :: proc(state: ^State) {
    for state_step(state, 0.016, 10_000_000) {
        if state.is_sleeping && state.sleep_timer > 0 {
            sleep_duration := time.Duration(state.sleep_timer * f64(time.Millisecond))
            time.sleep(sleep_duration)

            state.sleep_timer = 0
            state.is_sleeping = false
        }
    }
}

// -----------------------------------------------------------------------------
// State Stepping
// -----------------------------------------------------------------------------

state_step :: proc(state: ^State, delta_time: f64, max_operations: int = 256) -> bool {
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

        error_message, is_success := _parse_statement(state, &parser)
        if !is_success {
            error_token := _peek_ahead(&parser)
            state.log_proc(.Fatal, error_message, error_token.line)
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
