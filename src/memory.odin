package simp

import "core:strings"

Block_Type :: enum {
    While,
    For,
    Foreach,
    Function,
    If,
    Else,
    Array,
    Object,
}

Block_Ref :: struct {
    type:   Block_Type,
    index:  int,
    breaks: [dynamic]int,
}

intern_string :: proc(state: ^State, text: string) -> string {
    if cached_string, exists := state.string_cache[text]; exists {
        return cached_string
    }

    cloned_string := strings.clone(text, state.allocator)
    state.string_cache[cloned_string] = cloned_string

    return cloned_string
}

create_object :: proc(state: ^State) -> ^Object {
    new_object := new(Object)
    new_object^ = make(Object)
    state.tracked_objects[new_object] = true

    return new_object
}

free_object :: proc(state: ^State, target_object: ^Object) {
    if target_object in state.tracked_objects {
        delete(target_object^)
        free(target_object)

        delete_key(&state.tracked_objects, target_object)
    }
}

create_array :: proc(state: ^State) -> ^Array {
    new_array := new(Array)
    new_array^ = make(Array)
    state.tracked_arrays[new_array] = true

    return new_array
}

free_array :: proc(state: ^State, target_array: ^Array) {
    if target_array in state.tracked_arrays {
        delete(target_array^)
        free(target_array)
        delete_key(&state.tracked_arrays, target_array)
    }
}

@(private = "package")
_compute_tables :: proc(tokens: []Token, allocator := context.allocator) -> []int {
    jump_table := make([]int, len(tokens), allocator)
    for index := 0; index < len(tokens); index += 1 {
        jump_table[index] = -1
    }

    label_map := make(map[string]int, 16, context.temp_allocator)

    for token_index := 0; token_index < len(tokens); token_index += 1 {
        if tokens[token_index].keyword == .Label {
            if token_index + 1 < len(tokens) && tokens[token_index + 1].type == .Ident {
                label_name := tokens[token_index + 1].text
                label_map[label_name] = token_index
            }
        }
    }

    stack := make([dynamic]Block_Ref, context.temp_allocator)

    for token_index := 0; token_index < len(tokens); token_index += 1 {
        token := tokens[token_index]

        #partial switch token.keyword {
        case .While:
            append(&stack, Block_Ref{type = .While, index = token_index, breaks = make([dynamic]int, context.temp_allocator)})

        case .For:
            append(&stack, Block_Ref{type = .For, index = token_index, breaks = make([dynamic]int, context.temp_allocator)})

        case .Foreach:
            append(&stack, Block_Ref{type = .Foreach, index = token_index, breaks = make([dynamic]int, context.temp_allocator)})

        case .Function:
            append(&stack, Block_Ref{type = .Function, index = token_index, breaks = nil})

        case .Array, .Object:
            block_type := Block_Type.Object
            if token.keyword == .Array {
                block_type = .Array
            }
            append(&stack, Block_Ref{type = block_type, index = token_index, breaks = nil})

        case .If:
            is_block := false

            for search_index := token_index + 1; search_index < len(tokens); search_index += 1 {
                tok := tokens[search_index]
                if tok.type == .LBrace {
                    is_block = true
                    break
                }
                if tok.keyword == .Then {
                    is_block = false
                    break
                }
                if tok.type == .Newline {
                    break
                }
            }

            if is_block {
                append(&stack, Block_Ref{type = .If, index = token_index, breaks = nil})
            }

        case .None:
            if token.type == .RBrace {
                if len(stack) > 0 {
                    block_reference := pop(&stack)

                    has_else := token_index + 1 < len(tokens) && tokens[token_index + 1].keyword == .Else

                    if block_reference.type == .If && has_else {
                        else_index := token_index + 1
                        jump_table[block_reference.index] = else_index

                        append(&stack, Block_Ref{type = .Else, index = token_index, breaks = nil})
                    } else if block_reference.type == .Else {
                        jump_table[block_reference.index] = token_index
                    } else {
                        jump_table[block_reference.index] = token_index
                        jump_table[token_index] = block_reference.index

                        if block_reference.breaks != nil {
                            for break_index in block_reference.breaks {
                                jump_table[break_index] = token_index
                            }
                            delete(block_reference.breaks)
                        }
                    }
                }
            }

        case .Break:
            for stack_index := len(stack) - 1; stack_index >= 0; stack_index -= 1 {
                current_block := stack[stack_index].type
                is_loop := current_block == .While || current_block == .For || current_block == .Foreach

                if is_loop {
                    append(&stack[stack_index].breaks, token_index)
                    break
                }
            }

        case .Continue:
            for stack_index := len(stack) - 1; stack_index >= 0; stack_index -= 1 {
                current_block := stack[stack_index].type
                is_loop := current_block == .While || current_block == .For || current_block == .Foreach

                if is_loop {
                    jump_table[token_index] = stack[stack_index].index
                    break
                }
            }

        case .Goto:
            if token_index + 1 < len(tokens) && tokens[token_index + 1].type == .Ident {
                name := tokens[token_index + 1].text
                if target_idx, exists := label_map[name]; exists {
                    jump_table[token_index] = target_idx
                }
            }
        }
    }

    return jump_table
}
