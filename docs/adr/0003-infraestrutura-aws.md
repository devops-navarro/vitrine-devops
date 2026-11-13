# ADR 0003 · Infraestrutura na AWS: módulos, custo e testes sem conta

- **Status:** aceita

## Contexto

A Vitrine vai rodar na AWS (EKS, RDS, ECR), descrita em Terraform. A conta é pessoal: cada hora ligada é paga do próprio bolso, e o ambiente existe para estudo, não para atender usuário. Ao mesmo tempo, o código precisa ser o que se usaria em produção, porque é o que vai ser lido numa entrevista.

Quatro perguntas precisavam de resposta:

1. Como organizar o Terraform para servir tanto ao laboratório quanto a um ambiente de produção?
2. Como manter o custo baixo sem fazer um código "de brinquedo"?
3. Como testar tudo sem conta AWS, já que o apply real é raro e manual?
4. Que decisões de arquitetura valem para qualquer ambiente?

## Decisão

**Módulos com padrões de produção; ambientes que escolhem, por escrito, quando abrir mão.**

- `infra/modules/` tem um módulo por responsabilidade (estado remoto, rede, ECR, RDS, EKS, OIDC do GitHub, orçamento), cada um com testes. Os padrões são os seguros: RDS com Multi-AZ, proteção contra exclusão e snapshot final; NAT por variável; API do EKS privada.
- `infra/envs/` compõe os módulos. O `dev` desliga o que não faz sentido num ambiente de algumas horas (Multi-AZ, proteção, snapshot) **na chamada do módulo**, com o motivo, e o Checkov registra a exceção.

**Custo:** um NAT só, nós Spot com Graviton (`t4g`), RDS `db.t4g.micro` numa AZ, e o ambiente criado e destruído a cada sessão pelo runbook. Orçamento com alerta de previsão como rede de segurança. Estimativa: cerca de US$ 0,22 por hora.

**Testes sem conta, em camadas:**

| Camada | Ferramenta | O que pega |
| --- | --- | --- |
| Sintaxe e tipos | `terraform validate` | Erro de digitação, tipo errado |
| Erros da AWS e boas práticas | tflint com plugin AWS | Tipo de instância inexistente, variável não usada |
| Configuração insegura | Checkov | Bucket público, sem cifra, IAM largo |
| Regras de cada módulo | `terraform test` com `mock_provider` | "A rota privada sai pelo NAT", "o banco não é público" |
| Apply de verdade | Moto (emulador) | O módulo sobe, o plan seguinte não muda nada, o destroy funciona |

Tudo roda no CI, sem nenhuma credencial da AWS. O apply na conta real segue o [runbook](../runbook-aws.md) e é feito por uma pessoa.

**Decisões de arquitetura:**
- **State** no S3 com lock nativo (`use_lockfile`), sem DynamoDB; bucket versionado, cifrado com KMS próprio e só com TLS.
- **Acesso do CI** por OIDC, com `sub` exato do repositório e da branch; nenhuma chave guardada.
- **Acesso ao cluster** por access entries declaradas; nada de "quem criou vira admin".
- **Permissão de pod** por EKS Pod Identity, não por IRSA: não depende de provider OIDC por cluster e a associação fica na API do EKS.
- **Senha do banco** gerada e guardada pela AWS (`manage_master_user_password`); nunca passa pelo state.
- **Exposição** por ALB com WAF ([ADR 0002](0002-exposicao-com-alb-e-waf.md)).

## Alternativas consideradas

- **Um módulo grande com tudo, ou o módulo da comunidade `terraform-aws-modules`.** O da comunidade é maduro e seria a escolha num time; aqui o objetivo é mostrar domínio de cada peça, e módulos próprios e pequenos deixam cada decisão visível e testada.
- **Workspaces ou Terragrunt para os ambientes.** Com um ambiente só, seriam complexidade sem uso. Ficam para a fase de melhorias, quando houver dev e prod.
- **LocalStack como emulador.** As versões atuais exigem token de conta mesmo no plano gratuito; o Moto é de código aberto e cobre o que o projeto precisa (S3, KMS, IAM, EC2, ECR, CloudWatch Logs).
- **IRSA em vez de Pod Identity.** Funciona e ainda é muito comum; Pod Identity é o caminho que a AWS recomenda para clusters novos e tem menos peças.
- **Ambiente ligado o tempo todo.** Mais perto de produção, mas passaria de US$ 150 por mês para um projeto de estudo.

## Consequências

- O mesmo código serve a produção: basta um ambiente que não desligue as proteções.
- O apply real é raro, então a confiança vem dos testes e do emulador. O que o emulador não cobre (EKS, RDS) só é provado no apply real, pelo runbook.
- Imagens precisam ser multi-arquitetura (`linux/arm64`), por causa dos nós Graviton.
- O emulador tem limites conhecidos e documentados (tags de bucket via S3 Control, condição `aws:SecureTransport`).
- O bucket do state e a chave KMS dele ficam sempre existindo (cerca de US$ 1 por mês); o resto nasce e morre a cada sessão.
