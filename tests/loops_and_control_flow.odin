package tests

import simp "../src"
import test "core:testing"

@(test)
test_flow_if_else :: proc(t: ^test.T) {
    S: simp.State

    simp.state_init(&S)
    defer simp.state_destroy(&S)

    script := `
        let branch_a = 0;
        if true { branch_a = 1 } else { branch_a = 2 }

        let branch_b = 0;
        if false { branch_b = 1 } else { branch_b = 2 }

        let branch_c = 0;
        let val = 5;

        if val == 1 {
            branch_c = 1
        } else if val == 5 {
            branch_c = 5
        } else {
            branch_c = 9
        }
    `

    if _execute_test(t, &S, script) {
        branch_a, _ := simp.get_user_variable(&S, "branch_a")
        branch_b, _ := simp.get_user_variable(&S, "branch_b")
        branch_c, _ := simp.get_user_variable(&S, "branch_c")

        test_case := branch_a == 1 && branch_b == 2 && branch_c == 5
        test.expectf(t, test_case, "Expected[1, 2, 5], got [%v, %v, %v]", branch_a, branch_b, branch_c)
    }
}

@(test)
test_flow_while :: proc(t: ^test.T) {
    S: simp.State

    simp.state_init(&S)
    defer simp.state_destroy(&S)

    script := `
        let counter = 0;
        let sum = 0;

        while (counter < 10) {
            counter += 1

            if (counter == 5) then continue
            if (counter == 8) then break

            sum += counter
        }
    `

    if _execute_test(t, &S, script) {
        counter, _ := simp.get_user_variable(&S, "counter")
        sum, _ := simp.get_user_variable(&S, "sum")

        test_case := counter == 8 && sum == 23
        test.expectf(t, test_case, "Expected [counter = 8 and sum = 23], got [counter = %v and sum = %v]", counter, sum)
    }
}

@(test)
test_flow_for_loops :: proc(t: ^test.T) {
    S: simp.State

    simp.state_init(&S)
    defer simp.state_destroy(&S)

    script := `
        // Standard For Loop (1 + 2 + 3 + 4 + 5 = 15)
        let sum_standard = 0
        for (i = 1 to 5) {
            sum_standard += i
        }

        // Stepped For Loop (0 + 2 + 4 + 6 + 8 + 10 = 30)
        let sum_stepped = 0
        for (j = 0 to 10 step 2) {
            sum_stepped += j
        }

        // Foreach Loop
        let arr = array { 10, 20, 30 }
        let foreach_sum = 0
        let last_idx = 0

        foreach (idx, val in arr) {
            foreach_sum += val
            last_idx = idx
        }
    `

    if _execute_test(t, &S, script) {
        sum_standard, _ := simp.get_user_variable(&S, "sum_standard")
        sum_stepped, _ := simp.get_user_variable(&S, "sum_stepped")
        foreach_sum, _ := simp.get_user_variable(&S, "foreach_sum")
        last_idx, _ := simp.get_user_variable(&S, "last_idx")


        test_case := sum_standard == 15 && sum_stepped == 30 && foreach_sum == 60 && last_idx == 2
        test.expectf(t, test_case, "Expected [standard = 15, stepped = 30, foreach = 60, last_idx = 2] Got[standard = %v, stepped = %v, foreach = %v, last_idx = %v]", sum_standard, sum_stepped, foreach_sum, last_idx)
    }
}
