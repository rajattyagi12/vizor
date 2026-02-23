{{- define "vizor-platform-support.serviceAccountName" -}}
{{- .Values.serviceAccount.name | default (printf "%s-runtime" .Release.Namespace) | default .Values.global.serviceAccountName | default "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-platform-support.fullname" -}}
{{- default "vizor-platform-support" .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
