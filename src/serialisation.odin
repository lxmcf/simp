package simp

MAGIC_HEADER: string : "SIMP"

serialise_script :: proc(script: string, filename: string) -> (bytecode: []u8, ok: bool) #optional_ok {
    visited_files := make(map[string]bool, 16, context.temp_allocator)
    tokens := _tokenise_and_resolve(nil, script, filename, &visited_files) or_return

    jump_table, break_table, continue_table := _compute_tables(tokens, context.temp_allocator)

    buffer := make([dynamic]u8)
    append(&buffer, ..transmute([]u8)MAGIC_HEADER)

    // Pre-computed tables
    _write_u32(&buffer, u32(len(jump_table)))
    for key, value in jump_table {
        _write_u32(&buffer, u32(key))
        _write_u32(&buffer, u32(value))
    }

    _write_u32(&buffer, u32(len(break_table)))
    for key, value in break_table {
        _write_u32(&buffer, u32(key))
        _write_u32(&buffer, u32(value))
    }

    _write_u32(&buffer, u32(len(continue_table)))
    for key, value in continue_table {
        _write_u32(&buffer, u32(key))
        _write_u32(&buffer, u32(value))
    }

    // Tokens
    _write_u32(&buffer, u32(len(tokens)))
    for token in tokens {
        append(&buffer, u8(token.type), u8(token.keyword))
        _write_u32(&buffer, u32(token.line))

        needs_text := token.keyword == .None && (token.type == .Ident || token.type == .Number || token.type == .String)

        if needs_text {
            _write_u32(&buffer, u32(len(token.text)))
            append(&buffer, ..transmute([]u8)token.text)
        } else {
            _write_u32(&buffer, 0)
        }
    }

    return buffer[:], true
}

@(private = "package")
_deserialise_bytecode :: proc(state: ^State, bytecode_data: string) {
    index := 0

    // Precomputed tables
    clear(&state.jump_table)
    clear(&state.break_table)
    clear(&state.continue_table)

    number_of_jumps := _read_u32(bytecode_data, &index)
    for _ in 0 ..< number_of_jumps {
        jump_key := _read_u32(bytecode_data, &index)
        jump_value := _read_u32(bytecode_data, &index)

        state.jump_table[jump_key] = jump_value
    }

    number_of_breaks := _read_u32(bytecode_data, &index)
    for _ in 0 ..< number_of_breaks {
        break_key := _read_u32(bytecode_data, &index)
        break_value := _read_u32(bytecode_data, &index)

        state.break_table[break_key] = break_value
    }

    number_of_continues := _read_u32(bytecode_data, &index)
    for _ in 0 ..< number_of_continues {
        continue_key := _read_u32(bytecode_data, &index)
        continue_value := _read_u32(bytecode_data, &index)

        state.continue_table[continue_key] = continue_value
    }

    // Tokens
    number_of_tokens := _read_u32(bytecode_data, &index)
    state.tokens = make([dynamic]Token, 0, number_of_tokens)

    for _ in 0 ..< number_of_tokens {
        token_type := Token_Type(bytecode_data[index])
        index += 1

        token_keyword := Token_Keyword(bytecode_data[index])
        index += 1

        line_number := _read_u32(bytecode_data, &index)

        token_length := _read_u32(bytecode_data, &index)
        token_text: string

        if token_length > 0 {
            token_text = bytecode_data[index:index + token_length]
            index += token_length
        } else {
            token_text = _get_default_token_text(token_type, token_keyword)
        }

        new_token := Token {
            type    = token_type,
            keyword = token_keyword,
            text    = token_text,
            line    = line_number,
        }

        append(&state.tokens, new_token)
    }
}

@(private = "file")
_write_u32 :: #force_inline proc(buffer: ^[dynamic]u8, value: u32) {
    byte_0 := u8(value & 0xFF)
    byte_1 := u8((value >> 8) & 0xFF)
    byte_2 := u8((value >> 16) & 0xFF)
    byte_3 := u8((value >> 24) & 0xFF)

    append(buffer, byte_0, byte_1, byte_2, byte_3)
}

@(private = "file")
_read_u32 :: #force_inline proc(data: string, index_pointer: ^int) -> int {
    value := u32(data[index_pointer^]) | (u32(data[index_pointer^ + 1]) << 8) | (u32(data[index_pointer^ + 2]) << 16) | (u32(data[index_pointer^ + 3]) << 24)

    index_pointer^ += 4

    return int(value)
}
