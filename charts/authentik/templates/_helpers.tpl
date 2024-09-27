{{/* vim: set filetype=mustache: */}}

{{/*
Create authentik server name and version as used by the chart label.
*/}}
{{- define "authentik.server.fullname" -}}
{{- printf "%s-%s" (include "authentik.fullname" .) .Values.server.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create authentik server worker and version as used by the chart label.
*/}}
{{- define "authentik.worker.fullname" -}}
{{- printf "%s-%s" (include "authentik.fullname" .) .Values.worker.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create authentik configuration environment variables.
*/}}
{{- define "authentik.env" -}}
    {{- range $k, $v := .values -}}
        {{- if kindIs "map" $v -}}
            {{- range $sk, $sv := $v -}}
                {{- include "authentik.env" (dict "root" $.root "values" (dict (printf "%s__%s" (upper $k) (upper $sk)) $sv)) -}}
            {{- end -}}
        {{- else -}}
            {{- $value := $v -}}
            {{- if or (kindIs "bool" $v) (kindIs "float64" $v) (kindIs "int" $v) (kindIs "int64" $v) -}}
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

{{/*
Common deployment strategy definition
- Recreate doesn't have additional fields, we need to remove them if added by the mergeOverwrite
*/}}
{{- define "authentik.strategy" -}}
{{- $preset := . -}}
{{- if (eq (toString $preset.type) "Recreate") }}
type: Recreate
{{- else if (eq (toString $preset.type) "RollingUpdate") }}
type: RollingUpdate
{{- with $preset.rollingUpdate }}
rollingUpdate:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Common affinity definition
Pod affinity
  - Soft prefers different nodes
  - Hard requires different nodes and prefers different availibility zones
Node affinity
  - Soft prefers given user expressions
  - Hard requires given user expressions
*/}}

{{- define "authentik.matchExpressions" -}}
{{- $root := .root -}}
{{- range $expr := .matchExpressions }}
- key: {{ tpl $expr.key $root }}
  operator: {{ tpl $expr.operator $root }}
  values:
    {{- range $value := $expr.values }}
    - {{ tpl $value $root }}
    {{- end }}
{{- end }}
{{- end -}}

{{- define "authentik.affinity" -}}
{{- $context := .context -}}
{{- $component := .component -}}
{{- with $component.affinity -}}
  {{- toYaml . -}}
{{- else -}}
  {{- $preset := $context.Values.global.affinity -}}
  {{- if (eq $preset.podAntiAffinity "soft") }}
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              {{- include "authentik.selectorLabels" (dict "context" $context "component" $component.name) | nindent 14 }}
          topologyKey: kubernetes.io/hostname
  {{- else if (eq $preset.podAntiAffinity "hard") }}
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              {{- include "authentik.selectorLabels" (dict "context" $context "component" $component.name) | nindent 14 }}
          topologyKey: topology.kubernetes.io/zone
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            {{- include "authentik.selectorLabels" (dict "context" $context "component" $component.name) | nindent 14 }}
        topologyKey: kubernetes.io/hostname
  {{- end }}
  {{- with $preset.nodeAffinity.matchExpressions }}
    {{- if (eq $preset.nodeAffinity.type "soft") }}
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      preference:
        matchExpressions:
          {{- include "authentik.matchExpressions" (dict "matchExpressions" $preset.nodeAffinity.matchExpressions "root" $context) | indent 8 }}
{{- else if (eq $preset.nodeAffinity.type "hard") }}
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          {{- include "authentik.matchExpressions" (dict "matchExpressions" $preset.nodeAffinity.matchExpressions "root" $context) | indent 8 }}
    {{- end }}
  {{- end }}
{{- end }}
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
{{- define "coreweave.env" -}}
- name: AUTHENTIK_POSTGRESQL__PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-postgresql
      key: password
- name: AUTHENTIK_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: secret_key
- name: AUTHENTIK_BOOTSTRAP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: akadmin_password
- name: AUTHENTIK_BOOTSTRAP_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: bootstrap_token
- name: AUTHENTIK_BOOTSTRAP_EMAIL
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: admin_email
- name: AUTHENTIK_LDAP_SVC_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-keys
      key: ldapsvc_password
{{- range ((.Values).customBlueprints).oidcProvider }}
- name: {{ printf "oidc-%s-client-id" .name }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-oidc-%s-keys" $.Release.Name .name }}
      key: {{ printf "oidc-%s-client-id" .name }}
- name: {{ printf "oidc-%s-client-secret" .name }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-oidc-%s-keys" $.Release.Name .name }}
      key: {{ printf "oidc-%s-client-secret" .name }}
{{- end }}
{{- range ((.Values).customBlueprints).users }}
{{- if ne .generatePassword "false" }}
- name: {{ printf "%s_password" .userName }}
  valueFrom:
    secretKeyRef:
      name: {{ printf "%s-%s-keys"  $.Release.Name .userName }}
      key: {{ printf "%s_password" .userName }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "coreweave.blueprints" -}}
blueprints:
  - {{ .Release.Name }}-ldap-provider-blueprint
  - {{ .Release.Name }}-users-blueprint
  - {{ .Release.Name }}-users-passwords-blueprint
  - {{ .Release.Name }}-groups-blueprint
  - {{ .Release.Name }}-ldap-federation-blueprint
  - {{ .Release.Name }}-google-ldap-mapping-blueprint
  - {{ .Release.Name }}-okta-ldap-mapping-blueprint
  - {{ .Release.Name }}-oidc-provider-blueprint
  - {{ .Release.Name }}-require-mfa
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
{{- if .Values.server.ingress.annotations }}
{{- with .Values.server.ingress.annotations }}
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}
