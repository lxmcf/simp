#+private

package simp

import "core:fmt"
import "core:strconv"
import "core:strings"

// -----------------------------------------------------------------------------
// Parser Types
// -----------------------------------------------------------------------------

Block_Type :: enum {
    While,
    For,
    Foreach,
    Function,
    If,
    Else,
}

Block_Ref :: struct {
    type:  Block_Type,
    index: int,
}

Parser :: struct {
    tokens:   []Token,
    position: int,
}

_peek_ahead :: proc(parser: ^Parser, n: int = 0) -> Token {
    tokens_length := len(parser.tokens)

    if parser.position + n < tokens_length {
        return parser.tokens[parser.position + n]
    }

    last_line := tokens_length > 0 ? parser.tokens[tokens_length - 1].line : 1

    return Token{type = .EOF, keyword = .None, text = "EOF", line = last_line}
}

_advance :: proc(parser: ^Parser) -> Token {
    token := _peek_ahead(parser)

    if parser.position < len(parser.tokens) {
        parser.position += 1
    }

    return token
}

_build_jump_table :: proc(state: ^State) {
    clear(&state.jump_table)
    clear(&state.break_table)
    clear(&state.continue_table)

    stack := make([dynamic]Block_Ref, context.temp_allocator)
    tokens := state.tokens[:]

    for token_index := 0; token_index < len(tokens); token_index += 1 {
        token := tokens[token_index]

        #partial switch token.keyword {
        case .While:
            append(&stack, Block_Ref{type = .While, index = token_index})

        case .For:
            append(&stack, Block_Ref{type = .For, index = token_index})

        case .Foreach:
            append(&stack, Block_Ref{type = .Foreach, index = token_index})

        case .Function:
            append(&stack, Block_Ref{type = .Function, index = token_index})

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
                append(&stack, Block_Ref{type = .If, index = token_index})
            }

        case .Else:
            if len(stack) > 0 && stack[len(stack) - 1].type == .If {
                block_reference := pop(&stack)
                state.jump_table[block_reference.index] = token_index

                append(&stack, Block_Ref{type = .Else, index = token_index})
            }

        case .End:
            if len(stack) > 0 {
                block_reference := pop(&stack)
                state.jump_table[block_reference.index] = token_index
                state.jump_table[token_index] = block_reference.index
            }

        case .Break, .Continue:
            for stack_index := len(stack) - 1; stack_index >= 0; stack_index -= 1 {
                current_block := stack[stack_index].type

                is_loop := current_block == .While || current_block == .For || current_block == .Foreach

                if is_loop {
                    if token.keyword == .Break {
                        state.break_table[token_index] = stack[stack_index].index
                    } else {
                        state.continue_table[token_index] = stack[stack_index].index
                    }

                    break
                }
            }
        }
    }
}

_evaluate_function_call :: proc(state: ^State, parser: ^Parser, name: string) -> (Value, bool) {
    if _peek_ahead(parser).type != .LParen {
        return DEFAULT_VALUE, false
    }
    _advance(parser)

    argument_start_index := len(state.argument_stack)

    for _peek_ahead(parser).type != .RParen && _peek_ahead(parser).type != .EOF {
        append(&state.argument_stack, _parse_expression(state, parser))

        if _peek_ahead(parser).type == .Comma {
            _advance(parser)
        }
    }

    if _peek_ahead(parser).type == .RParen {
        _advance(parser)
    }

    arguments_slice := state.argument_stack[argument_start_index:]
    result: Value = DEFAULT_VALUE
    success := false

    if native_proc_pointer, is_native_function := state.native_procs[name]; is_native_function {
        result = native_proc_pointer(state, arguments_slice)
        success = true
    } else if _, is_user_function := state.functions[name]; is_user_function {
        result = _call_user_function(state, parser, name, arguments_slice)
        success = true
    }

    resize(&state.argument_stack, argument_start_index)
    return result, success
}

