# Building principles

## About this file

This file holds the building principles behind ctlhq. They explain why its skills and
tools work the way they do. In this file, the operator is the person who directs the
agents. The operator gives them tasks, approves plans, and accepts results.

The people who change ctlhq, and the main agent that does that work for them, read this
file when they change ctlhq. An agent doing a task does not read it; it uses the skills and
tools built from it. An agent meets this direction through `/ctlhq-mode`, the working
contract, which carries it to agents through skills: the `principle-*` skills hold the
coding principles, and this file holds the building principles. Where a coding principle
says the same thing as this file, this file holds the reason and the skill holds the rule.
This file is not one of the five layers that prevent mistakes (principle 6); it directs the
building of those layers. Each decision in ctlhq traces to a building principle in this
file. Every directional rule for ctlhq lives here and nowhere else. This file holds no work
items and no status.

## Core motivation

Build an environment where agents do good work, check it, and improve it without the human
carrying information between steps. The goal is a product its users like: one that works,
responds, and feels considered, at any number of changes or agents. Craft and user
experience stay central. More changes, more code, and more agents do not make a better
product.

Trust grows from three sources: evidence from verification, skills and tools that teach
agents to work like good engineers, and constraints built into the code. Verification shows
what happened. Structure limits which mistakes are possible. Neither replaces the other.

The far end is an agent that merges its own verified code while the operator sleeps, and an
operator who is free to step away. The phase with a few agents is the hardest to leave,
because the way out is unclear and there is no shortcut. That end is reached inside the
boundaries at the end of this file, by environment work and by the operator's deliberate
decision to let go. No setting turns it on. The operator stays responsible for the product
and for the environment that shapes it.

The work inside every repository is built for agents first: its code, files, structure,
checks, and tools fit how agents work, not how people work. The human writes no code and
does no repository work. The human gives goals, approvals, and judgment calls, which the
environment keeps rare, and an agent records each one in the file where it belongs. Agents
first never applies to what reaches the human. Every report, question, and request for a
decision is written for the human: plain, complete, and quick to act on. The environment
exists to make both jobs easy. The agent writes code, shapes files and structure, and runs
checks with the least friction. The human makes each call with the least effort.

An environment is dependable when it shows seven qualities:

1. Self-sufficient: the agent gets facts and runs checks without a human copying anything.
2. Observable: a result shows the actions, the outcomes, the measurements, and the missing
   coverage.
3. Repeatable: a fresh agent reaches the same feature with the same maintained tools.
4. Constrained: a known forbidden pattern is rejected by structure or by a check.
5. Isolated: parallel workers have separate outputs and separate live sessions.
6. Maintained: maps, tools, and skills change when a real failure shows a gap.
7. Accountable: one owner checks the combined result and keeps the human decisions.

## Building principles

1. **Remove the human as the relay.** Each time the operator fetches a fact, runs a tool, or
   repeats a correction for the agent, a tool, check, or source is missing. The agent finds
   facts itself and asks the operator only for decisions. The operator's standing questions
   are "where am I the bottleneck?" and "why does the agent need me here?".

   - **1.1. Reply so the operator acts at once.** The operator's attention is the
     scarcest resource. Lead with the answer, give exact numbers, explain each label, number
     each list, and end with the next step and who takes it. A reply is right when the
     operator acts on it without asking again or correcting it.
   - **1.2. Classify a question before asking it.** A fact the agent could observe by
     running a probe (behavior, timing, layout, output, speed) is not the human's to answer:
     run the probe and bring the result. A probe answers fast and hands the operator a result
     to react to; a question costs the operator's attention and a wait. A read-only
     investigation answers from the evidence and builds no probe. A question goes to the
     operator only for a product choice, a preference, or authority the operator kept, and
     the question carries a recommendation. Routine choices stay inside the accepted scope.
     A cause is asserted only after the agent has read the code and the evidence on that
     path. A cause without that evidence is reported as unverified, with the check that
     would settle it.
   - **1.3. Connect the outside world.** The inner loop builds and checks toward the goal.
     The outer loop brings reports, messages, and operating data in. Both stay connected, so
     a new report enters the investigation path without the operator pasting it, and an
     outside event starts an agent only through a proven workflow. Start from one concrete
     gap and one source. Give agents tool access to the real source. Build a knowledge
     system only for a gap that tool access did not close. A connected source never
     authorizes a message, merge, or release by itself.

