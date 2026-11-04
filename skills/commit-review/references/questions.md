# Review questions

Every review answers each question, citing file and line. A question that does not apply gets "not applicable" and the reason.

1. **Correct.** How could this pass its tests while being broken for the operator? Which invariant in `AGENTS.md` could it break, and which test would catch that?
2. **Secure and private.** Does any path run untrusted input, write outside its folder, print a secret or a private value, or weaken an existing guard?
3. **Tests prove the claims.** Which "Done when" line or stated behaviour has no named test? Which negative claim ("never", "warns only", "refuses") has no test that shows the expected next to the observed?
4. **Smallest complete change.** What could the change leave out and still meet the requirement? Is any part a shortcut or a hack, or outside the asked scope?
5. **Every addition needed.** Which new file, function, option, or setting could the change drop, or replace by deleting something?
6. **Nothing duplicated.** Where does the change solve a problem the repository already solves, or solve one problem two ways?
7. **No added comments.** Which added comment could a name, type, assertion, or test replace?
8. **Deterministic logic in tools.** Which rule in skill or doc text could a script check or do instead?
9. **Neutral text.** Which tracked text, commit message or pull-request text would mean nothing to an outside reader, or reveals internal notes, status, dates of internal runs, or private names? A finding in a commit message or in pull-request text is "fix first", because the text outlives the commit. It cannot become a known limit.
