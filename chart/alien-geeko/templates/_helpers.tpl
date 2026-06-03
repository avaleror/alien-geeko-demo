{{- define "alien-geeko.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "alien-geeko.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "alien-geeko.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "alien-geeko.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alien-geeko.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
