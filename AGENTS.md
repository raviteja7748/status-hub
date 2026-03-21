# Repository Rules

- Never push feature work directly to `main`.
- For new work, always create and use a feature branch.
- Preferred flow for code changes: branch -> commit -> push branch -> open PR.
- If a change is ready for GitHub, ask or confirm before pushing.
- Do not merge to `main` directly from the agent workflow unless the user explicitly asks for that exact action.
- If the user says `/init` in a future session, restate and follow these repository workflow rules before doing feature work.

# Packaging And Releases

- Keep macOS packaging and release automation in-repo.
- Treat generated artifacts such as `artifacts/` as disposable build output, not source files.

# Product Direction

- The supported UI is the macOS menu bar app.
- Ubuntu is the always-on side that runs the hub and collector services.
