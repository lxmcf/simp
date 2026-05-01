#+private

package simp

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// -----------------------------------------------------------------------------
// Parser Types
// -----------------------------------------------------------------------------

Parser :: struct {
    tokens:   []Token,
    position: int,
}

_peek_ahead :: #force_inline proc(parser: ^Parser, n: int = 0) -> Token {
    idx := parser.position + n

    if idx < len(parser.tokens) {
        return parser.tokens[idx]
    }

    return Token{type = .EOF, keyword = .None, text = "EOF", line = -1}
}

_advance :: #force_inline proc(parser: ^Parser) -> Token {
    if parser.position < len(parser.tokens) {
        token := parser.tokens[parser.position]
        parser.position += 1

        return token
    }
    return Token{type = .EOF, keyword = .None, text = "EOF", line = -1}
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

    if native_proc_variant, is_native_function := state.native_procs[name]; is_native_function {
        switch raw_proc in native_proc_variant {
        case Native_Proc_Return:
            result = raw_proc(state, arguments_slice)

        case Native_Proc_No_Return:
            raw_proc(state, arguments_slice)
            result = DEFAULT_VALUE
        }

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

    // FIX 1: The Guard must allow Braces to pass through
    if token.type != .Ident && token.type != .LBrace && token.type != .RBrace {
        return fmt.tprintf("Unexpected token '%s'", token.text), false
    }

    // FIX 2: If we start a statement with '{', we just ignore it.
    // The jump table handles the logic; the parser just needs to move past it.
    if token.type == .LBrace {
        return "", true
    }

    #partial switch token.keyword {
    case .Put:
        evaluated_value := _parse_expression(state, parser)
        fmt.print(value_to_string(evaluated_value))
        return "", true

    case .Pull:
        prompt_value := _parse_expression(state, parser)
        fmt.print(value_to_string(prompt_value))
        os.flush(os.stdout)
        input_buffer: [1024]u8
        if _, read_error := os.read(os.stdin, input_buffer[:]); read_error != nil {
            return fmt.tprintf("Failed to pull text: %v", read_error), false
        }
        return "", true

    case .Sleep:
        evaluated_value := _parse_expression(state, parser)
        if sleep_time_ms, time_is_valid := value_as_f64(evaluated_value); time_is_valid {
            state.sleep_timer = sleep_time_ms
        }
        state.is_sleeping = true

    case .Delete:
        id_token := _advance(parser)
        if id_token.type != .Ident {
            return "Expected identifier after 'delete'", false
        }
        target_identifier := id_token.text

        if _has_var(state, target_identifier) {
            variable_value := _get_var(state, target_identifier)

            if object_reference, is_object := variable_value.(^Object); is_object {
                free_object(state, object_reference)
                _set_var(state, target_identifier, DEFAULT_VALUE)
            } else if array_reference, is_array := variable_value.(^Array); is_array {
                free_array(state, array_reference)
                _set_var(state, target_identifier, DEFAULT_VALUE)
            } else {
                // If it's a primitive, just set to null
                _set_var(state, target_identifier, DEFAULT_VALUE)
            }
        } else if target_identifier in state.functions {
            function := state.functions[target_identifier] // Copy the struct
            for argument in function.arguments {
                delete(argument)
            }
            delete(function.arguments) // <-- CRITICAL FIX: Delete the slice itself
            delete_key(&state.functions, target_identifier)
        } else if target_identifier in state.native_procs {
            delete_key(&state.native_procs, target_identifier)
        } else {
            return fmt.tprintf("Cannot delete: Variable or Function '%s' does not exist", target_identifier), false
        }
        return "", true

    case .Exit:
        evaluated_value := _parse_expression(state, parser)
        if exit_code, is_valid := value_as_int(evaluated_value); is_valid {
            state.exit_value = exit_code
        } else {
            state.exit_value = 0
            state.log_proc(.Warning, "Exit code must be an integer, defaulting to 0", token.line)
        }
        state.should_close = true
        state.is_exiting = true
        return "", true

    case .Label:
        if _peek_ahead(parser).type == .Ident {
            _advance(parser)
        } else {
            return "Expected identifier after 'label'", false
        }
        return "", true

    case .Goto:
        target_token := _peek_ahead(parser)
        if target_token.type != .Ident {
            return "Expected identifier after 'goto'", false
        }
        target := state.jump_table[statement_index]
        if target != -1 {
            parser.position = target
        } else {
            return fmt.tprintf("Label '%s' not found", target_token.text), false
        }
        return "", true

    case .Let:
        id_token := _advance(parser)
        if id_token.type != .Ident {
            return "Expected identifier after 'let'", false
        }
        first_identifier := id_token.text
        if slot, exists := _get_slot(state, first_identifier); exists {
            if slot.decl_pc != statement_index {
                return fmt.tprintf("Variable '%s' already exists and cannot be redeclared", first_identifier), false
            }
        }
        if _peek_ahead(parser).type == .Equals {
            _advance(parser)
            _set_var(state, first_identifier, _parse_expression(state, parser), false, statement_index)
            return "", true
        }
        _parse_assignment(state, parser, first_identifier)
        return "", true

    case .Const:
        identifier_token := _advance(parser)
        if identifier_token.type != .Ident {
            return "Expected identifier after 'const'", false
        }
        if slot, exists := _get_slot(state, identifier_token.text); exists {
            if slot.decl_pc != statement_index {
                return fmt.tprintf("Variable '%s' already exists and cannot be redeclared", identifier_token.text), false
            }
        }
        if _peek_ahead(parser).type != .Equals {
            return "'const' requires an assignment", false
        }
        _advance(parser)
        evaluated_value := _parse_expression(state, parser)
        _set_var(state, identifier_token.text, evaluated_value, true, statement_index)
        return "", true

    case .While:
        condition_value := _parse_expression(state, parser)
        if _peek_ahead(parser).type == .LBrace {
            _advance(parser)
        }

        if !_is_truthy(condition_value) {
            target := state.jump_table[statement_index]
            if target != -1 {
                parser.position = target + 1
            } else {
                _skip_block_forward(parser)
            }
        }
        return "", true

    case .For:
        id_token := _advance(parser)
        if id_token.type != .Ident {
            return "Expected identifier after 'for'", false
        }
        identifier := id_token.text
        if _peek_ahead(parser).type == .Equals {
            _advance(parser)
        } else {
            return "Expected '=' after identifier in 'for' loop", false
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
        if _peek_ahead(parser).type == .LBrace {
            _advance(parser)
        }

        initialization_key := fmt.tprintf("__for_init_%d", statement_index)
        _, is_initialized := _get_var(state, initialization_key).(bool)
        if !is_initialized {
            _set_var(state, identifier, start_value)
            _set_var(state, initialization_key, true)
        } else {
            current_value := _get_var(state, identifier)
            next_value, _ := _evaluate_math(state, .Plus, current_value, step_value)
            _set_var(state, identifier, next_value)
        }

        current_value := _get_var(state, identifier)
        continue_loop := false
        current_float_value, is_current_float := value_as_f64(current_value)
        end_float_value, is_end_float := value_as_f64(end_value)
        step_float_value, is_step_float := value_as_f64(step_value)

        if is_current_float && is_end_float && is_step_float {
            if step_float_value >= 0 {
                continue_loop = current_float_value <= end_float_value
            } else {
                continue_loop = current_float_value >= end_float_value
            }
        }

        if !continue_loop {
            target := state.jump_table[statement_index]
            if target != -1 {
                parser.position = target + 1
            } else {
                _skip_block_forward(parser)
            }
            _set_var(state, initialization_key, DEFAULT_VALUE)
        }
        return "", true

    case .Foreach:
        key_token := _advance(parser)
        if key_token.type != .Ident {
            return "Expected key identifier after 'foreach'", false
        }
        key_identifier := key_token.text
        if _peek_ahead(parser).type == .Comma {
            _advance(parser)
        }
        value_token := _advance(parser)
        if value_token.type != .Ident {
            return "Expected value identifier in 'foreach' loop", false
        }
        value_identifier := value_token.text
        if _peek_ahead(parser).keyword == .In {
            _advance(parser)
        }
        object_value := _parse_expression(state, parser)
        if _peek_ahead(parser).type == .LBrace {
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
            if index, is_index_valid := value_as_int(index_value); is_index_valid {
                _set_var(state, index_key, int(index + 1))
            }
        }

        index_value := _get_var(state, index_key)
        keys_object_value := _get_var(state, keys_key)
        continue_loop := false
        if index, is_index_valid := value_as_int(index_value); is_index_valid {
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
                        if key_number, is_key_number := value_as_int(key_value); is_key_number {
                            if key_identifier != "_" {
                                _set_var(state, key_identifier, int(key_number))
                            }
                            if value_identifier != "_" {
                                _set_var(state, value_identifier, array_reference^[key_number])
                            }
                        }
                    } else if string_reference, is_string := object_value.(string); is_string {
                        if key_number, is_key_number := value_as_int(key_value); is_key_number {
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
            if target != -1 {
                parser.position = target + 1
            } else {
                _skip_block_forward(parser)
            }
            _set_var(state, initialization_key, DEFAULT_VALUE)
        }
        return "", true

    case .Break, .Continue:
        target := state.jump_table[statement_index]
        if target != -1 {
            parser.position = token.keyword == .Break ? target + 1 : target
        }
        return "", true

    case .Function:
        name_token := _advance(parser)
        if name_token.type != .Ident {
            return "Expected identifier for function name", false
        }
        name := name_token.text

        if (name in state.functions || name in state.native_procs) {
            return fmt.tprintf("function '%s' is already defined!", name), false
        }

        if _advance(parser).type != .LParen {
            return "Expected '(' after function name", false
        }
        arguments := make([dynamic]string, context.temp_allocator)
        for _peek_ahead(parser).type == .Ident || _peek_ahead(parser).type == .Ellipsis {
            next_token := _advance(parser)
            if next_token.type == .Ellipsis {
                append(&arguments, "...")
                break
            }
            append(&arguments, next_token.text)
            if _peek_ahead(parser).type == .Comma {
                _advance(parser)
            }
        }
        if _advance(parser).type != .RParen {
            return "Expected ')' after arguments", false
        }

        // FIX 3: Consume opening brace for function definition
        if _peek_ahead(parser).type == .LBrace {
            _advance(parser)
        }

        cloned_parameters := make([]string, len(arguments))
        for arg, i in arguments {
            cloned_parameters[i] = strings.clone(arg)
        }

        state.functions[name] = Function_Def {
            arguments = cloned_parameters,
            position  = parser.position,
        }

        target := state.jump_table[statement_index]
        if target != -1 {
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

        if _peek_ahead(parser).type == .LBrace {
            _advance(parser)
            target := state.jump_table[statement_index]

            if _is_truthy(condition) {
                return "", true
            } else {
                if target != -1 {
                    parser.position = target
                    // If we jumped to 'else', we want to skip the keyword and the '{'
                    if state.tokens[parser.position].keyword == .Else {
                        _advance(parser) // skip 'else'
                        if _peek_ahead(parser).type == .LBrace {
                            _advance(parser)
                        }
                    }
                } else {
                    _skip_block_forward(parser)
                }
                return "", true
            }
        } else if _peek_ahead(parser).keyword == .Then {
            _advance(parser)
            if _is_truthy(condition) {
                return _parse_statement(state, parser)
            } else {
                for parser.position < len(parser.tokens) {
                    next_tok := _peek_ahead(parser).type
                    if next_tok == .Newline {
                        break
                    }
                    _advance(parser)
                }
            }
            return "", true
        }
        return "Expected '{' or 'then' after if condition", false

    case .Else:
        // If the interpreter hits 'else' without jumping to it, it means
        // the 'if' block just finished. We must jump over the 'else' block.
        target := state.jump_table[statement_index]
        if target != -1 {
            parser.position = target + 1
        } else {
            if _peek_ahead(parser).type == .LBrace {
                _advance(parser)
            }
            _skip_block_forward(parser)
        }
        return "", true

    case .None:
        if token.type == .RBrace {
            target := state.jump_table[statement_index]
            if target != -1 {
                if target < statement_index {
                    // Backward jump (Loops / Functions)
                    start_tok := state.tokens[target]
                    is_loop := start_tok.keyword == .While || start_tok.keyword == .For || start_tok.keyword == .Foreach
                    if is_loop {
                        parser.position = target
                    } else if start_tok.keyword == .Function {
                        state.is_returning = true
                        state.return_value = DEFAULT_VALUE
                    }
                } else {
                    // Forward jump (End of an IF block jumping over the ELSE block)
                    parser.position = target
                }
            }
            return "", true
        }

        next_tok := _peek_ahead(parser).type
        is_assign := next_tok == .Equals || next_tok == .PlusEquals || next_tok == .MinusEquals || next_tok == .StarEquals || next_tok == .SlashEquals || next_tok == .PercentEquals || next_tok == .Dot || next_tok == .LBracket

        if is_assign {
            if token.text != "_" && !_has_var(state, token.text) {
                return fmt.tprintf("Undeclared variable '%s'!", token.text), false
            }
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

        if next_tok == .LParen {
            return fmt.tprintf("Attempted to call unknown function '%s'", token.text), false
        }

        return fmt.tprintf("Unknown function or command: %s", token.text), false
    }

    return "", true
}

_apply_assignment :: proc(state: ^State, operation: Token_Type, current_value: Value, right_value: Value) -> Value {
    if math_result, math_success := _evaluate_math(state, operation, current_value, right_value); math_success {
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

        left_number, is_left_valid := value_as_f64(left)
        right_number, is_right_valid := value_as_f64(right)

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

        if math_result, math_success := _evaluate_math(state, operation, left, right); math_success {
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

        if math_result, math_success := _evaluate_math(state, operation, left, right); math_success {
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

    case .Number, .String:
        value = state.literals[parser.position - 1]

    case .Ident:
        #partial switch token.keyword {
        case .New:
            type_token := _advance(parser)

            #partial switch type_token.keyword {
            case .Array:
                value = create_array(state)

            case .Object:
                value = create_object(state)

            case .Int:
                value = int(0)

            case .Float:
                value = f64(0.0)

            case .String:
                value = intern_string(state, "")

            case .Bool:
                value = false

            case:
                error_message := fmt.aprintf("Invalid or unknown type '%s' after 'new'", type_token.text)
                state.log_proc(.Error, error_message, type_token.line)
                delete(error_message)
                state.should_close = true

                return DEFAULT_VALUE
            }

        case .Pull:
            prompt_value := _parse_expression(state, parser)
            fmt.print(value_to_string(prompt_value))

            os.flush(os.stdout)

            input_buffer: [1024]u8
            bytes_read, read_error := os.read(os.stdin, input_buffer[:])

            user_input_text := ""
            if read_error == nil && bytes_read > 0 {
                user_input_text = strings.trim_right_space(string(input_buffer[:bytes_read]))
            }

            return intern_string(state, user_input_text)

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

        case .Function:
            value = Type_Value.Function

        case .Array:
            if _peek_ahead(parser).type == .LBrace {
                _advance(parser)
            }
            new_array := create_array(state)

            for _peek_ahead(parser).type != .EOF {
                if _peek_ahead(parser).type == .RBrace {
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
            if _peek_ahead(parser).type == .LBrace {
                _advance(parser)
            }
            new_object := create_object(state)
            array_index := 0

            for _peek_ahead(parser).type != .EOF {
                if _peek_ahead(parser).type == .RBrace {
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
                if _peek_ahead(parser).type == .DoubleColon {
                    _advance(parser) // skip ::
                    type_token := _advance(parser)

                    if type_token.text == "type" {
                        value = Type_Value.Function
                    } else {
                        error_message := fmt.aprintf("Unknown property '%s' for function '%s'", type_token.text, name)
                        state.log_proc(.Error, error_message, type_token.line)
                        delete(error_message)
                        state.should_close = true

                        return DEFAULT_VALUE
                    }
                } else {
                    new_value, success := _evaluate_function_call(state, parser, name)
                    if !success {
                        message := fmt.aprintf("Expected '(' after function '%s'", name)
                        state.log_proc(.Fatal, message, token.line)
                        state.should_close = true
                        delete(message)

                        return DEFAULT_VALUE
                    }

                    value = new_value
                }
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
                if array_index, is_number := value_as_int(index_value); is_number {
                    // Resolve negative index
                    actual_index := array_index
                    if actual_index < 0 {
                        actual_index += len(array_reference^)
                    }

                    if actual_index >= 0 && actual_index < len(array_reference^) {
                        value = array_reference^[actual_index]
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
                if string_index, is_number := value_as_int(index_value); is_number {
                    // Resolve negative index
                    actual_index := string_index
                    if actual_index < 0 {
                        actual_index += len(string_reference)
                    }

                    if actual_index >= 0 && actual_index < len(string_reference) {
                        value = string_reference[actual_index:actual_index + 1]
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
                if numeric_value, is_number := value_as_int(value); is_number {
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
                if numeric_value, is_number := value_as_f64(value); is_number {
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

    parent_value := _get_var(state, first_identifier)

    for {
        next_token_type = _peek_ahead(parser).type
        if next_token_type != .Dot && next_token_type != .LBracket {
            break
        }

        is_dot := next_token_type == .Dot
        bracket_token := _advance(parser) // skip . or[

        key: string
        if is_dot {
            key = _advance(parser).text
        } else {
            key = _to_key(_parse_expression(state, parser))

            if _peek_ahead(parser).type == .RBracket {
                _advance(parser)
            }
        }

        peek_op := _peek_ahead(parser).type
        is_assignment_operation = peek_op == .Equals || peek_op == .PlusEquals || peek_op == .MinusEquals || peek_op == .StarEquals || peek_op == .SlashEquals || peek_op == .PercentEquals

        if is_assignment_operation {
            operation := _advance(parser).type
            right_value := _parse_expression(state, parser)

            if object_reference, is_object := parent_value.(^Object); is_object {
                if operation != .Equals {
                    current_value: Value = DEFAULT_VALUE
                    if existing_value, exists := object_reference^[key]; exists {
                        current_value = existing_value
                    }

                    right_value = _apply_assignment(state, operation, current_value, right_value)
                }

                _set_object_value(state, object_reference, key, right_value)
            } else if array_reference, is_array := parent_value.(^Array); !is_dot && is_array {
                if array_index, is_valid := strconv.parse_int(key, 10); is_valid {
                    actual_index := array_index
                    if actual_index < 0 {
                        actual_index += len(array_reference^)
                    }

                    if actual_index >= 0 {
                        old_length := len(array_reference^)
                        is_expansion := actual_index >= old_length

                        if is_expansion {
                            resize(array_reference, actual_index + 1)
                        }

                        final_value := right_value
                        if operation != .Equals {
                            current_value := array_reference^[actual_index]
                            final_value = _apply_assignment(state, operation, current_value, right_value)
                        }

                        array_reference^[actual_index] = final_value

                        if is_expansion {
                            for fill_index := old_length; fill_index < actual_index; fill_index += 1 {
                                array_reference^[fill_index] = final_value
                            }
                        }
                    } else {
                        warning_msg := fmt.aprintf("Cannot assign to negative array index %d", array_index)
                        state.log_proc(.Warning, warning_msg, bracket_token.line)
                        delete(warning_msg)
                    }
                }
            } else if _, is_string := parent_value.(string); !is_dot && is_string {
                state.log_proc(.Warning, "Strings are read-only. Cannot assign to a string index.", bracket_token.line)
            }

            return
        } else {
            if object_reference, is_object := parent_value.(^Object); is_object {
                if new_value, exists := object_reference^[key]; exists {
                    parent_value = new_value
                } else {
                    parent_value = DEFAULT_VALUE
                }
            } else if array_reference, is_array := parent_value.(^Array); !is_dot && is_array {
                if array_index, is_valid := strconv.parse_int(key, 10); is_valid {
                    actual_index := array_index
                    if actual_index < 0 {
                        actual_index += len(array_reference^)
                    }

                    if actual_index >= 0 && actual_index < len(array_reference^) {
                        parent_value = array_reference^[actual_index]
                    } else {
                        parent_value = DEFAULT_VALUE
                    }
                } else {
                    parent_value = DEFAULT_VALUE
                }
            } else if string_reference, is_string := parent_value.(string); !is_dot && is_string {
                if string_index, is_valid := strconv.parse_int(key, 10); is_valid {
                    actual_index := string_index
                    if actual_index < 0 {
                        actual_index += len(string_reference)
                    }

                    if actual_index >= 0 && actual_index < len(string_reference) {
                        parent_value = string_reference[actual_index:actual_index + 1]
                    } else {
                        parent_value = DEFAULT_VALUE
                    }
                } else {
                    parent_value = DEFAULT_VALUE
                }
            } else {
                parent_value = DEFAULT_VALUE
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
                decl_pc  = -1,
            }
            break

        } else if argument_index < len(arguments) {
            local_scope[argument] = Variable_Slot {
                value    = arguments[argument_index],
                is_const = false,
                decl_pc  = -1,
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
        if token.type == .LBrace {
            nest += 1
        } else if token.type == .RBrace {
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

        if token.type == .RBrace {
            nest += 1
        } else if token.type == .LBrace {
            nest -= 1
        }

        if nest == 0 {
            break
        }
    }

    if nest > 0 {
        parser.position = len(parser.tokens)
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
