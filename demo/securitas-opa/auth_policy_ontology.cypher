// ── Authorization Policy Ontology — Securitas Demo ───────────────────────────
//
// Use case: OPA documentation corpus ingested as Markdown → knowledge graph.
// This ontology mirrors the conceptual graph that Securitas's own platform
// documentation would produce if ingested via Neo4j Document Intelligence.
//
// The ontology extracts:
//   - PolicyModule    — an OPA policy file / package
//   - Rule            — an individual rule (allow, deny, etc.)
//   - Concept         — high-level authorization concepts (RBAC, JWT, ABAC, etc.)
//   - ResourceType    — types of resources being governed
//
// Relationships:
//   - (PolicyModule)-[:CONTAINS]->(Rule)
//   - (PolicyModule)-[:REFERENCES]->(Concept)
//   - (Rule)-[:GOVERNS]->(ResourceType)
//   - (Rule)-[:DEPENDS_ON]->(Rule)
//
// Demo questions enabled by this graph:
//   Q1: "Which policy modules reference RBAC concepts?"
//       MATCH (pm:PolicyModule)-[:REFERENCES]->(c:Concept {name: "RBAC"}) RETURN pm.name
//   Q2: "What resource types does the 'allow' rule govern?"
//       MATCH (r:Rule {name: "allow"})-[:GOVERNS]->(rt:ResourceType) RETURN rt.name
//   Q3: "Show all dependencies of the entitlements rule hierarchy"
//       MATCH path = (r:Rule)-[:DEPENDS_ON*1..3]->(dep:Rule) RETURN path LIMIT 25
//   Q4: "Which concepts appear in the security documentation?"
//       MATCH (pm:PolicyModule {name: "security"})-[:REFERENCES]->(c) RETURN c.name
//
// Run against the Ontology DB AFTER calling setup_ontology_db().
// Statements are self-contained (each MERGE re-binds via name lookup).
// ─────────────────────────────────────────────────────────────────────────────

// ── Ontology root ─────────────────────────────────────────────────────────────
MERGE (o:Ontology {name: "opa_auth_policy"})
SET o.description = "OPA authorization policy concepts — mirrors Securitas platform documentation graph",
    o.version = "v1",
    o.created_at = datetime();

// ── NodeType: PolicyModule ────────────────────────────────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MERGE (pm:NodeType {name: "PolicyModule"})
SET pm.description = "An OPA policy module, file, or package containing authorization rules"
MERGE (o)-[:CONTAINS]->(pm);

MATCH (pm:NodeType {name: "PolicyModule"})
MERGE (pm)-[:HAS_PROPERTY]->(pd:PropertyDef {name: "name"})
SET pd.type = "STRING",
    pd.description = "Module name or package path (e.g. 'authz.rbac', 'data.allow'). Extract only if explicitly named in the text.",
    pd.required = true,
    pd.is_key = true,
    pd.normalizer = "lowercase";

MATCH (pm:NodeType {name: "PolicyModule"})
MERGE (pm)-[:HAS_PROPERTY]->(pd2:PropertyDef {name: "packageName"})
SET pd2.type = "STRING",
    pd2.description = "OPA package declaration (e.g. 'package authz', 'package httpapi.authz'). Extract the package string literally.";

MATCH (pm:NodeType {name: "PolicyModule"})
MERGE (pm)-[:HAS_PROPERTY]->(pd3:PropertyDef {name: "purpose"})
SET pd3.type = "STRING",
    pd3.description = "Brief purpose of this policy module in one sentence.";

// ── NodeType: Rule ────────────────────────────────────────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MERGE (rule:NodeType {name: "Rule"})
SET rule.description = "An individual OPA rule definition (allow, deny, is_admin, permit, etc.)"
MERGE (o)-[:CONTAINS]->(rule);

MATCH (rule:NodeType {name: "Rule"})
MERGE (rule)-[:HAS_PROPERTY]->(pd:PropertyDef {name: "name"})
SET pd.type = "STRING",
    pd.description = "Rule name as it appears in the policy (e.g. 'allow', 'deny', 'is_admin', 'permit')",
    pd.required = true,
    pd.is_key = true,
    pd.normalizer = "lowercase";

MATCH (rule:NodeType {name: "Rule"})
MERGE (rule)-[:HAS_PROPERTY]->(pd2:PropertyDef {name: "effect"})
SET pd2.type = "STRING",
    pd2.description = "Effect of the rule: 'allow', 'deny', or 'derived' (for helper rules that feed into allow/deny)",
    pd2.normalizer = "enum_validate",
    pd2.enum_values = ["allow", "deny", "derived"];

