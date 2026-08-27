# ARIES PaaS

ARIES PaaS is an ontology-aware control plane around the existing ARIES Rust
planning kernel. It **does not rewrite the planner in Elixir**. The preserved
`aries-plan` binary remains the only planning actuator.

## Manufacturing correspondence

```text
public capability graph (SKOS + DCTERMS + PROV-O + P-Plan + ODRL + OWL-Time + QUDT)
        │
        ├── ggen sync run ──> generated capability catalog + ggen receipt
        │
Ash resources + AshR2RML metadata
        │
        └── AshR2RML.Reactor.Pipeline ──> admitted R2RML/PROV semantic mapping
                                             │
request ─> admit ─> semantic_admission ─> authorize ─> actuate ARIES ─> verify_receipt
                                                ^              │
                                                │              └─ aries-plan --domain ... problem.pddl
                                                └─ explicit `execute` authority only
```

The runtime Reactor has one DO edge: `AriesPaaS.Steps.Actuate`. Hooks, RDF,
ggen output, and planner text cannot call ARIES directly. A non-zero solver
exit still receives an execution receipt; a request refused before actuation
does not manufacture a false execution receipt.

## Public semantic surface

| Concern | Public ontology |
| --- | --- |
| Plan intent / planned steps | P-Plan (`http://purl.org/net/p-plan#`) |
| Executed solver activity / provenance bundle | W3C PROV-O |
| Runtime authorization vocabulary | W3C ODRL |
| Temporal semantics | W3C OWL-Time |
| Quantity semantics for future cost/duration projections | QUDT |
| Capability catalog | W3C SKOS + Dublin Core Terms |
| Relational RDF projection | W3C R2RML |
| Operational semantic admission | W3C SHACL |

The local `ontology/public-capabilities.ttl` defines **individuals**, not a
private replacement ontology. Ash-specific storage facts stay in AshR2RML
metadata; they are not written into public ontology definitions.

## Construction

The PaaS pins `ash_r2rml` to commit
`067954ad406fd637fd47646bdb10c4580809c79d`. CI pins the ggen source tree to
`1e9fcb9679a61460fbd641415cb72511c7e50b33`.

```bash
# From a checkout with a built ggen binary:
cd paas
ggen sync run
ggen receipt verify
mix deps.get
mix compile --warnings-as-errors
mix test
```

`ggen` is a construction dependency, not a request-time dependency. The
generated `lib/aries_paas/generated/capability_catalog.ex` projection is
manufactured before Mix compilation and is never a hand-editing surface.

## Exact execution proof

The E2E test builds and invokes ARIES's own `aries-plan` binary against the
repository's existing Gripper PDDL fixtures:

```text
planning/problems/pddl/tests/gripper.dom.pddl
planning/problems/pddl/tests/gripper.pb.pddl
```

The verifier requires:

1. a real Ash create action to execute;
2. AshR2RML's Reactor pipeline to compile the three public-semantic resources;
3. ggen to manufacture the capability catalog twice with identical output;
4. explicit `execute` authority;
5. the real ARIES binary to return exit 0 and a non-empty plan;
6. the plan SHA-256 to match the receipt;
7. the receipt to carry the exact semantic-mapping identity.

The GitHub workflow uploads the ARIES receipt and ggen receipt as replay
evidence. Green CI establishes ALIVE only for the exact tested repository head,
toolchain, dependency refs, Gripper subject, and workflow configuration.
