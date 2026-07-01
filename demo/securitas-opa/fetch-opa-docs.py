"""
Fetch a curated subset of OPA (Open Policy Agent) documentation from GitHub.

Source: https://github.com/open-policy-agent/opa/tree/main/docs/docs
        (verified 2026-06-30 — docs moved from docs/content/ to docs/docs/)

Why OPA docs?
- Same Markdown format as Securitas's own platform documentation
- Authorization domain: roles, policies, rules — mirrors Securitas's RBAC graph
- Demo questions like "which policies reference RBAC?" are structurally identical
  to what Securitas developer teams would ask of their own platform docs

Run from the workspace root:
    python demo/securitas-opa/fetch-opa-docs.py

Downloads to: data/markdown/opa-docs/
"""

import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

REPO   = "open-policy-agent/opa"
BRANCH = "main"
DOCS_BASE = "docs/docs"
RAW_BASE  = f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/{DOCS_BASE}"
BROWSE_URL = f"https://github.com/{REPO}/tree/{BRANCH}/{DOCS_BASE}"

# ── Curated corpus: (source_path_in_repo, local_filename) ────────────────────
#
# Verified against repo on 2026-06-30.
# Selection criteria: files that map directly to Securitas's production graph model
# as revealed by the Neo4j healthcheck report (securitas_healthCheck_20260303_220620.pdf).
#
# Securitas graph model (from healthcheck):
#   Nodes: user, organization, customer, client, customerObject, roleAssignable,
#          area, role, configuration, tempRole, costCenter
#   Relationships: authRecord (typed), site, responsibleFor, hasConfiguration,
#                  hosts, includes
#   Key patterns:
#     - RBAC via: MATCH (org:customer)<-[*0..]-()<-[authRecord]--(user)
#       with WHEN/THEN/ELSE branching on authRecord type
#     - Org hierarchy variable-length traversal: (source:organization)-[r*]->(target)
#     - Role check: ({id:$userId})-[r*]->(n:roleAssignable)
#     - Dynamic label filter: WHERE $label IN labels(orgVertex)
#   Auth providers: oidc-azure, oidc-k8s (OIDC + JWT token validation)
#
# Each file below maps to one or more of these patterns.

ALL_DOCS = [
    # --- Core policy language ---
    # Defines Rego rules, packages, WHEN/THEN branching — maps to authRecord type branching
    ("policy-language.md",            "policy-language.md"),
    # Allow/deny rule testing patterns — maps to RBAC roleAssignable path queries
    ("policy-testing.md",             "policy-testing.md"),

    # --- Authentication — exact match to Securitas auth providers ---
    # TLS, OIDC, token-based auth — mirrors oidc-azure + oidc-k8s configuration
    ("security.md",                   "security.md"),
    # JWT/JWKS token validation — Securitas Azure OIDC integration
    ("oauth-oidc.md",                 "oauth-oidc.md"),

    # --- Authorization use cases — map to Securitas RBAC graph patterns ---
    # REST API authz mirrors authRecord-based allow/deny on org:customer endpoints
    ("http-api-authorization.md",     "http-api-authorization.md"),
    # Field-level access control mirrors dynamic label filter: $label IN labels(orgVertex)
    ("graphql-api-authorization.md",  "graphql-api-authorization.md"),
    # Topic ACLs mirror area/costCenter/site resource-based access patterns
    ("kafka-authorization.md",        "kafka-authorization.md"),
    # Role hierarchy mirrors customer/client/organization traversal and roleAssignable nodes
    ("ssh-and-sudo-authorization.md", "ssh-and-sudo-authorization.md"),

    # --- Infrastructure integration ---
    # K8s admission control mirrors oidc-k8s provider + dynamic resource governance
    ("kubernetes/index.md",           "kubernetes-primer.md"),
    # REST/Bolt API integration mirrors dotnet client authz call patterns
    ("integration.md",                "integration.md"),
]

OUTPUT_DIR = Path(__file__).parent.parent.parent / "data" / "markdown" / "opa-docs"