_parse_statement :: proc(state: ^State, parser: ^Parser) -> (message: string, ok: bool) {
    statement_index := parser.position
    token := _advance(parser)

    if token.type != .Ident {
        return fmt.tprintf("Unexpected token '%s'", token.text), false
    }

    #partial switch token.keyword {
    case .Put:
        evaluated_value := _parse_expression(state, parser)
        fmt.print(value_to_string(evaluated_value))

        return "", true

    case .Sleep:
        evaluated_value := _parse_expression(state, parser)
        if sleep_time_ms, time_is_valid := get_as_f64(evaluated_value); time_is_valid {
            state.sleep_timer = sleep_time_ms
        }
        state.is_sleeping = true

    case .Delete:
        target_identifier := _advance(parser).text

        if _has_var(state, target_identifier) {
            variable_value := _get_var(state, target_identifier)

            if object_reference, is_object := variable_value.(^Object); is_object {
                if object_reference in state.tracked_objects {
                    delete(object_reference^)
                    free(object_reference)
                    delete_key(&state.tracked_objects, object_reference)
                }

                _set_var(state, target_identifier, DEFAULT_VALUE)
            } else if array_reference, is_array := variable_value.(^Array); is_array {
                if array_reference in state.tracked_arrays {
                    delete(array_reference^)
                    free(array_reference)
                    delete_key(&state.tracked_arrays, array_reference)
                }

                _set_var(state, target_identifier, DEFAULT_VALUE)
            } else {
                return fmt.tprintf("Variable '%s' is not an object or array and cannot be deleted", target_identifier), false
            }
        } else {
            return fmt.tprintf("Cannot delete: Variable '%s' does not exist", target_identifier), false
        }

        return "", true


    case .Let:
        first_identifier := _advance(parser).text

        if _has_var(state, first_identifier) {
            return fmt.tprintf("Variable '%s' already exists and cannot be redeclared", first_identifier), false
        }

        if _peek_ahead(parser).type == .Equals {
            _advance(parser) // Skip the =
            _set_var(state, first_identifier, _parse_expression(state, parser))

            return "", true
        }

        _parse_assignment(state, parser, first_identifier)
        return "", true

    case .Const:
        identifier_token := _advance(parser)

        if identifier_token.type != .Ident {
            return "Expected identifier after 'const'", false
        }

        if _has_var(state, identifier_token.text) {
            return fmt.tprintf("Variable '%s' already exists and cannot be redeclared", identifier_token.text), false
        }

        if _peek_ahead(parser).type != .Equals {
            return "'const' requires an assignment", false
        }

        _advance(parser) // skip =
        evaluated_value := _parse_expression(state, parser)

        _set_var(state, identifier_token.text, evaluated_value, true)

        return "", true

    case .While:
        condition_value := _parse_expression(state, parser)
        if _peek_ahead(parser).keyword == .Then {
            _advance(parser)
        }

        if !_is_truthy(condition_value) {
            target := state.jump_table[statement_index]

            if target > 0 {
                parser.position = target + 1
            } else {
                _skip_block_forward(parser)
            }
        }

        return "", true

    case .For:
        identifier := _advance(parser).text

        if _peek_ahead(parser).type == .Equals {
            _advance(parser)
        }
        start_value := _parse_expression(state, parser)

        if _peek_ahead(parser).keyword == .To {
            _advance(parser)
        }
        end_value := _parse_expression(state, parser)

        step_value: Value = int(1)
        if _peek_ahead(parser).keyword == .Step {
            _advance(parser)
            step_value = _parse_expression(state, parser)
        }

        if _peek_ahead(parser).keyword == .Then {
            _advance(parser)
        }

        initialization_key := fmt.tprintf("__for_init_%d", statement_index)
        _, is_initialized := _get_var(state, initialization_key).(bool)

        if !is_initialized {
            _set_var(state, identifier, start_value)
            _set_var(state, initialization_key, true)
        } else {
            current_value := _get_var(state, identifier)
            next_value, _ := _do_math(state, .Plus, current_value, step_value)
            _set_var(state, identifier, next_value)
        }

        current_value := _get_var(state, identifier)
        continue_loop := false

        current_float_value, is_current_float := get_as_f64(current_value)
        end_float_value, is_end_float := get_as_f64(end_value)
        step_float_value, is_step_float := get_as_f64(step_value)

        if is_current_float && is_end_float && is_step_float {
            if step_float_value >= 0 {
                continue_loop = current_float_value <= end_float_value
            } else {
                continue_loop = current_float_value >= end_float_value
            }
        }

        if !continue_loop {
            target := state.jump_table[statement_index]

            if target > 0 {
                parser.position = target + 1
            } else {
                _skip_block_forward(parser)
            }

            _set_var(state, initialization_key, DEFAULT_VALUE)
        }

        return "", true

    case .Foreach:
        key_identifier := _advance(parser).text

        if _peek_ahead(parser).type == .Comma {
            _advance(parser)
        }
        value_identifier := _advance(parser).text

        if _peek_ahead(parser).keyword == .In {
            _advance(parser)
        }
        object_value := _parse_expression(state, parser)

        if _peek_ahead(parser).keyword == .Then {
            _advance(parser)
        }

        initialization_key := fmt.tprintf("__foreach_init_%d", statement_index)
        index_key := fmt.tprintf("__foreach_idx_%d", statement_index)
        keys_key := fmt.tprintf("__foreach_keys_%d", statement_index)

        _, is_initialized := _get_var(state, initialization_key).(bool)

        if !is_initialized {
            keys_object := create_object(state)

            if object_reference, is_object := object_value.(^Object); is_object {
                index := 0
                for key, _ in object_reference^ {
                    _set_object_value(state, keys_object, fmt.tprintf("%d", index), key)
                    index += 1
                }
            } else if array_reference, is_array := object_value.(^Array); is_array {
                for index := 0; index < len(array_reference^); index += 1 {
                    _set_object_value(state, keys_object, fmt.tprintf("%d", index), int(index))
                }
            } else if string_reference, is_string := object_value.(string); is_string {
                for index := 0; index < len(string_reference); index += 1 {
                    _set_object_value(state, keys_object, fmt.tprintf("%d", index), int(index))
                }
            } else {
                return "'foreach' loop requires an object, array, or string", false
            }

            _set_var(state, keys_key, keys_object)
            _set_var(state, initialization_key, true)
            _set_var(state, index_key, int(0))
        } else {
            index_value := _get_var(state, index_key)

            if index, is_index_valid := get_as_int(index_value); is_index_valid {
                _set_var(state, index_key, int(index + 1))
            }
        }

        index_value := _get_var(state, index_key)
        keys_object_value := _get_var(state, keys_key)
        continue_loop := false

        if index, is_index_valid := get_as_int(index_value); is_index_valid {
            if keys_object, is_keys_object_valid := keys_object_value.(^Object); is_keys_object_valid {
                if index < len(keys_object^) {
                    continue_loop = true
                    key_value := keys_object^[fmt.tprintf("%d", index)]

                    if object_reference, is_object := object_value.(^Object); is_object {
                        if key_string, is_key_string := key_value.(string); is_key_string {
                            if key_identifier != "_" {
                                _set_var(state, key_identifier, key_string)
                            }

                            if value_identifier != "_" {
                                _set_var(state, value_identifier, object_reference^[key_string])
                            }
                        }
                    } else if array_reference, is_array := object_value.(^Array); is_array {
                        if key_number, is_key_number := get_as_int(key_value); is_key_number {
                            if key_identifier != "_" {
                                _set_var(state, key_identifier, int(key_number))
                            }

                            if value_identifier != "_" {
                                _set_var(state, value_identifier, array_reference^[key_number])
                            }
                        }
                    } else if string_reference, is_string := object_value.(string); is_string {
                        if key_number, is_key_number := get_as_int(key_value); is_key_number {
                            if key_identifier != "_" {
                                _set_var(state, key_identifier, int(key_number))
                            }

                            if value_identifier != "_" {
                                char_string := string_reference[key_number:key_number + 1]
                                _set_var(state, value_identifier, char_string)
                            }
                        }
                    }
                }
            }
        }

        if !continue_loop {
            target := state.jump_table[statement_index]

            if target > 0 {
                parser.position = target + 1
            } else {
                _skip_block_forward(parser)
            }

            _set_var(state, initialization_key, DEFAULT_VALUE)
        }

        return "", true

    case .End:
        if target, exists := state.jump_table[statement_index]; exists {
            start_token := state.tokens[target]

            #partial switch start_token.keyword {
            case .While, .For, .Foreach:
                parser.position = target

            // NOTE: May be redundant having these here, needs more testing
            case .If, .Else:
            // Do nothing

            case .Function:
                state.is_returning = true
                state.return_value = DEFAULT_VALUE
            }
        } else {
            _skip_block_backward(parser)
        }

        return "", true

    case .Break:
        if loop_index, exists := state.break_table[statement_index]; exists {
            target := state.jump_table[loop_index]
            parser.position = target + 1
        }

        return "", true

    case .Continue:
        if loop_index, exists := state.continue_table[statement_index]; exists {
            parser.position = loop_index
        }

        return "", true

    case .Function:
        name := _advance(parser).text
        _advance(parser) // (

        arguments := make([dynamic]string, context.temp_allocator)

        for _peek_ahead(parser).type == .Ident || _peek_ahead(parser).type == .Ellipsis {
            next_token := _advance(parser)

            if next_token.type == .Ellipsis {
                append(&arguments, "...")

                if _peek_ahead(parser).type == .Comma {
                    return fmt.tprintf("'...' must be the last argument in function '%s'", name), false
                }
                break
            }

            append(&arguments, next_token.text)
            if _peek_ahead(parser).type == .Comma {
                _advance(parser)
            }
        }
        _advance(parser) // )

        cloned_parameters := make([]string, len(arguments))
        for argument, index in arguments {
            cloned_parameters[index] = strings.clone(argument)
        }

        state.functions[name] = Function_Def {
            arguments = cloned_parameters,
            position  = parser.position,
        }

        target := state.jump_table[statement_index]

        if target > 0 {
            parser.position = target + 1
        } else {
            _skip_block_forward(parser)
        }

        return "", true

    case .Return:
        state.return_value = _parse_expression(state, parser)
        state.is_returning = true

        return "", true

    case .If:
        condition := _parse_expression(state, parser)

        if _peek_ahead(parser).keyword != .Then {
            return "Expected 'then'", false
        }
        _advance(parser)

        is_block := (statement_index in state.jump_table)

        if is_block {
            if _is_truthy(condition) {
                return "", true
            } else {
                target := state.jump_table[statement_index]

                if target > 0 {
                    parser.position = target + 1
                } else {
                    _skip_if_false(parser)
                }

                return "", true
            }
        } else {
            if _is_truthy(condition) {
                return _parse_statement(state, parser)
            } else {
                for parser.position < len(parser.tokens) && _peek_ahead(parser).type != .Newline && _peek_ahead(parser).keyword != .Else {
                    _advance(parser)
                }

                if _peek_ahead(parser).keyword == .Else {
                    _advance(parser)

                    return _parse_statement(state, parser)
                }
            }
        }

        return "", true

    case .Else:
        target := state.jump_table[statement_index]

        if target > 0 {
            parser.position = target + 1
        } else {
            _skip_else_block(parser)
        }

        return "", true

    case .None:
        next_token_type := _peek_ahead(parser).type
        is_assignment_operation :=
            next_token_type == .Equals ||
            next_token_type == .PlusEquals ||
            next_token_type == .MinusEquals ||
            next_token_type == .StarEquals ||
            next_token_type == .SlashEquals ||
            next_token_type == .PercentEquals ||
            next_token_type == .Dot ||
            next_token_type == .LBracket

        if is_assignment_operation {
            _parse_assignment(state, parser, token.text)

            return "", true
        }

        if (token.text in state.native_procs) || (token.text in state.functions) {
            _, success := _evaluate_function_call(state, parser, token.text)

            if !success {
                return fmt.tprintf("Expected '(' after '%s'", token.text), false
            }

            return "", true
        }

        if next_token_type == .LParen {
            return fmt.tprintf("Attempted to call unknown function '%s'", token.text), false
        }

        return fmt.tprintf("Unknown function or command: %s", token.text), false
    }

    return "", true
}

