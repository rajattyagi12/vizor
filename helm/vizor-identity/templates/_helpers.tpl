{{/*
Compute public-facing base URL from ingress values.
Uses publicHost (external) when set, falls back to host (internal).
Scheme is https when certName is non-empty, otherwise http.
*/}}
{{- define "vizor-identity.publicUrl" -}}
{{- $host := coalesce .Values.ingress.publicHost .Values.ingress.host -}}
{{- if $host -}}
  {{- $scheme := ternary "https" "http" (not (empty .Values.ingress.certName)) -}}
  {{- printf "%s://%s" $scheme $host -}}
{{- end -}}
{{- end -}}

{{- define "vizor-identity.serviceAccountName" -}}
{{- .Values.serviceAccount.name | default (printf "%s-runtime" .Release.Namespace) | default .Values.global.serviceAccountName | default "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-identity.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
