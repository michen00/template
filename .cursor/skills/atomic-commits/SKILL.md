---
name: atomic-commits
description: >-
  Analyzes current unstaged and staged work, groups changes
  by logical concern, plans a dependency-aware commit sequence,
  writes gitlint-compliant messages, and executes atomic commits
  that each leave the codebase in a good state.
---

# Atomic Commits

Bundle working-tree changes into a series of atomic,
self-consistent commits. Each commit addresses exactly one
logical concern and passes verification, so the history reads
as a clean narrative.

## When to Use

- Multiple unrelated changes accumulated in the working tree
  (feature + fix + docs, etc.)
- Generated/derived files changed alongside their source files
- Work spans several concerns and a single commit would
  conflate them
- You want a reviewable, bisectable history

## When to Keep It Simple

The full analysis/planning workflow is designed for
multi-concern situations. You can skip Steps 1–2 and just
commit directly (still following the message format) when:

- Only one logical change exists
- All changes are part of the same atomic concern
  (e.g., one bug fix touching three files)

The gitlint rules, message format, and verification steps
in this skill still apply — just skip the grouping and
sequencing overhead.

## Gitlint Rules (Source of Truth)

All commits must satisfy the project's `.gitlint`
configuration:

### Title Rules

| Rule          | Constraint                                    |
| ------------- | --------------------------------------------- |
| Format        | `<type>(<scope>): <subject>` (scope optional) |
| Length        | 5–50 characters (entire title line)           |
| Mood          | Imperative ("add", "fix" — not past tense)    |
| Allowed types | `feat`, `fix`, `chore`, `docs`, `style`, `ci` |
|               | `refactor`, `test`, `build`, `perf`, `revert` |

### Body Rules

| Rule        | Constraint                            |
| ----------- | ------------------------------------- |
| Presence    | Optional (body-is-missing is ignored) |
| Line length | 72 characters max per line            |
| Min length  | Ignored                               |

### Exemptions

| Pattern                  | Exempted rules   |
| ------------------------ | ---------------- |
| `chore: merge ...` title | body-is-missing, |
|                          | body-min-length, |
|                          | title-max-length |

## Workflow

### Step 1: Analyze Current Work

Inventory all changes and group them by logical concern.

**Commands to run:**

```bash
git status            # Modified, staged, and untracked files
git diff              # Unstaged changes
git diff --cached     # Staged changes
git log --oneline -5  # Recent commits for style reference
```

**Grouping criteria:**

- **By concern:** Feature code, bug fix, configuration,
  documentation, generated output, test
- **By coupling:** Files that must change together to keep the
  codebase consistent
- **By derivation:** Source files and their generated/derived
  outputs belong together

**Key rule:** Generated or derived files
(e.g., `.gitignore` from
`scripts/concat-gitignores.sh`) must be committed alongside
the source change that produced them — never in a separate
commit.

### Step 2: Plan Commit Sequence

Order commits so every intermediate state is self-consistent.

**Sequencing rules:**

1. Infrastructure/config changes first
   (build tools, linter config, dependencies)
2. Core logic changes next
   (library code, scripts, processing pipelines)
3. Features and fixes that depend on core changes
4. Generated/derived output alongside its source change
   (same commit)
5. Documentation and standalone cleanups last

**Dependency check:** For each planned commit, ask:
"If I checked out this commit alone, would the codebase build
and behave correctly?" If not, merge it with its dependency
or reorder.

**Present the plan to the user before executing.** List each
planned commit with:

- Proposed type and title
- Files included
- Rationale for grouping

### Step 3: Write Commit Messages

Follow gitlint rules exactly.

**Title formula:**

```text
<type>(<scope>): <subject>
```

Scope is optional. Subject should use imperative mood and
concise language.

**Constraints checklist:**

- Total title length: 5–50 characters
- Imperative mood: "add", "fix", "update", "remove",
  "refactor" (not "added", "fixes")
- No trailing period
- Lowercase after the colon

**Body guidelines:**

- Explain _why_, not _what_ (the diff shows what)
- Wrap at 72 characters
- Separate from title with a blank line
- Optional — omit for self-explanatory changes

**Footer:**

- Optionally include a co-author line
- Separate from body (or title if no body) with a blank line

**Message template:**

```text
<type>(<scope>): <subject>

<optional body explaining why>
```

Scope is optional; include it when it improves clarity.

### Step 4: Execute Commits

For each commit in the planned sequence:

