# Documentation

### Types

---

SIMP has several default user facing types as listed below...

```md
<!-- Core Types -->

null
float
int
string
bool
object
array
type
```

However these types are only useful in standalone scripts, to allow SIMP to be used to extend an applications functinality, there are several more 'types' called 'bound types'

```md
<!-- Bound Types  -->

rawptr
^f64
^f32
^int
^i32
^string
^bool
```

These bound types directly map to some form of core type with the only exception being the `rawptr` as this is used purely for future C and Odin interop.

### Functions

---

SIMP has 2 forms of functions, native and user functions. A native function is a procedure written in odin and bound using 'bind_native_proc' where as a user function is defined in SIMP itself, here is an example of some user functions:

```simp
function say_hello () {
    put "Hello SIMP!\n"
}

function sum (...) {
    let total = 0.0

    foreach _, number in ... {
        if number::type != int && number::type != float {
            continue
        }

        total += number
    }

    return total
}
```

There are a lot of core concepts shown off in the `sum` user function here, however we will covers these later on.

### Variables

---

SIMP has 2 kinds of variables, constants and mutables; however these are not limited to just being used inside your SIMP scripts as you can also bind a variety of variable types from your Odin program.

```simp
let foo = "Hello simp"
const bar = "Hello simp"
```

Variables defined by `let` are always mutable and those defined by `const` are immutable, a constant will work similar to a JavaScript constant where you can declare and array or object as const; however you can still modify the stored data as shown:

```simp
const arr = array { 7, 0, 0, 8, 5 }
array[0] = 8
```
