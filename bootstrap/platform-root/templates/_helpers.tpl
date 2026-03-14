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
{{- end -}}