2. **Verify before claiming.** The agent checks its own result on the real product: it drives
   the product through the surface its users use (browser, desktop app, simulator, or
   command line) and reads the result there. Without this check there is no loop. Autonomy
   reaches only as far as the checks reach. Every claim of success carries the command and
   its exit or output, tied to the exact version checked. Evidence shows the action, the
   state after it, and the side effects (files, rows, messages). A final screen alone proves
   little.

   - **2.1. Close loops on an observed result.** An improvement claim shows before and after
     numbers from the same check against a stated criterion, and the agent repeats change
     and check until the number improves. Verifiers hunt for defects beyond the happy path,
     and the fix and the check repeat until the change is fit to land. The checker itself
     gets checked.
   - **2.2. Prove it locally first.** The operator watches the agent drive the real product
     locally before unattended or cloud work. The environment grows in dependency order from
     that one real user journey, and each step is proved before the next. The same tools
     serve local work, cloud agents, and automations, and each new environment's setup is
     verified before use. A target is checked before its behavior is read: the expected
     build, process, data, and starting state. A process that answers is not a ready product;
     ready means the journey under test is reachable. Cleanup removes what the run started
     and keeps the evidence.

3. **Say what a check proves.** Correctness, performance, code quality, and user experience
   are separate questions, each with its own evidence. A green test proves only what it
   tests. A test that repeats the code proves nothing. Reproducing a report and showing that
   the current code still has the defect are two different checks; when the current code
   already holds the fix, the remaining work is a release or an explanation. A reported
   defect is reproduced more than once on the current code before anyone changes code, with
   the report's version, setup, data, and steps kept. Running the product, compiling, review,
   and mathematical proof are different kinds of evidence; mathematical proof is the
   strongest kind and the hardest to reach. A document describes a workflow; only a run shows
   it works. A report names what was checked, what was not, and which kind of evidence it is.
   Missing coverage stays visible.

4. **Code for mechanical steps, judgment for the agent.** Steps that must happen the same way
   every time live in stable, shared tools. The checks that drive the real product come
   before the features they check. Every other job that will run more than once (builds,
   deploys, releases, operations, incident checks) also gets its tools before the work that
   depends on them. The tools let an agent see the current state, confirm the problem, do the
   job, and prove it done. The next run then needs the human only for a decision the operator
   kept. Agents call the shared tools and do not rebuild them as one-off scripts each
   session. A tool that worked is kept, so every agent benefits. Reuse, speed, and
   predictable behavior justify a tool; a smaller context window is a side benefit. A skill
   is a light wrapper around its tools. A migration across many files runs as a script, and
   the agent handles only the exceptions.

   - **4.1. A command explains itself.** When a file, setting, or service is not where it
     should be, the command's own output says what is wrong, why it matters, and how to fix
     it, with the real file, line, or command filled in. Each finding carries a fix line. The
     skill around it then stays short and covers only the calls a command cannot make.
   - **4.2. Shared tools are infrastructure with an owner.** Tools, feature maps, checks, and
     skills get planned build and upkeep time, next to features, because they lift every
     agent and every contributor: new hires, product managers, designers, and cloud agents.
     A tool states its inputs, outputs, starting conditions, side effects, and failure exits
     in its own help. A tool is tested against the situations agents meet, failures
     included. Creating a command is the start of maintaining it. A tool that failed a real
     run is fixed in the tool, and the fix cites the run. A tool's examples add no dependency
     to the tool.

5. **Make the easy path the right path.** Agents copy the nearest pattern, edit the open file,
   take the shortest route that compiles, and keep code whose callers they cannot see. Agents
   also carry out a requested implementation even when it breaks a system invariant, so an
   invariant is enforced by the environment, never by the request. A check blocks a change
   the operator asked for as firmly as one the agent chose. Design for these habits: one
   supported way to do common work, and a conventional route that needs fewer decisions than
   a shortcut. The obvious command or file location is the correct one. An agent with little
   context and a cheaper model both do good work on the conventional path, without the
   project history. Agents absorb strictness that a person would find tiresome, so a
   constraint is never weighed against human comfort, and an agent's burden never argues
   against a constraint.

6. **Prevent mistakes at the strongest layer.** Five layers, strongest first: code structure
   and data shapes that remove the invalid choice; automated checks (lint, compiler,
   continuous integration, hooks); written rules and review bots; skills; a style guide held
   up by human review. Written guidance is the weakest layer, because agents miss rules. The
   choice of language sits in the first layer: a strict compiler gives trust with no human
   check, as long as a check blocks its escape hatches (unsafe blocks, casts, suppressions).
   Credentials and permissions sit there too: an agent without production access cannot wipe
   production. A constraint in the environment frees the agent from remembering it; the
   agent meets the rule at the moment it matters. Structure removes some mistakes. Live
   checks and judgment catch the rest. Both stay in place. Human review is where the next
   missing check is found, so a rule that keeps being broken becomes a hook or check instead
   of another sentence. Any code starts by naming its data shape and choosing its organizing
   structure. A code base enforces five rules:

   1. The conventional path needs fewer decisions than a shortcut.
   2. A forbidden dependency fails mechanically. Where a product draws an interface, heavy
      work is not imported into the code that draws it.
   3. Every durable value has one obvious writer.
   4. New work adds its own isolated files; nothing appends to a shared root file or a
      hand-kept list. A list that names files is generated from those files.
   5. An exception is narrow, explicit, and reviewed as an architecture change.

   Each performance bar comes from a measurement of this product. A number from another
   product is never a bar here.

