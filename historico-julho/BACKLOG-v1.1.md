# BACKLOG OFICIAL — v1.1

> **Criterio de abertura:**
> A v1.1 só deve iniciar quando houver pelo menos 30 dias de operação real
> OU demandas concretas validadas pelos operadores em produção.
> Nao iniciar desenvolvimento apenas por ideias.

---

## PRIORIDADE ALTA — Integridade de Dados

### B-01 — Save Atomico

**Objetivo:** Garantir consistência entre `bookings`, `payment_groups` e `basecamp_booking_experiences` mesmo em caso de erro de rede.

**Problema atual:**
`handleSave` executa duas sequências de operações sem transação:
1. `INSERT/UPDATE bookings`
2. `INSERT payment_groups`

Se a rede falhar entre as duas, o booking fica salvo sem grupos de pagamento — `payment_division_mode` indica `groups` ou `manual` mas a tabela `payment_groups` fica vazia. Na próxima abertura, o painel de divisão exibe estado inconsistente.

**Solucao proposta:**
- Edge Function `save-booking` recebe o payload completo e executa dentro de uma transação PostgreSQL (`BEGIN ... COMMIT`)
- Frontend chama a edge function em vez de chamar o banco diretamente
- Em caso de falha, rollback automático — nunca estado parcial

**Impacto:** Alto — integridade de dados em falha de rede durante pagamento parcelado

---

### B-02 — Controle de Concorrência no loadData()

**Objetivo:** Evitar múltiplas chamadas simultâneas ao `loadData()`.

**Problema atual:**
`loadData()` pode ser acionado simultaneamente por:
- Auto no-show (intervalo 60s)
- Refresh manual
- Após save, check-in, transferência, boarding, etc.

Chamadas concorrentes sobrescrevem o estado `bookings` em ordem não determinística, causando flash visual ou dados desatualizados por um ciclo de render.

**Possiveis abordagens:**
- Mutex via `useRef` (`isLoadingRef.current`)
- Debounce (descartar chamadas dentro de X ms após a primeira)
- Request queue (enfileirar e processar em série)
- `AbortController` para cancelar a chamada anterior antes de iniciar a nova

**Impacto:** Baixo — sem perda de dados, apenas consistência visual

---

## PRIORIDADE MEDIA — Evolução SaaS

### S-01 — Multi-tenant (pre-requisito de S-02 e S-03)

**Planejamento:**
- `company_id uuid` em todas as tabelas operacionais
- Tabela `companies` com plano, status e configurações globais
- Atualizar todas as políticas RLS para incluir verificação de `company_id`
- Fluxo de onboarding de nova empresa
- `company_settings`, `machine_configs`, `time_slots` isolados por empresa

**Nota:** S-01 é pré-requisito obrigatório de S-02 e S-03. Não iniciar S-02 ou S-03 sem S-01 finalizado.

---

### S-02 — Planos e Billing

**Planejamento:**
- Tabela `plans` com limites: máquinas, usuários, reservas/mês, módulos habilitados
- Período de teste (trial)
- Licenças vitalícias
- Integração Stripe para cobrança recorrente
- Painel de billing por empresa
- Alertas de limite de uso

**Dependência:** S-01

---

### S-03 — Autenticação via Supabase Auth

**Planejamento:**
- Migrar login para `supabase.auth.signInWithPassword()`
- Senhas bcrypt via Supabase Auth (substituir PIN de 4 dígitos em texto claro)
- MFA opcional para administradores
- Recuperação de senha por e-mail
- Vincular `app_users.id` a `auth.users.id` para políticas RLS baseadas em `auth.uid()`

**Dependência:** S-01

---

## PRIORIDADE MEDIA — Relatórios Avançados

### R-01 — Dashboard Analítico por Período

**Sugestoes:**
- Ocupação por máquina (% de slots preenchidos por dia/semana/mês)
- Receita por período
- Receita por veículo
- Receita por operador
- Ticket médio por período
- Gráfico de horários mais populares (heatmap por hora × dia da semana)
- Comparativo semana atual vs semana anterior

---

### R-02 — Relatório Financeiro Detalhado

**Sugestoes:**
- Separação receita recebida × a receber
- Receita por forma de pagamento (PIX, dinheiro, crédito, débito)
- Relatório de reservas com valor personalizado (`is_custom_value = true`) — auditoria de descontos
- Exportação CSV/Excel
- Filtro por operador, máquina, período, status, forma de pagamento

---

### R-03 — Relatórios Operacionais

**Sugestoes:**
- Taxa de conversão de reservas
- Relatório de No-show histórico
- Relatório de Não Apto
- Relatório Base Camp (adesão, pacotes mais escolhidos)
- Histórico completo por cliente (buscado por nome ou telefone)

---

## PRIORIDADE BAIXA — Melhorias de UX

### U-01 — Dashboard Mais Visual

**Sugestoes:**
- Indicadores operacionais em tempo real
- Atalhos rápidos para operações frequentes
- Timeline operacional do dia

---

### U-02 — Melhorias Mobile

**Sugestoes:**
- Busca de reservas acessível no mobile (campo oculto em telas pequenas na v1.0)
- Gaveta de resultados de busca (melhor ergonomia mobile vs dropdown)
- Filtros avançados acessíveis em mobile

---

### U-03 — Limpeza Técnica (sem impacto funcional)

