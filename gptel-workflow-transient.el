;;; gptel-workflow-transient.el --- Transient interface for gptel-workflow  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Karthik Chikmagalur

;; Author: Karthik Chikmagalur
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

;; Transient interface for gptel-workflow.

;;; Code:

(require 'transient)
(require 'gptel-workflow)

;;; Transient Definitions

;;;###autoload (autoload 'gptel-workflow-menu "gptel-workflow-transient" nil t)
(transient-define-prefix gptel-workflow-menu ()
  "Main menu for gptel workflow dispatcher."
  ["Workflow Actions"
   ["Setup"
    ("s" "Start workflow" gptel-workflow-start)
    ("r" "Reset workflow" gptel-workflow-reset)]
   ["Steps"
    ("p" "Run plan" gptel-workflow-run-plan)
    ("d" "Run diff" gptel-workflow-run-diff)
    ("t" "Run tests" gptel-workflow-run-tests)
    ("i" "Run integration tests" gptel-workflow-run-tests-integration)
    ("v" "Run review" gptel-workflow-run-review)
    ("c" "Run checklist" gptel-workflow-run-checklist)]
   ["Utilities"
    ("R" "Retry current step" gptel-workflow-retry-step)
    ("o" "Show output" gptel-workflow-show-output)
    ("l" "Show log" gptel-workflow-show-log)
    ("q" "Quit" transient-quit-one)]])

;;;###autoload (autoload 'gptel-workflow-step-menu "gptel-workflow-transient" nil t)
(transient-define-prefix gptel-workflow-step-menu ()
  "Per-step menu for workflow actions."
  ["Current Step Actions"
   ["Navigate"
    ("n" "Next step" gptel-workflow-next-step)
    ("p" "Previous step" gptel-workflow-previous-step)]
   ["Actions"
    ("r" "Retry with alternate preset" gptel-workflow-retry-step)
    ("e" "Edit ACs" gptel-workflow-edit-acs)
    ("c" "Continue" gptel-workflow-continue-to-next)]
   ["View"
    ("o" "Show output" gptel-workflow-show-output)
    ("l" "Show log" gptel-workflow-show-log)
    ("q" "Quit" transient-quit-one)]])

;;; Helper Commands for Transient

(defun gptel-workflow-next-step ()
  "Advance to next workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let ((current-step (gptel-workflow-state-current-step gptel-workflow--current-state)))
    (pcase current-step
      ('plan (gptel-workflow-run-diff))
      ('diff (gptel-workflow-run-tests))
      ('tests (if (gptel-workflow-state-integration-tests-flag gptel-workflow--current-state)
                  (gptel-workflow-run-tests-integration)
                (gptel-workflow-run-review)))
      ('tests-integration (gptel-workflow-run-review))
      ('review (gptel-workflow-run-checklist))
      ('checklist (message "Workflow completed"))
      (_ (gptel-workflow-run-plan)))))

(defun gptel-workflow-previous-step ()
  "Go back to previous workflow step."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let ((current-step (gptel-workflow-state-current-step gptel-workflow--current-state)))
    (pcase current-step
      ('diff (gptel-workflow-run-plan))
      ('tests (gptel-workflow-run-diff))
      ('tests-integration (gptel-workflow-run-tests))
      ('review (if (gptel-workflow-state-integration-tests-flag gptel-workflow--current-state)
                   (gptel-workflow-run-tests-integration)
                 (gptel-workflow-run-tests)))
      ('checklist (gptel-workflow-run-review))
      (_ (message "Already at first step")))))

(defun gptel-workflow-continue-to-next ()
  "Continue to next step, proceeding even if validation fails."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  ;; Set continue flag to bypass validation
  (setf (gptel-workflow-state-continue gptel-workflow--current-state) t)
  (gptel-workflow-next-step))

(defun gptel-workflow-edit-acs ()
  "Edit acceptance criteria for current workflow."
  (interactive)
  (unless gptel-workflow--current-state
    (error "No active workflow state"))
  (let* ((current-acs (gptel-workflow-state-acs gptel-workflow--current-state))
         (acs-string (mapconcat #'identity current-acs " | "))
         (new-acs-input (read-string "Acceptance criteria (separate with |): " acs-string))
         (new-acs (split-string new-acs-input "|" t "[ \t\n]+"))
         (new-acs-tagged (gptel-workflow--tag-acs new-acs)))
    (setf (gptel-workflow-state-acs gptel-workflow--current-state) new-acs)
    (setf (gptel-workflow-state-acs-tagged gptel-workflow--current-state) new-acs-tagged)
    (gptel-workflow--log "Updated ACs to: %s" new-acs-tagged)
    (message "Acceptance criteria updated")))

(provide 'gptel-workflow-transient)
;;; gptel-workflow-transient.el ends here
