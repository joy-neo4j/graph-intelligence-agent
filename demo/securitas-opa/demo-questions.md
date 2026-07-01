# Securitas Demo Readout — OPA Documentation Knowledge Graph

**Account:** Securitas Intelligent Services AB · **Demo date:** July 1, 2026 · **Owner:** Joy Das
**Corpus:** OPA (Open Policy Agent) documentation — 10 Markdown files, authorisation domain, structurally identical to Securitas's platform docs
**Graph:** `neo4j+s://ee0bb26c.databases.neo4j.io` (AuraDB Enterprise 5.27)
**Two-tier structure:** Aura DI console (zero setup, WOW) → graph-intelligence-agent (custom schema, developer control)

> This is the live-call script: what to say, what to type, what appears, and how each result maps back to Securitas's own documentation. Every Cypher query below has been run against the built graph — the result shapes are real.

---

## Opening Frame (30 seconds)

> "On June 3 you mentioned making your Markdown documentation interactive for other developer teams. I want to show you two things: first, what's already available in your Aura console today — you could try this next week with zero setup. Then, what your engineering team gets when they define exactly what to extract."

**Guardrail statement (say this before touching anything):**

> "One thing upfront: the knowledge graph is read-only. The agent queries it and answers questions from it — it has no write access to your operational Neo4j instance. Same Aura RBAC you already manage. That's the safe on-ramp."

---

## Core Thesis

> **Azure Cognitive Search retrieves chunks.**
> **A Neo4j knowledge graph retrieves context.**

A keyword search returns documents that contain the words you searched for. A knowledge graph returns the *entities*, their *relationships*, and the *traversal paths* that explain why the answer is correct. For documentation that describes how systems connect — which services depend on which roles, which APIs share which resources — that difference is the entire value proposition.

---

## Why OPA Docs Are a Securitas Proxy — the Mapping

OPA documentation isn't a random corpus. It's the closest public analogue to what Securitas's platform team produces: **Markdown, authorisation domain, developer-facing, describing how systems grant and deny access.** The graph we extracted from it maps one-to-one onto the graph you would get from your own docs.


| Graph element    | In the OPA docs                                             | The Securitas equivalent                               |
| ------------------ | ------------------------------------------------------------- | -------------------------------------------------------- |
| **PolicyModule** | An OPA policy file or doc section (`httpapi.authz`, `oidc`) | A platform**service documentation page**               |
| **Concept**      | RBAC, JWT, TLS, Rego, OPA Bundle                            | Your**APIs, roles, data models, protocols**            |
| **Rule**         | `allow`, `deny`, `user_owns_token`                          | Your**authorisation requirements / access rules**      |
| **ResourceType** | HTTP API, Kafka topic, SSH host                             | Your**governed resources** (services, data, endpoints) |
| **REFERENCES**   | A module cites a concept                                    | A doc page**references** an API or role                |
| **CONTAINS**     | A module defines a rule                                     | A service page**defines** an access rule               |
| **GOVERNS**      | A rule controls a resource                                  | A rule**controls access** to a resource                |
| **DEPENDS_ON**   | A rule builds on another rule                               | A requirement**builds on** another requirement         |

**The same questions, translated:**


| The OPA question we answer today                    | The Securitas question it stands in for                  |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| "Which modules reference JWT authentication?"       | "Which service docs reference role*X*?"                  |
| "Which rules depend on other rules?"                | "If we change this requirement, what breaks downstream?" |
| "Which resources are governed by multiple modules?" | "Which resources do multiple teams share access to?"     |

> **Say it:** "Everything you're about to see on OPA docs, you get on your docs — same shapes, same queries, same value. We're using OPA only because it's public."

---

## Tier 1: Aura Document Intelligence — The WOW Moment

*Console-native path. Zero code, zero configuration. Pre-build the graph before the call.*

**Quick-start docs:** https://neo4j.com/docs/aura/document-intelligence/quick-start/

