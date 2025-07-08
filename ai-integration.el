;;; ai-integration.el --- AI Integration for Emacs -*- lexical-binding: t; indent-tabs-mode: nil; tab-width: 2 -*-
;; Author: Christian Bahls
;; Version: 0.1
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Keywords: ai, chat, openai, claude, gemini, ollama, tools
;; URL: https://github.com/approximated-intelligence/emacs-ai-integration
;;; Commentary:
;; AI Integration provides comprehensive AI assistance in Emacs with support for
;; multiple providers (OpenAI, Claude, Gemini, Ollama, llama.cpp) and extensive
;; features for code analysis, text editing, and project management.
;;
;; Key Features:
;; - Multi-provider support with easy switching
;; - Streaming and non-streaming responses
;; - Code analysis: explain, fix, review (security, performance, style, bugs)
;; - Text editing: grammar, style, spelling fixes
;; - Project context awareness
;; - File and workspace analysis
;; - Session management with save/load
;; - Buffer-to-session association
;; - Integration with org-mode, magit, lsp-mode, projectile
;;
;; Quick Start:
;; 1. Configure your API keys (if you don't want to use the more secure ENV vars):
;;    (setq ai-openai-api-key "your-key-here")
;;    (setq ai-claude-api-key "your-key-here")
;;
;; 2. Start a chat session:
;;    C-c a RET
;;
;; 3. Send code for analysis:
;;    Select region and press C-c a c e r (explain code region)
;;
;; Main Keybindings:
;; - C-c a RET    : Start AI chat
;; - C-c a c      : Code commands prefix
;; - C-c a t      : Text commands prefix
;; - C-c a s      : Send commands prefix
;; - C-c a x      : Context commands prefix
;; - C-c a q      : Quick actions
;;
;; See README for complete documentation.

;;; Code:

(require 'org)

(require 'json)

(require 'cl-lib)

(defgroup ai-integration nil
  "AI Integration for Emacs."
  :group 'applications
  :prefix "ai-"
  :link '(url-link :tag "GitHub" "https://github.com/yourusername/ai-integration"))

(defgroup ai-integration-providers nil
  "AI provider configuration."
  :group 'ai-integration)

(defgroup ai-integration-behavior nil
  "AI behavior configuration."
  :group 'ai-integration)

(defgroup ai-integration-appearance nil
  "AI appearance configuration."
  :group 'ai-integration)

(defcustom ai-debug-enabled nil
  "Enable debug messages for AI integration."
  :type 'boolean
  :group 'ai-integration-behavior)

(defun ai-debug (format-string &rest args)
  "Print debug message if debugging is enabled."
  (when ai-debug-enabled
    (apply #'message (concat "AI-DEBUG: " format-string) args)))

(defcustom ai-default-provider "openai"
  "Default AI provider."
  :type '(choice (const "openai") (const "claude") (const "gemini") (const "ollama") (const "llama-cpp"))
  :group 'ai-integration-providers)

(defcustom ai-openai-api-key nil
  "OpenAI API key."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-openai-model "gpt-4o"
  "Default OpenAI model."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-openai-endpoint "https://api.openai.com/v1/chat/completions"
  "OpenAI API endpoint."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-claude-api-key nil
  "Claude API key."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-claude-model "claude-sonnet-4-20250514"
  "Default Claude model."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-claude-endpoint "https://api.anthropic.com/v1/messages"
  "Claude API endpoint."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-ollama-api-key nil
  "Ollama API key (usually not needed)."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-ollama-model "llama3.2"
  "Default Ollama model."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-ollama-endpoint "http://localhost:11434/api/chat"
  "Ollama API endpoint."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-llama-cpp-api-key nil
  "llama.cpp API key (usually not needed)."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-llama-cpp-model "llama-3.2"
  "Default llama.cpp model."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-llama-cpp-endpoint "http://localhost:8080/v1/chat/completions"
  "llama.cpp API endpoint."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-gemini-api-key nil
  "Gemini API key."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-gemini-model "gemini-1.5-flash"
  "Default Gemini model."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-gemini-endpoint "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
  "Gemini API endpoint (with %s placeholder for model)."
  :type 'string
  :group 'ai-integration-providers)

(defcustom ai-conversation-directory "~/.emacs.d/ai-chat/sessions"
  "Directory for storing conversation files."
  :type 'directory
  :group 'ai-integration-behavior)

(defcustom ai-streaming-default t
  "Default streaming mode for new sessions."
  :type 'boolean
  :group 'ai-integration-behavior)

(defcustom ai-auto-associate-buffers t
  "Automatically associate buffers with chat sessions."
  :type 'boolean
  :group 'ai-integration-behavior)

(defcustom ai-status-indicators
  '((idle . "")
    (requesting . " [Requesting...]")
    (streaming . " [Streaming")  ; Will be completed with progress
    (cancelling . " [Cancelling...]")
    (cancelled . " [Cancelled]")
    (error . " [Error]"))
  "Status indicators for AI sessions."
  :type '(alist :key-type symbol :value-type string)
  :group 'ai-integration-appearance)

(defconst ai-template-mappings
  '(
    ("explain-code" . "Please explain this code:\n\n```%s\n%s\n```")
    ("fix-code" . "Please review and fix any issues in this code:\n\n```%s\n%s\n```")
    ("review-code" . "Please perform a comprehensive code review:\n\n```%s\n%s\n```")
    ("review-security" . "Please review this code for security vulnerabilities:\n\n```%s\n%s\n```")
    ("review-performance" . "Please review this code for performance issues:\n\n```%s\n%s\n```")
    ("review-style" . "Please review this code for style and best practices:\n\n```%s\n%s\n```")
    ("review-bugs" . "Please review this code for potential bugs:\n\n```%s\n%s\n```")
    ("fix-prose-style" . "Please improve the writing style of this text:\n\n%s")
    ("fix-prose-grammar" . "Please fix any grammar errors in this text:\n\n%s")
    ("fix-prose-spelling" . "Please fix any spelling errors in this text:\n\n%s")
    ("explain-text" . "Please explain or analyze this text:\n\n%s"))
  "Mapping of template keys to prompt templates.")

(defcustom ai-file-intro-template "File: %s\n---\n%s\n---\n"
  "Template for introducing file content. %s is replaced with filename and content."
  :type 'string
  :group 'ai-integration-behavior)

(defcustom ai-openai-models
  '("gpt-4o" "gpt-4o-mini" "gpt-4-turbo" "gpt-4" "gpt-3.5-turbo" "o1-preview" "o1-mini")
  "Available OpenAI models."
  :type '(repeat string)
  :group 'ai-integration-providers)

(defcustom ai-claude-models
  '("claude-opus-4-20250514" "claude-sonnet-4-20250514" "claude-3-opus-20240229"
    "claude-3-sonnet-20240229" "claude-3-haiku-20240307")
  "Available Claude models."
  :type '(repeat string)
  :group 'ai-integration-providers)

(defcustom ai-gemini-models
  '("gemini-1.5-pro" "gemini-1.5-flash" "gemini-pro" "gemini-pro-vision")
  "Available Gemini models."
  :type '(repeat string)
  :group 'ai-integration-providers)

(defcustom ai-request-timeout 300
  "Request timeout in seconds."
  :type 'integer
  :group 'ai-integration-behavior)

(defcustom ai-max-tokens 4096
  "Maximum tokens for response."
  :type 'integer
  :group 'ai-integration-behavior)

(defcustom ai-temperature 0.7
  "Temperature for AI responses (0.0 to 1.0)."
  :type 'float
  :group 'ai-integration-behavior)

(cl-defstruct ai-session
  name buffer source-buffer provider model messages created-at associated-buffers)

(cl-defstruct ai-stream-context
  buffer response-marker accumulated-text request-object)

(cl-defstruct ai-provider
  name                ; Display name
  default-model       ; Default model name
  api-key-env-var     ; Environment variable name
  default-endpoint    ; Default API endpoint
  headers-fn          ; Function to generate headers
  data-fn             ; Function to generate request data
  response-parser     ; Function to parse response
  stream-parser       ; Function to parse streaming data
  error-parser)        ; Function to parse errors from provider

(defvar ai-providers (make-hash-table :test 'equal)
  "Registry of AI provider plugins.")

(defvar ai-sessions nil
  "List of all active sessions.")

(defvar ai-buffer-session-map (make-hash-table :test 'eq)
  "Map from buffers to their associated sessions.")

(defvar ai-buffer-last-session-map (make-hash-table :test 'eq)
  "Map from buffers to their last used session.")

(defvar-local ai-current-session nil
  "Current AI session for this buffer.")

(defvar-local ai-current-status nil
  "Current status of the AI session.")

(defvar-local ai-input-history nil
  "Input history for this buffer.")

(defvar-local ai-streaming-enabled nil
  "Streaming mode for this buffer.")

(defvar-local ai-current-stream nil
  "Current stream context for this buffer.")

(defvar-local ai-associated-sessions nil
  "List of AI sessions associated with this buffer.")

(defun ai-associate-buffer-with-session (buffer session)
  "Associate BUFFER with SESSION."
  (when (and buffer session)
    (puthash buffer session ai-buffer-last-session-map)
    (unless (member buffer (ai-session-associated-buffers session))
      (setf (ai-session-associated-buffers session)
            (cons buffer (ai-session-associated-buffers session))))))

(defvar ai-session-buffer-counters (make-hash-table :test 'equal)
  "Hash table to track buffer name counters for each source buffer.")

(defun ai-generate-buffer-name (&optional provider source-buffer force-new)
  "Generate appropriate buffer name for AI session."
  (let* ((provider (or provider ai-default-provider))
         (source-name (if source-buffer
                          (buffer-name source-buffer)
                        "ai"))
         (base-name (format "*%s (%s) " source-name provider)))
    (if force-new
        (generate-new-buffer-name base-name)
      base-name)))

(defun ai-register-provider (name provider)
  "Register PROVIDER under NAME."
  (puthash name provider ai-providers))

(defun ai-get-provider (name)
  "Get provider by NAME."
  (gethash name ai-providers))

(defun ai-get-provider-api-key (provider-name)
  "Get API key for PROVIDER-NAME."
  (let* ((provider (ai-get-provider provider-name))
         (custom-key-var (intern (format "ai-%s-api-key" provider-name)))
         (custom-key (and (boundp custom-key-var) (symbol-value custom-key-var)))
         (env-var (and provider (ai-provider-api-key-env-var provider))))
    (or custom-key
        (and env-var (getenv env-var))
        nil)))

(defun ai-get-provider-model (provider-name)
  "Get default model for PROVIDER-NAME."
  (let* ((provider (ai-get-provider provider-name))
         (custom-model-var (intern (format "ai-%s-model" provider-name)))
         (custom-model (and (boundp custom-model-var) (symbol-value custom-model-var))))
    (or custom-model
        (and provider (ai-provider-default-model provider))
        "unknown")))

(defun ai-get-provider-endpoint (provider-name)
  "Get endpoint for PROVIDER-NAME."
  (let* ((provider (ai-get-provider provider-name))
         (custom-endpoint-var (intern (format "ai-%s-endpoint" provider-name)))
         (custom-endpoint (and (boundp custom-endpoint-var) (symbol-value custom-endpoint-var))))
    (cond
     ((string= provider-name "gemini")
      (ai-get-gemini-endpoint (ai-get-provider-model provider-name)))
     (custom-endpoint custom-endpoint)
     ((and provider (ai-provider-default-endpoint provider))
      (ai-provider-default-endpoint provider))
     (t (error "No endpoint configured for provider %s" provider-name)))))

(defun ai-format-messages (messages)
  "Format MESSAGES for API."
  (mapcar (lambda (msg)
            `((role . ,(plist-get msg :role))
              (content . ,(plist-get msg :content))))
          messages))

(defun ai-openai-response-parser (data)
  "Parse OpenAI response format."
  (let* ((choices (cdr (assoc 'choices data)))
         (message (cdr (assoc 'message (aref choices 0))))
         (content (cdr (assoc 'content message))))
    (or content "No response received")))

(defun ai-openai-stream-parser (json-data)
  "Parse OpenAI streaming chunk."
  (ai-debug "OpenAI parser received: %s" json-data)
  (let ((choices (cdr (assoc 'choices json-data))))
    (ai-debug "OpenAI choices: %s" choices)
    (when choices
      (let* ((delta (cdr (assoc 'delta (aref choices 0))))
             (content (cdr (assoc 'content delta))))
        (ai-debug "OpenAI delta: %s, content: %s" delta content)
        (ai-debug "OpenAI returning content: %s" content)
        content))))

(defun ai-openai-error-parser (data)
  "Parse OpenAI error response."
  (when-let ((error (cdr (assoc 'error data))))
    (format "OpenAI Error: %s" (cdr (assoc 'message error)))))

(defun ai-openai-headers-fn (model messages)
  "Generate headers for OpenAI API."
  (let ((api-key (ai-get-provider-api-key "openai")))
    (unless api-key
      (error "No OpenAI API key found. Set ai-openai-api-key or OPENAI_API_KEY"))
    `(("Authorization" . ,(format "Bearer %s" api-key))
      ("Content-Type" . "application/json"))))

(defun ai-openai-data-fn (model messages streaming)
  "Generate request data for OpenAI API."
  (json-encode `((model . ,model)
                 (messages . ,(ai-format-messages messages))
                 ,@(when streaming '((stream . t))))))

(defun ai-claude-response-parser (data)
  "Parse Claude response format."
  (let ((content (cdr (assoc 'content data))))
    (if (and content (> (length content) 0))
        (cdr (assoc 'text (aref content 0)))
      "No response received")))

(defun ai-claude-stream-parser (json-data)
  "Parse Claude streaming chunk."
  (ai-debug "Claude parser received: %s" json-data)
  (let ((event-type (cdr (assoc 'type json-data))))
    (ai-debug "Claude event type: %s" event-type)
    (when (string= event-type "content_block_delta")
      (let* ((delta (cdr (assoc 'delta json-data)))
             (delta-type (cdr (assoc 'type delta)))
             (content (cdr (assoc 'text delta))))
        (ai-debug "Claude delta: %s, delta-type: %s, content: %s" delta delta-type content)
        (when (string= delta-type "text_delta")
          (ai-debug "Claude returning content: %s" content)
          content)))))

(defun ai-claude-error-parser (data)
  "Parse Claude error response."
  (when-let ((error (cdr (assoc 'error data))))
    (format "Claude Error: %s" (cdr (assoc 'message error)))))

(defun ai-claude-headers-fn (model messages)
  "Generate headers for Claude API."
  (let ((api-key (ai-get-provider-api-key "claude")))
    (unless api-key
      (error "No Claude API key found. Set ai-claude-api-key or ANTHROPIC_API_KEY"))
    `(("x-api-key" . ,api-key)
      ("Content-Type" . "application/json")
      ("anthropic-version" . "2023-06-01"))))

(defun ai-claude-data-fn (model messages streaming)
  "Generate request data for Claude API."
  (json-encode `((model . ,model)
                 (max_tokens . 4096)
                 (messages . ,(ai-format-messages messages))
                 ,@(when streaming '((stream . t))))))

(defun ai-ollama-response-parser (data)
  "Parse Ollama response format."
  (or (cdr (assoc 'content (cdr (assoc 'message data))))
      (cdr (assoc 'response data))
      "No response received"))

(defun ai-ollama-stream-parser (json-data)
  "Parse Ollama streaming chunk."
  (let ((message (cdr (assoc 'message json-data))))
    (when message
      (cdr (assoc 'content message)))))

(defun ai-ollama-error-parser (data)
  "Parse Ollama error response."
  (when-let ((error (cdr (assoc 'error data))))
    (format "Ollama Error: %s" error)))

(defun ai-ollama-headers-fn (model messages)
  "Generate headers for Ollama (no authentication)."
  '(("Content-Type" . "application/json")))

(defun ai-ollama-data-fn (model messages streaming)
  "Generate request data for Ollama API."
  (json-encode `((model . ,model)
                 (messages . ,(ai-format-messages messages))
                 ,@(when streaming '((stream . t))))))

(defun ai-local-headers-fn (model messages)
  "Generate headers for local providers (no authentication)."
  '(("Content-Type" . "application/json")))

(defun ai-gemini-response-parser (data)
  "Parse Gemini response format."
  (let* ((candidates (cdr (assoc 'candidates data)))
         (content (cdr (assoc 'content (aref candidates 0))))
         (parts (cdr (assoc 'parts content)))
         (text (cdr (assoc 'text (aref parts 0)))))
    (or text "No response received")))

(defun ai-gemini-stream-parser (json-data)
  "Parse Gemini streaming chunk."
  nil)

(defun ai-gemini-error-parser (data)
  "Parse Gemini error response."
  (when-let ((error (cdr (assoc 'error data))))
    (format "Gemini Error: %s" (cdr (assoc 'message error)))))

(defun ai-gemini-headers-fn (model messages)
  "Generate headers for Gemini API."
  (let ((api-key (ai-get-provider-api-key "gemini")))
    (unless api-key
      (error "No Gemini API key found. Set ai-gemini-api-key or GEMINI_API_KEY"))
    `(("Content-Type" . "application/json"))))

(defun ai-gemini-data-fn (model messages streaming)
  "Generate request data for Gemini API."
  (let ((contents (mapcar (lambda (msg)
                            `((role . ,(if (string= (plist-get msg :role) "assistant")
                                           "model"
                                         (plist-get msg :role)))
                              (parts . [((text . ,(plist-get msg :content)))])))
                          messages)))
    (json-encode `((contents . ,contents)
                   (generationConfig . ((temperature . 0.7)
                                        (maxOutputTokens . 4096)))))))

(defun ai-get-gemini-endpoint (model)
  "Get Gemini endpoint with MODEL inserted."
  (format ai-gemini-endpoint model))

(ai-register-provider "openai"
  (make-ai-provider
   :name "OpenAI"
   :default-model "gpt-4o"
   :api-key-env-var "OPENAI_API_KEY"
   :default-endpoint "https://api.openai.com/v1/chat/completions"
   :headers-fn #'ai-openai-headers-fn
   :data-fn #'ai-openai-data-fn
   :response-parser #'ai-openai-response-parser
   :stream-parser #'ai-openai-stream-parser
   :error-parser #'ai-openai-error-parser))

(ai-register-provider "claude"
  (make-ai-provider
   :name "Claude"
   :default-model "claude-sonnet-4-20250514"
   :api-key-env-var "ANTHROPIC_API_KEY"
   :default-endpoint "https://api.anthropic.com/v1/messages"
   :headers-fn #'ai-claude-headers-fn
   :data-fn #'ai-claude-data-fn
   :response-parser #'ai-claude-response-parser
   :stream-parser #'ai-claude-stream-parser
   :error-parser #'ai-claude-error-parser))

(ai-register-provider "ollama"
  (make-ai-provider
   :name "Ollama"
   :default-model "llama3.2"
   :api-key-env-var nil
   :default-endpoint "http://localhost:11434/api/chat"
   :headers-fn #'ai-ollama-headers-fn
   :data-fn #'ai-ollama-data-fn
   :response-parser #'ai-ollama-response-parser
   :stream-parser #'ai-ollama-stream-parser
   :error-parser #'ai-ollama-error-parser))

(ai-register-provider "llama-cpp"
  (make-ai-provider
   :name "llama.cpp"
   :default-model "llama-3.2"
   :api-key-env-var nil
   :default-endpoint "http://localhost:8080/v1/chat/completions"
   :headers-fn #'ai-local-headers-fn
   :data-fn #'ai-openai-data-fn        ; OpenAI-compatible
   :response-parser #'ai-openai-response-parser
   :stream-parser #'ai-openai-stream-parser
   :error-parser #'ai-openai-error-parser))

(ai-register-provider "gemini"
  (make-ai-provider
   :name "Gemini"
   :default-model "gemini-1.5-flash"
   :api-key-env-var "GEMINI_API_KEY"
   :default-endpoint nil  ; Dynamic endpoint based on model
   :headers-fn #'ai-gemini-headers-fn
   :data-fn #'ai-gemini-data-fn
   :response-parser #'ai-gemini-response-parser
   :stream-parser #'ai-gemini-stream-parser
   :error-parser #'ai-gemini-error-parser))

(defun ai-make-unified-request (provider-name model messages streaming)
  "Make unified request to PROVIDER-NAME with MODEL and MESSAGES."
  (let* ((provider (ai-get-provider provider-name))
         (endpoint (ai-get-provider-endpoint provider-name))
         (headers (funcall (ai-provider-headers-fn provider) model messages))
         (data (funcall (ai-provider-data-fn provider) model messages streaming))
         (target-buffer (current-buffer))
         (response-marker (with-current-buffer target-buffer (point-max-marker)))
         (stream-context (make-ai-stream-context
                          :buffer target-buffer
                          :response-marker response-marker
                          :accumulated-text ""
                          :request-object nil)))
    (unless provider
      (error "Unknown provider: %s" provider-name))
    (when (string= provider-name "gemini")
      (let ((api-key (ai-get-provider-api-key "gemini")))
        (setq endpoint (concat endpoint "?key=" api-key))))
    (with-current-buffer target-buffer
      (setq ai-current-stream stream-context)
      (ai-set-status 'requesting))
    (ai-make-curl-request provider-name endpoint headers data stream-context streaming)))



(defun ai-make-curl-request (provider-name url headers data stream-context streaming)
  "Make HTTP request using curl process with robust error handling."
  (let* ((target-buffer (ai-stream-context-buffer stream-context))
         (process-name (format "ai-request-%s" (buffer-name target-buffer)))
         (buffer-name (format " *%s*" process-name))
         (temp-file (make-temp-file "ai-request-" nil ".json"))
         (response-buffer "")
         (headers-processed nil)
         (stderr-buffer (generate-new-buffer (format " *%s-stderr*" process-name))))

    (ai-debug "CURL: %s: Starting curl process (%s)" provider-name (if streaming "streaming" "non-streaming"))

    ;; Validate curl availability early
    (unless (executable-find "curl")
      (ai-handle-request-error "curl command not found in PATH" stream-context)
      (return))

    ;; Write data to temp file with error handling
    (condition-case err
        (with-temp-file temp-file
          (insert data))
      (error
       (ai-handle-request-error (format "Failed to write request data: %s" (error-message-string err)) stream-context)
       (return)))

    (let* ((header-args (mapcar (lambda (h) (list "-H" (format "%s: %s" (car h) (cdr h)))) headers))
           (curl-args (append '("curl" "-s" "--show-error" "--fail-with-body")
                              (when streaming '("-N" "--no-buffer"))
                              (list "--max-time" (number-to-string ai-request-timeout)
                                    "--connect-timeout" "30"
                                    "-i")  ; Include response headers
                              (apply #'append header-args)
                              (list "-X" "POST"
                                    "-d" (format "@%s" temp-file)
                                    url))))

      (ai-debug "CURL: %S" curl-args)
      (ai-debug "HEADER: %S" header-args)
      (ai-debug "TEMP FILE: %S" temp-file)

      (with-temp-buffer
        (insert-file-contents temp-file)
        (ai-debug "Request data: %s" (buffer-string)))

      (condition-case err
          (let ((process (make-process
                          :name process-name
                          :buffer buffer-name
                          :stderr stderr-buffer
                          :command curl-args
                          :connection-type 'pipe)))

            (setf (ai-stream-context-request-object stream-context) process)

            (set-process-filter
             process
             (lambda (proc output)
               (condition-case filter-err
                   (progn
                     (setq response-buffer (concat response-buffer output))
                     (unless headers-processed
                       (when (string-match "\r?\n\r?\n" response-buffer)
                         (let ((headers-section (substring response-buffer 0 (match-beginning 0))))
                           (ai-debug "Response headers: %s" headers-section)
                           ;; Check for HTTP error status in headers
                           (when (string-match "HTTP/[0-9.]+ \\([45][0-9][0-9]\\)" headers-section)
                             (let ((status-code (match-string 1 headers-section)))
                               (ai-debug "HTTP error status detected: %s" status-code)
                               ;; Don't return early - let the process complete to get full error message
                               )))
                         (setq response-buffer (substring response-buffer (match-end 0)))
                         (setq headers-processed t)))
                     (when headers-processed
                       (if streaming
                           ;; Streaming: process line by line
                           (while (string-match "\\(.*?\n\\)" response-buffer)
                             (let ((line (match-string 1 response-buffer)))
                               (setq response-buffer (substring response-buffer (match-end 0)))
                               (ai-process-response line stream-context provider-name t)))
                         ;; Non-streaming: accumulate all response
                         (setf (ai-stream-context-accumulated-text stream-context) response-buffer))))
                 (error
                  (ai-debug "Error in process filter: %s" filter-err)
                  (ai-handle-request-error (format "Process filter error: %s" (error-message-string filter-err)) stream-context)))))

            (set-process-sentinel
             process
             (lambda (proc event)
               (ai-debug "Process sentinel called: %s with event: %s" proc (string-trim event))

               ;; Clean up temp file
               (when (file-exists-p temp-file)
                 (condition-case nil (delete-file temp-file) (error nil)))

               ;; Get stderr content for better error messages
               (let ((stderr-content "")
                     (exit-code (process-exit-status proc))
                     (exit-signal (process-status proc)))

                 (when (buffer-live-p stderr-buffer)
                   (with-current-buffer stderr-buffer
                     (setq stderr-content (string-trim (buffer-string))))
                   (kill-buffer stderr-buffer))

                 (when (buffer-live-p (process-buffer proc))
                   (kill-buffer (process-buffer proc)))

                 (ai-debug "Process exit: code=%s, signal=%s, stderr=%s" exit-code exit-signal stderr-content)

                 (cond
                  ((zerop exit-code)
                   (when (not streaming)
                     ;; Process the complete response
                     (let ((response-data (ai-stream-context-accumulated-text stream-context)))
                       (ai-debug "Non-streaming response data: %s" (substring response-data 0 (min 200 (length response-data))))
                       (if (string-empty-p response-data)
                           (ai-handle-request-error "Empty response from server" stream-context)
                         (ai-process-response response-data stream-context provider-name nil))))
                   (ai-finalize-response stream-context))

                  ((memq exit-signal '(signal interrupt))
                   (ai-handle-request-cancellation stream-context))

                  (t
                   ;; Enhanced error message combining exit code, stderr, and response
                   (let ((error-msg (ai-get-enhanced-curl-error-message proc exit-code stderr-content
                                                                        (ai-stream-context-accumulated-text stream-context))))
                     (ai-debug "Curl error: %s" error-msg)
                     (ai-handle-request-error error-msg stream-context)))))))

            process)

        (error
         (ai-debug "Failed to start curl process: %s" err)
         (when (file-exists-p temp-file)
           (condition-case nil (delete-file temp-file) (error nil)))
         (when (buffer-live-p stderr-buffer)
           (kill-buffer stderr-buffer))
         (ai-handle-request-error (format "Failed to start curl process: %s" (error-message-string err)) stream-context)
         nil)))))

;; Enhanced error message function:

(defun ai-get-enhanced-curl-error-message (process exit-code stderr-content response-content)
  "Get comprehensive error message from curl process."
  (let ((base-error (cond
                     ((= exit-code 6) "Could not resolve host - check your internet connection")
                     ((= exit-code 7) "Failed to connect to server - server may be down or URL incorrect")
                     ((= exit-code 22) "HTTP error - check API key, endpoint, and request format")
                     ((= exit-code 28) "Request timeout - server took too long to respond")
                     ((= exit-code 35) "SSL connection error - check server certificates")
                     ((= exit-code 52) "Server returned empty response")
                     ((= exit-code 56) "Network receive error")
                     (t (format "curl exit code: %d" exit-code))))
        (additional-info '()))

    ;; Add stderr content if meaningful
    (when (and stderr-content (not (string-empty-p stderr-content))
               (not (string-match-p "^curl:" stderr-content))) ; Avoid duplicating curl prefix
      (push stderr-content additional-info))

    ;; Add response content if it looks like an error message
    (when (and response-content (not (string-empty-p response-content)))
      (condition-case nil
          (let ((json-data (json-read-from-string response-content)))
            (cond
             ;; Try common error formats
             ((assoc 'error json-data)
              (let ((error-obj (cdr (assoc 'error json-data))))
                (cond
                 ((stringp error-obj) (push error-obj additional-info))
                 ((and (listp error-obj) (assoc 'message error-obj))
                  (push (cdr (assoc 'message error-obj)) additional-info)))))
             ((assoc 'message json-data)
              (push (cdr (assoc 'message json-data)) additional-info))))
        (error
         ;; If not JSON, include raw response if it's short and looks like an error
         (when (and (< (length response-content) 200)
                    (or (string-match-p "error\\|Error\\|ERROR" response-content)
                        (string-match-p "unauthorized\\|forbidden\\|not found" response-content)))
           (push (string-trim response-content) additional-info)))))

    ;; Combine all information
    (if additional-info
        (format "%s: %s" base-error (string-join additional-info "; "))
      base-error)))

;; Enhanced ai-process-response with better error handling:

(defun ai-process-response (response-data stream-context provider-name is-streaming)
  "Process response data (streaming chunk or bulk response) with robust error handling."
  (if is-streaming
      ;; Streaming: process as SSE line
      (ai-process-stream-line response-data stream-context provider-name)
    ;; Non-streaming: parse JSON and stream the complete response
    (condition-case err
        (let* ((provider (ai-get-provider provider-name))
               ;; Clean up the response data before parsing
               (cleaned-data (string-trim response-data))
               json-data error-msg response)

          ;; Validate we have a provider (robust against missing providers)
          (unless provider
            (ai-handle-request-error (format "Provider '%s' not found or not configured properly" provider-name) stream-context)
            (return))

          ;; Parse JSON with better error reporting
          (condition-case json-err
              (progn
                (ai-debug "Parsing JSON data: %s" (substring cleaned-data 0 (min 500 (length cleaned-data))))
                (setq json-data (json-read-from-string cleaned-data)))
            (error
             (ai-debug "JSON parsing failed. Raw data: %s" cleaned-data)
             (ai-handle-request-error (format "Invalid JSON response: %s\nRaw response: %s"
                                              (error-message-string json-err)
                                              (substring cleaned-data 0 (min 200 (length cleaned-data))))
                                      stream-context)
             (return)))

          ;; Check for API errors using provider error parser (if available)
          (when (and (ai-provider-error-parser provider) json-data)
            (condition-case parser-err
                (setq error-msg (funcall (ai-provider-error-parser provider) json-data))
              (error
               (ai-debug "Error parser failed: %s" parser-err)
               ;; Continue without provider-specific error parsing
               (setq error-msg nil))))

          (if error-msg
              (ai-handle-request-error error-msg stream-context)
            ;; Extract response using provider parser (if available)
            (condition-case parser-err
                (if (ai-provider-response-parser provider)
                    (setq response (funcall (ai-provider-response-parser provider) json-data))
                  ;; Fallback if no response parser
                  (setq response (or (cdr (assoc 'content json-data))
                                     (cdr (assoc 'text json-data))
                                     (cdr (assoc 'message json-data))
                                     (format "Received response but no parser available for provider '%s'" provider-name))))
              (error
               (ai-debug "Response parser failed: %s" parser-err)
               ;; Use fallback parsing
               (setq response (or (cdr (assoc 'content json-data))
                                  (cdr (assoc 'text json-data))
                                  (cdr (assoc 'message json-data))
                                  "Response parser failed - check provider configuration"))))

            (ai-debug "Extracted response: %s" (substring response 0 (min 100 (length response))))
            (ai-stream-chunk response stream-context))))
    (error
     (ai-debug "Unexpected error in process-response: %s" err)
     (ai-handle-request-error (format "Response processing error: %s" (error-message-string err)) stream-context))))

(defun ai-stream-chunk (content stream-context)
  "Stream CONTENT chunk to buffer."
  (when (and content (not (string-empty-p content)) stream-context)
    (let ((buffer (ai-stream-context-buffer stream-context))
          (marker (ai-stream-context-response-marker stream-context)))
      (when (and buffer (buffer-live-p buffer) marker)
        (with-current-buffer buffer
          (when (string-empty-p (ai-stream-context-accumulated-text stream-context))
            (ai-set-status 'streaming))
          (setf (ai-stream-context-accumulated-text stream-context)
                (concat (ai-stream-context-accumulated-text stream-context) content))
          (save-excursion
            (goto-char marker)
            (insert content)
            (set-marker marker (point)))
          ;; Handle progress updates based on streaming mode
          (if ai-streaming-enabled
              (ai-update-mode-line (length (ai-stream-context-accumulated-text stream-context)))
            (ai-update-mode-line))
          (redisplay t))))))

(defun ai-finalize-response (stream-context)
  "Finalize response (always the same regardless of streaming mode)."
  (when (and stream-context (ai-stream-context-buffer stream-context))
    (let ((buffer (ai-stream-context-buffer stream-context))
          (accumulated-text (ai-stream-context-accumulated-text stream-context))
          (response-marker (ai-stream-context-response-marker stream-context)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (setq ai-current-stream nil)
          (when (and accumulated-text (not (string-empty-p accumulated-text)))
            (ai-add-message accumulated-text "assistant")
            (ai-highlight-code-blocks response-marker (point-max))
            (ai-insert-prompt)
            (goto-char (point-max)))
          (ai-clear-status)
          (message "Response complete"))))))

(defun ai-process-stream-line (line stream-context provider-name)
  "Process a single line from the streaming response."
  (let ((line (string-trim line)))
    (when (and (not (string-empty-p line))
               (not (string-prefix-p "event:" line))
               (string-prefix-p "data:" line))
      (let ((data-str (string-trim (substring line 5))))
        (when (not (string-empty-p data-str))
          (condition-case err
              (let* ((data (json-read-from-string data-str))
                     (provider (ai-get-provider provider-name))
                     (error-msg (when (ai-provider-error-parser provider)
                                  (funcall (ai-provider-error-parser provider) data))))
                (if error-msg
                    (ai-handle-request-error error-msg stream-context)
                  (ai-extract-and-stream-content data stream-context provider-name)))
            (error
             (ai-debug "JSON parsing error: %s" err))))))))

(defun ai-handle-request-error (error stream-context)
  "Handle request ERROR with enhanced UI feedback."
  (when (and stream-context (ai-stream-context-buffer stream-context))
    (let ((buffer (ai-stream-context-buffer stream-context)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (setq ai-current-stream nil)
          (ai-set-status 'error)

          ;; Insert error message in the chat buffer
          (save-excursion
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert (format "\n** Error\n%s\n" error)))

          ;; Show error in messages and mode line
          (message "AI Chat Error: %s" error)
          (ai-debug "Request error: %s" error)

          ;; Clear error status after delay
          (run-with-timer 5.0 nil
                          (lambda ()
                            (when (buffer-live-p buffer)
                              (with-current-buffer buffer
                                (ai-clear-status))))))))))

(defun ai-handle-request-cancellation (stream-context)
  "Handle request cancellation."
  (when (and stream-context (ai-stream-context-buffer stream-context))
    (let ((buffer (ai-stream-context-buffer stream-context)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (setq ai-current-stream nil)
          (ai-set-status 'cancelled)
          (run-with-timer 2.0 nil
                          (lambda ()
                            (when (buffer-live-p buffer)
                              (with-current-buffer buffer
                                (ai-clear-status)))))
          (message "Request cancelled"))))))

(defun ai-cleanup-cancelled-request ()
  "Clean up after request cancellation."
  (when (and ai-current-stream (ai-stream-context-buffer ai-current-stream))
    (let ((buffer (ai-stream-context-buffer ai-current-stream)))
      (setq ai-current-stream nil)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (ai-set-status 'cancelled)
          (save-excursion
            (goto-char (point-max))
            (when (re-search-backward "^\\*\\* Assistant Response" nil t)
              (let ((response-start (progn (forward-line 1) (point))))
                (when (string-empty-p (string-trim (buffer-substring response-start (point-max))))
                  (delete-region (line-beginning-position 0) (point-max))))))
          (run-with-timer 1.0 nil
                          (lambda ()
                            (when (buffer-live-p buffer)
                              (with-current-buffer buffer
                                (ai-clear-status)))))))))
  (message "Request cancelled"))

(defun ai-get-curl-error-message (process exit-code)
  "Get meaningful error message from curl process."
  (let ((error-buffer (process-buffer process)))
    (cond
     ((= exit-code 7) "Failed to connect to server")
     ((= exit-code 28) "Request timeout")
     ((= exit-code 22) "HTTP error (check API key and endpoint)")
     ((= exit-code 6) "Could not resolve host")
     ((= exit-code 35) "SSL connect error")
     ((and error-buffer (buffer-live-p error-buffer))
      (with-current-buffer error-buffer
        (let ((stderr-content (string-trim (buffer-string))))
          (if (string-empty-p stderr-content)
              (format "curl exit code: %d" exit-code)
            stderr-content))))
     (t (format "curl exit code: %d" exit-code)))))

(defun ai-diagnose-streaming ()
  "Diagnose streaming issues."
  (interactive)
  (let ((diagnosis '())
        (current-provider (if ai-current-session
                              (ai-session-provider ai-current-session)
                            ai-default-provider)))
    (condition-case nil
        (let ((curl-version (shell-command-to-string "curl --version")))
          (if (string-match "curl \\([0-9]+\\.[0-9]+\\)" curl-version)
              (push (format "✓ curl available: %s" (match-string 1 curl-version)) diagnosis)
            (push "✗ curl version not detected" diagnosis)))
      (error (push "✗ curl not found in PATH" diagnosis)))
    (let ((provider (ai-get-provider current-provider)))
      (if provider
          (push (format "✓ Provider '%s' configured" current-provider) diagnosis)
        (push (format "✗ Provider '%s' not found" current-provider) diagnosis)))
    (let ((api-key (ai-get-provider-api-key current-provider)))
      (if (and api-key (> (length api-key) 10))
          (push (format "✓ API key present (%d chars)" (length api-key)) diagnosis)
        (push "✗ API key missing or too short" diagnosis)))
    (let ((streaming-enabled (if ai-current-session
                                 ai-streaming-enabled
                               ai-streaming-default)))
      (if streaming-enabled
          (push "✓ Streaming enabled" diagnosis)
        (push "✗ Streaming disabled" diagnosis)))
    (with-current-buffer (get-buffer-create "*AI Streaming Diagnosis*")
      (erase-buffer)
      (insert "AI Streaming Diagnosis\n")
      (insert "======================\n\n")
      (dolist (item (reverse diagnosis))
        (insert item "\n"))
      (insert "\nTo enable streaming: M-x ai-toggle-streaming\n")
      (insert "To enable debug: M-x ai-toggle-debug\n")
      (display-buffer (current-buffer)))))

(defun ai-extract-and-stream-content (json-data stream-context provider-name)
  "Extract content from JSON-DATA and stream it."
  (ai-debug "Extract and Stream Content called: provider: %s :: %s" provider-name json-data)
  (let* ((provider (ai-get-provider provider-name))
         (content (when provider
                    (funcall (ai-provider-stream-parser provider) json-data))))
    (when content
      (ai-stream-chunk content stream-context))))

(defvar ai-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") 'ai-send-input)
    (define-key map (kbd "C-c C-v") 'ai-send-input-non-streaming)
    (define-key map (kbd "C-c C-t") 'ai-toggle-streaming)
    (define-key map (kbd "C-c C-r") 'ai-regenerate-last)
    (define-key map (kbd "C-c C-s") 'ai-save-session)
    (define-key map (kbd "C-c C-k") 'ai-cancel-request)
    (define-key map (kbd "C-c C-f") 'ai-format-code-blocks)
    (define-key map (kbd "C-c C-p") 'ai-change-provider)
    (define-key map (kbd "C-c C-m") 'ai-select-model)
    (define-key map (kbd "C-c C-y") 'ai-copy-last-response)
    (define-key map (kbd "C-c C-x s") 'ai-set-system-prompt)
    (define-key map (kbd "C-c C-x t") 'ai-use-template)
    (define-key map (kbd "C-c C-x c") 'ai-add-context)
    (define-key map (kbd "C-c C-x f") 'ai-send-files)
    (define-key map (kbd "C-c C-i") 'ai-view-conversation-stats)
    (define-key map (kbd "M-p") 'ai-previous-input)
    (define-key map (kbd "M-n") 'ai-next-input)
    map)
  "Keymap for AI Chat mode.")

(define-derived-mode ai-mode org-mode "AI Chat"
  "Major mode for AI chat interface."
  :group 'ai-integration
  :keymap ai-mode-map
  (setq-local ai-current-session nil)
  (setq-local ai-input-history nil)
  (setq-local ai-streaming-enabled ai-streaming-default)
  (setq-local ai-current-stream nil)
  (setq-local ai-current-status 'idle)
  (setq-local org-src-fontify-natively t)
  (setq-local org-src-preserve-indentation t)
  (setq-local org-fontify-quote-and-verse-blocks t)
  (add-hook 'post-command-hook 'ai-update-mode-line nil t)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (python . t)
     (shell . t)
     (js . t)
     (ruby . t)
     (C . t)
     (java . t)
     (sql . t))))

(defun ai-create-session (&optional source-buffer provider model force-new)
  "Create a new AI chat session."
  (let* ((provider (or provider ai-default-provider))
         (model (or model (ai-get-provider-model provider)))
         (buffer-name (if force-new
                          (ai-generate-buffer-name provider source-buffer t)
                        (ai-generate-buffer-name provider source-buffer)))
         (buffer (get-buffer-create buffer-name))
         (session (make-ai-session
                   :name buffer-name
                   :buffer buffer
                   :source-buffer source-buffer
                   :provider provider
                   :model model
                   :messages nil
                   :created-at (current-time)
                   :associated-buffers (when source-buffer (list source-buffer)))))
    (with-current-buffer buffer
      (ai-mode)
      (setq-local ai-current-session session)
      (setq-local ai-streaming-enabled ai-streaming-default)
      (setq-local ai-current-status 'idle)
      (when (= (buffer-size) 0)
        (ai-insert-header session)
        (ai-insert-prompt))
      (ai-update-mode-line))
    (when (and source-buffer ai-auto-associate-buffers)
      (ai-associate-buffer-with-session source-buffer session))
    (push session ai-sessions)
    session))

(defun ai-get-sessions-for-buffer (buffer)
  "Get all sessions associated with BUFFER."
  (cl-remove-if-not
   (lambda (session)
     (and (buffer-live-p (ai-session-buffer session))
          (member buffer (ai-session-associated-buffers session))))
   ai-sessions))

(defun ai-select-session-for-buffer (source-buffer &optional force-new)
  "Select appropriate session for SOURCE-BUFFER.
If FORCE-NEW is non-nil, always create new session."
  (if force-new
      (ai-create-session source-buffer)
    (let ((existing-sessions (ai-get-sessions-for-buffer source-buffer)))
      (cond
       ((null existing-sessions)
        (ai-create-session source-buffer))
       ((= 1 (length existing-sessions))
        (car existing-sessions))
       (t
        (let* ((session-choices (mapcar (lambda (s)
                                          (cons (ai-session-name s) s))
                                        existing-sessions))
               (all-choices (append session-choices
                                    '(("Create new session" . new))))
               (choice-name (completing-read "Select session: " all-choices))
               (choice (cdr (assoc choice-name all-choices))))
          (if (eq choice 'new)
              (ai-create-session source-buffer)
            choice)))))))

(defun ai-select-or-create-session-for-buffer (&optional force-new-session)
  "Select or create session for current buffer."
  (ai-select-session-for-buffer (current-buffer) force-new-session))

(defun ai-insert-header (session)
  "Insert session header."
  (insert (format "#+TITLE: AI Chat Session\n"))
  (insert (format "#+PROVIDER: %s\n" (ai-session-provider session)))
  (insert (format "#+MODEL: %s\n" (ai-session-model session)))
  (insert (format "#+CREATED: %s\n\n" (format-time-string "[%Y-%m-%d %a %H:%M]")))
  (insert "* Conversation\n\n"))

(defun ai-insert-prompt ()
  "Insert user input prompt."
  (goto-char (point-max))
  (unless (bolp) (insert "\n"))
  (insert "\n** User Input\n")
  )

(defun ai-get-current-input ()
  "Get current input if point is in user input section."
  (save-excursion
    (let ((current-pos (point)))
      (when (re-search-backward "^** User Input" nil t)
        (let ((content-start (progn (forward-line 1) (point))))
          (when (>= current-pos content-start)
            (let ((content-end (if (re-search-forward "^** Assistant Response" nil t)
                                   (line-beginning-position)
                                 (point-max))))
              (when (<= current-pos content-end)
                (string-trim (buffer-substring content-start content-end))))))))))

(defun ai-add-message (content role)
  "Add message to current session."
  (when ai-current-session
    (push (list :role role :content content :timestamp (current-time))
          (ai-session-messages ai-current-session))))

(defun ai-prepare-response ()
  "Prepare for response and return marker for insertion point."
  (goto-char (point-max))
  (unless (bolp) (insert "\n"))
  (insert "\n** Assistant Response\n")
  )

(defun ai-insert-response-text (response)
  "Insert non-streaming RESPONSE text at the correct location."
  (let ((response-marker (ai-prepare-response)))
    (save-excursion
      (goto-char response-marker)
      (insert response))
    (ai-add-message response "assistant")
    (goto-char (point-max))
    (ai-highlight-code-blocks response-marker (point))
    (ai-insert-prompt)))

(defun ai-highlight-code-blocks (start end)
  "Convert markdown code blocks to org-mode in region."
  (save-excursion
    (goto-char start)
    (while (and (< (point) end)
                (re-search-forward "```\\([a-zA-Z0-9_+-]+\\)?\n" end t))
      (let ((lang (or (match-string 1) ""))
            (code-start (match-end 0)))
        (when (re-search-forward "```" end t)
          (let ((code-end (match-beginning 0)))
            (goto-char (match-beginning 0))
            (delete-region (match-beginning 0) (match-end 0))
            (insert "#+END_SRC")
            (goto-char code-start)
            (beginning-of-line 0)
            (delete-region (point) code-start)
            (insert (format "#+BEGIN_SRC %s\n" lang))))))))

(defun ai-set-status (status)
  "Set current STATUS and update mode line."
  (setq ai-current-status status)
  (ai-update-mode-line)
  (force-mode-line-update))

(defun ai-update-mode-line (&optional chunk-count)
  "Update mode line with current status."
  (when ai-current-session
    (let* ((status-text (cdr (assoc ai-current-status ai-status-indicators)))
           (buffer-display-name (buffer-name (ai-session-buffer ai-current-session))))
      (setq mode-line-buffer-identification
            (list (propertize
                   (if (and chunk-count (eq ai-current-status 'streaming))
                       (let ((progress-indicator (cond
                                                  ((< chunk-count 32) "▏")
                                                  ((< chunk-count 64) "▎")
                                                  ((< chunk-count 128) "▍")
                                                  ((< chunk-count 256) "▌")
                                                  ((< chunk-count 512) "▋")
                                                  ((< chunk-count 1024) "▊")
                                                  ((< chunk-count 2048) "▉")
                                                  (t "█"))))
                         (format "%s %s %d chunks" buffer-display-name progress-indicator chunk-count))
                     (format "%s%s" buffer-display-name (or status-text "")))
                   'face (cond
                          ((eq ai-current-status 'error) 'error)
                          ((eq ai-current-status 'streaming) 'success)
                          ((eq ai-current-status 'requesting) 'warning)
                          ((eq ai-current-status 'cancelling) 'warning)
                          ((eq ai-current-status 'cancelled) 'shadow)
                          (t 'mode-line-buffer-id)))))
      (force-mode-line-update))))

(defun ai-clear-status ()
  "Clear current status."
  (ai-set-status 'idle))

(defun ai-make-request (provider-name model messages streaming)
  "Make request to PROVIDER-NAME with MODEL and MESSAGES."
  (ai-debug "Making %s request: provider=%s, model=%s, messages=%d"
            (if streaming "streaming" "non-streaming")
            provider-name model (length messages))
  (ai-make-unified-request provider-name model messages streaming))

(defun ai-start (&optional provider model)
  "Start new AI chat session."
  (interactive
   (when current-prefix-arg
     (let ((providers (hash-table-keys ai-providers)))
       (list (completing-read "Provider: " providers nil t)
             (read-string "Model: ")))))
  (let ((session (ai-create-session provider model)))
    (switch-to-buffer (ai-session-buffer session))
    (message "Started AI chat with %s (%s)"
             (ai-session-provider session)
             (ai-session-model session))))

(defun ai-new-session ()
  "Create new AI chat session."
  (interactive)
  (let ((session (ai-create-session nil nil nil t)))
    (switch-to-buffer (ai-session-buffer session))
    (message "Started new AI chat session with %s (%s)"
             (ai-session-provider session)
             (ai-session-model session))))

(defun ai-toggle-debug ()
  "Toggle AI debug messages."
  (interactive)
  (setq ai-debug-enabled (not ai-debug-enabled))
  (message "AI debug messages %s" (if ai-debug-enabled "enabled" "disabled")))

(defun ai-send-input ()
  "Send current input to AI."
  (interactive)
  (unless ai-current-session
    (error "No active AI chat session"))
  (when ai-current-stream
    (error "Request already in progress. Use C-c C-k to cancel."))
  (let ((input (ai-get-current-input)))
    (unless input
      (error "Point is not in a user input section"))
    (when (string-empty-p (string-trim input))
      (error "Empty input"))
    (ai-debug "Sending input: %s" (substring input 0 (min 50 (length input))))
    (ai-add-message input "user")
    (push input ai-input-history)
    (ai-prepare-response)
    (ai-make-request
     (ai-session-provider ai-current-session)
     (ai-session-model ai-current-session)
     (reverse (ai-session-messages ai-current-session))
     ai-streaming-enabled)))

(defun ai-send-input-non-streaming ()
  "Send input without streaming."
  (interactive)
  (let ((ai-streaming-enabled nil))
    (ai-send-input)))

(defun ai-toggle-streaming ()
  "Toggle streaming mode."
  (interactive)
  (setq ai-streaming-enabled (not ai-streaming-enabled))
  (message "Streaming %s" (if ai-streaming-enabled "enabled" "disabled")))

(defun ai-cancel-request ()
  "Cancel current request."
  (interactive)
  (if ai-current-stream
      (let ((request-obj (ai-stream-context-request-object ai-current-stream)))
        (if (and request-obj (process-live-p request-obj))
            (progn
              (ai-set-status 'cancelling)  ; Intermediate status
              (ai-debug "Attempting to cancel process: %s" request-obj)
              (condition-case err
                  (progn
                    (interrupt-process request-obj)
                    (run-with-timer 2.0 nil 'ai-force-cancel-request request-obj))
                (error
                 (ai-debug "Error interrupting process: %s" err)
                 (ai-force-cancel-request request-obj))))
          (ai-cleanup-cancelled-request)))
    (message "No active request to cancel")))

(defun ai-force-cancel-request (process)
  "Force cancel REQUEST-OBJ if still running."
  (when (and process (process-live-p process))
    (ai-debug "Force killing process: %s" process)
    (condition-case err
        (kill-process process)
      (error (ai-debug "Error killing process: %s" err))))
  (ai-cleanup-cancelled-request))

(defun ai-regenerate-last ()
  "Regenerate last response."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (let ((messages (ai-session-messages ai-current-session)))
    (when (and messages (string= (plist-get (car messages) :role) "assistant"))
      (setf (ai-session-messages ai-current-session) (cdr messages))
      (save-excursion
        (goto-char (point-max))
        (when (re-search-backward "^** Assistant Response" nil t)
          (delete-region (point) (point-max))))
      (ai-prepare-response)
      (ai-make-request
       (ai-session-provider ai-current-session)
       (ai-session-model ai-current-session)
       (reverse (ai-session-messages ai-current-session))
       ai-streaming-enabled))))

(defun ai-change-provider (&optional provider model)
  "Change provider for current session."
  (interactive
   (let* ((providers (hash-table-keys ai-providers))
          (new-provider (completing-read "Provider: " providers nil t))
          (new-model (when current-prefix-arg
                       (read-string "Model (leave empty for default): "))))
     (list new-provider new-model)))
  (unless ai-current-session
    (error "No active session"))
  (let* ((new-provider (or provider
                           (completing-read "Provider: "
                                            (hash-table-keys ai-providers) nil t)))
         (new-model (or model (ai-get-provider-model new-provider))))
    (ai-debug "Switching provider: %s (%s) -> %s (%s)"
              (ai-session-provider ai-current-session)
              (ai-session-model ai-current-session)
              new-provider new-model)
    (setf (ai-session-provider ai-current-session) new-provider)
    (setf (ai-session-model ai-current-session) new-model)
    (message "Changed to %s (%s)" new-provider new-model)))

(defun ai-switch-to-openai ()
  "Switch to OpenAI."
  (interactive)
  (ai-change-provider "openai"))

(defun ai-switch-to-claude ()
  "Switch to Claude."
  (interactive)
  (ai-change-provider "claude"))

(defun ai-switch-to-gemini ()
  "Switch to Gemini."
  (interactive)
  (ai-change-provider "gemini"))

(defun ai-previous-input ()
  "Insert previous input from history."
  (interactive)
  (when ai-input-history
    (let ((input (pop ai-input-history)))
      (ai-replace-current-input input)
      (setq ai-input-history (append ai-input-history (list input))))))

(defun ai-next-input ()
  "Insert next input from history."
  (interactive)
  (when ai-input-history
    (let ((input (car (last ai-input-history))))
      (ai-replace-current-input input)
      (setq ai-input-history (cons input (butlast ai-input-history))))))

(defun ai-replace-current-input (text)
  "Replace current input with TEXT."
  (save-excursion
    (when (re-search-backward "^** User Input" nil t)
      (forward-line 1)
      (let ((start (point))
            (end (if (re-search-forward "^** Assistant Response" nil t)
                     (line-beginning-position)
                   (point-max))))
        (delete-region start end)
        (goto-char start)
        (insert text)))))

(defun ai-send-region (start end &optional new-session)
  "Send region to AI chat.
With prefix argument or NEW-SESSION, create a new session."
  (interactive "r\nP")
  (let* ((text (buffer-substring start end))
         (source-buffer (current-buffer))
         (session (if new-session
                      (ai-create-session source-buffer nil nil t)  ; Pass force-new=t
                    (or (gethash source-buffer ai-buffer-last-session-map)
                        (ai-create-session source-buffer)))))
    (switch-to-buffer (ai-session-buffer session))
    (goto-char (point-max))
    (ai-replace-current-input text)
    (message "Text inserted. Add your prompt and send with C-c C-c")))

(defun ai-send-buffer (&optional new-session)
  "Send entire buffer to AI.
With prefix argument or NEW-SESSION, create a new session."
  (interactive "P")
  (ai-send-region (point-min) (point-max) new-session))

(defun ai-send-file (filename &optional new-session)
  "Send FILE content to AI chat.
With prefix argument or NEW-SESSION, create a new session."
  (interactive
   (list (read-file-name "File to send: " nil nil t)
         current-prefix-arg))
  (let* ((source-buffer (current-buffer))
         (session (if new-session
                      (ai-create-session source-buffer nil nil t)
                    (or (gethash source-buffer ai-buffer-last-session-map)
                        (ai-create-session source-buffer))))
         (content (with-temp-buffer
                    (insert-file-contents filename)
                    (buffer-string))))
    (switch-to-buffer (ai-session-buffer session))
    (goto-char (point-max))
    (ai-replace-current-input
     (format ai-file-intro-template filename content))
    (message "File content inserted. Add your prompt and send with C-c C-c")))

(defun ai-send-at-point (&optional new-session)
  "Send thing at point to AI chat.
With prefix argument or NEW-SESSION, create a new session."
  (interactive "P")
  (let ((thing (ai-get-thing-at-point)))
    (if thing
        (let* ((source-buffer (current-buffer))
               (session (if new-session
                            (ai-create-session source-buffer nil nil t)
                          (or (gethash source-buffer ai-buffer-last-session-map)
                              (ai-create-session source-buffer)))))
          (switch-to-buffer (ai-session-buffer session))
          (goto-char (point-max))
          (ai-replace-current-input thing)
          (message "Content inserted. Add your prompt and send with C-c C-c"))
      (error "No content found at point"))))

(defun ai-send-region-new-session (start end)
  "Send region to new AI chat session."
  (interactive "r")
  (ai-send-region start end t))

(defun ai-send-buffer-new-session ()
  "Send buffer to new AI chat session."
  (interactive)
  (ai-send-buffer t))

(defun ai-send-file-new-session (filename)
  "Send file to new AI chat session."
  (interactive "fFile to send: ")
  (ai-send-file filename t))

(defun ai-send-at-point-new-session ()
  "Send thing at point to new AI chat session."
  (interactive)
  (ai-send-at-point t))

(defun ai-clear-session ()
  "Clear current session."
  (interactive)
  (when ai-current-session
    (erase-buffer)
    (setf (ai-session-messages ai-current-session) nil)
    (ai-insert-header ai-current-session)
    (ai-insert-prompt)))

(defun ai-save-session (&optional filename)
  "Save current session."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (let ((filename (or filename
                      (expand-file-name
                       (format "session-%s.json"
                               (format-time-string "%Y%m%d-%H%M%S"))
                       ai-conversation-directory))))
    (unless (file-exists-p ai-conversation-directory)
      (make-directory ai-conversation-directory t))
    (with-temp-file filename
      (insert (json-encode
               (list :provider (ai-session-provider ai-current-session)
                     :model (ai-session-model ai-current-session)
                     :created (ai-session-created-at ai-current-session)
                     :messages (ai-session-messages ai-current-session)))))
    (message "Session saved to %s" filename)))

(defun ai-load-session (filename)
  "Load session from file."
  (interactive
   (list (read-file-name "Load session: " ai-conversation-directory nil t)))
  (let* ((data (with-temp-buffer
                 (insert-file-contents filename)
                 (json-read)))
         (provider (cdr (assoc 'provider data)))
         (model (cdr (assoc 'model data)))
         (messages (cdr (assoc 'messages data)))
         (session (ai-create-session provider model)))
    (setf (ai-session-messages session) messages)
    (with-current-buffer (ai-session-buffer session)
      (setq ai-current-session session)
      (erase-buffer)
      (ai-insert-header session)
      (dolist (msg (reverse messages))
        (let ((role (cdr (assoc 'role msg)))
              (content (cdr (assoc 'content msg))))
          (cond
           ((string= role "user")
            (insert (format "** User Input\n%s\n\n" content)))
           ((string= role "assistant")
            (insert (format "** Assistant Response\n%s\n\n" content))))))
      (ai-insert-prompt))
    (switch-to-buffer (ai-session-buffer session))
    (message "Session loaded from %s" filename)))

(defun ai-format-code-blocks ()
  "Format code blocks in buffer."
  (interactive)
  (ai-highlight-code-blocks (point-min) (point-max))
  (font-lock-ensure))

(defvar ai-send-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "r") 'ai-send-region)
    (define-key map (kbd "b") 'ai-send-buffer)
    (define-key map (kbd "f") 'ai-send-file)
    (define-key map (kbd "p") 'ai-send-at-point)
    (define-key map (kbd "R") 'ai-send-region-new-session)
    (define-key map (kbd "B") 'ai-send-buffer-new-session)
    (define-key map (kbd "F") 'ai-send-file-new-session)
    (define-key map (kbd "P") 'ai-send-at-point-new-session)
    map)
  "Prefix keymap for AI send commands.")

(defvar ai-prose-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s r") 'ai-fix-prose-style-region)
    (define-key map (kbd "s b") 'ai-fix-prose-style-buffer)
    (define-key map (kbd "s p") 'ai-fix-prose-style-at-point)
    (define-key map (kbd "s f") 'ai-fix-prose-style-file)
    (define-key map (kbd "g r") 'ai-fix-prose-grammar-region)
    (define-key map (kbd "g b") 'ai-fix-prose-grammar-buffer)
    (define-key map (kbd "g p") 'ai-fix-prose-grammar-at-point)
    (define-key map (kbd "g f") 'ai-fix-prose-grammar-file)
    (define-key map (kbd "l r") 'ai-fix-prose-spelling-region)
    (define-key map (kbd "l b") 'ai-fix-prose-spelling-buffer)
    (define-key map (kbd "l p") 'ai-fix-prose-spelling-at-point)
    (define-key map (kbd "l f") 'ai-fix-prose-spelling-file)
    (define-key map (kbd "e r") 'ai-explain-text-region)
    (define-key map (kbd "e b") 'ai-explain-text-buffer)
    (define-key map (kbd "e p") 'ai-explain-text-at-point)
    (define-key map (kbd "e f") 'ai-explain-text-file)
    map)
  "Prefix keymap for AI prose commands.")

(defvar ai-code-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "e r") 'ai-explain-code-region)
    (define-key map (kbd "e b") 'ai-explain-code-buffer)
    (define-key map (kbd "e p") 'ai-explain-code-at-point)
    (define-key map (kbd "e f") 'ai-explain-code-file)
    (define-key map (kbd "f r") 'ai-fix-code-region)
    (define-key map (kbd "f b") 'ai-fix-code-buffer)
    (define-key map (kbd "f p") 'ai-fix-code-at-point)
    (define-key map (kbd "f f") 'ai-fix-code-file)
    (define-key map (kbd "r r") 'ai-review-code-region)
    (define-key map (kbd "r b") 'ai-review-code-buffer)
    (define-key map (kbd "r p") 'ai-review-code-at-point)
    (define-key map (kbd "r f") 'ai-review-code-file)
    (define-key map (kbd "s r") 'ai-review-security-region)
    (define-key map (kbd "s b") 'ai-review-security-buffer)
    (define-key map (kbd "s p") 'ai-review-security-at-point)
    (define-key map (kbd "s f") 'ai-review-security-file)
    (define-key map (kbd "p r") 'ai-review-performance-region)
    (define-key map (kbd "p b") 'ai-review-performance-buffer)
    (define-key map (kbd "p p") 'ai-review-performance-at-point)
    (define-key map (kbd "p f") 'ai-review-performance-file)
    (define-key map (kbd "y r") 'ai-review-style-region)
    (define-key map (kbd "y b") 'ai-review-style-buffer)
    (define-key map (kbd "y p") 'ai-review-style-at-point)
    (define-key map (kbd "y f") 'ai-review-style-file)
    (define-key map (kbd "b r") 'ai-review-bugs-region)
    (define-key map (kbd "b b") 'ai-review-bugs-buffer)
    (define-key map (kbd "b p") 'ai-review-bugs-at-point)
    (define-key map (kbd "b f") 'ai-review-bugs-file)
    (define-key map (kbd "TAB") 'ai-complete-at-point)
    (define-key map (kbd "c") 'ai-complete-at-point)
    map)
  "Prefix keymap for AI code commands.")

(defvar ai-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'ai-start)
    (define-key map (kbd "N") 'ai-new-session)
    (define-key map (kbd "S") 'ai-save-session)
    (define-key map (kbd "L") 'ai-load-session)
    (define-key map (kbd "x") 'ai-clear-session)
    (define-key map (kbd "k") 'ai-cancel-request)
    (define-key map (kbd "P") 'ai-change-provider)
    (define-key map (kbd "O") 'ai-switch-to-openai)
    (define-key map (kbd "C") 'ai-switch-to-claude)
    (define-key map (kbd "G") 'ai-switch-to-gemini)
    (define-key map (kbd "r") 'ai-send-region)
    (define-key map (kbd "b") 'ai-send-buffer)
    (define-key map (kbd "i") 'ai-insert-response)
    (define-key map (kbd "v") 'ai-toggle-streaming)
    (define-key map (kbd "d") 'ai-toggle-debug)
    (define-key map (kbd "m") 'ai-minor-mode)
    (define-key map (kbd "s") ai-send-prefix-map)
    (define-key map (kbd "p") ai-prose-prefix-map)
    (define-key map (kbd "c") ai-code-prefix-map)
    map)
  "Prefix keymap for AI Integration commands.")

(define-key global-map (kbd "C-c a") ai-prefix-map)

(defvar ai-minor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c a") ai-prefix-map)
    map)
  "Keymap for AI Chat minor mode.")

(defmacro ai-define-utility-functions ()
  "Generate utility functions from template mappings."
  `(progn
     ,@(mapcar
        (lambda (mapping)
          (let* ((key (car mapping))
                 (template (cdr mapping))
                 (is-code (string-match-p "```" template))
                 (base-name (replace-regexp-in-string "-" "-" key)))
            `(progn
               (defun ,(intern (format "ai-%s-region" base-name)) (start end)
                 ,(format "Apply %s to region." base-name)
                 (interactive "r")
                 (let ((content (buffer-substring start end))
                       (mode-name (if ,is-code
                                      (replace-regexp-in-string "-mode$" ""
                                                                (symbol-name major-mode))
                                    "")))
                   (ai-with-template
                    (if ,is-code
                        (format ,template mode-name content)
                      (format ,template content)))))
               (defun ,(intern (format "ai-%s-buffer" base-name)) ()
                 ,(format "Apply %s to entire buffer." base-name)
                 (interactive)
                 (,(intern (format "ai-%s-region" base-name)) (point-min) (point-max)))
               (defun ,(intern (format "ai-%s-at-point" base-name)) ()
                 ,(format "Apply %s to thing at point." base-name)
                 (interactive)
                 (let ((thing (if ,is-code
                                  (or (thing-at-point 'defun)
                                      (thing-at-point 'symbol))
                                (ai-get-thing-at-point))))
                   (if thing
                       (let ((mode-name (if ,is-code
                                            (replace-regexp-in-string "-mode$" ""
                                                                      (symbol-name major-mode))
                                          "")))
                         (ai-with-template
                          (if ,is-code
                              (format ,template mode-name thing)
                            (format ,template thing))))
                     (error "No content found at point"))))
               (defun ,(intern (format "ai-%s-file" base-name)) (filename)
                 ,(format "Apply %s to file." base-name)
                 (interactive "fFile: ")
                 (let ((content (with-temp-buffer
                                  (insert-file-contents filename)
                                  (buffer-string)))
                       (mode-name (if ,is-code
                                      (let ((mode (assoc-default filename auto-mode-alist
                                                                 'string-match)))
                                        (if mode
                                            (replace-regexp-in-string "-mode$" ""
                                                                      (symbol-name mode))
                                          "text"))
                                    "")))
                   (ai-with-template
                    (concat
                     (format "File: %s\n\n" filename)
                     (if ,is-code
                         (format ,template mode-name content)
                       (format ,template content)))))))))
        ai-template-mappings)))

(ai-define-utility-functions)

(defun ai-send-with-template (template-text &optional force-new-session)
  "Send TEMPLATE-TEXT to AI, optionally in new session."
  (let* ((source-buffer (current-buffer))
         (session (ai-select-session-for-buffer source-buffer force-new-session)))
    (switch-to-buffer (ai-session-buffer session))
    (goto-char (point-max))
    (ai-replace-current-input template-text)
    (ai-send-input)))

(defun ai-with-template (prompt)
  "Send PROMPT to AI chat with template."
  (ai-send-with-template prompt current-prefix-arg))

(defun ai-get-thing-at-point ()
  "Get relevant thing at point based on context."
  (or (thing-at-point 'defun)
      (thing-at-point 'paragraph)
      (thing-at-point 'sentence)
      (thing-at-point 'symbol)
      (thing-at-point 'word)))

(defun ai-fix-prose-style-at-point ()
  "Fix prose style at point."
  (interactive)
  (let ((text (ai-get-thing-at-point)))
    (if text
        (ai-with-template (format "Please improve the writing style of this text:\n\n%s" text))
      (error "No text found at point"))))

(defun ai-fix-prose-grammar-at-point ()
  "Fix grammar at point."
  (interactive)
  (let ((text (ai-get-thing-at-point)))
    (if text
        (ai-with-template (format "Please fix any grammar errors in this text:\n\n%s" text))
      (error "No text found at point"))))

(defun ai-fix-prose-spelling-at-point ()
  "Fix spelling at point."
  (interactive)
  (let ((text (ai-get-thing-at-point)))
    (if text
        (ai-with-template (format "Please fix any spelling errors in this text:\n\n%s" text))
      (error "No text found at point"))))

(defun ai-explain-text-region (start end)
  "Explain text in region."
  (interactive "r")
  (let ((text (buffer-substring start end)))
    (ai-with-template (format "Please explain or analyze this text:\n\n%s" text))))

(defun ai-explain-text-buffer ()
  "Explain text in buffer."
  (interactive)
  (ai-explain-text-region (point-min) (point-max)))

(defun ai-explain-text-at-point ()
  "Explain text at point."
  (interactive)
  (let ((text (ai-get-thing-at-point)))
    (if text
        (ai-with-template (format "Please explain or analyze this text:\n\n%s" text))
      (error "No text found at point"))))

(defun ai-insert-response ()
  "Get AI response and insert at point."
  (interactive)
  (let ((text (if (region-active-p)
                  (buffer-substring (region-beginning) (region-end))
                (read-string "Prompt: ")))
        (session (ai-create-session)))
    (ai-make-request
     (ai-session-provider session)
     (ai-session-model session)
     (list (list :role "user" :content text))
     nil))) ; Non-streaming for inline insertion

(defun ai-complete-at-point ()
  "Use AI to complete code at point."
  (interactive)
  (let* ((start (save-excursion (beginning-of-defun) (point)))
         (end (point))
         (context (buffer-substring start end)))
    (ai-with-template
     (format "Complete this %s code:\n\n```%s\n%s\n```\n\nJust provide the completion, no explanation."
             (replace-regexp-in-string "-mode$" "" (symbol-name major-mode))
             (replace-regexp-in-string "-mode$" "" (symbol-name major-mode))
             context))))

(define-minor-mode ai-minor-mode
  "Minor mode for AI chat integration in any buffer."
  :lighter " AI"
  :keymap ai-minor-mode-map
  :group 'ai-integration)

(defun ai-cleanup-sessions ()
  "Clean up killed session buffers."
  (setq ai-sessions
        (cl-remove-if (lambda (session)
                        (not (buffer-live-p (ai-session-buffer session))))
                      ai-sessions)))

(defun ai-list-sessions ()
  "List all active sessions."
  (interactive)
  (if ai-sessions
      (let ((session-info (mapcar (lambda (session)
                                    (format "%s (%s)"
                                            (ai-session-provider session)
                                            (ai-session-model session)))
                                  ai-sessions)))
        (message "Active sessions: %s" (string-join session-info ", ")))
    (message "No active sessions")))

(defun ai-kill-all-sessions ()
  "Kill all AI chat sessions."
  (interactive)
  (when (yes-or-no-p "Kill all AI chat sessions? ")
    (dolist (session ai-sessions)
      (when (buffer-live-p (ai-session-buffer session))
        (kill-buffer (ai-session-buffer session))))
    (setq ai-sessions nil)
    (message "All sessions killed")))

(defun ai-export-session (format)
  "Export current session in FORMAT."
  (interactive
   (list (completing-read "Export format: " '("markdown" "org" "json" "text") nil t)))
  (unless ai-current-session
    (error "No active session"))
  (let ((filename (read-file-name "Export to: " nil nil nil
                                  (format "ai-export.%s"
                                          (cond ((string= format "markdown") "md")
                                                ((string= format "org") "org")
                                                ((string= format "json") "json")
                                                ((string= format "text") "txt"))))))
    (cond
     ((string= format "markdown") (ai-export-to-markdown filename))
     ((string= format "org") (ai-export-to-org filename))
     ((string= format "json") (ai-export-to-json filename))
     ((string= format "text") (ai-export-to-text filename)))
    (message "Session exported to %s" filename)))

(defun ai-export-to-markdown (filename)
  "Export session to markdown."
  (with-temp-file filename
    (insert (format "# AI Chat Session\n\n"))
    (insert (format "**Provider:** %s\n" (ai-session-provider ai-current-session)))
    (insert (format "**Model:** %s\n\n" (ai-session-model ai-current-session)))
    (dolist (msg (reverse (ai-session-messages ai-current-session)))
      (insert (format "## %s\n\n%s\n\n"
                      (capitalize (plist-get msg :role))
                      (plist-get msg :content))))))

(defun ai-export-to-org (filename)
  "Export session to org format."
  (with-temp-file filename
    (insert-buffer-substring (current-buffer))))

(defun ai-export-to-json (filename)
  "Export session to JSON."
  (ai-save-session filename))

(defun ai-export-to-text (filename)
  "Export session to plain text."
  (with-temp-file filename
    (insert (format "AI Chat Session\nProvider: %s\nModel: %s\n\n"
                    (ai-session-provider ai-current-session)
                    (ai-session-model ai-current-session)))
    (dolist (msg (reverse (ai-session-messages ai-current-session)))
      (insert (format "[%s]\n%s\n\n"
                      (upcase (plist-get msg :role))
                      (plist-get msg :content))))))

(defun ai-select-model ()
  "Select a model for the current provider."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (let* ((provider (ai-session-provider ai-current-session))
         (models (cond
                  ((string= provider "openai") ai-openai-models)
                  ((string= provider "claude") ai-claude-models)
                  ((string= provider "gemini") ai-gemini-models)
                  (t (list (ai-get-provider-model provider)))))
         (model (completing-read (format "Select %s model: " provider) models nil t)))
    (setf (ai-session-model ai-current-session) model)
    (message "Model changed to %s" model)))

(defun ai-copy-last-response ()
  "Copy last assistant response to kill ring."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (let ((messages (ai-session-messages ai-current-session)))
    (when messages
      (let ((last-msg (car messages)))
        (when (string= (plist-get last-msg :role) "assistant")
          (kill-new (plist-get last-msg :content))
          (message "Response copied to kill ring"))))))

(defun ai-edit-last-input ()
  "Edit the last user input."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (save-excursion
    (goto-char (point-max))
    (when (re-search-backward "^\\*\\* User Input" nil t 2)
      (forward-line 1)
      (let ((start (point)))
        (if (re-search-forward "^\\*\\* Assistant Response" nil t)
            (goto-char (line-beginning-position))
          (goto-char (point-max)))
        (goto-char start)))))

(defun ai-view-conversation-stats ()
  "View statistics about current conversation."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (let* ((messages (ai-session-messages ai-current-session))
         (user-count (cl-count-if (lambda (msg) (string= (plist-get msg :role) "user")) messages))
         (assistant-count (cl-count-if (lambda (msg) (string= (plist-get msg :role) "assistant")) messages))
         (total-chars (apply '+ (mapcar (lambda (msg) (length (plist-get msg :content))) messages))))
    (message "Conversation stats: %d user messages, %d assistant responses, %d total characters"
             user-count assistant-count total-chars)))

(defcustom ai-system-prompts
  '(("default" . "You are a helpful AI assistant.")
    ("coder" . "You are an expert programmer. Provide clear, concise code examples and explanations.")
    ("writer" . "You are a professional writer and editor. Help improve writing quality and clarity.")
    ("tutor" . "You are a patient tutor. Explain concepts clearly with examples and check understanding.")
    ("researcher" . "You are a research assistant. Provide detailed, well-sourced information.")
    ("creative" . "You are a creative assistant. Think outside the box and generate innovative ideas."))
  "Predefined system prompts."
  :type '(alist :key-type string :value-type string)
  :group 'ai-integration)

(defcustom ai-default-system-prompt "default"
  "Default system prompt to use."
  :type 'string
  :group 'ai-integration)

(defun ai-set-system-prompt ()
  "Set system prompt for current session."
  (interactive)
  (unless ai-current-session
    (error "No active session"))
  (let* ((prompt-keys (mapcar #'car ai-system-prompts))
         (selected (completing-read "System prompt: " prompt-keys nil nil))
         (prompt (or (cdr (assoc selected ai-system-prompts))
                     (read-string "Custom system prompt: "))))
    (let ((messages (ai-session-messages ai-current-session)))
      (unless (and messages (string= (plist-get (car (last messages)) :role) "system"))
        (setf (ai-session-messages ai-current-session)
              (append messages (list (list :role "system" :content prompt))))))
    (message "System prompt set")))

(defun ai-quick-action (action)
  "Perform quick AI action."
  (interactive
   (list (completing-read "Quick action: "
                          '("Explain error"
                            "Generate test"
                            "Add documentation"
                            "Improve naming"
                            "Extract function"
                            "Add type hints"
                            "Generate docstring"
                            "Find bugs"
                            "Optimize performance"
                            "Add error handling"))))
  (let ((region-text (if (use-region-p)
                         (buffer-substring-no-properties (region-beginning) (region-end))
                       (thing-at-point 'defun))))
    (unless region-text
      (error "No code selected"))
    (ai-with-template
     (format "Please %s for this code:\n\n```%s\n%s\n```"
             (downcase action)
             (replace-regexp-in-string "-mode$" "" (symbol-name major-mode))
             region-text))))

(defcustom ai-conversation-templates
  '(("code-review" .
     "I need you to review this code. Please check for:
1. Bugs and potential issues
2. Performance problems
3. Security vulnerabilities
4. Code style and best practices
5. Suggestions for improvement
Here's the code:")
    ("explain-error" .
     "I'm getting this error. Please explain what it means and how to fix it:")
    ("refactor" .
     "Please refactor this code to be more clean, efficient, and maintainable:")
    ("test" .
     "Please write comprehensive tests for this code:")
    ("document" .
     "Please add clear documentation and comments to this code:"))
  "Conversation starter templates."
  :type '(alist :key-type string :value-type string)
  :group 'ai-integration)

(defun ai-use-template ()
  "Insert a conversation template."
  (interactive)
  (let* ((template-keys (mapcar #'car ai-conversation-templates))
         (selected (completing-read "Template: " template-keys nil t))
         (template (cdr (assoc selected ai-conversation-templates))))
    (when template
      (ai-replace-current-input template))))

(defun ai-describe-bindings ()
  "Show all AI integration key bindings."
  (interactive)
  (with-help-window "*AI Integration Bindings*"
    (princ "AI Integration Key Bindings\n")
    (princ "==========================\n\n")
    (princ "Session Management:\n")
    (princ "  C-c a RET    - Start AI chat\n")
    (princ "  C-c a n      - New session\n")
    (princ "  C-c a s      - Save session\n")
    (princ "  C-c a l      - Load session\n")
    (princ "  C-c a k      - Cancel request\n\n")
    (princ "Code Commands (C-c a c):\n")
    (princ "  e r/b/p/f    - Explain region/buffer/point/file\n")
    (princ "  f r/b/p/f    - Fix code\n")
    (princ "  r r/b/p/f    - Review code\n")
    (princ "  s r/b/p/f    - Security review\n")
    (princ "  p r/b/p/f    - Performance review\n")
    (princ "  y r/b/p/f    - Style review\n")
    (princ "  b r/b/p/f    - Bug review\n")
    (princ "  TAB          - Complete at point\n\n")
    (princ "Text Commands (C-c a t):\n")
    (princ "  s r/b/p/f    - Fix style\n")
    (princ "  g r/b/p/f    - Fix grammar\n")
    (princ "  l r/b/p/f    - Fix spelling\n")
    (princ "  e r/b/p/f    - Explain text\n\n")
    (princ "Send Commands (C-c a S):\n")
    (princ "  r/b/f/p      - Send to existing session\n")
    (princ "  R/B/F/P      - Send to new session\n\n")
    (princ "Other Commands:\n")
    (princ "  C-c a q      - Quick actions\n")
    (princ "  C-c a p      - Change provider\n")
    (princ "  C-c a o/C/g  - Switch to OpenAI/Claude/Gemini\n")
    (princ "  C-c a v      - Toggle streaming\n")
    (princ "  C-c a d      - Toggle debug\n\n")
    (princ "In AI Chat buffers:\n")
    (princ "  C-c C-c      - Send input\n")
    (princ "  C-c C-m      - Select model\n")
    (princ "  C-c C-y      - Copy last response\n")
    (princ "  C-c C-x s    - Set system prompt\n")
    (princ "  C-c C-x t    - Use template\n")))

(defun ai-test-provider-selection ()
  "Test provider selection logic."
  (let ((ai-default-provider "openai"))
    (should (string= (ai-get-provider-model "openai") "gpt-4o"))
    (should (ai-get-provider "openai"))))

(defun ai-test-session-management ()
  "Test session creation and cleanup."
  (let ((session (ai-create-session)))
    (should (ai-session-p session))
    (should (buffer-live-p (ai-session-buffer session)))
    (kill-buffer (ai-session-buffer session))
    (ai-cleanup-sessions)
    (should-not (memq session ai-sessions))))

(defun ai-test-streaming ()
  "Test streaming with a simple request."
  (interactive)
  (ai-diagnose-streaming)
  (when (y-or-n-p "Continue with streaming test? ")
    (let ((session (ai-create-session)))
      (with-current-buffer (ai-session-buffer session)
        (setq ai-streaming-enabled t)
        (setq ai-debug-enabled t)
        (switch-to-buffer (current-buffer))
        (goto-char (point-max))
        (ai-replace-current-input "Say 'Hello' - this is a streaming test")
        (ai-send-input)))))

(defun ai-test-buffer-naming ()
  "Test buffer naming system."
  (interactive)
  (let ((test-buffer (get-buffer-create "*test-buffer*")))
    (dotimes (i 3)
      (let ((session (ai-create-session test-buffer)))
        (message "Created session %d: %s" (1+ i) (ai-session-name session))))
    (kill-buffer test-buffer)))

(defun ai-debug-session-state ()
  "Debug current session state."
  (interactive)
  (if ai-current-session
      (message "Session: %s, Provider: %s, Status: %s, Messages: %d"
               (ai-session-name ai-current-session)
               (ai-session-provider ai-current-session)
               ai-current-status
               (length (ai-session-messages ai-current-session)))
    (message "No active session")))

(defun ai-initialize ()
  "Initialize AI integration."
  (unless (file-exists-p ai-conversation-directory)
    (make-directory ai-conversation-directory t))
  (add-hook 'kill-emacs-hook 'ai-cleanup-sessions)
  (add-hook 'buffer-list-update-hook 'ai-cleanup-sessions))

(ai-initialize)

(provide 'ai-integration)
