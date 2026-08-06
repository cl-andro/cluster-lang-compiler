// pure-cluster/self-host/main.zk
// Main compiler orchestrator for the self-hosted Cluster compiler

import ast
import lexer
import parser
import codegen
import cl-fs as fs

cpp_inject "using namespace ast;"
cpp_inject "using namespace lexer;"
cpp_inject "using namespace parser;"
cpp_inject "using namespace codegen;"
cpp_inject "#include <unistd.h>"
cpp_inject "auto c_str = [](const string& s) { return s.c_str(); };"

fn get_zkc_dir() -> string:
    return ""


fn pp_char_code(s: string, idx: int) -> int:
    return char_at(s, idx)

fn pp_is_blank_or_comment(line: string) -> bool:
    i := 0
    sz := text_length(line)
    while i < sz:
        ch := pp_char_code(line, i)
        if ch == 32 or ch == 9:
            i += 1
            continue
        if ch == 35:
            return true
        if ch == 47:
            if i + 1 < sz:
                if pp_char_code(line, i + 1) == 47:
                    return true
        return false
    return true

fn pp_indent_of(line: string) -> int:
    i := 0
    sz := text_length(line)
    while i < sz:
        if pp_char_code(line, i) != 32:
            break
        i += 1
    return i

fn pp_is_block_close(line: string, ind: int) -> bool:
    if ind + 3 < text_length(line):
        if pp_char_code(line, ind) == 101:
            c1 := pp_char_code(line, ind + 1)
            c2 := pp_char_code(line, ind + 2)
            c3 := pp_char_code(line, ind + 3)
            if c1 == 108 and c2 == 115 and c3 == 101:
                return true
            if c1 == 108 and c2 == 105 and c3 == 102:
                return true
    if ind + 2 < text_length(line):
        if pp_char_code(line, ind) == 101:
            if pp_char_code(line, ind + 1) == 110 and pp_char_code(line, ind + 2) == 100:
                return true
    return false

fn preprocess_indentation(source: string) -> string:
    out: string := ""
    stack := vector[int]()
    list_push(stack, 0)
    
    line_start := 0
    i := 0
    sz := text_length(source)
    while i <= sz:
        is_line_end := false
        if i == sz:
            is_line_end = true
        elif pp_char_code(source, i) == 10:
            is_line_end = true
        if is_line_end:
            line: string := ""
            line = str_substr(source, line_start, i - line_start)
            if not pp_is_blank_or_comment(line):
                ind := pp_indent_of(line)
                while list_size(stack) > 1:
                    top_idx := list_size(stack) - 1
                    if stack[top_idx + 0] <= ind:
                        break
                    out = out + "end\n"
                    list_pop(stack)
                if ind > stack[list_size(stack) - 1 + 0]:
                    list_push(stack, ind)
            out = out + line
            out = out + "\n"
            line_start = i + 1
        i += 1
    while list_size(stack) > 1:
        out = out + "end\n"
        list_pop(stack)
    return out

fn parse_file(file_path: string, &nodes: vector[ASTNode], &root_ids: vector[int]) -> int:
    source := fs::read(file_path)
    preprocessed := preprocess_indentation(source)
    lex := Lexer(source=preprocessed, cursor=0, line=1, column=1)
    tokens := tokenize(lex)
    t_size := list_size(tokens)
    
    cursor := 0
    while cursor < t_size - 1:
        tok := peek(cursor, tokens)
        if tok.kind == "EOF":
            break
        stmt_id := parse_stmt(cursor, tokens, nodes)
        if stmt_id != -1:
            stmt_node := nodes[stmt_id + 0]
            if stmt_node.kind == "IMPORT":
                imp_path := stmt_node.name + ".cl"
                parse_file(imp_path, nodes, root_ids)
            else:
                list_push(root_ids, stmt_id)
    return 0

