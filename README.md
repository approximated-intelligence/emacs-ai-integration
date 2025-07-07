# Emacs AI Integration, major mode + minor mode + integration of GenAI provider APIs
<img src="https://repository-images.githubusercontent.com/1014713653/0036f9c7-20ac-4647-96c8-2cdecd49221a" style="width:100%; height:auth;">

A comprehensive AI assistant for Emacs with support for multiple providers (OpenAI, Claude, Gemini, Ollama, llama.cpp) and extensive features for code analysis, text editing, and project management.

## Features

- **Multi-provider support**: OpenAI, Claude, Gemini, Ollama, llama.cpp
- **Streaming and non-streaming responses**
- **Code analysis**: explain, fix, review (security, performance, style, bugs)
- **Text editing**: grammar, style, spelling fixes
- **Project context awareness**
- **Session management** with save/load
- **Buffer-to-session association**
- **Integration** with org-mode, magit, lsp-mode, projectile

## Installation

1. Download `ai-integration.el` to your Emacs configuration directory
2. Add to your `.emacs` or `init.el`:

```elisp
(load-file "~/.emacs.d/ai-integration.el")
(require 'ai-integration)
```

## Configuration

### API Keys (Recommended: Environment Variables)

```bash
export OPENAI_API_KEY="your-openai-key-here"
export ANTHROPIC_API_KEY="your-claude-key-here"
export GEMINI_API_KEY="your-gemini-key-here"
```

### Emacs Configuration

```elisp
;; Basic configuration
(setq ai-default-provider "openai")           ; or "claude", "gemini", "ollama", "llama-cpp"
(setq ai-streaming-default t)                 ; Enable streaming by default
(setq ai-auto-associate-buffers t)            ; Auto-associate buffers with sessions

;; Optional: Set API keys in Emacs (less secure than env vars)
(setq ai-openai-api-key "your-key-here")
(setq ai-claude-api-key "your-key-here")
(setq ai-gemini-api-key "your-key-here")

;; Optional: Customize models
(setq ai-openai-model "gpt-4o")
(setq ai-claude-model "claude-sonnet-4-20250514")
(setq ai-gemini-model "gemini-1.5-flash")

;; Optional: Enable minor mode globally
(global-ai-minor-mode 1)
```

### Local AI Providers

For Ollama:
```elisp
(setq ai-ollama-endpoint "http://localhost:11434/api/chat")
(setq ai-ollama-model "llama3.2")
```

For llama.cpp:
```elisp
(setq ai-llama-cpp-endpoint "http://localhost:8080/v1/chat/completions")
(setq ai-llama-cpp-model "llama-3.2")
```

## Quick Start

1. **Start a chat session**: `C-c a RET`
2. **Send code for analysis**: Select region → `C-c a c e r` (explain code region)
3. **Fix text**: Select text → `C-c a t g r` (fix grammar in region)
4. **Quick actions**: `C-c a q` → select action

## Key Bindings

### Main Commands
- `C-c a RET` - Start AI chat
- `C-c a N` - New session
- `C-c a S` - Save session
- `C-c a L` - Load session
- `C-c a P` - Change provider
- `C-c a O/C/G` - Switch to OpenAI/Claude/Gemini
- `C-c a v` - Toggle streaming
- `C-c a k` - Cancel request

### Code Commands (`C-c a c`)
- `e r/b/p/f` - **Explain** region/buffer/point/file
- `f r/b/p/f` - **Fix** code
- `r r/b/p/f` - **Review** code (comprehensive)
- `s r/b/p/f` - **Security** review
- `p r/b/p/f` - **Performance** review
- `y r/b/p/f` - **Style** review
- `b r/b/p/f` - **Bug** review
- `TAB` - Complete at point

### Text Commands (`C-c a t`)
- `s r/b/p/f` - Fix **style**
- `g r/b/p/f` - Fix **grammar**
- `l r/b/p/f` - Fix **spelling**
- `e r/b/p/f` - **Explain** text

### Send Commands (`C-c a s`)
- `r/b/f/p` - Send to existing session
- `R/B/F/P` - Send to new session

### In AI Chat Buffers
- `C-c C-c` - Send input
- `C-c C-v` - Send input (non-streaming)
- `C-c C-t` - Toggle streaming
- `C-c C-r` - Regenerate last response
- `C-c C-k` - Cancel request
- `C-c C-m` - Select model
- `C-c C-y` - Copy last response
- `C-c C-x s` - Set system prompt
- `C-c C-x t` - Use template

## Usage Examples

### Code Analysis
```elisp
;; Select a function and explain it
C-c a c e r

;; Review entire buffer for security issues
C-c a c s b

;; Fix code at point
C-c a c f p
```

### Text Editing
```elisp
;; Fix grammar in selected text
C-c a t g r

;; Improve writing style of paragraph
C-c a t s p

;; Fix spelling in entire buffer
C-c a t l b
```

### Interactive Chat
```elisp
;; Start chat session
C-c a RET

;; In the chat buffer, type your message and press:
C-c C-c    ; Send with streaming
C-c C-v    ; Send without streaming
```

## Advanced Features

### Session Management
- Sessions are automatically associated with source buffers
- Save/load conversations for later reference
- Multiple sessions per buffer supported

### Provider Switching
- Change providers mid-conversation
- Each provider has optimized settings
- Support for local AI models

### Templates and System Prompts
- Use predefined conversation templates
- Set custom system prompts for different roles
- Quick actions for common tasks

## Troubleshooting

### Enable Debug Mode
```elisp
M-x ai-toggle-debug
```

### Test Streaming
```elisp
M-x ai-diagnose-streaming
```

### Check Configuration
```elisp
M-x ai-debug-session-state
```

## Contributing

This project welcomes contributions! Please feel free to:
- Report bugs and issues
- Suggest new features
- Submit pull requests
- Improve documentation

## License

MIT License - see the source file for details.

---

**Note**: This package requires Emacs 27.1+ and active internet connection for cloud AI providers. Local providers (vLLM, Ollama, llama.cpp) work offline once set up.
