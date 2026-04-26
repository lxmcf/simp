// TODO: Move away from libc

package main

import "core:c/libc"

enable_raw_mode :: proc() {
    libc.system("stty cbreak -echo")
}

disable_raw_mode :: proc() {
    libc.system("stty sane")
}
