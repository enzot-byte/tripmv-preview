# CHANGELOG — RESERVAS PRO

---

## [v1.0.9] — 2026-06-06

### Correcoes Finais de Relatorios e Transferencias

**Status: Aprovado**

**Correcoes:**
- Transferencia para outra data agora consulta o banco diretamente para detectar conflito antes do INSERT.
- Mensagem amigavel exibida quando o slot de destino ja esta ocupado (ex: "Q3 ja esta ocupado em 07/06/2026 as 14:00").
- OperationalStats reescrito: abas Semana, Mes e Ano buscam dados reais do banco via query `gte/lte` na coluna `date`.
- Aba Hoje continua usando o array `bookings` ja carregado (sem query adicional).
- `anchorBookings` preservado em todas as abas para evitar dupla contagem de grupos multi-veiculo.
- Loading spinner exibido durante busca de periodo.
- Erro amigavel com botao "Tentar novamente" em caso de falha na query.

**Validacao:**
- 10 testes aprovados em OperationalStats (Dia, Semana, Mes, Ano, grupos, parceiro, erro).
- Transferencia cross-date validada: slot livre aceita, slot ocupado exibe mensagem amigavel, banco nao cria duplicata.
- UNIQUE constraint continua ativa como protecao final.
- Build limpo.

**Resultado:** APROVADO PARA OPERACAO.

---

## [v1.0.8] — 2026-06-06

### Persistencia das Configuracoes do Voucher

**Status: Aprovado**

**Correcao:**
- Corrigida sobrescrita de textos personalizados por valores padrao em `useConfig.ts` e `VoucherSettings.tsx`.
- Rodape, politica de cancelamento e instrucoes do voucher agora permanecem exatamente como o Admin salvou.
- Campos vazios intencionais sao preservados (operador `??` em vez de `||`).
- Corrigido debounce prematuro em `useConfig.setConfig` que podia gravar `defaultConfig` no Supabase antes do carregamento inicial completar.
- Corrigido `settingsToConfig`: substituido check de truthiness `if (settings.X)` por `if ('X' in settings)` para todos os campos de texto.

**Validacao:**
- 17 testes aprovados (rodape, politica de cancelamento, instrucoes, campo vazio intencional, outro dispositivo, cache offline).
- Persistencia entre dispositivos: APROVADO.
- Cache localStorage como fallback offline: APROVADO.

**Resultado:** APROVADO.

---

## [v1.0.7] — 2026-06-06

### Exportacao via Texto — Vendas de Parceiros

**Status: Aprovado**

**Implementacao:**
- Reescrito `ExportPanel` em `PartnersAdmin.tsx` com exportacao agrupada por parceiro.
- Formato WhatsApp conforme spec: cabecalho, bloco por parceiro (reservas, veiculos, valores, detalhes), separador, total geral.
- Cada linha de detalhe inclui data, horario, `Q{machine_id}`, cliente e valor.
- Status exibido apenas quando diferente de Confirmada/Check-in.
- Botoes: Copiar texto, Enviar WhatsApp, CSV (com coluna Veiculo), Imprimir.
- Pre-visualizacao do texto copiavel diretamente na tela.
- Acesso restrito a admin (via `PartnersAdmin` que so e renderizado para role admin).

**Validacao:**
- Exportacao agrupada por parceiro: APROVADO.
- Totais individuais e total geral corretos: APROVADO.
- Reservas internas nao aparecem no relatorio: APROVADO.
- Parceiro e operador comum nao acessam: APROVADO.

**Resultado:** APROVADO.

---

## [v1.0.6] — 2026-06-06

### Portal do Parceiro (Usuario do Sistema)

**Status: Aprovado**

**Implementacao:**
- Novo role `partner` no sistema de usuarios (`app_users`).
- Tabela `partner_user_settings` (1:1 com app_users) com horarios liberados, limite diario e modelo financeiro.
- Campo `partner_user_id` adicionado em `bookings` para rastrear origem da reserva.
- Parceiro faz login pela mesma tela de login do sistema — sem portal publico por token.
- Apos login, parceiro e redirecionado para o `PartnerPortal`, tela exclusiva com:
  - Visualizacao de disponibilidade apenas nos horarios liberados.
  - Formulario de reserva com calculo automatico de comissao.
  - Aba "Minhas Reservas" (apenas as proprias).
  - Aba "Relatorio" com totais por periodo.
- Admin > Parceiros reescrito: cria usuario com login, senha, horarios, modelo financeiro e limite diario.
- Exportacao de vendas de parceiros no Admin (CSV, WhatsApp, Imprimir).

