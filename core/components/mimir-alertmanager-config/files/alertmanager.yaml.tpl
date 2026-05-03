{{- /*
Alertmanager configuration template for Mimir.

Two layers of templating:
  1. Helm `tpl` renders this file at chart-sync time, materialising the
     channel names, routing tree, repeat intervals, etc. from
     .Values.slack.* into static YAML.
  2. The rendered YAML still contains __SLACK_WEBHOOK_*__ placeholders
     for the secret values; the Job's initContainer substitutes those
     at runtime before calling `mimirtool alertmanager load`.

The double-curly literals like `{{` `}}` you see below escape the
inner Go templates that Alertmanager itself processes when formatting
each notification (so the sequence `{{` ... `}}` survives Helm rendering
and reaches Alertmanager intact).

Template functions: Alertmanager uses Go text/template + a small set of
helpers (toUpper, toLower, title, join, match, reReplaceAll, safeHtml,
stringSlice). It does NOT include Sprig's `default` — use `or` (text/
template builtin: returns first non-empty arg) for missing-label fallback.
Confirmed in cortex prd 2026-05-03 by `function "default" not defined`
notify error.
*/ -}}
route:
  receiver: slack-warnings
  group_by: {{ toJson .Values.slack.defaults.groupBy }}
  group_wait: {{ .Values.slack.defaults.groupWait }}
  group_interval: {{ .Values.slack.defaults.groupInterval }}
  repeat_interval: {{ .Values.slack.defaults.repeatInterval }}
  routes:
{{- if .Values.slack.channels.critical.enabled }}
    - matchers:
        - tier="{{ .Values.slack.channels.critical.tier }}"
      receiver: slack-critical
      group_wait: {{ .Values.slack.channels.critical.groupWait }}
      repeat_interval: {{ .Values.slack.channels.critical.repeatInterval }}
      continue: {{ .Values.slack.criticalContinue }}
{{- end }}
{{- if .Values.slack.channels.warnings.enabled }}
    - matchers:
        - tier="{{ .Values.slack.channels.warnings.tier }}"
      receiver: slack-warnings
      group_wait: {{ .Values.slack.channels.warnings.groupWait }}
      repeat_interval: {{ .Values.slack.channels.warnings.repeatInterval }}
{{- end }}
{{- if .Values.slack.channels.info.enabled }}
    - matchers:
        - tier="{{ .Values.slack.channels.info.tier }}"
      receiver: slack-info
      group_wait: {{ .Values.slack.channels.info.groupWait }}
      repeat_interval: {{ .Values.slack.channels.info.repeatInterval }}
{{- end }}

inhibit_rules:
  # A firing critical alert silences related warning/info alerts so a
  # single underlying incident doesn't page three times in three channels.
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity=~"warning|info"
    equal: [alertname, namespace]

receivers:
{{- if .Values.slack.channels.critical.enabled }}
  - name: slack-critical
    slack_configs:
      - api_url: __SLACK_WEBHOOK_CRITICAL__
        channel: '{{ .Values.slack.channels.critical.channelName }}'
        send_resolved: {{ if hasKey .Values.slack.channels.critical "sendResolved" }}{{ .Values.slack.channels.critical.sendResolved }}{{ else }}{{ .Values.slack.defaults.sendResolved }}{{ end }}
        color: '{{ .Values.slack.channels.critical.color }}'
        title: '{{`[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}`}}'
        text: |
          {{`*Cluster:* {{ or .CommonLabels.cluster "?" }}`}}
          {{`*Namespace:* {{ or .CommonLabels.namespace "?" }}`}}
          {{`*Tier:* {{ or .CommonLabels.tier "?" }} | *Severity:* {{ or .CommonLabels.severity "?" }}`}}
          {{`{{ range .Alerts -}}`}}
          {{`  • *{{ .Annotations.summary }}*`}}
          {{`    {{ .Annotations.description }}`}}
          {{`{{ end }}`}}
{{- end }}
{{- if .Values.slack.channels.warnings.enabled }}
  - name: slack-warnings
    slack_configs:
      - api_url: __SLACK_WEBHOOK_WARNINGS__
        channel: '{{ .Values.slack.channels.warnings.channelName }}'
        send_resolved: {{ if hasKey .Values.slack.channels.warnings "sendResolved" }}{{ .Values.slack.channels.warnings.sendResolved }}{{ else }}{{ .Values.slack.defaults.sendResolved }}{{ end }}
        color: '{{ .Values.slack.channels.warnings.color }}'
        title: '{{`[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}`}}'
        text: |
          {{`*Cluster:* {{ or .CommonLabels.cluster "?" }}`}}
          {{`*Namespace:* {{ or .CommonLabels.namespace "?" }}`}}
          {{`*Tier:* {{ or .CommonLabels.tier "?" }} | *Severity:* {{ or .CommonLabels.severity "?" }}`}}
          {{`{{ range .Alerts -}}`}}
          {{`  • *{{ .Annotations.summary }}*`}}
          {{`    {{ .Annotations.description }}`}}
          {{`{{ end }}`}}
{{- end }}
{{- if .Values.slack.channels.info.enabled }}
  - name: slack-info
    slack_configs:
      - api_url: __SLACK_WEBHOOK_INFO__
        channel: '{{ .Values.slack.channels.info.channelName }}'
        send_resolved: {{ if hasKey .Values.slack.channels.info "sendResolved" }}{{ .Values.slack.channels.info.sendResolved }}{{ else }}{{ .Values.slack.defaults.sendResolved }}{{ end }}
        color: '{{ .Values.slack.channels.info.color }}'
        title: '{{`[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}`}}'
        text: |
          {{`*Cluster:* {{ or .CommonLabels.cluster "?" }}`}}
          {{`*Namespace:* {{ or .CommonLabels.namespace "?" }}`}}
          {{`*Tier:* {{ or .CommonLabels.tier "?" }}`}}
          {{`{{ range .Alerts -}}`}}
          {{`  • {{ .Annotations.summary }}`}}
          {{`{{ end }}`}}
{{- end }}
  # `null` receiver is mandatory in Alertmanager configs even when nothing
  # routes there — the Mimir AM config validator complains about
  # unreachable receivers but accepts a placeholder.
  - name: 'null'
