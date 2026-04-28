package main

import simp "../../src"
import lib "../../src/lib"
import "core:os"
import rl "vendor:raylib"

player_x: f64 = 400.0
player_y: f64 = 300.0
player_color := rl.BLACK

fn_set_color :: proc(state: ^simp.State, arguments: []simp.Value) {
    if len(arguments) >= 3 {
        args := arguments

        r, _ := simp.pop_int(&args)
        g, _ := simp.pop_int(&args)
        b, _ := simp.pop_int(&args)

        player_color = rl.Color{u8(r), u8(g), u8(b), 255}
    }
}

Script :: struct {
    is_loaded: bool,
    state:     simp.State,
    name:      string,
}

init_script :: proc(script: ^Script, script_path: string) -> bool {
    script.name = os.short_stem(script_path)
    simp.state_init(&script.state)

    if !simp.state_load_file(&script.state, script_path) {
        return false
    }

    lib.load_math_library(&script.state)

    simp.bind_native_proc(&script.state, "set_color", fn_set_color)

    simp.bind_variable(&script.state, "player_x", &player_x)
    simp.bind_variable(&script.state, "player_y", &player_y)

    script.is_loaded = true

    return true
}

main :: proc() {
    rl.InitWindow(800, 600, "SIMP: Multi-Script Example")
    rl.SetTargetFPS(60)

    // This is purely for an example, would suggest an array or map
    script_movement: Script
    script_rainbow: Script

    init_script(&script_movement, "movement.smp")
    init_script(&script_rainbow, "rainbow.smp")

    defer {
        if script_movement.is_loaded {
            simp.state_destroy(&script_movement.state)
        }

        if script_movement.is_loaded {
            simp.state_destroy(&script_rainbow.state)
        }

        rl.CloseWindow()
    }


    for !rl.WindowShouldClose() {
        delta_time_ms := f64(rl.GetFrameTime()) * 1000.0

        simp.state_step(&script_movement.state, delta_time_ms)
        simp.state_step(&script_rainbow.state, delta_time_ms)

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        rl.DrawText("Running 2 Script Scripts Simultaneously!", 10, 10, 20, rl.DARKGRAY)

        rl.DrawCircle(i32(player_x), i32(player_y), 40.0, player_color)

        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}
