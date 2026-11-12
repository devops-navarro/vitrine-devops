# ADR 0002 · Exposição das APIs na AWS com ALB e WAF

- **Status:** aceita

## Contexto

As APIs vão rodar no EKS, em subnets privadas. Elas precisam ser alcançadas da internet com TLS, proteção contra ataques comuns na camada HTTP (injeção, bots, excesso de requisições) e sem expor o que é só interno: `/metrics`, `/docs` e o banco.

As duas opções gerenciadas mais usadas na AWS para isso são o Application Load Balancer com AWS WAF e o Amazon API Gateway.

## Decisão

**Route 53 → ALB público com certificado do ACM e AWS WAF associado → pods no EKS.**

- O ALB é criado pelo AWS Load Balancer Controller a partir de um `Ingress` do Kubernetes, que fica versionado com o resto do deploy.
- O `Ingress` publica só os prefixos de negócio: `/clientes`, `/produtos` e `/pedidos`. `/metrics`, `/docs`, `/openapi.json`, `/health` e `/ready` não têm rota pública.
- TLS termina no ALB (certificado do ACM, renovação automática), com redirecionamento de HTTP para HTTPS e política TLS 1.2 ou superior.
- WAF com as regras gerenciadas da AWS (Core rule set, Known bad inputs, SQL database, Amazon IP reputation list) e uma regra de limite por IP.
- O security group dos nós só aceita tráfego vindo do security group do ALB. O banco (RDS) fica em subnet privada, sem acesso público, aceitando só os nós.
- A API key continua sendo validada pela aplicação. O WAF filtra o tráfego; quem decide se o chamador é conhecido é o serviço.

## Alternativas consideradas

- **API Gateway (HTTP API) com VPC Link para um ALB ou NLB interno.** Traz autorizador JWT, throttling e planos de uso por cliente prontos. Rejeitada por agora: é mais uma camada a pagar e operar na frente do mesmo ALB, tem limite de 30 s por requisição, e a configuração de rotas sairia do Kubernetes para o Terraform, separando o que hoje fica junto. Volta a fazer sentido se a Vitrine abrir a API para parceiros com cota por cliente.
- **Service do tipo `LoadBalancer` (NLB) direto.** Funciona na camada 4, então não permite WAF nem roteamento por caminho. Rejeitada.
- **Ingress NGINX com um NLB na frente.** Dá mais controle sobre o proxy, mas o WAF da AWS não se associa a NLB, e o NGINX vira mais um componente a manter. Rejeitada.
- **CloudFront na frente do ALB.** Ajuda com cache e com tráfego global. As APIs não são cacheáveis e o público é nacional; fica como evolução se houver front-end estático.

## Consequências

- Um ALB por ambiente, cobrado por hora mais o uso. Ele é destruído junto com o ambiente ao fim de cada sessão de estudo.
- Limite por cliente (cota, plano) não existe na borda: só o limite por IP do WAF. Se for preciso, entra rate limiting na aplicação ou o API Gateway.
- As regras gerenciadas do WAF podem bloquear requisições legítimas. Elas começam em modo de contagem (`count`) e passam a bloquear depois de observadas nas métricas do WAF.
- Toda a configuração de borda fica em código: `Ingress` no repositório de deploy, WAF e certificado no Terraform.
