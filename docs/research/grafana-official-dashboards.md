# Grafana Labs Official Dashboards — Research

**Status:** Research-only. No dashboards installed. Decisions deferred.
**Date:** 2026-05-03
**Scope:** identifying official self-monitoring dashboards published by
Grafana Labs for the products active in our cluster, validating that
they're installable in our `core/components/grafana-dashboards/` chart,
and surfacing the trade-offs that need a human decision before
proceeding.

The work was sparked by an audit on the cortex AWS prd cluster. Same
question applies to every AWS or Azure deployment of the platform,
since the Grafana stack ships identically.

---

## Grafana stack inventory (audited on cortex prd, 2026-05-03)

| Product   | Version | Self-monitoring dashboard installed? |
|-----------|---------|--------------------------------------|
| Grafana   | 12.x    | ❌                                    |
| Mimir     | 3.0.1   | ❌                                    |
| Loki      | 3.6.5   | ❌                                    |
| Tempo     | 2.5.0   | ❌                                    |
| Pyroscope | 1.19.0  | ❌                                    |
| Alloy     | 1.14.0  | ❌                                    |

What `core/components/grafana-dashboards/files/` ships today (15 dashboards):

```
argocd-application       cnpg-cluster        k8s-pods         opencost-overview
argocd-notifications     k8s-global          kyverno          traefik
argocd-operational       k8s-namespaces      opencost-namespace
cert-manager             k8s-nodes           trivy-operator   velero
```

None of these cover the Grafana products themselves — they're all for
*other* tools that Grafana monitors. The Grafana stack runs without any
self-observability dashboard, which is a real gap for incident triage
(e.g. the cortex prd query-frontend OOM incident on 2026-05-03 had to
be diagnosed via raw `kubectl logs` + `kubectl top` because there was
no Mimir / read-path dashboard to point at).

---

## Sources of truth (canonical, by product)

The Grafana Labs dashboards for these products live in the **mixin
repos** on GitHub, not in the `grafana.com/grafana/dashboards/` catalogue.
The grafana.com catalogue does have one referenceable Grafana-itself
dashboard (ID 3590), but it's published by an individual maintainer
(Bart Van Bos), not under a "Grafana Labs" org slug.

Verified via `https://grafana.com/api/dashboards?orgSlug=grafanalabs` —
returns zero items. There is no single publisher catalogue for these on
grafana.com.

| Product   | Source                                                                                  | Format                  |
|-----------|------------------------------------------------------------------------------------------|-------------------------|
| Mimir     | https://github.com/grafana/mimir/tree/main/operations/mimir-mixin/dashboards              | `.libsonnet` (compiled) |
| Loki      | https://github.com/grafana/loki/tree/main/production/loki-mixin/dashboards                | 5 `.json` + `.libsonnet`|
| Tempo     | https://github.com/grafana/tempo/tree/main/operations/tempo-mixin/dashboards              | 2 `.json` + `.libsonnet`|
| Pyroscope | https://github.com/grafana/pyroscope/tree/main/operations/pyroscope/jsonnet/pyroscope-mixin/pyroscope-mixin/dashboards | `.libsonnet` (compiled) |
| Alloy     | https://github.com/grafana/alloy/tree/main/operations/alloy-mixin/dashboards              | `.libsonnet` (compiled) |
| Grafana   | https://grafana.com/grafana/dashboards/3590-grafana-internals/                            | `.json` (download)      |

Mimir / Pyroscope / Alloy ship only `.libsonnet` (Jsonnet templates).
The mixin output has to be **compiled to JSON** before it's
consumable by the existing `grafana-dashboards` chart pattern (which
mounts raw `.json` files into a ConfigMap).

---

## Compilation toolchain (validated)

Tested locally on 2026-05-03 in a scratch dir; all artefacts discarded
after validation. Tools needed:

