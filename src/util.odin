#+private

package simp

import "core:fmt"
import "core:math"

_is_digit :: #force_inline proc(character: u8) -> bool {
    return character >= '0' && character <= '9'
}

_is_character :: #force_inline proc(character: u8) -> bool {
    return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z')
}

_to_key :: proc(value: Value) -> string {
    #partial switch raw_value in value {
    case f64:
        if math.floor(raw_value) == raw_value {
            return fmt.tprintf("%d", int(raw_value))
        }
        return fmt.tprintf("%f", raw_value)

    case int:
        return fmt.tprintf("%d", raw_value)

    case string:
        return raw_value

    case bool:
        if raw_value {
            return "true"
        } else {
            return "false"
        }

    case ^Object:
        return "[object]"

    case ^Array:
        return "[array]"

    case Null_Value:
        return "null"

    case Type_Value:
        switch raw_value {
        case .Int:
            return "int"

        case .Float:
            return "float"

        case .String:
            return "string"

        case .Bool:
            return "bool"

        case .Object:
            return "object"

        case .Array:
            return "array"

        case .Null:
            return "null"

        case .Function:
            return "function"

        case .Type:
            return "type"

        }
    }

    return ""
}

_get_default_token_text :: proc(token_type: Token_Type, token_keyword: Token_Keyword) -> string {
    if token_keyword != .None {
        #partial switch token_keyword {
        case .Import:
            return "import"

        case .Put:
            return "put"

        case .Delete:
            return "delete"

        case .And:
            return "and"

        case .Or:
            return "or"

        case .Not:
            return "not"

        case .While:
            return "while"

        case .For:
            return "for"

        case .Foreach:
            return "foreach"

        case .In:
            return "in"

        case .Break:
            return "break"

        case .Continue:
            return "continue"

        case .Function:
            return "function"

        case .End:
            return "end"

        case .Then:
            return "then"

        case .Else:
            return "else"

        case .If:
            return "if"

        case .Let:
            return "let"

        case .Const:
            return "const"

        case .To:
            return "to"

        case .Step:
            return "step"

        case .Return:
            return "return"

        case .True:
            return "true"

        case .False:
            return "false"

        case .Null:
            return "null"

        case .Object:
            return "object"

        case .Array:
            return "array"

        case .Int:
            return "int"

        case .Float:
            return "float"

        case .String:
            return "string"

        case .Bool:
            return "bool"

        case .Type:
            return "type"

        case .Ellipsis:
            return "..."
        }
    }

    #partial switch token_type {
    case .Plus:
        return "+"

    case .Minus:
        return "-"

    case .Star:
        return "*"

    case .Slash:
        return "/"

    case .Equals:
        return "="

    case .DoubleEquals:
        return "=="

    case .NotEqual:
        return "!="

    case .Less:
        return "<"

    case .Greater:
        return ">"

    case .LessEqual:
        return "<="

    case .GreaterEqual:
        return ">="

    case .LParen:
        return "("

    case .RParen:
        return ")"

    case .Comma:
        return ","

    case .Colon:
        return ":"

    case .DoubleColon:
        return "::"

    case .Newline:
        return "\n"

    case .LBracket:
        return "["

    case .RBracket:
        return "]"

    case .Dot:
        return "."

    case .Percent:
        return "%"

    case .PlusEquals:
        return "+="

    case .MinusEquals:
        return "-="

    case .StarEquals:
        return "*="

    case .SlashEquals:
        return "/="

    case .PercentEquals:
        return "%="

    case .Ellipsis:
        return "..."

    case .EOF:
        return "EOF"
    }

    return ""
}

_has_var :: proc(state: ^State, name: string) -> bool {
    if name == "_" {
        return false
    }

    for scope_index := len(state.scopes) - 1; scope_index >= 0; scope_index -= 1 {
        if _, exists := state.scopes[scope_index][name]; exists {
            return true
        }
    }
    return false
}

_get_var :: proc(state: ^State, name: string) -> Value {
    scopes_len := len(state.scopes)
    if scopes_len == 0 {
        return DEFAULT_VALUE
    }

    if existing_slot, exists := state.scopes[scopes_len - 1][name]; exists {
        return _resolve_pointer_value(existing_slot)
    }

    for scope_index := scopes_len - 2; scope_index >= 0; scope_index -= 1 {
        if existing_slot, exists := state.scopes[scope_index][name]; exists {
            return _resolve_pointer_value(existing_slot)
        }
    }

    return DEFAULT_VALUE
}

_resolve_pointer_value :: #force_inline proc "contextless" (slot: Variable_Slot) -> Value {
    #partial switch actual_value in slot.value {
    case ^f64:
        return actual_value^

    case ^int:
        return actual_value^

    case ^string:
        return actual_value^

    case ^bool:
        return actual_value^

    case:
        return slot.value
    }
}

_set_var :: proc(state: ^State, name: string, value: Value, is_const: bool = false) {
    if name == "_" {
        return
    }

    for scope_index := len(state.scopes) - 1; scope_index >= 0; scope_index -= 1 {
        if existing_slot, exists := state.scopes[scope_index][name]; exists {
            if existing_slot.is_const {
                state.log_proc(.Error, fmt.tprintf("Cannot reassign constant variable '%s'", name))
                state.should_close = true

                return
            }

            #partial switch target in existing_slot.value {
            case ^f64:
                if value_float, is_float := value.(f64); is_float {
                    target^ = value_float
                    return
                }

            case ^int:
                if value_integer, is_integer := value.(int); is_integer {
                    target^ = value_integer
                    return
                }

            case ^string:
                if string_value, is_string := value.(string); is_string {
                    target^ = intern_string(state, string_value)
                    return
                }

            case ^bool:
                if value_boolean, is_boolean := value.(bool); is_boolean {
                    target^ = value_boolean
                    return
                }

            case:
                value_to_store := value
                if string_value, is_string := value.(string); is_string {
                    value_to_store = intern_string(state, string_value)
                }

                state.scopes[scope_index][name] = Variable_Slot {
                    value    = value_to_store,
                    is_const = is_const,
                }

                return
            }
        }
    }

    persistent_name := intern_string(state, name)

    value_to_store := value
    if string_value, is_string := value.(string); is_string {
        value_to_store = intern_string(state, string_value)
    }

    state.scopes[len(state.scopes) - 1][persistent_name] = Variable_Slot {
        value    = value_to_store,
        is_const = is_const,
    }
}

_is_truthy :: proc(value: Value) -> bool {
    #partial switch raw_value in value {
    case f64:
        return raw_value != 0

    case ^f64:
        return raw_value^ != 0

    case int:
        return raw_value != 0

    case ^int:
        return raw_value^ != 0

    case string:
        return len(raw_value) > 0

    case bool:
        return raw_value

    case ^Object:
        return true

    case ^Array:
        return true

    case Null_Value:
        return false

    case ^string:
        return len(raw_value^) > 0

    case ^bool:
        return raw_value^

    case Type_Value:
        return true
    }

    return false
}
