#+build linux

// TODO: Move away from libc
// TODO: Use POSIX package, can't seem to get it working?

package main

import "core:c/libc"

enable_raw_mode :: proc() {
    libc.system("stty cbreak -echo")
}

disable_raw_mode :: proc() {
    libc.system("stty sane")
}
