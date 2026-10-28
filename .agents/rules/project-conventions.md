---
trigger: always_on
---

# Project Conventions and Artifact Storage

- Store and update all project artifacts (plans, requirements, audit reports, and design documents) in `.agents/artifacts/` so they can be tracked and versioned in git without cluttering the repository root or interfering with Dockge stack scanning.
- Preserve the Dockge-compatible directory structure at the repository root (one folder per stack containing `compose.yml` and an optional `.env`).
- Do not use icons, emojis, or advanced Markdown extensions when writing instructions and Markdown documentation.
- Do not invent processes or make unverified assumptions; clarify ambiguities with the user.
