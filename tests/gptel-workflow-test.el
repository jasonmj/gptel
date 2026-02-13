;;; gptel-workflow-test.el --- Tests for gptel-workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Jason M. Jensen

;; Author: Jason M. Jensen
;; Keywords: tests

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

;; ERT tests for gptel-workflow functionality.

;;; Code:

(require 'ert)
(require 'gptel-workflow)

;; Mock gptel-request for tests
(unless (fboundp 'gptel-request)
  (defun gptel-request (prompt &rest args)
    "Mock gptel-request for testing."
    (let ((callback (plist-get args :callback)))
      (when callback
        (funcall callback
                 (format "[Mock response to: %s]" (substring prompt 0 (min 50 (length prompt))))
                 '(:status "200"))))))

;;; State Management Tests

(ert-deftest gptel-workflow-test-state-creation ()
  "Test workflow state creation."
  (let ((state (gptel-workflow-state-create
                :current-step 'plan
                :acs '("Feature works" "Tests pass")
                :context-raw "test context")))
    (should (gptel-workflow-state-p state))
    (should (eq (gptel-workflow-state-current-step state) 'plan))
    (should (equal (gptel-workflow-state-acs state) '("Feature works" "Tests pass")))
    (should (equal (gptel-workflow-state-context-raw state) "test context"))
    (should (eq (gptel-workflow-state-continue-flag state) t))
    (should (eq (gptel-workflow-state-retry-count state) 0))))

(ert-deftest gptel-workflow-test-state-modification ()
  "Test workflow state modification."
  (let ((state (gptel-workflow-state-create)))
    (setf (gptel-workflow-state-plan state) "Test plan")
    (setf (gptel-workflow-state-diff state) "Test diff")
    (should (equal (gptel-workflow-state-plan state) "Test plan"))
    (should (equal (gptel-workflow-state-diff state) "Test diff"))))

;;; Acceptance Criteria Tests

(ert-deftest gptel-workflow-test-ac-tagging ()
  "Test AC tagging functionality."
  (let ((acs '("Feature works" "Tests pass" "Code is clean")))
    (let ((tagged (gptel-workflow--tag-acs acs)))
      (should (equal tagged
                     '("AC1: Feature works"
                       "AC2: Tests pass"
                       "AC3: Code is clean"))))))

(ert-deftest gptel-workflow-test-ac-extraction ()
  "Test AC tag extraction from text."
  (let ((text "This addresses AC1 and AC3. See also AC2 for details. AC1 again."))
    (let ((tags (gptel-workflow--extract-ac-tags text)))
      (should (equal tags '("AC1" "AC3" "AC2"))))))

(ert-deftest gptel-workflow-test-ac-extraction-empty ()
  "Test AC extraction with no tags."
  (let ((text "This has no AC tags at all."))
    (should (null (gptel-workflow--extract-ac-tags text)))))

(ert-deftest gptel-workflow-test-ac-formatting ()
  "Test AC formatting for prompts."
  (let ((acs '("AC1: Feature works" "AC2: Tests pass")))
    (let ((formatted (gptel-workflow--format-acs-for-prompt acs)))
      (should (string-match-p "Acceptance Criteria:" formatted))
      (should (string-match-p "AC1: Feature works" formatted))
      (should (string-match-p "AC2: Tests pass" formatted))
      (should (string-match-p "cite AC IDs" formatted)))))

(ert-deftest gptel-workflow-test-ac-formatting-empty ()
  "Test AC formatting with empty list."
  (should (equal (gptel-workflow--format-acs-for-prompt nil) "")))

;;; Context Management Tests

(ert-deftest gptel-workflow-test-context-pruning ()
  "Test context pruning functionality."
  (let ((context "Line 1\n\n\n\n\nLine 2\nLine 3"))
    (let ((pruned (gptel-workflow--prune-context context)))
      (should (not (string-match-p "\n\n\n" pruned)))
      (should (string-match-p "Line 1" pruned))
      (should (string-match-p "Line 2" pruned)))))

(ert-deftest gptel-workflow-test-context-pruning-long-lines ()
  "Test context pruning of long lines."
  (let ((long-line (make-string 600 ?x))
        (context (concat "Short\n" (make-string 600 ?x) "\nShort2")))
    (let ((pruned (gptel-workflow--prune-context context)))
      (should (< (length pruned) (length context)))
      (should (string-match-p "\\.\\.\\." pruned)))))

;;; Validation Tests

(ert-deftest gptel-workflow-test-validate-plan-success ()
  "Test plan validation with valid output."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :acs '("Feature works"))))
    (let ((output "- Step 1: Do something\n- Step 2: Check AC1\n* Another item"))
      (let ((result (gptel-workflow--validate-plan output)))
        (should (plist-get result :valid))
        (should (plist-get result :has-bullets))
        (should (member "AC1" (plist-get result :ac-tags)))))))

(ert-deftest gptel-workflow-test-validate-plan-no-bullets ()
  "Test plan validation failure with no bullets."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create)))
    (let ((output "Just plain text without bullets"))
      (let ((result (gptel-workflow--validate-plan output)))
        (should (not (plist-get result :valid)))
        (should (not (plist-get result :has-bullets)))))))

(ert-deftest gptel-workflow-test-validate-plan-no-ac-tags ()
  "Test plan validation failure when AC tags expected but missing."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :acs '("Feature works"))))
    (let ((output "- Step 1: Do something\n- Step 2: Do more"))
      (let ((result (gptel-workflow--validate-plan output)))
        (should (not (plist-get result :valid)))
        (should (plist-get result :has-bullets))
        (should (null (plist-get result :ac-tags)))))))

(ert-deftest gptel-workflow-test-validate-diff-success ()
  "Test diff validation with valid unified diff."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :acs '("Feature works"))))
    (let ((output "diff --git a/file.el b/file.el\n@@ -1,3 +1,4 @@\n+new line AC1\n old line"))
      (let ((result (gptel-workflow--validate-diff output)))
        (should (plist-get result :valid))
        (should (plist-get result :has-diff))
        (should (member "AC1" (plist-get result :ac-tags)))))))

(ert-deftest gptel-workflow-test-validate-diff-no-diff ()
  "Test diff validation failure with no diff."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create)))
    (let ((output "Just some text, not a diff"))
      (let ((result (gptel-workflow--validate-diff output)))
        (should (not (plist-get result :valid)))
        (should (not (plist-get result :has-diff)))))))

(ert-deftest gptel-workflow-test-validate-tests-success ()
  "Test tests validation with test paths."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :acs '("Tests pass"))))
    (let ((output "diff --git a/test/mytest.el b/test/mytest.el\n+test code AC1"))
      (let ((result (gptel-workflow--validate-tests output)))
        (should (plist-get result :valid))
        (should (plist-get result :has-test-path))
        (should (member "AC1" (plist-get result :ac-tags)))))))

(ert-deftest gptel-workflow-test-validate-tests-no-test-path ()
  "Test tests validation failure with no test paths."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create)))
    (let ((output "diff --git a/src/main.el b/src/main.el\n+code"))
      (let ((result (gptel-workflow--validate-tests output)))
        (should (not (plist-get result :valid)))
        (should (not (plist-get result :has-test-path)))))))

(ert-deftest gptel-workflow-test-validate-review-success ()
  "Test review validation with bullets."
  (let ((output "* Risk: Memory leak\n- Missing: Integration tests\n* Alternative: Use cache"))
    (let ((result (gptel-workflow--validate-review output)))
      (should (plist-get result :valid))
      (should (plist-get result :has-bullets)))))

(ert-deftest gptel-workflow-test-validate-review-no-bullets ()
  "Test review validation failure with no bullets."
  (let ((output "Just plain text review"))
    (let ((result (gptel-workflow--validate-review output)))
      (should (not (plist-get result :valid)))
      (should (not (plist-get result :has-bullets))))))

;;; Prompt Building Tests

(ert-deftest gptel-workflow-test-build-plan-prompt ()
  "Test plan prompt building."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :acs '("Feature works")
          :context-raw "def foo():\n  pass")))
    (let ((prompt (gptel-workflow--build-prompt 'plan)))
      (should (string-match-p "implementation plan" prompt))
      (should (string-match-p "def foo" prompt))
      (should (string-match-p "AC1: Feature works" prompt)))))

(ert-deftest gptel-workflow-test-build-diff-prompt ()
  "Test diff prompt building."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :plan "1. Add feature\n2. Test it"
          :context-raw "def foo():\n  pass")))
    (let ((prompt (gptel-workflow--build-prompt 'diff)))
      (should (string-match-p "unified diff" prompt))
      (should (string-match-p "1\\. Add feature" prompt))
      (should (string-match-p "def foo" prompt)))))

(ert-deftest gptel-workflow-test-build-review-prompt ()
  "Test review prompt building."
  (let ((gptel-workflow--current-state
         (gptel-workflow-state-create
          :plan "Test plan"
          :diff "Test diff"
          :tests "Test tests")))
    (let ((prompt (gptel-workflow--build-prompt 'review)))
      (should (string-match-p "Review" prompt))
      (should (string-match-p "Test plan" prompt))
      (should (string-match-p "Test diff" prompt))
      (should (string-match-p "Test tests" prompt))
      (should (string-match-p "risks" prompt)))))

;;; State Progression Tests

(ert-deftest gptel-workflow-test-state-progression ()
  "Test workflow state progression through steps."
  (with-temp-buffer
    (insert "def test_function():\n    return 42\n")
    (goto-char (point-min))
    (set-mark (point-max))
    
    (gptel-workflow-start 'region '("Works correctly") nil)
    (let ((state (gptel-workflow-get-state)))
      (should (gptel-workflow-state-p state))
      (should (equal (gptel-workflow-state-acs state) '("Works correctly")))
      (should (gptel-workflow-state-context-raw state))
      (should (null (gptel-workflow-state-current-step state)))
      
      ;; Run plan step (synchronous for tests via mock)
      (let ((done nil))
        (gptel-workflow-run-plan
         (lambda (_validation)
           (setq done t)))
        ;; In real async, would need to wait, but mock is synchronous
        (should done)
        (should (eq (gptel-workflow-state-current-step state) 'plan))
        (should (gptel-workflow-state-plan state)))
      
      ;; Run diff step
      (let ((done nil))
        (gptel-workflow-run-diff
         (lambda (_validation)
           (setq done t)))
        (should done)
        (should (eq (gptel-workflow-state-current-step state) 'diff))
        (should (gptel-workflow-state-diff state))))))

(ert-deftest gptel-workflow-test-step-without-state ()
  "Test that steps fail without active state."
  (setq gptel-workflow--current-state nil)
  (should-error (gptel-workflow-run-plan)))

(ert-deftest gptel-workflow-test-step-order-enforcement ()
  "Test that steps require proper order."
  (with-temp-buffer
    (insert "test content")
    (set-mark (point-min))
    (goto-char (point-max))
    
    (gptel-workflow-start 'region nil nil)
    ;; Try to run diff without plan
    (should-error (gptel-workflow-run-diff))))

;;; Retry Tests

(ert-deftest gptel-workflow-test-retry-increments-count ()
  "Test that retry increments retry count."
  (with-temp-buffer
    (insert "test")
    (set-mark (point-min))
    (goto-char (point-max))
    
    (gptel-workflow-start 'region nil nil)
    
    (let ((done nil))
      (gptel-workflow-run-plan
       (lambda (_validation)
         (setq done t)))
      (should done))
    
    (let ((state (gptel-workflow-get-state)))
      (should (= (gptel-workflow-state-retry-count state) 0))
      
      (let ((done nil))
        (gptel-workflow-retry-step)
        ;; Mock callback is synchronous
        (should (= (gptel-workflow-state-retry-count state) 1)))
      
      (let ((done nil))
        (gptel-workflow-retry-step)
        (should (= (gptel-workflow-state-retry-count state) 2))))))

;;; Integration Tests

(ert-deftest gptel-workflow-test-integration-tests-flag ()
  "Test integration tests flag handling."
  (with-temp-buffer
    (insert "test")
    (set-mark (point-min))
    (goto-char (point-max))
    
    (gptel-workflow-start 'region nil t)
    (let ((state (gptel-workflow-get-state)))
      (should (gptel-workflow-state-integration-tests-p state)))))

;;; Output Formatting Tests

(ert-deftest gptel-workflow-test-output-display ()
  "Test output display creates buffer."
  (let ((output "Test output")
        (validation (list :valid t :message "Success" :ac-tags '("AC1" "AC2"))))
    (gptel-workflow--display-output "Test Step" output validation)
    (should (get-buffer gptel-workflow-output-buffer-name))
    (with-current-buffer gptel-workflow-output-buffer-name
      (should (string-match-p "Test Step" (buffer-string)))
      (should (string-match-p "Test output" (buffer-string)))
      (should (string-match-p "Success" (buffer-string)))
      (should (string-match-p "AC1, AC2" (buffer-string))))))

;;; Logging Tests

(ert-deftest gptel-workflow-test-logging ()
  "Test logging creates entries."
  (gptel-workflow--log "test-step" "test-preset" "test-variant" "success")
  (should (get-buffer gptel-workflow-log-buffer-name))
  (with-current-buffer gptel-workflow-log-buffer-name
    (should (string-match-p "test-step" (buffer-string)))
    (should (string-match-p "test-preset" (buffer-string)))
    (should (string-match-p "test-variant" (buffer-string)))
    (should (string-match-p "success" (buffer-string)))))

;;; Preset Tests

(ert-deftest gptel-workflow-test-presets-defined ()
  "Test that all required presets are defined."
  (should (assq 'fast-low gptel-workflow-presets))
  (should (assq 'strong-medium gptel-workflow-presets))
  (should (assq 'strong-low gptel-workflow-presets)))

(ert-deftest gptel-workflow-test-step-preset-mapping ()
  "Test step to preset mapping."
  (should (eq (alist-get 'plan gptel-workflow-step-preset-map) 'strong-medium))
  (should (eq (alist-get 'diff gptel-workflow-step-preset-map) 'strong-low))
  (should (eq (alist-get 'tests gptel-workflow-step-preset-map) 'strong-low))
  (should (eq (alist-get 'review gptel-workflow-step-preset-map) 'strong-low))
  (should (eq (alist-get 'summarize gptel-workflow-step-preset-map) 'fast-low)))

;;; Edge Cases

(ert-deftest gptel-workflow-test-empty-context ()
  "Test handling of empty context."
  (let ((pruned (gptel-workflow--prune-context "")))
    (should (equal pruned ""))))

(ert-deftest gptel-workflow-test-set-acs ()
  "Test setting ACs via API."
  (with-temp-buffer
    (insert "test")
    (set-mark (point-min))
    (goto-char (point-max))
    
    (gptel-workflow-start 'region nil nil)
    (gptel-workflow-set-acs "AC1,AC2,AC3")
    
    (let ((state (gptel-workflow-get-state)))
      (should (equal (gptel-workflow-state-acs state)
                     '("AC1" "AC2" "AC3"))))))

(provide 'gptel-workflow-test)
;;; gptel-workflow-test.el ends here
