# 🚀 Cluster-lang Compiler (Self-Hosted)

Welcome to the official, fully independent, self-hosted compiler repository for the **Cluster programming language**. 

This repository contains the native frontend and driver logic written entirely in pure Cluster-lang. It compiles Cluster-lang source files (`.zk`) directly to native binaries via LLVM IR—with **zero dependencies on Python or G++**.

---

## 🏗️ How it Works

The compiler operates in four stages:
1. **Frontend Parsing**: Resolves grammatical tokens (`lexer.zk`), builds the Abstract Syntax Tree (`parser.zk`), and parses module structures (`ast.zk`).
2. **Intermediate Code Generation (`codegen.zk`)**: Translates AST nodes into optimized text-based **LLVM Intermediate Representation (LLVM IR)**.
3. **Machine Code Emission**: Emits platform-specific machine code (object files) by automatically calling LLVM backend tools (`clang` or `llc`).
4. **Linking**: Links the object files with standard startup wrappers (`libc`) to produce independent native binaries.

---

## 🛠️ Build and Usage Instructions

### 1. Compile the Compiler Natively
To compile this compiler itself from its source code using a pre-existing compiler binary (`compiler.out`):
```bash
./compiler.out main.zk -o compiler.out
```

### 2. Compile a Program
To compile any `.zk` source file into a native executable:
```bash
./compiler.out your_program.zk
```
*This compiles `your_program.zk` and generates the standalone binary executable `your_program.out`.*

---

## 📁 Repository Structure
* `main.zk`: Main compiler orchestrator and CLI driver.
* `codegen.zk`: LLVM IR generator.
* `parser.zk`: Grammatical parser.
* `lexer.zk`: Lexer token generator.
* `ast.zk`: AST node structures.
* `input.zk`: A sandbox program to verify compiler runtime functionality.
* `LICENSE`: MIT License.

---

## 🤝 Submitting Modules and Packages
Cluster-lang uses a decentralized package ecosystem. To submit your own module or package to the official registry, please read the [Module Contribution Guide](CONTRIBUTING.md).
