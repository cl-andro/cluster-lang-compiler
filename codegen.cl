// pure-cluster/self-host/codegen.zk
// LLVM IR Generator implementation for self-hosted Cluster compiler

import ast

cpp_inject "using namespace ast;"
cpp_inject "int64_t char_at(std::string s, int64_t idx) { if (idx >= 0 && idx < s.length()) return static_cast<unsigned char>(s[idx]); return 0; }"
cpp_inject "inline std::string char_to_string(int64_t c) { return std::string(1, (char)c); }"
cpp_inject "inline std::string str_heap_copy(std::string s) { return s; }"
cpp_inject "inline void str_append(std::string &s, const std::string &t) { s += t; }"
cpp_inject "inline void print_err(std::string s) { std::cerr << s << std::endl; }"
cpp_inject "std::vector<std::string> global_user_fns;"
cpp_inject "void clear_global_user_fns() { global_user_fns.clear(); }"
cpp_inject "void add_global_user_fn(std::string name) { global_user_fns.push_back(name); }"
cpp_inject "bool has_global_user_fn(std::string name) { for (const auto &n : global_user_fns) { if (n == name) return true; } return false; }"

fn emit(&ir_output: string, line: string):
    str_append(ir_output, line)
    str_append(ir_output, "\n")

fn escape_llvm_string(s: string) -> string:
    res: string := ""
    i := 0
    sz := text_length(s)
    while i < sz:
        ch := char_at(s, i)
        if ch == 92:
            next_ch := 0
            if i + 1 < sz:
                next_ch = char_at(s, i + 1)
            if next_ch == 110:
                res = res + "\\0A"
                i += 1
            elif next_ch == 116:
                res = res + "\\09"
                i += 1
            elif next_ch == 34:
                res = res + "\\22"
                i += 1
            elif next_ch == 92:
                res = res + "\\5C"
                i += 1
            else:
                res = res + "\\5C"
        elif ch == 34:
            res = res + "\\22"
        elif ch == 10:
            res = res + "\\0A"
        else:
            res = res + char_to_string(ch)
        i += 1
    return res

fn register_user_fn(name: string):
    cpp_inject "add_global_user_fn(name);"
    
fn clear_user_fns():
    cpp_inject "clear_global_user_fns();"
    
fn is_user_fn(name: string) -> int:
    res := 0
    cpp_inject "res = has_global_user_fn(name) ? 1 : 0;"
    return res

fn get_llvm_string_len(s: string) -> int:
    len := 0
    i := 0
    sz := text_length(s)
    while i < sz:
        ch := char_at(s, i)
        if ch == 92:
            i += 1
        len += 1
        i += 1
    return len

fn has_var(&var_allocs: vector[string], name: string) -> bool:
    return vec_contains(var_allocs, name)

fn var_ref(name: string) -> string:
    if name == "sys_args":
        return "@" + name
    return "%" + name

fn get_raw_var_type(name: string, &var_allocs: vector[string], &var_types: vector[string]) -> string:
    i := 0
    sz := list_size(var_allocs)
    while i < sz:
        v_name := var_allocs[i + 0]
        if v_name == name:
            return var_types[i + 0]
        i += 1
    return ""

fn is_param_ref_int(name: string, &var_allocs: vector[string], &var_types: vector[string]) -> bool:
    raw_type := get_raw_var_type(name, var_allocs, var_types)
    if text_length(raw_type) > 10 and char_at(raw_type, 9) == 58:
        return true
    return false

fn var_struct_ref(name: string, &var_allocs: vector[string], &var_types: vector[string], &temp_counter: int, &ir_output: string) -> string:
    raw_type := get_raw_var_type(name, var_allocs, var_types)
    if text_length(raw_type) > 5 and char_at(raw_type, 5) == 58:
        temp_counter += 1
        reg := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + reg + " = load ptr, ptr " + var_ref(name) + ", align 8")
        return reg
    return var_ref(name)

fn is_model_type(&nodes: vector[ASTNode], type_name: string) -> bool:
    i := 0
    size := list_size(nodes)
    while i < size:
        n := nodes[i + 0]
        if n.kind == "MODEL" and n.name == type_name:
            return true
        i += 1
    return false

fn find_var_model_type(&nodes: vector[ASTNode], var_name: string) -> string:
    i := 0
    size := list_size(nodes)
    while i < size:
        n := nodes[i + 0]
        if n.kind == "ASSIGN" and n.name == var_name:
            expr_id := n.left_id
            expr_node := nodes[expr_id + 0]
            while expr_node.kind == "BLOCK":
                curr_block := expr_id
                last_expr_id := -1
                while curr_block != -1:
                    block_node := nodes[curr_block + 0]
                    last_expr_id = block_node.left_id
                    curr_block = block_node.right_id
                if last_expr_id != -1:
                    expr_id = last_expr_id
                    expr_node = nodes[expr_id + 0]
                else:
                    break
            
            if expr_node.kind == "VAR":
                return find_var_model_type(nodes, expr_node.name)
            elif expr_node.kind == "CALL":
                if is_model_type(nodes, expr_node.name):
                    return expr_node.name
                if expr_node.name == "vector" and expr_node.op != "":
                    return expr_node.op
                k := 0
                while k < size:
                    fn_node := nodes[k + 0]
                    if fn_node.kind == "FN" and fn_node.name == expr_node.name:
                        return fn_node.op
                    k += 1
            elif expr_node.kind == "INDEX":
                vec_var_node := nodes[expr_node.left_id + 0]
                return find_var_model_type(nodes, vec_var_node.name)
        elif n.kind == "FN":
            curr_param := n.left_id
            while curr_param != -1:
                param_node := nodes[curr_param + 0]
                if param_node.name == var_name:
                    if param_node.op == "vector":
                        return ""
                    if text_length(param_node.op) > 7 and char_at(param_node.op, 6) == 91:
                        if char_at(param_node.op, 7) == 115:
                            if param_node.op == "vector[string]":
                                return "string"
                        kk := 0
                        while kk < size:
                            m_node := nodes[kk + 0]
                            if m_node.kind == "MODEL":
                                expected := "vector[" + m_node.name + "]"
                                if param_node.op == expected:
                                    return m_node.name
                            kk += 1
                        return ""
                    return param_node.op
                curr_param = param_node.right_id
        i += 1
    return ""

fn find_field_index(&nodes: vector[ASTNode], model_name: string, field_name: string) -> int:
    model_id := -1
    i := 0
    size := list_size(nodes)
    while i < size:
        n := nodes[i + 0]
        if n.kind == "MODEL" and n.name == model_name:
            model_id = n.id
            break
        i += 1
        
    if model_id == -1:
        return -1
        
    model_node := nodes[model_id + 0]
    curr_field := model_node.right_id
    idx := 0
    while curr_field != -1:
        field_node := nodes[curr_field + 0]
        if field_node.name == field_name:
            return idx
        idx += 1
        curr_field = field_node.right_id
        
    return -1

fn model_byte_size(&nodes: vector[ASTNode], model_name: string) -> int:
    i := 0
    size := list_size(nodes)
    while i < size:
        n := nodes[i + 0]
        if n.kind == "MODEL" and n.name == model_name:
            total := 0
            curr_field := n.right_id
            while curr_field != -1:
                field_node := nodes[curr_field + 0]
                if field_node.op == "string":
                    total += 16
                elif field_node.op == "vector":
                    total += 24
                else:
                    total += 8
                curr_field = field_node.right_id
            return total
        i += 1
    return 0

fn get_node_type(&nodes: vector[ASTNode], &var_allocs: vector[string], &var_types: vector[string], node_id: int) -> string:
    if node_id == -1:
        return "int"
    node := nodes[node_id + 0]
    if node.kind == "LITERAL":
        if node.val_int == 1:
            return "string"
        return "int"
    elif node.kind == "VAR":
        if node.name == "sys_args":
            return "vector"
        i := 0
        sz := list_size(var_allocs)
        while i < sz:
            v_name := var_allocs[i + 0]
            if node.name == "cursor" or v_name == "cursor":
                print_err("DEBUG: get_node_type comparing '" + v_name + "' with '" + node.name + "' at index " + to_text(i))
            if v_name == node.name:
                raw_type := var_types[i + 0]
                if node.name == "cursor":
                    print_err("DEBUG: cursor matched at index " + to_text(i) + " raw_type = '" + raw_type + "'")
                if text_length(raw_type) > 5 and char_at(raw_type, 5) == 58:
                    if char_at(raw_type, 6) == 115:
                        return "string"
                    return "vector"
                if text_length(raw_type) > 10 and char_at(raw_type, 9) == 58:
                    return "int"
                return raw_type
            i += 1
        return "int"
    elif node.kind == "UNARY":
        if node.op == "&":
            return "ptr"
        if node.op == "*":
            return "int"
        return "int"
    elif node.kind == "BINARY":
        left_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
        right_type := get_node_type(nodes, var_allocs, var_types, node.right_id)
        is_str_concat := false
        if node.op == "+":
            if left_type == "string" or right_type == "string":
                is_str_concat = true
        if is_str_concat:
            return "string"
        return "int"
    elif node.kind == "BLOCK":
        curr_block := node_id
        last_type := "int"
        while curr_block != -1:
            block_node := nodes[curr_block + 0]
            last_type = get_node_type(nodes, var_allocs, var_types, block_node.left_id)
            curr_block = block_node.right_id
        return last_type
    elif node.kind == "CALL":
        if node.name == "vector":
            return "vector"
        if node.name == "read_file" or node.name == "read" or node.name == "file_read":
            return "string"
        if node.name == "to_text":
            return "string"
        if node.name == "get_char":
            return "string"
        if node.name == "str_heap_copy":
            return "string"
        if node.name == "str_substr":
            return "string"
        if node.name == "char_to_string":
            return "string"
        k_n := 0
        sz_n := list_size(nodes)
        while k_n < sz_n:
            n := nodes[k_n + 0]
            if n.kind == "MODEL" and n.name == node.name:
                return node.name
            k_n += 1
        fn_ret_type: string := "int"
        k_n = 0
        while k_n < sz_n:
            n := nodes[k_n + 0]
            if n.kind == "FN" and n.name == node.name:
                fn_ret_type = n.op
                break
            k_n += 1
        return fn_ret_type
    elif node.kind == "MEMBER":
        parent_node := nodes[node.left_id + 0]
        model_name: string := ""
        if parent_node.kind == "CALL":
            fn_ret_type: string := "int"
            k := 0
            sz := list_size(nodes)
            while k < sz:
                n := nodes[k + 0]
                if n.kind == "FN" and n.name == parent_node.name:
                    fn_ret_type = n.op
                    break
                k += 1
            if is_model_type(nodes, parent_node.name):
                fn_ret_type = parent_node.name
            model_name = fn_ret_type
        elif parent_node.kind == "INDEX":
            vec_var_node := nodes[parent_node.left_id + 0]
            model_name = find_var_model_type(nodes, vec_var_node.name)
        else:
            parent_var_name := parent_node.name
            model_name = find_var_model_type(nodes, parent_var_name)
        model_id := -1
        k := 0
        sz := list_size(nodes)
        while k < sz:
            n := nodes[k + 0]
            if n.kind == "MODEL" and n.name == model_name:
                model_id = n.id
                break
            k += 1
        if model_id != -1:
            m_node := nodes[model_id + 0]
            curr_field := m_node.right_id
            while curr_field != -1:
                f_node := nodes[curr_field + 0]
                if f_node.name == node.name:
                    return f_node.op
                curr_field = f_node.right_id
        return "int"
    elif node.kind == "INDEX":
        vec_var_node := nodes[node.left_id + 0]
        if vec_var_node.name == "sys_args":
            return "string"
        vec_elem_type := find_var_model_type(nodes, vec_var_node.name)
        if vec_elem_type != "":
            return vec_elem_type
        return "int"
    return "int"

