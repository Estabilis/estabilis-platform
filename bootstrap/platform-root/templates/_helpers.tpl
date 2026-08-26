{{/*
Estabilis Platform — branding annotations injected into every namespace
managed by the platform. Carries release-level provenance (platform-version)
plus identity, source, and contact info for inspection/audit.

This is the canonical place for the platform release version — the
platform-root chart knows .Values.platformVersion natively, no plumbing
needed. Per-resource branding lives in each chart's own _helpers.tpl
(`estabilis.annotations`) and carries the chart's own version.

See: estabilis-platform-tools issue #45.
*/}}
{{- define "platform-root.estabilisNamespaceAnnotations" -}}
estabilis.io/platform: "Estabilis Platform"
estabilis.io/platform-version: {{ .Values.platformVersion | quote }}
estabilis.io/website: "https://estabilis.com"
estabilis.io/source: "https://github.com/Estabilis/estabilis-platform"
estabilis.io/support: "ops@estabilis.com"
estabilis.io/license: "proprietary"
{{- /*
  ADR 0005 L1 provenance annotations — DISABLED due to ArgoCD bug #20477.
  https://github.com/argoproj/argo-cd/issues/20477

  managedNamespaceMetadata does NOT respect ignoreDifferences. These
  temporal annotations (built-at, git-revision) change on every promote,
  causing ALL Applications to show OutOfSync permanently. Confirmed in
  ArgoCD v3.3.2.

  DO NOT UNCOMMENT until the upstream bug is fixed. Track the issue.
  When re-enabled, also remove the ignoreDifferences.all entries from
  core/components/argocd/values.yaml (they become redundant).

  {{- if .Values.global.provenance.gitRevision }}
  estabilis.io/git-revision: {{ .Values.global.provenance.gitRevision | quote }}
  estabilis.io/git-source: {{ .Values.global.provenance.gitSource | quote }}
  estabilis.io/built-at: {{ .Values.global.provenance.builtAt | quote }}
  estabilis.io/build-id: {{ .Values.global.provenance.buildId | quote }}
  {{- end }}
*/ -}}
{{- end -}}