7. **Learn from real failures.** Change the setup when a failure repeats across agents or
   tasks. A one-off mistake needs no new rule. Imagined failures need none either. Until the
   operator samples output instead of reading all of it, the operator reads the agent's tool
   calls and reasoning to see where it fails; a failure mode seen more than once becomes a
   skill, check, or tool. Each new rule, check, tool, or skill change cites the failure that
   caused it. Pick the next environment improvement from an observed bottleneck, and weigh
   its build and upkeep cost against the gain. Set aside time for this work on purpose. An
   operator stuck relaying and correcting never finds that time.

8. **Keep what agents copy worth copying.** Agents extend the patterns they find, so the code
   base is their memory, and a bad pattern spreads. Block a bad pattern with a lint the
   second time it appears, so no workaround spreads, then clean up the rest, and keep that
   cleanup visible until finished. A standing gardening pass with an owner inspects
   representative changes and weeds the code base. An audit (a fresh review of the code base)
   runs from the first commit: hooks check every commit and push, and an agent audit follows
   each accepted piece of work before the next feature starts. Audit and fix repeat until no
   serious finding (high or medium) remains, unless the operator accepts a named exception.
   What counts as serious is fixed before the first round, so grading does not move between
   rounds. When the count of serious findings fails to fall two rounds in a row, the loop
   stops and goes to the operator. Reuse the safeguards an existing code base already has;
   rewrite for an observed problem, never as a starting rule. A new code base grown fast
   without constraints is the biggest risk, so it gets its constraints from the first commit.
   Each change lands as one coherent unit, so history explains itself and a revert stays
   easy; there is no fixed size cap. Agents use comments to excuse a workaround or to freeze
   one-off feedback as a rule. A comment survives only for a reason the code cannot show. A
   blanket rule copied from another project comes with that project's context and exceptions.

9. **Make intent clear before broad work.** State the goal, the reason, the conditions that
   matter, and the decisions the operator keeps. Separate required outcomes from suggested
   implementation. The environment's tools turn this intent into the project's plan: what,
   why, how, an owner and a done condition for each step, and the checks that prove each one.
   The agent produces that plan without reading these principles. The agent restates the ask,
   the scope, and the kept decisions before it builds. A request for approval points to the
   whole plan it covers, so no step drops out of the grant. Use precise words; one
   well-chosen term carries a whole rule to the agent. Give the agent context and reasons,
   the way you would brief a capable colleague; step-by-step control teaches nothing. As
   models improve, passing intent becomes the bottleneck. The operator's domain knowledge
   picks the valuable work; the environment gives the agent the context to act on it.
   Uncertainty gets evidence before action: a nontrivial change, an architecture decision, or
   an "are we sure?" gets an investigation first, and a change that crosses a function
   boundary gets parallel design exploration first. A plan is a snapshot of intent and goes
   stale. Plans refresh when new facts arrive, with the reason kept. Settled choices stay
   settled until new evidence arrives or the operator reopens them. A topic the operator
   deferred waits for the operator.

10. **Give agents a map of the product.** Controls alone leave an agent guessing where to act.
    A feature map describes each feature from the user's side: name, purpose, how to reach
    it, expected result, and what it needs (data, account, platform). The map says how to
    use a feature. Code says how it is built, and changes faster than any map. With the map,
    a vague report maps to a named feature and a drivable journey. A check waits on an
    observable end state, never on time, and runs with the product in its user-facing state.
    An unreachable route is reported, never skipped in silence. An outdated map, a broken
    control, and a product defect are three different findings; a regression is never hidden
    by weakening the expected result. Keeping the map current is maintenance with an owner,
    automated as the product changes.

