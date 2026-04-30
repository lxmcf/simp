# SIMP

### Description...

---

SIMP is a general purpose, extendable and simple scripting language with no warranty, designed to be easy to learn and impliment into an already existing project to extend functionality or even operate as a simple standalone scripting option. SIMP is heavily inspired by languages such as BASIC and Lua; with enough JavaScript and SQL influence to make you feel uneasy.

SIMP started as a simple language with nothing but functions, variables and if statements for a game engine debug console but quickly grew to the mess I have today.

SIMP is designed to be as simple as possible, to the point there are 0 functions without manually loading the standard library, this being the case; here is an example of writing a 'print' function in SIMP...

```lua
function print (...) {
	foreach , arg in ... {
		if idx > 0 {
			put " "
		}

		put arg
	}

	put "\n"
}

print ("Hello Simp!")
```

### Implementation...

---

For now, SIMP only offers an Odin implementation; as shown in the `examples` directory, a C binding is in the works but not high priority for now.

### Documentation?

---

Documentation is for losers, just look at the examples and start slapping something together...

_More documentation is in the works to highlight everything the language offers but this is a toy scripting language and I do not take this seriously at all_
