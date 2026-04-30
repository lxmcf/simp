package simp

import "core:fmt"
import "core:strings"

Native_Proc_Return :: #type proc(state: ^State, arguments: []Value) -> Value
Native_Proc_No_Return :: #type proc(state: ^State, arguments: []Value)

Native_Proc :: union {
    Native_Proc_No_Return,
    Native_Proc_Return,
}

bind_native_proc :: proc(state: ^State, name: string, function: Native_Proc) {
    state.native_procs[name] = function
}

bind_variable :: proc(state: ^State, name: string, value: Value, is_const := false) -> bool {
    if name not_in state.scopes[0] {
        state.scopes[0][name] = Variable_Slot {
            value    = value,
            is_const = is_const,
            decl_pc  = -1,
        }

        return true
    } else {
        message := fmt.aprintf("Unable to bind variables with name '%s' as it already exists!", name)
        state.log_proc(.Warning, message)
        delete(message)
    }

    return false
}

pop_int :: proc(arguments: ^[]Value) -> (int, bool) {
    if len(arguments^) == 0 {
        return 0, false
    }

    if value, success := value_as_int(arguments^[0]); success {
        arguments^ = arguments^[1:]
        return value, true
    }

    return 0, false
}

pop_f64 :: proc(arguments: ^[]Value) -> (f64, bool) {
    if len(arguments^) == 0 {
        return 0.0, false
    }

    if value, success := value_as_f64(arguments^[0]); success {
        arguments^ = arguments^[1:]
        return value, true
    }

    return 0.0, false
}

pop_i32 :: proc(arguments: ^[]Value) -> (i32, bool) {
    if len(arguments^) == 0 {
        return 0, false
    }

    if value, success := value_as_int(arguments^[0]); success {
        arguments^ = arguments^[1:]
        return i32(value), true
    }

    return 0, false
}

pop_f32 :: proc(arguments: ^[]Value) -> (f32, bool) {
    if len(arguments^) == 0 {
        return 0.0, false
    }

    if value, success := value_as_f64(arguments^[0]); success {
        arguments^ = arguments^[1:]
        return f32(value), true
    }

    return 0.0, false
}

pop_string :: proc(arguments: ^[]Value) -> (string, bool) {
    if len(arguments^) == 0 {
        return "", false
    }

    #partial switch actual_value in arguments^[0] {
    case string:
        arguments^ = arguments^[1:]
        return actual_value, true
    }

    return "", false
}

pop_bool :: proc(arguments: ^[]Value) -> (bool, bool) {
    if len(arguments^) == 0 {
        return false, false
    }

    #partial switch actual_value in arguments^[0] {
    case bool:
        arguments^ = arguments^[1:]
        return actual_value, true
    }

    return false, false
}

pop_object :: proc(arguments: ^[]Value) -> (^Object, bool) {
    if len(arguments^) == 0 {
        return nil, false
    }

    #partial switch actual_value in arguments^[0] {
    case ^Object:
        arguments^ = arguments^[1:]
        return actual_value, true
    }

    return nil, false
}

pop_array :: proc(arguments: ^[]Value) -> (^Array, bool) {
    if len(arguments^) == 0 {
        return nil, false
    }

    #partial switch actual_value in arguments^[0] {
    case ^Array:
        arguments^ = arguments^[1:]
        return actual_value, true
    }

    return nil, false
}

pop_rawptr :: proc(arguments: ^[]Value) -> (rawptr, bool) {
    if len(arguments^) == 0 {
        return nil, false
    }

    #partial switch actual_value in arguments^[0] {
    case rawptr:
        arguments^ = arguments^[1:]
        return actual_value, true
    }

    return nil, false
}

values_are_equal :: proc(left: Value, right: Value) -> bool {
    left_number, is_left_valid := value_as_f64(left)
    right_number, is_right_valid := value_as_f64(right)

    if is_left_valid && is_right_valid {
        return left_number == right_number
    }

    // Allow for 'type' checking
    if left_type, is_left_type := left.(Type_Value); is_left_type {
            #partial switch _ in right {
            case Null_Value: return left_type == .Null
            case int:        return left_type == .Int
            case f64:        return left_type == .Float
            case string:     return left_type == .String
            case bool:       return left_type == .Bool
            case ^Object:    return left_type == .Object
            case ^Array:     return left_type == .Array
            case Type_Value: return left_type == right.(Type_Value)
            }
        }
        if right_type, is_right_type := right.(Type_Value); is_right_type {
            #partial switch _ in left {
            case Null_Value: return right_type == .Null
            case int:        return right_type == .Int
            case f64:        return right_type == .Float
            case string:     return right_type == .String
            case bool:       return right_type == .Bool
            case ^Object:    return right_type == .Object
            case ^Array:     return right_type == .Array
            }
        }

    return left == right
}

value_to_string :: proc(value: Value) -> string {
    #partial switch raw_value in value {
    case f64:
        return fmt.tprintf("%v", raw_value)

    case ^f64:
        return fmt.tprintf("%v", raw_value^)

    case ^f32:
        return fmt.tprintf("%v", raw_value^)

    case int:
        return fmt.tprintf("%v", raw_value)

    case ^int:
        return fmt.tprintf("%v", raw_value^)

    case ^i32:
        return fmt.tprintf("%v", raw_value^)

    case string:
        return raw_value

    case bool:
        return raw_value ? "true" : "false"

    case ^Object:
        builder := strings.builder_make(context.temp_allocator)
        strings.write_string(&builder, "{")

        is_first := true
        for key, val in raw_value^ {
            if !is_first {
                strings.write_string(&builder, ", ")
            }

            is_first = false

            strings.write_string(&builder, fmt.tprintf("%q: ", key))
            _write_json_value(&builder, val)
        }

        strings.write_string(&builder, "}")
        return strings.to_string(builder)

    case ^Array:
        builder := strings.builder_make(context.temp_allocator)
        strings.write_string(&builder, "[")

        for index := 0; index < len(raw_value^); index += 1 {
            if index > 0 {
                strings.write_string(&builder, ", ")
            }

            _write_json_value(&builder, raw_value^[index])
        }

        strings.write_string(&builder, "]")
        return strings.to_string(builder)

    case Null_Value:
        return "null"

    case ^string:
        return raw_value^

    case ^bool:
        return raw_value^ ? "true" : "false"

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

        case .Pointer:
            return "pointer"

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

value_as_f64 :: #force_inline proc(value: Value) -> (f64, bool) {
    #partial switch actual_value in value {
    case f64:
        return actual_value, true

    case int:
        return f64(actual_value), true
    }

    return 0, false
}

value_as_int :: #force_inline proc(value: Value) -> (int, bool) {
    #partial switch actual_value in value {
    case f64:
        return int(actual_value), true

    case int:
        return actual_value, true
    }

    return 0, false
}

@(private = "file")
_write_json_value :: proc(builder: ^strings.Builder, val: Value) {
    if str_val, is_str := val.(string); is_str {
        strings.write_string(builder, fmt.tprintf("%q", str_val))
    } else if str_ptr, is_str_ptr := val.(^string); is_str_ptr {
        strings.write_string(builder, fmt.tprintf("%q", str_ptr^))
    } else {
        strings.write_string(builder, value_to_string(val))
    }
}