**Correcoes:**
- Corrigido bug de timing no carregamento de maquinas (`activeMachineCount` adicionado as dependencias do `useEffect`).
- Backend revalida `allowed_time_slots`, `is_active` e `max_bookings_per_day` antes de criar reserva.

**Validacao:**
- Parceiro com 13:00 e 14:00 ve apenas 13:00 e 14:00: APROVADO.
- Parceiro com apenas 13:00 ve apenas 13:00: APROVADO.
- Parceiro sem horarios liberados ve mensagem de aviso: APROVADO.
- Tela nao fica vazia por erro de timing de carregamento: APROVADO.
- Tentativa de reserva em horario nao permitido via manipulacao: BLOQUEADO.
- Admin e Operador continuam vendo todos os horarios: APROVADO.

**Resultado:** APROVADO.

---

## [v1.0.5] — 2026-06-04

### Seguranca do Storage company-assets

**Status: Aprovada**

**Correcao:**
- Removidas policies anonimas de INSERT, UPDATE e DELETE do bucket `company-assets`.
- Mantida leitura publica para exibicao de logo e icones.
- Upload de logo e app icon migrado para Edge Function segura (`upload-company-asset`).
- Apenas admin e manager com sessao ativa podem alterar assets da empresa.

**Validacao:**
- Header carrega logo: APROVADO.
- Voucher PDF carrega logo: APROVADO.
- Voucher Imagem carrega logo: APROVADO.
- Preview Admin carrega logo: APROVADO.
- Upload anonimo bloqueado: APROVADO.
- Usuario sem permissao bloqueado: APROVADO.
- Security Advisor sem alerta de escrita anonima: APROVADO.

**Resultado:** APROVADO.

---

## [v1.0.4] — 2026-06-04

### Correcao dos criticos de estabilidade

**Status: Aprovada**

Correcoes criticas validadas:

**1. Dupla reserva / Q9+**
- UNIQUE constraint preservado.
- CHECK antigo removido.
- Q9 a Q20 aceitos.
- Segunda tentativa de reserva no mesmo slot falha corretamente.

**2. Grupos de pagamento atomicos**
- Salvamento migrado para funcao transacional no banco.
- Se falhar, faz rollback.
- Nao deixa booking sem payment_groups.

**3. Realtime durante edicao**
- Modal rastreado por group_id.
- Alteracao externa detectada sem sobrescrever campos em edicao.
- Banner laranja exibido ao operador.

**4. Duplo check-in**
- isSubmittingRef bloqueia duplo clique.
- Botao desabilitado durante envio.
- Banco relido antes do update.
- Operacao idempotente.

**Resultado:** Todos os 4 criticos aprovados em validacao.

**Observacao:** Altos, medios e baixos permanecem no backlog para avaliacao separada.

---

## [v1.0.3] — 2026-06-04

### Sincronizacao de Configuracoes

**Status: Aprovada para operacao**

**Correcoes:**
- `useConfig` passou a usar `company_settings` no Supabase como fonte oficial de todas as configuracoes gerais.
- `localStorage` deixou de ser fonte primaria e passou a ser apenas cache offline da ultima configuracao valida recebida do Supabase.
- Cache offline atualizado apos cada carga bem-sucedida do Supabase, inclusive as disparadas por realtime.
- Configuracoes gerais (nome da empresa, WhatsApp, Maps, logo, textos do voucher, taxa de reserva, valor padrao do veiculo) agora sincronizam entre multiplos dispositivos via realtime.

**Validacao realizada em 04/06/2026:**
- Supabase online: APROVADO.
- Fallback offline: APROVADO.
- `machine_configs`: sem regressao.
- Horarios dinamicos: sem regressao.
- Exportacoes: sem regressao.
- Transferencias: sem regressao.

**Ressalva remanescente:**
- `CheckInPage.tsx` ainda lê configuracoes do `localStorage` (pagina de uso nao operacional no momento). Incluida no backlog para migracao futura.

---

## [v1.0.2] — 2026-06-04

### Correcoes Operacionais

**Status: Aprovada para operacao**

**Correcoes:**
- Removido limite de 8 veiculos no banco — constraints `machine_id <= 8` removidas de `bookings` e `machine_configs`.
- Reservas Q9+ aprovadas — testes realizados com Q9, Q10 e multipla Q1 + Q9.
- Horarios dinamicos validados — adicionar e remover horarios no Admin reflete imediatamente na grade.
- WhatsApp corrigido usando `wa.me` — encoding correto, sem tela branca no mobile.
- Valor personalizado por maquina validado — 3 maquinas x R$ 400 = R$ 1.200 sem dupla contagem.
- Exportacoes PDF, imagem e texto validadas com valores corretos.
- Senhas hardcoded removidas do frontend — `ADMIN_PASSWORD`, `MANAGER_PASSWORD`, `MAINTENANCE_PASSWORD` eliminadas; acesso passa a depender exclusivamente das permissoes reais do usuario logado.
- Modal de senha removido do `ReportExport.tsx`.
- `verifyMaintenanceAccess` reescrita para usar `isAdminMode || isManagerMode`, sem prompt de senha.

