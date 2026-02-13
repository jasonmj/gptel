;;; gptel-workflow-test.el --- Tests for gptel-workflow  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; ERT tests for gptel-workflow module.

;;; Code:

(require 'ert)
(require 'gptel-workflow)

;;; State Management Tests

(ert-deftest gptel-workflow-test-state-creation ()
  "Test workflow state creation."
  (let ((state (gptel-workflow-state-create
                :current-step 'plan
                :acs '("Feature A" "Feature B")
                :context "test context")))
    (should (gptel-workflow-state-p state))
    (should (eq (gptel-workflow-state-current-step state) 'plan))
    (should (equal (gptel-workflow-state-acs state) '("Feature A" "Feature B")))
    (should (equal (gptel-workflow-state-context state) "test context"))))

(ert-deftest gptel-workflow-test-ac-tagging ()
  "Test acceptance criteria tagging."
  (let* ((acs '("Implement feature X" "Add validation" "Update docs"))
         (tagged (gptel-workflow--tag-acs acs)))
    (should (equal tagged '("AC1: Implement feature X"
                           "AC2: Add validation"
                           "AC3: Update docs")))))

(ert-deftest gptel-workflow-test-ac-formatting ()
  "Test acceptance criteria formatting for prompts."
  (let* ((tagged-acs '("AC1: Feature A" "AC2: Feature B"))
         (formatted (gptel-workflow--format-acs tagged-acs)))
    (should (string-match-p "Acceptance Criteria:" formatted))
    (should (string-match-p "AC1: Feature A" formatted))
    (should (string-match-p "AC2: Feature B" formatted))))

;;; Preset Management Tests

(ert-deftest gptel-workflow-test-get-preset ()
  "Test getting preset configuration."
  (let ((preset (gptel-workflow--get-preset 'fast-low)))
    (should (plist-get preset :model))
    (should (plist-get preset :temperature))
    (should (plist-get preset :max-tokens))))

(ert-deftest gptel-workflow-test-step-preset-mapping ()
  "Test step to preset mapping."
  (should (eq (gptel-workflow--get-step-preset 'plan) 'strong-medium))
  (should (eq (gptel-workflow--get-step-preset 'diff) 'strong-low))
  (should (eq (gptel-workflow--get-step-preset 'tests) 'strong-low))
  (should (eq (gptel-workflow--get-step-preset 'review) 'strong-low)))

(ert-deftest gptel-workflow-test-preset-override ()
  "Test preset override functionality."
  (let ((state (gptel-workflow-state-create
                :preset-overrides '((plan . fast-low)))))
    (should (eq (gptel-workflow--get-step-preset 'plan state) 'fast-low))
    (should (eq (gptel-workflow--get-step-preset 'diff state) 'strong-low))))

;;; Context Management Tests

(ert-deftest gptel-workflow-test-context-pruning ()
  "Test context pruning removes excessive whitespace."
  (let* ((context "Line 1   with   spaces\n\n\n\nLine 2")
         (pruned (gptel-workflow--prune-context context)))
    (should (not (string-match-p "   " pruned)))
    (should (not (string-match-p "\n\n\n" pruned)))))

(ert-deftest gptel-workflow-test-context-pruning-size-limit ()
  "Test context pruning limits size."
  (let* ((large-context (make-string 20000 ?x))
         (pruned (gptel-workflow--prune-context large-context)))
    (should (<= (length pruned) 10000))))

;;; Validation Tests

(ert-deftest gptel-workflow-test-validate-plan-with-bullets ()
  "Test plan validation with bullets and AC citations."
  (let* ((acs-tagged '("AC1: Feature A" "AC2: Feature B"))
         (valid-plan "- Implement feature (AC1)\n- Add validation (AC2)")
         (result (gptel-workflow--validate-plan valid-plan acs-tagged)))
    (should (car result))
    (should (string-match-p "passed" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-plan-missing-bullets ()
  "Test plan validation fails without bullets."
  (let* ((acs-tagged '("AC1: Feature A"))
         (invalid-plan "Just text without bullets AC1")
         (result (gptel-workflow--validate-plan invalid-plan acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "bullet" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-plan-missing-ac-citations ()
  "Test plan validation fails without AC citations."
  (let* ((acs-tagged '("AC1: Feature A" "AC2: Feature B"))
         (invalid-plan "- Implement feature (AC1)\n- Other stuff")
         (result (gptel-workflow--validate-plan invalid-plan acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "does not cite all ACs" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-diff-unified-format ()
  "Test diff validation with unified diff format."
  (let* ((acs-tagged '("AC1: Feature A"))
         (valid-diff "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n+new (AC1)")
         (result (gptel-workflow--validate-diff valid-diff acs-tagged)))
    (should (car result))))

(ert-deftest gptel-workflow-test-validate-diff-empty ()
  "Test diff validation fails with empty diff."
  (let* ((acs-tagged '("AC1: Feature A"))
         (empty-diff "   \n  \n")
         (result (gptel-workflow--validate-diff empty-diff acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "empty" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-diff-not-unified ()
  "Test diff validation fails without unified diff format."
  (let* ((acs-tagged '("AC1: Feature A"))
         (invalid-diff "Just some text (AC1)")
         (result (gptel-workflow--validate-diff invalid-diff acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "unified diff" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-tests-empty ()
  "Test tests validation fails with empty output."
  (let* ((diff "--- a/file.txt\n+++ b/file.txt")
         (empty-tests "   ")
         (result (gptel-workflow--validate-tests empty-tests diff)))
    (should (not (car result)))
    (should (string-match-p "empty" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-tests-with-test-paths ()
  "Test tests validation succeeds with test paths."
  (let* ((diff "--- a/file.txt\n+++ b/file.txt")
         (tests "--- a/test/unit/feature_test.py\n+++ b/test/unit/feature_test.py")
         (result (gptel-workflow--validate-tests tests diff)))
    (should (car result))))

(ert-deftest gptel-workflow-test-validate-review-with-bullets ()
  "Test review validation with bullets."
  (let* ((valid-review "- Risk: Security issue\n- Missing test: Edge case")
         (result (gptel-workflow--validate-review valid-review)))
    (should (car result))))

(ert-deftest gptel-workflow-test-validate-review-empty ()
  "Test review validation fails with empty review."
  (let* ((empty-review "  ")
         (result (gptel-workflow--validate-review empty-review)))
    (should (not (car result)))
    (should (string-match-p "empty" (cdr result)))))

(ert-deftest gptel-workflow-test-validate-review-missing-bullets ()
  "Test review validation fails without bullets."
  (let* ((invalid-review "Just text without bullets")
         (result (gptel-workflow--validate-review invalid-review)))
    (should (not (car result)))
    (should (string-match-p "bullet" (cdr result)))))

;;; Prompt Building Tests

(ert-deftest gptel-workflow-test-build-plan-prompt ()
  "Test building plan prompt."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged '("AC1: Feature A")
                 :context "test context"))
         (prompt (gptel-workflow--build-prompt 'plan state)))
    (should (string-match-p "implementation plan" prompt))
    (should (string-match-p "AC1: Feature A" prompt))
    (should (string-match-p "test context" prompt))))

(ert-deftest gptel-workflow-test-build-diff-prompt ()
  "Test building diff prompt."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged '("AC1: Feature A")
                 :plan "- Step 1\n- Step 2"))
         (prompt (gptel-workflow--build-prompt 'diff state)))
    (should (string-match-p "unified diff" prompt))
    (should (string-match-p "AC1: Feature A" prompt))
    (should (string-match-p "Step 1" prompt))))

(ert-deftest gptel-workflow-test-build-tests-prompt ()
  "Test building tests prompt."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged '("AC1: Feature A")
                 :diff "--- a/file.txt\n+++ b/file.txt"))
         (prompt (gptel-workflow--build-prompt 'tests state)))
    (should (string-match-p "unit tests" prompt))
    (should (string-match-p "AC1: Feature A" prompt))
    (should (string-match-p "file.txt" prompt))))

(ert-deftest gptel-workflow-test-build-review-prompt ()
  "Test building review prompt."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged '("AC1: Feature A")
                 :diff "--- a/file.txt"
                 :tests "--- a/test.py"))
         (prompt (gptel-workflow--build-prompt 'review state)))
    (should (string-match-p "Review" prompt))
    (should (string-match-p "risks" prompt))
    (should (string-match-p "AC1: Feature A" prompt))))

(ert-deftest gptel-workflow-test-build-checklist-prompt ()
  "Test building checklist prompt."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged '("AC1: Feature A")
                 :plan "- Step 1"
                 :review "- Risk: X"))
         (prompt (gptel-workflow--build-prompt 'checklist state)))
    (should (string-match-p "checklist" prompt))
    (should (string-match-p "AC1: Feature A" prompt))
    (should (string-match-p "Step 1" prompt))))

;;; State Progression Tests

(ert-deftest gptel-workflow-test-state-progression ()
  "Test workflow state progression through steps."
  (let ((state (gptel-workflow-state-create
                :current-step nil
                :acs '("Feature A"))))
    ;; Start with plan
    (setf (gptel-workflow-state-current-step state) 'plan)
    (should (eq (gptel-workflow-state-current-step state) 'plan))
    ;; Move to diff
    (setf (gptel-workflow-state-current-step state) 'diff)
    (should (eq (gptel-workflow-state-current-step state) 'diff))
    ;; Store plan output
    (setf (gptel-workflow-state-plan state) "Plan output")
    (should (equal (gptel-workflow-state-plan state) "Plan output"))
    ;; Move to tests
    (setf (gptel-workflow-state-current-step state) 'tests)
    (should (eq (gptel-workflow-state-current-step state) 'tests))
    ;; Store diff output
    (setf (gptel-workflow-state-diff state) "Diff output")
    (should (equal (gptel-workflow-state-diff state) "Diff output"))))

(ert-deftest gptel-workflow-test-retry-count ()
  "Test retry count increments."
  (let ((state (gptel-workflow-state-create :retry-count 0)))
    (should (= (gptel-workflow-state-retry-count state) 0))
    (cl-incf (gptel-workflow-state-retry-count state))
    (should (= (gptel-workflow-state-retry-count state) 1))
    (cl-incf (gptel-workflow-state-retry-count state))
    (should (= (gptel-workflow-state-retry-count state) 2))))

(ert-deftest gptel-workflow-test-integration-flag ()
  "Test integration tests flag."
  (let ((state (gptel-workflow-state-create
                :integration-tests-flag t)))
    (should (gptel-workflow-state-integration-tests-flag state)))
  (let ((state (gptel-workflow-state-create
                :integration-tests-flag nil)))
    (should (not (gptel-workflow-state-integration-tests-flag state)))))

;;; Output Formatting Tests

(ert-deftest gptel-workflow-test-ac-formatting-empty ()
  "Test AC formatting with empty list."
  (let ((formatted (gptel-workflow--format-acs nil)))
    (should (equal formatted ""))))

(ert-deftest gptel-workflow-test-ac-formatting-multiple ()
  "Test AC formatting with multiple ACs."
  (let* ((acs '("AC1: First" "AC2: Second" "AC3: Third"))
         (formatted (gptel-workflow--format-acs acs)))
    (should (string-match-p "Acceptance Criteria:" formatted))
    (should (string-match-p "AC1: First" formatted))
    (should (string-match-p "AC2: Second" formatted))
    (should (string-match-p "AC3: Third" formatted))))

;;; Edge Cases and Error Handling

(ert-deftest gptel-workflow-test-unknown-step ()
  "Test handling of unknown step."
  (let ((state (gptel-workflow-state-create)))
    (should-error (gptel-workflow--build-prompt 'unknown-step state))))

(ert-deftest gptel-workflow-test-nil-context ()
  "Test handling of nil context."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged '("AC1: Feature A")
                 :context nil))
         (prompt (gptel-workflow--build-prompt 'plan state)))
    (should (string-match-p "implementation plan" prompt))
    (should (not (string-match-p "Context:" prompt)))))

(ert-deftest gptel-workflow-test-empty-acs ()
  "Test handling of empty ACs."
  (let* ((state (gptel-workflow-state-create
                 :acs-tagged nil
                 :context "test"))
         (prompt (gptel-workflow--build-prompt 'plan state)))
    (should (string-match-p "implementation plan" prompt))
    (should (not (string-match-p "Acceptance Criteria:" prompt)))))

;;; Integration Tests

(ert-deftest gptel-workflow-test-full-state-workflow ()
  "Test full workflow state through all steps."
  (let ((state (gptel-workflow-state-create
                :current-step nil
                :acs '("Feature A" "Feature B")
                :context "Initial context")))
    ;; Tag ACs
    (setf (gptel-workflow-state-acs-tagged state)
          (gptel-workflow--tag-acs (gptel-workflow-state-acs state)))
    (should (equal (gptel-workflow-state-acs-tagged state)
                  '("AC1: Feature A" "AC2: Feature B")))
    ;; Plan step
    (setf (gptel-workflow-state-current-step state) 'plan)
    (setf (gptel-workflow-state-plan state) "- Implement feature (AC1)\n- Add validation (AC2)")
    (let ((validation (gptel-workflow--validate-plan
                      (gptel-workflow-state-plan state)
                      (gptel-workflow-state-acs-tagged state))))
      (should (car validation)))
    ;; Diff step
    (setf (gptel-workflow-state-current-step state) 'diff)
    (setf (gptel-workflow-state-diff state)
          "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n+new (AC1) (AC2)")
    (let ((validation (gptel-workflow--validate-diff
                      (gptel-workflow-state-diff state)
                      (gptel-workflow-state-acs-tagged state))))
      (should (car validation)))
    ;; Tests step
    (setf (gptel-workflow-state-current-step state) 'tests)
    (setf (gptel-workflow-state-tests state)
          "--- a/test/unit/feature_test.py\n+++ b/test/unit/feature_test.py")
    (let ((validation (gptel-workflow--validate-tests
                      (gptel-workflow-state-tests state)
                      (gptel-workflow-state-diff state))))
      (should (car validation)))
    ;; Review step
    (setf (gptel-workflow-state-current-step state) 'review)
    (setf (gptel-workflow-state-review state)
          "- Risk: Security\n- Missing test: Edge case")
    (let ((validation (gptel-workflow--validate-review
                      (gptel-workflow-state-review state))))
      (should (car validation)))
    ;; Checklist step
    (setf (gptel-workflow-state-current-step state) 'checklist)
    (setf (gptel-workflow-state-checklist state)
          "- [ ] Unit tests pass\n- [ ] Code reviewed")
    (should (gptel-workflow-state-checklist state))))

;;; Enhanced Validation Tests

(ert-deftest gptel-workflow-test-multiline-bullets ()
  "Test multiline bullet validation."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Valid multiline with bullets
         (valid-plan "Some intro\n- First bullet (AC1)\n- Second bullet\n\nConclusion")
         (result1 (gptel-workflow--validate-plan valid-plan acs-tagged))
         ;; Invalid multiline with bullets only on first line
         (invalid-plan "- Only first line has bullet\nSecond line no bullet\nThird line no bullet")
         (result2 (gptel-workflow--validate-plan invalid-plan '())))
    (should (car result1))
    ;; Still valid even if not all lines have bullets, as long as some do
    (should (gptel-workflow--has-bullets-p invalid-plan))))

(ert-deftest gptel-workflow-test-ac-word-boundaries ()
  "Test AC citation with word boundaries."
  (let* ((acs-tagged '("AC1: Feature A" "AC2: Feature B"))
         ;; Valid - proper AC citations with bullets
         (valid "- Implement AC1\n- Also AC2")
         (result1 (gptel-workflow--validate-plan valid acs-tagged))
         ;; Invalid - partial match (AC11 should not match AC1)
         (invalid "- Implement AC11 only")
         (result2 (gptel-workflow--validate-plan invalid '("AC1: Feature A"))))
    (should (car result1))
    (should (not (car result2)))))

(ert-deftest gptel-workflow-test-diff-structure ()
  "Test improved diff validation requiring full structure."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Valid unified diff
         (valid-diff "--- a/file.txt\n+++ b/file.txt\n@@ -1,2 +1,2 @@\n-old line\n+new line (AC1)")
         (result1 (gptel-workflow--validate-diff valid-diff acs-tagged))
         ;; Invalid - missing file headers
         (invalid-diff1 "@@ -1,2 +1,2 @@\n-old\n+new (AC1)")
         (result2 (gptel-workflow--validate-diff invalid-diff1 acs-tagged))
         ;; Invalid - missing hunk
         (invalid-diff2 "--- a/file.txt\n+++ b/file.txt\n-old (AC1)\n+new")
         (result3 (gptel-workflow--validate-diff invalid-diff2 acs-tagged))
         ;; Invalid - missing body
         (invalid-diff3 "--- a/file.txt\n+++ b/file.txt\n@@ -1,2 +1,2 @@ (AC1)")
         (result4 (gptel-workflow--validate-diff invalid-diff3 acs-tagged)))
    (should (car result1))
    (should (not (car result2)))
    (should (string-match-p "file headers" (cdr result2)))
    (should (not (car result3)))
    (should (string-match-p "hunk headers" (cdr result3)))
    (should (not (car result4)))
    (should (string-match-p "+/- lines" (cdr result4)))))

(ert-deftest gptel-workflow-test-glob-to-regex ()
  "Test glob pattern to regex conversion."
  (let ((regex1 (gptel-workflow--glob-to-regex "**/test/**"))
        (regex2 (gptel-workflow--glob-to-regex "**/*_test.*"))
        (regex3 (gptel-workflow--glob-to-regex "**/tests/**")))
    ;; Should match paths with /test/ in them
    (should (string-match-p regex1 "src/test/unit/feature.py"))
    (should (string-match-p regex1 "test/file.txt"))
    ;; Should match files ending with _test.
    (should (string-match-p regex2 "file_test.py"))
    (should (string-match-p regex2 "src/feature_test.js"))
    ;; Should match paths with /tests/ in them
    (should (string-match-p regex3 "src/tests/unit.py"))))

(ert-deftest gptel-workflow-test-integration-validation ()
  "Test integration test validation uses correct patterns."
  (let* ((diff "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n+new")
         ;; Unit test with unit path
         (unit-tests "--- a/test/unit/feature_test.py\n+++ b/test/unit/feature_test.py")
         (result1 (gptel-workflow--validate-tests unit-tests diff nil))
         ;; Integration test with integration path
         (integration-tests "--- a/test/integration/api_test.py\n+++ b/test/integration/api_test.py")
         (result2 (gptel-workflow--validate-tests integration-tests diff t)))
    (should (car result1))
    (should (car result2))))

(ert-deftest gptel-workflow-test-context-truncation-logged ()
  "Test that context truncation is logged."
  (let* ((large-context (make-string 15000 ?x))
         (log-buffer (get-buffer-create gptel-workflow-log-buffer-name)))
    (with-current-buffer log-buffer
      (erase-buffer))
    (gptel-workflow--prune-context large-context)
    (with-current-buffer log-buffer
      (should (string-match-p "truncated" (buffer-string)))
      (should (string-match-p "15000" (buffer-string)))
      (should (string-match-p "10000" (buffer-string))))))

;;; Enhanced Diff Validation Tests

(ert-deftest gptel-workflow-test-diff-multi-hunk ()
  "Test diff validation with multiple hunks."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Valid multi-hunk diff
         (multi-hunk "--- a/file1.txt
+++ b/file1.txt
@@ -1,1 +1,1 @@
-old line
+new line (AC1)
--- a/file2.txt
+++ b/file2.txt
@@ -1,1 +1,1 @@
-old line 2
+new line 2")
         (result (gptel-workflow--validate-diff multi-hunk acs-tagged)))
    (should (car result))))

(ert-deftest gptel-workflow-test-diff-headers-mid-string ()
  "Test diff validation with headers not at start."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Headers after some text - should still be valid
         (headers-mid "Some preamble text
--- a/file.txt
+++ b/file.txt
@@ -1,1 +1,1 @@
-old (AC1)
+new")
         (result (gptel-workflow--validate-diff headers-mid acs-tagged)))
    (should (car result))))

(ert-deftest gptel-workflow-test-diff-only-context-lines ()
  "Test diff validation rejects diffs with only context lines (no +/-)."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Invalid - only context lines, no additions or deletions
         (only-context "--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 context line 1 (AC1)
 context line 2
 context line 3")
         (result (gptel-workflow--validate-diff only-context acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "+/- lines" (cdr result)))))

(ert-deftest gptel-workflow-test-diff-only-additions ()
  "Test diff validation rejects diffs with only additions (no deletions)."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Invalid - only additions, no deletions
         (only-additions "--- a/file.txt
+++ b/file.txt
@@ -0,0 +1,2 @@
+new line 1 (AC1)
+new line 2")
         (result (gptel-workflow--validate-diff only-additions acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "+/- lines" (cdr result)))))

(ert-deftest gptel-workflow-test-diff-only-deletions ()
  "Test diff validation rejects diffs with only deletions (no additions)."
  (let* ((acs-tagged '("AC1: Feature A"))
         ;; Invalid - only deletions, no additions
         (only-deletions "--- a/file.txt
+++ b/file.txt
@@ -1,2 +0,0 @@
-old line 1 (AC1)
-old line 2")
         (result (gptel-workflow--validate-diff only-deletions acs-tagged)))
    (should (not (car result)))
    (should (string-match-p "+/- lines" (cdr result)))))

;;; Enhanced Test Path Validation Tests

(ert-deftest gptel-workflow-test-path-validation-file-headers-only ()
  "Test that test path validation only matches file headers, not content."
  (let* ((diff "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n+new")
         ;; Tests with test path in content but not in file headers - should fail
         (tests-wrong-path "--- a/src/feature.py
+++ b/src/feature.py
@@ -1,1 +1,1 @@
-old
+new test/unit/something")
         (result1 (gptel-workflow--validate-tests tests-wrong-path diff nil))
         ;; Tests with test path in file headers - should pass
         (tests-correct-path "--- a/test/unit/feature_test.py
+++ b/test/unit/feature_test.py
@@ -1,1 +1,1 @@
-old
+new")
         (result2 (gptel-workflow--validate-tests tests-correct-path diff nil)))
    (should (not (car result1)))
    (should (car result2))))

(ert-deftest gptel-workflow-test-glob-negative-cases ()
  "Test glob conversion doesn't over-match."
  (let ((regex-test (gptel-workflow--glob-to-regex "**/test/**"))
        (regex-tests (gptel-workflow--glob-to-regex "**/tests/**")))
    ;; Should not match paths without the pattern
    (should (not (string-match-p regex-test "src/contest/file.py")))
    (should (not (string-match-p regex-test "testing/file.py")))
    (should (not (string-match-p regex-tests "src/test/file.py")))
    ;; Should match correct paths
    (should (string-match-p regex-test "src/test/unit.py"))
    (should (string-match-p regex-tests "src/tests/unit.py"))))

(provide 'gptel-workflow-test)
;;; gptel-workflow-test.el ends here
