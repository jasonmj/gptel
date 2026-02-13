;;; gptel-workflow-example.el --- Example usage of gptel-workflow  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file demonstrates various usage patterns for gptel-workflow.

;;; Code:

(require 'gptel-workflow)
(require 'gptel-workflow-transient)

;;; Example 1: Basic workflow with mock backend

(defun gptel-workflow-example-basic ()
  "Demonstrate basic workflow usage with mock backend."
  (interactive)
  ;; Create sample code context
  (let* ((context "(defun add (x y)
  \"Add two numbers.\"
  (+ x y))")
         (acs '("Function should handle negative numbers"
                "Function should validate numeric inputs"
                "Function should have comprehensive tests"))
         (state (gptel-workflow-state-create
                 :context context
                 :acs acs)))
    
    ;; Run workflow steps
    (message "Running plan step...")
    (gptel-workflow-plan state)
    
    ;; In a real scenario, you'd wait for async completion
    ;; and then run subsequent steps
    state))

;;; Example 2: Workflow with preset override

(defun gptel-workflow-example-preset-override ()
  "Demonstrate workflow with preset override."
  (interactive)
  (let ((state (gptel-workflow-state-create
                :context "(defun complex-function () ...)"
                :acs '("AC1: Performance optimization"))))
    
    ;; Override to use strong-medium for this diff
    (setf (gptel-workflow-state-preset-override state) 'strong-medium)
    
    (gptel-workflow-plan state)
    state))

;;; Example 3: Integration test workflow

(defun gptel-workflow-example-integration-tests ()
  "Demonstrate workflow with integration tests."
  (interactive)
  (let ((state (gptel-workflow-state-create
                :context "(defun api-handler () ...)"
                :acs '("AC1: API endpoint validation")
                :integration-test-flag t)))
    
    (gptel-workflow-plan state)
    state))

;;; Example 4: Custom backend

(defun gptel-workflow-example-custom-backend ()
  "Demonstrate workflow with custom backend."
  (interactive)
  ;; Set a custom backend function
  (setq gptel-workflow-backend-function
        (lambda (request-plist)
          (let ((prompt (plist-get request-plist :prompt))
                (callback (plist-get request-plist :callback)))
            ;; Simulate async response
            (run-at-time
             0.5 nil
             (lambda ()
               (funcall callback
                        (format "Custom backend response for: %s"
                                (substring prompt 0 (min 30 (length prompt))))
                        '(:status "Custom OK")))))))
  
  (let ((state (gptel-workflow-state-create
                :context "sample context"
                :acs '("AC1: test"))))
    (gptel-workflow-plan state)
    state))

;;; Example 5: Complete workflow with all steps

(defun gptel-workflow-example-complete ()
  "Demonstrate complete workflow with all steps.
Note: This is a simplified example. In practice, you'd need to
handle async callbacks properly between steps."
  (interactive)
  (let ((state (gptel-workflow-state-create
                :context "(defun example (x) (+ x 1))"
                :acs '("AC1: Handle edge cases"
                       "AC2: Add input validation"))))
    
    ;; Manually set outputs for demonstration
    ;; (In real use, these would come from LLM responses)
    (setf (gptel-workflow-state-plan state)
          "Plan:
- AC1: Add checks for nil and negative values
- AC2: Add type checking for numeric inputs
- Add comprehensive tests")
    
    (setf (gptel-workflow-state-diff state)
          "--- a/example.el
+++ b/example.el
@@ -1,2 +1,5 @@
 (defun example (x)
+  ;; AC1: Handle edge cases
+  (unless (numberp x)
+    (error \"Input must be a number\"))
   (+ x 1))")
    
    (setf (gptel-workflow-state-tests state)
          "--- a/test-example.el
+++ b/test-example.el
@@ -0,0 +1,5 @@
+(ert-deftest test-example ()
+  (should (= 2 (example 1)))
+  (should-error (example \"not-a-number\")))")
    
    (setf (gptel-workflow-state-review state)
          "Review:
- Risk: Error message could be more descriptive
- Missing test: No test for negative numbers
- Alternative: Consider using cl-check-type")
    
    (setf (gptel-workflow-state-checklist state)
          "Checklist:
- [ ] Verify type checking works
- [ ] Test with edge cases
- [ ] Update documentation
- [ ] Run full test suite")
    
    ;; Show results
    (gptel-workflow-show-output)
    state))

;;; Example 6: Interactive workflow with transient

(defun gptel-workflow-example-interactive ()
  "Launch interactive workflow with transient menu."
  (interactive)
  ;; Set up some context in a buffer
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun sample-function (x y)
  \"Sample function for demonstration.\"
  (+ x y))")
    (mark-whole-buffer)
    ;; Launch transient menu
    (call-interactively #'gptel-workflow-menu)))

;;; Example 7: Programmatic state inspection

(defun gptel-workflow-example-inspect-state ()
  "Demonstrate state inspection and manipulation."
  (interactive)
  (let ((state (gptel-workflow-state-create
                :context "context"
                :acs '("AC1" "AC2"))))
    
    ;; Set current state
    (gptel-workflow-set-state state)
    
    ;; Run a step
    (gptel-workflow-plan state)
    
    ;; Inspect state
    (message "Current step: %s" (gptel-workflow-state-step state))
    (message "ACs: %s" (gptel-workflow-state-acs state))
    (message "Has plan: %s" (if (gptel-workflow-state-plan state) "yes" "no"))
    
    ;; Get state back
    (let ((current (gptel-workflow-get-state)))
      (message "Retrieved state step: %s"
               (gptel-workflow-state-step current)))
    
    state))

;;; Example 8: Validation testing

(defun gptel-workflow-example-validation ()
  "Demonstrate validation functionality."
  (interactive)
  ;; Test plan validation
  (let* ((acs '("First requirement" "Second requirement"))
         (tagged-acs (gptel-workflow--tag-acs acs))
         
         ;; Valid plan
         (valid-plan "- AC1: Address first requirement
- AC2: Address second requirement")
         
         ;; Invalid plan (missing AC2)
         (invalid-plan "- AC1: Address first requirement
- Some other item"))
    
    ;; Validate valid plan
    (let ((result (gptel-workflow--validate-plan valid-plan tagged-acs)))
      (message "Valid plan validation: %s" (if (car result) "PASS" "FAIL")))
    
    ;; Validate invalid plan
    (let ((result (gptel-workflow--validate-plan invalid-plan tagged-acs)))
      (message "Invalid plan validation: %s (expected FAIL)"
               (if (car result) "PASS" "FAIL"))
      (message "Issues: %s" (cdr result))))
  
  ;; Test diff validation
  (let ((valid-diff "--- a/file.el
+++ b/file.el
@@ -1,1 +1,2 @@
 (defun test ()
+  ;; AC1: requirement
   (+ 1 1))")
        (invalid-diff "Not a unified diff"))
    
    (let ((result (gptel-workflow--validate-diff valid-diff nil)))
      (message "Valid diff validation: %s" (if (car result) "PASS" "FAIL")))
    
    (let ((result (gptel-workflow--validate-diff invalid-diff nil)))
      (message "Invalid diff validation: %s (expected FAIL)"
               (if (car result) "PASS" "FAIL"))
      (message "Issues: %s" (cdr result)))))

;;; Example 9: Context capture modes

(defun gptel-workflow-example-context-modes ()
  "Demonstrate different context capture modes."
  (interactive)
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun func1 () 1)
(defun func2 () 2)
(defun func3 () 3)")
    
    ;; Capture entire buffer
    (let ((buffer-context (gptel-workflow--capture-context 'buffer)))
      (message "Buffer context length: %d" (length buffer-context)))
    
    ;; Capture region
    (goto-char (point-min))
    (set-mark (point))
    (forward-line 1)
    (let ((region-context (gptel-workflow--capture-context 'region)))
      (message "Region context: %s" region-context))
    (deactivate-mark)
    
    ;; Capture defun
    (goto-char (point-min))
    (let ((defun-context (gptel-workflow--capture-context 'defun)))
      (message "Defun context: %s" defun-context))))

;;; Example 10: Logging and observability

(defun gptel-workflow-example-logging ()
  "Demonstrate logging and observability features."
  (interactive)
  (let ((state (gptel-workflow-state-create :step 'test)))
    
    ;; Add log entries
    (gptel-workflow--log state "Starting workflow")
    (gptel-workflow--log state "Processing step: %s" 'plan)
    (gptel-workflow--log state "Validation result: %s" "passed")
    
    ;; View logs
    (gptel-workflow-show-log)
    
    ;; Inspect log entries in state
    (message "Log entry count: %d"
             (length (gptel-workflow-state-log-entries state)))
    
    state))

(provide 'gptel-workflow-example)
;;; gptel-workflow-example.el ends here
