# 📦 Cluster-lang Module Contribution Guide

Welcome! We are excited that you want to contribute to the Cluster-lang package ecosystem. This guide outlines how to format your modules and register them so other developers can install them.

---

## 1. Package Structure
Every Cluster-lang module/package must follow this directory structure:

```text
my-package/
├── package.cl       # Package Manifest
├── README.md        # Description and usage instructions
├── LICENSE          # License file (e.g. MIT, Apache 2.0)
└── src/
    └── my_module.cl # Source code file(s)
```

### Manifest Format (`package.cl`)
The manifest file declares package metadata using standard YAML formatting:
```yaml
name: "cl-http"
version: "1.0.0"
description: "High-performance asynchronous HTTP server stack"
dependencies:
  - "cl-json@0.1.0"
```

---

## 2. Coding Guidelines
* Use clean, self-documenting function names.
* Use double-slash `//` comments for code-level documentation.
* Avoid global mutable state to ensure packages remain safe and predictable under multi-threaded concurrency models.

---

## 3. Submitting to the Registry

To register your package globally so that others can download it via `zkc pkg install <name>`:

1. **Host Your Repository**: Publish your package folder to a public Git repository (GitHub, GitLab, etc.).
2. **Submit a Registry Pull Request**:
   - Go to the official registry repository: `cl-andro/cluster-packages` (or the equivalent package index).
   - Edit the index register `index.json`.
   - Add your package name, version, and Git URL to the index mapping:
     ```json
     "my-package": {
       "versions": {
         "1.0.0": {
           "url": "https://github.com/username/my-package.git",
           "commit": "a1b2c3d4e5f6..."
         }
       }
     }
     ```
3. **Approval**: Once the Pull Request is merged, your package will be globally discoverable and installable!