### What to show (8 minutes)

**1. The graph schema** — open Aura Explore, show the auto-detected schema.

> "We uploaded OPA's documentation. Document Intelligence detected the entity types and relationship structure automatically. No modelling, no pipeline. Minutes from upload to queryable graph."

```cypher
CALL db.schema.visualization()
```

**2. Natural-language question via the built-in console chat** — type directly in the Aura DI chat:

> "Which documentation sections describe how role-based access control is implemented?"

Then:

> "What are the dependencies between the entitlements layer and the role hierarchy?"

> *(Talking point: "Azure Cognitive Search returns chunks that mention 'role hierarchy'. DI returns the entity relationships — which sections depend on which concepts. That's the graph advantage.")*

**3. A structured traversal in Aura Explore** — the lexical layer:

```cypher
MATCH (d:Document)<-[:PART_OF]-(c:Chunk)
WHERE c.text CONTAINS 'role' AND c.text CONTAINS 'allow'
RETURN d.name AS document, count(c) AS relevant_chunks
ORDER BY relevant_chunks DESC
LIMIT 10
```

> "This is the lexical layer — every document chunked and searchable by keyword or vector. Next I'll show what happens when you add the entity layer on top and control exactly what gets extracted."

**4. The pivot**

> "This is what's in your Aura console today — no developer needed. Now let me show you what your engineering team gets when they define the schema."

---

## Tier 2: graph-intelligence-agent — Custom Control

*Same OPA docs, same graph principle, but with a **custom extraction schema** your team defines. Pre-build before the call.*

**Repo:** https://github.com/joy-neo4j/graph-intelligence-agent (customised for Securitas)

### What this adds over Tier 1


| Capability            | Tier 1 (Aura DI console)    | Tier 2 (graph-intelligence-agent)                                      |
| ----------------------- | ----------------------------- | ------------------------------------------------------------------------ |
| Entity types          | Auto-detected               | **Custom-defined** — PolicyModule, Rule, Concept, ResourceType        |
| Relationships         | Auto-detected               | **Schema-controlled** — CONTAINS, REFERENCES, GOVERNS, DEPENDS_ON     |
| Entity dedup          | Exact-match only            | **MERGE on key property** + schema field constraints (lowercase, enum) |
| Querying              | Console chat + Aura Explore | **Full Cypher + vector search + MCP agent**                            |
| Schema iteration      | Re-upload to change         | **Edit the schema file → re-extract** (versioned in git)              |
| Developer integration | Console only                | **Claude Code, Claude Desktop, Cursor, VS Code**                       |

### The extracted graph (real numbers)

```
(PolicyModule)-[:CONTAINS]->(Rule)
(PolicyModule)-[:REFERENCES]->(Concept)
(Rule)-[:GOVERNS]->(ResourceType)
(Rule)-[:DEPENDS_ON]->(Rule)
```


| Entity       | Count | Relationship | Count |
| -------------- | ------- | -------------- | ------- |
| PolicyModule | 123   | REFERENCES   | 654   |
| Rule         | 177   | CONTAINS     | 311   |
| Concept      | 434   | DEPENDS_ON   | 85    |
| ResourceType | 68    | GOVERNS      | 49    |

Concept taxonomy: policy_construct 197 · infrastructure 111 · data_type 51 · protocol 43 · access_model 32
Lexical layer: 10 documents · 138 active chunks · embedded at 1536d (vector + fulltext indexes).

---

### Round 1 — Relationship queries: graph vs search (7 minutes)

These look simple but **cannot be answered by Azure Cognitive Search** — they require traversal across the entity graph, not keyword matching on document chunks.

---

**Q1 — "What are the most important concepts across all the authorization documentation?"**

*The opening query — the conceptual fingerprint of the whole corpus.*

```cypher
MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WITH c, count(DISTINCT pm) AS breadth
ORDER BY breadth DESC LIMIT 10
RETURN c.name AS concept, c.category AS category, breadth AS referenced_by_n_modules
```

