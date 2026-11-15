> This file extends [common/patterns.md](../common/patterns.md) with web-specific design-quality guidance.

# Web Design Quality Standards

## Anti-Template Policy

Do not ship generic template-looking UI. Frontend output should look intentional, opinionated, and specific to the product.

### Banned Patterns

- Default card grids with uniform spacing and no hierarchy
- Stock hero section with centered headline, gradient blob, and generic CTA
- Unmodified library defaults passed off as finished design
- Flat layouts with no layering, depth, or motion
- Uniform radius, spacing, and shadows across every component
- Safe gray-on-white styling with one decorative accent color
- Dashboard-by-numbers layouts with sidebar + cards + charts and no point of view
- Default font stacks used without a deliberate reason

### Required Qualities

Every meaningful frontend surface should demonstrate at least four of these:

1. Clear hierarchy through scale contrast
2. Intentional rhythm in spacing, not uniform padding everywhere
3. Depth or layering through overlap, shadows, surfaces, or motion
4. Typography with character and a real pairing strategy
5. Color used semantically, not just decoratively
6. Hover, focus, and active states that feel designed
7. Grid-breaking editorial or bento composition where appropriate
8. Texture, grain, or atmosphere when it fits the visual direction
9. Motion that clarifies flow instead of distracting from it
10. Data visualization treated as part of the design system, not an afterthought

## Design Skill

Use `/impeccable` as the default skill for all frontend design work.

- First time on a project: run `/impeccable init` to write `PRODUCT.md` (who it is for, what it must do). `teach` is an alias.
- Existing visual system: run `/impeccable document` to capture it in `DESIGN.md`.
- Building UI: describe the surface (or `/impeccable shape`); `craft` is a deprecated alias.
- Before calling a screen done: `/impeccable critique <target>` and `/impeccable audit <target>`, then `/impeccable polish <target>`.
- Look at the rendered result (screenshot) at the sizes it ships at. Rules alone do not catch an AI-looking screen.

Do not skip `init` — design without project context produces generic output.
Projects that still have only a legacy `.impeccable.md` (impeccable 2.x): run `/impeccable init`; 4.x reads `PRODUCT.md` and `DESIGN.md`, not `.impeccable.md`.

## Before Writing Frontend Code

1. Confirm design context exists (`PRODUCT.md` / `DESIGN.md`, or loaded instructions). If not, run `/impeccable init` first.
2. Pick a specific style direction. Avoid vague defaults like "clean minimal".
3. Define a palette intentionally.
4. Choose typography deliberately.
5. Gather at least a small set of real references.

## Worthwhile Style Directions

- Editorial / magazine
- Neo-brutalism
- Glassmorphism with real depth
- Dark luxury or light luxury with disciplined contrast
- Bento layouts
- Scrollytelling
- 3D integration
- Swiss / International
- Retro-futurism

Do not default to dark mode automatically. Choose the visual direction the product actually wants.

## Component Checklist

- [ ] Does it avoid looking like a default Tailwind or shadcn template?
- [ ] Does it have intentional hover/focus/active states?
- [ ] Does it use hierarchy rather than uniform emphasis?
- [ ] Would this look believable in a real product screenshot?
- [ ] If it supports both themes, do both light and dark feel intentional?
