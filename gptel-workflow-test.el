;;; gptel-workflow-test.el --- Tests for gptel-workflow  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; Author: Karthik Chikmagalur <karthikchikmagalur@gmail.com>

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

;; Comprehensive ERT tests for gptel-workflow.

;;; Code:

(require 'ert)
(require 'gptel-workflow)

;;; Test fixtures

(defvar gptel-workflow-test--sample-context
  "(defun example-function (x y)
  \"Add two numbers.\"
  (+ x y))"
  "Sample context for testing.")

(defvar gptel-workflow-test--sample-acs
  '("Function should handle negative numbers"
    "Function should validate inputs"
    "Function should include comprehensive tests")
  "Sample acceptance criteria for testing.")

(defvar gptel-workflow-test--sample-plan
  "Implementation Plan:
- AC1: Add input validation for negative numbers
- AC2: Add type checking for inputs
- AC3: Create unit tests covering edge cases
- Update documentation"
  "Sample plan output.")

(defvar gptel-workflow-test--sample-diff
  "--- a/example.el
+++ b/example.el
@@ -1,4 +1,8 @@
 (defun example-function (x y)
-  \"Add two numbers.\"
+  \"Add two numbers with validation.
+AC1: Handles negative numbers
+AC2: Validates input types\"
+  (unless (and (numberp x) (numberp y))
+    (error \"Inputs must be numbers\"))
   (+ x y))"
  "Sample diff output.")

(defvar gptel-workflow-test--sample-tests
  "--- a/test-example.el
+++ b/test-example.el
@@ -0,0 +1,10 @@
+(ert-deftest test-example-function ()
+  \"Test example-function with various inputs.\"
+  (should (= 5 (example-function 2 3)))
+  (should (= -1 (example-function -3 2)))
+  (should-error (example-function \"a\" 2)))"
  "Sample tests output.")

(defvar gptel-workflow-test--sample-review
  "Code Review:
- Risk: Error handling may throw confusing messages
- Missing test: No test for both negative inputs
- Alternative: Consider using cl-check-type for validation"
  "Sample review output.")

;;; State structure tests

(ert-deftest gptel-workflow-test-state-creation ()
  "Test workflow state creation."
  (let ((state (gptel-workflow-state-create
                :context "test context"
                :acs '("AC1" "AC2"))))
    (should (gptel-workflow-state-p state))
    (should (equal "test context" (gptel-workflow-state-context state)))
    (should (equal '("AC1" "AC2") (gptel-workflow-state-acs state)))
    (should (null (gptel-workflow-state-plan state)))
    (should (eq t (gptel-workflow-state-continue-flag state)))))

(ert-deftest gptel-workflow-test-state-progression ()
  "Test state progression through steps."
  (let ((state (gptel-workflow-state-create)))
    ;; Initial state
    (should (null (gptel-workflow-state-step state)))
    
    ;; Set plan
    (setf (gptel-workflow-state-step state) 'plan)
    (setf (gptel-workflow-state-plan state) "Test plan")
    (should (eq 'plan (gptel-workflow-state-step state)))
    (should (equal "Test plan" (gptel-workflow-state-plan state)))
    
    ;; Set diff
    (setf (gptel-workflow-state-step state) 'diff)
    (setf (gptel-workflow-state-diff state) "Test diff")
    (should (eq 'diff (gptel-workflow-state-step state)))
    (should (equal "Test diff" (gptel-workflow-state-diff state)))
    
    ;; Ensure plan is still present
    (should (equal "Test plan" (gptel-workflow-state-plan state)))))

;;; Backend abstraction tests

(ert-deftest gptel-workflow-test-mock-backend ()
  "Test mock backend functionality."
  (let ((response-received nil)
        (response-text nil))
    (gptel-workflow--mock-backend
     `(:prompt "test prompt"
       :callback ,(lambda (resp info)
                    (setq response-received t
                          response-text resp))))
    ;; Wait for async callback
    (sleep-for 0.2)
    (should response-received)
    (should (stringp response-text))
    (should (string-match-p "Mock response" response-text))))

(ert-deftest gptel-workflow-test-backend-selection ()
  "Test backend selection logic."
  ;; Mock backend should be used when gptel not available
  (let ((gptel-workflow-backend-function nil)
        (response-received nil))
    (gptel-workflow--send-request
     "test" "system" 'fast-low
     (lambda (resp info)
       (setq response-received t)))
    (sleep-for 0.2)
    (should response-received)))

;;; Context capture and hygiene tests

(ert-deftest gptel-workflow-test-context-capture-buffer ()
  "Test capturing context from buffer."
  (with-temp-buffer
    (insert "Line 1\nLine 2\nLine 3")
    (let ((context (gptel-workflow--capture-context 'buffer)))
      (should (equal "Line 1\nLine 2\nLine 3" context)))))

(ert-deftest gptel-workflow-test-context-capture-region ()
  "Test capturing context from region."
  (with-temp-buffer
    (insert "Line 1\nLine 2\nLine 3")
    (goto-char (point-min))
    (set-mark (point))
    (forward-line 2)
    (activate-mark)
    (let ((context (gptel-workflow--capture-context 'region)))
      (should (equal "Line 1\nLine 2" context)))))

(ert-deftest gptel-workflow-test-context-pruning ()
  "Test context pruning for large content."
  (let* ((large-context (make-string 60000 ?x))
         (pruned (gptel-workflow--prune-context large-context)))
    (should (< (length pruned) (length large-context)))
    (should (string-match-p "context pruned" pruned))))

(ert-deftest gptel-workflow-test-context-no-pruning ()
  "Test context not pruned when under limit."
  (let* ((small-context "Small context")
         (result (gptel-workflow--prune-context small-context)))
    (should (equal small-context result))))

;;; Acceptance criteria tests

(ert-deftest gptel-workflow-test-ac-tagging ()
  "Test AC tagging functionality."
  (let ((acs '("First AC" "Second AC" "Third AC"))
        (tagged (gptel-workflow--tag-acs acs)))
    (should (equal 3 (length tagged)))
    (should (equal "AC1" (caar tagged)))
    (should (equal "First AC" (cdar tagged)))
    (should (equal "AC2" (car (nth 1 tagged))))
    (should (equal "Second AC" (cdr (nth 1 tagged))))))

(ert-deftest gptel-workflow-test-ac-formatting ()
  "Test AC formatting for prompts."
  (let* ((acs '("First" "Second"))
         (tagged (gptel-workflow--tag-acs acs))
         (formatted (gptel-workflow--format-acs-for-prompt tagged)))
    (should (string-match-p "Acceptance Criteria" formatted))
    (should (string-match-p "AC1.*First" formatted))
    (should (string-match-p "AC2.*Second" formatted))))

(ert-deftest gptel-workflow-test-ac-citation-validation-valid ()
  "Test AC citation validation with all citations present."
  (let* ((acs '("First" "Second"))
         (tagged (gptel-workflow--tag-acs acs))
         (text "This implementation addresses AC1 and AC2 requirements.")
         (result (gptel-workflow--validate-ac-citations text tagged)))
    (should (car result))
    (should (null (cdr result)))))

(ert-deftest gptel-workflow-test-ac-citation-validation-missing ()
  "Test AC citation validation with missing citations."
  (let* ((acs '("First" "Second" "Third"))
         (tagged (gptel-workflow--tag-acs acs))
         (text "This implementation addresses AC1 requirements.")
         (result (gptel-workflow--validate-ac-citations text tagged)))
    (should-not (car result))
    (should (member "AC2" (cdr result)))
    (should (member "AC3" (cdr result)))))

(ert-deftest gptel-workflow-test-ac-empty-list ()
  "Test AC handling with empty list."
  (let ((tagged (gptel-workflow--tag-acs nil))
        (formatted (gptel-workflow--format-acs-for-prompt nil)))
    (should (null tagged))
    (should (equal "" formatted))))

;;; Validation gates tests

(ert-deftest gptel-workflow-test-validate-plan-valid ()
  "Test plan validation with valid plan."
  (let* ((acs '("First" "Second"))
         (tagged (gptel-workflow--tag-acs acs))
         (plan gptel-workflow-test--sample-plan)
         (result (gptel-workflow--validate-plan plan tagged)))
    (should (car result))
    (should (null (cdr result)))))

(ert-deftest gptel-workflow-test-validate-plan-no-bullets ()
  "Test plan validation fails without bullets."
  (let ((plan "Just a plain text plan without bullets")
        (result (gptel-workflow--validate-plan plan nil)))
    (should-not (car result))
    (should (cl-some (lambda (issue)
                       (string-match-p "bullet" issue))
                     (cdr result)))))

(ert-deftest gptel-workflow-test-validate-plan-missing-acs ()
  "Test plan validation fails with missing AC citations."
  (let* ((acs '("First" "Second"))
         (tagged (gptel-workflow--tag-acs acs))
         (plan "- Item 1\n- Item 2")  ; No AC citations
         (result (gptel-workflow--validate-plan plan tagged)))
    (should-not (car result))
    (should (cl-some (lambda (issue)
                       (string-match-p "AC" issue))
                     (cdr result)))))

(ert-deftest gptel-workflow-test-validate-diff-valid ()
  "Test diff validation with valid diff."
  (let* ((acs '("First" "Second"))
         (tagged (gptel-workflow--tag-acs acs))
         (diff gptel-workflow-test--sample-diff)
         (result (gptel-workflow--validate-diff diff tagged)))
    (should (car result))))

(ert-deftest gptel-workflow-test-validate-diff-empty ()
  "Test diff validation fails with empty diff."
  (let ((result (gptel-workflow--validate-diff "" nil)))
    (should-not (car result))
    (should (cl-some (lambda (issue)
                       (string-match-p "empty" issue))
                     (cdr result)))))

(ert-deftest gptel-workflow-test-validate-diff-invalid-format ()
  "Test diff validation fails with invalid format."
  (let ((diff "Not a unified diff\nJust some text")
        (result (gptel-workflow--validate-diff diff nil)))
    (should-not (car result))
    (should (cl-some (lambda (issue)
                       (string-match-p "unified diff" issue))
                     (cdr result)))))

(ert-deftest gptel-workflow-test-validate-tests-valid ()
  "Test tests validation with valid tests."
  (let ((tests gptel-workflow-test--sample-tests)
        (result (gptel-workflow--validate-tests tests nil t)))
    (should (car result))))

(ert-deftest gptel-workflow-test-validate-review-valid ()
  "Test review validation with valid review."
  (let ((review gptel-workflow-test--sample-review)
        (result (gptel-workflow--validate-review review)))
    (should (car result))))

(ert-deftest gptel-workflow-test-validate-review-no-bullets ()
  "Test review validation fails without bullets."
  (let ((review "Plain text review without structure")
        (result (gptel-workflow--validate-review review)))
    (should-not (car result))))

;;; Prompt generation tests

(ert-deftest gptel-workflow-test-make-prompt-plan ()
  "Test plan prompt generation."
  (let* ((context "test context")
         (acs '("AC1" "AC2"))
         (tagged (gptel-workflow--tag-acs acs))
         (prompt (gptel-workflow--make-prompt-plan context tagged)))
    (should (stringp prompt))
    (should (string-match-p "test context" prompt))
    (should (string-match-p "AC1" prompt))
    (should (string-match-p "AC2" prompt))))

(ert-deftest gptel-workflow-test-make-prompt-diff ()
  "Test diff prompt generation."
  (let* ((plan "test plan")
         (context "test context")
         (tagged (gptel-workflow--tag-acs '("AC1")))
         (prompt (gptel-workflow--make-prompt-diff plan context tagged)))
    (should (stringp prompt))
    (should (string-match-p "test plan" prompt))
    (should (string-match-p "test context" prompt))
    (should (string-match-p "unified diff" prompt))))

(ert-deftest gptel-workflow-test-make-prompt-tests-unit ()
  "Test unit tests prompt generation."
  (let* ((plan "test plan")
         (diff "test diff")
         (context "test context")
         (tagged nil)
         (prompt (gptel-workflow--make-prompt-tests plan diff context tagged nil)))
    (should (stringp prompt))
    (should (string-match-p "unit" prompt))
    (should-not (string-match-p "integration" prompt))))

(ert-deftest gptel-workflow-test-make-prompt-tests-integration ()
  "Test integration tests prompt generation."
  (let* ((plan "test plan")
         (diff "test diff")
         (context "test context")
         (tagged nil)
         (prompt (gptel-workflow--make-prompt-tests plan diff context tagged t)))
    (should (stringp prompt))
    (should (string-match-p "integration" prompt))))

(ert-deftest gptel-workflow-test-make-prompt-review ()
  "Test review prompt generation."
  (let ((prompt (gptel-workflow--make-prompt-review "plan" "diff" "tests" "context")))
    (should (stringp prompt))
    (should (string-match-p "plan" prompt))
    (should (string-match-p "diff" prompt))
    (should (string-match-p "tests" prompt))
    (should (string-match-p "risk" prompt))))

(ert-deftest gptel-workflow-test-make-prompt-checklist ()
  "Test checklist prompt generation."
  (let ((prompt (gptel-workflow--make-prompt-checklist "plan" "diff" "tests" "review")))
    (should (stringp prompt))
    (should (string-match-p "plan" prompt))
    (should (string-match-p "checklist" prompt))))

;;; Logging tests

(ert-deftest gptel-workflow-test-logging ()
  "Test workflow logging functionality."
  (let ((state (gptel-workflow-state-create :step 'test)))
    (gptel-workflow--log state "Test message %s" "arg")
    (let ((entries (gptel-workflow-state-log-entries state)))
      (should (= 1 (length entries)))
      (should (string-match-p "Test message arg"
                              (plist-get (car entries) :message))))))

;;; Output buffer tests

(ert-deftest gptel-workflow-test-output-buffer ()
  "Test output buffer functionality."
  (gptel-workflow--append-output 'test "Test content")
  (with-current-buffer gptel-workflow--output-buffer
    (should (string-match-p "TEST" (buffer-string)))
    (should (string-match-p "Test content" (buffer-string)))))

;;; Integration tests

(ert-deftest gptel-workflow-test-full-workflow-state ()
  "Test complete workflow state progression."
  (let ((state (gptel-workflow-state-create
                :context gptel-workflow-test--sample-context
                :acs gptel-workflow-test--sample-acs)))
    
    ;; Set plan
    (setf (gptel-workflow-state-step state) 'plan)
    (setf (gptel-workflow-state-plan state) gptel-workflow-test--sample-plan)
    (should (gptel-workflow-state-plan state))
    
    ;; Set diff
    (setf (gptel-workflow-state-step state) 'diff)
    (setf (gptel-workflow-state-diff state) gptel-workflow-test--sample-diff)
    (should (gptel-workflow-state-diff state))
    
    ;; Set tests
    (setf (gptel-workflow-state-step state) 'tests)
    (setf (gptel-workflow-state-tests state) gptel-workflow-test--sample-tests)
    (should (gptel-workflow-state-tests state))
    
    ;; Set review
    (setf (gptel-workflow-state-step state) 'review)
    (setf (gptel-workflow-state-review state) gptel-workflow-test--sample-review)
    (should (gptel-workflow-state-review state))
    
    ;; Verify all steps are present
    (should (gptel-workflow-state-plan state))
    (should (gptel-workflow-state-diff state))
    (should (gptel-workflow-state-tests state))
    (should (gptel-workflow-state-review state))))

(ert-deftest gptel-workflow-test-preset-configuration ()
  "Test preset configuration."
  (should (assq 'fast-low gptel-workflow-presets))
  (should (assq 'strong-medium gptel-workflow-presets))
  (should (assq 'strong-low gptel-workflow-presets))
  
  (let ((fast-low (alist-get 'fast-low gptel-workflow-presets)))
    (should (plist-get fast-low :model))
    (should (plist-get fast-low :temperature))
    (should (plist-get fast-low :max-tokens))))

(ert-deftest gptel-workflow-test-step-preset-routing ()
  "Test default preset routing for steps."
  (should (eq 'strong-medium (alist-get 'plan gptel-workflow-step-presets)))
  (should (eq 'strong-low (alist-get 'diff gptel-workflow-step-presets)))
  (should (eq 'strong-low (alist-get 'tests gptel-workflow-step-presets)))
  (should (eq 'strong-low (alist-get 'review gptel-workflow-step-presets)))
  (should (eq 'fast-low (alist-get 'checklist gptel-workflow-step-presets))))

;;; Error handling tests

(ert-deftest gptel-workflow-test-context-capture-no-region ()
  "Test error when capturing region without active region."
  (with-temp-buffer
    (should-error (gptel-workflow--capture-context 'region))))

(ert-deftest gptel-workflow-test-unknown-context-source ()
  "Test error with unknown context source."
  (should-error (gptel-workflow--capture-context 'unknown)))

;;; Public API tests

(ert-deftest gptel-workflow-test-get-set-state ()
  "Test public API for getting and setting state."
  (let ((state (gptel-workflow-state-create)))
    (gptel-workflow-set-state state)
    (should (eq state (gptel-workflow-get-state)))))

(provide 'gptel-workflow-test)
;;; gptel-workflow-test.el ends here