1. Stage only the changes for this commit
   - **Whole files:** `git add <file1> <file2> ...`
   - **Mixed-concern files:** Prefer staging whole files when all
     hunks serve the same commit; otherwise defer the file to a
     later commit. If splitting is unavoidable, explain the
     conflict to the user and ask which concern the file should
     accompany — do not attempt interactive staging (agents cannot
     use `git add -p`).
2. Verify staging is correct (`git diff --cached --stat`)
3. Commit with the prepared message
4. Verify the commit succeeded (`git log --oneline -1`)

**Use specific file paths** — never `git add -A` or
`git add .` during atomic commits, as this defeats the
purpose of selective grouping.

**Never use `--no-verify`** to bypass failing hooks. Fix the
root cause instead.

**Handling files with mixed concerns:**

- When all hunks in a file serve the same commit, stage the
  whole file.
- When a file mixes unrelated concerns (e.g., typo fix +
  logic change), prefer committing one concern first and
  deferring the file until its other concern is ready, or
  explain the conflict to the user and ask which concern
  the file should accompany.
- When hunks are interleaved so tightly that splitting would
  leave an inconsistent intermediate state, commit the file
  as one unit under the dominant concern.

### Step 5: Verify Each Commit

After each commit, run relevant verification if applicable:

- **Code/config changes:** Run `make test` (not `make check` —
  `make check` runs formatting which can modify files mid-sequence)
- **Script changes:** Run the affected script
  to confirm it works
- **Commit-message linting:** `gitlint` runs via pre-commit
  on commit; run `gitlint` manually when needed

Run `make check` only after the entire commit sequence is
complete; commit any resulting formatting fixes as a separate
`style:` commit.

If verification fails, offer to restructure: unstage, regroup
files, and re-commit.

## Commit Message Examples

### Feature with generated output

```text
feat: regenerate consolidated gitignore

Upstream GitHub templates added new Python
and macOS patterns.
```

### Bug fix

```text
fix: correct glob pattern in script

The old pattern skipped nested matches in
some directories.
```

### Documentation only

```text
docs: update README installation section
```

### Configuration change

```text
chore: add gitlint config
```

### Refactoring

```text
refactor: simplify config parsing
```

### Build/tooling

```text
build: add nox session for coverage
```

### Scoped title example

```text
ci(lint): add workflow for code quality checks
```

## Common Patterns

### Pattern: Script change + regenerated output

**Commits:** 1 commit containing both the script and its
output.

```text
feat: regenerate consolidated gitignore
```

Files: `scripts/concat-gitignores.sh`,
`.gitignore`

### Pattern: Feature + related documentation

**Commits:** 2 commits — feature first, then docs.

1. `feat: add retry logic to core module` — code files
2. `docs: document retry configuration` — markdown files

### Pattern: Bug fix + verification script

**Commits:** 1 commit if the script is needed to verify the
fix; 2 if the script is independently useful.

### Pattern: Config + code that uses it

**Commits:** 1 commit — config and code together so neither
commit is broken in isolation.

### Pattern: Multiple independent fixes

**Commits:** 1 commit per fix, ordered by dependency
(or alphabetically if independent).

### Pattern: One file, multiple concerns

**Commits:** Stage whole files when hunks share a concern;
otherwise commit one concern first and defer the file, or ask
the user which concern the file should accompany.

Example: `CLAUDE.md` has both a prefix list update and
a new guide reference added — two unrelated concerns.

1. `build: bump hook versions` — if the version-bump hunks
   can be isolated, stage that file and commit; else ask user
2. `ci: add yaml lint hook` — remaining changes in a
   follow-up commit

### Pattern: Partially complete work

If work is incomplete and you still need to commit:

- Commit the complete portions as proper atomic commits
- Leave incomplete work uncommitted, or commit on a feature
  branch with `chore(wip): checkpoint <description>`
- Never mix complete and incomplete work in one commit

## Quality Checklist

Before executing the commit sequence:

- [ ] Each commit addresses exactly one logical concern
- [ ] Generated files are paired with their source changes
- [ ] No commit leaves the codebase in a broken state
- [ ] Commit sequence respects dependency order
- [ ] All titles are 5–50 characters, imperative mood
- [ ] All titles follow `<type>(<scope>): <subject>` format (scope optional)
- [ ] Body lines wrap at 72 characters (if body present)
- [ ] No sensitive files (.env, credentials) are staged
- [ ] `git add` uses specific file paths, not `-A` or `.`

After executing:

- [ ] `git log --oneline` shows clean, readable history
- [ ] Each commit message accurately describes its changes
- [ ] Verification passed for commits touching scripts/builds
