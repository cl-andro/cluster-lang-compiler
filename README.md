# 🚀 Cluster-lang Compiler (Self-Hosted)

Welcome to the official, fully independent, self-hosted compiler repository for the **Cluster programming language**. 

This repository contains the native frontend and driver logic written entirely in pure Cluster-lang. It compiles Cluster-lang source files (`.cl`) directly to native binaries via LLVM IR—with **zero dependencies on Python or G++**.

---

## 🏗️ How it Works

The compiler operates in four stages:
1. **Frontend Parsing**: Resolves grammatical tokens (`lexer.cl`), builds the Abstract Syntax Tree (`parser.cl`), and parses module structures (`ast.cl`).
2. **Intermediate Code Generation (`codegen.cl`)**: Translates AST nodes into optimized text-based **LLVM Intermediate Representation (LLVM IR)**.
3. **Machine Code Emission**: Emits platform-specific machine code (object files) by automatically calling LLVM backend tools (`clang` or `llc`).
4. **Linking**: Links the object files with standard startup wrappers (`libc`) to produce independent native binaries.

---

## 🛠️ Build and Usage Instructions

### 1. Compile the Compiler Natively
To compile this compiler itself from its source code using a pre-existing compiler binary (`compiler.out`):
```bash
./compiler.out main.cl -o compiler.out
```

### 2. Compile a Program
To compile any `.cl` source file into a native executable:
```bash
./compiler.out your_program.cl
```
*This compiles `your_program.cl` and generates the standalone binary executable `your_program.out`.*

---

## 📁 Repository Structure
* `main.cl`: Main compiler orchestrator and CLI driver.
* `codegen.cl`: LLVM IR generator.
* `parser.cl`: Grammatical parser.
* `lexer.cl`: Lexer token generator.
* `ast.cl`: AST node structures.
* `input.cl`: A sandbox program to verify compiler runtime functionality.
* `LICENSE`: Custom license terms.

---

## 🤝 Submitting Modules and Packages
Cluster-lang uses a decentralized package ecosystem. To submit your own module or package to the official registry, please read the [Module Contribution Guide](CONTRIBUTING.md).
