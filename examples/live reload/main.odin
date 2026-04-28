package main

import simp "../../src"
import "core:fmt"
import "core:os"
import "core:time"
import rl "vendor:raylib"

Script :: struct {
    state:          simp.State,
    path:           string,
    last_modified:  time.Time,
    is_initialised: bool,
}

background := rl.BLACK
example_string := "Hello SIMP"

fn_set_colour :: proc(state: ^simp.State, arguments: []simp.Value) {
    if len(arguments) == 3 {
        args := arguments

        red, red_ok := simp.pop_i32(&args)
        green, green_ok := simp.pop_i32(&args)
        blue, blue_ok := simp.pop_i32(&args)

        if red_ok && green_ok && blue_ok {
            background.r = u8(red)
            background.g = u8(green)
            background.b = u8(blue)
        }
    }
}

main :: proc() {
    rl.InitWindow(800, 600, "SIMP Hot-Reload")
    rl.SetTargetFPS(60)

    script: Script

    init_script(&script, "script.smp")

    for !rl.WindowShouldClose() {
        delta := f64(rl.GetFrameTime() * 1000)

        poll_script(&script)
        simp.state_step(&script.state, delta, 1000)

        rl.BeginDrawing()
        rl.ClearBackground(background)

        rl.DrawText(fmt.ctprint(example_string), 32, 32, 40, rl.WHITE)

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

    if script.is_initialised {
        simp.state_destroy(&script.state)
    }

    rl.CloseWindow()
}

init_script :: proc(script: ^Script, script_path: string) {
    script.path = script_path
}

reload_script :: proc(script: ^Script) {
    if script.is_initialised {
        simp.state_destroy(&script.state)

        script.state = simp.State{}
    }

    new_time, err := os.last_write_time_by_name(script.path)
    if err == nil {
        script.last_modified = new_time
    }

    simp.state_init(&script.state)
    script.is_initialised = true

    simp.bind_native_proc(&script.state, "set_colour", fn_set_colour)
    simp.bind_variable(&script.state, "message", &example_string)

    file_data, read_err := os.read_entire_file(script.path, context.temp_allocator)
    if read_err == nil {
        simp.state_load_source(&script.state, string(file_data), script.path)
        fmt.printfln("Successfully loaded mod: %s", script.path)
    } else {
        fmt.printfln("Failed to read mod file: %s", script.path)
    }
}

poll_script :: proc(script: ^Script) {
    current_time, err := os.last_write_time_by_name(script.path)

    if err == nil && current_time != script.last_modified {
        fmt.printfln("\nReloading: %s", script.path)
        reload_script(script)
    }
}
