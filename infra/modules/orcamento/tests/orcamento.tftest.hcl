mock_provider "aws" {}

variables {
  nome              = "vitrine-teste"
  limite_mensal_usd = 30
  emails            = ["alertas@example.com"]
}

run "avisa_em_50_80_e_na_previsao_de_estouro" {
  command = plan

  assert {
    condition = toset([for n in aws_budgets_budget.this.notification : "${n.notification_type}:${n.threshold}"]) == toset([
      "ACTUAL:50", "ACTUAL:80", "FORECASTED:100",
    ])
    error_message = "Alertas esperados: 50% e 80% do gasto real e 100% da previsão do mês."
  }

  assert {
    condition     = aws_budgets_budget.this.limit_amount == "30" && aws_budgets_budget.this.time_unit == "MONTHLY"
    error_message = "Limite mensal em dólares."
  }
}

run "filtra_pela_tag_do_projeto" {
  command = plan

  variables {
    filtro_tag_projeto = "vitrine"
  }

  assert {
    condition     = one(aws_budgets_budget.this.cost_filter).values == tolist([format("user:projeto%s%s", "$", "vitrine")])
    error_message = "Com filtro, o orçamento conta só os recursos com projeto=vitrine."
  }
}

run "email_invalido_e_recusado" {
  command = plan

  variables {
    emails = ["nao-e-email"]
  }

  expect_failures = [var.emails]
}

run "limite_zero_e_recusado" {
  command = plan

  variables {
    limite_mensal_usd = 0
  }

  expect_failures = [var.limite_mensal_usd]
}
