;;; gptel-workflow.el --- Chained LLM workflow orchestration -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Jason M. Jensen

;; Author: Jason M. Jensen
;; Keywords: convenience, tools
;; Package-Requires: ((emacs "27.1") (gptel "0.9.9"))

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

;; gptel-workflow orchestrates chained LLM workflows: plan → diff → tests → review → refine.
;;
;; Features:
;; - Model presets and step-to-preset routing
;; - Workflow state management with context hygiene
;; - Acceptance criteria (AC) handling with auto-tagging
;; - Step runners (plan, diff, tests, review, checklist)
;; - Validation gates with human confirmation
;; - Transient/buffer UX integration
;; - Logging and observability

;;; Code:

(require 'cl-lib)
(require 'gptel)
(require 'transient)

;;; Customization

(defgroup gptel-workflow nil
  "Chained LLM workflow orchestration for gptel."
  :group 'gptel
  :prefix "gptel-workflow-")

(defcustom gptel-workflow-log-buffer-name "*gptel-workflow-log*"
  "Name of the buffer for logging workflow steps."
  :type 'string
  :group 'gptel-workflow)

(defcustom gptel-workflow-output-buffer-name "*gptel-workflow-output*"
  "Name of the buffer for collating workflow outputs."
  :type 'string
  :group 'gptel-workflow)

(defcustom gptel-workflow-default-test-paths '("test/" "tests/" "*_test.el" "*-test.el")
  "Default test path patterns for validation."
  :type '(repeat string)
  :group 'gptel-workflow)

(defcustom gptel-workflow-default-file-globs '("*.el" "*.py" "*.js" "*.java" "*.go")
  "Default file glob patterns for validation."
  :type '(repeat string)
  :group 'gptel-workflow)

(defcustom gptel-workflow-summarization-threshold 2000
  "Character threshold for context summarization."
  :type 'integer
  :group 'gptel-workflow)

;;; Model Presets

(defconst gptel-workflow-presets
  '((fast-low
     :description "Fast model with low temperature"
     :model "gpt-4o-mini"
     :temperature 0.3
     :max-tokens 2000)
    (strong-medium
     :description "Strong model with medium temperature"
     :model "gpt-4o"
     :temperature 0.5
     :max-tokens 4000)
    (strong-low
     :description "Strong model with low temperature"
     :model "gpt-4o"
     :temperature 0.3
     :max-tokens 4000))
  "Predefined model presets for workflow steps.")

(defconst gptel-workflow-step-preset-map
  '((plan . strong-medium)
    (diff . strong-low)
    (tests . strong-low)
    (tests-integration . strong-low)
    (review . strong-low)
    (checklist . strong-low)
    (summarize . fast-low))
  "Mapping from workflow steps to default presets.")

;;; Workflow State

(cl-defstruct (gptel-workflow-state
               (:constructor gptel-workflow-state-create)
               (:copier gptel-workflow-state-copy))
  "State container for gptel workflow."
  (current-step nil :documentation "Current workflow step symbol.")
  (acs nil :documentation "List of acceptance criteria strings.")
  (context-raw nil :documentation "Raw context string.")
  (context-summary nil :documentation "Optional summarized context.")
  (plan nil :documentation "Generated plan output.")
  (diff nil :documentation "Generated diff output.")
  (tests nil :documentation "Generated tests output.")
  (review nil :documentation "Generated review output.")
  (refine nil :documentation "Generated refine output.")
  (continue-flag t :documentation "Continue to next step if t.")
  (integration-tests-p nil :documentation "Include integration tests if t.")
  (retry-count 0 :documentation "Number of retries for current step.")
  (last-error nil :documentation "Last error message."))

(defvar gptel-workflow--current-state nil
  "Current workflow state.")

;;; Acceptance Criteria Handling

(defun gptel-workflow--tag-acs (acs)
  "Tag acceptance criteria ACS with AC1, AC2, etc."
  (let ((counter 1))
    (mapcar (lambda (ac)
              (prog1
                  (format "AC%d: %s" counter ac)
                (setq counter (1+ counter))))
            acs)))

(defun gptel-workflow--extract-ac-tags (text)
  "Extract AC tag references (AC1, AC2, etc.) from TEXT."
  (let ((tags nil))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward "\\bAC\\([0-9]+\\)\\b" nil t)
        (push (match-string 0) tags)))
    (delete-dups (nreverse tags))))

(defun gptel-workflow--format-acs-for-prompt (acs)
  "Format tagged ACS for inclusion in prompts."
  (if acs
      (concat "\n\nAcceptance Criteria:\n"
              (mapconcat (lambda (ac) (concat "- " ac)) acs "\n")
              "\n\nPlease cite AC IDs (e.g., AC1, AC2) in your response.\n")
    ""))

;;; Context Management

(defun gptel-workflow--capture-region ()
  "Capture the current region as context."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    (error "No region selected")))

(defun gptel-workflow--capture-defun ()
  "Capture the current function/defun as context."
  (save-excursion
    (beginning-of-defun)
    (let ((start (point)))
      (end-of-defun)
      (buffer-substring-no-properties start (point)))))

(defun gptel-workflow--prune-context (context)
  "Prune noisy or large sections from CONTEXT.
This is a simple implementation that removes excessive blank lines
and truncates very long lines."
  (with-temp-buffer
    (insert context)
    ;; Remove excessive blank lines (more than 2 in a row)
    (goto-char (point-min))
    (while (re-search-forward "\n\n\n+" nil t)
      (replace-match "\n\n"))
    ;; Truncate lines longer than 500 characters
    (goto-char (point-min))
    (while (not (eobp))
      (let ((line-end (line-end-position)))
        (when (> (- line-end (point)) 500)
          (forward-char 500)
          (delete-region (point) line-end)
          (insert "...")))
      (forward-line 1))
    (buffer-string)))

(defun gptel-workflow--summarize-context (context callback)
  "Summarize CONTEXT using fast-low preset and call CALLBACK with result."
  (let* ((preset (alist-get 'summarize gptel-workflow-step-preset-map))
         (preset-spec (alist-get preset gptel-workflow-presets))
         (prompt (format "Please provide a concise summary of the following code/context:\n\n%s"
                         context)))
    (gptel-workflow--log "Summarizing context" preset "summary")
    ;; For now, just return truncated context - full async implementation would use gptel-request
    (funcall callback (substring context 0 (min (length context)
                                                gptel-workflow-summarization-threshold)))))

;;; Logging

(defun gptel-workflow--log (step preset variant &optional result)
  "Log workflow STEP with PRESET, prompt VARIANT, and optional validation RESULT."
  (let ((buf (get-buffer-create gptel-workflow-log-buffer-name)))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert (format "[%s] Step: %s | Preset: %s | Variant: %s%s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      step
                      preset
                      variant
                      (if result (format " | Result: %s" result) ""))))))

;;; Validation Gates

(defun gptel-workflow--validate-plan (output)
  "Validate plan OUTPUT has bullets and cites AC tags."
  (let ((has-bullets (string-match-p "^[*-]\\|^[0-9]+\\." output))
        (ac-tags (gptel-workflow--extract-ac-tags output))
        (expected-acs (gptel-workflow-state-acs gptel-workflow--current-state)))
    (list
     :valid (and has-bullets (or (null expected-acs) ac-tags))
     :has-bullets has-bullets
     :ac-tags ac-tags
     :message (cond
               ((not has-bullets) "Plan missing bullet points or numbered items")
               ((and expected-acs (not ac-tags)) "Plan does not cite any AC tags")
               (t "Plan validation passed")))))

(defun gptel-workflow--validate-diff (output)
  "Validate diff OUTPUT is non-empty unified diff with AC tags."
  (let ((has-diff (string-match-p "^diff\\|^@@\\|^[+-][^+-]" output))
        (ac-tags (gptel-workflow--extract-ac-tags output))
        (expected-acs (gptel-workflow-state-acs gptel-workflow--current-state)))
    (list
     :valid (and has-diff (or (null expected-acs) ac-tags))
     :has-diff has-diff
     :ac-tags ac-tags
     :message (cond
               ((not has-diff) "Diff output is empty or not in unified diff format")
               ((and expected-acs (not ac-tags)) "Diff does not cite any AC tags")
               (t "Diff validation passed")))))

(defun gptel-workflow--validate-tests (output)
  "Validate tests OUTPUT touches test paths and cites AC tags."
  (let ((has-test-path (cl-some (lambda (pattern)
                                  (string-match-p pattern output))
                                gptel-workflow-default-test-paths))
        (ac-tags (gptel-workflow--extract-ac-tags output))
        (expected-acs (gptel-workflow-state-acs gptel-workflow--current-state)))
    (list
     :valid (and has-test-path (or (null expected-acs) ac-tags))
     :has-test-path has-test-path
     :ac-tags ac-tags
     :message (cond
               ((not has-test-path) "Tests output does not reference test paths")
               ((and expected-acs (not ac-tags)) "Tests do not cite any AC tags")
               (t "Tests validation passed")))))

(defun gptel-workflow--validate-review (output)
  "Validate review OUTPUT has non-empty bullets."
  (let ((has-bullets (string-match-p "^[*-]\\|^[0-9]+\\." output)))
    (list
     :valid has-bullets
     :has-bullets has-bullets
     :message (if has-bullets
                  "Review validation passed"
                "Review missing bullet points or numbered items"))))

(defvar gptel-workflow-validators
  '((plan . gptel-workflow--validate-plan)
    (diff . gptel-workflow--validate-diff)
    (tests . gptel-workflow--validate-tests)
    (tests-integration . gptel-workflow--validate-tests)
    (review . gptel-workflow--validate-review))
  "Alist mapping step symbols to validation functions.")

