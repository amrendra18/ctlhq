---
name: emulate
description: "Build a local, stateful stand-in (an emulator) for an outside service a project calls, from the service's public API documents. Scope it to the calls the project makes, keep state in memory, match the real protocol, record what it does not cover, and add it to the feature map. Use for /emulate, or when a harness needs an outside service it must not call for real."
disable-model-invocation: true
---

# Emulate an outside service

A harness proves the running product. When the product calls an outside service (GitHub, a mail server, a storage API, a NAS admin API), the run must not touch the real one. The real one costs money, needs the operator's keys, or changes real data. An emulator is a small local server that answers the same requests the way the real service does. It also remembers what earlier requests changed, so a create followed by a list shows the new item.

The method: run local, stateful clones of the services the product calls (for example Slack, GitHub, Gmail, Stripe, or AWS through LocalStack). When no clone exists, the agent builds one from the service's public API documents.

The emulator replaces only the outside service, at the boundary the project already has. The product code stays the same. Only the address it calls changes, through a base URL or an environment variable.

## Steps

1. **Look for an existing emulator first.** Maintained ones exist for some services, for example Mailpit for mail and LocalStack for AWS. If one covers the calls in step 2, use it and go to step 7. Adding it is a new dependency, so run the **supply-chain** skill first.
2. **Scope the calls the project makes.** Find every call to the service in the source, for example with `rg -n '<base URL or client library name>'`. Write a numbered table: method and path (or command), the fields the project sends, the fields it reads, and the status codes it handles. The emulator covers this table and nothing more. A call the project never makes stays out.
3. **Read the public API documents for each call in scope.** Record each document's URL and the date or version you read. Note the request and response shapes, status codes, error bodies, content types, ID formats, pagination, and the auth and rate-limit headers the project reads. A fact the documents do not state is a guess. Mark it as one in the "Not covered" list (step 7).
4. **Build it with state in memory.** Put it in the project at `verify/emulators/<service>/`. Write it in Python's standard library, or in Node with no packages, matching the project. It is one process. State lives in memory and starts empty, or from a seed file, on every start, so two runs never share state. A write changes what later reads return. A delete followed by a read returns the real not-found status and body.
5. **Match the real protocol.** Use the same transport, paths, methods, headers, status codes, error bodies, content types, ID formats, and pagination as the documents. Accept one fixed fake token, and answer a missing or wrong token with the real error. Never accept, store, or forward a real credential. Bind to `127.0.0.1` only.
6. **Wire it into the harness.** `scripts/verify` starts it in the launch step with `ctlhq-serve start --name emulator-<service> --cwd verify/emulators/<service> --ready-url <URL> -- <command>`, and stops it in cleanup with `ctlhq-serve stop --name emulator-<service>`. The doctor step can check it with `ctlhq-preflight --service <URL>`. Point the product at it through the setting the product already has for the service address. If the product has no such setting, adding one is a product change. Name it in the reply, and make it only within the task the operator approved.
7. **Record what it does not cover.** Write `verify/emulators/<service>/README.md` with three numbered lists: the source documents (URL and date), the calls covered, and "Not covered". "Not covered" holds every call out of scope, every guessed behavior, and what the emulator skips, such as rate limits, webhooks, timing, and real authentication. The run's summary names every emulator it used.
8. **Add it to the feature map.** In `verify/features/README.md`, add a numbered "Stand-ins" table with the service, the emulator path, the calls covered, and a link to its "Not covered" list. Each feature file whose journey reaches the service names the emulator in its preconditions. A proof that depends on a "Not covered" behavior is unproven for that part. Say so in the feature's `Gotchas`.
9. **Prove it.** For each call in scope, check the happy path and one documented error against the emulator. Where the operator has a recorded real response, compare its fields with the emulator's. Then run `scripts/verify fast` for one feature that uses it. The run must exit 0 and name the emulator in its summary.
10. **Reply contract.** The service, the calls covered (count and the table), the emulator path, the check command and its exit code, the "Not covered" list, the feature files that now name the emulator, and the evidence folder of the `scripts/verify` run.