fn hoist_var_allocas(&nodes: vector[ASTNode], &var_allocs: vector[string], &var_types: vector[string], &ir_output: string, node_id: int):
    if node_id == -1:
        return
    node := nodes[node_id + 0]
    if node.kind == "ASSIGN":
        if node.val_int == -1:
            if not has_var(var_allocs, node.name):
                expr_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
                list_push(var_allocs, node.name)
                list_push(var_types, str_heap_copy(expr_type))
                if expr_type == "string":
                    emit(ir_output, "    %" + node.name + " = alloca %struct.string, align 8")
                elif expr_type == "vector":
                    emit(ir_output, "    %" + node.name + " = alloca %struct.vector, align 8")
                elif expr_type == "ptr" or is_model_type(nodes, expr_type):
                    emit(ir_output, "    %" + node.name + " = alloca ptr, align 8")
                else:
                    emit(ir_output, "    %" + node.name + " = alloca i64, align 8")
    elif node.kind == "BLOCK":
        hoist_var_allocas(nodes, var_allocs, var_types, ir_output, node.left_id)
        hoist_var_allocas(nodes, var_allocs, var_types, ir_output, node.right_id)
    elif node.kind == "IF":
        hoist_var_allocas(nodes, var_allocs, var_types, ir_output, node.right_id)
        hoist_var_allocas(nodes, var_allocs, var_types, ir_output, node.val_int)
    elif node.kind == "WHILE":
        hoist_var_allocas(nodes, var_allocs, var_types, ir_output, node.right_id)
    elif node.kind == "ELIF":
        hoist_var_allocas(nodes, var_allocs, var_types, ir_output, node.right_id)

