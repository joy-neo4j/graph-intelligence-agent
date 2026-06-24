// ============================================================
// Opposing Counsel — Graph Intelligence Queries
// Corpus: 20 EWHC Commercial Court judgments (2026)
// Graph:  Judgment · Counsel · LawFirm · Party · LegalTopic
//         Legislation · Judge · Document · Chunk
// ============================================================

// ------------------------------------------------------------
// SECTION 1: DEMO SCRIPT — 5 TARGET QUESTIONS
// ------------------------------------------------------------

// Q1. Which law firms have acted for sovereign states resisting
//     enforcement of arbitral awards, and have any also appeared
//     on the claimant side?
// Traversal: LawFirm → Judgment → Party (sovereign defendant)
//            + cross-check HAS_CLAIMANT_FIRM for same firm

MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'republic' OR toLower(p.name) CONTAINS 'federation'
   OR toLower(p.name) CONTAINS 'kingdom' OR p.partyType CONTAINS 'sovereign'
MATCH (j)-[:HAS_DEFENDANT_FIRM]->(f:LawFirm)
WITH f.name AS firm, collect(DISTINCT j.neutralCitation) AS defendantCases
OPTIONAL MATCH (j2:Judgment)-[:HAS_CLAIMANT_FIRM]->(f2:LawFirm {name: firm})
RETURN firm, size(defendantCases) AS defended, collect(DISTINCT j2.neutralCitation) AS alsoClaimant
ORDER BY defended DESC;

// ────────────────────────────────────────────────────────────

// Q2. Who appeared for the Russian Federation across its cases
//     before the Commercial Court, and what was the outcome?
// Traversal: Party (Russia) ← Judgment → Counsel + LawFirm (both sides)

MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'russian' OR toLower(p.name) CONTAINS 'russia'
OPTIONAL MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(dc:Counsel)
OPTIONAL MATCH (j)-[:HAS_DEFENDANT_FIRM]->(df:LawFirm)
OPTIONAL MATCH (j)-[:HAS_CLAIMANT_COUNSEL]->(cc:Counsel)
RETURN j.neutralCitation, j.caseName, j.outcome,
       collect(DISTINCT dc.name) AS defCounsel,
       collect(DISTINCT df.name) AS defFirms,
       collect(DISTINCT cc.name) AS claimantCounsel;

// ────────────────────────────────────────────────────────────

// Q3. For a state client challenging an award on jurisdictional
//     grounds — which barristers have the most experience on that
//     defence side? (requires CSV-enriched chambers + kcYear)
// Traversal: Party (sovereign) ← Judgment → Counsel ← LegalTopic (jurisdiction)

MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'republic' OR toLower(p.name) CONTAINS 'federation'
   OR toLower(p.name) CONTAINS 'kingdom'
MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(c:Counsel)
MATCH (j)-[:CONCERNS]->(t:LegalTopic)
WHERE toLower(t.name) CONTAINS 'jurisdict'
RETURN c.name AS barrister, c.chambers AS chambers, c.isKc AS kc, c.kcYear AS kcYear,
       count(DISTINCT j) AS caseCount,
       collect(DISTINCT t.name) AS jurisdictionTopics
ORDER BY caseCount DESC;

// ────────────────────────────────────────────────────────────

// Q4. Has Quinn Emanuel ever acted against a sovereign state
//     respondent, or do they consistently act for one side?
// Traversal: LawFirm (Quinn Emanuel) → Judgment → Party (both sides)

MATCH (j:Judgment)-[r:HAS_CLAIMANT_FIRM|HAS_DEFENDANT_FIRM]->(f:LawFirm)
WHERE toLower(f.name) CONTAINS 'quinn'
OPTIONAL MATCH (j)-[:HAS_CLAIMANT]->(cp:Party)
OPTIONAL MATCH (j)-[:HAS_DEFENDANT]->(dp:Party)
RETURN j.neutralCitation, j.caseName, j.outcome,
       type(r) AS side,
       collect(DISTINCT cp.name) AS claimants,
       collect(DISTINCT dp.name) AS defendants;

// ────────────────────────────────────────────────────────────

// Q5. Which barristers appeared in cases involving the Energy
//     Charter Treaty, and which firms instructed them?
// Traversal: Legislation (ECT) ← Judgment → Counsel + LawFirm (both sides)

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
       collect(DISTINCT df.name) AS defendantFirms;

// ============================================================
// SECTION 2: COMPLEX GRAPH TRAVERSAL QUERIES
// ============================================================