**What appears:**


| concept     | category         | referenced_by_n_modules |
| ------------- | ------------------ | ------------------------- |
| Rego        | policy_construct | 44                      |
| OPA         | infrastructure   | 31                      |
| JSON Schema | data_type        | 10                      |
| JWT         | protocol         | 8                       |
| OPA Bundle  | infrastructure   | 8                       |
| SSH         | infrastructure   | 7                       |
| GraphQL     | protocol         | 6                       |

> **Talking point:** "This is the conceptual fingerprint of your authorization documentation. Rego and OPA are foundational — 44 and 31 modules. JWT, SSH, GraphQL are the protocol layer. Azure Cognitive Search would return a list of documents containing the word 'JWT'. This graph tells you JWT is a *protocol-category concept referenced across 8 distinct policy modules* — and, in the next query, exactly which rules those modules define around it."
>
> **Securitas mapping:** "Swap in your docs and this is the fingerprint of your platform — which APIs and roles are foundational, which are feature-specific."

---

**Q2 — "Which modules handle JWT authentication, and what rules do they define?"**

*A two-hop query that structurally separates **authentication** (token validation) from **authorisation** (allow/deny decisions).*

```cypher
MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WHERE toLower(c.name) CONTAINS 'jwt' OR toLower(c.name) CONTAINS 'json web token'
WITH pm, collect(DISTINCT c.name)[0..3] AS auth_concepts
MATCH (pm)-[:CONTAINS]->(r:Rule)
WITH pm.name AS module, auth_concepts, collect(DISTINCT r.name)[0..5] AS rules
RETURN module, auth_concepts, rules
ORDER BY size(rules) DESC
LIMIT 8
```

**What appears:**


| module           | auth_concepts                                   | rules                                                             |
| ------------------ | ------------------------------------------------- | ------------------------------------------------------------------- |
| example-jwt.rego | JWT, JSON Web Tokens, OPA builtin io.jwt.decode | allow, variable_arg, user_owns_token, token, query_ast            |
| oidc             | JWT, JSON Web Tokens                            | **jwt_unverified, jwt_header, jwks, issuers, metadata_discovery** |
| authz            | JWT                                             | allow, result, allow1, allow2                                     |
| httpapi.authz    | JSON Web Tokens                                 | allow, user_owns_token, token                                     |

> **Talking point (this is the killer):** "Look at the `oidc` module — its rules are `jwks`, `issuers`, `metadata_discovery`. That's token *validation*: does this token come from a trusted issuer? Now look at `example-jwt.rego` — `allow`, `user_owns_token`. That's *authorisation*: given a valid token, is this request permitted? The graph surfaces the separation of concerns between authentication and authorisation **structurally** — not by reading the docs, but by traversing the entity graph. No keyword search can do that."
>
> **Securitas mapping:** "This is 'which service docs handle identity, and what access rules do they define' — the exact question a new engineer asks on day one."

---

**Q3 — "Which rules depend on other rules to reach their decision?"**

*Variable-length path traversal — the policy dependency graph and the basis for impact analysis.*

```cypher
MATCH path = (r:Rule)-[:DEPENDS_ON*1..3]->(dep:Rule)
WHERE r.name <> dep.name
RETURN r.name AS rule, [n IN nodes(path) | n.name] AS dependency_chain
LIMIT 20
```

**What appears:**


| rule              | dependency_chain           |
| ------------------- | ---------------------------- |
| allow             | [allow, deny]              |
| result            | [result, allow]            |
| test_allow        | [test_allow, allow]        |
| test_post_allowed | [test_post_allowed, allow] |
| result            | [result, allow, deny]      |