_apply_assignment :: proc(state: ^State, operation: Token_Type, current_value: Value, right_value: Value) -> Value {
    if math_result, math_success := _do_math(state, operation, current_value, right_value); math_success {
        return math_result
    } else if operation == .PlusEquals {
        new_string := fmt.tprintf("%v%v", value_to_string(current_value), value_to_string(right_value))

        return intern_string(state, new_string)
    }

    return right_value
}

_parse_expression :: proc(state: ^State, parser: ^Parser) -> Value {
    left := _parse_and(state, parser)

    for _peek_ahead(parser).type == .Or {
        _advance(parser)
        right := _parse_and(state, parser)
        left = _is_truthy(left) || _is_truthy(right)
    }

    return left
}

_parse_and :: proc(state: ^State, parser: ^Parser) -> Value {
    left := _parse_comparison(state, parser)

    for _peek_ahead(parser).type == .And {
        _advance(parser)
        right := _parse_comparison(state, parser)
        left = _is_truthy(left) && _is_truthy(right)
    }

    return left
}

_parse_comparison :: proc(state: ^State, parser: ^Parser) -> Value {
    left := _parse_sum(state, parser)
    token := _peek_ahead(parser)

    is_comparison_operation := token.type == .Equals || token.type == .DoubleEquals || token.type == .NotEqual || token.type == .Less || token.type == .Greater || token.type == .LessEqual || token.type == .GreaterEqual

    if is_comparison_operation {
        operation := _advance(parser).type
        right := _parse_sum(state, parser)

        if operation == .Equals || operation == .DoubleEquals {
            return values_are_equal(left, right)
        }

        if operation == .NotEqual {
            return !values_are_equal(left, right)
        }

        left_number, is_left_valid := get_as_f64(left)
        right_number, is_right_valid := get_as_f64(right)

        if is_left_valid && is_right_valid {
            #partial switch (operation) {
            case .Less:
                return left_number < right_number

            case .Greater:
                return left_number > right_number

            case .LessEqual:
                return left_number <= right_number

            case .GreaterEqual:
                return left_number >= right_number
            }
        }
    }

    return left
}

