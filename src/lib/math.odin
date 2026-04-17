package lib

import simp "../"
import "core:math"
import "core:math/rand"

MATH_VERSION :: 100

load_math_library :: proc(state: ^simp.State) {
    simp.register_native_proc(state, "rand", fn_rand)
    simp.register_native_proc(state, "abs", fn_abs)
    simp.register_native_proc(state, "sqrt", fn_sqrt)
    simp.register_native_proc(state, "sin", fn_sin)
    simp.register_native_proc(state, "cos", fn_cos)
    simp.register_native_proc(state, "pow", fn_pow)
    simp.register_native_proc(state, "min", fn_min)
    simp.register_native_proc(state, "max", fn_max)
    simp.register_native_proc(state, "floor", fn_floor)
    simp.register_native_proc(state, "ceil", fn_ceil)
    simp.register_native_proc(state, "round", fn_round)

    @(static) version := MATH_VERSION
    simp.bind_int(state, "MATH_VERSION", &version, true)
}

// RAND() -> 0.0 to 1.0 (f64)
// RAND(n) -> Integer from 0 to n-1 (int)
fn_rand :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if parsed_integer, is_valid := simp.pop_int(&args); is_valid {
        if parsed_integer > 0 {
            return int(rand.int31_max(i32(parsed_integer)))
        }
    }

    return f64(rand.float64())
}

// Returns the absolute simp.Value: ABS(-5) -> 5
fn_abs :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    if len(arguments) < 1 {
        return simp.DEFAULT_VALUE
    }

    #partial switch actual_value in arguments[0] {
    case int:
        return actual_value < 0 ? -actual_value : actual_value

    case f64:
        return math.abs(actual_value)
    }

    if parsed_float, is_valid := simp.get_as_f64(arguments[0]); is_valid {
        return math.abs(parsed_float)
    }

    return simp.DEFAULT_VALUE
}

// sqrt(16) -> 4
fn_sqrt :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if parsed_float, is_valid := simp.pop_float(&args); is_valid {
        if parsed_float > 0 {
            return math.sqrt(parsed_float)
        }
    }

    return simp.DEFAULT_VALUE
}

fn_sin :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if parsed_float, is_valid := simp.pop_float(&args); is_valid {
        return math.sin(parsed_float)
    }

    return simp.DEFAULT_VALUE
}

fn_cos :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if parsed_float, is_valid := simp.pop_float(&args); is_valid {
        return math.cos(parsed_float)
    }

    return simp.DEFAULT_VALUE
}

// pow(2, 3) -> 8
fn_pow :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    base_value, is_base_valid := simp.pop_float(&args)
    exponent_value, is_exponent_valid := simp.pop_float(&args)

    if is_base_valid && is_exponent_valid {
        return math.pow(base_value, exponent_value)
    }

    return simp.DEFAULT_VALUE
}

// min(a, b)
fn_min :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    left_value, is_left_valid := simp.pop_float(&args)
    right_value, is_right_valid := simp.pop_float(&args)

    if is_left_valid && is_right_valid {
        return left_value < right_value ? arguments[0] : arguments[1]
    }

    return simp.DEFAULT_VALUE
}

// max(a, b)
fn_max :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    left_value, is_left_valid := simp.pop_float(&args)
    right_value, is_right_valid := simp.pop_float(&args)

    if is_left_valid && is_right_valid {
        return left_value > right_value ? arguments[0] : arguments[1]
    }

    return simp.DEFAULT_VALUE
}

// floor(4.8) -> 4
fn_floor :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if parsed_float, is_valid := simp.pop_float(&args); is_valid {
        return math.floor(parsed_float)
    }

    return simp.DEFAULT_VALUE
}

// ceil(4.2) -> 5
fn_ceil :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments
    if parsed_float, is_valid := simp.pop_float(&args); is_valid {
        return math.ceil(parsed_float)
    }
    return simp.DEFAULT_VALUE
}

// round(4.5) -> 5
fn_round :: proc(state: ^simp.State, arguments: []simp.Value) -> simp.Value {
    args := arguments

    if parsed_float, is_valid := simp.pop_float(&args); is_valid {
        return math.round(parsed_float)
    }

    return simp.DEFAULT_VALUE
}
