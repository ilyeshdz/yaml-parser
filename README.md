# yaml-parser

Like the name suggests, it is a YAML parser written in Odin. Why Odin? Cuz it's fun :)

I started this project because I wanted to work on something (even if it might end up being useless) that would teach me new things, and somehow it turned into a complex project that will be under continuous development until I actually finish it.

And no, I initially thought it was a great idea to match what the specification says in terms of how to implement it, but it was such a messy and complex architecture that I would never finish it in a reasonable amount of time. So, why not just build it my own way (even if it's not the "official" way and might lead to a bunch of bugs and stuff)?

Also, reading the YAML spec was... an experience. Did you know YAML technically supports JSON as a subset? Yeah, I'm not gonna bother with that. Full spec compliance is completely out of scope, the spec is 70 pages of pure chaos and I will never use all of it anyway.

The lexer handles identifiers, quoted strings, integers, floats, indentation, stream markers, bullets, and colons. The parser is a recursive descent parser that handles flat and nested block mappings, block sequences, and typed scalar values (string, integer, float) with proper error propagation.

I think that's pretty much it for the core of it. Sure, there are things I could add like flow sequences or anchors, but honestly this does what I need it to do. Might add more stuff later, might not. We'll see.

Hope you find this project at least a little bit useful and interesting :)))

Made with ❤️ by [@ilyeshdz](https://github.com/ilyeshdz)
