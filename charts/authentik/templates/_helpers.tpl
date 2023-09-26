{{/* Allow KubeVersion to be overridden. */}}
{{- define "authentik.capabilities.ingress.kubeVersion" -}}
  {{- default .Capabilities.KubeVersion.Version .Values.kubeVersionOverride -}}
{{- end -}}

{{/* Return the appropriate apiVersion for Ingress objects */}}
{{- define "authentik.capabilities.ingress.apiVersion" -}}
  {{- print "networking.k8s.io/v1" -}}
  {{- if semverCompare "<1.19" (include "authentik.capabilities.ingress.kubeVersion" .) -}}
    {{- print "beta1" -}}
  {{- end -}}
{{- end -}}

{{/* Check Ingress stability */}}
{{- define "authentik.capabilities.ingress.isStable" -}}
  {{- if eq (include "authentik.capabilities.ingress.apiVersion" .) "networking.k8s.io/v1" -}}
    {{- true -}}
  {{- end -}}
{{- end -}}

{{- define "authentik.env" -}}
  {{- range $k, $v := .values -}}
    {{- if kindIs "map" $v -}}
      {{- range $sk, $sv := $v -}}
        {{- include "authentik.env" (dict "root" $.root "values" (dict (printf "%s__%s" (upper $k) (upper $sk)) $sv)) -}}
      {{- end -}}
    {{- else -}}
      {{- $value := $v -}}
      {{- if or (kindIs "bool" $v) (kindIs "float64" $v) -}}
        {{- $v = $v | toString | b64enc | quote -}}
      {{- else -}}
        {{- $v = tpl $v $.root | toString | b64enc | quote }}
      {{- end -}}
      {{- if and ($v) (ne $v "\"\"") }}
{{ printf "AUTHENTIK_%s" (upper $k) }}: {{ $v }}
      {{- end }}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Expand the name of the chart */}}
{{- define "authentik.names.name" -}}
  {{- $globalNameOverride := "" -}}
  {{- if hasKey .Values "global" -}}
    {{- $globalNameOverride = (default $globalNameOverride .Values.global.nameOverride) -}}
  {{- end -}}
  {{- default .Chart.Name (default .Values.nameOverride $globalNameOverride) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Create chart name and version as used by the chart label */}}
{{- define "authentik.names.chart" -}}
  {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "authentik.names.fullname" -}}
  {{- $name := include "authentik.names.name" . -}}
  {{- $globalFullNameOverride := "" -}}
  {{- if hasKey .Values "global" -}}
    {{- $globalFullNameOverride = (default $globalFullNameOverride .Values.global.fullnameOverride) -}}
  {{- end -}}
  {{- if or .Values.fullnameOverride $globalFullNameOverride -}}
    {{- $name = default .Values.fullnameOverride $globalFullNameOverride -}}
  {{- else -}}
    {{- if contains $name .Release.Name -}}
      {{- $name = .Release.Name -}}
    {{- else -}}
      {{- $name = printf "%s-%s" .Release.Name $name -}}
    {{- end -}}
  {{- end -}}
  {{- trunc 63 $name | trimSuffix "-" -}}
{{- end -}}


