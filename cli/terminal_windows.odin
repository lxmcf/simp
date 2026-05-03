#+build windows

// NOTE: This is clanker generated, idk windows man

package main

import "core:sys/windows"

_saved_input_mode: u32
_saved_output_mode: u32
_stdin_handle: windows.HANDLE
_stdout_handle: windows.HANDLE

enable_raw_mode :: proc() {
    _stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE)
    windows.GetConsoleMode(_stdin_handle, &_saved_input_mode)

    new_input_mode := _saved_input_mode
    new_input_mode &= ~(windows.ENABLE_PROCESSED_INPUT | windows.ENABLE_LINE_INPUT | windows.ENABLE_ECHO_INPUT)
    new_input_mode |= windows.ENABLE_VIRTUAL_TERMINAL_INPUT

    windows.SetConsoleMode(_stdin_handle, new_input_mode)

    _stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)

    windows.GetConsoleMode(_stdout_handle, &_saved_output_mode)
    windows.SetConsoleMode(_stdout_handle, _saved_output_mode | windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
}

disable_raw_mode :: proc() {
    windows.SetConsoleMode(_stdin_handle, _saved_input_mode)
    windows.SetConsoleMode(_stdout_handle, _saved_output_mode)
}