**Ressalva:**
- Algumas configuracoes gerais ainda usam `localStorage` como fonte primaria (chave `trip_exp_config_v17`).
- Em ambientes com multiplos dispositivos, mudancas de configuracao feitas no Admin podem nao refletir imediatamente em celulares com cache local desatualizado.
- Migracao completa de configuracoes gerais para Supabase incluida no backlog v1.1.

**Auditoria de seguranca realizada em 04/06/2026:**
- Nenhuma senha fixa encontrada em nenhum arquivo `.ts`/`.tsx` do projeto.
- 10 chaves de `localStorage` auditadas — 3 classificadas como criticas para futura migracao.

---

### Patch anterior: Remocao do limite de veiculos

- Removida constraint `bookings_machine_id_check` que limitava reservas ate Q8.
- Nova regra permite `machine_id >= 1`, sem limite superior.
- Sistema agora aceita reservas para qualquer veiculo ativo configurado no Admin.
- Removida tambem a constraint equivalente em `machine_configs`.
- Modal "Configurar Numero de Veiculos" simplificado: dois inputs confusos unificados em um; campo sem `max` fixo.
- `updateMachineCount` corrigido para criar maquinas inexistentes via INSERT, nao apenas UPDATE.

---

## [v1.0.1] — 2026-06-04

### Correcao: Valor Personalizado por Maquina

- **PaymentDivisionPanel corrigido:** o componente recebia `unitValue` derivado de `total_value / machineCount`, ignorando o valor customizado. Agora usa `customUnitValue` como fonte principal, com fallback para `unit_value_at_booking` e por ultimo a derivação por divisão.
- **customUnitValue como fonte canonica:** toda a cadeia de cálculo (useEffect, onChange, PaymentDivisionPanel) passa a usar `customUnitValue` diretamente quando `is_custom_value = true`, eliminando recálculos em cascata.
- **Campo vinculado ao unitário:** o campo de entrada do valor passou a exibir o valor por máquina (não o total), evitando que a máscara de centavos lesse o total multiplicado como base para o próximo dígito.
- **Divisão total_value / machineCount restrita a fallback:** mantida apenas para reservas antigas sem `unit_value_at_booking` preenchido; nunca executada quando `customUnitValue > 0`.
- **Auditoria realizada em 04/06/2026:** todos os pontos críticos verificados (useEffect, onChange, exportações, getGroupFinancials, VoucherPDF, VoucherImage, handleSlotClick, handleBookingSelectFromHeader). Nenhuma regressão identificada. Resultado: APROVADO.

---

## [v1.0 ESTAVEL] — 2026-06-04

> **STATUS: APROVADA PARA PRODUCAO**
> Data de Congelamento: 04/06/2026
>
> A versão v1.0 é considerada estável e apta para operação real.
> O foco deixa de ser desenvolvimento e passa a ser estabilidade operacional.

---

## REGRAS DA VERSAO v1.0

### NAO IMPLEMENTAR

- Novas funcionalidades
- Novos fluxos financeiros
- Alterações na lógica de veículos
- Alterações em pagamentos
- Alterações em vouchers
- Alterações em exportações
- Mudanças estruturais no banco de dados
- Refatorações sem necessidade

### PERMITIDO

- Correção de bugs reais encontrados em operação
- Ajustes visuais pequenos
- Correções de textos
- Correções de permissões
- Correções de segurança
- Correções de performance sem alterar comportamento

---

## MODULOS CONGELADOS

- Reservas
- Multi-veículos
- Valor personalizado / unit_value_at_booking
- Pagamentos / Divisão de pagamento
- Voucher padrão / Voucher Base Camp
- WhatsApp / PDF / Impressão
- Check-in / Embarque / Não Apto
- Transferência / Exclusão
- Documentos / Políticas
- Dashboard / Relatórios atuais

---

## 1. FUNCIONALIDADES IMPLEMENTADAS NA v1.0

### Reservas

