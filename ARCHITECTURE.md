# AI Integration Architecture

This document describes the architecture of the AI Integration for Emacs package, designed to help contributors understand the codebase structure and design decisions.

## Overview

The AI Integration package is built around a modular provider system that abstracts different AI services behind a common interface. The architecture emphasizes:

- **Provider abstraction**: Clean separation between AI providers
- **Session management**: Persistent conversation state
- **Streaming support**: Real-time response handling
- **Template system**: Reusable prompt patterns
- **Buffer integration**: Seamless Emacs workflow

## Core Components

### 1. Provider System (`ai-provider`)

The heart of the architecture is the provider abstraction:

```elisp
(cl-defstruct ai-provider
  name                ; Display name
  default-model       ; Default model name
  api-key-env-var     ; Environment variable name
  default-endpoint    ; Default API endpoint
  headers-fn          ; Function to generate headers
  data-fn             ; Function to generate request data
  response-parser     ; Function to parse response
  stream-parser       ; Function to parse streaming data
  error-parser)       ; Function to parse errors
```

**Key Files:**
- Provider definitions: Lines 200-400
- Registration: `ai-register-provider`
- Retrieval: `ai-get-provider`

**Adding a New Provider:**
1. Define parser functions (`ai-newprovider-response-parser`, etc.)
2. Create provider struct with `make-ai-provider`
3. Register with `ai-register-provider`

### 2. Session Management (`ai-session`)

Sessions represent individual AI conversations:

```elisp
(cl-defstruct ai-session
  name buffer source-buffer provider model messages created-at associated-buffers)
```

**Key Components:**
- `ai-sessions`: Global list of active sessions
- `ai-buffer-session-map`: Buffer → Session mapping
- `ai-buffer-last-session-map`: Buffer → Last used session mapping

**Session Lifecycle:**
1. `ai-create-session` - Creates new session with buffer
2. `ai-associate-buffer-with-session` - Links source buffers
3. `ai-cleanup-sessions` - Removes dead sessions

### 3. Request/Response System

The package handles both streaming and non-streaming requests through a unified interface:

```elisp
(cl-defstruct ai-stream-context
  buffer response-marker accumulated-text request-object)
```

**Request Flow:**
1. `ai-make-unified-request` - Entry point for all requests
2. `ai-make-curl-request` - HTTP handling via curl subprocess
3. `ai-process-response` - Response parsing and handling
4. `ai-finalize-response` - Cleanup and UI updates

**Streaming Architecture:**
- Uses curl with `-N --no-buffer` flags
- Line-by-line processing for Server-Sent Events
- Real-time UI updates via `ai-stream-chunk`
- Graceful cancellation support

### 4. Template System

Templates provide reusable prompt patterns:

```elisp
(defconst ai-template-mappings
  '(("explain-code" . "Please explain this code:\n\n```%s\n%s\n```")
    ("fix-code" . "Please review and fix any issues in this code:\n\n```%s\n%s\n```")
    ...))
```

**Template Expansion:**
- `ai-define-utility-functions` macro generates functions for each template
- Creates variants for region/buffer/point/file operations
- Automatic language detection for code templates

## File Structure

```
ai-integration.el
├── Package Header (lines 1-50)
├── Configuration (lines 51-200)
├── Provider System (lines 201-500)
├── Core Data Structures (lines 501-600)
├── HTTP/Request Layer (lines 601-900)
├── Session Management (lines 901-1200)
├── UI/Mode Implementation (lines 1201-1500)
├── Utility Functions (lines 1501-1800)
├── Key Bindings (lines 1801-1900)
└── Initialization (lines 1901-2000)
```

## Key Design Patterns

### 1. Provider Pattern

Each AI service implements the same interface:

```elisp
;; Provider-specific implementations
(defun ai-openai-response-parser (data) ...)
(defun ai-claude-response-parser (data) ...)
(defun ai-gemini-response-parser (data) ...)

;; Unified interface
(defun ai-make-unified-request (provider-name model messages streaming)
  (let ((provider (ai-get-provider provider-name)))
    (funcall (ai-provider-response-parser provider) data)))
```

### 2. Macro-Generated Functions

The template system uses macros to generate repetitive functions:

```elisp
(ai-define-utility-functions)
;; Generates:
;; - ai-explain-code-region
;; - ai-explain-code-buffer
;; - ai-explain-code-at-point
;; - ai-explain-code-file
;; ... for each template
```

### 3. State Management

The package maintains several state variables:

```elisp
;; Global state
(defvar ai-sessions nil)
(defvar ai-buffer-session-map (make-hash-table :test 'eq))

;; Buffer-local state
(defvar-local ai-current-session nil)
(defvar-local ai-current-status nil)
(defvar-local ai-streaming-enabled nil)
```

### 4. Error Handling

Comprehensive error handling at multiple levels:

