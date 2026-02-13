;;; gptel-workflow-transient.el --- Transient UI for gptel-workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Jason M. Jensen

;; Author: Jason M. Jensen
;; Keywords: convenience
;; Package-Requires: ((emacs "27.1") (transient "0.7.4") (gptel-workflow "0.1"))

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

;; Transient interface for gptel-workflow operations.

;;; Code:

(require 'transient)
(require 'gptel-workflow)

;;; Transient Options

(defvar gptel-workflow-transient--context-source 'region
  "Context source for workflow initialization.")

(defvar gptel-workflow-transient--integration-tests nil
  "Whether to include integration tests.")

(defvar gptel-workflow-transient--acs nil
  "Acceptance criteria for workflow.")

;;; Entry Transient

(transient-define-argument gptel-workflow-transient--context-source-arg ()
  "Select context source."
  :description "Context source"
  :class 'transient-option
  :key "-c"
  :argument "--context-source="
  :choices '("region" "defun")
  :init-value (lambda (obj)
                (oset obj value
                      (format "--context-source=%s" gptel-workflow-transient--context-source))))

(transient-define-argument gptel-workflow-transient--integration-tests-arg ()
  "Toggle integration tests."
  :description "Integration tests"
  :class 'transient-switch
  :key "-i"
  :argument "--integration-tests")

(transient-define-argument gptel-workflow-transient--acs-arg ()
  "Enter acceptance criteria."
  :description "Acceptance criteria"
  :class 'transient-option
  :key "-a"
  :argument "--acs="
  :reader 'read-string)

(transient-define-prefix gptel-workflow-menu ()
  "Main workflow menu."
  ["Options"
   (gptel-workflow-transient--context-source-arg)
   (gptel-workflow-transient--integration-tests-arg)
   (gptel-workflow-transient--acs-arg)]
  ["Start Step"
   ("p" "Plan" gptel-workflow-transient-start-plan)
   ("d" "Diff" gptel-workflow-transient-start-diff)
   ("t" "Tests" gptel-workflow-transient-start-tests)
   ("r" "Review" gptel-workflow-transient-start-review)]
  ["Workflow"
   ("a" "Run All" gptel-workflow-transient-run-all)
   ("q" "Quit" transient-quit-one)])

(defun gptel-workflow-transient--parse-args (args)
  "Parse transient ARGS into workflow parameters."
  (let ((context-source 'region)
        (integration-tests nil)
        (acs nil))
    (dolist (arg args)
      (cond
       ((string-prefix-p "--context-source=" arg)
        (setq context-source
              (intern (substring arg (length "--context-source=")))))
       ((string= "--integration-tests" arg)
        (setq integration-tests t))
       ((string-prefix-p "--acs=" arg)
        (setq acs (split-string
                   (substring arg (length "--acs="))
                   "," t "[ \t\n]+")))))
    (list context-source acs integration-tests)))

(transient-define-suffix gptel-workflow-transient-start-plan (&optional args)
  "Start workflow at plan step."
  :transient nil
  (interactive (list (transient-args 'gptel-workflow-menu)))
  (cl-destructuring-bind (context-source acs integration-tests)
      (gptel-workflow-transient--parse-args args)
    (gptel-workflow-start context-source acs integration-tests)
    (gptel-workflow-run-plan)
    (gptel-workflow-step-menu)))

(transient-define-suffix gptel-workflow-transient-start-diff (&optional args)
  "Start workflow at diff step."
  :transient nil
  (interactive (list (transient-args 'gptel-workflow-menu)))
  (cl-destructuring-bind (context-source acs integration-tests)
      (gptel-workflow-transient--parse-args args)
    (gptel-workflow-start context-source acs integration-tests)
    (gptel-workflow-run-plan)
    (gptel-workflow-run-diff)
    (gptel-workflow-step-menu)))

(transient-define-suffix gptel-workflow-transient-start-tests (&optional args)
  "Start workflow at tests step."
  :transient nil
  (interactive (list (transient-args 'gptel-workflow-menu)))
  (cl-destructuring-bind (context-source acs integration-tests)
      (gptel-workflow-transient--parse-args args)
    (gptel-workflow-start context-source acs integration-tests)
    (gptel-workflow-run-plan)
    (gptel-workflow-run-diff)
    (gptel-workflow-run-tests)
    (gptel-workflow-step-menu)))

(transient-define-suffix gptel-workflow-transient-start-review (&optional args)
  "Start workflow at review step."
  :transient nil
  (interactive (list (transient-args 'gptel-workflow-menu)))
  (cl-destructuring-bind (context-source acs integration-tests)
      (gptel-workflow-transient--parse-args args)
    (gptel-workflow-start context-source acs integration-tests)
    (gptel-workflow-run-plan)
    (gptel-workflow-run-diff)
    (gptel-workflow-run-tests)
    (gptel-workflow-run-review)
    (gptel-workflow-step-menu)))

(transient-define-suffix gptel-workflow-transient-run-all (&optional args)
  "Run complete workflow."
  :transient nil
  (interactive (list (transient-args 'gptel-workflow-menu)))
  (cl-destructuring-bind (context-source acs integration-tests)
      (gptel-workflow-transient--parse-args args)
    (gptel-workflow-start context-source acs integration-tests)
    (gptel-workflow-run-all)))

;;; Per-Step Transient

(transient-define-prefix gptel-workflow-step-menu ()
  "Per-step workflow menu."
  ["Current Step Actions"
   ("n" "Next Step" gptel-workflow-transient-next-step)
   ("r" "Retry" gptel-workflow-transient-retry)
   ("e" "Edit ACs" gptel-workflow-transient-edit-acs)]
  ["Navigation"
   ("o" "Show Output" gptel-workflow-transient-show-output)
   ("l" "Show Log" gptel-workflow-transient-show-log)
   ("q" "Quit" transient-quit-one)])

(transient-define-suffix gptel-workflow-transient-next-step ()
  "Proceed to next workflow step."
  :transient t
  (interactive)
  (let ((state (gptel-workflow-get-state)))
    (unless state
      (error "No active workflow state"))
    (let ((current (gptel-workflow-state-current-step state)))
      (pcase current
        ('plan (gptel-workflow-run-diff))
        ('diff (gptel-workflow-run-tests))
        ((or 'tests 'tests-integration) (gptel-workflow-run-review))
        ('review (gptel-workflow-run-checklist))
        ('checklist (message "Workflow complete"))
        (_ (message "Unknown step: %s" current))))))

(transient-define-suffix gptel-workflow-transient-retry ()
  "Retry current step."
  :transient t
  (interactive)
  (gptel-workflow-retry-step))

(transient-define-suffix gptel-workflow-transient-edit-acs ()
  "Edit acceptance criteria."
  :transient t
  (interactive)
  (call-interactively #'gptel-workflow-set-acs))

(transient-define-suffix gptel-workflow-transient-show-output ()
  "Show workflow output buffer."
  :transient t
  (interactive)
  (display-buffer (get-buffer-create gptel-workflow-output-buffer-name)))

(transient-define-suffix gptel-workflow-transient-show-log ()
  "Show workflow log buffer."
  :transient t
  (interactive)
  (display-buffer (get-buffer-create gptel-workflow-log-buffer-name)))

(provide 'gptel-workflow-transient)
;;; gptel-workflow-transient.el ends here