- Remover colunas órfãs: `bookings.group_total_value`, `machine_configs.icon_url`, `machine_configs.icon_type`
- Limpar 3 registros `basecamp_booking_experiences` sem booking correspondente
- `handleModeChange` chamar `onGroupsChange([])` ao trocar para modo `none`/`equal`
- Verificar `BookingPaymentModal.tsx` — conectar ao fluxo real ou deletar se for código morto

---

## PRIORIDADE MEDIA — Parceiros de Venda

### P-01 — Modulo Parceiros de Venda

**Objetivo:** Permitir que pousadas, hoteis, agencias e parceiros comerciais vendam horários específicos liberados pela Trip Experience, sem acesso à agenda interna completa.

**Contexto:** A Trip Experience pode liberar apenas determinados horarios para parceiros revenderem. O parceiro acessa um link exclusivo, ve somente os slots autorizados e gera reservas que caem diretamente na agenda principal da Trip.

---

#### Escopo inicial

**1. Gestao de parceiros (admin)**
- Cadastro: nome, telefone, status (ativo/inativo)
- Modelo financeiro: preco liquido (valor Trip) ou comissao percentual
- Horarios permitidos por parceiro
- Limite de reservas por dia (opcional)
- Geracao e revogacao de link exclusivo com token unico

**2. Portal do parceiro**
- URL exclusiva: `tripmv.com/parceiro/<token>`
- Exibe somente os horarios liberados para aquele parceiro
- Nao exibe agenda completa, faturamento, clientes internos ou configuracoes
- Formulario simples de reserva (nome, telefone, horario, quantidade)

**3. Integracao com reservas**
- `bookings` recebe `partner_id` e `booking_origin = 'parceiro'`
- Registra `public_price` (valor cobrado pelo parceiro), `trip_net_price` (valor Trip), `partner_margin` (margem/comissao)
- Reserva criada pelo parceiro aparece normalmente na agenda principal
- Operador interno pode editar, confirmar ou cancelar normalmente

**4. Relatorio de parceiros (futuro)**
- Por parceiro: quantidade de reservas, valor vendido, valor liquido Trip, comissao/margem, periodo, status

---

#### O que NAO deve ser feito na v1.0.5

- Nenhuma alteracao em `bookings`, `payment_groups`, `machine_configs`, `company_settings`
- Nenhuma alteracao em permissoes internas (`app_users`, `user_sessions`)
- Nenhuma alteracao em vouchers, exportacoes, horarios ou financeiro atual
- Nenhuma alteracao no fluxo de login interno
- Nao criar tabelas ainda

---

#### Tabelas futuras sugeridas

```
partners
  id uuid PK
  name text
  phone text
  token text UNIQUE
  model text ('net_price' | 'commission')
  commission_pct numeric
  is_active boolean
  daily_limit int (nullable)
  created_at timestamptz

partner_allowed_slots
  id uuid PK
  partner_id uuid FK partners
  slot_time text (ex: '13:00')

partner_sales
  id uuid PK
  partner_id uuid FK partners
  booking_id uuid FK bookings
  public_price numeric
  trip_net_price numeric
  partner_margin numeric
  created_at timestamptz
```

Coluna adicional em `bookings`:
- `partner_id uuid NULL FK partners`
- `booking_origin text DEFAULT 'internal'`

---

#### Riscos

| Risco | Severidade | Mitigacao |
|---|---|---|
| Token do parceiro exposto ou reutilizado | Alta | Token UUID v4, revogacao imediata pelo admin |
| Parceiro ver dados internos | Alta | Portal isolado sem acesso ao painel principal |
| Overbooking via portal parceiro | Alta | Mesmo constraint UNIQUE do banco se aplica |
| Reserva parceiro sumir da agenda interna | Media | booking cai na mesma tabela, query normal |
| Confusao financeira (valor publico vs liquido) | Media | Campos separados, relatorio dedicado |

---

#### Dependencias

- Nenhuma dependencia da v1.0 e alterada
- S-01 (multi-tenant) NAO e pre-requisito para a fase 1 (empresa unica)
- S-03 (Supabase Auth) recomendado antes da fase 2 para parceiros com login proprio

---

#### Fases de implementacao sugeridas

**Fase 1 — Portal simples (sem login do parceiro)**
- Tabelas `partners` e `partner_allowed_slots`
- Admin cria parceiro e libera horarios
- Portal publico por token exibe slots e permite reservar
- Reserva grava `partner_id` em `bookings`
- Sem autenticacao no portal do parceiro

**Fase 2 — Financeiro e relatorios**
- Tabela `partner_sales`
- Registro de `public_price`, `trip_net_price`, `partner_margin`
- Relatorio admin por parceiro
- Painel simples para o parceiro ver suas proprias reservas

**Fase 3 — Parceiro com login (opcional)**
- Autenticacao propria para o parceiro (depende de S-03)
- Historico de vendas do parceiro
- Notificacoes de confirmacao

---



1. Cada item deve ser desenvolvido em branch própria: `v1.1/B-01`, `v1.1/R-01`, etc.
2. Antes de qualquer merge, executar auditoria funcional estática no escopo alterado.
3. S-01 é pré-requisito de S-02 e S-03 — não iniciar em paralelo.
4. Itens R-01, R-02, R-03 podem ser desenvolvidos em paralelo — sem dependência entre si.
5. Itens U-01, U-02, U-03 são independentes e de baixo risco — podem ser feitos em qualquer ordem.
6. Nenhum item da v1.1 deve ser implementado na branch da v1.0.
