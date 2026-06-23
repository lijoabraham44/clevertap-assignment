{{/* Common name + label helpers. */}}
{{- define "event-ingestion.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "event-ingestion.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "event-ingestion.labels" -}}
app.kubernetes.io/name: {{ include "event-ingestion.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{- define "event-ingestion.selectorLabels" -}}
app: {{ include "event-ingestion.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
