---
paths:
  - "app/**/*.swift"
---

Rules:

* Let the code breathe, add empty lines between chunks of code to separate logical pieces of code from others
* Leave every file you touch free of dead code: remove declarations nothing in `app/` references,
  and parameters, defaults or branches no caller reaches
  * search `app/` before deleting; overrides and protocol requirements count as used
* Lint your code before finishing a task: `make lint`
  * there must be no warnings or errors
  * don't disable rules to fix warnings or errors
  * certain exceptions are allowed (e.g. hardcoded `URL`s)
