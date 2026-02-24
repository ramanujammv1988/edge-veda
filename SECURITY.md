# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 2.4.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Edge Veda, please report it responsibly. **Do not open a public GitHub issue.**

**Email:** [security@edgeveda.dev](mailto:security@edgeveda.dev)

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Impact assessment (what an attacker could achieve)
- Affected versions (if known)

### Response Timeline

- **Acknowledgement:** Within 48 hours
- **Initial assessment:** Within 5 business days
- **Fix or mitigation:** Depends on severity, typically within 30 days

### Embargo

We ask that you do not publicly disclose the vulnerability until a fix has been released. We will coordinate disclosure timing with you and credit you in the release notes (unless you prefer to remain anonymous).

## Scope

### In Scope

- FFI bindings and native interop (llama.cpp, whisper.cpp, stable-diffusion.cpp)
- Model loading and memory management
- Isolate worker communication
- Platform channel implementations
- Data handling in RAG pipeline and embeddings

### Out of Scope

- Third-party model weights (report to the model provider)
- Application-level code in example apps
- Vulnerabilities in Flutter framework itself (report to flutter.dev)
- Social engineering attacks

## Security Best Practices for Users

- Always validate and sanitize user input before passing to LLM inference
- Do not expose raw model outputs to untrusted contexts without filtering
- Keep your Edge Veda dependency updated to the latest supported version
