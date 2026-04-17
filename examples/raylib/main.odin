package main

import simp "../../src"
import rl "vendor:raylib"

fn_draw_circle :: proc(state: ^simp.State, args: []simp.Value) -> simp.Value {
    if len(args) < 3 {
        return simp.DEFAULT_VALUE
    }

    arguments := args

    x, _ := simp.pop_int(&arguments)
    y, _ := simp.pop_int(&arguments)
    radius, _ := simp.pop_float(&arguments)

    rl.DrawCircle(i32(x), i32(y), f32(radius), rl.RED)

    return simp.DEFAULT_VALUE
}

fn_is_key_down :: proc(state: ^simp.State, args: []simp.Value) -> simp.Value {
    if len(args) < 1 {
        return false
    }

    key_str := simp.value_to_string(args[0])

    if key_str == "SPACE" {
        return bool(rl.IsKeyDown(.SPACE))
    }

    if key_str == "UP" { return bool(rl.IsKeyDown(.UP)) }
    if key_str == "DOWN" { return bool(rl.IsKeyDown(.DOWN)) }
    if key_str == "LEFT" { return bool(rl.IsKeyDown(.LEFT)) }
    if key_str == "RIGHT" { return bool(rl.IsKeyDown(.RIGHT)) }

    return false
}

main :: proc() {
    state: simp.State
    simp.init_interpreter(&state)
    defer simp.destroy_interpreter(&state)

    simp.register_native_proc(&state, "draw_circle", fn_draw_circle)
    simp.register_native_proc(&state, "is_key_down", fn_is_key_down)

    simp.load_script_from_file(&state, "raylib.smp")

    rl.InitWindow(800, 600, "SIMP + Raylib Integration")
    rl.SetTargetFPS(60)
    defer rl.CloseWindow()

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        if !state.should_close {
            simp.step_state(&state, f64(rl.GetFrameTime()), 100_000)
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