{{/* Common labels shared across objects */}}
{{- define "authentik.labels" -}}
helm.sh/chart: {{ include "authentik.names.chart" . }}
{{ include "authentik.labels.selectorLabels" . }}
  {{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
  {{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels shared across objects */}}
{{- define "authentik.labels.selectorLabels" -}}
app.kubernetes.io/name: {{ include "authentik.names.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
    Create Hostname helper -- Coreweave Use Only
*/}}
{{- define "coreweave.externalDnsName" -}}
{{- if .Values.fullnameOverride -}}
{{ default (printf "%s.%s.%s.ingress.coreweave.cloud" .Values.fullnameOverride .Release.Namespace (.Values.region | lower | toString)) .Values.customExternalDnsName }}
{{- else -}}
{{ default (printf "%s.%s.%s.ingress.coreweave.cloud" .Release.Name .Release.Namespace ((default "ORD1" .Values.region) | lower | toString)) .Values.customExternalDnsName }}
{{- end -}}
{{- end -}}

{{/*
    Create DRY Helpers
*/}}
{{- define "coreweave.tolerations" -}}
{{- if .Values.tolerations }}
{{- with .Values.tolerations }}
tolerations:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- else }}
tolerations:
  - key: is_cpu_compute
    operator: Exists
{{- end }}
{{- end -}}
{{- define "coreweave.affinity" -}}
{{- if .Values.affinity }}
{{- with .Values.affinity }}
affinity:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- else }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/region
              operator: In
              values:
                - {{ .Values.region }}
            - key: node.coreweave.cloud/class
              operator: In
              values:
                - cpu
            - key: node.coreweave.cloud/cpu
              operator: In
              values:
                - intel-xeon-v4
                - amd-epyc-rome
                - amd-epyc-milan
                - intel-xeon-scalable
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/managed-by
                operator: In
                values:
                  - goauthentik.io
              - key: app.kubernetes.io/instance
                operator: In
                values:
                  - {{ .Release.Name }}
          topologyKey: kubernetes.io/hostname
        weight: 100
{{- end }}
{{- end -}}
{{- define "coreweave.certSecretName" -}}
{{printf "%s-tls-cert" .Release.Name }}
{{- end -}}
{{- define "coreweave.envValueFrom" -}}
envValueFrom:
  AUTHENTIK_POSTGRESQL__PASSWORD:
    secretKeyRef:
      name: {{ .Release.Name }}-postgresql
      key: postgresql-password
  AUTHENTIK_SECRET_KEY:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: secret_key
  AUTHENTIK_BOOTSTRAP_PASSWORD:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: akadmin_password
  AUTHENTIK_BOOTSTRAP_TOKEN:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: bootstrap_token
  AUTHENTIK_BOOTSTRAP_EMAIL:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: admin_email
  AUTHENTIK_LDAP_SVC_KEY:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: ldapsvc_password
  {{- range ((.Values).customBlueprints).oidcProvider }}
  {{ printf "oidc-%s-client-id" .name }}:
    secretKeyRef:
      name: {{ printf "%s-oidc-%s-keys" $.Release.Name .name }}
      key: {{ printf "oidc-%s-client-id" .name }}
  {{ printf "oidc-%s-client-secret" .name }}:
    secretKeyRef:
      name: {{ printf "%s-oidc-%s-keys" $.Release.Name .name }}
      key: {{ printf "oidc-%s-client-secret" .name }}
  {{- end }}
  {{- range ((.Values).customBlueprints).users }}
  {{ printf "%s_password" .userName }}:
    secretKeyRef:
      name: {{ printf "%s-%s-keys"  $.Release.Name .userName }}
      key: {{ printf "%s_password" .userName }}
  {{- end }}
{{- if .Values.envValueFrom }}
{{- with .Values.envValueFrom }}
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "coreweave.blueprints" -}}
blueprints:
  - {{ .Release.Name }}-ldap-provider-blueprint
  - {{ .Release.Name }}-users-blueprint
  - {{ .Release.Name }}-groups-blueprint
  - {{ .Release.Name }}-ldap-federation-blueprint
  - {{ .Release.Name }}-google-ldap-mapping-blueprint
  - {{ .Release.Name }}-okta-ldap-mapping-blueprint
  - {{ .Release.Name }}-oidc-provider-blueprint
{{- if .Values.blueprints }}
{{- with .Values.blueprints }}
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "coreweave.ingressAnnotations" -}}
annotations:
  {{- if .Values.customExternalDnsName }}
  kubernetes.io/ingress.class: {{ .Values.customIngressControllerClassAnnotation }}
  {{- end }}
  cert-manager.io/cluster-issuer: letsencrypt-prod
  traefik.ingress.kubernetes.io/redirect-entry-point: https
  ingress.kubernetes.io/force-ssl-redirect: "true"
  ingress.kubernetes.io/ssl-redirect: "true"
  kubernetes.io/ingress.allow-http: "false"
{{- if .Values.ingress.annotations }}
{{- with .Values.ingress.annotations }}
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}
