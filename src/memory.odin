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
    for i := 0; i < len(tokens); i += 1 {
        jump_table[i] = -1
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
            // <- FIX: Allows loops outside these not to be falsely ended!
            append(&stack, Block_Ref{type = token.keyword == .Array ? .Array : .Object, index = token_index, breaks = nil})

        case .If:
            is_block := false

            for search_index := token_index + 1; search_index < len(tokens); search_index += 1 {
                if tokens[search_index].keyword == .Then {
                    if search_index + 1 < len(tokens) {
                        next_token_type := tokens[search_index + 1].type

                        if next_token_type == .Newline || next_token_type == .Colon {
                            is_block = true
                        } else {
                            line_number := tokens[search_index].line

                            for inner_index := search_index + 1; inner_index < len(tokens); inner_index += 1 {
                                if tokens[inner_index].line != line_number {
                                    break
                                }

                                if tokens[inner_index].keyword == .End || tokens[inner_index].keyword == .Else {
                                    is_block = true
                                    break
                                }
                            }
                        }
                    }
                    break
                }
            }

            if is_block {
                append(&stack, Block_Ref{type = .If, index = token_index, breaks = nil})
            }

        case .Else:
            if len(stack) > 0 && stack[len(stack) - 1].type == .If {
                block_reference := pop(&stack)
                jump_table[block_reference.index] = token_index

                append(&stack, Block_Ref{type = .Else, index = token_index, breaks = nil})
            }

        case .End:
            if len(stack) > 0 {
                block_reference := pop(&stack)
                jump_table[block_reference.index] = token_index
                jump_table[token_index] = block_reference.index

                if block_reference.breaks != nil {
                    for b in block_reference.breaks {
                        jump_table[b] = token_index // Breaks instantly map to the End token
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
