package main

import simp "../../src"
import rl "vendor:raylib"

PLAYER_SPEED :: 5.0

fn_draw_circle :: proc(state: ^simp.State, args: []simp.Value) {
    if len(args) < 3 {
        return
    }

    arguments := args

    x, _ := simp.pop_i32(&arguments)
    y, _ := simp.pop_i32(&arguments)
    radius, _ := simp.pop_f32(&arguments)

    rl.DrawCircle(x, y, radius, rl.RED)
}

fn_is_key_down :: proc(state: ^simp.State, args: []simp.Value) -> simp.Value {
    if len(args) < 1 {
        return false
    }

    key := simp.value_to_string(args[0])
    switch key {
    case "SPACE":
        return rl.IsKeyDown(.SPACE)

    case "UP":
        return rl.IsKeyDown(.UP)

    case "DOWN":
        return rl.IsKeyDown(.DOWN)

    case "LEFT":
        return rl.IsKeyDown(.LEFT)

    case "RIGHT":
        return rl.IsKeyDown(.RIGHT)
    }

    return false
}

main :: proc() {
    state: simp.State
    simp.state_init(&state)
    defer simp.state_destroy(&state)

    simp.bind_native_proc(&state, "draw_circle", fn_draw_circle)
    simp.bind_native_proc(&state, "is_key_down", fn_is_key_down)

    simp.bind_variable(&state, "PLAYER_SPEED", PLAYER_SPEED, true)

    simp.state_load_file(&state, "raylib.smp")

    rl.InitWindow(800, 600, "SIMP + Raylib Integration")
    rl.SetTargetFPS(60)
    defer rl.CloseWindow()

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        if !state.should_close {
            simp.state_step(&state, f64(rl.GetFrameTime()), 100_000)
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
