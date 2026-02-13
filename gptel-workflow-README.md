# gptel-workflow

Chained LLM workflow orchestration for gptel.

## Overview

`gptel-workflow` provides a structured workflow system for gptel that chains together multiple LLM interactions: plan → diff → tests → review → refine. It includes model presets, validation gates, acceptance criteria tracking, and a transient-based UI.

## Features

### 1. Model Presets and Routing

Three predefined presets with automatic step-to-preset routing:

- **fast-low**: Fast model (gpt-4o-mini) with low temperature (0.3) - used for summarization
- **strong-medium**: Strong model (gpt-4o) with medium temperature (0.5) - used for planning
- **strong-low**: Strong model (gpt-4o) with low temperature (0.3) - used for diff/tests/review

Default routing:
- `plan` → strong-medium
- `diff`, `tests`, `review` → strong-low
- `summarize` → fast-low

### 2. Workflow State Management

The workflow maintains state through a `gptel-workflow-state` struct:

```elisp
(cl-defstruct gptel-workflow-state
  current-step        ; Current step symbol (plan, diff, tests, review, etc.)
  acs                 ; List of acceptance criteria
  context-raw         ; Raw captured context
  context-summary     ; Optional summarized context
  plan                ; Generated plan output
  diff                ; Generated diff output
  tests               ; Generated tests output
  review              ; Generated review output
  refine              ; Generated refine output
  continue-flag       ; Whether to continue automatically
  integration-tests-p ; Whether to include integration tests
  retry-count         ; Number of retries for current step
  last-error)         ; Last error message
```

### 3. Acceptance Criteria (AC) Handling

- **Input**: Accept ACs as a list of strings
- **Auto-tagging**: Automatically tags as AC1, AC2, AC3, etc.
- **Propagation**: ACs are included in all step prompts
- **Citation tracking**: Validates that outputs cite AC IDs

Example:
```elisp
(gptel-workflow-start 'region '("Feature works correctly" "Tests pass") nil)
;; ACs become: "AC1: Feature works correctly", "AC2: Tests pass"
```

### 4. Context Capture and Hygiene

**Capture methods:**
- `region`: Capture selected region
- `defun`: Capture current function/defun

**Context pruning:**
- Removes excessive blank lines (>2 consecutive)
- Truncates very long lines (>500 chars)
- Optional summarization for contexts exceeding threshold (2000 chars)

### 5. Workflow Steps

Available step runners:

- `gptel-workflow-run-plan`: Generate implementation plan
- `gptel-workflow-run-diff`: Generate unified diff
- `gptel-workflow-run-tests`: Generate unit tests
- `gptel-workflow-run-review`: Review implementation
- `gptel-workflow-run-checklist`: Generate verification checklist

Integration tests variant:
- Set `integration-tests-p` flag to generate integration tests

### 6. Validation Gates

Each step includes validation:

**Plan validation:**
- ✓ Has bullet points or numbered items
- ✓ Cites AC tags (when ACs present)

**Diff validation:**
- ✓ Non-empty unified diff format
- ✓ Cites AC tags (when ACs present)

**Tests validation:**
- ✓ References test paths (test/, tests/, *-test.el, etc.)
- ✓ Cites AC tags (when ACs present)

**Review validation:**
- ✓ Has bullet points or numbered items

Validation results include:
- `:valid` - Boolean success flag
- `:message` - Human-readable result message
- Additional step-specific flags (`:has-bullets`, `:has-diff`, etc.)

### 7. Retry Support

When validation fails or output is unsatisfactory:

```elisp
(gptel-workflow-retry-step)
```

- Increments retry counter
- Re-executes current step
- Can use alternate presets or stricter prompts

### 8. Transient UI

**Entry transient** (`gptel-workflow-menu`):
- Select context source (region/defun)
- Toggle integration tests
- Enter acceptance criteria
- Choose starting step
- Run complete workflow

**Per-step transient** (`gptel-workflow-step-menu`):
- Proceed to next step
- Retry current step
- Edit acceptance criteria
- Show output buffer
- Show log buffer

### 9. Logging and Observability

All workflow actions logged to `*gptel-workflow-log*`:

```
[2025-01-15 10:30:45] Step: plan | Preset: strong-medium | Variant: default | Result: success
[2025-01-15 10:31:12] Step: diff | Preset: strong-low | Variant: default
```

Output collated in `*gptel-workflow-output*`:

```
=== Plan ===
[plan content]
Validation: Plan validation passed
AC Tags cited: AC1, AC2

=== Diff ===
[diff content]
Validation: Diff validation passed
```

## Installation

1. Ensure gptel is installed and configured
2. Load the workflow modules:

```elisp
(require 'gptel-workflow)
(require 'gptel-workflow-transient)
```

## Usage

### Interactive Usage

1. **Start workflow:**
   ```
   M-x gptel-workflow-menu
   ```

2. **Configure options:**
   - `-c` Context source (region/defun)
   - `-i` Integration tests toggle
   - `-a` Acceptance criteria

3. **Select action:**
   - `p` Start at plan step
   - `d` Start at diff step
   - `t` Start at tests step
   - `r` Start at review step
   - `a` Run all steps

4. **Per-step actions:**
   - `n` Next step
   - `r` Retry
   - `e` Edit ACs
   - `o` Show output
   - `l` Show log

### Programmatic Usage