// Q6. Chambers concentration — appearances per chambers, split by side
//     Requires: CSV-enriched Counsel.chambers
// Pattern: Counsel ← HAS_CLAIMANT_COUNSEL/HAS_DEFENDANT_COUNSEL ← Judgment

MATCH (c:Counsel)<-[:HAS_CLAIMANT_COUNSEL|HAS_DEFENDANT_COUNSEL]-(j:Judgment)
WHERE c.chambers IS NOT NULL
RETURN c.chambers AS chambers,
       count(CASE WHEN EXISTS { (j)-[:HAS_CLAIMANT_COUNSEL]->(c) } THEN 1 END) AS claimantApps,
       count(CASE WHEN EXISTS { (j)-[:HAS_DEFENDANT_COUNSEL]->(c) } THEN 1 END) AS defendantApps
ORDER BY claimantApps + defendantApps DESC;

// ────────────────────────────────────────────────────────────

// Q7. Firm tier vs outcome in investment treaty arbitration
//     Requires: CSV-enriched LawFirm.arbitrationTier
// Pattern: LegalTopic ← Judgment → LawFirm (both sides, with tier)

MATCH (j:Judgment)-[:CONCERNS]->(t:LegalTopic {name: 'investment treaty arbitration'})
MATCH (j)-[:HAS_CLAIMANT_FIRM]->(cf:LawFirm)
MATCH (j)-[:HAS_DEFENDANT_FIRM]->(df:LawFirm)
RETURN j.neutralCitation, j.outcome,
       cf.name AS claimantFirm, cf.arbitrationTier AS claimantTier,
       df.name AS defendantFirm, df.arbitrationTier AS defendantTier;

// ────────────────────────────────────────────────────────────

// Q8. KC seniority at time of sovereign-state enforcement hearings
//     Requires: CSV-enriched Counsel.kcYear
// Pattern: Party (sovereign) ← Judgment → Counsel (KC before 2015)

MATCH (j:Judgment)-[:HAS_DEFENDANT]->(p:Party)
WHERE toLower(p.name) CONTAINS 'republic' OR toLower(p.name) CONTAINS 'federation'
MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(c:Counsel)
WHERE c.kcYear IS NOT NULL AND c.kcYear > 0 AND c.kcYear < 2015
RETURN c.name, c.chambers, c.kcYear,
       collect(DISTINCT j.neutralCitation) AS cases,
       collect(DISTINCT p.name) AS sovereignParties
ORDER BY c.kcYear;

// ────────────────────────────────────────────────────────────

// Q9. Standing team detection — which barristers appear together
//     on the defence side more than once?
// Pattern: Counsel1 ← Judgment → Counsel2 (same side, multiple cases)

MATCH (j:Judgment)-[:HAS_DEFENDANT_COUNSEL]->(c1:Counsel)
MATCH (j)-[:HAS_DEFENDANT_COUNSEL]->(c2:Counsel)
WHERE c1.name < c2.name
WITH c1.name AS counsel1, c1.chambers AS ch1,
     c2.name AS counsel2, c2.chambers AS ch2,
     collect(DISTINCT j.neutralCitation) AS sharedCases
WHERE size(sharedCases) > 1
RETURN counsel1, ch1, counsel2, ch2, sharedCases
ORDER BY size(sharedCases) DESC;

// ────────────────────────────────────────────────────────────

// Q10. Conflict check for new mandate
//      Find claimant-side KCs with ECT/ICSID/enforcement experience
//      who have NOT appeared for defendants in any of those same cases.
//      Requires: CSV-enriched Counsel.chambers + Counsel.isKc

MATCH (j:Judgment)-[:CONCERNS]->(t:LegalTopic)
WHERE t.name IN ['investment treaty arbitration', 'energy charter treaty', 'arbitral award enforcement']
MATCH (j)-[:HAS_CLAIMANT_COUNSEL]->(c:Counsel)
WHERE c.isKc = true AND c.chambers IS NOT NULL
WITH c, collect(DISTINCT j.neutralCitation) AS claimantCases
WHERE NOT EXISTS {
  MATCH (j2:Judgment)-[:HAS_DEFENDANT_COUNSEL]->(c)
  WHERE j2.neutralCitation IN claimantCases
}
RETURN c.name AS counsel, c.chambers AS chambers, c.kcYear AS kcYear,
       c.specialisms AS specialisms, claimantCases
ORDER BY size(claimantCases) DESC;

// ============================================================
// SECTION 3: VALIDATION & HEALTH-CHECK QUERIES
// ============================================================

