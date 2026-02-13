# gptel-workflow

A standalone workflow dispatcher for orchestrating chained, validated LLM workflows with gptel.

## Overview

`gptel-workflow` provides a comprehensive system for managing multi-step LLM workflows with validation, acceptance criteria tracking, and a transient UI. The workflow follows this pattern:

**plan → diff → tests → review → checklist**

## Features

### Core Capabilities

- **Standalone operation**: Works with or without gptel installed
- **Backend abstraction**: Pluggable LLM backend with auto-detection of gptel
- **Named presets**: Fast-low, strong-medium, and strong-low configurations
- **Workflow state management**: Tracks all steps and maintains context hygiene
- **Acceptance criteria (AC) handling**: Tag, propagate, and validate ACs throughout the workflow
- **Validation gates**: Each step includes validation with human override options
- **Transient UI**: Rich interactive menu for workflow management
- **Comprehensive logging**: Full observability of workflow execution

### Step Runners

1. **Plan**: Generate implementation plan based on context and ACs
2. **Diff**: Create unified diff showing required changes
3. **Tests**: Generate unit or integration tests
4. **Review**: Review implementation for risks and alternatives
5. **Checklist**: Create final verification checklist

Each step:
- Uses appropriate preset (configurable)
- Validates output format and AC citations
- Supports retry with alternate presets
- Logs execution details

### Validation Gates

Each step has specific validation requirements:

- **Plan**: Must contain bullets/numbered list and cite all ACs
- **Diff**: Must be valid unified diff format with AC citations
- **Tests**: Must touch test paths when behavior changes
- **Review**: Must contain bullets mentioning risks/concerns

Failed validations can be overridden by the user.

## Installation

Add `gptel-workflow.el` and `gptel-workflow-transient.el` to your load path:

```elisp
(add-to-list 'load-path "/path/to/gptel")
(require 'gptel-workflow)
(require 'gptel-workflow-transient)
```

## Usage

### Interactive Workflow

Start the workflow menu:

```elisp
M-x gptel-workflow-menu
```

This opens a transient menu where you can:
- Select context source (region/defun/buffer)
- Enter acceptance criteria
- Choose preset overrides
- Execute workflow steps
- View output and logs

### Programmatic Usage

Create and run a workflow programmatically:

```elisp
;; Create a new workflow
(let ((state (gptel-workflow-state-create
              :context "code context here"
              :acs '("AC1: First requirement"
                     "AC2: Second requirement"))))
  
  ;; Run plan step
  (gptel-workflow-plan state)
  
  ;; After async completion, run diff
  (gptel-workflow-diff state)
  
  ;; Continue with other steps
  (gptel-workflow-tests state)
  (gptel-workflow-review state)
  (gptel-workflow-checklist state))
```

### Custom Backend

Provide a custom LLM backend:

```elisp
(setq gptel-workflow-backend-function
      (lambda (request-plist)
        (let ((prompt (plist-get request-plist :prompt))
              (callback (plist-get request-plist :callback)))
          ;; Send request to your LLM service
          ;; Call callback with (response info) when complete
          )))
```

## Configuration

### Presets

Customize the available presets:

```elisp
(setq gptel-workflow-presets
      '((fast-low
         :description "Fast responses with low cost"
         :model "gpt-3.5-turbo"
         :temperature 0.3
         :max-tokens 2000)
        (strong-medium
         :description "Strong model with medium length"
         :model "gpt-4"
         :temperature 0.5
         :max-tokens 4000)
        (strong-low
         :description "Strong model with low cost"
         :model "gpt-4"
         :temperature 0.3
         :max-tokens 2000)))
```

### Step Routing

Configure which preset each step uses:

```elisp
(setq gptel-workflow-step-presets
      '((plan . strong-medium)
        (diff . strong-low)
        (tests . strong-low)
        (review . strong-low)
        (checklist . fast-low)))
```

### Path Validation

Configure allowed file paths and test patterns:

```elisp
(setq gptel-workflow-allowed-paths
      '("*.el" "*.py" "*.js" "*.ts"))

(setq gptel-workflow-test-path-patterns
      '("test-*.el" "*-test.el" "test/*.el"))
```

## Public API

### State Management

- `gptel-workflow-state-create`: Create a new workflow state
- `gptel-workflow-get-state`: Get current workflow state
- `gptel-workflow-set-state`: Set current workflow state

### Step Commands

- `gptel-workflow-plan`: Execute plan step
- `gptel-workflow-diff`: Execute diff step
- `gptel-workflow-tests`: Execute tests step
- `gptel-workflow-review`: Execute review step
- `gptel-workflow-checklist`: Execute checklist step

### Utility Commands

- `gptel-workflow-new`: Start new workflow interactively
- `gptel-workflow-show-output`: Display workflow output buffer
- `gptel-workflow-show-log`: Display workflow log buffer

## Testing

Run the comprehensive test suite:

```bash
emacs -batch -L . -l test/gptel-workflow-test.el -f ert-run-tests-batch-and-exit
```

Tests cover:
- State management and progression
- Backend abstraction (with mock backend)
- Context capture and pruning
- AC tagging and validation
- All validation gates
- Prompt generation
- Logging and output
- Error handling
- Integration scenarios

## Architecture

### Backend Abstraction

The system supports three backend modes:

1. **gptel**: Auto-detected when available, uses `gptel-request`
2. **Custom**: User-provided backend function via `gptel-workflow-backend-function`
3. **Mock**: Built-in mock backend for testing without network

### State Structure

Workflow state is managed through a `cl-defstruct`:

```elisp
(cl-defstruct gptel-workflow-state
  step                    ; Current step symbol
  acs                     ; Acceptance criteria list
  context                 ; Raw context string
  context-summary         ; Optional summary
  plan                    ; Plan output
  diff                    ; Diff output
  tests                   ; Tests output
  tests-integration       ; Integration tests output
  review                  ; Review output
  checklist               ; Checklist output
  continue-flag           ; Continue to next step?
  integration-test-flag   ; Run integration tests?
  preset-override         ; Override preset
  validation-results      ; Validation results
  log-entries)            ; Log entries
```

### Context Hygiene

Large contexts are automatically pruned to stay under `gptel-workflow-context-max-chars` (default 50000). Optional summarization before plan step via `gptel-workflow-summarize-before-plan`.

## Non-Goals

- **No automatic patch application**: Users apply diffs manually
- **No hard gptel dependency**: Works standalone with pluggable backend
- **No network in tests**: All tests use mock backend

## License

GPL-3.0-or-later

## Contributing

This module is part of gptel. See the main gptel repository for contribution guidelines.
