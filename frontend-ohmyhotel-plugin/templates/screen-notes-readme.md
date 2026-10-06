# docs/screens — per-screen development notes

<!-- scaffolded by /frontend-ohmyhotel-plugin:fo-init — one file per spec unit, written by people as decisions land -->

One `<screen>.md` per spec unit (same id as `specs/<screen>/`). The spec is the requirement source; a note holds what
was decided **around** it: decisions applied (with the ADR), the V2 modules that carry the logic, backend requests,
exclusions, known conflicts. `fo-plan` hands the note to the planner as settled ground, so a decision recorded here is
not re-derived and not re-asked.

Suggested sections: What the screen is · Decisions applied · Sources (DS components, V2 hooks/modules, backend
request ids) · Known conflicts / open questions (link `docs/open-questions.md` rows).
