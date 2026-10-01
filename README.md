# yaml-parser

Like the name suggests, it is a YAML parser written in Odin. Why Odin? Cuz it's fun :)

I started this project because I wanted to work on something (even if it might end up being useless) that would teach me new things, and somehow it turned into a complex project that will be under continuous development until I actually finish it.

And no, I initially thought it was a great idea to match what the specification says in terms of how to implement it, but it was such a messy and complex architecture that I would never finish it in a reasonable amount of time. So, why not just build it my own way (even if it's not the "official" way and might lead to a bunch of bugs and stuff)?

Also, reading the YAML spec was... an experience. Did you know YAML technically supports JSON as a subset? Yeah, I'm not gonna bother with that. Full spec compliance is completely out of scope, the spec is 70 pages of pure chaos and I will never use all of it anyway.

The lexer handles identifiers, quoted strings, integers, floats, indentation, the markers that open and close a document, bullets, colons, and anchors and aliases. The parser is a recursive descent parser that walks every document of a stream and handles flat and nested block mappings, block sequences, and typed scalar values (string, integer, float) with proper error propagation. The emitter goes the other way and writes a parsed stream back out as YAML, which is what makes editing a value in a file possible.

I think that's pretty much it for the core of it. Sure, there are things I could add like flow sequences, but honestly this does what I need it to do. Might add more stuff later, might not. We'll see.

## Usage

```
yaml-parser                            parse and print the built-in sample
yaml-parser dump <file>                parse <file> and print the whole tree
yaml-parser get <file> <key.path>      print the value found at <key.path>
yaml-parser get <file> <key.path> -t   print the type of that value instead
yaml-parser set <file> <key.path> <value>  replace the value at <key.path>
yaml-parser add <file> <key.path> <value>  add a new key at <key.path>
yaml-parser get <file> <key.path> --doc 1  work on the second document
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

## More than one document in a file

A file can hold a stream of documents, each one opened by a `---` of its own and closed either by the marker opening the next one or by a `...`:

```yaml
---
name: production
replicas: 3
---
name: staging
replicas: 1
...
```

`dump` prints every document of the stream, with a blank line telling them apart, and `get`, `set` and `add` work on the first one unless `--doc <n>` picks another, where the first document is 0:

```sh
$ yaml-parser dump envs.yaml
name:
  production
replicas:
  3

name:
  staging
replicas:
  1
$ yaml-parser get envs.yaml name --doc 1
staging
$ yaml-parser set envs.yaml replicas 4 --doc 0
4
```

An anchor name belongs to the document that gave it, so the same name can show up again in the next one, and an alias cannot reach across the marker into the document above it.

`set` and `add` write the whole stream back out, so editing one document keeps the ones behind it in the file instead of dropping them.

`set` and `add` edit the file instead of just reading from it:

```sh
$ yaml-parser set config.yaml version 2.6
2.6
$ yaml-parser add config.yaml parent_key.new_child hello
hello
$ yaml-parser add config.yaml parent_key.another.nested_leaf 42
42
$ yaml-parser set config.yaml sequence_key.1 item9
item9
$ yaml-parser add config.yaml sequence_key.0 first
first
$ yaml-parser add config.yaml sequence_key item4
item4
$ yaml-parser set config.yaml name next-version --dry-run
---
name: next-version
...
```

`add` makes the mappings the path needs on its way down, and complains if the key is already there, while `set` only replaces what is already in the file. The value is typed the way the parser would type it, so `1.5` comes back as a float, `true` as a boolean, and anything with a space in it gets quoted for you. There is no way to ask for a string, so `42` is always the integer 42.

A numeric path segment edits a list, so `set config.yaml sequence_key.1 item9` replaces the second item and `add config.yaml sequence_key.0 first` puts a new item in front of it. Adding at the length of the list appends to it, and adding to a key that is a list without an index appends as well, which is what the last example above does. Only items that are already in the list can be set, so an index past the end is an error.

The catch is that the document gets written back out from the parsed tree, so comments, blank lines, quote style, and the exact spacing of the original are gone. That is the price of not keeping the source around, and `--dry-run` is there so you can see the result before it lands. The parser only reads lists of plain values for now, so a list of lists or a list of mappings cannot be written yet, even though the editing side is ready for it.

A key written twice in the same mapping is a parse error instead of a quiet pick between the two, because a lookup would otherwise hand back whichever one it happens to reach first:

```yaml
---
name: yaml-parser
name: next-version   # parser error, "name" is already defined above
```

The same key showing up in two documents of a stream, or in two items of a list, is a different mapping every time, so that stays fine.

## Anchors and aliases

An anchor gives a value a name, and an alias reads that value back, so a block that shows up in several places only has to be written once:

```yaml
---
defaults: &defaults
	flag: true
	ratio: 2.5
production: *defaults
staging: *defaults
```

`get` walks right through an alias, so `yaml-parser get config.yaml staging.ratio` is `2.5`. An alias to a scalar works the same way, and so does one inside a sequence. Since the emitter knows which nodes go out more than once, `set` and `add` write anchors and aliases back out instead of spelling the same block out twice, so a file that shares values keeps sharing them after an edit. Editing a key an alias points at takes the alias apart, on the grounds that the edited value is no longer the value the anchor named.

An anchor name can only be used once, an alias has to name an anchor defined above it, and an alias cannot point at the node it lives in, which is why a tree here never holds itself:

```yaml
--- &root        # parser error, *root is a node that contains itself
name: yaml-parser
mirror: *root
```

Merge keys (`<<: *defaults`) are not supported and say so instead of quietly doing nothing.

Hope you find this project at least a little bit useful and interesting :)))

Made with ❤️ by [@ilyeshdz](https://github.com/ilyeshdz)