{{/*
Standard namespace metadata — PSA baseline enforcement + platform label.
Used by all Applications that create their namespace (CreateNamespace=true).
Multiple apps targeting the same namespace MUST use identical metadata.
*/}}
{{- define "platform-root.managedNamespaceMetadata" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: platform
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
  annotations:
    {{- include "platform-root.estabilisNamespaceAnnotations" . | nindent 4 }}
{{- end -}}

{{/*
Excluded namespace metadata — same as standard but adds kyverno.io/exclude=true
so Kyverno webhook skips the namespace entirely.
*/}}
{{- define "platform-root.managedNamespaceMetadataExcluded" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: platform
    kyverno.io/exclude: "true"
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
  annotations:
    {{- include "platform-root.estabilisNamespaceAnnotations" . | nindent 4 }}
{{- end -}}

{{/*
Privileged namespace metadata — for components requiring host-level access
(e.g. node-exporter needs hostPID, hostNetwork).
*/}}
{{/*
Client override source — adds the client's downstream repo as an additional
source for Helm value overrides. Only rendered when BOTH configRepoUrl AND
configRepoVersion are set. The client must explicitly define the git ref
(branch, tag, or SHA) for their downstream repo.

Usage in Application templates:
  sources:
    - repoURL: https://charts.example.com
      chart: my-chart
      helm:
        valueFiles:
          - $values/core/components/my-component/values.yaml
          {{- include "platform-root.overrideValueFile" (dict "component" "my-component" "root" $) | nindent 10 }}
        {{- include "platform-root.ignoreMissingValueFiles" $ | nindent 8 }}
    - repoURL: {{ .Values.platformRepoUrl }}
      ref: values
    {{- include "platform-root.overrideSource" . | nindent 4 }}
*/}}
{{/*
Ref resolver helpers — resolve the effective git ref for each repo,
preferring the new *Revision values over the legacy *Version values.
Adopted in v0.13.0 per ADR 0020 (GitOps-native continuous
reconciliation) to allow consumers to track branches for own-content
repos (config overrides, client gitops). Tag pinning remains the
pattern for external dependencies (upstream Estabilis tags, charts,
container images).

Both legacy (configRepoVersion / clientGitopsRepoVersion) and new
(configRepoRevision / clientGitopsRepoRevision) values are accepted.
When both are set, the *Revision wins. When both are empty but the
corresponding URL is configured, `overrideEnabled` returns false
(backcompat: missing refs silently disabled the helpers already).
*/}}

{{- define "platform-root.configRepoRef" -}}
{{- if .Values.configRepoRevision -}}
{{- .Values.configRepoRevision -}}
{{- else if .Values.configRepoVersion -}}
{{- .Values.configRepoVersion -}}
{{- end -}}
{{- end -}}

{{- define "platform-root.clientGitopsRef" -}}
{{- if .Values.clientGitopsRepoRevision -}}
{{- .Values.clientGitopsRepoRevision -}}
{{- else if .Values.clientGitopsRepoVersion -}}
{{- .Values.clientGitopsRepoVersion -}}
{{- end -}}
{{- end -}}

{{- define "platform-root.clientGitopsRefRequired" -}}
{{- $ref := include "platform-root.clientGitopsRef" . -}}
{{- if not $ref -}}
{{- fail "clientGitopsRepoRevision (or legacy clientGitopsRepoVersion) is required when clientGitopsRepoUrl is set" -}}
{{- end -}}
{{- $ref -}}
{{- end -}}

{{- define "platform-root.configRepoRefRequired" -}}
{{- $ref := include "platform-root.configRepoRef" . -}}
{{- if not $ref -}}
{{- fail "configRepoRevision (or legacy configRepoVersion) is required when configRepoUrl is set" -}}
{{- end -}}
{{- $ref -}}
{{- end -}}

{{- define "platform-root.overrideEnabled" -}}
{{- and .Values.configRepoUrl (include "platform-root.configRepoRef" .) -}}
{{- end -}}

{{- define "platform-root.overrideSource" -}}
{{- if include "platform-root.overrideEnabled" . }}
- repoURL: {{ .Values.configRepoUrl }}
  targetRevision: {{ include "platform-root.configRepoRef" . }}
  ref: overrides
{{- end }}
{{- end -}}

{{- define "platform-root.overrideValueFile" -}}
{{- if include "platform-root.overrideEnabled" .root }}
- $overrides/overrides/{{ .component }}/values.yaml
{{- end }}
{{- end -}}

{{- define "platform-root.ignoreMissingValueFiles" -}}
{{- if include "platform-root.overrideEnabled" . }}
ignoreMissingValueFiles: true
{{- end }}
{{- end -}}

{{/*
ADR 0005 Phase 2b — forwards global.provenance.* from platform-root's
values.yaml into each child Application's Helm render. The internal
charts pick these up through their own `estabilis.provenanceAnnotations`
helper. Both helpers emit nothing when gitRevision is empty, so the
enclosing block stays valid when the CLI has no git context.

Two variants:

- `provenanceParameters` — emits bare list items. Use inside a child
  Application template that ALREADY has a `parameters:` block; append
  the include at the end so the extra entries merge in cleanly.

      parameters:
        - name: foo
          value: bar
        {{- include "platform-root.provenanceParameters" $ | nindent 10 }}

- `provenanceParametersBlock` — emits a complete `parameters:` key
  wrapped in a guard so nothing is rendered when provenance is absent.
  Use inside a child Application template that does NOT already have a
  `parameters:` block.

      helm:
        valueFiles:
          - ...
        {{- include "platform-root.ignoreMissingValueFiles" $ | nindent 8 }}
        {{- include "platform-root.provenanceParametersBlock" $ | nindent 8 }}
*/}}
{{- define "platform-root.provenanceParameters" -}}
{{- if .Values.global.provenance.gitRevision }}
- name: global.provenance.gitRevision
  value: {{ .Values.global.provenance.gitRevision | quote }}
- name: global.provenance.gitSource
  value: {{ .Values.global.provenance.gitSource | quote }}
- name: global.provenance.builtAt
  value: {{ .Values.global.provenance.builtAt | quote }}
- name: global.provenance.buildId
  value: {{ .Values.global.provenance.buildId | quote }}
{{- end }}
{{- end -}}

{{- define "platform-root.provenanceParametersBlock" -}}
{{- if .Values.global.provenance.gitRevision }}
parameters:
  {{- include "platform-root.provenanceParameters" . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "platform-root.managedNamespaceMetadataPrivileged" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: platform
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
  annotations:
    {{- include "platform-root.estabilisNamespaceAnnotations" . | nindent 4 }}
{{- end -}}

{{/*
Excluded privileged namespace metadata — privileged PSA + kyverno.io/exclude=true.
*/}}
{{- define "platform-root.managedNamespaceMetadataExcludedPrivileged" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: platform
    kyverno.io/exclude: "true"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
  annotations:
    {{- include "platform-root.estabilisNamespaceAnnotations" . | nindent 4 }}
{{- end -}}

{{/*
estabilis.host — constructs a hostname as {app}.{clusterName}.{domain}.

Usage (from component templates that receive global values):
  {{ include "estabilis.host" (dict "app" "grafana" "global" .Values.global) }}

Pattern: {app}.{clusterName}.{domain}
  The cluster name carries environment + region, no separate env prefix needed.
*/}}
{{/*
Client GitOps override helpers (ADR 0008 Tier 3).
Adds a $gitops source pointing at the client's gitops repo with
per-platform override paths scoped by deploymentId.
*/}}

{{- define "platform-root.gitopsSource" -}}
{{- if and .Values.clientGitopsRepoUrl .Values.deploymentId }}
- repoURL: {{ .Values.clientGitopsRepoUrl }}
  targetRevision: {{ include "platform-root.clientGitopsRef" . | default "HEAD" }}
  ref: gitops
{{- end }}
{{- end -}}

{{- define "platform-root.gitopsValueFile" -}}
{{- if and .root.Values.clientGitopsRepoUrl .root.Values.deploymentId }}
- $gitops/platforms/{{ .root.Values.deploymentId }}/overrides/{{ .component }}/values.yaml
{{- end }}
{{- end -}}

{{- define "estabilis.host" -}}
{{- $app := .app -}}
{{- $g := .global -}}
{{ $app }}.{{ $g.clusterName }}.{{ $g.domain }}
{{- end -}}
{{- /*
  Scheduling helpers — renders tolerations + nodeAffinity for charts so
  workloads tolerate Spot node taints and optionally express preference
  for a pool (regular / spot / auto).

  ADR 0012 (tracked in Estabilis/estabilis-platform-tools#97).

  Input: .Values.scheduling.mode — one of {auto, regular-only, spot-only}.
  Default (when unset): auto — tolerates spot, prefers regular.

  The tolerations block is ALWAYS the same (always allow scheduling on
  Spot when needed). Only the affinity part varies by mode:
    - auto         : preferredDuringScheduling → regular preferred
    - regular-only : requiredDuringScheduling  → regular hard
    - spot-only    : requiredDuringScheduling  → spot hard

  These helpers are rendered at platform-root time. Downstream charts
  consume them via Helm parameters wired in each Application template
  (see bootstrap/platform-root/templates/*.yaml).
*/ -}}

{{- /*
  schedulingTolerations — cloud-specific spot toleration, gated by
  `.provider`. Caller passes `provider` (typically
  `.Values.global.provider`) in the dict. Without a match, emits
  nothing — pods schedule normally on untainted nodes (AWS spot pools
  use a different taint, not this one).

  Until 2026-04-27 this helper emitted the AKS toleration
  unconditionally, leaking Azure-specific config into AWS Pod specs
  (no functional harm since the taint never existed there, but a
  cosmetic anomaly that surfaces in audits).
*/ -}}
{{- define "platform-root.schedulingTolerations" -}}
{{- $provider := default "" .provider -}}
{{- if eq $provider "azure" -}}
- key: "kubernetes.azure.com/scalesetpriority"
  operator: "Equal"
  value: "spot"
  effect: "NoSchedule"
{{- end -}}
{{- end -}}

{{- define "platform-root.schedulingAffinity" -}}
{{- $mode := default "auto" .mode -}}
nodeAffinity:
{{- if eq $mode "auto" }}
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 50
      preference:
        matchExpressions:
          - key: estabilis.io/schedulable
            operator: In
            values: ["regular"]
{{- else if eq $mode "regular-only" }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: estabilis.io/schedulable
            operator: In
            values: ["regular"]
{{- else if eq $mode "spot-only" }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: estabilis.io/schedulable
            operator: In
            values: ["spot"]
{{- end }}
{{- end -}}

{{- /*
  schedulingValuesFor — renders a valuesObject block for multiple
  sub-component paths at once. Used by Application templates that
  configure umbrella charts with per-component tolerations/affinity
  (argocd, cert-manager, kyverno, external-secrets, etc.).

  Input:
    .mode  — scheduling mode (auto|regular-only|spot-only). Defaults to auto.
    .paths — list of string paths (e.g. ["controller", "server", "webhook"])

  Emits one block per path with tolerations + affinity rendered from
  platform-root.schedulingTolerations and platform-root.schedulingAffinity.
*/ -}}
{{- define "platform-root.schedulingValuesFor" -}}
{{- $mode := default "auto" .mode -}}
{{- $tolerations := include "platform-root.schedulingTolerations" . -}}
{{- $affinity := include "platform-root.schedulingAffinity" (dict "mode" $mode) -}}
{{- range $comp := .paths }}
{{ $comp }}:
  {{- if $tolerations | trim }}
  tolerations:
    {{- $tolerations | nindent 4 }}
  {{- end }}
  affinity:
    {{- $affinity | nindent 4 }}
{{- end -}}
{{- end -}}

{{- /*
  schedulingValuesTopLevel — same but at the top of the chart (no path).
  Used by charts like external-dns, traefik, velero where tolerations/
  affinity live at the chart root.

  Input: .mode
*/ -}}
{{- define "platform-root.schedulingValuesTopLevel" -}}
{{- $mode := default "auto" .mode -}}
{{- $tolerations := include "platform-root.schedulingTolerations" . -}}
{{- if $tolerations | trim }}
tolerations:
  {{- $tolerations | nindent 2 }}
{{- end }}
affinity:
  {{- include "platform-root.schedulingAffinity" (dict "mode" $mode) | nindent 2 }}
{{- end -}}

{{- /*
  schedulingTolerationsOnly — for DaemonSets where nodeAffinity is
  not applicable (DS always deploys to all nodes matching node selector).
*/ -}}
{{- define "platform-root.schedulingTolerationsOnly" -}}
{{- $tolerations := include "platform-root.schedulingTolerations" . -}}
{{- if $tolerations | trim }}
tolerations:
  {{- $tolerations | nindent 2 }}
{{- end }}
{{- end -}}

{{- /*
  componentsForwarding — emit `.Values.components` filtered by provider,
  skipping AWS-only entries when global.provider != "aws". Used by the
  network-policies and resource-quotas Application templates that hand
  the components map to their gitops-side child charts.

  Without this filter, AWS-only namespaces (which never come into
  existence on Azure because their Application templates are gated on
  global.provider == "aws") still get forwarded as components.{ns}=true,
  causing the gitops charts to render NetworkPolicies / ResourceQuotas
  for non-existent namespaces and producing permanent OutOfSync drift.

  AWS-only set must match the gating clauses in:
    - bootstrap/platform-root/templates/aws-load-balancer-controller.yaml
    - bootstrap/platform-root/templates/karpenter.yaml (also gates karpenter-resources)
    - bootstrap/platform-root/templates/metrics-server.yaml
    - bootstrap/platform-root/templates/snapshot-controller.yaml

  Output: a `components:` block ready to nest under valuesObject.
*/ -}}
{{- define "platform-root.componentsForwarding" -}}
{{- /* Vault is intentionally NOT in this list — it's multi-provider (AWS + Azure) and gated separately on (provider in (aws|azure)) in vault.yaml. */ -}}
{{- $awsOnly := list "aws-load-balancer-controller" "karpenter" "karpenter-resources" "metrics-server" "snapshot-controller" -}}
{{- /* Never forwarded, on any provider. `resource-quotas` joined the components
       map so its Application could be switched off like every other component.
       Forwarding it would add a key to the map the network-policies and
       resource-quotas child charts consume, changing rendered output on
       deployments that changed nothing — and one of those charts is the very
       thing being toggled. */ -}}
{{- $notForwarded := list "resource-quotas" -}}
components:
  {{- range $k, $v := .Values.components }}
  {{- if has $k $notForwarded }}
  {{- /* never forwarded — see above */ -}}
  {{- else if and (has $k $awsOnly) (ne $.Values.global.provider "aws") }}
  {{- /* skip AWS-only component on non-AWS provider — namespace doesn't exist */ -}}
  {{- else }}
  {{ $k | quote }}: {{ $v }}
  {{- end }}
  {{- end }}
{{- end -}}

{{/*
Resolved ArgoCD UI base URL, e.g. "https://argocd.example.com", or "" when
ArgoCD has no enabled external exposure.

Derived from `global.argocdExposures` — the same payload
templates/argocd-ingress.yaml decodes to build the Ingress, and the same
`host` field providers/{aws,azure}/platform-outputs.tf reads. Deriving here
instead of consuming `global.argocdUrl` removes a value that had to be
computed upstream, published to the infrastructure ConfigMap, and forwarded
as a parameter — three places to stay in sync for information the chart
already holds.

That chain is not hypothetical: on a real deployment the parameter was
absent from the consumer's hand-maintained list, `global.argocdUrl` resolved
empty, and every dashboard data link silently became a relative URL that
resolved against Grafana's own host.

`global.argocdUrl` still wins when set, so deployments that supply it keep
their current behaviour. Accepts base64 or raw JSON, matching
argocd-ingress.yaml.
*/}}
{{- define "platform-root.argocdUrl" -}}
{{- $explicit := .Values.global.argocdUrl | default "" -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
{{- $raw := index .Values.global "argocdExposures" | default "" -}}
{{- $jsonStr := "{}" -}}
{{- if $raw -}}
{{- if or (hasPrefix "{" $raw) (hasPrefix "[" $raw) -}}
{{- $jsonStr = $raw -}}
{{- else -}}
{{- $jsonStr = b64dec $raw -}}
{{- end -}}
{{- end -}}
{{- $exp := (fromJson $jsonStr).external | default dict -}}
{{- if and $exp.enabled $exp.host -}}
{{- printf "https://%s" $exp.host -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /*
  chartVersion — which version of a third-party Helm chart to install.

  Precedence, first non-empty wins:

    1. chartVersions.<chart>   the map, keyed by the chart's OWN name as it
                               appears in the `chart:` field — `argo-cd`, not
                               `argocd`; `cloudnative-pg`, not `cnpg`; and one
                               `traefik` entry covering both the public and the
                               internal Application, because they are the same
                               chart.
    2. .legacy                 the per-component key that predates the map
                               (vaultChartVersion, argocdChartVersion). Still
                               honoured so nothing that already sets one breaks.
    3. .default                the version this release was tested against.

  WHY A MAP AND NOT ONE KEY PER COMPONENT

    Twenty-three charts had their version written into the template, so a
    deployment that needed a different one had to fork or wait for an upstream
    release that would move every other deployment with it. Twenty-three
    separate `<name>ChartVersion` keys would have solved that and left the
    values file unreadable.

  ⚠️ A CHART VERSION AND WHAT IS INSTALLED ARE THE SAME DECISION

    Bumping a chart bumps everything inside it. argo-cd 9.5.6 -> 10.4.0 moves
    every Argo CD image from v3.3.8 to v3.5.1 and Redis from 8.2.3 to 8.6.4.
    There is no separate knob for the contents, and there should not be: the
    chart is what was tested together.
*/ -}}
{{- define "platform-root.chartVersion" -}}
{{- $v := "" -}}
{{- with .root.Values.chartVersions -}}
{{- $v = default "" (index . $.chart) -}}
{{- end -}}
{{- if not $v -}}
{{- $v = default "" .legacy -}}
{{- end -}}
{{- default .default $v -}}
{{- end -}}

{{- /*
  autoSyncWhenUndeclared — emit an `automated` block, or nothing.

  Included in the syncPolicy of every Application that does not declare its own.
  Renders nothing when componentAutoSync.enabled is false, so a deployment that
  has not opted in gets byte-identical output to before this existed.

  prune is hardcoded false rather than exposed. ADR 0029 decides pruning
  per-App by risk class, and a global switch that could turn it on everywhere
  would undo that decision for CRD-owning and Foundational components at once.
*/ -}}
{{- define "platform-root.autoSyncWhenUndeclared" -}}
{{- if (.Values.componentAutoSync | default dict).enabled }}
    automated:
      selfHeal: {{ (.Values.componentAutoSync | default dict).selfHeal | default false }}
      prune: false
{{- end }}
{{- end -}}