- Criação de reserva com veículo principal e até N veículos adicionais no mesmo horário
- Agrupamento de reservas multi-veículo por `group_id` — todas as operações (editar, excluir, pagar) atuam sobre o grupo de forma atômica
- Detecção e bloqueio de conflito real: mesma máquina + mesmo horário + mesma data (constraint de banco + validação frontend)
- Alerta de nome semelhante (sem bloqueio) — compara palavras do nome, mesmo dia, apenas status ativos
- Alerta de telefone/WhatsApp duplicado (sem bloqueio) — comparação exata de dígitos, mínimo 8 dígitos
- Campo opcional "Telefone / WhatsApp" no formulário de reserva
- Transferência de reserva para outra data/horário com preservação do histórico (`transferred_from`)
- Transferência copia: `has_basecamp`, `is_custom_value`, `unit_value_at_booking`, `payment_method`, `payment_division_mode`, `customer_phone`
- Exclusão individual ou de grupo completo (com confirmação explícita)
- Bloqueio de horário por máquina (dia todo ou horário único)
- Check-in e Confirmação de Embarque como operações independentes
- Marcação de No-show com registro de operador e timestamp
- Marcação "Não Apto para Pilotar" com motivo, observação, operador e timestamp — status `NOT_FIT` persistido no banco
- Reversão de "Não Apto" com restauração de status anterior
- `readable_id` gerado automaticamente pelo banco para identificação amigável

### Header Search

- Busca de reservas por ID ou nome no cabeçalho
- Abertura pelo resultado da busca reseta completamente o estado do modal: `additionalMachines`, `customUnitValue`, `paymentGroups`, `paymentDivisionMode`, `isEditingTotalValue`
- Comportamento idêntico ao click direto no slot da grade

### Precificação e Valores

- `unit_value_at_booking`: valor por máquina travado no momento da criação da reserva. Mudanças posteriores na taxa do Admin não afetam reservas já salvas.
- Indicador visual de origem do valor (verde = padrão / azul = histórico / âmbar = personalizado)
- `is_custom_value`: flag que desativa o recálculo automático quando o operador digita um valor manualmente
- Edição manual do valor total atualiza simultaneamente: `total_value`, `customUnitValue`, `unit_value_at_booking`, `is_custom_value`
- Botão "Usar valor padrão atual" para atualizar reservas existentes para a taxa vigente

### Pagamentos

- Modos de divisão: Sem divisão / Igualmente / Por grupos / Manual
- Modos `groups` e `manual` bloqueiam o recálculo automático do total
- `PaymentDivisionPanel` preserva valores configurados manualmente — usar máquinas entre grupos não sobrescreve valores já definidos pelo operador
- `Restante = Total − Pago` calculado de forma consistente em todos os pontos de exibição e exportação
- Histórico de pagamentos por grupo via tabela `payment_groups`

### Exportações

- WhatsApp texto, WhatsApp imagem (canvas), PDF, Impressão direta
- Todas as exportações usam valores salvos no banco — nenhuma recalcula

### Voucher

- Voucher padrão para horários 10h–16h
- Voucher Base Camp exclusivo para o horário 17h (layout diferenciado)
- Configuração visual completa via painel Admin

### Base Camp

- Habilitação/desabilitação com motivo visível para o operador
- Gerenciamento de itens e pacotes da experiência
- Seleção de experiência por reserva persistida em `basecamp_booking_experiences`

### Documentos e Políticas

- Gaveta de documentos por reserva: Política de Cancelamento, Aptidão, Termo de Riscos
- Envio individual ou em lote via WhatsApp
- Registro em `document_send_logs` com status (`not_sent`, `sent`, `signed`, `refused`)

### Gestão de Usuários e Permissões

- Usuários com 4 papéis: admin, manager, operator, maintenance
- 17 flags de permissão granular por usuário

### Dashboard e Relatórios

- Estatísticas operacionais por dia, semana, mês e ano
- `anchorBookings()` — deduplicação correta de reservas multi-veículo
- Log de atividades por operador
- Exportação de relatório via WhatsApp

---

## 2. BUGS CORRIGIDOS NA v1.0

### B1 — DELETE sem group_id deixava registros órfãos (ALTO)

Ao excluir grupos sem `group_id` legado, o cleanup usava apenas o ID do booking principal. Corrigido para percorrer todos os bookings do grupo e coletar IDs únicos.

**Arquivo:** `src/App.tsx`

---

### B2 — Exclusão de pacote Base Camp deixava itens órfãos (MEDIO)

`deletePackage` não removia registros filhos em `basecamp_package_items` antes de deletar o pacote.

**Arquivo:** `src/hooks/useBaseCamp.ts`

---

### B3 — is_custom_value undefined em nova reserva (MEDIO)

Campo não inicializado explicitamente. Corrigido para `is_custom_value: false` na criação.

