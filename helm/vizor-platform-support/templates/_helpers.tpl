{{- define "vizor-platform-support.serviceAccountName" -}}
{{- default .Values.global.serviceAccountName "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-platform-support.fullname" -}}
{{- default "vizor-platform-support" .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