| Tool                   | Install                                                                |
|------------------------|------------------------------------------------------------------------|
| `jsonnet` (Go impl.)   | `go install github.com/google/go-jsonnet/cmd/jsonnet@latest`           |
| `jb` (jsonnet-bundler) | `go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest`  |
| `mixtool`              | `go install github.com/monitoring-mixins/mixtool/cmd/mixtool@latest`   |

Per-product compile recipe:

```bash
# Mimir
git clone --depth=1 --filter=blob:none --sparse https://github.com/grafana/mimir.git
cd mimir && git sparse-checkout set operations/mimir-mixin
cd operations/mimir-mixin
jb install
mixtool generate dashboards mixin.libsonnet -d /out/mimir
# -> 27 .json

# Pyroscope (note: nested pyroscope-mixin/pyroscope-mixin layout, vendor lives at parent)
git clone --depth=1 --filter=blob:none --sparse https://github.com/grafana/pyroscope.git
cd pyroscope && git sparse-checkout set operations/pyroscope/jsonnet/pyroscope-mixin
cd operations/pyroscope/jsonnet/pyroscope-mixin/pyroscope-mixin
mixtool generate dashboards -J ../vendor mixin.libsonnet -d /out/pyroscope
# -> 2 .json

# Alloy
git clone --depth=1 --filter=blob:none --sparse https://github.com/grafana/alloy.git
cd alloy && git sparse-checkout set operations/alloy-mixin
cd operations/alloy-mixin
jb install
mixtool generate dashboards mixin.libsonnet -d /out/alloy
# -> 9 .json
```

End-to-end time on a fresh laptop: ~2 min (mostly the `go install` +
`jb install` network calls).

---

## Validated outputs (compiled artefacts, then discarded)

All 38 generated JSONs were verified to be syntactically valid Grafana
dashboards (parseable JSON, with `title`, `templating`, and either
`panels[]` or legacy `rows[].panels[]`).

### Mimir — 27 dashboards (~641 panels total, schemaVersion 14)

```
mimir-overview                       mimir-overview-resources       mimir-overview-networking
mimir-reads                          mimir-reads-resources          mimir-reads-networking
mimir-writes                         mimir-writes-resources         mimir-writes-networking
mimir-alertmanager                   mimir-alertmanager-resources
mimir-compactor                      mimir-compactor-resources
mimir-ruler                          mimir-remote-ruler-reads       mimir-remote-ruler-reads-resources  mimir-remote-ruler-reads-networking
mimir-object-store                   mimir-config                   mimir-overrides
mimir-queries                        mimir-slow-queries
mimir-tenants                        mimir-top-tenants
mimir-scaling                        mimir-rollout-progress
rollout-operator
```

### Pyroscope — 2 dashboards (12 panels, schemaVersion 14)

```
pyroscope-reads
pyroscope-writes
```

### Alloy — 9 dashboards (95 panels, schemaVersion 36)

```
alloy-cluster-overview               alloy-cluster-node             alloy-controller
alloy-resources                      alloy-logs                     alloy-loki
alloy-prometheus-remote-write        alloy-opentelemetry            alloy-otel-engine-overview
```

### Loki — 5 dashboards JSON-ready in repo (no compile needed)

```
dashboard-loki-operational
dashboard-loki-logs
dashboard-recording-rules
dashboard-bloom-build
dashboard-bloom-gateway
```

### Tempo — 2 dashboards JSON-ready in repo

```
tempo-operational
tempo-backendwork
```

### Grafana — 1 dashboard from grafana.com

```
grafana-internals (id 3590)
```

**Headline number:** **46 dashboards** total potentially installable.

---

## Caveats discovered during validation

1. **Mimir / Pyroscope use schemaVersion 14** (Grafana 4-7 era). Grafana
   12.x **auto-migrates on import** (no functional issue), but the JSON
   committed to git stays in the legacy schema. Future re-edits via
   the Grafana UI will save in the new schema, creating diff churn.
   Options: regenerate via `grafonnet`-based modern templates, or
   accept the auto-migration path.

