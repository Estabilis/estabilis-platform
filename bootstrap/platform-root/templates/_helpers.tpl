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
{{- define "platform-root.managedNamespaceMetadataPrivileged" -}}
managedNamespaceMetadata:
  labels:
    estabilis.io/managed-by: platform
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
{{- end -}}