> **Talking point:** "The `allow → deny` chain means the `allow` rule explicitly references `deny` — deny takes precedence. The test rules depending on `allow` show OPA's testing pattern: your test suite is structurally linked to the rules it verifies. Change `allow`, and the graph tells you immediately which rules and tests are affected. That's impact analysis — not a search result."
>
> **Securitas mapping:** "'If we change this authorization requirement, what else depends on it?' — answered by traversal, in milliseconds."

---

### Round 2 — Semantic + hybrid queries (5 minutes)

**Q4 — "What concepts does each area of the documentation introduce?" (Hybrid GraphRAG)**

Run a vector search first (in Claude Code or the graphrag MCP) to show the lexical/semantic layer:

```
vector_search: "authentication versus authorisation separation of concerns"
```

Then the graph traversal over the entity layer:

```cypher
MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WHERE pm.name IN ['http-api-authorization','kafka-authorization','security',
                  'kubernetes-primer','policy-language']
RETURN pm.name AS source_doc,
       collect(DISTINCT c.name)[0..6] AS top_concepts,
       count(DISTINCT c) AS total_concepts
ORDER BY total_concepts DESC
```

**What appears:**


| source_doc             | top_concepts                                                                  | total_concepts |
| ------------------------ | ------------------------------------------------------------------------------- | ---------------- |
| policy-language        | Rego, undefined, some keyword, built-in functions, unification, every keyword | 22             |
| http-api-authorization | JWT, OPA, allow/deny policies, external data, remote bundle server            | 8              |
| security               | OPA, TLS, HTTPS, authentication, authorization, CA cert                       | 6              |
| kubernetes-primer      | OPA, AdmissionReview, Kubernetes, Kubernetes API Server                       | 4              |
| kafka-authorization    | Kafka authorization, PII, Kafka bundle API                                    | 3              |

> **Talking point:** "Vector search finds the relevant chunks — that's what Azure Cognitive Search does. The graph traversal finds the conceptual structure: each doc's fingerprint. `policy-language` is broad (22 concepts — the language reference); `kafka-authorization` is narrow (3 — laser-focused on PII and Kafka). Together they answer WHY, not just WHAT. That's GraphRAG."
>
> **Securitas mapping:** "Platform-wide docs light up with many concepts; feature docs stay tight and focused. That's the topology of your knowledge base, visible in one query."

---

**Q5 — "What security concepts does the security documentation cover?"**

```cypher
MATCH (pm:PolicyModule {name: "security"})-[:REFERENCES]->(c:Concept)
RETURN c.name AS concept, c.category AS category
ORDER BY c.category, c.name
```

**What appears:**


| concept        | category       |
| ---------------- | ---------------- |
| authorization  | access_model   |
| CA cert        | data_type      |
| OPA            | infrastructure |
| HTTPS          | protocol       |
| TLS            | protocol       |
| authentication | protocol       |

> **Talking point:** "The security doc covers two distinct layers: the *protocol* layer (TLS, HTTPS, CA cert — transport security) and the *access-model* layer (authentication, authorization — identity decisions). The graph distinguishes these automatically via the category we defined in the schema. A keyword search returns the whole document; the graph returns the structured taxonomy."

---

### Round 3 — The analogy close (3 minutes)

> "Now imagine this graph isn't OPA documentation — it's YOUR platform documentation. The `PolicyModule` nodes are your service documentation pages. The `Concept` nodes are your APIs, roles, and data models. The `Rule` nodes are your authorization requirements. The `REFERENCES` and `GOVERNS` relationships are the dependency map your developers need when they ask: *'If we change this API's access model, which downstream services are affected?'*"

**Killer backup query — the full authorization taxonomy:**

```cypher
MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WITH c.category AS category,
     count(DISTINCT c) AS unique_concepts,
     count(DISTINCT pm) AS modules_using,
     collect(DISTINCT c.name)[0..4] AS examples
RETURN category, unique_concepts, modules_using, examples
ORDER BY modules_using DESC
```

**What appears:**


