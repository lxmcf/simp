<!-- Using lua for syntax highlighting as it mostly matches the keywords -->

# Documentation

SIMP is a very small but somewhat powerful language out of the box, by default there is not standard library (However there is one), this documentation will not cover this library and focus purely on the language.

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
    putln "Hello SIMP!"
}

function sum (...) {
    let total = 0.0

    foreach (_, number in ...) {
        if (number::type not in (int, float)) then continue

        total += number
    }

    return total
}
```

There are a lot of core concepts shown off in the `sum` user function here, however we will cover these later on.

### Variables

---

SIMP has 2 kinds of variables, constants and mutables; however these are not limited to just being used inside your SIMP scripts as you can also bind a variety of variable types from your Odin program.

```lua
let foo = "Hello simp"
const bar = "Hello simp"
```

Variables defined by `let` are always mutable and those defined by `const` are immutable, a constant will work similar to a JavaScript constant where you can declare and array or object as const; however you can still modify the stored data as shown:

```lua
--- Arrays ---
const arr = array { 7, 0, 0, 8, 5 }
array[0] = 8

--- Objects ---
const obj = object { my_name_is = "what?" }
obj.my_name_is = "who?"
```

### Comments

---

SIMP supports 2 forms of comments, single line and multi line. Single line is defined by the using `//` however multi line is done using `---`, this multi line format is a psuedo way to make it easier to potentially port over lua code given the language similarities and is not final.

```lua
// This is a single line comment

---
    This is a multi
    line comment!
---
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
let var_integer = "1337"::int
let var_string = 3.14::string
```

Type casting also has some powerful functionality when it comes to the `type` type and complex types like arrays and objects.

If you cast anything to a type, it will return it's type as a value an casting a complex type to a string will return a JSON formatted string:

```lua
--- Simple type casting ---
let my_type = type

my_type = 1::type
putln "I am an '" + my_type

my_type = "When in doubt, use brute force."::type
putln "I am now a '" + my_type

--- JSON String casting ---
const arr = array { "F", "E", "E", "F" }
putln arr::string

const obj = object {
    sanity = "lol",
    are_you_actually_reading = false
}

putln obj::string
```

### Control Flow and Loops

---

SIMP supports standard most forms of control flow and loops, from the simple `if` statement to `foreach`, depending on the types; some loops may have different behaviour as shown for the `foreach` statement and strings...

```lua
let shall_i_pass = false

if shall_i_pass {
    putln "YOU SHALL PASS... SOMEHOW"
} else {
    putln "YOU SHALL NOT PASS"
}

--- Outputs numbers: 1, 2, 3, 4, 5
for i = 0 to 5 {
    putln i
}

-- Outputs numners: 0, 2, 4, 6, 8 ,10
for i = 0 to 10 step 2 {
    putln i
}

let arr = array { "how", "can", "we", "sleep" }
foreach idx, str in arr {
    putln "[" + idx + "]: " + str
}

let msg = "when the beds are burning"
foreach idx, char in msg {
    putln "[" + idx + "]: " + char
}
```