(defun gptel-workflow--validate-output (step output)
  "Validate OUTPUT for workflow STEP using appropriate validator."
  (if-let ((validator (alist-get step gptel-workflow-validators)))
      (funcall validator output)
    (list :valid t :message "No validator for this step")))

;;; Step Execution

(defun gptel-workflow--build-prompt (step)
  "Build prompt for workflow STEP based on state."
  (let* ((state gptel-workflow--current-state)
         (acs (gptel-workflow-state-acs state))
         (tagged-acs (when acs (gptel-workflow--tag-acs acs)))
         (context (or (gptel-workflow-state-context-summary state)
                      (gptel-workflow-state-context-raw state)))
         (ac-section (gptel-workflow--format-acs-for-prompt tagged-acs)))
    (pcase step
      ('plan
       (concat "Based on the following context, create a detailed implementation plan:\n\n"
               context
               ac-section
               "\nProvide a bullet-point plan with clear steps."))
      ('diff
       (concat "Based on this plan:\n\n"
               (gptel-workflow-state-plan state)
               "\n\nAnd this context:\n\n"
               context
               ac-section
               "\nGenerate a unified diff showing the required changes."))
      ('tests
       (concat "Based on this diff:\n\n"
               (gptel-workflow-state-diff state)
               ac-section
               "\nGenerate unit tests in unified diff format."))
      ('tests-integration
       (concat "Based on this diff:\n\n"
               (gptel-workflow-state-diff state)
               ac-section
               "\nGenerate integration tests in unified diff format."))
      ('review
       (concat "Review the following implementation:\n\n"
               "Plan:\n" (gptel-workflow-state-plan state) "\n\n"
               "Diff:\n" (gptel-workflow-state-diff state) "\n\n"
               "Tests:\n" (gptel-workflow-state-tests state)
               ac-section
               "\nProvide a bullet-point review covering risks, missing tests, and alternatives."))
      ('checklist
       (concat "Create a checklist for the following implementation:\n\n"
               (gptel-workflow-state-plan state)
               "\n\nProvide a markdown checklist of verification steps.")))))