| category         | unique_concepts | modules_using | examples                                      |
| ------------------ | ----------------- | --------------- | ----------------------------------------------- |
| policy_construct | 177             | 85            | Rego, policy bundles, allow/deny policies     |
| infrastructure   | 73              | 72            | OPA, OPA Bundle, io.jwt.decode                |
| data_type        | 45              | 48            | external data, AST, PII                       |
| protocol         | 30              | 27            | JWT, GraphQL, REST API                        |
| access_model     | 21              | 24            | HTTP API Authorization, GraphQL authorization |

> **Talking point:** "177 distinct policy constructs, 30 protocol concepts, 21 access-model concepts — all structured and queryable, extracted automatically in under two minutes. Replace OPA docs with Securitas platform docs and you have the authorization taxonomy of your own system, on demand."

---

## Demo Flow (25 minutes)


| Time       | Action                                                     | Notes                                          |
| ------------ | ------------------------------------------------------------ | ------------------------------------------------ |
| 0–2 min   | Opening frame + guardrail statement                        | Address agent hesitancy upfront                |
| 2–10 min  | **Tier 1: Aura DI** — schema, console chat, lexical query | WOW: "this is in your console today"           |
| 10–11 min | Pivot to Tier 2                                            | "Now what your engineering team gets…"        |
| 11–18 min | **Tier 2: Q1–Q3** — relationship traversal               | Graph vs search contrast; Q2 is the anchor     |
| 18–20 min | **Tier 2: Q4–Q5** — hybrid GraphRAG                      | The "why not just Azure Search" answer         |
| 20–22 min | Analogy close + taxonomy backup query                      | Map OPA graph → Securitas platform docs       |
| 22–25 min | POC proposal                                               | Two tiers, concrete questions, 4-week timeline |

---

## POC Proposal (What to Get a Yes On)

**Tier 1 POC (Mattias can approve now):**

> "We upload a sample of your platform Markdown docs to your Aura console — same toggle, same workflow as the demo. You get a graph and a chat interface for your developer teams. No engineering work on your side."

**Tier 2 POC (4-week, Lukasz involved):**

> "We define the entity schema for your domain, ingest 10–20 of your platform docs, and identify 3 questions your developer teams ask today that take 10+ minutes to answer across scattered Markdown files. In 4 weeks, those run in under a second."

**3 proposed POC queries:**

1. "Which services depend on [auth-role-X]?" — cross-service dependency traversal
2. "What are all the downstream impacts if we change [API endpoint Y]?" — impact analysis
3. "Which teams' services share access to [data-resource Z]?" — multi-team access pattern

---

## Known Limitations (Mention Proactively)


| Limitation         | Tier 1 (Aura DI)                         | Tier 2 (graph-intelligence-agent)                               |
| -------------------- | ------------------------------------------ | ----------------------------------------------------------------- |
| Entity dedup       | Exact-match only ("k8s" ≠ "Kubernetes") | MERGE on key property + schema field constraints                |
| Doc-count limit    | 10–20 docs / job in preview             | No limit — MCP workspace ingests in batches                    |
| Schema control     | None — auto-detected                    | Full control via the extraction schema file                     |
| First-pass quality | May extract noise entities               | Schema scopes extraction; first pass still benefits from review |

Frame all of these as: "Preview limitations. Here's the workaround, here's the roadmap."

**One honest note if asked about RBAC specifically:** OPA docs use concrete implementations (JWT, bearer tokens, mTLS) more than they name "RBAC" — so RBAC appears in only the `sudo` docs. On *your* IAM documentation, which names these patterns explicitly, coverage is higher. It's a property of the source corpus, not the graph.

---

## If VG Comes Up

Mattias deferred VG to the AI team on June 3. If it comes up:

> "For the AI team specifically, there's a separate conversation about Virtual Graph — running Cypher and graph algorithms directly on your Databricks data without moving it. Rather than taking time from today's DI demo, could we set up a separate session with Wilhelm and whoever manages Databricks? I have something specific to show them."

Then move back to the DI POC close.
