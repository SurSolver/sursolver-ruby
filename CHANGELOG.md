# Changelog

## 0.1.0 — unreleased

First release. Tested against the SDK specification revision in `SPEC_VERSION` (catalog of
2026-11-04).

- `SurSolver::Client` with `create_task`, `get_task_result`, `get_balance`, `list_task_types`,
  `list_services` and `solve` (3 s polling, 210 s deadline, `on_task_created:`).
- Typed errors: `AuthenticationError`, `InvalidTaskError` (with `supported_user_agents`),
  `InsufficientBalanceError`, `NoSlotAvailableError`, `TaskNotFoundError`, `TaskFailedError`,
  `ApiError`, `TransportError` (with `may_have_created_task?`), `ProtocolError`,
  `SolveTimeoutError`, `ConfigurationError`, all under `SurSolver::Error`.
- `SurSolver::TaskTypes` and `SurSolver::ErrorCodes` constants generated from the public catalog.
- Standard library only (`net/http`, `json`).
