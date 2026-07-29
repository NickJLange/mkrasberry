# Engineering Preferences and Review Guidelines

Review this plan thoroughly before making any code changes. For every issue or recommendation, explain the concrete tradeoffs, give me an opinionated recommendation, and ask for my input before assuming a direction.

## Engineering Preferences

These preferences guide all recommendations and implementations:

* **DRY is about knowledge, not just text** - Flag logic duplication aggressively, but tolerate structural duplication if sharing it creates premature coupling (WET is better than the wrong abstraction).
* **Well-tested code is non-negotiable** - Test behavior, not implementation details. I prefer redundant coverage over missing edge cases, but ensure tests are resilient to refactoring.
* **Target "Engineered Enough"** - Handle current requirements + immediate edge cases. **Apply YAGNI**: do not build for hypothetical future use cases. Abstract only when you see the pattern for the third time (Rule of Three).
* **Err on the side of handling more edge cases, not fewer** - thoughtfulness > speed.
* **Bias toward explicit over clever.**

---

## Review Framework

### 1. Architecture review
Evaluate:
* Overall system design and component boundaries.
* Dependency graph and coupling concerns.
* Data flow patterns and potential bottlenecks.
* Scaling characteristics and single points of failure.
* Security architecture (auth, data access, API boundaries).

### 2. Code quality review
Evaluate:
* Code organization and module structure.
* DRY violations - be aggressive here.
* Error handling patterns and missing edge cases (call these out explicitly).
* Technical debt hotspots.
* Areas that are over-engineered or under-engineered relative to my preferences.

### 3. Test review
Evaluate:
* Test coverage gaps (unit, integration, e2e).
* Test quality and assertion strength.
* Missing edge case coverage - be thorough.
* Untested failure modes and error paths.

### 4. Performance review
Evaluate:
* N+1 queries and database access patterns.
* Memory-usage concerns.
* Caching opportunities.
* Slow or high-complexity code paths.

---

## Issue and Option Format

For every specific issue (bug, smell, design concern, or risk):

1. **Describe the problem concretely**, with file and line references.
2. **Present 2-3 options**, including "do nothing" where that's reasonable.
3. **For each option**, specify: implementation effort, risk, impact on other code, and maintenance burden.
4. **Give me your recommended option and why**, mapped to my preferences above.
5. **Then explicitly ask whether I agree or want to choose a different direction before proceeding.**

---

## Workflow and Interaction

* **Do not assume my priorities on timeline or scale.**
* **After each section, pause and ask for my feedback before moving on.**

### BEFORE YOU START:
Ask if I want one of two options:
1. **BIG CHANGE**: Work through this interactively, one section at a time (Architecture → Code Quality → Tests → Performance) with at most 4 top issues in each section.
2. **SMALL CHANGE**: Work through interactively ONE question per review section.

### FOR EACH STAGE OF REVIEW:
* Output the explanation and pros and cons of each stage's questions.
* Provide your opinionated recommendation and why.
* Use `AskUserQuestion` (or equivalent tool) to get confirmation.
* **NUMBER issues** (1, 2, 3...) and then give **LETTERS for options** (A, B, C...).
* When asking for selection, make sure each option clearly labels the issue NUMBER and option LETTER.
* **The recommended option must always be the 1st option.**
