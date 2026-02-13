;;; gptel-workflow-transient.el --- Transient menu for gptel-workflow  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; Author: Karthik Chikmagalur <karthikchikmagalur@gmail.com>
;; Keywords: convenience

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

;; Transient menu interface for gptel-workflow.

;;; Code:

(require 'gptel-workflow)
(require 'transient)

;;; Transient arguments and variables

(defvar gptel-workflow--transient-context-source 'region
  "Context source for workflow: region, defun, or buffer.")

(defvar gptel-workflow--transient-preset nil
  "Preset override for current step.")

(defvar gptel-workflow--transient-integration-tests nil
  "Whether to run integration tests.")

(defvar gptel-workflow--transient-acs nil
  "List of acceptance criteria strings.")

;;; Transient classes and readers

(transient-define-infix gptel-workflow--infix-context-source ()
  "Set context source for workflow."
  :class 'transient-lisp-variable
  :variable 'gptel-workflow--transient-context-source
  :reader (lambda (_prompt _initial-input _history)
            (intern (completing-read "Context source: "
                                     '(region defun buffer)
                                     nil t)))
  :prompt "Context source: "
  :key "c")

(transient-define-infix gptel-workflow--infix-preset ()
  "Set preset override for current step."
  :class 'transient-lisp-variable
  :variable 'gptel-workflow--transient-preset
  :reader (lambda (_prompt _initial-input _history)
            (intern (completing-read "Preset: "
                                     '(fast-low strong-medium strong-low)
                                     nil t)))
  :prompt "Preset override: "
  :key "p")

(transient-define-infix gptel-workflow--infix-integration-tests ()
  "Toggle integration tests flag."
  :class 'transient-lisp-variable
  :variable 'gptel-workflow--transient-integration-tests
  :reader (lambda (_prompt _initial-input _history)
            (not gptel-workflow--transient-integration-tests))
  :key "i")

(transient-define-infix gptel-workflow--infix-acs ()
  "Set acceptance criteria."
  :class 'transient-lisp-variable
  :variable 'gptel-workflow--transient-acs
  :reader (lambda (_prompt _initial-input _history)
            (let ((input (read-string "Acceptance criteria (one per line): ")))
              (if (string-blank-p input)
                  nil
                (split-string input "\n" t "[ \t]+"))))
  :prompt "Acceptance criteria: "
  :key "a")

;;; Helper functions

(defun gptel-workflow--transient-setup-state ()
  "Setup workflow state from transient arguments."
  (unless gptel-workflow--current-state
    (let* ((context (gptel-workflow--capture-context
                     gptel-workflow--transient-context-source))
           (context (gptel-workflow--prune-context context))
           (state (gptel-workflow-state-create
                   :context context
                   :acs gptel-workflow--transient-acs
                   :integration-test-flag gptel-workflow--transient-integration-tests
                   :preset-override gptel-workflow--transient-preset)))
      (setq gptel-workflow--current-state state)
      (gptel-workflow--log state "Workflow created from transient")))
  gptel-workflow--current-state)

(defun gptel-workflow--transient-update-preset ()
  "Update preset override in current state."
  (when gptel-workflow--current-state
    (setf (gptel-workflow-state-preset-override gptel-workflow--current-state)
          gptel-workflow--transient-preset)))

(defun gptel-workflow--transient-run-step (step-fn)
  "Run STEP-FN with current state."
  (let ((state (gptel-workflow--transient-setup-state)))
    (gptel-workflow--transient-update-preset)
    (funcall step-fn state)))

;;; Step commands

(transient-define-suffix gptel-workflow--transient-plan ()
  "Run plan step from transient."
  :description "Generate plan"
  :key "1"
  (interactive)
  (gptel-workflow--transient-run-step #'gptel-workflow-plan))

(transient-define-suffix gptel-workflow--transient-diff ()
  "Run diff step from transient."
  :description "Generate diff"
  :key "2"
  (interactive)
  (gptel-workflow--transient-run-step #'gptel-workflow-diff))

(transient-define-suffix gptel-workflow--transient-tests ()
  "Run tests step from transient."
  :description "Generate tests"
  :key "3"
  (interactive)
  (gptel-workflow--transient-run-step #'gptel-workflow-tests))

(transient-define-suffix gptel-workflow--transient-review ()
  "Run review step from transient."
  :description "Generate review"
  :key "4"
  (interactive)
  (gptel-workflow--transient-run-step #'gptel-workflow-review))

(transient-define-suffix gptel-workflow--transient-checklist ()
  "Run checklist step from transient."
  :description "Generate checklist"
  :key "5"
  (interactive)
  (gptel-workflow--transient-run-step #'gptel-workflow-checklist))

(transient-define-suffix gptel-workflow--transient-run-all ()
  "Run all workflow steps sequentially."
  :description "Run all steps"
  :key "r"
  (interactive)
  (let ((state (gptel-workflow--transient-setup-state)))
    (gptel-workflow--transient-update-preset)
    (message "Running all workflow steps...")
    ;; Note: This simplified version doesn't chain callbacks properly
    ;; A production version would need proper async chaining
    (gptel-workflow-plan state)))

(transient-define-suffix gptel-workflow--transient-show-output ()
  "Show workflow output buffer."
  :description "Show output"
  :key "o"
  (interactive)
  (gptel-workflow-show-output))

(transient-define-suffix gptel-workflow--transient-show-log ()
  "Show workflow log buffer."
  :description "Show log"
  :key "l"
  (interactive)
  (gptel-workflow-show-log))

(transient-define-suffix gptel-workflow--transient-reset ()
  "Reset workflow state."
  :description "Reset workflow"
  :key "R"
  (interactive)
  (when (yes-or-no-p "Reset workflow state? ")
    (setq gptel-workflow--current-state nil)
    (message "Workflow state reset")))

;;; Main transient menu

;;;###autoload (autoload 'gptel-workflow-menu "gptel-workflow-transient" nil t)
(transient-define-prefix gptel-workflow-menu ()
  "Main menu for gptel-workflow dispatcher."
  ["Configuration"
   [("c" "Context source" gptel-workflow--infix-context-source)
    ("a" "Acceptance criteria" gptel-workflow--infix-acs)]
   [("p" "Preset override" gptel-workflow--infix-preset)
    ("i" "Integration tests" gptel-workflow--infix-integration-tests)]]
  ["Steps"
   [("1" "Plan" gptel-workflow--transient-plan)
    ("2" "Diff" gptel-workflow--transient-diff)
    ("3" "Tests" gptel-workflow--transient-tests)]
   [("4" "Review" gptel-workflow--transient-review)
    ("5" "Checklist" gptel-workflow--transient-checklist)
    ("r" "Run all" gptel-workflow--transient-run-all)]]
  ["Output"
   [("o" "Show output" gptel-workflow--transient-show-output)
    ("l" "Show log" gptel-workflow--transient-show-log)
    ("R" "Reset" gptel-workflow--transient-reset)]]
  ["Quit"
   ("q" "Quit" transient-quit-one)])

;;; Per-step transient menu

(defun gptel-workflow--step-status (state step)
  "Get status string for STEP in STATE."
  (let ((step-data (pcase step
                     ('plan (gptel-workflow-state-plan state))
                     ('diff (gptel-workflow-state-diff state))
                     ('tests (gptel-workflow-state-tests state))
                     ('review (gptel-workflow-state-review state))
                     ('checklist (gptel-workflow-state-checklist state)))))
    (if step-data "✓" "⋯")))

(transient-define-suffix gptel-workflow--step-proceed ()
  "Proceed to next step."
  :description "Proceed"
  :key "p"
  (interactive)
  (message "Proceeding to next step..."))

(transient-define-suffix gptel-workflow--step-retry ()
  "Retry current step."
  :description "Retry"
  :key "r"
  (interactive)
  (when gptel-workflow--current-state
    (let ((step (gptel-workflow-state-step gptel-workflow--current-state)))
      (message "Retrying step: %s" step)
      (pcase step
        ('plan (gptel-workflow-plan gptel-workflow--current-state))
        ('diff (gptel-workflow-diff gptel-workflow--current-state))
        ('tests (gptel-workflow-tests gptel-workflow--current-state))
        ('review (gptel-workflow-review gptel-workflow--current-state))
        ('checklist (gptel-workflow-checklist gptel-workflow--current-state))))))

(transient-define-suffix gptel-workflow--step-edit-prompt ()
  "Edit prompt for current step."
  :description "Edit prompt"
  :key "e"
  (interactive)
  (message "Edit prompt functionality not yet implemented"))

;;;###autoload (autoload 'gptel-workflow-step-menu "gptel-workflow-transient" nil t)
(transient-define-prefix gptel-workflow-step-menu ()
  "Per-step menu for workflow management."
  ["Current Step"
   [("p" "Proceed" gptel-workflow--step-proceed)
    ("r" "Retry" gptel-workflow--step-retry)
    ("e" "Edit" gptel-workflow--step-edit-prompt)]]
  ["View"
   [("o" "Show output" gptel-workflow--transient-show-output)
    ("l" "Show log" gptel-workflow--transient-show-log)]]
  ["Quit"
   ("q" "Quit" transient-quit-one)])

(provide 'gptel-workflow-transient)
;;; gptel-workflow-transient.el ends here