_parse_sum :: proc(state: ^State, parser: ^Parser) -> Value {
    left := _parse_multiply(state, parser)

    for _peek_ahead(parser).type == .Plus || _peek_ahead(parser).type == .Minus {
        operation := _advance(parser).type
        right := _parse_multiply(state, parser)

        if math_result, math_success := _do_math(state, operation, left, right); math_success {
            left = math_result
        } else if operation == .Plus {
            new_string := fmt.tprintf("%v%v", value_to_string(left), value_to_string(right))
            left = intern_string(state, new_string)
        }
    }

    return left
}

_parse_multiply :: proc(state: ^State, parser: ^Parser) -> Value {
    left := _parse_factor(state, parser)

    for _peek_ahead(parser).type == .Star || _peek_ahead(parser).type == .Slash || _peek_ahead(parser).type == .Percent {
        operation := _advance(parser).type
        right := _parse_factor(state, parser)

        if math_result, math_success := _do_math(state, operation, left, right); math_success {
            left = math_result
        }
    }

    return left
}

_parse_factor :: proc(state: ^State, parser: ^Parser) -> Value {
    token := _advance(parser)
    value: Value = DEFAULT_VALUE

    #partial switch token.type {
    case .Ellipsis:
        value = _get_var(state, "...")

    case .Number:
        if strings.contains(token.text, ".") {
            parsed_value, _ := strconv.parse_f64(token.text)
            value = parsed_value
        } else {
            parsed_value, _ := strconv.parse_int(token.text, 10)
            value = parsed_value
        }

    case .String:
        value = intern_string(state, token.text)

    case .Ident:
        #partial switch token.keyword {
        case .True:
            value = true

        case .False:
            value = false

        case .Null:
            value = Null_Value{}

        case .Int:
            value = Type_Value.Int

        case .Float:
            value = Type_Value.Float

        case .String:
            value = Type_Value.String

        case .Bool:
            value = Type_Value.Bool

        case .Type:
            value = Type_Value.Type

        case .Array:
            new_array := create_array(state)

            for _peek_ahead(parser).type != .EOF {
                if _peek_ahead(parser).keyword == .End {
                    _advance(parser)
                    break
                }

                next_token_type := _peek_ahead(parser).type
                if next_token_type == .Newline || next_token_type == .Colon || next_token_type == .Comma {
                    _advance(parser)
                    continue
                }

                new_value := _parse_expression(state, parser)
                append(new_array, new_value)
            }

            value = new_array

        case .Object:
            new_object := create_object(state)
            array_index := 0

            for _peek_ahead(parser).type != .EOF {
                if _peek_ahead(parser).keyword == .End {
                    _advance(parser)
                    break
                }

                next_token_type := _peek_ahead(parser).type
                if next_token_type == .Newline || next_token_type == .Colon || next_token_type == .Comma {
                    _advance(parser)
                    continue
                }

                is_key_value := false
                if _peek_ahead(parser).type == .Ident && _peek_ahead(parser, 1).type == .Equals {
                    is_key_value = true
                }

                if is_key_value {
                    key := _advance(parser).text
                    _advance(parser) // skip =
                    _set_object_value(state, new_object, key, _parse_expression(state, parser))
                } else {
                    new_value := _parse_expression(state, parser)
                    key := fmt.tprintf("%d", array_index)
                    _set_object_value(state, new_object, key, new_value)
                    array_index += 1
                }
            }

            value = new_object

        case .None:
            name := token.text
            if (name in state.native_procs) || (name in state.functions) {
                new_value, success := _evaluate_function_call(state, parser, name)
                if !success {
                    message := fmt.aprintf("Expected '(' after function '%s'", name)
                    state.log_proc(.Fatal, message, token.line)
                    state.should_close = true

                    delete(message)
                    return DEFAULT_VALUE
                }
                value = new_value
            } else {
                if _peek_ahead(parser).type == .LParen {
                    message := fmt.aprintf("Attempted to call unknown function '%s'", name)
                    state.log_proc(.Fatal, message, token.line)
                    state.should_close = true
                    delete(message)

                    return DEFAULT_VALUE
                }

                value = _get_var(state, name)
            }
        }

    case .LParen:
        value = _parse_expression(state, parser)
        if _peek_ahead(parser).type == .RParen {
            _advance(parser)
        }

    case .Minus:
        inner_value := _parse_factor(state, parser)
        if value_float, is_float := inner_value.(f64); is_float {
            return -value_float
        }

        if value_integer, is_integer := inner_value.(int); is_integer {
            return -value_integer
        }

        return DEFAULT_VALUE

    case .Not:
        inner_value := _parse_factor(state, parser)
        return !_is_truthy(inner_value)
    }

    // --- SUFFIX LOOP ---
    for {
        next_token_type := _peek_ahead(parser).type

        if next_token_type != .Dot && next_token_type != .LBracket && next_token_type != .DoubleColon {
            break
        }

        if next_token_type == .Dot {
            _advance(parser)
            property := _advance(parser).text

            if object_reference, is_object := value.(^Object); is_object {
                if new_value, exists := object_reference^[property]; exists {
                    value = new_value
                } else {
                    value = DEFAULT_VALUE
                }
            } else {
                value = DEFAULT_VALUE
            }

        } else if next_token_type == .LBracket {
            bracket_token := _advance(parser)
            index_value := _parse_expression(state, parser)

            if _peek_ahead(parser).type == .RBracket {
                _advance(parser)
            }

            if object_reference, is_object := value.(^Object); is_object {
                key := _to_key(index_value)
                if new_value, exists := object_reference^[key]; exists {
                    value = new_value
                } else {
                    value = DEFAULT_VALUE
                }
            } else if array_reference, is_array := value.(^Array); is_array {
                if array_index, is_number := get_as_int(index_value); is_number {
                    if array_index >= 0 && array_index < len(array_reference^) {
                        value = array_reference^[array_index]
                    } else {
                        warning_msg := fmt.aprintf("Array index %d out of bounds (Length: %d). Returning null.", array_index, len(array_reference^))
                        state.log_proc(.Warning, warning_msg, bracket_token.line)
                        delete(warning_msg)

                        value = DEFAULT_VALUE
                    }
                } else {
                    value = DEFAULT_VALUE
                }
            } else if string_reference, is_string := value.(string); is_string {
                if string_index, is_number := get_as_int(index_value); is_number {
                    if string_index >= 0 && string_index < len(string_reference) {
                        value = string_reference[string_index:string_index + 1]
                    } else {
                        warning_msg := fmt.aprintf("String index %d out of bounds (Length: %d). Returning null.", string_index, len(string_reference))
                        state.log_proc(.Warning, warning_msg, bracket_token.line)
                        delete(warning_msg)

                        value = DEFAULT_VALUE
                    }
                } else {
                    value = DEFAULT_VALUE
                }
            } else {
                value = DEFAULT_VALUE
            }
        } else if next_token_type == .DoubleColon {
            _advance(parser) // skip ::
            type_token := _advance(parser)

            if type_token.type != .Ident {
                error_message := fmt.aprintf("Expected type identifier after '::', got '%s'", type_token.text)
                state.log_proc(.Error, error_message, type_token.line)
                delete(error_message)
                state.should_close = true

                return DEFAULT_VALUE
            }

            type_name := type_token.text
            switch type_name {

            case "len":
                #partial switch actual_value in value {
                case string:
                    value = len(actual_value)

                case ^Object:
                    value = len(actual_value^)

                case ^Array:
                    value = len(actual_value^)

                case:
                    value = 0
                }

            case "type":
                #partial switch actual_value in value {
                case f64:
                    value = Type_Value.Float

                case int:
                    value = Type_Value.Int

                case string:
                    value = Type_Value.String

                case bool:
                    value = Type_Value.Bool

                case ^Object:
                    value = Type_Value.Object

                case ^Array:
                    value = Type_Value.Array

                case Null_Value:
                    value = Type_Value.Null

                case Type_Value:
                    value = Type_Value.Type
                }

            case "int":
                if numeric_value, is_number := get_as_int(value); is_number {
                    value = numeric_value
                } else if string_value, is_string := value.(string); is_string {
                    if parsed_int, is_valid_int := strconv.parse_int(string_value, 10); is_valid_int {
                        value = parsed_int
                    } else if parsed_float, is_valid_float := strconv.parse_f64(string_value); is_valid_float {
                        value = int(parsed_float)
                    } else {
                        value = int(0)
                    }
                } else if boolean_value, is_bool := value.(bool); is_bool {
                    if boolean_value {
                        value = int(1)
                    } else {
                        value = int(0)
                    }
                } else {
                    value = int(0)
                }

            case "float":
                if numeric_value, is_number := get_as_f64(value); is_number {
                    value = numeric_value
                } else if string_value, is_string := value.(string); is_string {
                    if parsed_float, is_valid_float := strconv.parse_f64(string_value); is_valid_float {
                        value = parsed_float
                    } else {
                        value = f64(0.0)
                    }
                } else if boolean_value, is_bool := value.(bool); is_bool {
                    if boolean_value {
                        value = f64(1.0)
                    } else {
                        value = f64(0.0)
                    }
                } else {
                    value = f64(0.0)
                }

            case "string":
                value = intern_string(state, value_to_string(value))

            case "bool":
                value = _is_truthy(value)

            case:
                error_message := fmt.aprintf("Unknown type or property '%s' after '::'", type_name)
                state.log_proc(.Error, error_message, type_token.line)
                delete(error_message)
                state.should_close = true

                return DEFAULT_VALUE
            }
        }
    }

    return value
}

