// ============================================================
// OPA Authorization Policy — Graph Intelligence Queries
// Corpus: 10 OPA (Open Policy Agent) documentation Markdown files
// Graph:  PolicyModule · Rule · Concept · ResourceType
//         Document · Chunk
// Demo:   Securitas Intelligent Services AB — Document
//         Intelligence, July 1 2026 (demo/securitas-opa/)
// Source: demo/securitas-opa/demo-questions.md
// ============================================================

// ------------------------------------------------------------
// SECTION 1: TIER 1 — AURA DOCUMENT INTELLIGENCE (auto-schema)
// ------------------------------------------------------------

// Show the auto-detected schema after uploading the Markdown
// corpus via the Aura DI console. Run in Aura Explore.
CALL db.schema.visualization();

// ────────────────────────────────────────────────────────────

// The lexical layer — every document is chunked and searchable
// by keyword. Shows which documents contain both 'role' and
// 'allow' without any entity extraction.
MATCH (d:Document)<-[:PART_OF]-(c:Chunk)
WHERE c.text CONTAINS 'role' AND c.text CONTAINS 'allow'
RETURN d.name AS document, count(c) AS relevant_chunks
ORDER BY relevant_chunks DESC
LIMIT 10;

// ============================================================
// SECTION 2: TIER 2 — RELATIONSHIP TRAVERSAL (Round 1, 7 min)
// ============================================================

// Q1. "What are the most important concepts across all the
//     authorization documentation?"
// The opening query — the conceptual fingerprint of the whole
// corpus. No keyword search returns a ranked concept breadth.

MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WITH c, count(DISTINCT pm) AS breadth
ORDER BY breadth DESC LIMIT 10
RETURN c.name AS concept, c.category AS category, breadth AS referenced_by_n_modules;

// ────────────────────────────────────────────────────────────

// Q2. "Which modules handle JWT authentication, and what rules
//     do they define?"
// Two-hop query that structurally separates authentication
// (token validation) from authorisation (allow/deny decisions).
// The anchor query of the demo — compare 'oidc' (jwks, issuers,
// metadata_discovery = validation) vs 'example-jwt.rego'
// (allow, user_owns_token = authorisation).

MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WHERE toLower(c.name) CONTAINS 'jwt' OR toLower(c.name) CONTAINS 'json web token'
WITH pm, collect(DISTINCT c.name)[0..3] AS auth_concepts
MATCH (pm)-[:CONTAINS]->(r:Rule)
WITH pm.name AS module, auth_concepts, collect(DISTINCT r.name)[0..5] AS rules
RETURN module, auth_concepts, rules
ORDER BY size(rules) DESC
LIMIT 8;

// ────────────────────────────────────────────────────────────

// Q3. "Which rules depend on other rules to reach their
//     decision?"
// Variable-length path traversal — the policy dependency graph
// and the basis for impact analysis ("if I change this rule,
// what else does it affect?").

MATCH path = (r:Rule)-[:DEPENDS_ON*1..3]->(dep:Rule)
WHERE r.name <> dep.name
RETURN r.name AS rule, [n IN nodes(path) | n.name] AS dependency_chain
LIMIT 20;

// ============================================================
// SECTION 3: TIER 2 — SEMANTIC + HYBRID QUERIES (Round 2, 5 min)
// ============================================================

// Q4. "What concepts does each area of the documentation
//     introduce?" (Hybrid GraphRAG)
// Pair with a vector search first to show the lexical/semantic
// layer, e.g. via the neo4j-graphrag MCP tool:
//   vector_search: "authentication versus authorisation
//   separation of concerns"
// Then run the graph traversal over the entity layer:

MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WHERE pm.name IN ['http-api-authorization','kafka-authorization','security',
                  'kubernetes-primer','policy-language']
RETURN pm.name AS source_doc,
       collect(DISTINCT c.name)[0..6] AS top_concepts,
       count(DISTINCT c) AS total_concepts
ORDER BY total_concepts DESC;

// ────────────────────────────────────────────────────────────

// Q5. "What security concepts does the security documentation
//     cover?"
// Distinguishes the protocol layer (TLS, HTTPS, CA cert) from
// the access-model layer (authentication, authorization) via
// the category property set during entity extraction.

MATCH (pm:PolicyModule {name: "security"})-[:REFERENCES]->(c:Concept)
RETURN c.name AS concept, c.category AS category
ORDER BY c.category, c.name;

// ============================================================
// SECTION 4: ANALOGY CLOSE — BACKUP QUERY (Round 3, 3 min)
// ============================================================

// Killer backup query — the full authorization taxonomy.
// 177 policy constructs, 30 protocol concepts, 21 access-model
// concepts — the entire authorization vocabulary of the corpus,
// structured and queryable, extracted automatically.

MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept)
WITH c.category AS category,
     count(DISTINCT c) AS unique_concepts,
     count(DISTINCT pm) AS modules_using,
     collect(DISTINCT c.name)[0..4] AS examples
RETURN category, unique_concepts, modules_using, examples
ORDER BY modules_using DESC;
