#!/usr/bin/env bash
# =============================================================================
# validate-specs.sh — single source of truth for spec/** JSON Schema gates.
# =============================================================================
#
# Called by:
#   - .pre-commit-config.yaml      (local hook, on commit touching spec/**)
#   - .github/workflows/spec-validation.yaml  (CI, on PR + push to main)
#
# Both consumers invoke the same script so local and CI cannot drift.
#
# Four checks, all must pass:
#   1. Production upstart specs (3 files) validate against upstart v3 schema.
#   2. Production cleanup specs (3 files) validate against cleanup v1 schema.
#   3. tests/good/*.yaml must validate (positive fixtures).
#   4. tests/bad/*.yaml must FAIL validation (negative fixtures — the
#      schema-weakening regression alarm). Any bad/* that passes means a
#      schema rule has been removed/relaxed — CI/commit blocked.
#
# Requires: check-jsonschema in PATH (pip install check-jsonschema==0.30.0).
#           When called from pre-commit, the hook env supplies it.
# =============================================================================

set -uo pipefail

# Resolve repo root regardless of cwd (pre-commit hooks set cwd to repo root,
# but be defensive).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

UPSTART_SCHEMA="spec/upstart/schema/upstart.v3.schema.json"
CLEANUP_SCHEMA="spec/cleanup/schema/cleanup.v1.schema.json"

if ! command -v check-jsonschema >/dev/null 2>&1; then
  echo "ERROR: check-jsonschema not found in PATH."
  echo "Install: pip install check-jsonschema==0.30.0"
  exit 2
fi

fails=0

# -----------------------------------------------------------------------------
# Step 1 — production upstart specs MUST validate.
# -----------------------------------------------------------------------------
echo "==> 1. Production upstart specs (must pass)"
for f in spec/upstart/upstart.yaml spec/upstart/upstart.aws.yaml spec/upstart/upstart.azure.yaml; do
  if check-jsonschema --schemafile "$UPSTART_SCHEMA" "$f" > /dev/null 2>&1; then
    echo "  ok  $f"
  else
    echo "  FAIL $f"
    check-jsonschema --schemafile "$UPSTART_SCHEMA" "$f" 2>&1 | sed 's/^/    /'
    fails=$((fails + 1))
  fi
done

# -----------------------------------------------------------------------------
# Step 2 — production cleanup specs MUST validate.
# -----------------------------------------------------------------------------
echo "==> 2. Production cleanup specs (must pass)"
for f in spec/cleanup/cleanup.yaml spec/cleanup/cleanup.aws.yaml spec/cleanup/cleanup.azure.yaml; do
  if check-jsonschema --schemafile "$CLEANUP_SCHEMA" "$f" > /dev/null 2>&1; then
    echo "  ok  $f"
  else
    echo "  FAIL $f"
    check-jsonschema --schemafile "$CLEANUP_SCHEMA" "$f" 2>&1 | sed 's/^/    /'
    fails=$((fails + 1))
  fi
done

# -----------------------------------------------------------------------------
# Step 3 — good fixtures MUST validate.
# -----------------------------------------------------------------------------
echo "==> 3. Good fixtures (must pass)"
for f in spec/upstart/schema/tests/good/*.yaml; do
  [ -e "$f" ] || continue
  if check-jsonschema --schemafile "$UPSTART_SCHEMA" "$f" > /dev/null 2>&1; then
    echo "  ok  $f"
  else
    echo "  FAIL $f"
    check-jsonschema --schemafile "$UPSTART_SCHEMA" "$f" 2>&1 | sed 's/^/    /'
    fails=$((fails + 1))
  fi
done
for f in spec/cleanup/schema/tests/good/*.yaml; do
  [ -e "$f" ] || continue
  if check-jsonschema --schemafile "$CLEANUP_SCHEMA" "$f" > /dev/null 2>&1; then
    echo "  ok  $f"
  else
    echo "  FAIL $f"
    check-jsonschema --schemafile "$CLEANUP_SCHEMA" "$f" 2>&1 | sed 's/^/    /'
    fails=$((fails + 1))
  fi
done

# -----------------------------------------------------------------------------
# Step 4 — bad fixtures MUST FAIL. Any that pass mean schema was weakened.
# -----------------------------------------------------------------------------
echo "==> 4. Bad fixtures (must FAIL — regression alarm)"
for f in spec/upstart/schema/tests/bad/*.yaml; do
  [ -e "$f" ] || continue
  if check-jsonschema --schemafile "$UPSTART_SCHEMA" "$f" > /dev/null 2>&1; then
    echo "  REGRESSION $f passed validation, but is in tests/bad/ and should FAIL."
    echo "             Schema rule it targets has been weakened. Either:"
    echo "               - restore the schema rule, OR"
    echo "               - delete this fixture if the rule is gone deliberately."
    fails=$((fails + 1))
  else
    echo "  ok  $f (rejected as expected)"
  fi
done
for f in spec/cleanup/schema/tests/bad/*.yaml; do
  [ -e "$f" ] || continue
  if check-jsonschema --schemafile "$CLEANUP_SCHEMA" "$f" > /dev/null 2>&1; then
    echo "  REGRESSION $f passed validation, but is in tests/bad/ and should FAIL."
    echo "             Schema rule it targets has been weakened. Either:"
    echo "               - restore the schema rule, OR"
    echo "               - delete this fixture if the rule is gone deliberately."
    fails=$((fails + 1))
  else
    echo "  ok  $f (rejected as expected)"
  fi
done

echo
if [ "$fails" -eq 0 ]; then
  echo "All spec validations passed."
  exit 0
else
  echo "$fails check(s) failed."
  exit 1
fi