MATCH (rule:NodeType {name: "Rule"})
MERGE (rule)-[:HAS_PROPERTY]->(pd3:PropertyDef {name: "isDefault"})
SET pd3.type = "STRING",
    pd3.description = "Whether this is a default rule ('true' for default allow := false or default deny := true). Extract 'true' or 'false' as string.";

// ── NodeType: Concept ─────────────────────────────────────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MERGE (concept:NodeType {name: "Concept"})
SET concept.description = "A high-level authorization or policy concept mentioned in the documentation"
MERGE (o)-[:CONTAINS]->(concept);

MATCH (concept:NodeType {name: "Concept"})
MERGE (concept)-[:HAS_PROPERTY]->(pd:PropertyDef {name: "name"})
SET pd.type = "STRING",
    pd.description = "Concept name. Examples: 'RBAC', 'ABAC', 'JWT', 'OPA Bundle', 'Decision Log', 'Rego', 'data.allow', 'input.user', 'mTLS'. Extract as found — normalize whitespace only.",
    pd.required = true,
    pd.is_key = true,
    pd.normalizer = "whitespace";

MATCH (concept:NodeType {name: "Concept"})
MERGE (concept)-[:HAS_PROPERTY]->(pd2:PropertyDef {name: "category"})
SET pd2.type = "STRING",
    pd2.description = "Category of this concept: 'access_model', 'policy_construct', 'data_type', 'infrastructure', or 'protocol'",
    pd2.normalizer = "enum_validate",
    pd2.enum_values = ["access_model", "policy_construct", "data_type", "infrastructure", "protocol"];

// ── NodeType: ResourceType ────────────────────────────────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MERGE (rt:NodeType {name: "ResourceType"})
SET rt.description = "A type of resource being governed by authorization policies"
MERGE (o)-[:CONTAINS]->(rt);

MATCH (rt:NodeType {name: "ResourceType"})
MERGE (rt)-[:HAS_PROPERTY]->(pd:PropertyDef {name: "name"})
SET pd.type = "STRING",
    pd.description = "Resource type name. Examples: 'API endpoint', 'Kubernetes resource', 'HTTP request', 'database', 'file', 'service account', 'namespace'. Extract only if explicitly referenced as a governed resource.",
    pd.required = true,
    pd.is_key = true,
    pd.normalizer = "lowercase";

// ── RelationshipType: CONTAINS (PolicyModule → Rule) ─────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MATCH (pm:NodeType {name: "PolicyModule"})
MATCH (rule:NodeType {name: "Rule"})
MERGE (rt_contains:RelationshipType {name: "CONTAINS"})
SET rt_contains.description = "This policy module contains or defines this rule"
MERGE (o)-[:CONTAINS]->(rt_contains)
MERGE (rt_contains)-[:FROM]->(pm)
MERGE (rt_contains)-[:TO]->(rule);

// ── RelationshipType: REFERENCES (PolicyModule → Concept) ────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MATCH (pm:NodeType {name: "PolicyModule"})
MATCH (concept:NodeType {name: "Concept"})
MERGE (rt_refs:RelationshipType {name: "REFERENCES"})
SET rt_refs.description = "This policy module or documentation section references or implements this concept"
MERGE (o)-[:CONTAINS]->(rt_refs)
MERGE (rt_refs)-[:FROM]->(pm)
MERGE (rt_refs)-[:TO]->(concept);

// ── RelationshipType: GOVERNS (Rule → ResourceType) ──────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MATCH (rule:NodeType {name: "Rule"})
MATCH (resource:NodeType {name: "ResourceType"})
MERGE (rt_governs:RelationshipType {name: "GOVERNS"})
SET rt_governs.description = "This rule controls or governs access to this type of resource"
MERGE (o)-[:CONTAINS]->(rt_governs)
MERGE (rt_governs)-[:FROM]->(rule)
MERGE (rt_governs)-[:TO]->(resource);

// ── RelationshipType: DEPENDS_ON (Rule → Rule) ───────────────────────────────
MATCH (o:Ontology {name: "opa_auth_policy"})
MATCH (rule:NodeType {name: "Rule"})
MERGE (rt_dep:RelationshipType {name: "DEPENDS_ON"})
SET rt_dep.description = "This rule references, calls, or builds upon another rule to produce its decision"
MERGE (o)-[:CONTAINS]->(rt_dep)
MERGE (rt_dep)-[:FROM]->(rule)
MERGE (rt_dep)-[:TO]->(rule);
