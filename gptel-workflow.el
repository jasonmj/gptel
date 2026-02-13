;;; gptel-workflow.el --- LLM workflow dispatcher for gptel  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; Author: Karthik Chikmagalur <karthikchikmagalur@gmail.com>
;; Keywords: convenience, tools

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; gptel-workflow provides a standalone workflow dispatcher for orchestrating
;; chained, validated LLM workflows (plan → diff → tests → review → checklist).
;;
;; Key features:
;; - Works standalone (no gptel required) with pluggable LLM backend
;; - Auto-detects and prefers gptel when available
;; - Named presets with model routing (fast-low, strong-medium, strong-low)
;; - Acceptance criteria (AC) handling with tagging and citation validation
;; - Step runners for plan, diff, tests, review, checklist
;; - Validation gates for each step with human override
;; - Transient/minibuffer UX for workflow management
;; - Context capture and hygiene (region/defun, pruning, summarization)
;; - Logging and observability
;; - Public API with comprehensive ERT tests

;;; Code:

(require 'cl-lib)
(eval-when-compile (require 'subr-x))

;; Try to load gptel-request but don't require it
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-temperature)
(defvar gptel-max-tokens)
(declare-function gptel-request "gptel-request")
(declare-function gptel-backend-name "gptel-request")

;;; Customization

(defgroup gptel-workflow nil
  "LLM workflow dispatcher for gptel."
  :group 'gptel
  :prefix "gptel-workflow-")

(defcustom gptel-workflow-backend-function nil
  "Function to send LLM requests when gptel is not available.

Should accept a plist with keys:
  :prompt     - The prompt string
  :system     - The system message string
  :model      - Model name/symbol
  :temperature - Temperature value
  :max-tokens - Maximum tokens
  :callback   - Function to call with (response info)

If nil and gptel is available, uses gptel-request.
If nil and gptel is not available, uses a mock backend."
  :type '(choice (const :tag "Auto (gptel or mock)" nil)
                 (function :tag "Custom backend function")))

(defcustom gptel-workflow-presets
  '((fast-low
     :description "Fast responses with low cost"
     :model "gpt-3.5-turbo"
     :temperature 0.3
     :max-tokens 2000)
    (strong-medium
     :description "Strong model with medium length"
     :model "gpt-4"
     :temperature 0.5
     :max-tokens 4000)
    (strong-low
     :description "Strong model with low cost"
     :model "gpt-4"
     :temperature 0.3
     :max-tokens 2000))
  "Named presets for gptel-workflow.

Each preset is a plist with keys:
  :description - Description of the preset
  :model       - Model name
  :temperature - Temperature value (0.0-1.0)
  :max-tokens  - Maximum tokens to generate"
  :type '(alist :key-type symbol
                :value-type plist))

(defcustom gptel-workflow-step-presets
  '((plan . strong-medium)
    (diff . strong-low)
    (tests . strong-low)
    (tests-integration . strong-low)
    (review . strong-low)
    (checklist . fast-low)
    (summary . fast-low))
  "Default preset routing for workflow steps."
  :type '(alist :key-type symbol :value-type symbol))

