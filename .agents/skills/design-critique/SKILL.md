---
name: design-critique
description: Produce a grounded UX/UI design critique of an app by reading its actual UI surfaces (views, styles, copy) rather than guessing. Use when the user asks for a design review, UX critique, UI feedback, "what's wrong with the design", or wants a prioritized list of interface improvements for a GUI/TUI/web app in the current codebase.
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash(ls *)
  - Bash(rg *)
  - Agent
---

# /design-critique — grounded UX/UI design critique

Produce a design critique that an engineer can act on, anchored in the
**actual interface code**, not in assumptions about what the app probably
looks like. Every claim cites a real file, value, or string.

## The one rule

**Never critique from memory or from the README alone.** Read the views,
the style/theme tokens, the copy strings, and the interaction handlers
first. A critique that says "the buttons are probably too small" is
worthless; "the footer hint is `overlay0` (#6c7086) on `mantle` at 9pt ≈
3:1 contrast — below WCAG 4.5:1" is actionable. If you haven't found the
number in the code, don't assert it.

## Procedure

### 1. Map the surfaces
Identify every user-facing surface and the files that define each one.
For a big codebase, dispatch an `Explore` agent to survey them in parallel;
otherwise read directly. You want, per surface:
- **Layout & visual:** dimensions, corner radii, padding/insets, colors
  (resolve to hex via the theme tokens), opacity/blur, typography sizes &
  weights, window/positioning.
- **Invocation & dismissal:** how it opens, how it closes, focus behavior.
- **Interaction model:** input handling, selection, navigation, confirm,
  fuzzy match, validation, failure paths.
- **Motion:** any animations/transitions (and conspicuous absence of them).
- **Copy:** every label, placeholder, hint, empty state, error string —
  quoted verbatim.

### 2. Judge against real heuristics
Hold what you found against concrete standards, not vibes:
- **Consistency** — do surfaces that look alike behave alike? Shared tokens
  or divergent magic numbers? (Visual sameness implying behavioral sameness
  is a classic learnability trap.)
- **Feedback** — does every action confirm success *and* failure? Silent
  failure (a no-op the user can't distinguish from success) is a P0.
- **Contrast & legibility** — compute fg/bg contrast for text; flag < 4.5:1
  for body/small text. Flag near-invisible opacities, tiny font sizes,
  translucency-without-blur (color bleed).
- **Copy honesty** — do labels name what the thing actually does, in the
  user's vocabulary? Flag implementer-model naming, duplicated hints,
  inconsistent voice/register.
- **Scaling** — fixed sizes that ignore display dimensions; absolute insets.
- **Discoverability & dead ends** — can the user reach everything? Are there
  unreachable states or modes?
- **Accessibility** — color-only signaling, no VoiceOver/AX labels,
  keyboard-only or mouse-only traps.
- **Motion** — jarring instant appearance of modals; missing transitions.

### 3. Lead with a verdict
Open with 2–4 sentences: the design's central thesis, whether execution
serves it, the single best decision, and the single weakest area. Be
opinionated. A critique with no point of view is a feature list.

### 4. Strengths, then issues by category
- **What works** — name the genuinely good calls (and why they're good), so
  the critique is calibrated, not just a complaint list.
- **UX issues** (interaction model) and **UI issues** (visual), each as
  concrete, numbered findings with file:line refs and quoted values.

### 5. Prioritized punch list
End with a table: **Priority | Fix | Why**. Use P0–P3.
- **P0** — breaks trust or correctness (silent failure, illegible critical
  text). 
- **P1** — actively misleads or causes friction (wrong labels, the biggest
  visual defect, learnability traps).
- **P2** — polish that noticeably raises quality (motion, scaling).
- **P3** — nice-to-have consistency.
Scale scope to the request: a quick gut-check gets a handful of findings; an
"audit" or "be thorough" gets full coverage across every surface.

## Output shape
1. Overall read (verdict)
2. What works
3. UX issues
4. UI issues
5. (if relevant) Cross-cutting: voice, color semantics, empty states
6. Prioritized punch list (P0–P3 table)
7. One-line offer to mock up a before/after of the top fix, if useful.

## Tone
Direct, specific, and fair. Praise what's earned, name what's broken, and
make every criticism land on a line of code or a measured value — never a
hunch. The deliverable is a critique someone can turn into commits.