fn generate_node_ir(&nodes: vector[ASTNode], &ir_output: string, &temp_counter: int, &label_counter: int, &var_allocs: vector[string], &var_types: vector[string], &break_stack: vector[int], &hoisted_vars: vector[string], node_id: int) -> string:
    if node_id == -1:
        return ""
        
    node := nodes[node_id + 0]
    
    if node.kind == "LITERAL":
        if node.val_int == 0:
            return node.name
        else:
            temp_counter += 1
            temp_str := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + temp_str + " = alloca %struct.string, align 8")
            
            temp_counter += 1
            ptr_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 0")
            emit(ir_output, "    store ptr @.str_" + to_text(node.id) + ", ptr " + ptr_field + ", align 8")
            
            str_len := get_llvm_string_len(node.name)
            temp_counter += 1
            len_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 1")
            emit(ir_output, "    store i64 " + to_text(str_len) + ", ptr " + len_field + ", align 8")
            
            return temp_str
    elif node.kind == "VAR":
        if node.name == "true":
            return "1"
        if node.name == "false":
            return "0"
        var_type := get_node_type(nodes, var_allocs, var_types, node_id)
        if is_param_ref_int(node.name, var_allocs, var_types):
            temp_counter += 1
            p_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + p_reg + " = load ptr, ptr " + var_ref(node.name) + ", align 8")
            temp_counter += 1
            v_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + v_reg + " = load i64, ptr " + p_reg + ", align 8")
            return v_reg
        if var_type == "string" or var_type == "vector":
            return var_struct_ref(node.name, var_allocs, var_types, temp_counter, ir_output)
        elif var_type == "ptr" or is_model_type(nodes, var_type):
            temp_counter += 1
            reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + reg + " = load ptr, ptr %" + node.name + ", align 8")
            return reg
        else:
            temp_counter += 1
            reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + reg + " = load i64, ptr %" + node.name + ", align 8")
            return reg
    elif node.kind == "UNARY":
        if node.op == "not":
            val_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
            
            temp_counter += 1
            cmp_reg: string := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + cmp_reg + " = icmp eq i64 " + val_reg + ", 0")
            
            temp_counter += 1
            zext_reg: string := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + zext_reg + " = zext i1 " + cmp_reg + " to i64")
            return zext_reg
        elif node.op == "-":
            val_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
            
            temp_counter += 1
            neg_reg: string := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + neg_reg + " = sub i64 0, " + val_reg)
            return neg_reg
        elif node.op == "&":
            operand := nodes[node.left_id + 0]
            if operand.kind == "VAR":
                if is_user_fn(operand.name) == 1:
                    return "@" + operand.name
                return "%" + operand.name
            return ""
        elif node.op == "*":
            ptr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
            temp_counter += 1
            val_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + val_reg + " = load i64, ptr " + ptr_reg + ", align 8")
            return val_reg
        return ""
    elif node.kind == "BINARY":
        left_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        right_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.right_id)
        
        left_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
        right_type := get_node_type(nodes, var_allocs, var_types, node.right_id)
        
        is_str_concat := false
        if node.op == "+":
            if left_type == "string" or right_type == "string":
                is_str_concat = true
        if is_str_concat:
            # Load LHS fields
            temp_counter += 1
            l_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + l_ptr_f + " = getelementptr inbounds %struct.string, ptr " + left_reg + ", i32 0, i32 0")
            temp_counter += 1
            l_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + l_ptr + " = load ptr, ptr " + l_ptr_f + ", align 8")
            
            temp_counter += 1
            l_len_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + l_len_f + " = getelementptr inbounds %struct.string, ptr " + left_reg + ", i32 0, i32 1")
            temp_counter += 1
            l_len := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + l_len + " = load i64, ptr " + l_len_f + ", align 8")
            
            # Load RHS fields
            temp_counter += 1
            r_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + r_ptr_f + " = getelementptr inbounds %struct.string, ptr " + right_reg + ", i32 0, i32 0")
            temp_counter += 1
            r_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + r_ptr + " = load ptr, ptr " + r_ptr_f + ", align 8")
            
            temp_counter += 1
            r_len_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + r_len_f + " = getelementptr inbounds %struct.string, ptr " + right_reg + ", i32 0, i32 1")
            temp_counter += 1
            r_len := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + r_len + " = load i64, ptr " + r_len_f + ", align 8")
            
            # Call str_concat
            temp_counter += 1
            new_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + new_ptr + " = call ptr @__zk_str_concat(ptr " + l_ptr + ", i64 " + l_len + ", ptr " + r_ptr + ", i64 " + r_len + ")")
            
            # Allocate temp struct and store
            temp_counter += 1
            temp_str := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + temp_str + " = alloca %struct.string, align 8")
            
            temp_counter += 1
            ptr_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 0")
            emit(ir_output, "    store ptr " + new_ptr + ", ptr " + ptr_field + ", align 8")
            
            temp_counter += 1
            total_len := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + total_len + " = add i64 " + l_len + ", " + r_len)
            
            temp_counter += 1
            len_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 1")
            emit(ir_output, "    store i64 " + total_len + ", ptr " + len_field + ", align 8")
            
            return temp_str
            
        temp_counter += 1
        reg := "%t" + to_text(temp_counter)
        
        op_name: string := "add"
        if node.op == "-":
            op_name = "sub"
        elif node.op == "*":
            op_name = "mul"
        elif node.op == "/":
            op_name = "sdiv"
        elif node.op == "%":
            op_name = "srem"
        elif node.op == "&":
            op_name = "and"
        elif node.op == "|":
            op_name = "or"
        elif node.op == "^":
            op_name = "xor"
        elif node.op == "<<":
            op_name = "shl"
        elif node.op == ">>":
            op_name = "ashr"
        elif node.op == "==":
            op_name = "icmp eq"
        elif node.op == "!=":
            op_name = "icmp ne"
        elif node.op == "<":
            op_name = "icmp slt"
        elif node.op == ">":
            op_name = "icmp sgt"
        elif node.op == ">=":
            op_name = "icmp sge"
        elif node.op == "<=":
            op_name = "icmp sle"
        elif node.op == "or":
            op_name = "or"
        elif node.op == "and":
            op_name = "and"
            
        is_comp := false
        if node.op == "==" or node.op == "!=":
            is_comp = true
        elif node.op == "<" or node.op == ">" or node.op == ">=" or node.op == "<=":
            is_comp = true
            
        if is_comp:
            cmp_type: string := "i64"
            if left_type == "string" or right_type == "string":
                if node.op == "==" or node.op == "!=":
                    temp_counter += 1
                    a_ptr_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + a_ptr_f + " = getelementptr inbounds %struct.string, ptr " + left_reg + ", i32 0, i32 0")
                    temp_counter += 1
                    a_ptr := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + a_ptr + " = load ptr, ptr " + a_ptr_f + ", align 8")
                    temp_counter += 1
                    a_len_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + a_len_f + " = getelementptr inbounds %struct.string, ptr " + left_reg + ", i32 0, i32 1")
                    temp_counter += 1
                    a_len := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + a_len + " = load i64, ptr " + a_len_f + ", align 8")
                    
                    temp_counter += 1
                    b_ptr_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + b_ptr_f + " = getelementptr inbounds %struct.string, ptr " + right_reg + ", i32 0, i32 0")
                    temp_counter += 1
                    b_ptr := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + b_ptr + " = load ptr, ptr " + b_ptr_f + ", align 8")
                    temp_counter += 1
                    b_len_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + b_len_f + " = getelementptr inbounds %struct.string, ptr " + right_reg + ", i32 0, i32 1")
                    temp_counter += 1
                    b_len := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + b_len + " = load i64, ptr " + b_len_f + ", align 8")
                    
                    temp_counter += 1
                    eq_reg := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + eq_reg + " = call i64 @__zk_str_eq(ptr " + a_ptr + ", i64 " + a_len + ", ptr " + b_ptr + ", i64 " + b_len + ")")
                    if node.op == "!=":
                        temp_counter += 1
                        ne_reg := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + ne_reg + " = icmp eq i64 " + eq_reg + ", 0")
                        temp_counter += 1
                        ne_zext := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + ne_zext + " = zext i1 " + ne_reg + " to i64")
                        return ne_zext
                    return eq_reg
                cmp_type = "ptr"
            emit(ir_output, "    " + reg + " = " + op_name + " " + cmp_type + " " + left_reg + ", " + right_reg)
            temp_counter += 1
            zext_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + zext_reg + " = zext i1 " + reg + " to i64")
            return zext_reg
            
        emit(ir_output, "    " + reg + " = " + op_name + " i64 " + left_reg + ", " + right_reg)
        return reg
    elif node.kind == "ASSIGN":
        expr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        
        if node.val_int != -1:
            lhs_node := nodes[node.val_int + 0]
            if lhs_node.kind == "INDEX":
                parent_var_node := nodes[lhs_node.left_id + 0]
                parent_var_name := parent_var_node.name
                
                index_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, lhs_node.right_id)
                
                temp_counter += 1
                ptr_f := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.vector, ptr " + var_struct_ref(parent_var_name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 0")
                
                temp_counter += 1
                elem_ptr := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + elem_ptr + " = load ptr, ptr " + ptr_f + ", align 8")
                
                temp_counter += 1
                dest_ptr := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + dest_ptr + " = getelementptr i64, ptr " + elem_ptr + ", i64 " + index_reg)
                
                store_reg := expr_reg
                store_type := "i64"
                elem_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
                if is_model_type(nodes, elem_type):
                    temp_counter += 1
                    store_reg = "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + store_reg + " = ptrtoint ptr " + expr_reg + " to i64")
                emit(ir_output, "    store " + store_type + " " + store_reg + ", ptr " + dest_ptr + ", align 8")
                return ""
            elif lhs_node.kind == "UNARY" and lhs_node.op == "*":
                ptr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, lhs_node.left_id)
                emit(ir_output, "    store i64 " + expr_reg + ", ptr " + ptr_reg + ", align 8")
                return ""
            elif lhs_node.kind == "MEMBER":
                parent_node := nodes[lhs_node.left_id + 0]
                model_name: string := ""
                parent_ptr: string := ""
                
                if parent_node.kind == "INDEX":
                    vec_var_node := nodes[parent_node.left_id + 0]
                    vec_var_name := vec_var_node.name
                    model_name = find_var_model_type(nodes, vec_var_name)
                    
                    index_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, parent_node.right_id)
                    
                    temp_counter += 1
                    vec_data_ptr := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + vec_data_ptr + " = getelementptr inbounds %struct.vector, ptr " + var_struct_ref(vec_var_name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 0")
                    
                    temp_counter += 1
                    vec_data := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + vec_data + " = load ptr, ptr " + vec_data_ptr + ", align 8")
                    
                    temp_counter += 1
                    elem_slot := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + elem_slot + " = getelementptr i64, ptr " + vec_data + ", i64 " + index_reg)
                    
                    temp_counter += 1
                    elem_load := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + elem_load + " = load i64, ptr " + elem_slot + ", align 8")
                    
                    temp_counter += 1
                    parent_ptr = "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + parent_ptr + " = inttoptr i64 " + elem_load + " to ptr")
                else:
                    parent_var_name := parent_node.name
                    model_name = find_var_model_type(nodes, parent_var_name)
                    temp_counter += 1
                    parent_ptr = "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + parent_ptr + " = load ptr, ptr %" + parent_var_name + ", align 8")
                
                field_idx := find_field_index(nodes, model_name, lhs_node.name)
                
                temp_counter += 1
                f_ptr := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + f_ptr + " = getelementptr inbounds %struct." + model_name + ", ptr " + parent_ptr + ", i32 0, i32 " + to_text(field_idx))
                emit(ir_output, "    store i64 " + expr_reg + ", ptr " + f_ptr + ", align 8")
                return ""
            return ""
        else:
            is_new := false
            if not has_var(var_allocs, node.name):
                is_new = true
                
            expr_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
            if is_new:
                list_push(var_allocs, node.name)
                list_push(var_types, str_heap_copy(expr_type))
                if node.name == "tokens":
                    print_err("DEBUG: tokens is_new = true. hoisted_vars size: " + to_text(list_size(hoisted_vars)))
                    ii := 0
                    while ii < list_size(hoisted_vars):
                        print_err("  hoisted_vars[" + to_text(ii) + "]: '" + hoisted_vars[ii + 0] + "'")
                        ii += 1
                if not has_var(hoisted_vars, node.name):
                    if expr_type == "string":
                        emit(ir_output, "    %" + node.name + " = alloca %struct.string, align 8")
                    elif expr_type == "vector":
                        emit(ir_output, "    %" + node.name + " = alloca %struct.vector, align 8")
                    elif expr_type == "ptr" or is_model_type(nodes, expr_type):
                        emit(ir_output, "    %" + node.name + " = alloca ptr, align 8")
                    else:
                        emit(ir_output, "    %" + node.name + " = alloca i64, align 8")
                if expr_type == "vector":
                    temp_counter += 1
                    ptr_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.vector, ptr %" + node.name + ", i32 0, i32 0")
                    emit(ir_output, "    store ptr null, ptr " + ptr_f + ", align 8")
                    
                    temp_counter += 1
                    sz_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + sz_f + " = getelementptr inbounds %struct.vector, ptr %" + node.name + ", i32 0, i32 1")
                    emit(ir_output, "    store i64 0, ptr " + sz_f + ", align 8")
                    
                    temp_counter += 1
                    cap_f := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + cap_f + " = getelementptr inbounds %struct.vector, ptr %" + node.name + ", i32 0, i32 2")
                    emit(ir_output, "    store i64 0, ptr " + cap_f + ", align 8")
                        
            if expr_type == "string":
                # Copy string fields
                temp_counter += 1
                rhs_ptr_field := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + rhs_ptr_field + " = getelementptr inbounds %struct.string, ptr " + expr_reg + ", i32 0, i32 0")
                
                temp_counter += 1
                rhs_ptr := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + rhs_ptr + " = load ptr, ptr " + rhs_ptr_field + ", align 8")
                
                temp_counter += 1
                rhs_len_field := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + rhs_len_field + " = getelementptr inbounds %struct.string, ptr " + expr_reg + ", i32 0, i32 1")
                
                temp_counter += 1
                rhs_len := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + rhs_len + " = load i64, ptr " + rhs_len_field + ", align 8")
                
                # Store to LHS
                temp_counter += 1
                lhs_ptr_field := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + lhs_ptr_field + " = getelementptr inbounds %struct.string, ptr " + var_struct_ref(node.name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 0")
                emit(ir_output, "    store ptr " + rhs_ptr + ", ptr " + lhs_ptr_field + ", align 8")
                
                temp_counter += 1
                lhs_len_field := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + lhs_len_field + " = getelementptr inbounds %struct.string, ptr " + var_struct_ref(node.name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 1")
                emit(ir_output, "    store i64 " + rhs_len + ", ptr " + lhs_len_field + ", align 8")
            elif expr_type == "vector":
                # Copy the RHS vector struct into the var (unless RHS is a fresh vector constructor)
                if expr_reg != "":
                    lhs_vec := var_struct_ref(node.name, var_allocs, var_types, temp_counter, ir_output)
                    temp_counter += 1
                    r0 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + r0 + " = getelementptr inbounds %struct.vector, ptr " + expr_reg + ", i32 0, i32 0")
                    temp_counter += 1
                    v0 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + v0 + " = load ptr, ptr " + r0 + ", align 8")
                    temp_counter += 1
                    d0 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + d0 + " = getelementptr inbounds %struct.vector, ptr " + lhs_vec + ", i32 0, i32 0")
                    emit(ir_output, "    store ptr " + v0 + ", ptr " + d0 + ", align 8")
                    temp_counter += 1
                    r1 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + r1 + " = getelementptr inbounds %struct.vector, ptr " + expr_reg + ", i32 0, i32 1")
                    temp_counter += 1
                    v1 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + v1 + " = load i64, ptr " + r1 + ", align 8")
                    temp_counter += 1
                    d1 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + d1 + " = getelementptr inbounds %struct.vector, ptr " + lhs_vec + ", i32 0, i32 1")
                    emit(ir_output, "    store i64 " + v1 + ", ptr " + d1 + ", align 8")
                    temp_counter += 1
                    r2 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + r2 + " = getelementptr inbounds %struct.vector, ptr " + expr_reg + ", i32 0, i32 2")
                    temp_counter += 1
                    v2 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + v2 + " = load i64, ptr " + r2 + ", align 8")
                    temp_counter += 1
                    d2 := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + d2 + " = getelementptr inbounds %struct.vector, ptr " + lhs_vec + ", i32 0, i32 2")
                    emit(ir_output, "    store i64 " + v2 + ", ptr " + d2 + ", align 8")
                return ""
            else:
                if expr_type == "ptr" or is_model_type(nodes, expr_type):
                    emit(ir_output, "    store ptr " + expr_reg + ", ptr %" + node.name + ", align 8")
                elif is_param_ref_int(node.name, var_allocs, var_types):
                    temp_counter += 1
                    p_reg := "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + p_reg + " = load ptr, ptr %" + node.name + ", align 8")
                    emit(ir_output, "    store i64 " + expr_reg + ", ptr " + p_reg + ", align 8")
                else:
                    emit(ir_output, "    store i64 " + expr_reg + ", ptr %" + node.name + ", align 8")
            return ""
    elif node.kind == "PUT":
        expr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        expr_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
        
        if expr_type == "string":
            temp_counter += 1
            ptr_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_field + " = getelementptr inbounds %struct.string, ptr " + expr_reg + ", i32 0, i32 0")
            
            temp_counter += 1
            ptr_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_val + " = load ptr, ptr " + ptr_field + ", align 8")
            
            temp_counter += 1
            len_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_field + " = getelementptr inbounds %struct.string, ptr " + expr_reg + ", i32 0, i32 1")
            
            temp_counter += 1
            len_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_val + " = load i64, ptr " + len_field + ", align 8")
            
            emit(ir_output, "    call void @__zk_print_string(ptr " + ptr_val + ", i64 " + len_val + ")")
        else:
            emit(ir_output, "    call void @__zk_print_int(i64 " + expr_reg + ")")
        return ""
    elif node.kind == "BLOCK":
        curr_block := node_id
        last_reg := ""
        while curr_block != -1:
            block_node := nodes[curr_block + 0]
            last_reg = generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, block_node.left_id)
            curr_block = block_node.right_id
        return last_reg
    elif node.kind == "ASM":
        emit(ir_output, "    call void asm sideeffect \"" + node.name + "\", \"\"()")
        return ""
    elif node.kind == "RETURN":
        if node.left_id == -1:
            emit(ir_output, "    ret i64 0")
        else:
            expr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
            expr_type := get_node_type(nodes, var_allocs, var_types, node.left_id)
            if expr_type == "string" or expr_type == "vector" or is_model_type(nodes, expr_type):
                struct_sz := 0
                if expr_type == "string":
                    struct_sz = 16
                elif expr_type == "vector":
                    struct_sz = 24
                else:
                    struct_sz = model_byte_size(nodes, expr_type)
                temp_counter += 1
                heap_reg := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + heap_reg + " = call ptr @malloc(i64 " + to_text(struct_sz) + ")")
                temp_counter += 1
                copy_reg := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + copy_reg + " = call ptr @memcpy(ptr " + heap_reg + ", ptr " + expr_reg + ", i64 " + to_text(struct_sz) + ")")
                temp_counter += 1
                cast_reg := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + cast_reg + " = ptrtoint ptr " + heap_reg + " to i64")
                emit(ir_output, "    ret i64 " + cast_reg)
            else:
                emit(ir_output, "    ret i64 " + expr_reg)
        return ""
    elif node.kind == "CALL":
        if node.name == "c_str":
            cstr_arg := nodes[node.left_id + 0]
            arg_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, cstr_arg.left_id)
            temp_counter += 1
            ptr_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_field + " = getelementptr inbounds %struct.string, ptr " + arg_reg + ", i32 0, i32 0")
            temp_counter += 1
            ptr_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_val + " = load ptr, ptr " + ptr_field + ", align 8")
            return ptr_val
        if node.name == "ptr_read":
            arg := nodes[node.left_id + 0]
            ptr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg.left_id)
            temp_counter += 1
            val_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + val_reg + " = load i64, ptr " + ptr_reg + ", align 8")
            return val_reg
            
        if node.name == "ptr_write":
            arg1 := nodes[node.left_id + 0]
            ptr_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg1.left_id)
            arg2 := nodes[arg1.right_id + 0]
            val_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg2.left_id)
            emit(ir_output, "    store i64 " + val_reg + ", ptr " + ptr_reg + ", align 8")
            return ""
            
        if node.name == "file_write" or node.name == "write_file":
            arg1_node := nodes[node.left_id + 0]
            path_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg1_node.left_id)
            arg2_node := nodes[arg1_node.right_id + 0]
            content_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg2_node.left_id)
            
            temp_counter += 1
            path_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr_f + " = getelementptr inbounds %struct.string, ptr " + path_reg + ", i32 0, i32 0")
            temp_counter += 1
            path_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr + " = load ptr, ptr " + path_ptr_f + ", align 8")
            
            temp_counter += 1
            content_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + content_ptr_f + " = getelementptr inbounds %struct.string, ptr " + content_reg + ", i32 0, i32 0")
            temp_counter += 1
            content_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + content_ptr + " = load ptr, ptr " + content_ptr_f + ", align 8")
            
            temp_counter += 1
            content_len_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + content_len_f + " = getelementptr inbounds %struct.string, ptr " + content_reg + ", i32 0, i32 1")
            temp_counter += 1
            content_len := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + content_len + " = load i64, ptr " + content_len_f + ", align 8")
            
            temp_counter += 1
            mode_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + mode_ptr + " = alloca [2 x i8], align 1")
            emit(ir_output, "    store i8 119, ptr " + mode_ptr + ", align 1")
            temp_counter += 1
            null_mode_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + null_mode_ptr + " = getelementptr i8, ptr " + mode_ptr + ", i64 1")
            emit(ir_output, "    store i8 0, ptr " + null_mode_ptr + ", align 1")
            
            temp_counter += 1
            file_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + file_ptr + " = call ptr @fopen(ptr " + path_ptr + ", ptr " + mode_ptr + ")")
            
            temp_counter += 1
            null_chk := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + null_chk + " = icmp eq ptr " + file_ptr + ", null")
            label_counter += 1
            wr_fail := "write_fail_" + to_text(label_counter)
            label_counter += 1
            wr_ok := "write_ok_" + to_text(label_counter)
            label_counter += 1
            wr_merge := "write_merge_" + to_text(label_counter)
            emit(ir_output, "    br i1 " + null_chk + ", label %" + wr_fail + ", label %" + wr_ok)
            
            emit(ir_output, wr_fail + ":")
            emit(ir_output, "    br label %" + wr_merge)
            
            emit(ir_output, wr_ok + ":")
            temp_counter += 1
            fwrite_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + fwrite_res + " = call i64 @fwrite(ptr " + content_ptr + ", i64 1, i64 " + content_len + ", ptr " + file_ptr + ")")
            emit(ir_output, "    %unused_close_wr = call i32 @fclose(ptr " + file_ptr + ")")
            emit(ir_output, "    br label %" + wr_merge)
            
            emit(ir_output, wr_merge + ":")
            return ""
            
        if node.name == "read_file" or node.name == "read" or node.name == "file_read":
            rdf_arg := nodes[node.left_id + 0]
            arg_expr_id := rdf_arg.left_id
            path_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg_expr_id)
            
            temp_counter += 1
            path_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr_f + " = getelementptr inbounds %struct.string, ptr " + path_reg + ", i32 0, i32 0")
            temp_counter += 1
            path_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr + " = load ptr, ptr " + path_ptr_f + ", align 8")
            
            temp_counter += 1
            mode_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + mode_ptr + " = alloca [2 x i8], align 1")
            emit(ir_output, "    store i8 114, ptr " + mode_ptr + ", align 1")
            temp_counter += 1
            null_mode_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + null_mode_ptr + " = getelementptr i8, ptr " + mode_ptr + ", i64 1")
            emit(ir_output, "    store i8 0, ptr " + null_mode_ptr + ", align 1")
            
            temp_counter += 1
            file_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + file_ptr + " = call ptr @fopen(ptr " + path_ptr + ", ptr " + mode_ptr + ")")
            
            temp_counter += 1
            null_chk := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + null_chk + " = icmp eq ptr " + file_ptr + ", null")
            label_counter += 1
            rd_empty := "read_empty_" + to_text(label_counter)
            label_counter += 1
            rd_ok := "read_ok_" + to_text(label_counter)
            label_counter += 1
            rd_merge := "read_merge_" + to_text(label_counter)
            emit(ir_output, "    br i1 " + null_chk + ", label %" + rd_empty + ", label %" + rd_ok)
            emit(ir_output, rd_empty + ":")
            temp_counter += 1
            es_buf := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + es_buf + " = call ptr @malloc(i64 1)")
            emit(ir_output, "    store i8 0, ptr " + es_buf + ", align 1")
            temp_counter += 1
            es_struct := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + es_struct + " = alloca %struct.string, align 8")
            temp_counter += 1
            es_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + es_ptr_f + " = getelementptr inbounds %struct.string, ptr " + es_struct + ", i32 0, i32 0")
            emit(ir_output, "    store ptr " + es_buf + ", ptr " + es_ptr_f + ", align 8")
            temp_counter += 1
            es_len_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + es_len_f + " = getelementptr inbounds %struct.string, ptr " + es_struct + ", i32 0, i32 1")
            emit(ir_output, "    store i64 0, ptr " + es_len_f + ", align 8")
            emit(ir_output, "    br label %" + rd_merge)
            emit(ir_output, rd_ok + ":")
            
            emit(ir_output, "    %unused_seek1 = call i32 @fseek(ptr " + file_ptr + ", i64 0, i32 2)")
            
            temp_counter += 1
            sz_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + sz_reg + " = call i64 @ftell(ptr " + file_ptr + ")")
            
            emit(ir_output, "    call void @rewind(ptr " + file_ptr + ")")
            
            temp_counter += 1
            buf_size := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + buf_size + " = add i64 " + sz_reg + ", 1")
            temp_counter += 1
            buf_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + buf_reg + " = call ptr @malloc(i64 " + buf_size + ")")
            
            temp_counter += 1
            fread_count := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + fread_count + " = call i64 @fread(ptr " + buf_reg + ", i64 1, i64 " + sz_reg + ", ptr " + file_ptr + ")")
            
            temp_counter += 1
            null_dest := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + null_dest + " = getelementptr i8, ptr " + buf_reg + ", i64 " + sz_reg)
            emit(ir_output, "    store i8 0, ptr " + null_dest + ", align 1")
            
            emit(ir_output, "    %unused_close = call i32 @fclose(ptr " + file_ptr + ")")
            
            temp_counter += 1
            temp_str := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + temp_str + " = alloca %struct.string, align 8")
            
            temp_counter += 1
            ptr_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 0")
            emit(ir_output, "    store ptr " + buf_reg + ", ptr " + ptr_field + ", align 8")
            
            temp_counter += 1
            len_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 1")
            emit(ir_output, "    store i64 " + sz_reg + ", ptr " + len_field + ", align 8")
            
            emit(ir_output, "    br label %" + rd_merge)
            emit(ir_output, rd_merge + ":")
            temp_counter += 1
            rd_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + rd_res + " = phi ptr [ " + es_struct + ", %" + rd_empty + " ], [ " + temp_str + ", %" + rd_ok + " ]")
            return rd_res
            
        if node.name == "file_exists":
            fe_arg := nodes[node.left_id + 0]
            path_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, fe_arg.left_id)
            
            temp_counter += 1
            path_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr_f + " = getelementptr inbounds %struct.string, ptr " + path_reg + ", i32 0, i32 0")
            temp_counter += 1
            path_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr + " = load ptr, ptr " + path_ptr_f + ", align 8")
            
            temp_counter += 1
            access_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + access_res + " = call i32 @access(ptr " + path_ptr + ", i32 0)")
            temp_counter += 1
            exists_cond := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + exists_cond + " = icmp eq i32 " + access_res + ", 0")
            temp_counter += 1
            zext_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + zext_res + " = zext i1 " + exists_cond + " to i64")
            return zext_res

        if node.name == "file_delete":
            fd_arg := nodes[node.left_id + 0]
            path_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, fd_arg.left_id)
            
            temp_counter += 1
            path_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr_f + " = getelementptr inbounds %struct.string, ptr " + path_reg + ", i32 0, i32 0")
            temp_counter += 1
            path_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + path_ptr + " = load ptr, ptr " + path_ptr_f + ", align 8")
            
            temp_counter += 1
            remove_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + remove_res + " = call i32 @remove(ptr " + path_ptr + ")")
            temp_counter += 1
            delete_cond := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + delete_cond + " = icmp eq i32 " + remove_res + ", 0")
            temp_counter += 1
            zext_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + zext_res + " = zext i1 " + delete_cond + " to i64")
            return zext_res
            
        if node.name == "to_text":
            tot_arg := nodes[node.left_id + 0]
            arg_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, tot_arg.left_id)
            
            temp_counter += 1
            int_str_buf := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + int_str_buf + " = alloca [32 x i8], align 1")
            
            temp_counter += 1
            int_str_count := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + int_str_count + " = call i32 (ptr, ptr, ...) @sprintf(ptr " + int_str_buf + ", ptr @__zk_fmt_int, i64 " + arg_reg + ")")
            
            temp_counter += 1
            int_str_len := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + int_str_len + " = sext i32 " + int_str_count + " to i64")
            
            temp_counter += 1
            temp_str := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + temp_str + " = alloca %struct.string, align 8")
            
            temp_counter += 1
            ptr_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 0")
            emit(ir_output, "    store ptr " + int_str_buf + ", ptr " + ptr_field + ", align 8")
            
            temp_counter += 1
            len_field := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_field + " = getelementptr inbounds %struct.string, ptr " + temp_str + ", i32 0, i32 1")
            emit(ir_output, "    store i64 " + int_str_len + ", ptr " + len_field + ", align 8")
            
            return temp_str
            
        if node.name == "char_at":
            arg1_node := nodes[node.left_id + 0]
            str_expr_id := arg1_node.left_id
            str_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, str_expr_id)
            
            temp_counter += 1
            ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.string, ptr " + str_reg + ", i32 0, i32 0")
            temp_counter += 1
            ptr_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_val + " = load ptr, ptr " + ptr_f + ", align 8")
            
            arg2_node := nodes[arg1_node.right_id + 0]
            idx_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg2_node.left_id)
            
            temp_counter += 1
            reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + reg + " = call i64 @__zk_char_at(ptr " + ptr_val + ", i64 " + idx_reg + ")")
            return reg
            
        if node.name == "addr_of":
            adr_arg := nodes[node.left_id + 0]
            var_node := nodes[adr_arg.left_id + 0]
            return "%" + var_node.name
            
        if node.name == "vector":
            return ""
            
        if node.name == "list_push":
            arg1_node := nodes[node.left_id + 0]
            vec_expr_id := arg1_node.left_id
            vec_var_node := nodes[vec_expr_id + 0]
            vec_name := vec_var_node.name
            
            arg2_node := nodes[arg1_node.right_id + 0]
            elem_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, arg2_node.left_id)
            
            elem_type := get_node_type(nodes, var_allocs, var_types, arg2_node.left_id)
            push_reg := elem_reg
            if elem_type == "string" or elem_type == "vector":
                temp_counter += 1
                push_reg = "%t" + to_text(temp_counter)
                emit(ir_output, "    " + push_reg + " = ptrtoint ptr " + elem_reg + " to i64")
            else:
                # Check if it's a model constructor (returns ptr)
                elem_expr := nodes[arg2_node.left_id + 0]
                is_model_push := is_model_type(nodes, elem_type)
                if elem_expr.kind == "CALL":
                    k_m := 0
                    sz_m := list_size(nodes)
                    while k_m < sz_m:
                        n := nodes[k_m + 0]
                        if n.kind == "MODEL" and n.name == elem_expr.name:
                            is_model_push = true
                            break
                        k_m += 1
                if is_model_push:
                    temp_counter += 1
                    push_reg = "%t" + to_text(temp_counter)
                    emit(ir_output, "    " + push_reg + " = ptrtoint ptr " + elem_reg + " to i64")
            
            emit(ir_output, "    call void @__zk_vector_push(ptr " + var_struct_ref(vec_name, var_allocs, var_types, temp_counter, ir_output) + ", i64 " + push_reg + ")")
            return ""
            
        if node.name == "list_size":
            sz_arg := nodes[node.left_id + 0]
            vec_expr_id := sz_arg.left_id
            vec_var_node := nodes[vec_expr_id + 0]
            vec_name := vec_var_node.name
            
            temp_counter += 1
            sz_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + sz_f + " = getelementptr inbounds %struct.vector, ptr " + var_struct_ref(vec_name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 1")
            temp_counter += 1
            sz_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + sz_val + " = load i64, ptr " + sz_f + ", align 8")
            return sz_val
            
        if node.name == "text_length":
            tl_arg := nodes[node.left_id + 0]
            str_expr_id := tl_arg.left_id
            str_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, str_expr_id)
            
            temp_counter += 1
            ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.string, ptr " + str_reg + ", i32 0, i32 0")
            temp_counter += 1
            ptr_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_val + " = load ptr, ptr " + ptr_f + ", align 8")
            
            temp_counter += 1
            len_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_val + " = call i64 @strlen(ptr " + ptr_val + ")")
            return len_val
            
        if node.name == "list_pop":
            pop_arg := nodes[node.left_id + 0]
            vec_expr_id := pop_arg.left_id
            vec_var_node := nodes[vec_expr_id + 0]
            vec_name := vec_var_node.name
            
            temp_counter += 1
            sz_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + sz_f + " = getelementptr inbounds %struct.vector, ptr " + var_struct_ref(vec_name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 1")
            temp_counter += 1
            sz_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + sz_val + " = load i64, ptr " + sz_f + ", align 8")
            
            temp_counter += 1
            sz_dec := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + sz_dec + " = sub i64 " + sz_val + ", 1")
            emit(ir_output, "    store i64 " + sz_dec + ", ptr " + sz_f + ", align 8")
            return ""
            
        if node.name == "is_alpha_at" or node.name == "is_digit_at" or node.name == "is_space_at":
            chk_arg := nodes[node.left_id + 0]
            str_expr_id := chk_arg.left_id
            str_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, str_expr_id)
            idx_arg := nodes[chk_arg.right_id + 0]
            idx_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, idx_arg.left_id)
            
            temp_counter += 1
            ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.string, ptr " + str_reg + ", i32 0, i32 0")
            temp_counter += 1
            ptr_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_val + " = load ptr, ptr " + ptr_f + ", align 8")
            
            temp_counter += 1
            ch_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ch_reg + " = call i64 @__zk_char_at(ptr " + ptr_val + ", i64 " + idx_reg + ")")
            
            helper: string := "__zk_is_alpha_char"
            if node.name == "is_digit_at":
                helper = "__zk_is_digit_char"
            elif node.name == "is_space_at":
                helper = "__zk_is_space_char"
            temp_counter += 1
            res_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + res_reg + " = call i64 @" + helper + "(i64 " + ch_reg + ")")
            return res_reg
            
        if node.name == "char_to_string":
            cts_arg := nodes[node.left_id + 0]
            c_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, cts_arg.left_id)
            temp_counter += 1
            res_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + res_reg + " = call ptr @__zk_char_to_string(i64 " + c_reg + ")")
            return res_reg
            
        if node.name == "str_heap_copy":
            hc_arg := nodes[node.left_id + 0]
            hc_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, hc_arg.left_id)
            temp_counter += 1
            hc_heap := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + hc_heap + " = call ptr @malloc(i64 16)")
            temp_counter += 1
            hc_copy := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + hc_copy + " = call ptr @memcpy(ptr " + hc_heap + ", ptr " + hc_reg + ", i64 16)")
            return hc_heap
            
        if node.name == "str_append":
            ap_arg := nodes[node.left_id + 0]
            ap_target := nodes[ap_arg.left_id + 0]
            temp_counter += 1
            ap_tp := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ap_tp + " = load ptr, ptr " + var_ref(ap_target.name) + ", align 8")
            ap_add_arg := nodes[ap_arg.right_id + 0]
            ap_add_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, ap_add_arg.left_id)
            temp_counter += 1
            ap_add_ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ap_add_ptr_f + " = getelementptr inbounds %struct.string, ptr " + ap_add_reg + ", i32 0, i32 0")
            temp_counter += 1
            ap_add_ptr := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ap_add_ptr + " = load ptr, ptr " + ap_add_ptr_f + ", align 8")
            temp_counter += 1
            ap_add_len_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ap_add_len_f + " = getelementptr inbounds %struct.string, ptr " + ap_add_reg + ", i32 0, i32 1")
            temp_counter += 1
            ap_add_len := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ap_add_len + " = load i64, ptr " + ap_add_len_f + ", align 8")
            emit(ir_output, "    call void @__zk_str_append_realloc(ptr " + ap_tp + ", ptr " + ap_add_ptr + ", i64 " + ap_add_len + ")")
            return ""
            
        if node.name == "str_substr":
            sub_arg := nodes[node.left_id + 0]
            str_expr_id := sub_arg.left_id
            str_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, str_expr_id)
            start_arg := nodes[sub_arg.right_id + 0]
            start_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, start_arg.left_id)
            len_arg := nodes[start_arg.right_id + 0]
            len_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, len_arg.left_id)
            
            temp_counter += 1
            ptr_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.string, ptr " + str_reg + ", i32 0, i32 0")
            temp_counter += 1
            ptr_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_val + " = load ptr, ptr " + ptr_f + ", align 8")
            temp_counter += 1
            len_f := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_f + " = getelementptr inbounds %struct.string, ptr " + str_reg + ", i32 0, i32 1")
            temp_counter += 1
            len_val := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + len_val + " = load i64, ptr " + len_f + ", align 8")
            
            temp_counter += 1
            res_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + res_reg + " = call ptr @__zk_str_substr(ptr " + ptr_val + ", i64 " + len_val + ", i64 " + start_reg + ", i64 " + len_reg + ")")
            return res_reg
            
        if node.name == "exit_code":
            ext_arg := nodes[node.left_id + 0]
            c_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, ext_arg.left_id)
            emit(ir_output, "    call void @__zk_exit(i64 " + c_reg + ")")
            return ""
            
        if node.name == "vec_contains":
            vc_arg := nodes[node.left_id + 0]
            vec_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, vc_arg.left_id)
            target_arg := nodes[vc_arg.right_id + 0]
            target_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, target_arg.left_id)
            temp_counter += 1
            vc_res := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + vc_res + " = call i64 @__zk_vec_contains(ptr " + vec_reg + ", ptr " + target_reg + ")")
            return vc_res
            
        model_id := -1
        k := 0
        sz := list_size(nodes)
        while k < sz:
            n := nodes[k + 0]
            if n.kind == "MODEL" and n.name == node.name:
                model_id = n.id
                break
            k += 1
            
        if model_id != -1:
            model_node := nodes[model_id + 0]
            temp_counter += 1
            struct_reg: string := "%t" + to_text(temp_counter)
            m_size := model_byte_size(nodes, model_node.name)
            emit(ir_output, "    " + struct_reg + " = call ptr @malloc(i64 " + to_text(m_size) + ")")
            
            field_idx := 0
            curr_field := model_node.right_id
            while curr_field != -1:
                field_node := nodes[curr_field + 0]
                
                match_arg_val: string := ""
                curr_arg := node.left_id
                while curr_arg != -1:
                    marg_node := nodes[curr_arg + 0]
                    if marg_node.name == field_node.name:
                        match_arg_val = generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, marg_node.left_id)
                        break
                    curr_arg = marg_node.right_id
                    
                temp_counter += 1
                field_ptr: string := "%t" + to_text(temp_counter)
                emit(ir_output, "    " + field_ptr + " = getelementptr inbounds %struct." + model_node.name + ", ptr " + struct_reg + ", i32 0, i32 " + to_text(field_idx))
                
                if field_node.op == "string":
                    if match_arg_val != "":
                        temp_counter += 1
                        s_ptr_f: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + s_ptr_f + " = getelementptr inbounds %struct.string, ptr " + match_arg_val + ", i32 0, i32 0")
                        temp_counter += 1
                        s_ptr: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + s_ptr + " = load ptr, ptr " + s_ptr_f + ", align 8")
                        
                        temp_counter += 1
                        s_len_f: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + s_len_f + " = getelementptr inbounds %struct.string, ptr " + match_arg_val + ", i32 0, i32 1")
                        temp_counter += 1
                        s_len: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + s_len + " = load i64, ptr " + s_len_f + ", align 8")
                        
                        temp_counter += 1
                        dest_ptr_f: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + dest_ptr_f + " = getelementptr inbounds %struct.string, ptr " + field_ptr + ", i32 0, i32 0")
                        emit(ir_output, "    store ptr " + s_ptr + ", ptr " + dest_ptr_f + ", align 8")
                        
                        temp_counter += 1
                        dest_len_f: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + dest_len_f + " = getelementptr inbounds %struct.string, ptr " + field_ptr + ", i32 0, i32 1")
                        emit(ir_output, "    store i64 " + s_len + ", ptr " + dest_len_f + ", align 8")
                    else:
                        temp_counter += 1
                        dest_ptr_f: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + dest_ptr_f + " = getelementptr inbounds %struct.string, ptr " + field_ptr + ", i32 0, i32 0")
                        emit(ir_output, "    store ptr null, ptr " + dest_ptr_f + ", align 8")
                        temp_counter += 1
                        dest_len_f: string := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + dest_len_f + " = getelementptr inbounds %struct.string, ptr " + field_ptr + ", i32 0, i32 1")
                        emit(ir_output, "    store i64 0, ptr " + dest_len_f + ", align 8")
                else:
                    if match_arg_val != "":
                        emit(ir_output, "    store i64 " + match_arg_val + ", ptr " + field_ptr + ", align 8")
                    else:
                        emit(ir_output, "    store i64 0, ptr " + field_ptr + ", align 8")
                        
                field_idx += 1
                curr_field = field_node.right_id
                
            return struct_reg
            
        fn_name := node.name
        if fn_name == "main":
            fn_name = "__zk_user_main"
        callee_param: int := -1
        kp := 0
        szp := list_size(nodes)
        while kp < szp:
            n := nodes[kp + 0]
            if n.kind == "FN" and n.name == node.name:
                callee_param = n.left_id
                break
            kp += 1
        args_str: string := ""
        curr_arg := node.left_id
        while curr_arg != -1:
            fnarg_node := nodes[curr_arg + 0]
            arg_val_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, fnarg_node.left_id)
            
            param_is_ref_int := false
            if callee_param != -1:
                pnode := nodes[callee_param + 0]
                p_norm_type := pnode.op
                if text_length(p_norm_type) > 6 and char_at(p_norm_type, 6) == 91:
                    p_norm_type = "vector"
                if pnode.val_int == 1 and p_norm_type == "int":
                    param_is_ref_int = true
                callee_param = pnode.right_id
            
            # Type resolution
            arg_type_str: string := "i64"
            arg_expr := nodes[fnarg_node.left_id + 0]
            arg_type := get_node_type(nodes, var_allocs, var_types, fnarg_node.left_id)
            if param_is_ref_int:
                arg_type_str = "ptr"
                if arg_expr.kind == "VAR":
                    if is_param_ref_int(arg_expr.name, var_allocs, var_types):
                        temp_counter += 1
                        paddr_reg := "%t" + to_text(temp_counter)
                        emit(ir_output, "    " + paddr_reg + " = load ptr, ptr " + var_ref(arg_expr.name) + ", align 8")
                        arg_val_reg = paddr_reg
                    else:
                        arg_val_reg = var_ref(arg_expr.name)
            elif arg_type == "ptr" or arg_type == "string" or arg_type == "vector":
                arg_type_str = "ptr"
            elif is_model_type(nodes, arg_type):
                arg_type_str = "ptr"
            elif arg_expr.kind == "CALL":
                if arg_expr.name == "c_str" or arg_expr.name == "read_file" or arg_expr.name == "addr_of" or arg_expr.name == "str_heap_copy":
                    arg_type_str = "ptr"
                elif arg_expr.name == "vector":
                    arg_type_str = "ptr"
                    
            if args_str == "":
                args_str = arg_type_str + " "
                args_str = args_str + arg_val_reg
            else:
                args_str = args_str + ", "
                args_str = args_str + arg_type_str
                args_str = args_str + " "
                args_str = args_str + arg_val_reg
            curr_arg = fnarg_node.right_id
            
        temp_counter += 1
        reg := "%t" + to_text(temp_counter)
        if is_user_fn(fn_name) == 1:
            temp_counter += 1
            fptr_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + fptr_reg + " = load ptr, ptr @__zk_fn_table_" + fn_name + ", align 8")
            emit(ir_output, "    " + reg + " = call i64 " + fptr_reg + "(" + args_str + ")")
        else:
            emit(ir_output, "    " + reg + " = call i64 @" + fn_name + "(" + args_str + ")")
        
        fn_ret_type: string := "int"
        k_c := 0
        sz_c := list_size(nodes)
        while k_c < sz_c:
            n := nodes[k_c + 0]
            if n.kind == "FN" and n.name == fn_name:
                fn_ret_type = n.op
                break
            k_c += 1
        if is_model_type(nodes, fn_name):
            fn_ret_type = fn_name
            
        if fn_ret_type == "string" or fn_ret_type == "vector" or is_model_type(nodes, fn_ret_type):
            temp_counter += 1
            ptr_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_reg + " = inttoptr i64 " + reg + " to ptr")
            return ptr_reg
        else:
            return reg
    elif node.kind == "MEMBER":
        parent_node := nodes[node.left_id + 0]
        model_name: string := ""
        parent_ptr_reg: string := ""
        
        if parent_node.kind == "CALL":
            fn_ret_type: string := "int"
            k := 0
            sz := list_size(nodes)
            while k < sz:
                n := nodes[k + 0]
                if n.kind == "FN" and n.name == parent_node.name:
                    fn_ret_type = n.op
                    break
                k += 1
            if is_model_type(nodes, parent_node.name):
                fn_ret_type = parent_node.name
            model_name = fn_ret_type
            parent_ptr_reg = generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        elif parent_node.kind == "INDEX":
            vec_var_node := nodes[parent_node.left_id + 0]
            vec_var_name := vec_var_node.name
            model_name = find_var_model_type(nodes, vec_var_name)
            parent_ptr_reg = generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        else:
            parent_var_name := parent_node.name
            model_name = find_var_model_type(nodes, parent_var_name)
            temp_counter += 1
            ptr_load_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_load_reg + " = load ptr, ptr %" + parent_var_name + ", align 8")
            parent_ptr_reg = ptr_load_reg
            
        field_idx := find_field_index(nodes, model_name, node.name)
        
        temp_counter += 1
        f_ptr: string := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + f_ptr + " = getelementptr inbounds %struct." + model_name + ", ptr " + parent_ptr_reg + ", i32 0, i32 " + to_text(field_idx))
        
        field_type: string := "int"
        model_id := -1
        mk_f := 0
        msz_f := list_size(nodes)
        while mk_f < msz_f:
            n := nodes[mk_f + 0]
            if n.kind == "MODEL" and n.name == model_name:
                model_id = n.id
                break
            mk_f += 1
        if model_id != -1:
            m_node := nodes[model_id + 0]
            curr_field := m_node.right_id
            while curr_field != -1:
                f_node := nodes[curr_field + 0]
                if f_node.name == node.name:
                    field_type = f_node.op
                    break
                curr_field = f_node.right_id
                
        if field_type == "string" or field_type == "vector":
            return f_ptr
        else:
            temp_counter += 1
            reg: string := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + reg + " = load i64, ptr " + f_ptr + ", align 8")
            return reg
    elif node.kind == "INDEX":
        parent_var_node := nodes[node.left_id + 0]
        parent_var_name := parent_var_node.name
        
        index_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.right_id)
        
        temp_counter += 1
        ptr_f := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + ptr_f + " = getelementptr inbounds %struct.vector, ptr " + var_struct_ref(parent_var_name, var_allocs, var_types, temp_counter, ir_output) + ", i32 0, i32 0")
        
        temp_counter += 1
        elem_ptr := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + elem_ptr + " = load ptr, ptr " + ptr_f + ", align 8")
        
        temp_counter += 1
        dest_ptr := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + dest_ptr + " = getelementptr i64, ptr " + elem_ptr + ", i64 " + index_reg)
        
        temp_counter += 1
        reg := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + reg + " = load i64, ptr " + dest_ptr + ", align 8")
        
        vec_elem_type := find_var_model_type(nodes, parent_var_name)
        if parent_var_name == "sys_args":
            vec_elem_type = "string"
        if vec_elem_type == "string":
            temp_counter += 1
            ptr_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_reg + " = inttoptr i64 " + reg + " to ptr")
            return ptr_reg
        if is_model_type(nodes, vec_elem_type):
            temp_counter += 1
            ptr_reg := "%t" + to_text(temp_counter)
            emit(ir_output, "    " + ptr_reg + " = inttoptr i64 " + reg + " to ptr")
            return ptr_reg
        return reg
    elif node.kind == "IF":
        label_counter += 1
        lbl_id := label_counter
        
        cond_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        
        temp_counter += 1
        cond_i1 := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + cond_i1 + " = icmp ne i64 " + cond_reg + ", 0")
        
        has_else := false
        if node.val_int != -1:
            has_else = true
            
        if has_else:
            emit(ir_output, "    br i1 " + cond_i1 + ", label %if_then_" + to_text(lbl_id) + ", label %if_else_" + to_text(lbl_id))
        else:
            emit(ir_output, "    br i1 " + cond_i1 + ", label %if_then_" + to_text(lbl_id) + ", label %if_merge_" + to_text(lbl_id))
            
        # Then branch
        emit(ir_output, "if_then_" + to_text(lbl_id) + ":")
        generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.right_id)
        emit(ir_output, "    br label %if_merge_" + to_text(lbl_id))
        
        # Else branch
        if has_else:
            emit(ir_output, "if_else_" + to_text(lbl_id) + ":")
            generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.val_int)
            emit(ir_output, "    br label %if_merge_" + to_text(lbl_id))
            
        # Merge block
        emit(ir_output, "if_merge_" + to_text(lbl_id) + ":")
        return ""
    elif node.kind == "WHILE":
        label_counter += 1
        lbl_id := label_counter
        
        emit(ir_output, "    br label %while_cond_" + to_text(lbl_id))
        
        # Cond block
        emit(ir_output, "while_cond_" + to_text(lbl_id) + ":")
        cond_reg := generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.left_id)
        
        temp_counter += 1
        cond_i1 := "%t" + to_text(temp_counter)
        emit(ir_output, "    " + cond_i1 + " = icmp ne i64 " + cond_reg + ", 0")
        emit(ir_output, "    br i1 " + cond_i1 + ", label %while_body_" + to_text(lbl_id) + ", label %while_end_" + to_text(lbl_id))
        
        # Body block
        emit(ir_output, "while_body_" + to_text(lbl_id) + ":")
        list_push(break_stack, lbl_id)
        generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, node.right_id)
        list_pop(break_stack)
        emit(ir_output, "    br label %while_cond_" + to_text(lbl_id))
        
        # End block
        emit(ir_output, "while_end_" + to_text(lbl_id) + ":")
        return ""
    elif node.kind == "BREAK":
        if list_size(break_stack) > 0:
            target := break_stack[list_size(break_stack) - 1]
            emit(ir_output, "    br label %while_end_" + to_text(target))
        return ""
    elif node.kind == "CONTINUE":
        if list_size(break_stack) > 0:
            target := break_stack[list_size(break_stack) - 1]
            emit(ir_output, "    br label %while_cond_" + to_text(target))
        return ""
        
    return ""