```elisp
;; Provider-level error parsing
(defun ai-openai-error-parser (data) ...)

;; Request-level error handling
(defun ai-handle-request-error (error stream-context) ...)

;; Process-level error handling
(defun ai-get-curl-error-message (process exit-code) ...)
```

## HTTP Layer Architecture

### Request Pipeline

1. **Request Preparation**
   - `ai-make-unified-request` orchestrates the request
   - Provider-specific functions generate headers and data
   - Stream context is created for state management

2. **HTTP Execution**
   - `ai-make-curl-request` spawns curl subprocess
   - Temporary files store request data
   - Process filters handle streaming/non-streaming responses

3. **Response Processing**
   - `ai-process-response` handles both streaming and bulk responses
   - Provider-specific parsers extract content
   - `ai-stream-chunk` updates UI in real-time

### Streaming Implementation

The streaming system uses Server-Sent Events (SSE) parsing:

```elisp
(defun ai-process-stream-line (line stream-context provider-name)
  "Process a single line from streaming response."
  (when (string-prefix-p "data:" line)
    (let ((data-str (substring line 5)))
      (ai-extract-and-stream-content 
       (json-read-from-string data-str) 
       stream-context 
       provider-name))))
```

## UI Integration

### Mode System

The package implements both a major mode and minor mode:

```elisp
(define-derived-mode ai-mode org-mode "AI Chat" ...)
(define-minor-mode ai-minor-mode ...)
```

**Major Mode Features:**
- Org-mode integration for formatting
- Specialized keybindings
- Syntax highlighting for code blocks
- Session-specific behavior

**Minor Mode Features:**
- Global keybindings
- Works in any buffer
- Quick access to AI functions

### Buffer Management

The package maintains multiple buffer types:

1. **AI Chat Buffers**: Interactive conversation interfaces
2. **Source Buffers**: User's working files
3. **Temporary Buffers**: For file operations and exports

## Extension Points

### Adding New Providers

1. **Implement Required Functions:**
   ```elisp
   (defun ai-newprovider-headers-fn (model messages) ...)
   (defun ai-newprovider-data-fn (model messages streaming) ...)
   (defun ai-newprovider-response-parser (data) ...)
   (defun ai-newprovider-stream-parser (json-data) ...)
   (defun ai-newprovider-error-parser (data) ...)
   ```

2. **Register Provider:**
   ```elisp
   (ai-register-provider "newprovider"
     (make-ai-provider
      :name "New Provider"
      :default-model "model-name"
      :headers-fn #'ai-newprovider-headers-fn
      :data-fn #'ai-newprovider-data-fn
      :response-parser #'ai-newprovider-response-parser
      :stream-parser #'ai-newprovider-stream-parser
      :error-parser #'ai-newprovider-error-parser))
   ```

### Adding New Templates

1. **Add to Template Mappings:**
   ```elisp
   (push '("new-template" . "Template text with %s placeholders") 
         ai-template-mappings)
   ```

2. **Regenerate Functions:**
   ```elisp
   (ai-define-utility-functions)
   ```

### Adding New Commands

1. **Create Command Function:**
   ```elisp
   (defun ai-new-command ()
     "Documentation."
     (interactive)
     (ai-with-template "Your prompt here"))
   ```

2. **Add Key Binding:**
   ```elisp
   (define-key ai-prefix-map (kbd "n") 'ai-new-command)
   ```

## Testing and Debugging

### Debug System

The package includes comprehensive debugging:

```elisp
(defun ai-debug (format-string &rest args)
  "Print debug message if debugging is enabled."
  (when ai-debug-enabled
    (apply #'message (concat "AI-DEBUG: " format-string) args)))
```

### Testing Functions

Several functions help with testing:

- `ai-test-provider-selection` - Test provider logic
- `ai-test-session-management` - Test session lifecycle
- `ai-test-streaming` - Interactive streaming test
- `ai-diagnose-streaming` - Diagnose streaming issues

### Error Diagnostics

The package provides diagnostic tools:

- `ai-diagnose-streaming` - Check streaming configuration
- `ai-debug-session-state` - Display current session state
- `ai-get-curl-error-message` - Interpret curl errors

## Performance Considerations

### Memory Management

- Sessions are cleaned up automatically when buffers are killed
- Temporary files are deleted after requests
- Process buffers are killed after completion

### Request Optimization

- Streaming reduces perceived latency
- Request cancellation prevents resource waste
- Connection reuse where possible

### UI Responsiveness

- Non-blocking request handling
- Progressive UI updates during streaming
- Graceful error handling and recovery

## Contributing Guidelines

### Code Style

- Follow existing naming conventions
- Use `ai-` prefix for all public functions
- Document all interactive functions
- Include error handling

### Testing

- Test with multiple providers
- Verify streaming and non-streaming modes
- Check error conditions
- Test session management

### Documentation

- Update docstrings for new functions
- Add examples for complex features
- Update README for user-facing changes
- Update this architecture document for structural changes