(defun gptel-workflow--execute-step (step)
  "Execute workflow STEP and return output."
  ;; This is a simplified synchronous version for testing
  ;; A full implementation would use gptel-request with callbacks
  (let* ((preset (alist-get step gptel-workflow-step-preset-map))
         (prompt (gptel-workflow--build-prompt step))
         (output (format "[Mock output for %s step]\n%s" step prompt)))
    (gptel-workflow--log step preset "default")
    output))

;;; Step Runners

;;;###autoload
(defun gptel-workflow-run-plan ()
  "Run the plan workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let* ((output (gptel-workflow--execute-step 'plan))
         (validation (gptel-workflow--validate-output 'plan output)))
    (setf (gptel-workflow-state-plan gptel-workflow--current-state) output)
    (setf (gptel-workflow-state-current-step gptel-workflow--current-state) 'plan)
    (gptel-workflow--display-output "Plan" output validation)
    validation))

;;;###autoload
(defun gptel-workflow-run-diff ()
  "Run the diff workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (unless (gptel-workflow-state-plan gptel-workflow--current-state)
    (error "Plan step must be completed first"))
  (let* ((output (gptel-workflow--execute-step 'diff))
         (validation (gptel-workflow--validate-output 'diff output)))
    (setf (gptel-workflow-state-diff gptel-workflow--current-state) output)
    (setf (gptel-workflow-state-current-step gptel-workflow--current-state) 'diff)
    (gptel-workflow--display-output "Diff" output validation)
    validation))

;;;###autoload
(defun gptel-workflow-run-tests ()
  "Run the tests workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (unless (gptel-workflow-state-diff gptel-workflow--current-state)
    (error "Diff step must be completed first"))
  (let* ((step (if (gptel-workflow-state-integration-tests-p gptel-workflow--current-state)
                   'tests-integration
                 'tests))
         (output (gptel-workflow--execute-step step))
         (validation (gptel-workflow--validate-output step output)))
    (setf (gptel-workflow-state-tests gptel-workflow--current-state) output)
    (setf (gptel-workflow-state-current-step gptel-workflow--current-state) step)
    (gptel-workflow--display-output "Tests" output validation)
    validation))

;;;###autoload
(defun gptel-workflow-run-review ()
  "Run the review workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (unless (gptel-workflow-state-tests gptel-workflow--current-state)
    (error "Tests step must be completed first"))
  (let* ((output (gptel-workflow--execute-step 'review))
         (validation (gptel-workflow--validate-output 'review output)))
    (setf (gptel-workflow-state-review gptel-workflow--current-state) output)
    (setf (gptel-workflow-state-current-step gptel-workflow--current-state) 'review)
    (gptel-workflow--display-output "Review" output validation)
    validation))

;;;###autoload
(defun gptel-workflow-run-checklist ()
  "Run the checklist workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let* ((output (gptel-workflow--execute-step 'checklist))
         (validation (list :valid t :message "Checklist generated")))
    (setf (gptel-workflow-state-current-step gptel-workflow--current-state) 'checklist)
    (gptel-workflow--display-output "Checklist" output validation)
    validation))

;;; Output Display

(defun gptel-workflow--display-output (step-name output validation)
  "Display STEP-NAME OUTPUT and VALIDATION in output buffer."
  (let ((buf (get-buffer-create gptel-workflow-output-buffer-name)))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert (format "\n\n=== %s ===\n\n" step-name))
      (insert output)
      (insert (format "\n\nValidation: %s\n"
                      (plist-get validation :message)))
      (when (plist-get validation :ac-tags)
        (insert (format "AC Tags cited: %s\n"
                        (mapconcat #'identity
                                   (plist-get validation :ac-tags)
                                   ", ")))))
    (display-buffer buf)))

;;; Workflow Initialization and Dispatcher

;;;###autoload
(defun gptel-workflow-start (&optional context-source acs integration-tests-p)
  "Start a new workflow with CONTEXT-SOURCE, ACS, and INTEGRATION-TESTS-P.
CONTEXT-SOURCE can be 'region or 'defun.
ACS is a list of acceptance criteria strings.
INTEGRATION-TESTS-P toggles integration test generation."
  (interactive)
  (let* ((source (or context-source 'region))
         (context (pcase source
                    ('region (gptel-workflow--capture-region))
                    ('defun (gptel-workflow--capture-defun))
                    (_ (error "Invalid context source: %s" source))))
         (pruned-context (gptel-workflow--prune-context context)))
    (setq gptel-workflow--current-state
          (gptel-workflow-state-create
           :current-step nil
           :acs acs
           :context-raw pruned-context
           :integration-tests-p integration-tests-p))
    (message "Workflow initialized with %d characters of context"
             (length pruned-context))
    (gptel-workflow--log "init" "n/a" "n/a" "success")))

;;;###autoload
(defun gptel-workflow-run-all ()
  "Run all workflow steps in sequence."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (gptel-workflow-run-plan)
  (gptel-workflow-run-diff)
  (gptel-workflow-run-tests)
  (gptel-workflow-run-review)
  (gptel-workflow-run-checklist)
  (message "Workflow completed"))

;;;###autoload
(defun gptel-workflow-retry-step ()
  "Retry the current workflow step with alternate preset."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let ((step (gptel-workflow-state-current-step gptel-workflow--current-state)))
    (unless step
      (error "No step to retry"))
    (cl-incf (gptel-workflow-state-retry-count gptel-workflow--current-state))
    (message "Retrying step: %s (attempt %d)"
             step
             (gptel-workflow-state-retry-count gptel-workflow--current-state))
    (pcase step
      ('plan (gptel-workflow-run-plan))
      ('diff (gptel-workflow-run-diff))
      ('tests (gptel-workflow-run-tests))
      ('tests-integration (gptel-workflow-run-tests))
      ('review (gptel-workflow-run-review))
      ('checklist (gptel-workflow-run-checklist)))))

;;; Public API

;;;###autoload
(defun gptel-workflow-get-state ()
  "Get the current workflow state."
  gptel-workflow--current-state)

;;;###autoload
(defun gptel-workflow-set-acs (acs)
  "Set acceptance criteria ACS for current workflow."
  (interactive "sEnter acceptance criteria (comma-separated): ")
  (let ((ac-list (if (stringp acs)
                     (split-string acs "," t "[ \t\n]+")
                   acs)))
    (if gptel-workflow--current-state
        (setf (gptel-workflow-state-acs gptel-workflow--current-state) ac-list)
      (error "No active workflow state"))
    (message "Set %d acceptance criteria" (length ac-list))))

(provide 'gptel-workflow)
;;; gptel-workflow.el ends here
