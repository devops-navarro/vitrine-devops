locals {
  # Gasto real em 50% e 80%; previsão do mês acima de 100% avisa antes de estourar.
  alertas = [
    { tipo = "ACTUAL", percentual = 50 },
    { tipo = "ACTUAL", percentual = 80 },
    { tipo = "FORECASTED", percentual = 100 },
  ]
}

resource "aws_budgets_budget" "this" {
  name         = var.nome
  budget_type  = "COST"
  limit_amount = tostring(var.limite_mensal_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "cost_filter" {
    for_each = var.filtro_tag_projeto == "" ? [] : [var.filtro_tag_projeto]

    content {
      name = "TagKeyValue"
      # formato do filtro de tag do Budgets: user:<chave>$<valor>
      values = [format("user:projeto%s%s", "$", cost_filter.value)]
    }
  }

  dynamic "notification" {
    for_each = local.alertas

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.percentual
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.tipo
      subscriber_email_addresses = var.emails
    }
  }
}
