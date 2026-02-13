;;; gptel-workflow.el --- Workflow dispatcher for gptel  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; Author: Karthik Chikmagalur
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

;; This module provides a workflow dispatcher for gptel that orchestrates
;; a chained LLM workflow: plan → diff → tests → review → checklist.
;;
;; Features:
;; - Model presets and step-to-preset routing
;; - Context capture, pruning, and summarization
;; - Acceptance criteria (AC) handling with auto-tagging
;; - Validation gates with human confirmation
;; - Transient/minibuffer UX
;; - Comprehensive logging and observability
;;
;; Usage:
;;   M-x gptel-workflow-start
;;   M-x gptel-workflow-run-plan
;;   M-x gptel-workflow-run-diff
;;   M-x gptel-workflow-run-tests
;;   M-x gptel-workflow-run-review
;;   M-x gptel-workflow-run-checklist

;;; Code:

(require 'cl-lib)
(require 'gptel-request)
(require 'transient)

;;; Customization

(defgroup gptel-workflow nil
  "Workflow dispatcher for gptel."
  :group 'gptel)

(defcustom gptel-workflow-default-model "gpt-4"
  "Default model to use for workflow steps."
  :type 'string
  :group 'gptel-workflow)

(defcustom gptel-workflow-test-path-globs '("**/test/**" "**/tests/**" "**/*_test.*" "**/*-test.*")
  "List of glob patterns for test file paths."
  :type '(repeat string)
  :group 'gptel-workflow)

(defcustom gptel-workflow-integration-test-paths '("**/integration/**" "**/e2e/**")
  "List of glob patterns for integration test paths."
  :type '(repeat string)
  :group 'gptel-workflow)

(defcustom gptel-workflow-output-buffer-name "*gptel-workflow*"
  "Name of the buffer for workflow output."
  :type 'string
  :group 'gptel-workflow)

(defcustom gptel-workflow-log-buffer-name "*gptel-workflow-log*"
  "Name of the buffer for workflow logs."
  :type 'string
  :group 'gptel-workflow)

;;; Model Presets

(defconst gptel-workflow-presets
  '((fast-low
     :description "Fast model with low temperature"
     :model "gpt-3.5-turbo"
     :temperature 0.3
     :max-tokens 2000)
    (strong-medium
     :description "Strong model with medium temperature"
     :model "gpt-4"
     :temperature 0.7
     :max-tokens 4000)
    (strong-low
     :description "Strong model with low temperature"
     :model "gpt-4"
     :temperature 0.3
     :max-tokens 4000))
  "Model presets for workflow steps.")

(defconst gptel-workflow-step-preset-mapping
  '((plan . strong-medium)
    (diff . strong-low)
    (tests . strong-low)
    (tests-integration . strong-low)
    (review . strong-low)
    (checklist . strong-low)
    (summary . fast-low))
  "Default mapping of workflow steps to presets.")

;;; Workflow State

(cl-defstruct (gptel-workflow-state
               (:constructor gptel-workflow-state-create)
               (:copier nil))
  "Workflow state structure."
  (current-step nil :documentation "Current workflow step.")
  (acs nil :documentation "List of acceptance criteria strings.")
  (acs-tagged nil :documentation "List of tagged ACs (AC1: ..., AC2: ..., etc.).")
  (context nil :documentation "Raw context string.")
  (context-summary nil :documentation "Optional summarized context.")
  (plan nil :documentation "Generated plan output.")
  (diff nil :documentation "Generated diff output.")
  (tests nil :documentation "Generated tests output.")
  (tests-integration nil :documentation "Generated integration tests output.")
  (review nil :documentation "Generated review output.")
  (checklist nil :documentation "Generated checklist output.")
  (continue t :documentation "Flag to continue to next step.")
  (integration-tests-flag nil :documentation "Flag to run integration tests.")
  (preset-overrides nil :documentation "Alist of step -> preset overrides.")
  (context-source 'region :documentation "Source of context: region, defun, or buffer.")
  (retry-count 0 :documentation "Number of retries for current step.")
  (validation-results nil :documentation "Alist of step -> validation result."))

(defvar gptel-workflow--current-state nil
  "Current workflow state.")

;;; Utility Functions

(defun gptel-workflow--get-preset (preset-name)
  "Get preset configuration by PRESET-NAME."
  (cdr (assq preset-name gptel-workflow-presets)))

(defun gptel-workflow--get-step-preset (step &optional state)
  "Get preset for STEP from STATE or default mapping."
  (let* ((state (or state gptel-workflow--current-state))
         (override (and state (alist-get step (gptel-workflow-state-preset-overrides state)))))
    (or override
        (cdr (assq step gptel-workflow-step-preset-mapping))
        'strong-medium)))

(defun gptel-workflow--tag-acs (acs)
  "Tag acceptance criteria ACS with AC1, AC2, etc."
  (cl-loop for ac in acs
           for i from 1
           collect (format "AC%d: %s" i ac)))

(defun gptel-workflow--format-acs (tagged-acs)
  "Format TAGGED-ACS as a string for prompts."
  (if tagged-acs
      (concat "\n\nAcceptance Criteria:\n"
              (mapconcat #'identity tagged-acs "\n"))
    ""))

(defun gptel-workflow--log (format-string &rest args)
  "Log message to workflow log buffer."
  (with-current-buffer (get-buffer-create gptel-workflow-log-buffer-name)
    (goto-char (point-max))
    (insert (format "[%s] " (format-time-string "%Y-%m-%d %H:%M:%S"))
            (apply #'format format-string args)
            "\n")))

(defun gptel-workflow--output (format-string &rest args)
  "Write message to workflow output buffer."
  (with-current-buffer (get-buffer-create gptel-workflow-output-buffer-name)
    (goto-char (point-max))
    (insert (apply #'format format-string args) "\n")))

;;; Context Management

(defun gptel-workflow--capture-context (source)
  "Capture context from SOURCE (region, defun, or buffer)."
  (pcase source
    ('region
     (if (use-region-p)
         (buffer-substring-no-properties (region-beginning) (region-end))
       (error "No active region")))
    ('defun
     (save-excursion
       (beginning-of-defun)
       (let ((start (point)))
         (end-of-defun)
         (buffer-substring-no-properties start (point)))))
    ('buffer
     (buffer-substring-no-properties (point-min) (point-max)))
    (_ (error "Unknown context source: %s" source))))

(defun gptel-workflow--prune-context (context)
  "Prune noisy/large sections from CONTEXT.
This is a simple implementation that removes excessive whitespace
and limits the size."
  (let* ((pruned (replace-regexp-in-string "[ \t]+" " " context))
         (pruned (replace-regexp-in-string "\n\n\n+" "\n\n" pruned))
         (max-size 10000))
    (if (> (length pruned) max-size)
        (substring pruned 0 max-size)
      pruned)))

(defun gptel-workflow--summarize-context (context callback)
  "Summarize CONTEXT using fast-low preset and call CALLBACK with result.
Note: The preset model/temperature/max-tokens are extracted but not
passed to gptel-request as it uses the current gptel-backend settings.
To use specific models, set gptel-backend and gptel-model before calling."
  (let* ((preset-name 'fast-low)
         (preset (gptel-workflow--get-preset preset-name))
         (model (plist-get preset :model))
         (temp (plist-get preset :temperature))
         (max-tokens (plist-get preset :max-tokens))
         (prompt (format "Summarize the following code/text concisely (max 500 words):\n\n%s"
                        context)))
    (gptel-workflow--log "Summarizing context with preset %s (model: %s, temp: %s, max-tokens: %s)"
                        preset-name model temp max-tokens)
    (gptel-request
     prompt
     :callback
     (lambda (response info)
       (if response
           (progn
             (gptel-workflow--log "Context summarization completed")
             (funcall callback response))
         (gptel-workflow--log "Context summarization failed: %s" info)
         (funcall callback nil))))))

;;; Validation Gates

(defconst gptel-workflow--bullet-pattern "^[-*•]\\|^[0-9]+\\."
  "Regex pattern for bullet points in workflow output.")

(defun gptel-workflow--validate-plan (plan acs-tagged)
  "Validate PLAN output against ACS-TAGGED.
Returns (valid-p . message)."
  (let* ((has-bullets (string-match-p gptel-workflow--bullet-pattern plan))
         (ac-count (length acs-tagged))
         (cited-acs (cl-loop for i from 1 to (length acs-tagged)
                            when (string-match-p (format "AC%d" i) plan)
                            collect i)))
    (cond
     ((not has-bullets)
      (cons nil "Plan does not contain bullet points"))
     ((< (length cited-acs) ac-count)
      (cons nil (format "Plan does not cite all ACs (cited %d of %d)"
                       (length cited-acs) ac-count)))
     (t (cons t "Plan validation passed")))))

(defun gptel-workflow--validate-diff (diff acs-tagged)
  "Validate DIFF output against ACS-TAGGED.
Returns (valid-p . message)."
  (let* ((is-unified-diff (string-match-p "^\\(---\\|\\+\\+\\+\\|@@\\)" diff))
         (is-empty (string-match-p "^[[:space:]]*$" diff))
         (ac-count (length acs-tagged))
         (cited-acs (cl-loop for i from 1 to (length acs-tagged)
                            when (string-match-p (format "AC%d" i) diff)
                            collect i)))
    (cond
     (is-empty
      (cons nil "Diff is empty"))
     ((not is-unified-diff)
      (cons nil "Diff is not in unified diff format"))
     ((< (length cited-acs) ac-count)
      (cons nil (format "Diff does not cite all ACs (cited %d of %d)"
                       (length cited-acs) ac-count)))
     (t (cons t "Diff validation passed")))))

(defun gptel-workflow--validate-tests (tests diff)
  "Validate TESTS output against DIFF.
Returns (valid-p . message)."
  (let* ((is-diff (and diff (not (string-match-p "^[[:space:]]*$" diff))))
         (has-test-paths (and tests
                             (cl-some (lambda (glob)
                                       ;; Extract pattern from glob (handle different formats)
                                       (let ((pattern (cond
                                                      ((string-prefix-p "**/" glob)
                                                       (substring glob 3))
                                                      (t glob))))
                                         (string-match-p (regexp-quote pattern) tests)))
                                     gptel-workflow-test-path-globs)))
         (is-empty (or (not tests) (string-match-p "^[[:space:]]*$" tests))))
    (cond
     (is-empty
      (cons nil "Tests output is empty"))
     ((and is-diff (not has-test-paths))
      (cons nil "Tests do not touch expected test paths when behavior changes"))
     (t (cons t "Tests validation passed")))))

(defun gptel-workflow--validate-review (review)
  "Validate REVIEW output.
Returns (valid-p . message)."
  (let ((has-bullets (string-match-p gptel-workflow--bullet-pattern review))
        (is-empty (string-match-p "^[[:space:]]*$" review)))
    (cond
     (is-empty
      (cons nil "Review is empty"))
     ((not has-bullets)
      (cons nil "Review does not contain bullet points"))
     (t (cons t "Review validation passed")))))

(defun gptel-workflow--confirm-validation (validation-result step)
  "Ask user to confirm VALIDATION-RESULT for STEP.
Returns t if user confirms to proceed, nil otherwise."
  (let ((valid-p (car validation-result))
        (message (cdr validation-result)))
    (if valid-p
        (prog1 t
          (gptel-workflow--log "Validation passed for %s: %s" step message))
      (gptel-workflow--log "Validation failed for %s: %s" step message)
      (yes-or-no-p (format "Validation failed for %s: %s\nProceed anyway? " step message)))))

;;; Step Runners

(defun gptel-workflow--build-prompt (step state)
  "Build prompt for STEP using STATE."
  (let* ((acs-formatted (gptel-workflow--format-acs
                        (gptel-workflow-state-acs-tagged state)))
         (context (or (gptel-workflow-state-context-summary state)
                     (gptel-workflow-state-context state)))
         (plan (gptel-workflow-state-plan state))
         (diff (gptel-workflow-state-diff state))
         (tests (gptel-workflow-state-tests state))
         (review (gptel-workflow-state-review state)))
    (pcase step
      ('plan
       (concat "Create a detailed implementation plan for the following requirements."
               acs-formatted
               (when context (format "\n\nContext:\n%s" context))
               "\n\nProvide a bulleted plan. Cite AC IDs in your plan."))
      ('diff
       (concat "Generate a unified diff implementing the following plan."
               acs-formatted
               (when plan (format "\n\nPlan:\n%s" plan))
               (when context (format "\n\nContext:\n%s" context))
               "\n\nProvide output in unified diff format. Cite AC IDs in comments."))
      ('tests
       (concat "Generate unit tests for the following changes."
               acs-formatted
               (when diff (format "\n\nDiff:\n%s" diff))
               (when context (format "\n\nContext:\n%s" context))
               "\n\nProvide tests as unified diffs touching test paths."))
      ('tests-integration
       (concat "Generate integration tests for the following changes."
               acs-formatted
               (when diff (format "\n\nDiff:\n%s" diff))
               (when context (format "\n\nContext:\n%s" context))
               "\n\nProvide integration tests as unified diffs."))
      ('review
       (concat "Review the following implementation."
               acs-formatted
               (when diff (format "\n\nDiff:\n%s" diff))
               (when tests (format "\n\nTests:\n%s" tests))
               "\n\nProvide a bulleted review covering: risks, missing tests, alternatives."))
      ('checklist
       (concat "Generate a completion checklist for the following implementation."
               acs-formatted
               (when plan (format "\n\nPlan:\n%s" plan))
               (when review (format "\n\nReview:\n%s" review))
               "\n\nProvide a markdown checklist of completion criteria."))
      (_ (error "Unknown step: %s" step)))))

(defun gptel-workflow--run-step (step &optional retry)
  "Run workflow STEP. If RETRY is non-nil, use alternate preset.
Note: The preset model/temperature/max-tokens are extracted but not
passed to gptel-request as it uses the current gptel-backend settings.
To use specific models, set gptel-backend and gptel-model before calling."
  (unless gptel-workflow--current-state
    (error "No active workflow state. Run gptel-workflow-start first"))
  (let* ((state gptel-workflow--current-state)
         (preset-name (if retry
                          (pcase (gptel-workflow--get-step-preset step state)
                            ('fast-low 'strong-low)
                            ('strong-medium 'strong-low)
                            ('strong-low 'strong-medium))
                        (gptel-workflow--get-step-preset step state)))
         (preset (gptel-workflow--get-preset preset-name))
         (model (plist-get preset :model))
         (temp (plist-get preset :temperature))
         (max-tokens (plist-get preset :max-tokens))
         (prompt (gptel-workflow--build-prompt step state)))
    (setf (gptel-workflow-state-current-step state) step)
    (when retry
      (cl-incf (gptel-workflow-state-retry-count state)))
    (gptel-workflow--log "Running step %s with preset %s (model: %s, temp: %s, max-tokens: %s, retry: %s)"
                        step preset-name model temp max-tokens retry)
    (gptel-workflow--output "\n=== Step: %s (preset: %s) ===\n" step preset-name)
    (gptel-request
     prompt
     :callback
     (lambda (response info)
       (if response
           (progn
             (gptel-workflow--log "Step %s completed successfully" step)
             (gptel-workflow--output "%s\n" response)
             (gptel-workflow--process-step-response step response))
         (gptel-workflow--log "Step %s failed: %s" step info)
         (message "Step %s failed: %s" step info))))))

(defun gptel-workflow--process-step-response (step response)
  "Process RESPONSE for STEP and update state."
  (let ((state gptel-workflow--current-state))
    (pcase step
      ('plan
       (setf (gptel-workflow-state-plan state) response)
       (let ((validation (gptel-workflow--validate-plan
                         response
                         (gptel-workflow-state-acs-tagged state))))
         (when (gptel-workflow--confirm-validation validation step)
           (message "Plan step completed. Run gptel-workflow-run-diff next."))))
      ('diff
       (setf (gptel-workflow-state-diff state) response)
       (let ((validation (gptel-workflow--validate-diff
                         response
                         (gptel-workflow-state-acs-tagged state))))
         (when (gptel-workflow--confirm-validation validation step)
           (message "Diff step completed. Run gptel-workflow-run-tests next."))))
      ('tests
       (setf (gptel-workflow-state-tests state) response)
       (let ((validation (gptel-workflow--validate-tests
                         response
                         (gptel-workflow-state-diff state))))
         (when (gptel-workflow--confirm-validation validation step)
           (message "Tests step completed. Run gptel-workflow-run-review next."))))
      ('tests-integration
       (setf (gptel-workflow-state-tests-integration state) response)
       (let ((validation (gptel-workflow--validate-tests
                         response
                         (gptel-workflow-state-diff state))))
         (when (gptel-workflow--confirm-validation validation step)
           (message "Integration tests step completed."))))
      ('review
       (setf (gptel-workflow-state-review state) response)
       (let ((validation (gptel-workflow--validate-review response)))
         (when (gptel-workflow--confirm-validation validation step)
           (message "Review step completed. Run gptel-workflow-run-checklist next."))))
      ('checklist
       (setf (gptel-workflow-state-checklist state) response)
       (message "Checklist step completed. Workflow finished."))
      (_ (error "Unknown step: %s" step)))))

;;; Public Commands

;;;###autoload
(defun gptel-workflow-start ()
  "Start a new workflow with context and acceptance criteria."
  (interactive)
  (let* ((context-source (intern (completing-read
                                 "Context source: "
                                 '("region" "defun" "buffer")
                                 nil t nil nil "region")))
         (context (gptel-workflow--capture-context context-source))
         (pruned-context (gptel-workflow--prune-context context))
         (acs-input (read-string "Acceptance criteria (separate with |): "))
         (acs (split-string acs-input "|" t "[ \t\n]+"))
         (acs-tagged (gptel-workflow--tag-acs acs))
         (integration-tests (y-or-n-p "Run integration tests? "))
         (summarize (y-or-n-p "Summarize context before planning? ")))
    (setq gptel-workflow--current-state
          (gptel-workflow-state-create
           :current-step nil
           :acs acs
           :acs-tagged acs-tagged
           :context pruned-context
           :context-summary nil
           :integration-tests-flag integration-tests
           :context-source context-source))
    (gptel-workflow--log "Started new workflow with %d ACs" (length acs))
    (gptel-workflow--output "=== Workflow Started ===\n")
    (gptel-workflow--output "Acceptance Criteria:\n%s\n"
                           (mapconcat #'identity acs-tagged "\n"))
    (if summarize
        (gptel-workflow--summarize-context
         pruned-context
         (lambda (summary)
           (when summary
             (setf (gptel-workflow-state-context-summary gptel-workflow--current-state)
                   summary)
             (gptel-workflow--log "Context summarized"))
           (message "Workflow initialized. Run gptel-workflow-run-plan to start.")))
      (message "Workflow initialized. Run gptel-workflow-run-plan to start."))))

;;;###autoload
(defun gptel-workflow-run-plan ()
  "Run the plan step of the workflow."
  (interactive)
  (gptel-workflow--run-step 'plan))

;;;###autoload
(defun gptel-workflow-run-diff ()
  "Run the diff step of the workflow."
  (interactive)
  (gptel-workflow--run-step 'diff))

;;;###autoload
(defun gptel-workflow-run-tests ()
  "Run the tests step of the workflow."
  (interactive)
  (gptel-workflow--run-step 'tests))

;;;###autoload
(defun gptel-workflow-run-tests-integration ()
  "Run the integration tests step of the workflow."
  (interactive)
  (gptel-workflow--run-step 'tests-integration))

;;;###autoload
(defun gptel-workflow-run-review ()
  "Run the review step of the workflow."
  (interactive)
  (gptel-workflow--run-step 'review))

;;;###autoload
(defun gptel-workflow-run-checklist ()
  "Run the checklist step of the workflow."
  (interactive)
  (gptel-workflow--run-step 'checklist))

;;;###autoload
(defun gptel-workflow-retry-step ()
  "Retry the current step with an alternate preset."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let ((step (gptel-workflow-state-current-step gptel-workflow--current-state)))
    (unless step
      (error "No current step to retry"))
    (gptel-workflow--run-step step t)))

;;;###autoload
(defun gptel-workflow-show-output ()
  "Show the workflow output buffer."
  (interactive)
  (display-buffer (get-buffer-create gptel-workflow-output-buffer-name)))

;;;###autoload
(defun gptel-workflow-show-log ()
  "Show the workflow log buffer."
  (interactive)
  (display-buffer (get-buffer-create gptel-workflow-log-buffer-name)))

;;;###autoload
(defun gptel-workflow-reset ()
  "Reset the workflow state."
  (interactive)
  (when (yes-or-no-p "Reset workflow state? ")
    (setq gptel-workflow--current-state nil)
    (with-current-buffer (get-buffer-create gptel-workflow-output-buffer-name)
      (erase-buffer))
    (gptel-workflow--log "Workflow reset")
    (message "Workflow state reset")))

(provide 'gptel-workflow)
;;; gptel-workflow.el ends here
