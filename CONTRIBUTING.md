# Contributing

Thanks for helping. This repo is a template: projects copy its **core** and keep their own
**overlay**. [TEMPLATE.md](TEMPLATE.md) says which files are which.

- **Core change** (skills, `_shared/`, gates, hooks, adapters): follow
  [TEMPLATE.md § Adding to core](TEMPLATE.md#adding-to-core). No product strings, a hook test or
  doc-budget check, and the same skill listed in each plugin manifest.
- **Docs:** a doc that describes a gate, hook, or script changes in the same branch, or the commit
  carries a `Docs-Unaffected:` trailer ([README § docs stay true](README.md)).
- **Before you push:** `pwsh ./scripts/ticket/Assert-AgenticFlow.ps1` prints `[PASS]`, and
  `node --test hooks/tests/*.test.js adapters/claude/hooks/tests/*.test.js` passes. CI runs the
  same checks on Linux and Windows.
- **Pull requests:** one concern per PR. Fill in the template.

Security reports go through [SECURITY.md](.github/SECURITY.md), not a public issue. By
contributing you agree your work is licensed under the [Apache License 2.0](LICENSE).
