package simp

import "core:strings"

Block_Ref :: struct {
    type:   Token_Keyword,
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
                label_map[tokens[token_index + 1].text] = token_index
            }
        }
    }

    stack := make([dynamic]Block_Ref, context.temp_allocator)

    for token_index := 0; token_index < len(tokens); token_index += 1 {
        token := tokens[token_index]

        #partial switch token.keyword {
        case .While, .For, .Foreach:
            append(&stack, Block_Ref{type = token.keyword, index = token_index, breaks = make([dynamic]int, context.temp_allocator)})

        case .Function, .If:
            append(&stack, Block_Ref{type = token.keyword, index = token_index})

        case .Array, .Object:
            append(&stack, Block_Ref{type = token.keyword, index = token_index})

        case .None:
            if token.type == .RBrace {
                if len(stack) > 0 {
                    block_ref := pop(&stack)

                    // Check if this '}' belongs to an 'if' that is followed by 'else'
                    // Ensure we ignore/skip any potential newlines
                    else_keyword_index := -1
                    for search_index := token_index + 1; search_index < len(tokens); search_index += 1 {
                        if tokens[search_index].type == .Newline {
                            continue
                        }
                        if tokens[search_index].keyword == .Else {
                            else_keyword_index = search_index
                        }
                        break
                    }

                    if block_ref.type == .If && else_keyword_index != -1 {
                        // 1. The 'if' keyword jumps to the 'else' keyword if the condition is false
                        jump_table[block_ref.index] = else_keyword_index

                        // 2. This '}' (end of if) needs to jump to the end of the 'else' block
                        // We push a reference to this '}' onto the stack so the Else's '}' can find it
                        append(&stack, Block_Ref{type = .Else, index = token_index})

                        // 3. Push the 'else' keyword so its '}' can link back to it
                        append(&stack, Block_Ref{type = .None, index = else_keyword_index}) // Use .None as a generic marker to avoid object block collisions
                    } else if block_ref.type == .None && len(stack) > 0 && stack[len(stack) - 1].type == .Else {
                        // This '}' belongs to an 'else' block.
                        actual_else_keyword_index := block_ref.index
                        if_end_brace_index := pop(&stack).index

                        // 1. The 'else' keyword jumps to the end of its own block
                        jump_table[actual_else_keyword_index] = token_index

                        // 2. The 'if' block's end-brace jumps to the end of the 'else' block
                        jump_table[if_end_brace_index] = token_index

                        // 3. The 'else' keyword's closure
                        jump_table[token_index] = actual_else_keyword_index
                    } else {
                        // Standard loop/function closure
                        jump_table[block_ref.index] = token_index
                        jump_table[token_index] = block_ref.index

                        if block_ref.breaks != nil {
                            for b in block_ref.breaks {
                                jump_table[b] = token_index
                            }
                            delete(block_ref.breaks)
                        }
                    }
                }
            }

        case .Break, .Continue:
            for i := len(stack) - 1; i >= 0; i -= 1 {
                if stack[i].type == .While || stack[i].type == .For || stack[i].type == .Foreach {
                    if token.keyword == .Break {
                        append(&stack[i].breaks, token_index)
                    } else {
                        jump_table[token_index] = stack[i].index
                    }
                    break
                }
            }

        case .Goto:
            if token_index + 1 < len(tokens) && tokens[token_index + 1].type == .Ident {
                if target, exists := label_map[tokens[token_index + 1].text]; exists {
                    jump_table[token_index] = target
                }
            }
        }
    }
    return jump_table
}
