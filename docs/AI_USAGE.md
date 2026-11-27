# AI usage

This repository was built with Claude Code (Anthropic) acting as an autonomous coding agent, following the rules in `CLAUDE.md` and the feature list in `SPECS.md`.

**What the AI did:** wrote the services, console, Helm chart, Terraform, scripts, docs and tests, and ran the stack to produce the proof.

**How the output was reviewed and tested**
- Every feature has a test that runs in CI or in `scripts/test-all.sh` (JUnit, WireMock, an HTTP integration test against the compose stack, Playwright, k6 thresholds).
- Behaviour claims in the docs are backed by captured artifacts in `proof/`: logs, JUnit XML, screenshots taken by a script, and CLI output from AWS (with account IDs redacted).
- Design choices that were not dictated by the specs are logged one per line in `docs/DECISIONS.md`.
- Nothing here was generated and left unrun: if a script or manifest is in the repo, it was executed at least once.