11. **Turn real workflows into small skills, and keep memory.** Skills come from processes
    that worked and carry the operator's own expertise, so agents work the way the operator
    would. They stay short and get simpler as models improve. A skill change is tested like
    a code change: run it on a task with the models that will do the work, and score the
    result against written criteria, judged by an agent that did not do the work. Keep the
    candidates blind to the test, because an agent that knows it is tested changes its
    behavior. The judge scores the transcript and the artifact, never the candidate's own
    account. Adopt a tool only after reading it; trust comes from understanding and observed
    results, never from a library's reputation. A tool's name does not tell its contents, and
    similar public and internal workflows differ. Earlier findings are recovered instead of
    re-investigated, and past transcripts hold the corrections worth turning into checks.

    - **11.1. One working contract routes the work.** The contract (the one skill that routes
      a task to its workflow) is turned on by the operator; it does not turn itself on. It
      demands replies the operator acts on at once, deliberate subagents, plain prose, simple
      code, and verified work. It routes every multi-step task to its workflow, and a
      workflow hands work on to another workflow when the task needs it. The operator's standing rules on
      replies, commits, and approvals live outside the contract and bind it. Every route
      rests on a building principle in this file and on the coding principle that carries
      it. Before multi-step work, an agent reads the coding principles the task applies and
      names the choice each one changed; a citation with no changed decision shows that the
      read was skipped. Rigor matches the task: multi-step work gets the full method, and a
      casual turn, or a turn the operator opts out of, gets a direct answer with no workflow.

12. **Scale only on proven reliability.** Make a small setup trustworthy before adding
    agents; adding agents before trust multiplies the mistakes and the cost. Split work only
    when the split helps the whole result, with one owner for coordination and the combined
    result. The coordinator looks for safe parallel work at every step. Independent
    investigations, plans, and reviews run in parallel from the start; they share no writes,
    so they wait on no proof of trust. Writers run in parallel once each owns separate files
    and a separate live session. A worker does its one task and leaves splitting to the
    coordinator. The coordinator delegates instead of doing the work, keeps the whole
    picture, and briefs each worker with one separate task, its context, its owned output,
    and the evidence it must return. Workers get separate outputs and separate live sessions;
    an ambiguous live-session target is refused, never defaulted. When two workers must write
    one object, code enforces the access order. A written warning does not. Every worker
    report is a claim the coordinator checks before use. Splitting one job across workers,
    running the same job several ways, and comparing competing designs are each a named
    workflow, chosen per task. Related reports are grouped before fixes are assigned; a
    findings queue shows the pattern that one fix per report hides, and the operator or the
    coordinator reads it on a set rhythm. An unattended coordinator reports on a fixed rhythm
    and escalates only when two reports in a row show no progress. Once one coordinator is
    dependable, standing coordinators are added one at a time, each owning one area, and the
    operator moves between them.

13. **The human stays responsible, and trust stays bounded.** Oversight shifts to sampling
    output after it lands, correcting failures, and improving the setup. Whether review
    happens before an action or after it follows from the risk and the authority involved.
    Verification effort is set per task from its risk and what a failure would cost.
    Uncertainty is stated. An irreversible step waits for the operator's own words or for a
    rule the operator wrote that covers that exact action. A force-push to a shared branch, a
    deploy, data deletion, and a customer message are irreversible steps. Evidence supports a
    decision inside the granted authority; it never grants new permission to merge, publish,
    deploy, delete, or widen access. One missing human decision never stops the rest of the
    work: the agent names it, routes it to the right person with the evidence attached, and
    keeps everything else moving. A finished item never stops the work either: the agent
    moves to the next step of the accepted work. Reversible work that crosses no privacy or
    security boundary goes ahead without asking. The agent stops only for a decision the
    operator kept or a blocker it cannot work around. Work backward from the question "how
    could the agent merge its own code?": define complete, the evidence required, and the
    missing capabilities, then build those first. Keep a recovery path: detect failures, keep
    history, revert or repair, recheck, and turn the correction into a check.

14. **Measure useful work, not activity.** Counts of changes, lines, or agents do not show
    value. Judge progress by dependable improvements a user notices. Cleanup and environment
    work count when they remove a repeated failure or a human intervention. Measure the
    whole cost: model use, human interventions, rework, coordination, verification,
    recovery. A status report pairs outcomes with the cost that produced them. Agents make
    work possible that no one person could do, including one rule enforced across a whole
    code base in one pass; judge the spend by what it returns. A measure changes when new
    evidence shows that it rewards the wrong behavior. Another team's numbers are examples,
    never targets.

## Boundaries

1. Freedom comes after work on the environment. Installing skills or writing instructions
   alone does not create it.
2. Human involvement changes shape, but it does not end.
3. Merging without review is one mature setup, reached under a written grant after the
   environment work this file describes. It is never a default.
4. A better check lets a risky action be tried and reverted only when its result is
   observable and a revert exists. It never makes data loss reversible.
5. No fixed number measures trust: no defect rate, sampling rate, verifier count, agent
   count, or score. A trust curve described by one team is an account, never a scale.
6. A building principle in this file counts only when it changed a decision in
   ctlhq; one that no longer prevents a real failure is simplified or removed.
   Every building principle is strengthened or simplified on evidence.
7. A coding principle counts in a reply only when the agent names the choice it changed.
8. An agent's approval is never the operator's approval. A change to authority or safeguards
   needs the operator's yes. When two rules disagree on authority, the stricter rule holds
   until the operator settles it.
