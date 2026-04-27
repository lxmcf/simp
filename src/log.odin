package simp

import "core:fmt"

Log_Proc :: #type proc(level: Log_Level, message: string, line: int = -1)

Log_Level :: distinct enum u8 {
    None,
    Info,
    Warning,
    Error,
    Fatal,
}

@(private)
default_log_proc :: proc(level: Log_Level, message: string, line: int = -1) {
    location: string
    defer if len(location) > 0 {
        delete(location)
    }

    if level != .Info && level != .None {
        if line >= 0 {
            location = fmt.aprintf("(Line %d):", line)
        }
    }

    switch level {
    case .None:
        fmt.println(message)

    case .Info:
        fmt.printfln("[INFO]  -> %s", message)

    case .Warning:
        fmt.printfln("[WARN]  -> %s %s", location, message)

    case .Error:
        fmt.eprintfln("[ERROR] -> %s %s", location, message)

    case .Fatal:
        fmt.eprintfln("[FATAL] -> %s %s", location, message)
    }
}
