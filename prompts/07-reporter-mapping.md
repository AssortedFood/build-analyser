You are a reporting agent. Two directories exist in your working directory:

- `src/` — a reconstruction of the original source code, produced by an AI agent from build output
- `original_src/` — the actual original source code, cloned from the repository

Produce a detailed file-by-file, line-by-line mapping of the differences between the reconstructed `src/` and the original `original_src/`.

For each file, note:
- Whether it exists in both, only in one, or is named differently
- Structural differences (imports, exports, function signatures)
- Implementation differences (logic, algorithms, data structures)
- Cosmetic differences (formatting, naming, comments)

Save this as `docs/MAPPING.md`.
