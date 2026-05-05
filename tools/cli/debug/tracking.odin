package debug

import "core:fmt"
import "core:mem"

@(private)
track: mem.Tracking_Allocator

init_allocator :: proc() -> mem.Allocator {
    mem.tracking_allocator_init(&track, context.allocator)

    return mem.tracking_allocator(&track)
}

unload_allocator :: proc() {
    if len(track.allocation_map) > 0 {
        fmt.eprintfln("[DEBUG]: %v leaked allocations", len(track.allocation_map))

        for _, entry in track.allocation_map {
            fmt.eprintfln("\t%v leaked %v bytes", entry.location, entry.size)
        }
    }

    if len(track.bad_free_array) > 0 {
        fmt.eprintfln("[DEBUG]: %v bad frees", len(track.bad_free_array))

        for entry in track.bad_free_array {
            fmt.eprintfln("\t%v bad free", entry.location)
        }
    }

    mem.tracking_allocator_destroy(&track)
}
