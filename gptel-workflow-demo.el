;;; gptel-workflow-demo.el --- Demo script for gptel-workflow  -*- lexical-binding: t; -*-

;; This is a demonstration script showing how to use gptel-workflow

(require 'gptel-workflow)
(require 'gptel-workflow-transient)

;; Demo 1: Create a workflow state programmatically
(defun gptel-workflow-demo-1 ()
  "Demo: Create and inspect workflow state."
  (interactive)
  (let ((state (gptel-workflow-state-create
                :current-step 'plan
                :acs '("Add feature X" "Update documentation")
                :context "Sample context for demonstration")))
    ;; Tag the ACs
    (setf (gptel-workflow-state-acs-tagged state)
          (gptel-workflow--tag-acs (gptel-workflow-state-acs state)))
    
    ;; Display state info
    (message "Workflow state created:")
    (message "  Current step: %s" (gptel-workflow-state-current-step state))
    (message "  Tagged ACs: %s" (gptel-workflow-state-acs-tagged state))
    (message "  Context length: %d chars" (length (gptel-workflow-state-context state)))
    state))

;; Demo 2: Test validation functions
(defun gptel-workflow-demo-2 ()
  "Demo: Test validation functions."
  (interactive)
  (let ((tagged-acs '("AC1: Feature X" "AC2: Documentation")))
    ;; Valid plan
    (let* ((valid-plan "- Implement feature (AC1)\n- Update docs (AC2)")
           (result (gptel-workflow--validate-plan valid-plan tagged-acs)))
      (message "Valid plan validation: %s - %s" (car result) (cdr result)))
    
    ;; Invalid plan (missing bullets)
    (let* ((invalid-plan "Just text with AC1 and AC2")
           (result (gptel-workflow--validate-plan invalid-plan tagged-acs)))
      (message "Invalid plan validation: %s - %s" (car result) (cdr result)))
    
    ;; Valid diff
    (let* ((valid-diff "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n+new (AC1) (AC2)")
           (result (gptel-workflow--validate-diff valid-diff tagged-acs)))
      (message "Valid diff validation: %s - %s" (car result) (cdr result)))
    
    ;; Invalid diff (not unified format)
    (let* ((invalid-diff "Some text (AC1) (AC2)")
           (result (gptel-workflow--validate-diff invalid-diff tagged-acs)))
      (message "Invalid diff validation: %s - %s" (car result) (cdr result)))))

;; Demo 3: Test context management
(defun gptel-workflow-demo-3 ()
  "Demo: Test context pruning."
  (interactive)
  (let* ((large-context (make-string 15000 ?x))
         (pruned (gptel-workflow--prune-context large-context)))
    (message "Original context size: %d chars" (length large-context))
    (message "Pruned context size: %d chars" (length pruned))
    (message "Pruning reduced size by: %d chars" (- (length large-context) (length pruned)))))

;; Demo 4: Test AC tagging and formatting
(defun gptel-workflow-demo-4 ()
  "Demo: Test AC tagging and formatting."
  (interactive)
  (let* ((acs '("Implement login" "Add validation" "Update tests"))
         (tagged (gptel-workflow--tag-acs acs))
         (formatted (gptel-workflow--format-acs tagged)))
    (message "Original ACs: %s" acs)
    (message "Tagged ACs: %s" tagged)
    (message "Formatted for prompt:\n%s" formatted)))

;; Demo 5: Test preset system
(defun gptel-workflow-demo-5 ()
  "Demo: Test preset system."
  (interactive)
  (dolist (preset-name '(fast-low strong-medium strong-low))
    (let ((preset (gptel-workflow--get-preset preset-name)))
      (message "Preset %s:" preset-name)
      (message "  Model: %s" (plist-get preset :model))
      (message "  Temperature: %s" (plist-get preset :temperature))
      (message "  Max tokens: %s" (plist-get preset :max-tokens))))
  (message "")
  (message "Step-to-preset mapping:")
  (dolist (step '(plan diff tests review checklist))
    (message "  %s -> %s" step (gptel-workflow--get-step-preset step))))

;; Demo 6: Full workflow simulation (without actual LLM calls)
(defun gptel-workflow-demo-6 ()
  "Demo: Simulate a full workflow."
  (interactive)
  (let ((state (gptel-workflow-state-create
                :current-step nil
                :acs '("Feature A" "Feature B")
                :context "Initial context")))
    ;; Initialize
    (setf (gptel-workflow-state-acs-tagged state)
          (gptel-workflow--tag-acs (gptel-workflow-state-acs state)))
    (message "=== Workflow Simulation ===")
    (message "Step 1: Plan")
    (setf (gptel-workflow-state-current-step state) 'plan)
    (setf (gptel-workflow-state-plan state) "- Implement feature (AC1)\n- Add validation (AC2)")
    (let ((validation (gptel-workflow--validate-plan
                      (gptel-workflow-state-plan state)
                      (gptel-workflow-state-acs-tagged state))))
      (message "  Validation: %s - %s" (car validation) (cdr validation)))
    
    (message "Step 2: Diff")
    (setf (gptel-workflow-state-current-step state) 'diff)
    (setf (gptel-workflow-state-diff state)
          "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n+new (AC1) (AC2)")
    (let ((validation (gptel-workflow--validate-diff
                      (gptel-workflow-state-diff state)
                      (gptel-workflow-state-acs-tagged state))))
      (message "  Validation: %s - %s" (car validation) (cdr validation)))
    
    (message "Step 3: Tests")
    (setf (gptel-workflow-state-current-step state) 'tests)
    (setf (gptel-workflow-state-tests state)
          "--- a/test/unit/feature_test.py\n+++ b/test/unit/feature_test.py")
    (let ((validation (gptel-workflow--validate-tests
                      (gptel-workflow-state-tests state)
                      (gptel-workflow-state-diff state))))
      (message "  Validation: %s - %s" (car validation) (cdr validation)))
    
    (message "Step 4: Review")
    (setf (gptel-workflow-state-current-step state) 'review)
    (setf (gptel-workflow-state-review state)
          "- Risk: Security\n- Missing test: Edge case")
    (let ((validation (gptel-workflow--validate-review
                      (gptel-workflow-state-review state))))
      (message "  Validation: %s - %s" (car validation) (cdr validation)))
    
    (message "Step 5: Checklist")
    (setf (gptel-workflow-state-current-step state) 'checklist)
    (setf (gptel-workflow-state-checklist state)
          "- [ ] Unit tests pass\n- [ ] Code reviewed")
    
    (message "=== Workflow Complete ===")
    state))

;; Run all demos
(defun gptel-workflow-run-all-demos ()
  "Run all workflow demos."
  (interactive)
  (message "=== Running gptel-workflow demos ===\n")
  (message "Demo 1: State Creation")
  (gptel-workflow-demo-1)
  (message "\nDemo 2: Validation Functions")
  (gptel-workflow-demo-2)
  (message "\nDemo 3: Context Pruning")
  (gptel-workflow-demo-3)
  (message "\nDemo 4: AC Tagging")
  (gptel-workflow-demo-4)
  (message "\nDemo 5: Preset System")
  (gptel-workflow-demo-5)
  (message "\nDemo 6: Full Workflow Simulation")
  (gptel-workflow-demo-6)
  (message "\n=== All demos completed ==="))

(provide 'gptel-workflow-demo)
;;; gptel-workflow-demo.el ends here
