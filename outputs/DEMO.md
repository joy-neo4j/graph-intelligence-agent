# Opposing Counsel

## Graph-Powered Litigation Intelligence for the Commercial Court

> **One-liner:** A natural language query over 20 approved England & Wales Commercial Court judgments — covering 86 barristers, 39 law firms, 261 parties, 30 canonical legal topics, and 135 statutory provisions — returns structured, sourced answers in seconds.

---

## Table of Contents

1. [What It Demonstrates](#1-what-it-demonstrates)
2. [Architecture Overview](#2-architecture-overview)
3. [Technical Components](#3-technical-components)
4. [Graph Data Model](#4-graph-data-model)
5. [Demo Script — 5 Target Questions](#5-demo-script--5-target-questions)
6. [Complex Graph Traversal Queries](#6-complex-graph-traversal-queries)
7. [Pipeline Reproducibility](#7-pipeline-reproducibility)
8. [Known Iteration Points](#8-known-iteration-points)

---

## 1. What It Demonstrates

Preparing for a high-stakes commercial dispute means knowing more than the law — it means knowing **the people**. Which barristers consistently appear for sovereign states resisting arbitral awards? Which firms have switched sides? What is a specific KC's track record on jurisdiction challenges under s.67?

Today, that intelligence is assembled manually: a junior lawyer trawling through PDFs one by one, building a spreadsheet that is out of date before it is finished.

**Opposing Counsel** replaces that process with a Neo4j knowledge graph. The demo shows three things Neo4j is uniquely positioned to do:

| Capability                                  | Description                                                                                                    | Example                                                                    |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **Multi-hop competitive profiling**   | Traverse Firm → Judgment → Party to answer questions that would otherwise require reading a dozen judgments  | "Has Quinn Emanuel ever acted against a sovereign state respondent?"       |
| **Pattern detection across a corpus** | Aggregate across the graph to surface standing teams and behavioural patterns invisible in any single document | "Which barristers most often appear together on the defence side?"         |
| **Hybrid retrieval**                  | Graph provides structured context; vector search retrieves the relevant judgment passage                       | "What reasoning did the court apply in the Hulley jurisdiction challenge?" |

---

## 2. Architecture Overview

> See: [`outputs/opposing_counsel_architecture.excalidraw`](opposing_counsel_architecture.excalidraw)
> Open at: [excalidraw.com](https://excalidraw.com) — File → Open — select the `.excalidraw` file

### Pipeline (PDF → Graph in under 3 minutes)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     GenAI Services (OpenAI)                                 │
│  gpt-5.4-mini (entity extraction)    text-embedding-3-small (embeddings)   │
└──────────────────────────┬──────────────────────────┬───────────────────────┘
                           │                          │
  ┌─────────────┐    ┌─────▼────────────┐    ┌───────▼────────────────────┐
  │  Data       │    │  Ingestion       │    │  Neo4j Knowledge Graph     │
  │  Sources    │    │  Pipeline        │    │                            │
  │             │    │                  │    │  Document──►Chunk          │
  │ 20 PDFs ───►│───►│ neo4j-           │    │  (891 embedded chunks)     │
  │ EWHC Comm  │    │ lexical-graph    │───►│                            │
  │ 2026        │    │ (pymupdf, chunk, │    │  Judgment  LegalTopic      │
  │             │    │  embed)          │    │  Counsel   Legislation     │
  │ 3 CSVs  ───►│───►│ neo4j-           │    │  LawFirm   Judge           │
  │ barristers  │    │ entity-graph     │───►│  Party                     │
  │ law_firms   │    │ (gpt-5.4-mini,   │    │                            │
  │ legislation │    │  Pydantic v3)    │    └────────────────┬───────────┘
  └─────────────┘    │                  │                     │
                     │ neo4j-ingest     │    ┌───────────────▼───────────┐
                     │ (CSV MERGE,      │    │  Retrieval Layer          │
                     │  enrichment)     │    │                           │
                     └──────────────────┘    │  vector_search            │
                                             │  fulltext_search          │
                                             │  read_neo4j_cypher        │
                                             └───────────────┬───────────┘
                                                             │
                                             ┌───────────────▼───────────┐
                                             │  Claude Code / Chatbot    │
                                             │  Natural language Q&A     │
                                             │  Reports & Analysis       │
                                             └───────────────────────────┘
```

---

## 3. Technical Components

### 3.1 MCP Servers (Model Context Protocol)

Five MCP servers are orchestrated by Claude Code. Each is a local Python service communicating over stdio.

| Server                  | Role                              | Key Tools                                                     | Source                                |
| ----------------------- | --------------------------------- | ------------------------------------------------------------- | ------------------------------------- |
| `neo4j-data-modeling` | Design and validate graph schemas | `validate_data_model`, `get_mermaid_config_str`           | `uvx mcp-neo4j-data-modeling@0.8.2` |
| `neo4j-lexical-graph` | PDF → chunks → embeddings       | `create_lexical_graph`, `embed_chunks`                    | Local`mcp-neo4j-lexical-graph/`     |
| `neo4j-entity-graph`  | LLM entity extraction             | `convert_schema`, `extract_entities`                      | Local`mcp-neo4j-entity-graph/`      |
| `neo4j-ingest`        | Structured CSV ingestion          | `ingest_csv_into_neo4j`                                     | Local`mcp-neo4j-ingest/`            |
| `neo4j-graphrag`      | Query, search, retrieve           | `vector_search`, `fulltext_search`, `read_neo4j_cypher` | Local`mcp-neo4j-graphrag/`          |

### 3.2 GenAI Components

#### Entity Extraction: `gpt-5.4-mini`

- **Purpose:** Reads each 500-token chunk and extracts structured entities conforming to a Pydantic schema
- **Structured output:** Pydantic v2 `ExtractionOutput` model enforces schema compliance — the LLM cannot hallucinate outside the defined types
- **Schema (v3):**
  - `LegalTopic.name` is a `Literal[30 values]` — controlled vocabulary prevents free-form topic explosion (1,278 → 30 topics)
  - `Counsel.name` strips trailing ` KC`/` QC` (KC status captured separately in `isKc: bool`)
  - `LawFirm.name` applies alias map (e.g. `"Quinn Emanuel"` → `"Quinn Emanuel Urquhart & Sullivan UK LLP"`)
  - `Judgment.neutralCitation` normalises format variants → `[YYYY] EWHC N (Comm)`
- **Parallelism:** 50 concurrent extraction calls → 891 chunks processed in ~100 seconds
- **Cost estimate:** ~$0.15–0.25 per full extraction pass

#### Embeddings: `text-embedding-3-small`

- **Purpose:** Creates 1536-dimensional vector for each chunk for semantic similarity search
- **Context enrichment:** Each chunk is embedded as `documentName + sectionContext + chunkText` — the document name is prepended so "Vernon Flynn KC" in chunk 47 of `ewhc_comm_2026_456` is semantically closer to other chunks from that case
- **Vector index:** `chunk_text_embedding` with `documentName` and `type` prefilter properties (Neo4j 5.18+ `WITH [...]` syntax) — enables filtered vector search without post-filtering overhead
- **Fulltext index:** `chunk_text_fulltext` (Lucene) created alongside vector index for hybrid BM25 + semantic retrieval

### 3.3 Graph RAG Architecture

```
User Question
      │
      ├─── Structured query? ──► Cypher traversal (exact, multi-hop)
      │    (who, which, how many)
      │
      ├─── Semantic query? ────► Vector search (top-k chunks by cosine similarity)
      │    (what happened, why)
      │
      └─── Hybrid? ─────────────► Graph context + Vector passage
           (explain + evidence)   e.g. node properties + chunk text
```

**Why graph beats pure vector RAG for this use case:**

| Query pattern                                      | Pure vector                              | Graph RAG                             |
| -------------------------------------------------- | ---------------------------------------- | ------------------------------------- |
| "Has Quinn Emanuel acted on both sides?"           | ❌ Requires reading every mention        | ✅ Single`MATCH` traversal          |
| "Which firms instructed on sovereign-state cases?" | ❌ Relation not in text structure        | ✅`HAS_DEFENDANT_FIRM` relationship |
| "Which barristers appeared together most?"         | ❌ Cross-document aggregation impossible | ✅ Path query +`count()`            |
| "What did the judge say about jurisdiction?"       | ✅ Semantic similarity works             | ✅ Also works + structured context    |

### 3.4 Neo4j Configuration

- **Database:** Neo4j local (bolt://127.0.0.1:7687) or Aura Free
- **Version:** 5.18+ required for vector index prefilter syntax
- **Indexes created automatically:**
  - `chunk_text_embedding` — VECTOR index on `Chunk.text_embedding` (1536d, ==cosine==)
  - `chunk_text_fulltext` — FULLTEXT index on `Chunk.text`
- **Constraints implied by MERGE:** All entity nodes MERGE on key property (`name`, `neutralCitation`)

---

## 4. Graph Data Model

```
                    ┌──────────────┐
                    │   Document   │
                    └──────┬───────┘
                           │ PART_OF
                    ┌──────▼───────┐
                    │    Chunk     │◄──── EXTRACTED_FROM ──── [all entities]
                    │ (embedded)   │
                    └──────────────┘

          ┌──────────────────────────────────────────────────┐
          │                  Judgment                        │
          │  neutralCitation · caseName · date · outcome     │
          └─┬──────┬─────────┬──────┬──────┬────────┬───────┘
            │      │         │      │      │        │
   PRESIDED_BY  HAS_CLAIMANT  HAS_DEFENDANT  CONCERNS  CITES
            │      │         │      │      │        │
            ▼      ▼         ▼      │      ▼        ▼
          Judge  Party     Party  Legal  Topic   Legislation
                               Topic   (30)    (135 · URL)
                                      
   HAS_CLAIMANT_COUNSEL ─────► Counsel ◄─── HAS_DEFENDANT_COUNSEL
   HAS_CLAIMANT_FIRM ──────►  LawFirm ◄──── HAS_DEFENDANT_FIRM
                                │                  │
                           chambers            firmType
                           kcYear              arbitrationTier
                           callYear            foundedYear
                           specialisms         legal500
```

### Entity counts (corpus: 20 EWHC Commercial Court 2026 judgments)

| Entity      | Count        | Notes                                          |
| ----------- | ------------ | ---------------------------------------------- |
| Document    | 20           | Primary judgments                              |
| Chunk       | 891          | ~500 tokens each, all embedded                 |
| Judgment    | 28           | 20 primary [2026] EWHC N (Comm) + 8 cited      |
| Counsel     | 86           | 30 enriched with chambers; 56 from cited cases |
| LawFirm     | 39           | 38 enriched with firm_type + tier              |
| Party       | 261          | Includes cited-case parties                    |
| LegalTopic  | **30** | Controlled vocabulary (Literal constraint)     |
| Legislation | 135          | Enriched with legislation.gov.uk URLs          |
| Judge       | 58           |                                                |

---

## 5. Demo Script — 5 Target Questions

> **Setup:** Open Neo4j Bloom or run `claude` from the workspace directory. All answers below are executed via `read_neo4j_cypher` from `neo4j-graphrag`.

---

### Q1. Which law firms have acted for sovereign states resisting enforcement of arbitral awards, and have any of them also appeared on the claimant side?

**Cypher:**

```cypher
MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'republic' OR toLower(p.name) CONTAINS 'federation'
   OR toLower(p.name) CONTAINS 'kingdom' OR p.partyType CONTAINS 'sovereign'
MATCH (j)-[:HAS_DEFENDANT_FIRM]->(f:LawFirm)
WITH f.name AS firm, collect(DISTINCT j.neutralCitation) AS defendantCases
OPTIONAL MATCH (j2:Judgment)-[:HAS_CLAIMANT_FIRM]->(f2:LawFirm {name: firm})
RETURN firm, size(defendantCases) AS defended, collect(DISTINCT j2.neutralCitation) AS alsoClaimant
ORDER BY defended DESC
```

**Expected answer:** 7 firms acted for sovereign state defendants. **Gibson Dunn & Crutcher LLP** and **Quinn Emanuel Urquhart & Sullivan UK LLP** both appear on the claimant side in other proceedings — demonstrating they are not exclusive to either side.

**Why graph wins:** "Which side did this firm appear on in comparable cases?" requires traversing `LawFirm → Judgment → Party` twice — impossible with vector search alone.

---

### Q2. Who appeared for the Russian Federation across its cases before the Commercial Court, and what was the outcome in each matter?

**Cypher:**

```cypher
MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'russian' OR toLower(p.name) CONTAINS 'russia'
OPTIONAL MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(dc:Counsel)
OPTIONAL MATCH (j)-[:HAS_DEFENDANT_FIRM]->(df:LawFirm)
OPTIONAL MATCH (j)-[:HAS_CLAIMANT_COUNSEL]->(cc:Counsel)
RETURN j.neutralCitation, j.caseName, j.outcome,
       collect(DISTINCT dc.name) AS defCounsel,
       collect(DISTINCT df.name) AS defFirms,
       collect(DISTINCT cc.name) AS claimantCounsel
```

**Expected answer:** **Vernon Flynn KC** (Pinna Goldberg Ltd) led the Russian Federation's defence in **Hulley v Russian Federation [2026] EWHC 456 (Comm)** across multiple hearings. Claimants instructed **Jonathan Crow CVO KC** (Stephenson Harwood LLP). Enforcement was ultimately allowed — public policy and jurisdiction challenges failed.

---

### Q3. If I'm instructing counsel for a state client challenging an award on jurisdictional grounds, which barristers have the most experience on that side of these disputes?

**Cypher:**

```cypher
MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'republic' OR toLower(p.name) CONTAINS 'federation'
   OR toLower(p.name) CONTAINS 'kingdom'
MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(c:Counsel)
MATCH (j)-[:CONCERNS]->(t:LegalTopic)
WHERE toLower(t.name) CONTAINS 'jurisdict'
RETURN c.name AS barrister, c.chambers AS chambers, c.isKc AS kc, c.kcYear AS kcYear,
       count(DISTINCT j) AS caseCount,
       collect(DISTINCT t.name) AS jurisdictionTopics
ORDER BY caseCount DESC
```

**Expected answer:**

1. **Vernon Flynn KC** (Brick Court, KC since 2006) — 5 appearances in Hulley/Russia proceedings
2. **Constantine Partasides KC** (Three Crowns, KC since 2013) — Republic of Korea, ECT
3. **Samuel Wordsworth KC** (Essex Court, KC since 2009) — ECT investment treaty
4. **Ruth Byrne KC** / **Tom Sprange KC** (Essex Court) — s.45 jurisdiction challenge

---

### Q4. Has Quinn Emanuel ever acted against a sovereign state respondent, or do they consistently act for one side in these enforcement proceedings?

**Cypher:**

```cypher
MATCH (j:Judgment)-[r:HAS_CLAIMANT_FIRM|HAS_DEFENDANT_FIRM]->(f:LawFirm)
WHERE toLower(f.name) CONTAINS 'quinn'
OPTIONAL MATCH (j)-[:HAS_CLAIMANT]->(cp:Party)
OPTIONAL MATCH (j)-[:HAS_DEFENDANT]->(dp:Party)
RETURN j.neutralCitation, j.caseName, j.outcome,
       type(r) AS side,
       collect(DISTINCT cp.name) AS claimants,
       collect(DISTINCT dp.name) AS defendants
```

**Expected answer:** Quinn Emanuel appeared on **both sides**:

- [2026] EWHC 1003 — **claimant side** (GE against Kurdistan Regional Government)
- [2026] EWHC 418 — **defendant side** (Republic of Djibouti against Soprim)

They do not consistently act for one side.

---

### Q5. Which barristers appeared in cases involving the Energy Charter Treaty, and which firms instructed them?

**Cypher:**

```cypher
MATCH (j:Judgment)-[:CITES]->(l:Legislation)
WHERE toLower(l.name) CONTAINS 'energy charter'
OPTIONAL MATCH (j)-[:HAS_CLAIMANT_COUNSEL]->(cc:Counsel)
OPTIONAL MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(dc:Counsel)
OPTIONAL MATCH (j)-[:HAS_CLAIMANT_FIRM]->(cf:LawFirm)
OPTIONAL MATCH (j)-[:HAS_DEFENDANT_FIRM]->(df:LawFirm)
RETURN j.neutralCitation, j.caseName, j.outcome,
       collect(DISTINCT cc.name) AS claimantCounsel,
       collect(DISTINCT cf.name) AS claimantFirms,
       collect(DISTINCT dc.name) AS defendantCounsel,
       collect(DISTINCT df.name) AS defendantFirms
```

**Expected answer:**

**[2026] EWHC 368 (Comm) — Republic of Korea v Elliott Associates, LP**

- Korea (claimant/s.67 challenger): **Samuel Wordsworth KC**, Peter Webster, Richard Hoyle → Arnold & Porter Kaye Scholer (UK) LLP
- Elliott (defendant): **Constantine Partasides KC**, Georgios Petrochilos, Andrew Stafford → Three Crowns LLP + Kobre & Kim (UK) LLP
- Outcome: Korea's s.67 challenge succeeded in part — Award set aside in part, causation remitted

**[2026] EWHC 456 (Comm) — Hulley v Russian Federation**

- Claimants: Jonathan Crow CVO KC → Stephenson Harwood LLP
- Russia: Vernon Flynn KC → Pinna Goldberg Ltd
- Outcome: Enforcement allowed (public policy defence failed)

---

## 6. Complex Graph Traversal Queries

These require multi-hop traversal or structured+CSV data joins — impossible with pure vector search.

### Q6. Chambers concentration across the corpus

```cypher
MATCH (c:Counsel)<-[:HAS_CLAIMANT_COUNSEL|HAS_DEFENDANT_COUNSEL]-(j:Judgment)
WHERE c.chambers IS NOT NULL
RETURN c.chambers AS chambers,
       count(CASE WHEN EXISTS { (j)-[:HAS_CLAIMANT_COUNSEL]->(c) } THEN 1 END) AS claimantApps,
       count(CASE WHEN EXISTS { (j)-[:HAS_DEFENDANT_COUNSEL]->(c) } THEN 1 END) AS defendantApps
ORDER BY claimantApps + defendantApps DESC
```

**Finding:** Essex Court Chambers leads with 9 appearances across both sides. Three Crowns LLP appears exclusively for defendants — consistent with their investment-treaty defence specialisation.

---

### Q7. Firm tier vs outcome in investment treaty arbitration

```cypher
MATCH (j:Judgment)-[:CONCERNS]->(t:LegalTopic {name: 'investment treaty arbitration'})
MATCH (j)-[:HAS_CLAIMANT_FIRM]->(cf:LawFirm)
MATCH (j)-[:HAS_DEFENDANT_FIRM]->(df:LawFirm)
RETURN j.neutralCitation, j.outcome,
       cf.name AS claimantFirm, cf.arbitrationTier AS claimantTier,
       df.name AS defendantFirm, df.arbitrationTier AS defendantTier
```

**Finding:** In the Korea v Elliott case, the Tier 1 boutique (Three Crowns) won for the defendant over a Tier 2 US firm (Arnold & Porter) — consistent with the specialisation advantage of boutiques in investment treaty work.

---

### Q8. KC seniority at time of sovereign-state enforcement hearings

```cypher
MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'republic' OR toLower(p.name) CONTAINS 'federation'
MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(c:Counsel)
WHERE c.kcYear IS NOT NULL AND c.kcYear > 0 AND c.kcYear < 2015
RETURN c.name, c.chambers, c.kcYear,
       collect(DISTINCT j.neutralCitation) AS cases,
       collect(DISTINCT p.name) AS sovereignParties
ORDER BY c.kcYear
```

**Finding:** Both senior silks defending sovereign states — Vernon Flynn KC (Brick Court, KC 2006) and Constantine Partasides KC (Three Crowns, KC 2013) — were appointed silk well before the 2026 hearings, bringing 12–20 years of KC-level practice to the cases.

---

### Q9. Standing team detection — who appears together?

```cypher
MATCH (j:Judgment)-[:HAS_DEFENDANT_COUNSEL]->(c1:Counsel)
MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(c2:Counsel)
WHERE c1.name < c2.name
WITH c1.name AS counsel1, c1.chambers AS ch1,
     c2.name AS counsel2, c2.chambers AS ch2,
     collect(DISTINCT j.neutralCitation) AS sharedCases
WHERE size(sharedCases) > 1
RETURN counsel1, ch1, counsel2, ch2, sharedCases
ORDER BY size(sharedCases) DESC
```

**Finding:** Charles Béar KC + Diya Sen Gupta KC (both Fountain Court) appear together on the defendant side across multiple cases — the standing team referenced in the demo transcript.

---

### Q10. Conflict check for new mandate

```cypher
// Find claimant-side counsel with ECT/ICSID experience, not already in opposing teams
MATCH (j:Judgment)-[:CONCERNS]->(t:LegalTopic)
WHERE t.name IN ['investment treaty arbitration', 'energy charter treaty', 'arbitral award enforcement']
MATCH (j)-[:HAS_CLAIMANT_COUNSEL]->(c:Counsel)
WHERE c.isKc = true AND c.chambers IS NOT NULL
WITH c, collect(DISTINCT j.neutralCitation) AS claimantCases
// Conflict check: same counsel has NOT appeared for defendants in ANY judgment
WHERE NOT EXISTS {
  MATCH (j2:Judgment)-[:HAS_DEFENDANT_COUNSEL]->(c)
  WHERE j2.neutralCitation IN claimantCases
}
RETURN c.name AS counsel, c.chambers AS chambers, c.kcYear AS kcYear,
       c.specialisms AS specialisms, claimantCases
ORDER BY size(claimantCases) DESC
```

---

## 7. Pipeline Reproducibility

### Prerequisites

```bash
# 1. Clone and setup
git clone https://github.com/neo4j-field/neo4j-mcp-workspace-template
cd neo4j-mcp-workspace-template
./setup.sh   # prompts for Neo4j URI, credentials, OpenAI key

# 2. Start Claude Code (loads all 5 MCP servers)
claude

# 3. Run the skill
/develop-neo4j-graph
```

### Expected timings (20 documents, M2 Mac or similar)

| Step                   | Tool                               | Time             |
| ---------------------- | ---------------------------------- | ---------------- |
| PDF parsing + chunking | `create_lexical_graph` (pymupdf) | ~83s             |
| Embedding 891 chunks   | `embed_chunks` (parallel=50)     | ~20s             |
| Entity extraction      | `extract_entities` (parallel=50) | ~100s            |
| CSV enrichment         | `ingest_csv_into_neo4j` × 3     | ~5s              |
| **Total**        |                                    | **~4 min** |

### MCP server startup (after venv warmup)

Local venvs on Google Drive (FUSE): ~120s cold start → fixed by `UV_PROJECT_ENVIRONMENT` to local `C:\neo4j-venvs\*` → **~14s** warm start.

See [`.mcp.json`](../.mcp.json) for the `env` block configuration.

---

## 8. Known Iteration Points

| Priority  | Item                                                            | Action                                                           |
| --------- | --------------------------------------------------------------- | ---------------------------------------------------------------- |
| 🔴 High   | XML legislation linkage (Pedro's`legal-legislation-explorer`) | Adds`Section` nodes → enables section-level citation queries  |
| 🔴 High   | Expand corpus to 100–500 judgments                             | Statistical patterns become reliable; team patterns emerge       |
| 🟡 Medium | Remove`costs` from LegalTopic Literal (too general)           | Add`s.67 challenge` as explicit canonical term                 |
| 🟡 Medium | `Party.partyType` normalisation                               | Reduce 261 Party nodes toward 98 target; filter cited-case noise |
| 🟢 Low    | `Judge.seniority` from judicial register CSV                  | Enables judge-pattern queries (promotion timeline, division)     |
| 🟢 Low    | Resolve`Mr Wright` ambiguity (Alexander vs Paul)              | 1 node — minor                                                  |

---

## Outputs Reference

| File                                                      | Description                                           |
| --------------------------------------------------------- | ----------------------------------------------------- |
| `outputs/data_models/opposing_counsel_data_model.json`  | Validated graph data model (7 nodes, 9 relationships) |
| `outputs/schemas/opposing_counsel_schema.py`            | Pydantic extraction schema v3 with validators         |
| `outputs/reports/opposing_counsel_chatbot_report.md`    | Full Q&A report with Cypher answers                   |
| `outputs/reports/opposing_counsel_complex_questions.md` | 10 complex traversal questions                        |
| `outputs/reports/opposing_counsel_anomaly_report.md`    | Data quality audit                                    |
| `outputs/opposing_counsel_architecture.excalidraw`      | Architecture diagram (open at excalidraw.com)         |
| `data/csv/barristers.csv`                               | 30 barristers with chambers, KC year, specialisms     |
| `data/csv/law_firms.csv`                                | 39 firms with type, tier, founding year               |
| `data/csv/legislation.csv`                              | 18 statutes/treaties with legislation.gov.uk URLs     |