**Arquivo:** `src/App.tsx`

---

### B4 — Header Search contaminava estado entre reservas (CRITICO)

`handleBookingSelectFromHeader` não resetava `additionalMachines`, `customUnitValue`, `paymentGroups`, `paymentDivisionMode`, `isEditingTotalValue`. Corrigido para executar reset completo idêntico ao `handleSlotClick`.

**Arquivo:** `src/App.tsx`

---

### B5 — Edição manual do total não atualizava unit_value_at_booking (CRITICO)

`onChange` do campo de valor total atualizava `total_value` e `is_custom_value` mas não `unit_value_at_booking`. Corrigido para atualizar os três simultaneamente em um único `setCurrentBooking`.

**Arquivo:** `src/App.tsx`

---

### B6 — Transferência não copiava 6 campos críticos (MEDIO)

O INSERT de transferência omitia: `has_basecamp`, `is_custom_value`, `unit_value_at_booking`, `payment_method`, `payment_division_mode`, `customer_phone`. Corrigido para incluir todos.

**Arquivo:** `src/App.tsx`

---

### B7 — PaymentDivisionPanel sobrescrevia valores configurados (MEDIO)

`toggleMachine` e `updateGroup` usavam o prop `unitValue` para recalcular `totalValue` de grupos. Se `unitValue` mudasse entre o momento da configuração e o próximo click, os valores eram sobrescritos. Corrigido para usar a taxa por-máquina do próprio grupo (`g.totalValue / g.machineIds.length`).

**Arquivo:** `src/components/PaymentDivisionPanel.tsx`

---

## 3. SEGURANCA E INTEGRIDADE

- 36 tabelas com Row Level Security habilitado — sem exceções
- Nenhuma política usa `USING (true)` (acesso irrestrito)
- `unit_value_at_booking` garante imutabilidade do preço histórico
- Nenhuma exportação recalcula valores — todas leem do banco
- `getGroupFinancials` sem risco de multiplicação de total
- `anchorBookings()` deduplica por `group_id` antes de qualquer soma

---

## 4. REGRAS FINANCEIRAS IMUAVEIS NA v1.0

| Regra | Implementação |
|---|---|
| Valor total existente nunca muda silenciosamente | `unit_value_at_booking` travado na criação |
| Mudança de taxa no Admin não afeta reservas salvas | Reservas leem `unit_value_at_booking`, não `getSuggestedValue()` |
| Adicionar veículos multiplica o unitário, nunca o total existente | `total = unit_value_at_booking × (additionalMachines.length + 1)` |
| Valor personalizado desativa recálculo automático | `customUnitValue` como base; useEffect verifica a flag |
| Modos groups/manual bloqueiam qualquer recálculo | useEffect retorna cedo se `paymentDivisionMode === 'groups' | 'manual'` |
| Restante = Total − Pago, nunca de outra forma | `Math.max(0, total - paid)` em todos os 7 pontos de exibição |

---

## 5. AUDITORIA FINAL (v462 — 04/06/2026)

```
[x] Build TypeScript limpo — 0 erros, 0 warnings críticos
[x] 36 tabelas com RLS ativo — sem tabela desprotegida
[x] 0 bugs críticos remanescentes
[x] 0 bugs médios de impacto real remanescentes
[x] unit_value_at_booking protege o valor histórico de cada reserva
[x] Nenhuma exportação recalcula valores
[x] getGroupFinancials sem risco de soma dupla
[x] Conflito de máquina bloqueado em 2 camadas (banco + frontend)
[x] Divisão de pagamento não altera total_value
[x] Header search reseta estado completo antes de abrir reserva
[x] Edição manual do total atualiza os 3 campos simultaneamente
[x] Transferência copia todos os campos críticos
[x] PaymentDivisionPanel preserva valores configurados pelo operador
```

---

## NOTAS PARA MANUTENCAO FUTURA (v1.0)

Para qualquer desenvolvedor que precisar corrigir um bug real nesta versão:

- Nunca somar `total_value` de siblings diretamente — usar sempre `anchorBookings()` ou `getGroupFinancials()`
- Nunca remover `unit_value_at_booking` do INSERT/UPDATE — é a garantia de imutabilidade do preço histórico
- Ao adicionar novos campos ao booking, incluí-los nos dois payloads: INSERT (novo booking) e `sharedFields` (UPDATE de grupo) — e também no INSERT de transferência
- O campo `customer_phone` é salvo como `null` quando vazio — nunca como string vazia
- Ao criar novas tabelas, sempre habilitar RLS e criar políticas restritivas. Nunca usar `USING (true)`
