// pure-cluster/self-host/parser.zk
// Flat AST Parser implementation for self-hosted Cluster compiler

import ast
import lexer

cpp_inject "using namespace ast;"
cpp_inject "using namespace lexer;"

cpp_inject "int64 parse_logical(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"
cpp_inject "int64 parse_comparison(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"
cpp_inject "int64 parse_expr(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"
cpp_inject "int64 parse_term(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"
cpp_inject "int64 parse_primary(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"
cpp_inject "int64 parse_block(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"
cpp_inject "int64 parse_stmt(int64& cursor, std::vector<ast::Token>& tokens, std::vector<ast::ASTNode>& nodes);"

fn make_node(&nodes: vector[ASTNode], kind: string, name: string, op: string, val_int: int, left_id: int, right_id: int) -> int:
    id := list_size(nodes)
    node := ASTNode(id=id, kind=kind, name=name, op=op, val_int=val_int, left_id=left_id, right_id=right_id)
    list_push(nodes, node)
    return id

fn peek(cursor: int, &tokens: vector[Token]) -> Token:
    size := list_size(tokens)
    if cursor >= size:
        return Token(kind="EOF", value="", line=0, column=0)
    return tokens[cursor + 0]

fn advance(&cursor: int, &tokens: vector[Token]) -> Token:
    size := list_size(tokens)
    if cursor >= size:
        return Token(kind="EOF", value="", line=0, column=0)
    tok := tokens[cursor + 0]
    cursor += 1
    return tok

fn match_token(&cursor: int, &tokens: vector[Token], kind: string, val: string) -> bool:
    tok := peek(cursor, tokens)
    if tok.kind == kind:
        if val == "" or tok.value == val:
            return true
    return false

fn consume(&cursor: int, &tokens: vector[Token], kind: string, val: string) -> Token:
    tok := peek(cursor, tokens)
    if tok.kind == kind:
        if val == "" or tok.value == val:
            cursor += 1
            return tok
    prev_tok := Token(kind="", value="", line=0, column=0)
    if cursor > 0:
        prev_tok = tokens[cursor - 1]
    put "Debug: Prev token was " + prev_tok.kind + " '" + prev_tok.value + "' at line " + to_text(prev_tok.line)
    put "Error: Expected token " + kind + " '" + val + "' but got " + tok.kind + " '" + tok.value + "' at line " + to_text(tok.line)
    exit_code(1)
    return tok

