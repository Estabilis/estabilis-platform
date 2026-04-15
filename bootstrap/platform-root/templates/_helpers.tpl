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
{{- define "platform-root.overrideEnabled" -}}
{{- and .Values.configRepoUrl .Values.configRepoVersion -}}
{{- end -}}

{{- define "platform-root.overrideSource" -}}
{{- if and .Values.configRepoUrl .Values.configRepoVersion }}
- repoURL: {{ .Values.configRepoUrl }}
  targetRevision: {{ .Values.configRepoVersion }}
  ref: overrides
{{- end }}
{{- end -}}

{{- define "platform-root.overrideValueFile" -}}
{{- if and .root.Values.configRepoUrl .root.Values.configRepoVersion }}
- $overrides/overrides/{{ .component }}/values.yaml
{{- end }}
{{- end -}}

{{- define "platform-root.ignoreMissingValueFiles" -}}
{{- if and .Values.configRepoUrl .Values.configRepoVersion }}
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
estabilis.host — constructs a hostname based on the host_pattern.

Usage (from component templates that receive global values):
  {{ include "estabilis.host" (dict "app" "grafana" "global" .Values.global) }}

Patterns:
  subdomain: app.effectiveDomain  (effectiveDomain already includes env for non-prod)
  prefix:    env-app.domain       (prod: app.domain)
  suffix:    app-env.domain       (prod: app.domain)
*/}}
{{/*
Client GitOps override helpers (ADR 0008 Tier 3).
Adds a $gitops source pointing at the client's gitops repo with
per-platform override paths scoped by deploymentId.
*/}}

{{- define "platform-root.gitopsSource" -}}
{{- if and .Values.clientGitopsRepoUrl .Values.deploymentId }}
- repoURL: {{ .Values.clientGitopsRepoUrl }}
  targetRevision: {{ .Values.clientGitopsRepoVersion | default "HEAD" }}
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
{{- $isProd := or (eq $g.environment "prod") (eq $g.environment "prd") (eq $g.environment "production") -}}
{{- if eq $g.hostPattern "subdomain" -}}
{{ $app }}.{{ $g.effectiveDomain }}
{{- else if eq $g.hostPattern "prefix" -}}
{{- if $isProd -}}
{{ $app }}.{{ $g.domain }}
{{- else -}}
{{ $g.environment }}-{{ $app }}.{{ $g.domain }}
{{- end -}}
{{- else if eq $g.hostPattern "suffix" -}}
{{- if $isProd -}}
{{ $app }}.{{ $g.domain }}
{{- else -}}
{{ $app }}-{{ $g.environment }}.{{ $g.domain }}
{{- end -}}
{{- else -}}
{{ $app }}.{{ $g.effectiveDomain }}
{{- end -}}
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

{{- define "platform-root.schedulingTolerations" -}}
- key: "kubernetes.azure.com/scalesetpriority"
  operator: "Equal"
  value: "spot"
  effect: "NoSchedule"
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
  tolerations:
    {{- $tolerations | nindent 4 }}
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
tolerations:
  {{- include "platform-root.schedulingTolerations" . | nindent 2 }}
affinity:
  {{- include "platform-root.schedulingAffinity" (dict "mode" $mode) | nindent 2 }}
{{- end -}}

{{- /*
  schedulingTolerationsOnly — for DaemonSets where nodeAffinity is
  not applicable (DS always deploys to all nodes matching node selector).
*/ -}}
{{- define "platform-root.schedulingTolerationsOnly" -}}
tolerations:
  {{- include "platform-root.schedulingTolerations" . | nindent 2 }}
{{- end -}}
