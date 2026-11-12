mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

variables {
  nome_papel            = "vitrine-pipeline"
  repositorio           = "devops-navarro/vitrine-devops"
  arns_repositorios_ecr = ["arn:aws:ecr:us-east-1:123456789012:repository/vitrine/clientes"]
}

run "so_este_repositorio_e_a_main_assumem" {
  command = apply

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.confianca.statement : anytrue([
        for c in st.condition :
        c.variable == "token.actions.githubusercontent.com:sub" && c.test == "StringEquals" &&
        tolist(c.values) == tolist(["repo:devops-navarro/vitrine-devops:ref:refs/heads/main"])
      ])
    ])
    error_message = "Só execuções deste repositório na main podem assumir o papel, com comparação exata."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.confianca.statement : anytrue([
        for c in st.condition : c.variable == "token.actions.githubusercontent.com:aud" && contains(c.values, "sts.amazonaws.com")
      ])
    ])
    error_message = "O token precisa ter sido emitido para a AWS (aud)."
  }

  assert {
    condition = !anytrue(flatten([
      for st in data.aws_iam_policy_document.confianca.statement : [for c in st.condition : [for v in c.values : strcontains(v, "*")]]
    ]))
    error_message = "A política de confiança não pode ter curinga."
  }
}

run "escrita_so_nos_repositorios_informados" {
  command = plan

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.publicar_imagens.statement :
      st.sid == "LoginNoRegistro" ? toset(st.actions) == toset(["ecr:GetAuthorizationToken"]) : toset(st.resources) == toset(var.arns_repositorios_ecr)
    ])
    error_message = "Só o login pode ter recurso \"*\"; a publicação fica limitada aos repositórios informados."
  }

  assert {
    condition = !anytrue(flatten([
      for st in data.aws_iam_policy_document.publicar_imagens.statement : [for a in st.actions : strcontains(a, "*") || strcontains(a, "Delete")]
    ]))
    error_message = "O pipeline não pode ter ação com curinga nem apagar imagens."
  }
}

run "usa_provider_existente_quando_pedido" {
  command = plan

  variables {
    criar_provider_oidc = false
  }

  override_data {
    target = data.aws_iam_openid_connect_provider.github[0]
    values = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "Com criar_provider_oidc = false, o provider existente é reaproveitado."
  }
}

run "repositorio_com_curinga_e_recusado" {
  command = plan

  variables {
    repositorio = "devops-navarro/*"
  }

  expect_failures = [var.repositorio]
}

run "branch_com_curinga_e_recusada" {
  command = plan

  variables {
    branches = ["*"]
  }

  expect_failures = [var.branches]
}

run "ecr_com_curinga_e_recusado" {
  command = plan

  variables {
    arns_repositorios_ecr = ["arn:aws:ecr:us-east-1:123456789012:repository/*"]
  }

  expect_failures = [var.arns_repositorios_ecr]
}
