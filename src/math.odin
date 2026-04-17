package simp

import "core:math"

_do_math :: proc(state: ^State, operation: Token_Type, left: Value, right: Value) -> (Value, bool) {
    is_compound := operation == .PlusEquals || operation == .MinusEquals || operation == .StarEquals || operation == .SlashEquals || operation == .PercentEquals

    left_array_reference, is_left_array := left.(^Array)
    right_array_reference, is_right_array := right.(^Array)

    is_left_number := false
    #partial switch _ in left {
    case f64, int:
        is_left_number = true
    }

    is_right_number := false
    #partial switch _ in right {
    case f64, int:
        is_right_number = true
    }

    if is_left_array && is_right_array {
        if len(left_array_reference^) == len(right_array_reference^) {
            result_array := is_compound ? left_array_reference : create_array(state)

            for index := 0; index < len(left_array_reference^); index += 1 {
                element_result, success := _do_math(state, operation, left_array_reference^[index], right_array_reference^[index])
                final_value: Value = success ? element_result : DEFAULT_VALUE

                if is_compound {
                    result_array^[index] = final_value
                } else {
                    append(result_array, final_value)
                }
            }

            return result_array, true
        }

        return DEFAULT_VALUE, false
    }

    if is_left_array && is_right_number {
        result_array := is_compound ? left_array_reference : create_array(state)

        for index := 0; index < len(left_array_reference^); index += 1 {
            element_result, success := _do_math(state, operation, left_array_reference^[index], right)
            final_value: Value = success ? element_result : DEFAULT_VALUE

            if is_compound {
                result_array^[index] = final_value
            } else {
                append(result_array, final_value)
            }
        }

        return result_array, true
    }

    if is_left_number && is_right_array {
        new_array := create_array(state)

        for index := 0; index < len(right_array_reference^); index += 1 {
            element_result, success := _do_math(state, operation, left, right_array_reference^[index])

            if success {
                append(new_array, element_result)
            } else {
                append(new_array, DEFAULT_VALUE)
            }
        }

        return new_array, true
    }

    left_float, right_float: f64
    left_integer, right_integer: int

    left_is_float, left_is_integer := false, false
    right_is_float, right_is_integer := false, false

    #partial switch actual_value in left {
    case f64:
        left_float = actual_value
        left_is_float = true

    case int:
        left_integer = actual_value
        left_is_integer = true
    }

    #partial switch actual_value in right {
    case f64:
        right_float = actual_value
        right_is_float = true

    case int:
        right_integer = actual_value
        right_is_integer = true
    }

    if !(left_is_float || left_is_integer) || !(right_is_float || right_is_integer) {
        return DEFAULT_VALUE, false
    }

    use_float := left_is_float || right_is_float
    if use_float {
        left_float_value := left_is_float ? left_float : f64(left_integer)
        right_float_value := right_is_float ? right_float : f64(right_integer)

        #partial switch operation {
        case .Plus, .PlusEquals:
            return left_float_value + right_float_value, true

        case .Minus, .MinusEquals:
            return left_float_value - right_float_value, true

        case .Star, .StarEquals:
            return left_float_value * right_float_value, true

        case .Slash, .SlashEquals:
            return left_float_value / right_float_value, true

        case .Percent, .PercentEquals:
            return math.mod(left_float_value, right_float_value), true
        }
    } else {
        #partial switch operation {
        case .Plus, .PlusEquals:
            return left_integer + right_integer, true

        case .Minus, .MinusEquals:
            return left_integer - right_integer, true

        case .Star, .StarEquals:
            return left_integer * right_integer, true

        case .Slash, .SlashEquals:
            if right_integer == 0 {
                return int(0), true
            }

            return left_integer / right_integer, true

        case .Percent, .PercentEquals:
            if right_integer == 0 {
                return int(0), true
            }

            return left_integer % right_integer, true
        }
    }

    return DEFAULT_VALUE, false
}
