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

@(private = "package")
default_log_proc :: proc(level: Log_Level, message: string, line: int = -1) {
    level_prefix := ""
    #partial switch level {
    case .Info:
        level_prefix = "[INFO]  "

    case .Warning:
        level_prefix = "[WARN]  "

    case .Error:
        level_prefix = "[ERROR] "

    case .Fatal:
        level_prefix = "[FATAL] "
    }

    if level == .None {
        fmt.println(message)
        return
    }

    if line >= 0 {
        fmt.printfln("%s -> (Line %d): %s", level_prefix, line, message)
    } else {
        fmt.printfln("%s -> %s", level_prefix, message)
    }
}