(defcustom gptel-workflow-allowed-paths
  '("*.el" "*.py" "*.js" "*.ts" "*.java" "*.c" "*.cpp" "*.go" "*.rs")
  "List of file path globs that diffs are allowed to touch."
  :type '(repeat string))

(defcustom gptel-workflow-test-path-patterns
  '("test-*.el" "*-test.el" "test/*.el" "tests/*.el"
    "test_*.py" "*_test.py" "test/*.py" "tests/*.py"
    "*.test.js" "*.test.ts" "test/*.js" "tests/*.ts")
  "Patterns for identifying test files."
  :type '(repeat string))

(defcustom gptel-workflow-context-max-chars 50000
  "Maximum characters to include in context before pruning."
  :type 'integer)

(defcustom gptel-workflow-summarize-before-plan nil
  "If non-nil, summarize large contexts before generating plan."
  :type 'boolean)

;;; State structure

(cl-defstruct (gptel-workflow-state
               (:constructor gptel-workflow-state-create)
               (:copier nil))
  "State for a workflow run."
  (step nil :documentation "Current step symbol")
  (acs nil :documentation "List of acceptance criteria strings")
  (context nil :documentation "Raw context string")
  (context-summary nil :documentation "Optional context summary")
  (plan nil :documentation "Generated plan string")
  (diff nil :documentation "Generated diff string")
  (tests nil :documentation "Generated tests string")
  (tests-integration nil :documentation "Generated integration tests string")
  (review nil :documentation "Generated review string")
  (checklist nil :documentation "Generated checklist string")
  (continue-flag t :documentation "Whether to continue to next step")
  (integration-test-flag nil :documentation "Whether to run integration tests")
  (preset-override nil :documentation "Override preset for current step")
  (validation-results nil :documentation "List of validation results")
  (log-entries nil :documentation "List of log entries"))

;;; Backend abstraction

(defun gptel-workflow--gptel-available-p ()
  "Return non-nil if gptel is available."
  (and (fboundp 'gptel-request)
       (boundp 'gptel-backend)))

(defun gptel-workflow--mock-backend (request-plist)
  "Mock backend for testing without network access.
REQUEST-PLIST should contain :prompt, :callback, and :system."
  (let ((callback (plist-get request-plist :callback))
        (prompt (plist-get request-plist :prompt)))
    (when callback
      (run-at-time
       0.1 nil
       (lambda ()
         (funcall callback
                  (format "Mock response for prompt: %s..."
                          (substring prompt 0 (min 50 (length prompt))))
                  '(:status "Mock OK")))))))

(defun gptel-workflow--send-request (prompt system preset callback)
  "Send LLM request with PROMPT, SYSTEM message, PRESET, and CALLBACK.

CALLBACK is called with (response info) where response is a string
or nil on error."
  (let* ((preset-spec (alist-get preset gptel-workflow-presets))
         (model (plist-get preset-spec :model))
         (temperature (plist-get preset-spec :temperature))
         (max-tokens (plist-get preset-spec :max-tokens))
         (request-plist `(:prompt ,prompt
                          :system ,system
                          :model ,model
                          :temperature ,temperature
                          :max-tokens ,max-tokens
                          :callback ,callback)))
    (cond
     ;; Use custom backend if provided
     (gptel-workflow-backend-function
      (funcall gptel-workflow-backend-function request-plist))
     
     ;; Use gptel if available
     ((gptel-workflow--gptel-available-p)
      (let ((gptel-model model))
        (gptel-request prompt
                       :callback callback
                       :system system)))
     
     ;; Fall back to mock backend
     (t
      (gptel-workflow--mock-backend request-plist)))))

;;; Logging

(defvar gptel-workflow--log-buffer "*gptel-workflow-log*"
  "Buffer name for workflow logging.")

(defun gptel-workflow--log (state format-string &rest args)
  "Log a message to the workflow log buffer.
STATE is the current workflow state.
FORMAT-STRING and ARGS are passed to `format'."
  (let ((message (apply #'format format-string args))
        (timestamp (format-time-string "%Y-%m-%d %H:%M:%S"))
        (step (gptel-workflow-state-step state)))
    (with-current-buffer (get-buffer-create gptel-workflow--log-buffer)
      (goto-char (point-max))
      (insert (format "[%s] [%s] %s\n" timestamp step message)))
    ;; Also add to state log entries
    (push (list :timestamp timestamp
                :step step
                :message message)
          (gptel-workflow-state-log-entries state))))

;;; Context capture and hygiene

(defun gptel-workflow--capture-context (source)
  "Capture context from SOURCE.

SOURCE can be:
  'region - Active region
  'defun  - Current defun
  'buffer - Entire buffer"
  (pcase source
    ('region
     (if (use-region-p)
         (buffer-substring-no-properties (region-beginning) (region-end))
       (error "No active region")))
    ('defun
     (save-excursion
       (mark-defun)
       (buffer-substring-no-properties (region-beginning) (region-end))))
    ('buffer
     (buffer-substring-no-properties (point-min) (point-max)))
    (_ (error "Unknown context source: %s" source))))

(defun gptel-workflow--prune-context (context)
  "Prune CONTEXT if it exceeds `gptel-workflow-context-max-chars'.

Returns pruned context string with indication of pruning."
  (if (<= (length context) gptel-workflow-context-max-chars)
      context
    (concat (substring context 0 gptel-workflow-context-max-chars)
            "\n\n[... context pruned ...]")))

(defun gptel-workflow--summarize-context (context callback)
  "Summarize CONTEXT using fast-low preset.
Calls CALLBACK with (summary info) when complete."
  (let ((prompt (format "Summarize this code context concisely:\n\n%s" context))
        (system "You are a code summarization assistant. Provide brief, technical summaries."))
    (gptel-workflow--send-request prompt system 'fast-low callback)))

;;; Acceptance Criteria (AC) handling

(defun gptel-workflow--tag-acs (acs)
  "Tag acceptance criteria strings in ACS list.
Returns alist of (tag . ac-text)."
  (cl-loop for ac in acs
           for i from 1
           collect (cons (format "AC%d" i) ac)))

(defun gptel-workflow--format-acs-for-prompt (tagged-acs)
  "Format TAGGED-ACS for inclusion in prompts."
  (if (null tagged-acs)
      ""
    (concat "\n\nAcceptance Criteria:\n"
            (mapconcat (lambda (pair)
                         (format "- %s: %s" (car pair) (cdr pair)))
                       tagged-acs
                       "\n"))))

(defun gptel-workflow--validate-ac-citations (text tagged-acs)
  "Validate that TEXT cites all AC tags from TAGGED-ACS.
Returns (valid . missing-tags)."
  (if (null tagged-acs)
      '(t)
    (let ((missing-tags
           (cl-remove-if (lambda (pair)
                           (string-match-p (regexp-quote (car pair)) text))
                         tagged-acs)))
      (cons (null missing-tags)
            (mapcar #'car missing-tags)))))

;;; Validation gates

(defun gptel-workflow--validate-plan (plan tagged-acs)
  "Validate PLAN output.
Returns (valid-p . issues) where issues is a list of problem strings."
  (let ((issues nil))
    ;; Check for bullets
    (unless (string-match-p "^[*-]\\|^[0-9]+\\." plan)
      (push "Plan does not contain bullet points or numbered list" issues))
    
    ;; Check AC citations
    (let ((ac-result (gptel-workflow--validate-ac-citations plan tagged-acs)))
      (unless (car ac-result)
        (push (format "Plan missing AC citations: %s"
                      (mapconcat #'identity (cdr ac-result) ", "))
              issues)))
    
    (cons (null issues) issues)))

(defun gptel-workflow--validate-diff (diff tagged-acs)
  "Validate DIFF output.
Returns (valid-p . issues)."
  (let ((issues nil))
    ;; Check non-empty
    (when (string-blank-p diff)
      (push "Diff is empty" issues))
    
    ;; Check unified diff format
    (unless (string-match-p "^\\(---\\|\\+\\+\\+\\|@@\\)" diff)
      (push "Diff is not in unified diff format" issues))
    
    ;; Check AC citations
    (let ((ac-result (gptel-workflow--validate-ac-citations diff tagged-acs)))
      (unless (car ac-result)
        (push (format "Diff missing AC citations: %s"
                      (mapconcat #'identity (cdr ac-result) ", "))
              issues)))
    
    (cons (null issues) issues)))

(defun gptel-workflow--validate-tests (tests tagged-acs behavior-changed-p)
  "Validate TESTS output.
BEHAVIOR-CHANGED-P indicates if code behavior changed.
Returns (valid-p . issues)."
  (let ((issues nil))
    ;; Check that tests touch test paths when behavior changed
    (when behavior-changed-p
      (let ((has-test-paths
             (cl-some (lambda (pattern)
                        (string-match-p pattern tests))
                      gptel-workflow-test-path-patterns)))
        (unless has-test-paths
          (push "Tests do not touch expected test paths" issues))))
    
    ;; Check for unified diff format (if tests are diffs)
    (when (string-match-p "^\\(---\\|\\+\\+\\+\\)" tests)
      (unless (string-match-p "^@@" tests)
        (push "Test diff missing hunk markers" issues)))
    
    (cons (null issues) issues)))

(defun gptel-workflow--validate-review (review)
  "Validate REVIEW output.
Returns (valid-p . issues)."
  (let ((issues nil))
    ;; Check non-empty bullets
    (unless (string-match-p "^[*-]\\|^[0-9]+\\." review)
      (push "Review does not contain bullet points" issues))
    
    ;; Check for key sections
    (unless (or (string-match-p "risk" review)
                (string-match-p "concern" review)
                (string-match-p "issue" review))
      (push "Review should mention risks or concerns" issues))
    
    (cons (null issues) issues)))

(defun gptel-workflow--confirm-validation (step validation-result)
  "Ask user to confirm validation result for STEP.
VALIDATION-RESULT is (valid-p . issues).
Returns non-nil if user confirms proceeding despite issues."
  (if (car validation-result)
      t  ; Valid, proceed
    (let ((issues (cdr validation-result)))
      (yes-or-no-p
       (format "Validation failed for %s:\n%s\n\nProceed anyway? "
               step
               (mapconcat #'identity issues "\n"))))))

;;; Output buffer

(defvar gptel-workflow--output-buffer "*gptel-workflow-output*"
  "Buffer name for workflow output.")

(defun gptel-workflow--append-output (step content)
  "Append CONTENT for STEP to the output buffer."
  (with-current-buffer (get-buffer-create gptel-workflow--output-buffer)
    (goto-char (point-max))
    (insert (format "\n\n=== %s ===\n\n%s\n" (upcase (symbol-name step)) content))))

;;; Step runners

(defun gptel-workflow--make-prompt-plan (context tagged-acs)
  "Create prompt for plan step with CONTEXT and TAGGED-ACS."
  (format "Generate an implementation plan for the following task.\n\nTask context:\n%s%s\n\nProvide a clear, bulleted plan that addresses all acceptance criteria."
          context
          (gptel-workflow--format-acs-for-prompt tagged-acs)))

(defun gptel-workflow--make-prompt-diff (plan context tagged-acs)
  "Create prompt for diff step with PLAN, CONTEXT, and TAGGED-ACS."
  (format "Based on this plan:\n\n%s\n\nAnd this context:\n%s%s\n\nGenerate a unified diff showing the changes needed. Format as standard unified diff with --- and +++ headers."
          plan
          context
          (gptel-workflow--format-acs-for-prompt tagged-acs)))

(defun gptel-workflow--make-prompt-tests (plan diff context tagged-acs integration-flag)
  "Create prompt for tests step.
PLAN, DIFF, CONTEXT, TAGGED-ACS, and INTEGRATION-FLAG control the output."
  (format "Based on this plan:\n\n%s\n\nAnd these changes:\n%s\n\nGenerate %s tests. Include test code as unified diffs touching test files.%s"
          plan
          diff
          (if integration-flag "integration" "unit")
          (gptel-workflow--format-acs-for-prompt tagged-acs)))

(defun gptel-workflow--make-prompt-review (plan diff tests context)
  "Create prompt for review step with PLAN, DIFF, TESTS, and CONTEXT."
  (format "Review this implementation:\n\nPlan:\n%s\n\nDiff:\n%s\n\nTests:\n%s\n\nProvide a bulleted review covering:\n- Potential risks\n- Missing tests\n- Alternative approaches"
          plan diff tests))

(defun gptel-workflow--make-prompt-checklist (plan diff tests review)
  "Create prompt for checklist step with PLAN, DIFF, TESTS, and REVIEW."
  (format "Create a final checklist for this implementation:\n\nPlan:\n%s\n\nDiff:\n%s\n\nTests:\n%s\n\nReview:\n%s\n\nGenerate a markdown checklist of verification items."
          plan diff tests review))

;;;###autoload
(defun gptel-workflow-plan (state)
  "Execute plan step for workflow STATE.
Generates an implementation plan based on context and ACs."
  (interactive
   (list (or gptel-workflow--current-state
             (gptel-workflow-state-create))))
  (let* ((context (or (gptel-workflow-state-context state)
                      (error "No context in state")))
         (tagged-acs (gptel-workflow--tag-acs (gptel-workflow-state-acs state)))
         (prompt (gptel-workflow--make-prompt-plan context tagged-acs))
         (system "You are a software architect. Generate clear, actionable plans.")
         (preset (or (gptel-workflow-state-preset-override state)
                     (alist-get 'plan gptel-workflow-step-presets))))
    
    (setf (gptel-workflow-state-step state) 'plan)
    (gptel-workflow--log state "Starting plan step with preset %s" preset)
    
    (gptel-workflow--send-request
     prompt system preset
     (lambda (response info)
       (if response
           (progn
             (setf (gptel-workflow-state-plan state) response)
             (gptel-workflow--append-output 'plan response)
             (let* ((validation (gptel-workflow--validate-plan response tagged-acs))
                    (valid (car validation)))
               (gptel-workflow--log state "Plan generated: %s"
                                    (if valid "valid" "invalid"))
               (when (not valid)
                 (gptel-workflow--log state "Validation issues: %s"
                                      (mapconcat #'identity (cdr validation) "; ")))
               (when (gptel-workflow--confirm-validation 'plan validation)
                 (message "Plan step completed"))))
         (gptel-workflow--log state "Plan step failed: %s"
                              (plist-get info :status))
         (message "Plan generation failed"))))))

;;;###autoload
(defun gptel-workflow-diff (state)
  "Execute diff step for workflow STATE.
Generates a unified diff based on plan and context."
  (interactive
   (list (or gptel-workflow--current-state
             (gptel-workflow-state-create))))
  (let* ((plan (or (gptel-workflow-state-plan state)
                   (error "No plan in state - run plan step first")))
         (context (or (gptel-workflow-state-context state)
                      (error "No context in state")))
         (tagged-acs (gptel-workflow--tag-acs (gptel-workflow-state-acs state)))
         (prompt (gptel-workflow--make-prompt-diff plan context tagged-acs))
         (system "You are a code generator. Produce accurate unified diffs.")
         (preset (or (gptel-workflow-state-preset-override state)
                     (alist-get 'diff gptel-workflow-step-presets))))
    
    (setf (gptel-workflow-state-step state) 'diff)
    (gptel-workflow--log state "Starting diff step with preset %s" preset)
    
    (gptel-workflow--send-request
     prompt system preset
     (lambda (response info)
       (if response
           (progn
             (setf (gptel-workflow-state-diff state) response)
             (gptel-workflow--append-output 'diff response)
             (let* ((validation (gptel-workflow--validate-diff response tagged-acs))
                    (valid (car validation)))
               (gptel-workflow--log state "Diff generated: %s"
                                    (if valid "valid" "invalid"))
               (when (not valid)
                 (gptel-workflow--log state "Validation issues: %s"
                                      (mapconcat #'identity (cdr validation) "; ")))
               (when (gptel-workflow--confirm-validation 'diff validation)
                 (message "Diff step completed"))))
         (gptel-workflow--log state "Diff step failed: %s"
                              (plist-get info :status))
         (message "Diff generation failed"))))))

;;;###autoload
(defun gptel-workflow-tests (state &optional integration)
  "Execute tests step for workflow STATE.
If INTEGRATION is non-nil, generate integration tests instead of unit tests."
  (interactive
   (list (or gptel-workflow--current-state
             (gptel-workflow-state-create))))
  (let* ((plan (or (gptel-workflow-state-plan state)
                   (error "No plan in state")))
         (diff (or (gptel-workflow-state-diff state)
                   (error "No diff in state")))
         (context (or (gptel-workflow-state-context state)
                      (error "No context in state")))
         (integration-flag (or integration
                               (gptel-workflow-state-integration-test-flag state)))
         (tagged-acs (gptel-workflow--tag-acs (gptel-workflow-state-acs state)))
         (prompt (gptel-workflow--make-prompt-tests plan diff context tagged-acs integration-flag))
         (system "You are a test engineer. Generate comprehensive tests.")
         (preset (or (gptel-workflow-state-preset-override state)
                     (alist-get (if integration-flag 'tests-integration 'tests)
                                gptel-workflow-step-presets))))
    
    (setf (gptel-workflow-state-step state)
          (if integration-flag 'tests-integration 'tests))
    (gptel-workflow--log state "Starting tests step (integration: %s) with preset %s"
                         integration-flag preset)
    
    (gptel-workflow--send-request
     prompt system preset
     (lambda (response info)
       (if response
           (progn
             (if integration-flag
                 (setf (gptel-workflow-state-tests-integration state) response)
               (setf (gptel-workflow-state-tests state) response))
             (gptel-workflow--append-output
              (if integration-flag 'tests-integration 'tests)
              response)
             (let* ((validation (gptel-workflow--validate-tests response tagged-acs t))
                    (valid (car validation)))
               (gptel-workflow--log state "Tests generated: %s"
                                    (if valid "valid" "invalid"))
               (when (not valid)
                 (gptel-workflow--log state "Validation issues: %s"
                                      (mapconcat #'identity (cdr validation) "; ")))
               (when (gptel-workflow--confirm-validation 'tests validation)
                 (message "Tests step completed"))))
         (gptel-workflow--log state "Tests step failed: %s"
                              (plist-get info :status))
         (message "Tests generation failed"))))))

;;;###autoload
(defun gptel-workflow-review (state)
  "Execute review step for workflow STATE.
Reviews the plan, diff, and tests."
  (interactive
   (list (or gptel-workflow--current-state
             (gptel-workflow-state-create))))
  (let* ((plan (or (gptel-workflow-state-plan state)
                   (error "No plan in state")))
         (diff (or (gptel-workflow-state-diff state)
                   (error "No diff in state")))
         (tests (or (gptel-workflow-state-tests state)
                    (error "No tests in state")))
         (context (or (gptel-workflow-state-context state)
                      (error "No context in state")))
         (prompt (gptel-workflow--make-prompt-review plan diff tests context))
         (system "You are a senior code reviewer. Provide constructive feedback.")
         (preset (or (gptel-workflow-state-preset-override state)
                     (alist-get 'review gptel-workflow-step-presets))))
    
    (setf (gptel-workflow-state-step state) 'review)
    (gptel-workflow--log state "Starting review step with preset %s" preset)
    
    (gptel-workflow--send-request
     prompt system preset
     (lambda (response info)
       (if response
           (progn
             (setf (gptel-workflow-state-review state) response)
             (gptel-workflow--append-output 'review response)
             (let* ((validation (gptel-workflow--validate-review response))
                    (valid (car validation)))
               (gptel-workflow--log state "Review generated: %s"
                                    (if valid "valid" "invalid"))
               (when (not valid)
                 (gptel-workflow--log state "Validation issues: %s"
                                      (mapconcat #'identity (cdr validation) "; ")))
               (when (gptel-workflow--confirm-validation 'review validation)
                 (message "Review step completed"))))
         (gptel-workflow--log state "Review step failed: %s"
                              (plist-get info :status))
         (message "Review generation failed"))))))

;;;###autoload
(defun gptel-workflow-checklist (state)
  "Execute checklist step for workflow STATE.
Generates final checklist from all previous steps."
  (interactive
   (list (or gptel-workflow--current-state
             (gptel-workflow-state-create))))
  (let* ((plan (or (gptel-workflow-state-plan state) ""))
         (diff (or (gptel-workflow-state-diff state) ""))
         (tests (or (gptel-workflow-state-tests state) ""))
         (review (or (gptel-workflow-state-review state) ""))
         (prompt (gptel-workflow--make-prompt-checklist plan diff tests review))
         (system "You are a project manager. Generate actionable checklists.")
         (preset (or (gptel-workflow-state-preset-override state)
                     (alist-get 'checklist gptel-workflow-step-presets))))
    
    (setf (gptel-workflow-state-step state) 'checklist)
    (gptel-workflow--log state "Starting checklist step with preset %s" preset)
    
    (gptel-workflow--send-request
     prompt system preset
     (lambda (response info)
       (if response
           (progn
             (setf (gptel-workflow-state-checklist state) response)
             (gptel-workflow--append-output 'checklist response)
             (gptel-workflow--log state "Checklist generated")
             (message "Checklist step completed"))
         (gptel-workflow--log state "Checklist step failed: %s"
                              (plist-get info :status))
         (message "Checklist generation failed"))))))

;;; Current state management

(defvar gptel-workflow--current-state nil
  "Current workflow state for interactive use.")

;;;###autoload
(defun gptel-workflow-new (context-source)
  "Start a new workflow with context from CONTEXT-SOURCE.
CONTEXT-SOURCE can be 'region, 'defun, or 'buffer."
  (interactive
   (list (intern (completing-read "Context source: "
                                  '(region defun buffer)
                                  nil t))))
  (let* ((context (gptel-workflow--capture-context context-source))
         (context (gptel-workflow--prune-context context))
         (acs-input (read-string "Acceptance criteria (one per line, empty to finish): "))
         (acs (when (not (string-blank-p acs-input))
                (split-string acs-input "\n" t "[ \t]+")))
         (state (gptel-workflow-state-create
                 :context context
                 :acs acs)))
    (setq gptel-workflow--current-state state)
    (gptel-workflow--log state "New workflow created from %s" context-source)
    (message "Workflow created. Use gptel-workflow-plan to start.")
    state))

;;;###autoload
(defun gptel-workflow-show-output ()
  "Show the workflow output buffer."
  (interactive)
  (pop-to-buffer gptel-workflow--output-buffer))

;;;###autoload
(defun gptel-workflow-show-log ()
  "Show the workflow log buffer."
  (interactive)
  (pop-to-buffer gptel-workflow--log-buffer))

;;; Public API

(defun gptel-workflow-get-state ()
  "Get the current workflow state."
  gptel-workflow--current-state)

(defun gptel-workflow-set-state (state)
  "Set the current workflow STATE."
  (setq gptel-workflow--current-state state))

(provide 'gptel-workflow)
;;; gptel-workflow.el ends here