// TODO: Clean up... Massively
_parse_assignment :: proc(state: ^State, parser: ^Parser, first_identifier: string) {
    next_token_type := _peek_ahead(parser).type
    is_assignment_operation := next_token_type == .Equals || next_token_type == .PlusEquals || next_token_type == .MinusEquals || next_token_type == .StarEquals || next_token_type == .SlashEquals || next_token_type == .PercentEquals

    if is_assignment_operation {
        operation := _advance(parser).type
        right_value := _parse_expression(state, parser)

        if operation != .Equals {
            current_value := _get_var(state, first_identifier)
            right_value = _apply_assignment(state, operation, current_value, right_value)
        }
        _set_var(state, first_identifier, right_value)
        return
    }

    value := _get_var(state, first_identifier)

    for {
        next_token_type = _peek_ahead(parser).type
        if next_token_type != .Dot && next_token_type != .LBracket {
            break
        }

        if next_token_type == .Dot {
            _advance(parser)
            property := _advance(parser).text

            next_token_type = _peek_ahead(parser).type
            is_assignment_operation = next_token_type == .Equals || next_token_type == .PlusEquals || next_token_type == .MinusEquals || next_token_type == .StarEquals || next_token_type == .SlashEquals || next_token_type == .PercentEquals

            if is_assignment_operation {
                operation := _advance(parser).type
                right_value := _parse_expression(state, parser)

                if object_reference, is_object := value.(^Object); is_object {
                    if operation != .Equals {
                        current_value: Value = DEFAULT_VALUE
                        if existing_value, exists := object_reference^[property]; exists {
                            current_value = existing_value
                        }

                        right_value = _apply_assignment(state, operation, current_value, right_value)
                    }

                    _set_object_value(state, object_reference, property, right_value)
                }

                return
            } else {
                if object_reference, is_object := value.(^Object); is_object {
                    if new_value, exists := object_reference^[property]; exists {
                        value = new_value
                    } else {
                        value = DEFAULT_VALUE
                    }
                } else {
                    value = DEFAULT_VALUE
                }
            }
        } else if next_token_type == .LBracket {
            bracket_token := _advance(parser)
            index_value := _parse_expression(state, parser)

            if _peek_ahead(parser).type == .RBracket {
                _advance(parser)
            }

            next_token_type = _peek_ahead(parser).type
            is_assignment_operation = next_token_type == .Equals || next_token_type == .PlusEquals || next_token_type == .MinusEquals || next_token_type == .StarEquals || next_token_type == .SlashEquals || next_token_type == .PercentEquals

            if is_assignment_operation {
                operation := _advance(parser).type
                right_value := _parse_expression(state, parser)

                if object_reference, is_object := value.(^Object); is_object {
                    key := _to_key(index_value)
                    if operation != .Equals {
                        current_value: Value = DEFAULT_VALUE
                        if existing_value, exists := object_reference^[key]; exists {
                            current_value = existing_value
                        }

                        right_value = _apply_assignment(state, operation, current_value, right_value)
                    }

                    _set_object_value(state, object_reference, key, right_value)
                } else if array_reference, is_array := value.(^Array); is_array {
                    if array_index, is_number := get_as_int(index_value); is_number {
                        if array_index >= 0 {
                            old_length := len(array_reference^)
                            is_expansion := array_index >= old_length

                            if is_expansion {
                                resize(array_reference, array_index + 1)
                            }

                            final_value := right_value
                            if operation != .Equals {
                                current_value := array_reference^[array_index]
                                final_value = _apply_assignment(state, operation, current_value, right_value)
                            }

                            array_reference^[array_index] = final_value

                            if is_expansion {
                                for fill_index := old_length; fill_index < array_index; fill_index += 1 {
                                    array_reference^[fill_index] = final_value
                                }
                            }
                        } else {
                            warning_msg := fmt.aprintf("Cannot assign to negative array index %d.", array_index)
                            state.log_proc(.Warning, warning_msg, bracket_token.line)
                            delete(warning_msg)
                        }
                    }
                } else if _, is_string := value.(string); is_string {
                    warning_msg := fmt.aprintf("Strings are read-only. Cannot assign to a string index.")
                    state.log_proc(.Warning, warning_msg, bracket_token.line)
                    delete(warning_msg)
                }

                return
            } else {
                if object_reference, is_object := value.(^Object); is_object {
                    key := _to_key(index_value)
                    if new_value, exists := object_reference^[key]; exists {
                        value = new_value
                    } else {
                        value = DEFAULT_VALUE
                    }
                } else if array_reference, is_array := value.(^Array); is_array {
                    if array_index, is_number := get_as_int(index_value); is_number {
                        if array_index >= 0 && array_index < len(array_reference^) {
                            value = array_reference^[array_index]
                        } else {
                            warning_msg := fmt.aprintf("Array index %d out of bounds (Length: %d). Returning null.", array_index, len(array_reference^))
                            state.log_proc(.Warning, warning_msg, bracket_token.line)
                            delete(warning_msg)

                            value = DEFAULT_VALUE
                        }
                    } else {
                        value = DEFAULT_VALUE
                    }
                } else if string_reference, is_string := value.(string); is_string {
                    if string_index, is_number := get_as_int(index_value); is_number {
                        if string_index >= 0 && string_index < len(string_reference) {
                            value = string_reference[string_index:string_index + 1]
                        } else {
                            warning_msg := fmt.aprintf("String index %d out of bounds (Length: %d). Returning null.", string_index, len(string_reference))
                            state.log_proc(.Warning, warning_msg, bracket_token.line)
                            delete(warning_msg)

                            value = DEFAULT_VALUE
                        }
                    } else {
                        value = DEFAULT_VALUE
                    }
                } else {
                    value = DEFAULT_VALUE
                }
            }
        }

    }
}

