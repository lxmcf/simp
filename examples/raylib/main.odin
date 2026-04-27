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

    if key == "SPACE" {
        return rl.IsKeyDown(.SPACE)
    }

    if key == "UP" {
        return rl.IsKeyDown(.UP)
    }

    if key == "DOWN" {
        return rl.IsKeyDown(.DOWN)
    }

    if key == "LEFT" {
        return rl.IsKeyDown(.LEFT)
    }

    if key == "RIGHT" {
        return rl.IsKeyDown(.RIGHT)
    }

    return false
}

main :: proc() {
    state: simp.State
    simp.init_state(&state)
    defer simp.destroy_state(&state)

    simp.bind_native_proc(&state, "draw_circle", fn_draw_circle)
    simp.bind_native_proc(&state, "is_key_down", fn_is_key_down)

    simp.bind_variable(&state, "PLAYER_SPEED", PLAYER_SPEED, true)

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
