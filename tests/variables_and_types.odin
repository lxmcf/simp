package tests

import simp "../src"
import test "core:testing"

@(test)
test_variable_decleration :: proc(t: ^test.T) {
    S: simp.State

    simp.state_init(&S)
    defer simp.state_destroy(&S)

    script := `
    	let declaration_mutable = 1337;
     	const DECLARATION_IMMUTABLE  = 1337;
    `

    if _execute_test(t, &S, script) {
        declaration_mutable, _ := simp.get_user_variable(&S, "declaration_mutable")
        declaration_immutable, _ := simp.get_user_variable(&S, "DECLARATION_IMMUTABLE")

        test.expect(t, declaration_mutable == 1337 && declaration_immutable == 1337)
    }
}

@(test)
test_variable_binding :: proc(t: ^test.T) {
    S: simp.State

    simp.state_init(&S)
    defer simp.state_destroy(&S)

    test_bool := false
    test_string := "Hello World"
    test_int := 0
    test_float := 0.0

    simp.bind_variable(&S, "test_bool", &test_bool)
    simp.bind_variable(&S, "test_string", &test_string)
    simp.bind_variable(&S, "test_int", &test_int)
    simp.bind_variable(&S, "test_float", &test_float)

    script := `
   		test_bool = true;
    	test_string = "simp";
    	test_int = 1
    	test_float = 1.5
    `

    if _execute_test(t, &S, script) {
        test_case := (test_bool == true && test_string == "simp" && test_int == 1 && test_float == 1.5)

        test.expectf(t, test_case, "Expected: [true, \"simp\", 1, 1.5] but got [%v, \"%v\", %v, %v]", test_bool, test_string, test_int, test_float)
    }
}
