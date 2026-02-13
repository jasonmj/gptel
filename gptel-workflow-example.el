;;; gptel-workflow-example.el --- Usage examples for gptel-workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Jason M. Jensen

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; This file provides usage examples for gptel-workflow.
;; Load this file to see how to use the workflow system.

;;; Code:

(require 'gptel-workflow)
(require 'gptel-workflow-transient)

;;; Example 1: Interactive workflow with transient UI

;; 1. Select a region of code in your buffer
;; 2. Run: M-x gptel-workflow-menu
;; 3. Configure:
;;    - Context source: region (default)
;;    - ACs: "Feature works, Tests pass"
;;    - Integration tests: toggle if needed
;; 4. Press 'a' to run all steps

;;; Example 2: Programmatic workflow

(defun my-workflow-example ()
  "Example of programmatic workflow usage."
  (interactive)
  ;; Capture region
  (when (use-region-p)
    ;; Initialize workflow with context from region
    (gptel-workflow-start
     'region
     '("Maintain backward compatibility"
       "Add comprehensive tests"
       "Optimize performance")
     nil)  ; No integration tests
    
    ;; Run all steps
    (gptel-workflow-run-all)))

;;; Example 3: Step-by-step workflow with custom handling

(defun my-custom-workflow ()
  "Example with custom step handling."
  (interactive)
  (when (use-region-p)
    ;; Initialize
    (gptel-workflow-start 'region
                          '("Security checked" "Error handling complete")
                          nil)
    
    ;; Run plan
    (gptel-workflow-run-plan
     (lambda (validation)
       (if (plist-get validation :valid)
           (progn
             (message "Plan validated successfully")
             ;; Continue to diff
             (gptel-workflow-run-diff
              (lambda (validation)
                (if (plist-get validation :valid)
                    (message "Diff validated successfully")
                  (message "Diff validation failed, retrying...")
                  (gptel-workflow-retry-step)))))
         (message "Plan validation failed")
         (gptel-workflow-retry-step))))))

;;; Example 4: Review-only workflow

(defun my-review-workflow ()
  "Quick review workflow for existing code."
  (interactive)
  (when (use-region-p)
    (gptel-workflow-start 'defun
                          '("Code follows best practices"
                            "No security vulnerabilities")
                          nil)
    
    ;; Skip to review step (requires plan first)
    (gptel-workflow-run-plan
     (lambda (_validation)
       (gptel-workflow-run-review
        (lambda (validation)
          (message "Review: %s" (plist-get validation :message))))))))

;;; Example 5: Integration test workflow

(defun my-integration-test-workflow ()
  "Workflow focused on integration tests."
  (interactive)
  (when (use-region-p)
    (gptel-workflow-start 'region
                          '("All edge cases covered"
                            "Error paths tested")
                          t)  ; Enable integration tests
    
    (gptel-workflow-run-plan
     (lambda (_v)
       (gptel-workflow-run-diff
        (lambda (_v)
          (gptel-workflow-run-tests
           (lambda (validation)
             (let ((state (gptel-workflow-get-state)))
               (if (gptel-workflow-state-integration-tests-p state)
                   (message "Integration tests generated")
                 (message "Unit tests generated")))))))))))

;;; Example 6: Accessing workflow state

(defun my-state-inspector ()
  "Inspect current workflow state."
  (interactive)
  (let ((state (gptel-workflow-get-state)))
    (if state
        (progn
          (message "Current step: %s" (gptel-workflow-state-current-step state))
          (message "ACs: %s" (gptel-workflow-state-acs state))
          (message "Retry count: %d" (gptel-workflow-state-retry-count state))
          (when (gptel-workflow-state-plan state)
            (message "Plan available: %d chars"
                     (length (gptel-workflow-state-plan state)))))
      (message "No active workflow"))))

;;; Example 7: Modifying ACs during workflow

(defun my-dynamic-ac-workflow ()
  "Workflow with dynamic AC modification."
  (interactive)
  (when (use-region-p)
    (gptel-workflow-start 'region
                          '("Initial AC")
                          nil)
    
    (gptel-workflow-run-plan
     (lambda (validation)
       ;; Based on plan, add more specific ACs
       (gptel-workflow-set-acs
        '("Initial AC"
          "Specific requirement from plan"
          "Additional constraint"))
       
       ;; Continue with updated ACs
       (gptel-workflow-run-diff)))))

;;; Example 8: Custom validation handling

(defun my-strict-workflow ()
  "Workflow with strict validation."
  (interactive)
  (when (use-region-p)
    (gptel-workflow-start 'region
                          '("Must cite all ACs" "Must have examples")
                          nil)
    
    (gptel-workflow-run-plan
     (lambda (validation)
       (if (and (plist-get validation :valid)
                (>= (length (plist-get validation :ac-tags)) 2))
           (progn
             (message "Plan meets strict requirements")
             (gptel-workflow-run-diff))
         (message "Plan does not meet requirements, retrying")
         (gptel-workflow-retry-step))))))

;;; Example 9: Workflow with custom output handling

(defun my-output-saving-workflow ()
  "Workflow that saves outputs to files."
  (interactive)
  (when (use-region-p)
    (gptel-workflow-start 'region '("Feature complete") nil)
    
    (gptel-workflow-run-all)
    
    ;; After workflow completes (in real scenario, add to callback)
    (let ((state (gptel-workflow-get-state)))
      (when (gptel-workflow-state-plan state)
        (with-temp-file "/tmp/workflow-plan.txt"
          (insert (gptel-workflow-state-plan state))))
      (when (gptel-workflow-state-diff state)
        (with-temp-file "/tmp/workflow-diff.patch"
          (insert (gptel-workflow-state-diff state))))
      (message "Outputs saved to /tmp/"))))

;;; Example 10: Workflow with logging inspection

(defun my-workflow-with-logging ()
  "Workflow that inspects logs."
  (interactive)
  (when (use-region-p)
    (gptel-workflow-start 'region '("Well tested") nil)
    
    (gptel-workflow-run-plan
     (lambda (_v)
       (gptel-workflow-run-diff
        (lambda (_v)
          ;; Check log after diff
          (with-current-buffer (get-buffer gptel-workflow-log-buffer-name)
            (goto-char (point-min))
            (if (search-forward "success" nil t)
                (message "Workflow steps successful so far")
              (message "Check logs for issues")))
          (gptel-workflow-run-tests)))))))

(provide 'gptel-workflow-example)
;;; gptel-workflow-example.el ends here
