{{- define "vizor-apps.serviceAccountName" -}}
{{- default .Values.global.serviceAccountName "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-apps.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "vizor-apps.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
