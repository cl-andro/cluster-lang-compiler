// pure-cluster/self-host/ast.zk
// AST Nodes and Token structure definitions for the self-hosted compiler

model Token:
    kind: string       // "KEYWORD", "IDENTIFIER", "NUMBER", "STRING", "SYMBOL", "EOF"
    value: string
    line: int
    column: int

model ASTNode:
    id: int
    kind: string       // "PROGRAM", "FUNCTION", "BLOCK", "ASSIGN", "CALL", "BINARY", "LITERAL", "VAR", "RETURN", "PUT"
    name: string
    op: string
    val_int: int
    left_id: int       // Index to left child in AST vector (-1 if none)
    right_id: int      // Index to right child in AST vector (-1 if none)
