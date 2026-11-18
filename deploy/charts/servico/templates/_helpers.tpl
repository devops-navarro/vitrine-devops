{{/* Nome do serviço, obrigatório. */}}
{{- define "servico.nome" -}}
{{- required "defina .Values.nome (clientes, catalogo ou pedidos)" .Values.nome -}}
{{- end -}}

{{/* Imagem com a tag do commit, obrigatória. */}}
{{- define "servico.imagem" -}}
{{- $repo := required "defina .Values.imagem.repositorio" .Values.imagem.repositorio -}}
{{- $tag := required "defina .Values.imagem.tag (o commit que gerou a imagem)" .Values.imagem.tag -}}
{{- if eq $tag "latest" -}}
{{- fail "imagem.tag \"latest\" não diz o que está rodando: use a tag do commit" -}}
{{- end -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}

{{/* Labels de seleção: nunca mudam entre versões, senão o Deployment não atualiza. */}}
{{- define "servico.selecao" -}}
app.kubernetes.io/name: {{ include "servico.nome" . }}
app.kubernetes.io/part-of: vitrine
{{- end -}}

{{- define "servico.labels" -}}
{{ include "servico.selecao" . }}
app.kubernetes.io/version: {{ .Values.imagem.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* Ambiente e segredos, iguais no Deployment e no Job de migração. */}}
{{- define "servico.env" -}}
# bytecode já vem compilado na imagem; o sistema de arquivos é só leitura
- name: PYTHONDONTWRITEBYTECODE
  value: "1"
{{- range $chave, $valor := .Values.ambiente }}
- name: {{ $chave }}
  value: {{ $valor | quote }}
{{- end }}
{{- range $chave, $ref := .Values.segredos }}
- name: {{ $chave }}
  valueFrom:
    secretKeyRef:
      name: {{ $ref.secret }}
      key: {{ $ref.chave }}
{{- end }}
{{- end -}}

{{/* Segurança do contêiner, igual no Deployment e no Job de migração. */}}
{{- define "servico.segurancaPod" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "servico.segurancaConteiner" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