```elisp
;; Initialize workflow
(gptel-workflow-start 'region '("Feature works" "Tests pass") nil)

;; Run steps
(gptel-workflow-run-plan)
(gptel-workflow-run-diff)
(gptel-workflow-run-tests)
(gptel-workflow-run-review)
(gptel-workflow-run-checklist)

;; Or run all at once
(gptel-workflow-run-all)

;; Access state
(let ((state (gptel-workflow-get-state)))
  (gptel-workflow-state-plan state))

;; Modify ACs
(gptel-workflow-set-acs '("New AC1" "New AC2"))

;; Retry if needed
(gptel-workflow-retry-step)
```

## Testing

The package includes comprehensive ERT tests in `tests/gptel-workflow-test.el`.

### Running Tests

```bash
emacs --batch -L . -l tests/gptel-workflow-test.el -f ert-run-tests-batch-and-exit
```

Or from within Emacs:

```elisp
(require 'gptel-workflow-test)
(ert-run-tests-interactively t)
```

### Test Coverage

- ✓ State creation and modification
- ✓ AC tagging and extraction
- ✓ Context pruning
- ✓ Validation gates (all steps)
- ✓ Prompt building
- ✓ State progression
- ✓ Retry mechanisms
- ✓ Integration test flags
- ✓ Output formatting
- ✓ Logging
- ✓ Preset configuration
- ✓ Edge cases

## Customization

### Variables

```elisp
;; Log buffer name
(setq gptel-workflow-log-buffer-name "*my-workflow-log*")

;; Output buffer name
(setq gptel-workflow-output-buffer-name "*my-workflow-output*")

;; Test path patterns
(setq gptel-workflow-default-test-paths '("test/" "spec/" "*_spec.rb"))

;; File glob patterns
(setq gptel-workflow-default-file-globs '("*.el" "*.py" "*.rb"))

;; Summarization threshold (chars)
(setq gptel-workflow-summarization-threshold 3000)
```

### Custom Presets

Modify `gptel-workflow-presets` to add custom presets:

```elisp
(add-to-list 'gptel-workflow-presets
  '(ultra-fast
    :description "Ultra fast for quick tasks"
    :model "gpt-3.5-turbo"
    :temperature 0.7
    :max-tokens 1000))
```

### Custom Step Routing

Modify `gptel-workflow-step-preset-map`:

```elisp
(setf (alist-get 'plan gptel-workflow-step-preset-map) 'ultra-fast)
```

### Custom Validators

Add custom validation for steps:

```elisp
(defun my-custom-validator (output)
  "Custom validation logic."
  (list :valid (string-match-p "pattern" output)
        :message "Custom validation message"))

(setf (alist-get 'my-step gptel-workflow-validators)
      #'my-custom-validator)
```

## Architecture

### Core Modules

- **gptel-workflow.el**: Core workflow orchestration
  - State management
  - Step execution
  - Validation gates
  - Context management
  - AC handling

- **gptel-workflow-transient.el**: Transient UI
  - Entry menu
  - Per-step menu
  - Argument parsing

- **tests/gptel-workflow-test.el**: ERT test suite
  - Unit tests
  - Integration tests
  - Edge cases

### Data Flow

```
1. User starts workflow → Context captured
2. State initialized with ACs and context
3. Step executed:
   - Build prompt (include ACs, context, previous outputs)
   - Execute with appropriate preset
   - Log execution
4. Validate output
5. Display results
6. User proceeds/retries/edits
7. Repeat for next step
```

### Extension Points

1. **Custom steps**: Define new workflow steps
2. **Custom validators**: Add validation logic
3. **Custom presets**: Define model configurations
4. **Custom context capture**: Implement new capture methods
5. **Custom prompts**: Override prompt building

## Examples

### Example 1: Feature Development Workflow

```elisp
;; Select code region, then:
(gptel-workflow-start 'region 
  '("Add caching" "Maintain backward compatibility" "Add tests")
  nil)

(gptel-workflow-run-all)
```

### Example 2: Code Review Workflow

```elisp
;; Review a defun:
(gptel-workflow-start 'defun
  '("Security checked" "Performance optimized")
  nil)

(gptel-workflow-run-review)
```

### Example 3: Test Generation Workflow

```elisp
;; Generate integration tests:
(gptel-workflow-start 'region
  '("Cover edge cases" "Test error handling")
  t)  ; Enable integration tests

(gptel-workflow-run-plan)
(gptel-workflow-run-diff)
(gptel-workflow-run-tests)  ; Will generate integration tests
```

## Troubleshooting

### Issue: Steps fail without active state

**Solution**: Ensure `gptel-workflow-start` is called first:
```elisp
(gptel-workflow-start 'region nil nil)
```

### Issue: Validation always fails

**Solution**: Check validation patterns match your output format. Customize:
```elisp
(setq gptel-workflow-default-test-paths '("your-test-dir/"))
```

### Issue: Context too large

**Solution**: Use summarization or reduce region size:
```elisp
(setq gptel-workflow-summarization-threshold 1500)
```

### Issue: Wrong model used

**Solution**: Check preset mapping:
```elisp
(alist-get 'plan gptel-workflow-step-preset-map)
```

## Contributing

Contributions welcome! Areas for enhancement:

1. **Async execution**: Full gptel-request integration
2. **More validators**: Additional validation patterns
3. **Context strategies**: Smarter context selection/pruning
4. **Preset templates**: Common preset configurations
5. **Step templates**: Reusable step definitions

## License

GPL-3.0-or-later

## See Also

- [gptel](https://github.com/karthink/gptel) - Main LLM client
- [transient](https://github.com/magit/transient) - Command interface
