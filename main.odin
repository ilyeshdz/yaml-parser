package main

import "core:fmt"
import "lexer"

main :: proc() {
    source := `schema: "my-custom-schema"
test: 10
test2: 3.14
    test3: test
    `

    my_lexer := lexer.lexer_init(source);

    for {
        tok := lexer.lexer_next_token(&my_lexer)
        if tok.kind == .Eof {
            break
        }
        fmt.println(tok)
    }
}