_call_user_function :: proc(state: ^State, parser: ^Parser, name: string, arguments: []Value) -> Value {
    function := state.functions[name]
    local_scope: map[string]Variable_Slot

    if len(state.scope_pool) > 0 {
        local_scope = pop(&state.scope_pool)
        clear(&local_scope)
    } else {
        local_scope = make(map[string]Variable_Slot)
    }

    for argument, argument_index in function.arguments {
        if argument == "..." {
            var_array := create_array(state)
            for i := argument_index; i < len(arguments); i += 1 {
                append(var_array, arguments[i])
            }

            local_scope["..."] = Variable_Slot {
                value    = var_array,
                is_const = true,
            }
            break

        } else if argument_index < len(arguments) {
            local_scope[argument] = Variable_Slot {
                value    = arguments[argument_index],
                is_const = false,
            }
        }
    }

    append(&state.scopes, local_scope)

    old_position := parser.position
    parser.position = function.position

    for parser.position < len(parser.tokens) {
        if state.is_returning {
            break
        }

        next_token_type := _peek_ahead(parser).type
        if next_token_type == .Newline || next_token_type == .Colon {
            _advance(parser)
            continue
        }

        message, ok := _parse_statement(state, parser)
        if !ok {
            error_token := _peek_ahead(parser)

            error := fmt.aprintf("'%s' near '%s'!", message, error_token.text)
            state.log_proc(.Fatal, error, error_token.line)
            delete(error)

            state.should_close = true

            break
        }

        if state.is_sleeping {
            state.log_proc(.Fatal, "Cannot sleep inside a function!")
            state.is_sleeping = false
            state.should_close = true

            break
        }
    }

    result := state.return_value
    state.is_returning = false
    state.return_value = DEFAULT_VALUE

    popped_scope := pop(&state.scopes)

    if variadic_slot, has_variadic := popped_scope["..."]; has_variadic {
        if array_ref, is_array := variadic_slot.value.(^Array); is_array {
            is_escaping := false

            if result_array, result_is_array := result.(^Array); result_is_array && result_array == array_ref {
                is_escaping = true
            }

            if !is_escaping {
                free_array(state, array_ref)
            }
        }

        delete_key(&popped_scope, "...")
    }

    append(&state.scope_pool, popped_scope)

    parser.position = old_position

    return result
}

