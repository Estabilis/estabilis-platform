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