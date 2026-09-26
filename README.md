# yaml-parser

Like the name suggests, it is a YAML parser written in Odin. Why Odin? Cuz it's fun :)

I started this project because I wanted to work on something (even if it might end up being useless) that would teach me new things, and somehow it turned into a complex project that will be under continuous development until I actually finish it.

And no, I initially thought it was a great idea to match what the specification says in terms of how to implement it, but it was such a messy and complex architecture that I would never finish it in a reasonable amount of time. So, why not just build it my own way (even if it's not the "official" way and might lead to a bunch of bugs and stuff)?

Also, reading the YAML spec was... an experience. Did you know YAML technically supports JSON as a subset? Yeah, I'm not gonna bother with that. Full spec compliance is completely out of scope, the spec is 70 pages of pure chaos and I will never use all of it anyway.

The lexer handles identifiers, quoted strings, integers, floats, indentation, stream markers, bullets, and colons. The parser is a recursive descent parser that handles flat and nested block mappings, block sequences, and typed scalar values (string, integer, float) with proper error propagation. The emitter goes the other way and writes a parsed document back out as YAML, which is what makes editing a value in a file possible.

I think that's pretty much it for the core of it. Sure, there are things I could add like flow sequences or anchors, but honestly this does what I need it to do. Might add more stuff later, might not. We'll see.

## Usage

```
yaml-parser                            parse and print the built-in sample
yaml-parser dump <file>                parse <file> and print the whole tree
yaml-parser get <file> <key.path>      print the value found at <key.path>
yaml-parser get <file> <key.path> -t   print the type of that value instead
yaml-parser set <file> <key.path> <value>  replace the value at <key.path>
yaml-parser add <file> <key.path> <value>  add a new key at <key.path>
yaml-parser help                       print the usage text
```

Key paths are dot separated, and a numeric segment indexes a sequence:

```sh
$ yaml-parser get config.yaml name
yaml-parser
$ yaml-parser get config.yaml parent_key.child_key.ratio
2.5
$ yaml-parser get config.yaml sequence_key.1
item2
$ yaml-parser get config.yaml version -t
float
$ VERSION=$(yaml-parser get config.yaml version)
```

If the key path points at a mapping or a sequence, the whole subtree is printed instead of a single value. Everything the parser cannot resolve (missing key, bad index, path going into a scalar) goes to stderr and exits with 3, a broken file exits with 1, a wrong command exits with 2, and a file that cannot be written exits with 4.

`set` and `add` edit the file instead of just reading from it:

```sh
$ yaml-parser set config.yaml version 2.6
2.6
$ yaml-parser add config.yaml parent_key.new_child hello
hello
$ yaml-parser add config.yaml parent_key.another.nested_leaf 42
42
$ yaml-parser set config.yaml name next-version --dry-run
---
name: next-version
...
```

`add` makes the mappings the path needs on its way down, and complains if the key is already there, while `set` only replaces what is already in the file. The value is typed the way the parser would type it, so `1.5` comes back as a float, `true` as a boolean, and anything with a space in it gets quoted for you.

The catch is that the document gets written back out from the parsed tree, so comments, blank lines, quote style, and the exact spacing of the original are gone, and a string that looks like a number will read back as a number unless you quote it yourself. That is the price of not keeping the source around, and `--dry-run` is there so you can see the result before it lands. Keys inside a sequence, like `sequence_key.0`, cannot be edited yet, only mapping keys.

Hope you find this project at least a little bit useful and interesting :)))

Made with ❤️ by [@ilyeshdz](https://github.com/ilyeshdz)
