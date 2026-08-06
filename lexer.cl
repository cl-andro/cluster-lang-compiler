// pure-cluster/self-host/lexer.zk
// Lexer implementation for the self-hosted Cluster compiler

import ast

cpp_inject "using namespace ast;"
cpp_inject "inline int64_t is_alpha_at(std::string s, int64_t idx) { if (idx < 0 || idx >= (int64_t)s.length()) return 0; int64_t c = static_cast<unsigned char>(s[idx]); return ((c>=65&&c<=90)||(c>=97&&c<=122)||c==95); }"
cpp_inject "inline int64_t is_digit_at(std::string s, int64_t idx) { if (idx < 0 || idx >= (int64_t)s.length()) return 0; int64_t c = static_cast<unsigned char>(s[idx]); return (c>=48&&c<=57); }"
cpp_inject "inline int64_t is_space_at(std::string s, int64_t idx) { if (idx < 0 || idx >= (int64_t)s.length()) return 0; int64_t c = static_cast<unsigned char>(s[idx]); return (c==32||c==9||c==11||c==12||c==13); }"
cpp_inject "inline std::string str_substr(std::string s, int64_t start, int64_t len) { if (start < 0) start = 0; if (start > (int64_t)s.length()) return std::string(\"\"); return s.substr(start, len); }"
cpp_inject "inline void exit_code(int64_t n) { exit((int)n); }"

fn is_alpha(s: string, idx: int) -> bool:
    return is_alpha_at(s, idx)

fn is_digit(s: string, idx: int) -> bool:
    return is_digit_at(s, idx)

fn is_alphanumeric(s: string, idx: int) -> bool:
    res := false
    if is_alpha(s, idx) or is_digit(s, idx):
        res = true
    return res

fn is_space(s: string, idx: int) -> bool:
    return is_space_at(s, idx)

fn get_char(s: string, idx: int) -> string:
    return str_substr(s, idx, 1)

model Lexer:
    source: string
    cursor: int
    line: int
    column: int

fn tokenize(&lex: Lexer) -> vector[Token]:
    tokens := vector[Token]()
    length := text_length(lex.source)
    
    while lex.cursor < length:
        ch := get_char(lex.source, lex.cursor)
        is_hash_comment := false
        if ch == "#":
            is_hash_comment = true
            
        is_slash_comment := false
        if ch == "/":
            next_ch := get_char(lex.source, lex.cursor + 1)
            if next_ch == "/":
                is_slash_comment = true
                
        if is_hash_comment or is_slash_comment:
            if is_hash_comment:
                lex.cursor += 1
                lex.column += 1
            else:
                lex.cursor += 2
                lex.column += 2
                
            is_comment_loop := true
            while is_comment_loop:
                if lex.cursor >= length:
                    is_comment_loop = false
                else:
                    comment_ch := get_char(lex.source, lex.cursor)
                    if comment_ch == "\n":
                        is_comment_loop = false
                    else:
                        lex.cursor += 1
                        lex.column += 1
            ch = get_char(lex.source, lex.cursor)
        
        if ch == "\n":
            lex.cursor += 1
            lex.line += 1
            lex.column = 1
        elif is_space(lex.source, lex.cursor):
            lex.cursor += 1
            lex.column += 1
        elif is_alpha(lex.source, lex.cursor):
            start := lex.cursor
            while lex.cursor < length and is_alphanumeric(lex.source, lex.cursor):
                lex.cursor += 1
                lex.column += 1
            
            val: string := ""
            val = str_substr(lex.source, start, lex.cursor - start)
            
            kind := "IDENTIFIER"
            if val == "fn" or val == "model" or val == "if" or val == "elif" or val == "else" or val == "while" or val == "for" or val == "in" or val == "break" or val == "continue" or val == "return" or val == "put" or val == "assert" or val == "unsafe" or val == "end" or val == "import" or val == "or" or val == "and" or val == "not" or val == "as" or val == "ptr" or val == "asm":
                kind = "KEYWORD"
                
            list_push(tokens, Token(kind=kind, value=val, line=lex.line, column=lex.column))
        elif is_digit(lex.source, lex.cursor):
            start := lex.cursor
            while lex.cursor < length and is_digit(lex.source, lex.cursor):
                lex.cursor += 1
                lex.column += 1
                
            val: string := ""
            val = str_substr(lex.source, start, lex.cursor - start)
            list_push(tokens, Token(kind="NUMBER", value=val, line=lex.line, column=lex.column))
        elif ch == "\"":
            start_col := lex.column
            lex.cursor += 1
            lex.column += 1
            start := lex.cursor
            
            while lex.cursor < length:
                curr_ch := get_char(lex.source, lex.cursor)
                if curr_ch == "\\":
                    lex.cursor += 2
                    lex.column += 2
                elif curr_ch == "\"":
                    break
                else:
                    lex.cursor += 1
                    lex.column += 1
                
            val: string := ""
            val = str_substr(lex.source, start, lex.cursor - start)
            lex.cursor += 1
            lex.column += 1
            
            list_push(tokens, Token(kind="STRING", value=val, line=lex.line, column=start_col))
        else:
            next_ch := get_char(lex.source, lex.cursor + 1)
            two_chars := ch + next_ch
            
            if two_chars == "==" or two_chars == "!=" or two_chars == "+=" or two_chars == "-=" or two_chars == "*=" or two_chars == "/=" or two_chars == "%=" or two_chars == ">=" or two_chars == "<=" or two_chars == "<<" or two_chars == ">>" or two_chars == ":=" or two_chars == "::":
                list_push(tokens, Token(kind="SYMBOL", value=two_chars, line=lex.line, column=lex.column))
                lex.cursor += 2
                lex.column += 2
            else:
                list_push(tokens, Token(kind="SYMBOL", value=ch, line=lex.line, column=lex.column))
                lex.cursor += 1
                lex.column += 1
                
    list_push(tokens, Token(kind="EOF", value="", line=lex.line, column=lex.column))
    return tokens