// Graph counts — run after every extraction pass
MATCH (n:Judgment)   RETURN 'Judgment'   AS label, count(n) AS count
UNION ALL MATCH (n:Counsel)    RETURN 'Counsel'    AS label, count(n) AS count
UNION ALL MATCH (n:LawFirm)    RETURN 'LawFirm'    AS label, count(n) AS count
UNION ALL MATCH (n:Party)      RETURN 'Party'      AS label, count(n) AS count
UNION ALL MATCH (n:LegalTopic) RETURN 'LegalTopic' AS label, count(n) AS count
UNION ALL MATCH (n:Legislation) RETURN 'Legislation' AS label, count(n) AS count
UNION ALL MATCH (n:Judge)      RETURN 'Judge'      AS label, count(n) AS count
UNION ALL MATCH (n:Document)   RETURN 'Document'   AS label, count(n) AS count
UNION ALL MATCH (n:Chunk)      RETURN 'Chunk'      AS label, count(n) AS count;

// ────────────────────────────────────────────────────────────

// Relationship coverage — key traversals for target questions
MATCH ()-[r:HAS_CLAIMANT_COUNSEL]->()   RETURN 'HAS_CLAIMANT_COUNSEL'   AS rel, count(r) AS count
UNION ALL MATCH ()-[r:HAS_DEFENDANT_COUNSEL]->() RETURN 'HAS_DEFENDANT_COUNSEL' AS rel, count(r) AS count
UNION ALL MATCH ()-[r:HAS_CLAIMANT_FIRM]->()     RETURN 'HAS_CLAIMANT_FIRM'     AS rel, count(r) AS count
UNION ALL MATCH ()-[r:HAS_DEFENDANT_FIRM]->()    RETURN 'HAS_DEFENDANT_FIRM'    AS rel, count(r) AS count
UNION ALL MATCH ()-[r:PRESIDED_BY]->()           RETURN 'PRESIDED_BY'           AS rel, count(r) AS count
UNION ALL MATCH ()-[r:CONCERNS]->()              RETURN 'CONCERNS'              AS rel, count(r) AS count
UNION ALL MATCH ()-[r:CITES]->()                 RETURN 'CITES'                 AS rel, count(r) AS count
UNION ALL MATCH ()-[r:EXTRACTED_FROM]->()        RETURN 'EXTRACTED_FROM'        AS rel, count(r) AS count;

// ────────────────────────────────────────────────────────────

// Orphan check — entities with no relationships
MATCH (c:Counsel)    WHERE NOT (c)--() RETURN 'Orphan Counsel'    AS issue, count(c) AS count
UNION ALL MATCH (f:LawFirm) WHERE NOT (f)--() RETURN 'Orphan LawFirm'   AS issue, count(f) AS count
UNION ALL MATCH (t:LegalTopic) WHERE NOT (t)--() RETURN 'Orphan LegalTopic' AS issue, count(t) AS count
UNION ALL MATCH (l:Legislation) WHERE NOT (l)--() RETURN 'Orphan Legislation' AS issue, count(l) AS count;

// ────────────────────────────────────────────────────────────

// Duplicate key check — any node with > 1 occurrence of its key property
MATCH (c:Counsel)
WITH c.name AS name, count(*) AS cnt WHERE cnt > 1
RETURN 'Duplicate Counsel' AS issue, name, cnt ORDER BY cnt DESC LIMIT 10;

MATCH (f:LawFirm)
WITH f.name AS name, count(*) AS cnt WHERE cnt > 1
RETURN 'Duplicate LawFirm' AS issue, name, cnt ORDER BY cnt DESC LIMIT 10;

// ────────────────────────────────────────────────────────────

// CSV enrichment coverage
MATCH (c:Counsel) WHERE c.chambers IS NOT NULL RETURN 'Counsel with chambers' AS metric, count(c) AS count
UNION ALL MATCH (c:Counsel) WHERE c.chambers IS NULL RETURN 'Counsel without chambers' AS metric, count(c) AS count
UNION ALL MATCH (f:LawFirm) WHERE f.firmType IS NOT NULL RETURN 'LawFirm with firmType' AS metric, count(f) AS count
UNION ALL MATCH (l:Legislation) WHERE l.url IS NOT NULL RETURN 'Legislation with URL' AS metric, count(l) AS count;

// ────────────────────────────────────────────────────────────

// Embedding coverage — all chunks should have text_embedding
MATCH (c:Chunk) WHERE c.text_embedding IS NOT NULL RETURN 'Embedded chunks' AS metric, count(c) AS count
UNION ALL MATCH (c:Chunk) WHERE c.text_embedding IS NULL RETURN 'Unembedded chunks' AS metric, count(c) AS count;
