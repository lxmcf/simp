package simp

import "core:fmt"
import "core:strings"

Native_Proc_Return :: #type proc(state: ^State, arguments: []Value) -> Value
Native_Proc_No_Return :: #type proc(state: ^State, arguments: []Value)

Native_Proc :: union {
    Native_Proc_No_Return,
    Native_Proc_Return,
}

// -----------------------------------------------------------------------------
// State Binding
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Arrays & Objects
// -----------------------------------------------------------------------------

object_set :: proc(state: ^State, target: ^Object, key: string, value: Value) {
    if target == nil {
        return
    }

    value_to_store := value
    if str, is_str := value.(string); is_str {
        value_to_store = intern_string(state, str)
    }

    if key in target^ {
        target^[key] = value_to_store
    } else {
        target^[intern_string(state, key)] = value_to_store
    }
}

object_get :: proc(target: ^Object, key: string) -> (Value, bool) {
    if target == nil {
        return DEFAULT_RETURN_VALUE, false
    }

    val, ok := target^[key]
    return val, ok
}

object_has :: proc(target: ^Object, key: string) -> bool {
    return target == nil ? false : key in target^
}

array_append :: proc(state: ^State, target: ^Array, value: Value) {
    if target == nil do return

    value_to_store := value
    if str, is_str := value.(string); is_str {
        value_to_store = intern_string(state, str)
    }

    append(target, value_to_store)
}

array_get :: proc(target: ^Array, index: int) -> (Value, bool) {
    if target == nil {
        return DEFAULT_RETURN_VALUE, false
    }

    if index >= 0 && index < len(target^) {
        return target^[index], true
    }

    return DEFAULT_RETURN_VALUE, false
}

array_length :: proc(target: ^Array) -> int {
    return target == nil ? 0 : len(target^)
}


// -----------------------------------------------------------------------------
// Argument Popping
// -----------------------------------------------------------------------------

pop_int :: proc(arguments: ^[]Value, default: int = 0) -> (int, bool) {
    if len(arguments^) > 0 {
        if actual_value, ok := value_as_int(arguments^[0]); ok {
            arguments^ = arguments^[1:]
            return actual_value, true
        }
    }

    return default, false
}

pop_f64 :: proc(arguments: ^[]Value, default: f64 = 0.0) -> (f64, bool) {
    if len(arguments^) > 0 {
        if actual_value, ok := value_as_f64(arguments^[0]); ok {
            arguments^ = arguments^[1:]
            return actual_value, true
        }
    }

    return default, false
}

pop_i32 :: proc(arguments: ^[]Value, default: i32 = 0) -> (i32, bool) {
    if len(arguments^) > 0 {
        if actual_value, ok := value_as_int(arguments^[0]); ok {
            arguments^ = arguments^[1:]
            return i32(actual_value), true
        }
    }

    return default, false
}

pop_f32 :: proc(arguments: ^[]Value, default: f32 = 0.0) -> (f32, bool) {
    if len(arguments^) > 0 {
        if actual_value, ok := value_as_f64(arguments^[0]); ok {
            arguments^ = arguments^[1:]
            return f32(actual_value), true
        }
    }

    return default, false
}

@(private = "file")
_pop_actual :: #force_inline proc(arguments: ^[]Value, default: $T) -> (T, bool) {
    if len(arguments^) > 0 {
        if actual_value, ok := arguments^[0].(T); ok {
            arguments^ = arguments^[1:]
            return actual_value, true
        }
    }

    return default, false
}

pop_string :: proc(arguments: ^[]Value, default: string = "") -> (string, bool) {
    return _pop_actual(arguments, default)
}

pop_bool :: proc(arguments: ^[]Value, default: bool = false) -> (bool, bool) {
    return _pop_actual(arguments, default)
}

pop_object :: proc(arguments: ^[]Value, default: ^Object = nil) -> (^Object, bool) {
    return _pop_actual(arguments, default)
}

pop_array :: proc(arguments: ^[]Value, default: ^Array = nil) -> (^Array, bool) {
    return _pop_actual(arguments, default)
}

pop_rawptr :: proc(arguments: ^[]Value, default: rawptr = nil) -> (rawptr, bool) {
    return _pop_actual(arguments, default)
}

// -----------------------------------------------------------------------------
// Values
// -----------------------------------------------------------------------------

values_are_equal :: proc(left: Value, right: Value) -> bool {
    left_num, left_valid := value_as_f64(left)
    right_num, right_valid := value_as_f64(right)

    if left_valid && right_valid {
        return left_num == right_num
    }

    left_type, left_is_type := left.(Type_Value)
    right_type, right_is_type := right.(Type_Value)

    if left_is_type && !right_is_type {
        return left_type == _get_value_type(right)
    } else if right_is_type && !left_is_type {
        return right_type == _get_value_type(left)
    }

    return left == right
}

value_to_string :: proc(value: Value) -> string {
    #partial switch raw_value in value {

    case string:
        return raw_value

    case ^string:
        return raw_value^

    case bool:
        return raw_value ? "true" : "false"

    case ^bool:
        return raw_value^ ? "true" : "false"

    case Null_Value:
        return "null"

    case f64, int:
        return fmt.tprintf("%v", raw_value)

    case ^f64:
        return fmt.tprintf("%v", raw_value^)

    case ^f32:
        return fmt.tprintf("%v", raw_value^)

    case ^int:
        return fmt.tprintf("%v", raw_value^)

    case ^i32:
        return fmt.tprintf("%v", raw_value^)

    case Type_Value:
        @(static) type_names := [Type_Value]string {
            .Int      = "int",
            .Float    = "float",
            .String   = "string",
            .Bool     = "bool",
            .Object   = "object",
            .Array    = "array",
            .Pointer  = "pointer",
            .Null     = "null",
            .Function = "function",
            .Type     = "type",
        }

        return type_names[raw_value]

    case ^Array:
        builder := strings.builder_make(context.temp_allocator)
        strings.write_string(&builder, "[")

        for val, index in raw_value^ {
            if index > 0 {
                strings.write_string(&builder, ", ")
            }

            _write_json_value(&builder, val)
        }

        strings.write_string(&builder, "]")
        return strings.to_string(builder)

    case ^Object:
        builder := strings.builder_make(context.temp_allocator)
        strings.write_string(&builder, "{")

        is_first := true
        for key, val in raw_value^ {
            if !is_first {
                strings.write_string(&builder, ", ")
            }

            is_first = false

            fmt.sbprintf(&builder, "%q: ", key)
            _write_json_value(&builder, val)
        }

        strings.write_string(&builder, "}")
        return strings.to_string(builder)
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