// -----------------------------------------------------------------------------
// Skips
// -----------------------------------------------------------------------------

_skip_block_forward :: proc(parser: ^Parser) {
    nest := 1

    for parser.position < len(parser.tokens) {
        token := _advance(parser)
        #partial switch token.keyword {
        case .While, .For, .Foreach, .Function, .Object, .Array:
            nest += 1

        case .If:
            if _peek_ahead(parser).keyword == .Then {
                nest += 1
            }

        case .End:
            nest -= 1
        }

        if nest == 0 {
            break
        }
    }
}

_skip_block_backward :: proc(parser: ^Parser) {
    nest := 1
    parser.position -= 1

    for parser.position > 0 {
        parser.position -= 1
        token := parser.tokens[parser.position]

        if token.keyword == .End {
            nest += 1
        } else {
            #partial switch token.keyword {
            case .While, .For, .Foreach, .Function, .Object, .Array, .If:
                nest -= 1
            }
        }

        if nest == 0 {
            break
        }
    }

    if nest > 0 {
        parser.position = len(parser.tokens)
    }
}

_skip_if_false :: proc(parser: ^Parser) {
    nest := 1

    loop: for parser.position < len(parser.tokens) {
        token := _advance(parser)

        #partial switch token.keyword {
        case .If:
            if _peek_ahead(parser).keyword == .Then {
                nest += 1
            }

        case .End:
            nest -= 1

            if nest == 0 {
                break loop
            }

        case .Else:
            if nest == 1 {
                break loop
            }
        }
    }
}

_skip_else_block :: proc(parser: ^Parser) {
    nest := 1

    for parser.position < len(parser.tokens) {
        token := _advance(parser)

        if token.keyword == .If {
            if _peek_ahead(parser).keyword == .Then {
                nest += 1
            }
        } else if token.keyword == .End {
            nest -= 1

            if nest == 0 {
                break
            }
        }
    }
}

_set_object_value :: proc(state: ^State, target_object: ^Object, key: string, value: Value) {
    if key in target_object^ {
        target_object^[key] = value
    } else {
        persistent_key := intern_string(state, key)
        target_object^[persistent_key] = value
    }
}