def raw_url(source_path: str) -> str:
    return f"{RAW_BASE}/{source_path}"


def fetch_one(source_path: str, local_name: str) -> tuple[str, str]:
    """
    Download a single file. Returns (status, detail).
      status: "ok" | "skipped" | "not_found" | "error"
    """
    output_path = OUTPUT_DIR / local_name

    if output_path.exists():
        return "skipped", f"already exists ({output_path.stat().st_size:,} bytes)"

    url = raw_url(source_path)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "securitas-opa-demo/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            content = resp.read()
        output_path.write_bytes(content)
        return "ok", f"{len(content):,} bytes -> {local_name}"

    except urllib.error.HTTPError as e:
        if e.code == 404:
            return "not_found", (
                f"HTTP 404 - not found at {DOCS_BASE}/{source_path}\n"
                f"           File may have moved. Browse: {BROWSE_URL}"
            )
        return "error", f"HTTP {e.code} {e.reason} for {url}"

    except urllib.error.URLError as e:
        return "error", f"Network error fetching {source_path}: {e.reason}"

    except Exception as e:
        return "error", f"Unexpected error fetching {source_path}: {type(e).__name__}: {e}"


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Fetching OPA documentation -> {OUTPUT_DIR}")
    print(f"Source: {BROWSE_URL}\n")

    results: dict[str, list[tuple[str, str, str]]] = {
        "ok": [], "skipped": [], "not_found": [], "error": []
    }

    for source_path, local_name in ALL_DOCS:
        status, detail = fetch_one(source_path, local_name)
        results[status].append((source_path, local_name, detail))

        prefix = {
            "ok":        "  OK      ",
            "skipped":   "  SKIP    ",
            "not_found": "  MISSING ",
            "error":     "  ERROR   ",
        }[status]

        if status == "ok":
            print(f"{prefix}{local_name:<46} {detail.split('->')[0].strip()}")
        elif status == "skipped":
            print(f"{prefix}{local_name:<46} {detail}")
        else:
            # not_found or error — print full detail on separate line for clarity
            print(f"{prefix}{local_name}")
            for line in detail.split("\n"):
                print(f"           {line.strip()}")

        if status not in ("skipped",):
            time.sleep(0.3)  # polite to GitHub

    # ── Summary ──────────────────────────────────────────────────────────────
    ok      = len(results["ok"])
    skipped = len(results["skipped"])
    missing = len(results["not_found"])
    errors  = len(results["error"])
    total_in_dir = len(list(OUTPUT_DIR.glob("*.md")))

    print("\n" + "-" * 65)
    print(f"  Downloaded : {ok:>3}   Already existed : {skipped:>3}   "
          f"Not found : {missing:>3}   Errors : {errors:>3}")
    print(f"  Total .md files now in output dir: {total_in_dir}")
    print("-" * 65)

    if results["not_found"]:
        print(f"\nWARN  {missing} file(s) not found at expected paths.")
        print(f"   These may have been renamed or moved since this script was written.")
        print(f"   Browse current repo structure: {BROWSE_URL}")
        print(f"   Files not found:")
        for src, _, _ in results["not_found"]:
            print(f"     {DOCS_BASE}/{src}")

    if results["error"]:
        print(f"\nFAIL  {errors} fetch error(s) — check network connection and retry:")
        for src, _, detail in results["error"]:
            print(f"     {src}: {detail.split(chr(10))[0]}")

    if ok + skipped > 0:
        print(f"\nNext step - open Claude Code in graph-intelligence-agent/ and run:")
        print(f"  /develop-neo4j-graph")
        print(f"  Source: {OUTPUT_DIR}")
        print(f"  Parse mode: markdown")
        if total_in_dir > 20:
            print(f"\n  Note: {total_in_dir} files downloaded. Aura DI console allows max 20 per job.")
            print(f"  For Tier 1 demo: use the first 20 files. Tier 2 (graph-intelligence-agent) has no limit.")
    else:
        print(f"\nFAIL  No files downloaded. Check your internet connection and try again.")
        sys.exit(1)


if __name__ == "__main__":
    main()