fn get_output_path(file_path: string) -> string:
    i := text_length(file_path) - 1
    dot_idx := -1
    while i >= 0:
        ch := char_at(file_path, i)
        if ch == 46:
            dot_idx = i
            break
        if ch == 47:
            break
        i -= 1
    if dot_idx != -1:
        return str_substr(file_path, 0, dot_idx) + ".out"
    return file_path + ".out"

fn main():
    if list_size(sys_args) < 1:
        put "Usage: zkc <source_file.cl> [-o <output_file>]"
    else:
        file_path := sys_args[0 + 0]
        
        output_path: string := ""
        if list_size(sys_args) >= 3:
            if sys_args[1 + 0] == "-o":
                output_path = sys_args[2 + 0]
        
        if output_path == "":
            output_path = get_output_path(file_path)
            
        dot_idx := -1
        i := text_length(file_path) - 1
        while i >= 0:
            ch := char_at(file_path, i)
            if ch == 46:
                dot_idx = i
                break
            if ch == 47:
                break
            i -= 1
            
        base_path: string := file_path
        if dot_idx != -1:
            base_path = str_substr(file_path, 0, dot_idx)
            
        ll_path := base_path + ".ll"
        obj_path := base_path + ".o"
        
        nodes := vector[ASTNode]()
        root_ids := vector[int]()
        
        put "[ZKC] Parsing source files..."
        parse_file(file_path, nodes, root_ids)
        
        put "[ZKC] Generating LLVM IR..."
        llvm_ir := generate_program_ir(nodes, root_ids)
        
        put "[ZKC] Saving LLVM IR to: " + ll_path
        file_write(ll_path, llvm_ir)
        
        put "[ZKC] Compiling LLVM IR to native binary..."
        
        zkc_dir := get_zkc_dir()
        clang_cmd := zkc_dir + "cl-cc " + ll_path + " -no-pie -o " + output_path
        ret := system(c_str(clang_cmd))
        if ret != 0:
            clang_cmd = zkc_dir + "cl-cc -mllvm -opaque-pointers " + ll_path + " -no-pie -o " + output_path
            ret = system(c_str(clang_cmd))
            
        if ret != 0:
            clang_cmd = "cl-cc " + ll_path + " -no-pie -o " + output_path
            ret = system(c_str(clang_cmd))
        if ret != 0:
            clang_cmd = "cl-cc -mllvm -opaque-pointers " + ll_path + " -no-pie -o " + output_path
            ret = system(c_str(clang_cmd))
            
        if ret != 0:
            clang_cmd = "clang " + ll_path + " -no-pie -o " + output_path
            ret = system(c_str(clang_cmd))
        if ret != 0:
            clang_cmd = "clang -mllvm -opaque-pointers " + ll_path + " -no-pie -o " + output_path
            ret = system(c_str(clang_cmd))
            
        if ret != 0:
            put "[ZKC] clang compiler failed or not found. Trying llc + gcc..."
            llc_cmd := "llc -opaque-pointers " + ll_path + " -filetype=obj -o " + obj_path
            ret = system(c_str(llc_cmd))
            if ret != 0:
                llc_specific := "/media/alamgir-zk/debian13-hdd/alamgir-zk/Cluster-Family/cluster-lang/zk_modules/containers/rust/rootfs/opt/rust/lib/rustlib/x86_64-unknown-linux-gnu/bin/llc"
                llc_specific_cmd := llc_specific + " -opaque-pointers " + ll_path + " -filetype=obj -o " + obj_path
                ret = system(c_str(llc_specific_cmd))
                
            if ret == 0:
                gcc_cmd := "gcc -no-pie " + obj_path + " -o " + output_path
                ret = system(c_str(gcc_cmd))
                if ret == 0:
                    system(c_str("rm -f " + obj_path))
                    
        if ret == 0:
            // Clean up temporary .ll file unless requested otherwise
            system(c_str("rm -f " + ll_path))
            put "[ZKC] Success! Standalone executable generated at: " + output_path
        else:
            put "[ZKC] Error: Failed to compile LLVM IR to binary. LLVM IR saved at: " + ll_path
            exit_code(1)


