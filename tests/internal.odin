package tests

import simp "../src"
import test "core:testing"

@(private)
_execute_test :: proc(t: ^test.T, S: ^simp.State, script: string) -> (ok: bool) {
    // SCRIPT EVALUATION
    success := simp.state_load_string(S, script, "")
    if !test.expect(t, success, "Script failed to evaluate!") {
        return false
    }

    simp.state_execute(S)

    // SCRIPT EXECUTION
    code := simp.state_get_exit_code(S)
    if !test.expect(t, code == 0, "Script did not exit successfully!") {
        return false
    }

    return true
}

@(disabled = true)
template :: proc(t: ^test.T) {
    S: simp.State

    simp.state_init(&S)
    defer simp.state_destroy(&S)

    script := `

	`

    if _execute_test(t, &S, script) {

    }
}
