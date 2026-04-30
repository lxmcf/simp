<!-- Using lua for syntax highlighting as it mostly matches the keywords -->

# Documentation

### Types

---

SIMP has several default user facing types as listed below...

```lua
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

```lua
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

```lua
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

```lua
let foo = "Hello simp"
const bar = "Hello simp"
```

Variables defined by `let` are always mutable and those defined by `const` are immutable, a constant will work similar to a JavaScript constant where you can declare and array or object as const; however you can still modify the stored data as shown:

```lua
const arr = array { 7, 0, 0, 8, 5 }
array[0] = 8

const obj = object { my_name_is = "what?" }
obj.my_name_is = "who?"
```

### Type Casting

---

SIMP is not a strictly typed language, this means all comparisons are truthy and values can have their type changed simply by re-assigning the variable:

```lua
let var = "Hello simp"
var = true
```

However, sometimes you will want to ensure a variable is off a specific type, this is where casting comes into play:

```lua
let var_integer = "1337"::int;
let var_string = 3.14::string;
```

Type casting also has some powerful functionality when it comes to the `type` type and complex types like arrays and objects.

If you cast anything to a type, it will return it's type as a value an casting a complex type to a string will return a JSON formatted string:

```lua
let my_type = type

my_type = 1::type
put "I am an '" + my_type + "'\n"

my_type = "When in doubt, use brute force."::type
put "I am now a '" + my_type + "'\n"

const arr = array { "F", "E", "E", "F" }
put arr::string + "\n"

const obj = object {
    sanity = "lol",
    are_you_actually_reading = false
}

put obj::string + "\n"
```