2. **Datasource UID is templated as `$datasource`**. Operator must pick
   the Mimir datasource from the panel dropdown on first open (or set
   it as a saved view per user). To make it zero-click on our cluster,
   pre-substitute at compile time:

   ```bash
   sed -i 's|"\\$datasource"|"mimir"|g' /out/*/*.json
   ```

   Trade-off: harder to share the dashboards across datasources.

3. **Volume.** 46 dashboards × ~17 panels avg = **~750 panel-instances**.
   That's a lot of side-bar UI clutter in the Grafana folder tree.
   Probably want a subset:

   - **Minimum viable for incident triage:**
     - Mimir: overview, reads, writes, queries, scaling (5)
     - Loki: dashboard-loki-operational (1)
     - Tempo: tempo-operational (1)
     - Alloy: alloy-cluster-overview, alloy-controller (2)
     - Pyroscope: pyroscope-reads (1)
     - Grafana: grafana-internals (1)
     - **Total: 11 dashboards** — covers "is the stack itself healthy?"
   - **Full self-monitoring suite:** all 46.
   - The cortex prd query-frontend OOM incident specifically would
     have been diagnosed faster with `mimir-reads` (shows query
     latency / errors / inflight).

4. **Build-pipeline decision pending.** Three honest options for keeping
   the JSONs in sync with upstream:

   - (a) Commit the 38 generated JSONs into
     `core/components/grafana-dashboards/files/` and regenerate manually
     (i.e. re-run the recipe above) when bumping Mimir / Loki / Tempo
     / Pyroscope / Alloy versions. Lowest infra cost, manual discipline.
   - (b) Add a `scripts/generate-dashboards.sh` to the repo that runs
     the recipe and writes into the chart's `files/` dir. JSONs are
     still checked in (so chart consumers don't need the toolchain),
     but regeneration is one command. Operator reruns when bumping
     stack versions.
   - (c) Containerised CI step that regenerates on every PR touching
     `core/components/grafana-dashboards/`. Highest infra cost; useful
     only at multi-cluster scale where manual regen drift becomes a
     real problem.

   Recommended starting point: (b). Scales to (c) only if pain emerges.

5. **The `grafana-dashboards` chart's current ConfigMap pattern doesn't
   substitute placeholders other than the recently-added
   `__ARGOCD_URL__`.** If we adopt official mixin dashboards, more
   placeholder substitutions may be desirable (datasource UID,
   per-cluster context, etc.) — chart template needs a generalisation
   pass.

6. **Folder organisation in Grafana UI.** Current ConfigMap annotations
   write `grafana_folder: <Tool Name>`. New mixins would need
   per-product folders (`Mimir`, `Loki`, `Tempo`, `Pyroscope`, `Alloy`,
   `Grafana`). Operator UX consideration; probably want a top-level
   "Stack Self-Monitoring" parent folder.

---

## Decisions deferred (not blocking)

- Pick the install scope (11 vs 46 vs custom subset).
- Pick the build pipeline (manual / scripted / CI).
- Decide on schemaVersion modernisation strategy.
- Decide on datasource pre-substitution.
- Folder taxonomy in Grafana UI.

When this work resumes, the recipe in this doc reproduces the validation
in ~2 min — no information lost by walking away now.

---

## References

- Mimir mixin: https://github.com/grafana/mimir/tree/main/operations/mimir-mixin
- Loki mixin: https://github.com/grafana/loki/tree/main/production/loki-mixin
- Tempo mixin: https://github.com/grafana/tempo/tree/main/operations/tempo-mixin
- Pyroscope mixin: https://github.com/grafana/pyroscope/tree/main/operations/pyroscope/jsonnet/pyroscope-mixin
- Alloy mixin: https://github.com/grafana/alloy/tree/main/operations/alloy-mixin
- Grafana Internals: https://grafana.com/grafana/dashboards/3590-grafana-internals/
- monitoring-mixins toolchain: https://github.com/monitoring-mixins/docs
- mixtool: https://github.com/monitoring-mixins/mixtool