fn parse_primary(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    tok := peek(cursor, tokens)
    if tok.kind == "SYMBOL" and tok.value == "-":
        next_cursor := cursor + 1
        next_tok := peek(next_cursor, tokens)
        if next_tok.kind == "NUMBER":
            advance(cursor, tokens)
            advance(cursor, tokens)
            neg_val: string := "-" + next_tok.value
            return make_node(nodes, "LITERAL", neg_val, "", 0, -1, -1)
            
    if tok.kind == "KEYWORD" and tok.value == "not":
        advance(cursor, tokens)
        val_id := parse_primary(cursor, tokens, nodes)
        return make_node(nodes, "UNARY", "", "not", 0, val_id, -1)
            
    if tok.kind == "NUMBER":
        advance(cursor, tokens)
        return make_node(nodes, "LITERAL", tok.value, "", 0, -1, -1) // 0 -> int
    elif tok.kind == "STRING":
        advance(cursor, tokens)
        return make_node(nodes, "LITERAL", tok.value, "", 1, -1, -1) // 1 -> string
    elif tok.kind == "IDENTIFIER":
        advance(cursor, tokens)
        next_tok := peek(cursor, tokens)
        if next_tok.kind == "SYMBOL" and next_tok.value == "::":
            advance(cursor, tokens)
            fn_tok := consume(cursor, tokens, "IDENTIFIER", "")
            tok = fn_tok
            next_tok = peek(cursor, tokens)
        if next_tok.kind == "SYMBOL" and next_tok.value == "(":
            advance(cursor, tokens)
            first_arg := -1
            last_arg := -1
            if not match_token(cursor, tokens, "SYMBOL", ")"):
                while true:
                    is_kw_arg := false
                    next_cursor := cursor + 1
                    if peek(cursor, tokens).kind == "IDENTIFIER":
                        if match_token(next_cursor, tokens, "SYMBOL", "="):
                            is_kw_arg = true
                            
                    arg_node := -1
                    if is_kw_arg:
                        name_tok := advance(cursor, tokens)
                        advance(cursor, tokens)
                        arg_val_id := parse_logical(cursor, tokens, nodes)
                        arg_node = make_node(nodes, "ARG", name_tok.value, "", 0, arg_val_id, -1)
                    else:
                        arg_val_id := parse_logical(cursor, tokens, nodes)
                        arg_node = make_node(nodes, "ARG", "", "", 0, arg_val_id, -1)
                    if first_arg == -1:
                        first_arg = arg_node
                    else:
                        prev_arg := nodes[last_arg + 0]
                        prev_arg.right_id = arg_node
                        nodes[last_arg + 0] = prev_arg
                    last_arg = arg_node
                    
                    if match_token(cursor, tokens, "SYMBOL", ","):
                        advance(cursor, tokens)
                    else:
                        break
            consume(cursor, tokens, "SYMBOL", ")")
            obj_node := make_node(nodes, "CALL", tok.value, "", 0, first_arg, -1)
            while match_token(cursor, tokens, "SYMBOL", ".") or match_token(cursor, tokens, "SYMBOL", "["):
                if match_token(cursor, tokens, "SYMBOL", "."):
                    advance(cursor, tokens)
                    member_tok := consume(cursor, tokens, "IDENTIFIER", "")
                    obj_node = make_node(nodes, "MEMBER", member_tok.value, "", 0, obj_node, -1)
                else:
                    advance(cursor, tokens)
                    idx_id := parse_logical(cursor, tokens, nodes)
                    consume(cursor, tokens, "SYMBOL", "]")
                    obj_node = make_node(nodes, "INDEX", "", "", 0, obj_node, idx_id)
            return obj_node
        
        # Check for type-parameterized call: name[Type](args) e.g. vector[Token]()
        if next_tok.kind == "SYMBOL" and next_tok.value == "[":
            # Look ahead past the brackets to see if () follows
            save_cursor := cursor
            advance(cursor, tokens)  // skip [
            # Skip tokens until we find ]
            bracket_depth := 1
            inner_type_str: string := ""
            while bracket_depth > 0:
                bt := peek(cursor, tokens)
                if bracket_depth == 1 and inner_type_str == "":
                    inner_type_str = bt.value
                if bt.value == "[":
                    bracket_depth += 1
                elif bt.value == "]":
                    bracket_depth -= 1
                advance(cursor, tokens)
            # Now check if ( follows
            after_bracket := peek(cursor, tokens)
            if after_bracket.kind == "SYMBOL" and after_bracket.value == "(":
                # This is a type-parameterized call like vector[Token]()
                advance(cursor, tokens)  // skip (
                first_arg := -1
                last_arg := -1
                if not match_token(cursor, tokens, "SYMBOL", ")"):
                    while true:
                        is_kw_arg := false
                        next_cursor := cursor + 1
                        if peek(cursor, tokens).kind == "IDENTIFIER":
                            if match_token(next_cursor, tokens, "SYMBOL", "="):
                                is_kw_arg = true
                        arg_node := -1
                        if is_kw_arg:
                            name_tok := advance(cursor, tokens)
                            advance(cursor, tokens)
                            arg_val_id := parse_logical(cursor, tokens, nodes)
                            arg_node = make_node(nodes, "ARG", name_tok.value, "", 0, arg_val_id, -1)
                        else:
                            arg_val_id := parse_logical(cursor, tokens, nodes)
                            arg_node = make_node(nodes, "ARG", "", "", 0, arg_val_id, -1)
                        if first_arg == -1:
                            first_arg = arg_node
                        else:
                            prev_arg := nodes[last_arg + 0]
                            prev_arg.right_id = arg_node
                            nodes[last_arg + 0] = prev_arg
                        last_arg = arg_node
                        if match_token(cursor, tokens, "SYMBOL", ","):
                            advance(cursor, tokens)
                        else:
                            break
                consume(cursor, tokens, "SYMBOL", ")")
                return make_node(nodes, "CALL", tok.value, inner_type_str, 0, first_arg, -1)
            else:
                # Not a type-parameterized call, restore cursor
                cursor = save_cursor

        obj_node := make_node(nodes, "VAR", tok.value, "", 0, -1, -1)
        while match_token(cursor, tokens, "SYMBOL", ".") or match_token(cursor, tokens, "SYMBOL", "["):
            if match_token(cursor, tokens, "SYMBOL", "."):
                advance(cursor, tokens)
                member_tok := consume(cursor, tokens, "IDENTIFIER", "")
                obj_node = make_node(nodes, "MEMBER", member_tok.value, "", 0, obj_node, -1)
            else:
                advance(cursor, tokens)
                idx_id := parse_logical(cursor, tokens, nodes)
                consume(cursor, tokens, "SYMBOL", "]")
                obj_node = make_node(nodes, "INDEX", "", "", 0, obj_node, idx_id)
        return obj_node
    
    advance(cursor, tokens)
    return -1

fn parse_term(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    left := parse_primary(cursor, tokens, nodes)
    while match_token(cursor, tokens, "SYMBOL", "*") or match_token(cursor, tokens, "SYMBOL", "/"):
        op := advance(cursor, tokens).value
        right := parse_primary(cursor, tokens, nodes)
        left = make_node(nodes, "BINARY", "", op, 0, left, right)
    return left

fn parse_expr(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    left := parse_term(cursor, tokens, nodes)
    while match_token(cursor, tokens, "SYMBOL", "+") or match_token(cursor, tokens, "SYMBOL", "-"):
        op := advance(cursor, tokens).value
        right := parse_term(cursor, tokens, nodes)
        left = make_node(nodes, "BINARY", "", op, 0, left, right)
    return left

fn parse_comparison(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    left := parse_expr(cursor, tokens, nodes)
    while match_token(cursor, tokens, "SYMBOL", "==") or match_token(cursor, tokens, "SYMBOL", "!=") or match_token(cursor, tokens, "SYMBOL", "<") or match_token(cursor, tokens, "SYMBOL", ">") or match_token(cursor, tokens, "SYMBOL", ">=") or match_token(cursor, tokens, "SYMBOL", "<="):
        op := advance(cursor, tokens).value
        right := parse_expr(cursor, tokens, nodes)
        left = make_node(nodes, "BINARY", "", op, 0, left, right)
    return left

fn parse_logical(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    left := parse_comparison(cursor, tokens, nodes)
    while match_token(cursor, tokens, "KEYWORD", "or") or match_token(cursor, tokens, "KEYWORD", "and"):
        op := advance(cursor, tokens).value
        right := parse_comparison(cursor, tokens, nodes)
        left = make_node(nodes, "BINARY", "", op, 0, left, right)
    return left

fn parse_elif_chain(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    advance(cursor, tokens)
    cond_id := parse_logical(cursor, tokens, nodes)
    then_block := parse_block(cursor, tokens, nodes)
    
    else_block := -1
    next_tok := peek(cursor, tokens)
    if next_tok.kind == "KEYWORD" and next_tok.value == "elif":
        else_block = parse_elif_chain(cursor, tokens, nodes)
    elif next_tok.kind == "KEYWORD" and next_tok.value == "else":
        advance(cursor, tokens)
        else_block = parse_block(cursor, tokens, nodes)
        
    return make_node(nodes, "IF", "", "", else_block, cond_id, then_block)

fn parse_block(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    consume(cursor, tokens, "SYMBOL", ":")
    
    first_stmt := -1
    last_block := -1
    
    while true:
        tok := peek(cursor, tokens)
        is_fn := false
        is_model := false
        is_elif := false
        is_else := false
        is_end := false
        if tok.kind == "KEYWORD":
            if tok.value == "fn":
                is_fn = true
            elif tok.value == "model":
                is_model = true
            elif tok.value == "elif":
                is_elif = true
            elif tok.value == "else":
                is_else = true
            elif tok.value == "end":
                is_end = true
                
        if tok.kind == "EOF" or is_fn or is_model or is_elif or is_else or is_end:
            break
            
        stmt := parse_stmt(cursor, tokens, nodes)
        if stmt != -1:
            block_id := make_node(nodes, "BLOCK", "", "", 0, stmt, -1)
            if first_stmt == -1:
                first_stmt = block_id
            else:
                prev_block := nodes[last_block + 0]
                prev_block.right_id = block_id
                nodes[last_block + 0] = prev_block
                
            last_block = block_id
            
    if match_token(cursor, tokens, "KEYWORD", "end"):
        advance(cursor, tokens)
        
    return first_stmt

fn parse_stmt(&cursor: int, &tokens: vector[Token], &nodes: vector[ASTNode]) -> int:
    tok := peek(cursor, tokens)
    if tok.kind == "KEYWORD" and tok.value == "put":
        advance(cursor, tokens)
        expr_id := parse_logical(cursor, tokens, nodes)
        return make_node(nodes, "PUT", "", "", 0, expr_id, -1)
    elif tok.kind == "KEYWORD" and tok.value == "return":
        advance(cursor, tokens)
        expr_id := -1
        if peek(cursor, tokens).kind != "EOF":
            next_tok := peek(cursor, tokens)
            is_boundary := false
            if next_tok.kind == "KEYWORD":
                if next_tok.value == "end" or next_tok.value == "elif" or next_tok.value == "else" or next_tok.value == "fn" or next_tok.value == "model":
                    is_boundary = true
            if not is_boundary:
                expr_id = parse_logical(cursor, tokens, nodes)
        return make_node(nodes, "RETURN", "", "", 0, expr_id, -1)
    elif tok.kind == "KEYWORD" and tok.value == "break":
        advance(cursor, tokens)
        return make_node(nodes, "BREAK", "", "", 0, -1, -1)
    elif tok.kind == "KEYWORD" and tok.value == "continue":
        advance(cursor, tokens)
        return make_node(nodes, "CONTINUE", "", "", 0, -1, -1)
    elif tok.kind == "KEYWORD" and tok.value == "model":
        advance(cursor, tokens)
        model_name := consume(cursor, tokens, "IDENTIFIER", "").value
        consume(cursor, tokens, "SYMBOL", ":")
        
        first_field := -1
        last_field := -1
        
        while true:
            next_tok := peek(cursor, tokens)
            if next_tok.kind == "EOF" or next_tok.kind == "KEYWORD":
                break
                
            field_name := consume(cursor, tokens, "IDENTIFIER", "").value
            consume(cursor, tokens, "SYMBOL", ":")
            field_type := consume(cursor, tokens, "IDENTIFIER", "").value
            
            field_id := make_node(nodes, "FIELD", field_name, field_type, 0, -1, -1)
            if first_field == -1:
                first_field = field_id
            else:
                prev_field := nodes[last_field + 0]
                prev_field.right_id = field_id
                nodes[last_field + 0] = prev_field
                
            last_field = field_id
            
        if match_token(cursor, tokens, "KEYWORD", "end"):
            advance(cursor, tokens)
            
        return make_node(nodes, "MODEL", model_name, "", 0, -1, first_field)
    elif tok.kind == "KEYWORD" and tok.value == "if":
        advance(cursor, tokens)
        cond_id := parse_logical(cursor, tokens, nodes)
        then_block := parse_block(cursor, tokens, nodes)
        
        else_block := -1
        next_tok := peek(cursor, tokens)
        if next_tok.kind == "KEYWORD" and next_tok.value == "elif":
            else_block = parse_elif_chain(cursor, tokens, nodes)
        elif next_tok.kind == "KEYWORD" and next_tok.value == "else":
            advance(cursor, tokens)
            else_block = parse_block(cursor, tokens, nodes)
            
        return make_node(nodes, "IF", "", "", else_block, cond_id, then_block)
    elif tok.kind == "KEYWORD" and tok.value == "while":
        advance(cursor, tokens)
        cond_id := parse_logical(cursor, tokens, nodes)
        body_block := parse_block(cursor, tokens, nodes)
        return make_node(nodes, "WHILE", "", "", 0, cond_id, body_block)
    elif tok.kind == "KEYWORD" and tok.value == "fn":
        advance(cursor, tokens)
        fn_name_tok := consume(cursor, tokens, "IDENTIFIER", "")
        consume(cursor, tokens, "SYMBOL", "(")
        
        first_param := -1
        last_param := -1
        while peek(cursor, tokens).value != ")":
            is_ref := 0
            if peek(cursor, tokens).value == "&":
                advance(cursor, tokens)
                is_ref = 1
            param_tok := consume(cursor, tokens, "IDENTIFIER", "")
            param_type: string := "int"
            if peek(cursor, tokens).value == ":":
                advance(cursor, tokens)
                type_tok := advance(cursor, tokens)
                param_type = type_tok.value
                if param_type == "vector":
                    if peek(cursor, tokens).value == "[":
                        advance(cursor, tokens)
                        inner_type := advance(cursor, tokens)
                        consume(cursor, tokens, "SYMBOL", "]")
                        param_type = "vector[" + inner_type.value + "]"
            param_id := make_node(nodes, "VAR", param_tok.value, param_type, is_ref, -1, -1)
            if first_param == -1:
                first_param = param_id
            else:
                prev_param := nodes[last_param + 0]
                prev_param.right_id = param_id
                nodes[last_param + 0] = prev_param
            last_param = param_id
            if peek(cursor, tokens).value == ",":
                advance(cursor, tokens)
        consume(cursor, tokens, "SYMBOL", ")")
        
        ret_type: string := "int"
        if peek(cursor, tokens).value == "-":
            advance(cursor, tokens)
            consume(cursor, tokens, "SYMBOL", ">")
            ret_type_tok := advance(cursor, tokens)
            ret_type = ret_type_tok.value
            if ret_type == "vector":
                if peek(cursor, tokens).value == "[":
                    advance(cursor, tokens)
                    inner_type := advance(cursor, tokens)
                    consume(cursor, tokens, "SYMBOL", "]")
                    
        body_block := parse_block(cursor, tokens, nodes)
        return make_node(nodes, "FN", fn_name_tok.value, ret_type, 0, first_param, body_block)
    elif tok.kind == "KEYWORD" and tok.value == "import":
        advance(cursor, tokens)
        mod_name_tok := consume(cursor, tokens, "IDENTIFIER", "")
        mod_name := mod_name_tok.value
        next_tok := peek(cursor, tokens)
        while next_tok.kind == "SYMBOL" and next_tok.value == "-":
            advance(cursor, tokens)
            part_tok := consume(cursor, tokens, "IDENTIFIER", "")
            mod_name = mod_name + "-" + part_tok.value
            next_tok = peek(cursor, tokens)
        if next_tok.kind == "KEYWORD" and next_tok.value == "as":
            advance(cursor, tokens)
            alias_tok := consume(cursor, tokens, "IDENTIFIER", "")
            return make_node(nodes, "IMPORT", mod_name, alias_tok.value, 0, -1, -1)
        return make_node(nodes, "IMPORT", mod_name, "", 0, -1, -1)
    elif tok.kind == "IDENTIFIER" and tok.value == "cpp_inject":
        advance(cursor, tokens)
        consume(cursor, tokens, "STRING", "")
        return -1
    elif tok.kind == "IDENTIFIER":
        lhs := parse_primary(cursor, tokens, nodes)
        next_tok := peek(cursor, tokens)
        if next_tok.kind == "SYMBOL" and next_tok.value == ":":
            advance(cursor, tokens)
            advance(cursor, tokens)
            if peek(cursor, tokens).value == "[":
                advance(cursor, tokens)
                advance(cursor, tokens)
                consume(cursor, tokens, "SYMBOL", "]")
            next_tok = peek(cursor, tokens)
        is_assign := false
        aug_op: string := ""
        if next_tok.kind == "SYMBOL":
            if next_tok.value == "=" or next_tok.value == ":=":
                is_assign = true
            elif next_tok.value == "+=" or next_tok.value == "-=" or next_tok.value == "*=" or next_tok.value == "/=":
                is_assign = true
                aug_op = next_tok.value
        if is_assign:
            op_tok := advance(cursor, tokens)
            expr_id := parse_logical(cursor, tokens, nodes)
            
            lhs_node := nodes[lhs + 0]
            if aug_op != "":
                aug_char: string := ""
                if aug_op == "+=":
                    aug_char = "+"
                elif aug_op == "-=":
                    aug_char = "-"
                elif aug_op == "*=":
                    aug_char = "*"
                elif aug_op == "/=":
                    aug_char = "/"
                bin_id := make_node(nodes, "BINARY", "", aug_char, -1, lhs, expr_id)
                if lhs_node.kind == "MEMBER" or lhs_node.kind == "INDEX":
                    return make_node(nodes, "ASSIGN", "", "=", lhs, bin_id, -1)
                else:
                    return make_node(nodes, "ASSIGN", lhs_node.name, "=", -1, bin_id, -1)
            if lhs_node.kind == "MEMBER" or lhs_node.kind == "INDEX":
                return make_node(nodes, "ASSIGN", "", op_tok.value, lhs, expr_id, -1)
            else:
                return make_node(nodes, "ASSIGN", lhs_node.name, op_tok.value, -1, expr_id, -1)
        else:
            return lhs
        
    advance(cursor, tokens)
    return -1
