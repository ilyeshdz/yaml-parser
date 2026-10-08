# yaml-parser

**yaml** is a YAML library for Odin, written from scratch. It reads block mappings, block and flow sequences, anchors and aliases, and typed scalars (string, integer, float, boolean, null, timestamp), and it looks documents up and edits them by key path.

## Use

Import the `yaml` package:

```odin
import yaml "path/to/yaml-parser/yaml"
```

Parse a file and read a value. Key paths are dot separated, and a numeric segment indexes a sequence:

```odin
doc, _, err := yaml.load_file("config.yaml", context.allocator)
node, lerr := yaml.node_lookup(doc.documents[0], "parent.child.ratio")
```

Edit a document and write it back out:

```odin
value := yaml.scalar_node("2.6", false)
edited, _ := yaml.node_edit(root, "parent.child", value, false)

docs := make([dynamic]^yaml.Node, context.allocator)
append(&docs, edited)
out := yaml.render_stream(docs, source, context.allocator)
```

## Layout

The library is split by responsibility, with `yaml` as the facade:

- `yaml.odin` — parse, load, render, scalar typing
- `query.odin` — key-path lookup
- `edit.odin` — key-path editing
- `lexer/` — identifiers, strings, numbers, timestamps, indentation
- `parser/` — recursive descent over every document of a stream
- `emitter/` — writes documents back out as YAML

## Check

```sh
odin build yaml -build-mode:obj
```

> Made with ❤️ by [ilyeshdz](https://github.com/ilyeshdz)
