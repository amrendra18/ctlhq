---
name: triage
description: "Use to sort one reported problem (an issue report, a bug thread, a user complaint) before anyone fixes it. Classifies it as bug, performance, feature request, question or feedback, or reroute; traces the likely owning layer; dedupes against the tracker; reproduces a bug twice on the current code with a receipt; files a ticket only for a clear new bug; replies once in the source thread with a verdict and a marker. Fails closed when the tracker or inputs are missing."
disable-model-invocation: true
---

# Triage

Classify one report and post one useful verdict in its source thread. Create a tracker issue only for a clear, new bug. Reproduce a bug here (step 5), and never fix it here; the **Bug fix** playbook of the **ctlhq-mode** skill does the fix.

The tracker is any issue system the run can search and write (Linear and GitHub Issues are examples). The thread is the place the report arrived (a chat thread, an issue, an email). Load the run's configuration first. It names the source thread, the tracker target fields, the marker strings, and an optional routing map. If any of it is missing, malformed, or uncertain, stop without posting or writing to the tracker.

## Hard rules

- Freeze the source coordinates (thread, channel, or issue id) before any work, and use only those for every later read and post. Never replace them with a reply id.
- Reply only inside the source thread. Never post a new top-level message, cross-post, or message someone directly.
- Check that the source thread still exists before any tracker write and again before the reply. If it is missing or uncertain, stop with no writes.
- Subagents are read-only on the thread and the tracker, return findings only, and never receive posting rights or credentials.
- Prefer no ticket over a guessed or duplicate ticket. Never create one that cannot link back to the source.
- Run the reply through the **unslop** skill.

## 1. Read the whole report

Read the root and every reply. Capture the reporter's wording, version and environment, expected and observed behavior, frequency and trigger, error text, linked issues, commits, or pull requests, and any statement that someone already owns the fix. Inspect every attachment (screenshots at full resolution, video for the state where correct and broken behavior split, logs for signatures). If an attachment cannot be read, say so in the verdict. Do not invent what it shows.

## 2. Trace the owning layer

Do a bounded source and history pass before choosing an owner. Use the **how** skill to trace the path from the reported action to the observed result. Use the **why** skill when it looks like a regression or touches defensive code. Check whether the symptom belongs to that path or a dependency below it, and whether a merged commit or open pull request already addresses it. Label hypotheses as hypotheses. If the repository cannot be read, do not guess an owner; classify conservatively and say tracing was unavailable.

## 3. Classify

Choose one:

1. **Bug.** Intended behavior is violated, such as wrong output, broken state, an error, a crash, a hang, a silent no-op, or a regression.
2. **Performance.** Measurable slowness, memory, battery, jank, or other resource cost. Treat it as a bug and keep the measurements.
3. **Feature request.** Current behavior looks intentional and the reporter wants something different.
4. **Question or feedback.** How something works, a preference, or general feedback with no concrete defect.
5. **Reroute.** Tracing shows another destination owns it. Tell the reporter where to go; do not cross-post.

When bug versus feature is unclear, file nothing. The verdict may ask one focused question under the `other` marker. Match a routing map only on a confirmed product area, code path, or error signature; a visible symptom alone is not enough. Owner pings are off unless the map names the owner and the configuration allows it.

## 4. Dedupe

First check whether this source is already linked to a tracker issue or a prior verdict. If so, stop. For a bug or performance report, search the tracker by error signature, product area, trigger, symptom, version or date window, suspected commit, and source link. Then pick one outcome:

1. **Confident duplicate** (same signature, same area, trigger, and symptom, or a confirmed shared cause). Add the source link and one recurrence note to that issue. Do not reopen, relabel, or reassign it unless the configuration says to.
2. **Possibly related.** Link it in the verdict as uncertain and create nothing.
3. **Weak resemblance** or **no match.** Go to step 5. A long-closed issue is a regression lead, not a live duplicate.

## 5. Reproduce on the current code

A reported defect is reproduced more than once on the current code before anyone changes code. Do this for a bug or performance report with a weak resemblance or no match in step 4. Drive the product with the report's version, setup, and steps, on a local or test build with test data only. Never use production or a user's real data; when only those show the defect, take outcome 3, say so, and the operator decides. Run it 2 times, each from a fresh start (a new launch or a reset state). Never force or inject the symptom. Save the receipt in the run's work folder, under a file-safe form of the source id (letters, digits, hyphens). The receipt holds the report version (or `unknown`), the current commit and build, the setup and steps, the expected result, and for each of the 2 runs the observed result with its screenshot or output path.

Then pick one outcome:

1. **Both runs show the defect.** It is live on the current code. The receipt goes into the issue (step 6).
2. **Both runs show the expected result.** The current code may already hold the fix. Name the fixing commit when tracing found it. The remaining work is a release or an explanation, so file nothing.
3. **Not reproduced** (the runs disagree, or cannot run: no access to a test build, missing test data, or only production shows it). The receipt gives the reason. The issue, when step 6 allows one, is marked "not reproduced".

## 6. Create only a clear new bug

Create an issue only when the class is bug or performance, the behavior is clearly broken and not known to be fixed on the current code (step 5), dedupe found no live match, the source check passed, the tracker fields resolved, and the run can cancel the issue if the reply fails. The issue holds a plain title naming area and symptom (no guessed cause), the reporter's quote, expected and observed behavior, version or `unknown`, trigger and frequency, the source link, labeled tracing findings, the reproduction receipt, and the attachments. Do not invent ids, labels, owners, or priority.

## 7. Reply exactly once

Check the source thread again, then post one reply in it. Lead with the outcome and the reproduction result (reproduced on <commit>, not reproduced, or already fixed), link the tracker issue when there is one, name a reroute or one missing fact when needed, and end with exactly one marker line from the configuration, for example `[triage:bug] tracker=<url>`, `[triage:performance]`, or `[triage:other]`. A later fix run trusts the marker only from the configured triage identity in this thread. Read the thread back and confirm the reply landed. If it did not, never retry at the top level; cancel any issue this run created and report the failure in the run output.

## 8. One follow-up window

Watch the thread for one configured window. Answer only a direct question to the triage identity, apply a concrete correction to the issue when safe, never emit a second marker, and stop when asked.
