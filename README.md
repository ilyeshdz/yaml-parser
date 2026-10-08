# yaml-parser

**yaml-parser** is a YAML parser written from scratch in Odin. It reads block mappings, block and flow sequences, anchors and aliases, and typed scalars (string, integer, float, boolean, null, timestamp), and it can query and edit files by key path.

## Build

This project is built with Odin:

```sh
odin build . -out:yaml-parser
```

## Usage

Key paths are dot separated, and a numeric segment indexes a sequence:

```sh
yaml-parser dump <file>                     # parse <file> and print the whole tree
yaml-parser get <file> <key.path>           # print the value at <key.path>
yaml-parser get <file> <key.path> -t        # print its type instead (--default <v> as fallback)
yaml-parser set <file> <key.path> <value>   # replace the value (--string to force a string)
yaml-parser add <file> <key.path> <value>   # add a new key
yaml-parser del <file> <key.path>           # delete the key
yaml-parser keys <file> [key.path]          # list the keys of a mapping
yaml-parser len <file> [key.path]           # count the entries of a mapping or sequence
```

`get`, `set`, `add` and `del` take `--doc <n>` to pick a document and `--dry-run` to preview an edit. Exit codes: 0 ok, 1 parse error, 2 wrong usage, 3 key path not found, 4 write error.

> Made with ❤️ by [ilyeshdz](https://github.com/ilyeshdz)