fn generate_program_ir(&nodes: vector[ASTNode], root_ids: vector[int]) -> string:
    ir_output: string := ""
    temp_counter := 0
    label_counter := 0
    var_allocs := vector[string]()
    var_types := vector[string]()
    break_stack := vector[int]()
    hoisted_vars := vector[string]()
    
    emit(ir_output, "; ModuleID = 'main'")
    emit(ir_output, "target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128\"")
    emit(ir_output, "target triple = \"x86_64-pc-linux-gnu\"")
    emit(ir_output, "")
    
    clear_user_fns()
    user_fns := vector[string]()
    i_fn := 0
    sz_fn := list_size(root_ids)
    while i_fn < sz_fn:
        id := root_ids[i_fn + 0]
        node := nodes[id + 0]
        if node.kind == "FN" and node.name != "main":
            if not has_var(user_fns, node.name):
                list_push(user_fns, node.name)
                register_user_fn(node.name)
        i_fn += 1
        
    emit(ir_output, "; IFT Table declarations")
    j := 0
    while j < list_size(user_fns):
        fn_name := user_fns[j + 0]
        fn_len := text_length(fn_name)
        emit(ir_output, "@.str_fn_" + fn_name + " = private unnamed_addr constant [" + to_text(fn_len + 1) + " x i8] c\"" + fn_name + "\\00\", align 1")
        emit(ir_output, "@__zk_fn_table_" + fn_name + " = global ptr @" + fn_name + ", align 8")
        j += 1
        
    emit(ir_output, "")
    
    # 1. Output string and vector struct definitions globally
    emit(ir_output, "%struct.string = type { ptr, i64 }")
    emit(ir_output, "%struct.vector = type { ptr, i64, i64 }")
    emit(ir_output, "@sys_args = global %struct.vector zeroinitializer")
    
    # 2. Output string literal constant declarations
    i := 0
    size := list_size(nodes)
    while i < size:
        node := nodes[i + 0]
        if node.kind == "LITERAL" and node.val_int == 1:
            len := get_llvm_string_len(node.name)
            llvm_len := len + 1
            escaped := escape_llvm_string(node.name)
            emit(ir_output, "@.str_" + to_text(node.id) + " = private unnamed_addr constant [" + to_text(llvm_len) + " x i8] c\"" + escaped + "\\00\", align 1")
        i += 1
        
    # 3. Output model (struct) definitions
    defined_structs := vector[string]()
    i = 0
    size = list_size(root_ids)
    while i < size:
        id := root_ids[i + 0]
        node := nodes[id + 0]
        if node.kind == "MODEL":
            if not vec_contains(defined_structs, node.name):
                list_push(defined_structs, node.name)
                field_types := ""
                curr_field := node.right_id
                while curr_field != -1:
                    field_node := nodes[curr_field + 0]
                    llvm_ft: string := "i64"
                    if field_node.op == "string":
                        llvm_ft = "{ ptr, i64 }"
                    elif field_node.op == "vector":
                        llvm_ft = "{ ptr, i64, i64 }"
                    if field_types == "":
                        field_types = llvm_ft
                    else:
                        field_types = field_types + ", " + llvm_ft
                    curr_field = field_node.right_id
                emit(ir_output, "%struct." + node.name + " = type { " + field_types + " }")
        i += 1
    
    emit(ir_output, "")
    emit(ir_output, "@__zk_fmt_int = private unnamed_addr constant [4 x i8] c\"%ld\\00\", align 1")
    emit(ir_output, "")
    emit(ir_output, "; POSIX system calls and formatting declarations")
    emit(ir_output, "declare i64 @write(i32, ptr, i64)")
    emit(ir_output, "declare i32 @sprintf(ptr, ptr, ...)")
    emit(ir_output, "declare ptr @malloc(i64)")
    emit(ir_output, "declare void @free(ptr)")
    emit(ir_output, "declare ptr @realloc(ptr, i64)")
    emit(ir_output, "declare ptr @memcpy(ptr, ptr, i64)")
    emit(ir_output, "declare i32 @memcmp(ptr, ptr, i64)")
    emit(ir_output, "declare void @exit(i32)")
    emit(ir_output, "declare i64 @strlen(ptr)")
    emit(ir_output, "declare i64 @chdir(ptr)")
    emit(ir_output, "declare i64 @unshare(i64)")
    emit(ir_output, "declare i64 @fork()")
    emit(ir_output, "declare i64 @waitpid(i64, ptr, i32)")
    emit(ir_output, "declare ptr @fopen(ptr, ptr)")
    emit(ir_output, "declare i32 @fseek(ptr, i64, i32)")
    emit(ir_output, "declare i64 @ftell(ptr)")
    emit(ir_output, "declare void @rewind(ptr)")
    emit(ir_output, "declare i64 @fread(ptr, i64, i64, ptr)")
    emit(ir_output, "declare i64 @fwrite(ptr, i64, i64, ptr)")
    emit(ir_output, "declare i32 @fclose(ptr)")
    emit(ir_output, "declare i64 @system(ptr)")
    emit(ir_output, "declare i32 @access(ptr, i32)")
    emit(ir_output, "declare i32 @remove(ptr)")
    emit(ir_output, "declare i32 @strcmp(ptr, ptr)")
    emit(ir_output, "")
    
    # 4. Add standard runtime functions
    emit(ir_output, "; Standard Library Print Error")
    emit(ir_output, "define i64 @print_err(ptr %str_val) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %str = alloca ptr, align 8")
    emit(ir_output, "    store ptr %str_val, ptr %str, align 8")
    emit(ir_output, "    %t1 = load ptr, ptr %str, align 8")
    emit(ir_output, "    %t2 = getelementptr inbounds %struct.string, ptr %t1, i32 0, i32 0")
    emit(ir_output, "    %t3 = load ptr, ptr %t2, align 8")
    emit(ir_output, "    %t4 = getelementptr inbounds %struct.string, ptr %t1, i32 0, i32 1")
    emit(ir_output, "    %t5 = load i64, ptr %t4, align 8")
    emit(ir_output, "    %unused1 = call i64 @write(i32 2, ptr %t3, i64 %t5)")
    emit(ir_output, "    %nl = alloca [1 x i8], align 1")
    emit(ir_output, "    store i8 10, ptr %nl, align 1")
    emit(ir_output, "    %unused2 = call i64 @write(i32 2, ptr %nl, i64 1)")
    emit(ir_output, "    ret i64 0")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library Print String")
    emit(ir_output, "define void @__zk_print_string(ptr %str, i64 %len) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %unused1 = call i64 @write(i32 1, ptr %str, i64 %len)")
    emit(ir_output, "    %nl = alloca [1 x i8], align 1")
    emit(ir_output, "    store i8 10, ptr %nl, align 1")
    emit(ir_output, "    %unused2 = call i64 @write(i32 1, ptr %nl, i64 1)")
    emit(ir_output, "    ret void")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library Print Integer")
    emit(ir_output, "define void @__zk_print_int(i64 %val) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %buf = alloca [32 x i8], align 1")
    emit(ir_output, "    %count = call i32 (ptr, ptr, ...) @sprintf(ptr %buf, ptr @__zk_fmt_int, i64 %val)")
    emit(ir_output, "    %len = sext i32 %count to i64")
    emit(ir_output, "    %unused1 = call i64 @write(i32 1, ptr %buf, i64 %len)")
    emit(ir_output, "    %nl = alloca [1 x i8], align 1")
    emit(ir_output, "    store i8 10, ptr %nl, align 1")
    emit(ir_output, "    %unused2 = call i64 @write(i32 1, ptr %nl, i64 1)")
    emit(ir_output, "    ret void")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library String Concatenation")
    emit(ir_output, "define ptr @__zk_str_concat(ptr %str1, i64 %len1, ptr %str2, i64 %len2) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %total = add i64 %len1, %len2")
    emit(ir_output, "    %total_null = add i64 %total, 1")
    emit(ir_output, "    %buf = call ptr @malloc(i64 %total_null)")
    emit(ir_output, "    %unused1 = call ptr @memcpy(ptr %buf, ptr %str1, i64 %len1)")
    emit(ir_output, "    %offset = getelementptr i8, ptr %buf, i64 %len1")
    emit(ir_output, "    %unused2 = call ptr @memcpy(ptr %offset, ptr %str2, i64 %len2)")
    emit(ir_output, "    %null_ptr = getelementptr i8, ptr %buf, i64 %total")
    emit(ir_output, "    store i8 0, ptr %null_ptr, align 1")
    emit(ir_output, "    ret ptr %buf")
    emit(ir_output, "}")
    emit(ir_output, "")
    emit(ir_output, "; Append: grow string struct in place via realloc (avoids quadratic leak)")
    emit(ir_output, "define void @__zk_str_append_realloc(ptr %str, ptr %add, i64 %addlen) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %p_f = getelementptr inbounds %struct.string, ptr %str, i32 0, i32 0")
    emit(ir_output, "    %old = load ptr, ptr %p_f, align 8")
    emit(ir_output, "    %l_f = getelementptr inbounds %struct.string, ptr %str, i32 0, i32 1")
    emit(ir_output, "    %len = load i64, ptr %l_f, align 8")
    emit(ir_output, "    %total = add i64 %len, %addlen")
    emit(ir_output, "    %cap2 = mul i64 %total, 2")
    emit(ir_output, "    %alloc = add i64 %cap2, 1")
    emit(ir_output, "    %p1 = ptrtoint ptr %old to i64")
    emit(ir_output, "    %is_heap = icmp uge i64 %p1, 8388608")
    emit(ir_output, "    br i1 %is_heap, label %do_realloc, label %do_malloc")
    emit(ir_output, "do_malloc:")
    emit(ir_output, "    %buf_m = call ptr @malloc(i64 %alloc)")
    emit(ir_output, "    %mcopy = call ptr @memcpy(ptr %buf_m, ptr %old, i64 %len)")
    emit(ir_output, "    br label %after_alloc")
    emit(ir_output, "do_realloc:")
    emit(ir_output, "    %buf_r = call ptr @realloc(ptr %old, i64 %alloc)")
    emit(ir_output, "    br label %after_alloc")
    emit(ir_output, "after_alloc:")
    emit(ir_output, "    %buf = phi ptr [ %buf_m, %do_malloc ], [ %buf_r, %do_realloc ]")
    emit(ir_output, "    %off = getelementptr i8, ptr %buf, i64 %len")
    emit(ir_output, "    %acopy = call ptr @memcpy(ptr %off, ptr %add, i64 %addlen)")
    emit(ir_output, "    %nl = getelementptr i8, ptr %buf, i64 %total")
    emit(ir_output, "    store i8 0, ptr %nl, align 1")
    emit(ir_output, "    store ptr %buf, ptr %p_f, align 8")
    emit(ir_output, "    store i64 %total, ptr %l_f, align 8")
    emit(ir_output, "    ret void")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library Vector Push")
    emit(ir_output, "define void @__zk_vector_push(ptr %vec, i64 %elem) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %cap_f = getelementptr inbounds %struct.vector, ptr %vec, i32 0, i32 2")
    emit(ir_output, "    %cap = load i64, ptr %cap_f, align 8")
    emit(ir_output, "    %sz_f = getelementptr inbounds %struct.vector, ptr %vec, i32 0, i32 1")
    emit(ir_output, "    %sz = load i64, ptr %sz_f, align 8")
    emit(ir_output, "    %cond = icmp sge i64 %sz, %cap")
    emit(ir_output, "    br i1 %cond, label %grow, label %insert")
    emit(ir_output, "grow:")
    emit(ir_output, "    %is_zero = icmp eq i64 %cap, 0")
    emit(ir_output, "    %new_cap_cand = mul i64 %cap, 2")
    emit(ir_output, "    %new_cap = select i1 %is_zero, i64 4, i64 %new_cap_cand")
    emit(ir_output, "    store i64 %new_cap, ptr %cap_f, align 8")
    emit(ir_output, "    %alloc_sz = mul i64 %new_cap, 8")
    emit(ir_output, "    %elem_ptr_f = getelementptr inbounds %struct.vector, ptr %vec, i32 0, i32 0")
    emit(ir_output, "    %elem_ptr = load ptr, ptr %elem_ptr_f, align 8")
    emit(ir_output, "    %new_elem_ptr = call ptr @realloc(ptr %elem_ptr, i64 %alloc_sz)")
    emit(ir_output, "    store ptr %new_elem_ptr, ptr %elem_ptr_f, align 8")
    emit(ir_output, "    br label %insert")
    emit(ir_output, "insert:")
    emit(ir_output, "    %elem_ptr_f2 = getelementptr inbounds %struct.vector, ptr %vec, i32 0, i32 0")
    emit(ir_output, "    %elem_ptr2 = load ptr, ptr %elem_ptr_f2, align 8")
    emit(ir_output, "    %dest_ptr = getelementptr i64, ptr %elem_ptr2, i64 %sz")
    emit(ir_output, "    store i64 %elem, ptr %dest_ptr, align 8")
    emit(ir_output, "    %new_sz = add i64 %sz, 1")
    emit(ir_output, "    store i64 %new_sz, ptr %sz_f, align 8")
    emit(ir_output, "    ret void")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library Character Reader")
    emit(ir_output, "define i64 @__zk_char_at(ptr %str, i64 %idx) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %ptr = getelementptr i8, ptr %str, i64 %idx")
    emit(ir_output, "    %val = load i8, ptr %ptr, align 1")
    emit(ir_output, "    %res = zext i8 %val to i64")
    emit(ir_output, "    ret i64 %res")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library String Equality")
    emit(ir_output, "define i64 @__zk_str_eq(ptr %a, i64 %alen, ptr %b, i64 %blen) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %leneq = icmp eq i64 %alen, %blen")
    emit(ir_output, "    br i1 %leneq, label %check_empty, label %not_equal")
    emit(ir_output, "check_empty:")
    emit(ir_output, "    %is_empty = icmp eq i64 %alen, 0")
    emit(ir_output, "    br i1 %is_empty, label %equal, label %check")
    emit(ir_output, "check:")
    emit(ir_output, "    %cmpres = call i32 @memcmp(ptr %a, ptr %b, i64 %alen)")
    emit(ir_output, "    %content_eq = icmp eq i32 %cmpres, 0")
    emit(ir_output, "    %res = zext i1 %content_eq to i64")
    emit(ir_output, "    ret i64 %res")
    emit(ir_output, "equal:")
    emit(ir_output, "    ret i64 1")
    emit(ir_output, "not_equal:")
    emit(ir_output, "    ret i64 0")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library Character Classification")
    emit(ir_output, "define i64 @__zk_is_alpha_char(i64 %c) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %upper = icmp sge i64 %c, 65")
    emit(ir_output, "    %upper2 = icmp sle i64 %c, 90")
    emit(ir_output, "    %is_upper = and i1 %upper, %upper2")
    emit(ir_output, "    %lower = icmp sge i64 %c, 97")
    emit(ir_output, "    %lower2 = icmp sle i64 %c, 122")
    emit(ir_output, "    %is_lower = and i1 %lower, %lower2")
    emit(ir_output, "    %alpha = or i1 %is_upper, %is_lower")
    emit(ir_output, "    %underscore = icmp eq i64 %c, 95")
    emit(ir_output, "    %ok = or i1 %alpha, %underscore")
    emit(ir_output, "    %res = zext i1 %ok to i64")
    emit(ir_output, "    ret i64 %res")
    emit(ir_output, "}")
    emit(ir_output, "")
    emit(ir_output, "define i64 @__zk_is_digit_char(i64 %c) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %lo = icmp sge i64 %c, 48")
    emit(ir_output, "    %hi = icmp sle i64 %c, 57")
    emit(ir_output, "    %ok = and i1 %lo, %hi")
    emit(ir_output, "    %res = zext i1 %ok to i64")
    emit(ir_output, "    ret i64 %res")
    emit(ir_output, "}")
    emit(ir_output, "")
    emit(ir_output, "define i64 @__zk_is_space_char(i64 %c) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %sp = icmp eq i64 %c, 32")
    emit(ir_output, "    %tb = icmp eq i64 %c, 9")
    emit(ir_output, "    %vt = icmp eq i64 %c, 11")
    emit(ir_output, "    %ff = icmp eq i64 %c, 12")
    emit(ir_output, "    %cr = icmp eq i64 %c, 13")
    emit(ir_output, "    %a = or i1 %sp, %tb")
    emit(ir_output, "    %b = or i1 %a, %vt")
    emit(ir_output, "    %tmp3 = or i1 %b, %ff")
    emit(ir_output, "    %tmp4 = or i1 %tmp3, %cr")
    emit(ir_output, "    %res = zext i1 %tmp4 to i64")
    emit(ir_output, "    ret i64 %res")
    emit(ir_output, "}")
    emit(ir_output, "")
    emit(ir_output, "; Standard Library Char To String")
    emit(ir_output, "define ptr @__zk_char_to_string(i64 %c) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %buf = call ptr @malloc(i64 2)")
    emit(ir_output, "    %b = trunc i64 %c to i8")
    emit(ir_output, "    store i8 %b, ptr %buf, align 1")
    emit(ir_output, "    %n = getelementptr i8, ptr %buf, i64 1")
    emit(ir_output, "    store i8 0, ptr %n, align 1")
    emit(ir_output, "    %structp = call ptr @malloc(i64 16)")
    emit(ir_output, "    %dp = getelementptr inbounds %struct.string, ptr %structp, i32 0, i32 0")
    emit(ir_output, "    store ptr %buf, ptr %dp, align 8")
    emit(ir_output, "    %dl = getelementptr inbounds %struct.string, ptr %structp, i32 0, i32 1")
    emit(ir_output, "    store i64 1, ptr %dl, align 8")
    emit(ir_output, "    ret ptr %structp")
    emit(ir_output, "}")
    emit(ir_output, "")
    emit(ir_output, "; Standard Library String Substring")
    emit(ir_output, "define ptr @__zk_str_substr(ptr %data, i64 %len, i64 %start, i64 %count) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %inb = icmp slt i64 %start, %len")
    emit(ir_output, "    %pos_ok = icmp sge i64 %start, 0")
    emit(ir_output, "    %ok = and i1 %inb, %pos_ok")
    emit(ir_output, "    br i1 %ok, label %do_sub, label %empty")
    emit(ir_output, "do_sub:")
    emit(ir_output, "    %avail = sub i64 %len, %start")
    emit(ir_output, "    %cnt_le = icmp slt i64 %count, %avail")
    emit(ir_output, "    %n = select i1 %cnt_le, i64 %count, i64 %avail")
    emit(ir_output, "    %pos_n = icmp sgt i64 %n, 0")
    emit(ir_output, "    br i1 %pos_n, label %copy, label %empty")
    emit(ir_output, "copy:")
    emit(ir_output, "    %total_null = add i64 %n, 1")
    emit(ir_output, "    %buf = call ptr @malloc(i64 %total_null)")
    emit(ir_output, "    %src = getelementptr i8, ptr %data, i64 %start")
    emit(ir_output, "    %unused1 = call ptr @memcpy(ptr %buf, ptr %src, i64 %n)")
    emit(ir_output, "    %nul = getelementptr i8, ptr %buf, i64 %n")
    emit(ir_output, "    store i8 0, ptr %nul, align 1")
    emit(ir_output, "    %structp = call ptr @malloc(i64 16)")
    emit(ir_output, "    %dp = getelementptr inbounds %struct.string, ptr %structp, i32 0, i32 0")
    emit(ir_output, "    store ptr %buf, ptr %dp, align 8")
    emit(ir_output, "    %dl = getelementptr inbounds %struct.string, ptr %structp, i32 0, i32 1")
    emit(ir_output, "    store i64 %n, ptr %dl, align 8")
    emit(ir_output, "    ret ptr %structp")
    emit(ir_output, "empty:")
    emit(ir_output, "    %buf2 = call ptr @malloc(i64 1)")
    emit(ir_output, "    store i8 0, ptr %buf2, align 1")
    emit(ir_output, "    %structp2 = call ptr @malloc(i64 16)")
    emit(ir_output, "    %dp2 = getelementptr inbounds %struct.string, ptr %structp2, i32 0, i32 0")
    emit(ir_output, "    store ptr %buf2, ptr %dp2, align 8")
    emit(ir_output, "    %dl2 = getelementptr inbounds %struct.string, ptr %structp2, i32 0, i32 1")
    emit(ir_output, "    store i64 0, ptr %dl2, align 8")
    emit(ir_output, "    ret ptr %structp2")
    emit(ir_output, "}")
    emit(ir_output, "")
    emit(ir_output, "; Standard Library Exit")
    emit(ir_output, "define void @__zk_exit(i64 %code) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %c = trunc i64 %code to i32")
    emit(ir_output, "    call void @exit(i32 %c)")
    emit(ir_output, "    ret void")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    emit(ir_output, "; Standard Library Vector Contains")
    emit(ir_output, "define i64 @__zk_vec_contains(ptr %vec, ptr %target) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %sz_f = getelementptr inbounds %struct.vector, ptr %vec, i32 0, i32 1")
    emit(ir_output, "    %sz = load i64, ptr %sz_f, align 8")
    emit(ir_output, "    %data_f = getelementptr inbounds %struct.vector, ptr %vec, i32 0, i32 0")
    emit(ir_output, "    %data = load ptr, ptr %data_f, align 8")
    emit(ir_output, "    %tptr_f = getelementptr inbounds %struct.string, ptr %target, i32 0, i32 0")
    emit(ir_output, "    %tptr = load ptr, ptr %tptr_f, align 8")
    emit(ir_output, "    %tlen_f = getelementptr inbounds %struct.string, ptr %target, i32 0, i32 1")
    emit(ir_output, "    %tlen = load i64, ptr %tlen_f, align 8")
    emit(ir_output, "    br label %loop")
    emit(ir_output, "loop:")
    emit(ir_output, "    %i = phi i64 [ 0, %entry ], [ %i_next, %cont ]")
    emit(ir_output, "    %in = icmp slt i64 %i, %sz")
    emit(ir_output, "    br i1 %in, label %body, label %notfound")
    emit(ir_output, "body:")
    emit(ir_output, "    %ep = getelementptr i64, ptr %data, i64 %i")
    emit(ir_output, "    %elem = load i64, ptr %ep, align 8")
    emit(ir_output, "    %es = inttoptr i64 %elem to ptr")
    emit(ir_output, "    %eptr_f = getelementptr inbounds %struct.string, ptr %es, i32 0, i32 0")
    emit(ir_output, "    %eptr = load ptr, ptr %eptr_f, align 8")
    emit(ir_output, "    %elen_f = getelementptr inbounds %struct.string, ptr %es, i32 0, i32 1")
    emit(ir_output, "    %elen = load i64, ptr %elen_f, align 8")
    emit(ir_output, "    %eq = call i64 @__zk_str_eq(ptr %eptr, i64 %elen, ptr %tptr, i64 %tlen)")
    emit(ir_output, "    %isone = icmp eq i64 %eq, 1")
    emit(ir_output, "    br i1 %isone, label %found, label %cont")
    emit(ir_output, "cont:")
    emit(ir_output, "    %i_next = add i64 %i, 1")
    emit(ir_output, "    br label %loop")
    emit(ir_output, "found:")
    emit(ir_output, "    ret i64 1")
    emit(ir_output, "notfound:")
    emit(ir_output, "    ret i64 0")
    emit(ir_output, "}")
    emit(ir_output, "; Standard Library sys_patch_function")
    emit(ir_output, "define i64 @sys_patch_function(ptr %name_struct, ptr %new_ptr) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %p_str_field = getelementptr inbounds %struct.string, ptr %name_struct, i32 0, i32 0")
    emit(ir_output, "    %p_str = load ptr, ptr %p_str_field, align 8")
    
    j_patch := 0
    while j_patch < list_size(user_fns):
        fn_name := user_fns[j_patch + 0]
        emit(ir_output, "    %cmp_" + fn_name + " = call i32 @strcmp(ptr %p_str, ptr @.str_fn_" + fn_name + ")")
        emit(ir_output, "    %is_" + fn_name + " = icmp eq i32 %cmp_" + fn_name + ", 0")
        
        next_label := "cont_" + to_text(j_patch)
        patch_label := "patch_" + to_text(j_patch)
        emit(ir_output, "    br i1 %is_" + fn_name + ", label %" + patch_label + ", label %" + next_label)
        
        emit(ir_output, patch_label + ":")
        emit(ir_output, "    store ptr %new_ptr, ptr @__zk_fn_table_" + fn_name + ", align 8")
        emit(ir_output, "    ret i64 0")
        
        emit(ir_output, next_label + ":")
        j_patch += 1
        
    emit(ir_output, "    ret i64 0")
    emit(ir_output, "}")
    emit(ir_output, "")
    
    # 5. Output user-defined functions globally
    
    has_user_main := false
    emitted_fns := vector[string]()
    i = 0
    size = list_size(root_ids)
    while i < size:
        id := root_ids[i + 0]
        node := nodes[id + 0]
        if node.kind == "FN":
            if has_var(emitted_fns, node.name):
                i += 1
                continue
            list_push(emitted_fns, node.name)
            fn_temp_counter := 0
            fn_label_counter := 0
            fn_vars := vector[string]()
            fn_types := vector[string]()
            fn_break_stack := vector[int]()
            fn_hoisted := vector[string]()
            
            fn_name := node.name
            if fn_name == "main":
                fn_name = "__zk_user_main"
                has_user_main = true
                
            param_decl: string := ""
            curr_param := node.left_id
            while curr_param != -1:
                param_node := nodes[curr_param + 0]
                
                # Determine LLVM type
                p_llvm_type: string := "i64"
                if param_node.op == "string" or param_node.op == "vector" or param_node.val_int == 1:
                    p_llvm_type = "ptr"
                    
                p_val_name := param_node.name + "_val"
                
                if param_decl == "":
                    param_decl = p_llvm_type + " %" + p_val_name
                else:
                    param_decl = param_decl + ", "
                    param_decl = param_decl + p_llvm_type
                    param_decl = param_decl + " %"
                    param_decl = param_decl + p_val_name
                curr_param = param_node.right_id
                
            emit(ir_output, "define i64 @" + fn_name + "(" + param_decl + ") {")
            emit(ir_output, "entry:")
            
            # Allocate local variables for parameters and store values
            curr_param = node.left_id
            while curr_param != -1:
                param_node := nodes[curr_param + 0]
                print_err("  PARAM: " + param_node.name + " OP: " + param_node.op + " VAL_INT: " + to_text(param_node.val_int))
                list_push(fn_vars, param_node.name)
                p_norm_type := param_node.op
                if text_length(p_norm_type) > 6 and char_at(p_norm_type, 6) == 91:
                    p_norm_type = "vector"
                if p_norm_type == "string" or p_norm_type == "vector":
                    list_push(fn_types, str_heap_copy("param:" + p_norm_type))
                elif param_node.val_int == 1 and p_norm_type == "int":
                    list_push(fn_types, str_heap_copy("param_ref:int"))
                else:
                    list_push(fn_types, str_heap_copy(p_norm_type))
                
                p_llvm_type: string := "i64"
                if param_node.op == "string" or param_node.op == "vector" or param_node.val_int == 1:
                    p_llvm_type = "ptr"
                    
                emit(ir_output, "    %" + param_node.name + " = alloca " + p_llvm_type + ", align 8")
                emit(ir_output, "    store " + p_llvm_type + " %" + param_node.name + "_val, ptr %" + param_node.name + ", align 8")
                curr_param = param_node.right_id
                
            fn_hoist_vars := vector[string]()
            fn_hoist_types := vector[string]()
            curr_param = node.left_id
            while curr_param != -1:
                param_node := nodes[curr_param + 0]
                list_push(fn_hoist_vars, param_node.name)
                p_norm_type := param_node.op
                if text_length(p_norm_type) > 6 and char_at(p_norm_type, 6) == 91:
                    p_norm_type = "vector"
                if p_norm_type == "string" or p_norm_type == "vector":
                    list_push(fn_hoist_types, str_heap_copy("param:" + p_norm_type))
                elif param_node.val_int == 1 and p_norm_type == "int":
                    list_push(fn_hoist_types, str_heap_copy("param_ref:int"))
                else:
                    list_push(fn_hoist_types, str_heap_copy(p_norm_type))
                curr_param = param_node.right_id

            hoist_var_allocas(nodes, fn_hoist_vars, fn_hoist_types, ir_output, node.right_id)

            k_h := 0
            while k_h < list_size(fn_hoist_vars):
                hoist_name := fn_hoist_vars[k_h + 0]
                list_push(fn_hoisted, str_heap_copy(hoist_name))
                k_h += 1
            generate_node_ir(nodes, ir_output, fn_temp_counter, fn_label_counter, fn_vars, fn_types, fn_break_stack, fn_hoisted, node.right_id)
            
            emit(ir_output, "    ret i64 0")
            emit(ir_output, "}")
            emit(ir_output, "")
        i += 1
    
    # 6. Main program logic entrypoint
    emit(ir_output, "define i32 @main(i32 %argc, ptr %argv) {")
    emit(ir_output, "entry:")
    emit(ir_output, "    %argc64 = sext i32 %argc to i64")
    emit(ir_output, "    %nargs = sub i64 %argc64, 1")
    emit(ir_output, "    %data = alloca i64, i64 %argc64, align 8")
    emit(ir_output, "    %strs = alloca %struct.string, i64 %argc64, align 8")
    emit(ir_output, "    br label %sys_args_init")
    emit(ir_output, "sys_args_init:")
    emit(ir_output, "    %sa_i = phi i64 [ 0, %entry ], [ %sa_next, %sa_cont ]")
    emit(ir_output, "    %sa_in = icmp slt i64 %sa_i, %nargs")
    emit(ir_output, "    br i1 %sa_in, label %sa_body, label %sa_done")
    emit(ir_output, "sa_body:")
    emit(ir_output, "    %sa_argv_i = add i64 %sa_i, 1")
    emit(ir_output, "    %argp = getelementptr ptr, ptr %argv, i64 %sa_argv_i")
    emit(ir_output, "    %arg = load ptr, ptr %argp, align 8")
    emit(ir_output, "    %alen = call i64 @strlen(ptr %arg)")
    emit(ir_output, "    %sp = getelementptr inbounds %struct.string, ptr %strs, i64 %sa_i, i32 0")
    emit(ir_output, "    store ptr %arg, ptr %sp, align 8")
    emit(ir_output, "    %sl = getelementptr inbounds %struct.string, ptr %strs, i64 %sa_i, i32 1")
    emit(ir_output, "    store i64 %alen, ptr %sl, align 8")
    emit(ir_output, "    %spi = ptrtoint ptr %sp to i64")
    emit(ir_output, "    %dpi = getelementptr i64, ptr %data, i64 %sa_i")
    emit(ir_output, "    store i64 %spi, ptr %dpi, align 8")
    emit(ir_output, "    br label %sa_cont")
    emit(ir_output, "sa_cont:")
    emit(ir_output, "    %sa_next = add i64 %sa_i, 1")
    emit(ir_output, "    br label %sys_args_init")
    emit(ir_output, "sa_done:")
    emit(ir_output, "    %vdata_f = getelementptr inbounds %struct.vector, ptr @sys_args, i32 0, i32 0")
    emit(ir_output, "    store ptr %data, ptr %vdata_f, align 8")
    emit(ir_output, "    %vsz_f = getelementptr inbounds %struct.vector, ptr @sys_args, i32 0, i32 1")
    emit(ir_output, "    store i64 %nargs, ptr %vsz_f, align 8")
    emit(ir_output, "    %vcap_f = getelementptr inbounds %struct.vector, ptr @sys_args, i32 0, i32 2")
    emit(ir_output, "    store i64 %nargs, ptr %vcap_f, align 8")
    
    if has_user_main:
        emit(ir_output, "    %unused = call i64 @__zk_user_main()")
        
    i = 0
    size = list_size(root_ids)
    while i < size:
        id := root_ids[i + 0]
        node := nodes[id + 0]
        if node.kind != "FN" and node.kind != "MODEL":
            generate_node_ir(nodes, ir_output, temp_counter, label_counter, var_allocs, var_types, break_stack, hoisted_vars, id)
        i += 1
        
    emit(ir_output, "    ret i32 0")
    emit(ir_output, "}")
    
    return ir_output
