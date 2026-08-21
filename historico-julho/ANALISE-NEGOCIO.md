# ANÁLISE DE NEGÓCIO — TripMV

> Documento para o dono do produto. Objetivo: você terminar de ler sabendo **tudo** sobre o negócio que este software representa — o que ele faz, quem usa, como ganha dinheiro, onde está o modelo de dados e, principalmente, onde estão as dores e as oportunidades. Escrito em linguagem de negócio; onde há afirmação técnica concreta, cito o arquivo e a linha para você poder mandar verificar. Onde não tenho certeza, marco **(verificar)**.

---

## 1. O que é o produto

Você tem, na prática, **dois produtos dentro do mesmo código**:

1. **O produto que a agência de turismo usa** para operar o dia a dia: uma **agenda de reservas por horário**. Imagine uma tabela onde as **linhas são os veículos** (quadriciclos Q1, Q2… Q8) e as **colunas são os horários** (10h, 11h, … 17h). Cada cruzamento é uma "vaga". O funcionário do balcão clica na vaga livre, preenche o cliente, cobra, imprime o voucher e conduz a operação do dia (check-in na chegada e confirmação de embarque na hora de subir na máquina). É o coração do sistema (`src/App.tsx`, o arquivo central de ~5.489 linhas — `src/App.tsx`).

2. **O produto que VOCÊ vende para outras agências**: isso tudo empacotado como um **SaaS multi-empresa** (multi-tenant), chamado internamente de **QuadriBook**. Cada agência que assina vira um "tenant" (uma empresa isolada dentro do sistema), com sua própria marca, seu subdomínio, seus usuários, seu plano e sua cobrança mensal. Existe um painel de **Super Admin** (`src/SuperAdminPage.tsx`, ~8.090 linhas) de onde você administra todas as empresas, planos, assinaturas e leads comerciais.

O produto **nasceu de uma operação real e específica**: passeios de quadriciclo da empresa "Trip Experience". Isso está gravado no código — os veículos foram semeados como "Quadriciclo Q1 (Maior)" até "Q8 (Menor)" (`supabase/migrations/20260304174355_create_machine_configs_table.sql:57-64`) e o número de máquinas foi travado entre 1 e 8 (`...:23`). Só **depois** o sistema foi generalizado para virar um SaaS que atende qualquer tipo de passeio: quadriciclo, cavalo, bike, UTV, jeep, moto, agência genérica (categorias semeadas em `supabase/migrations/20260701055337:39-47`). Essa história — "MVP de quadriciclo que virou SaaS" — explica quase todas as forças e fraquezas que aparecem neste documento.

Em cima da agenda, existe um **motor de marketing e vendas** robusto: promoções, vouchers, "raspadinha" digital, ofertas de urgência com contagem regressiva, CRM com funil, up-sell, lista de espera — e um **canal de revenda** (parceiros/hotéis que vendem passeios em seu nome). Também há **página pública de reservas** white-label: o cliente final reserva sozinho pelo site da agência, sem falar com ninguém.

**Stack técnico** (resumido, para contexto): React + TypeScript no front; Supabase (banco Postgres + segurança por linha + funções na nuvem) no back; pagamentos das assinaturas via **Asaas**; deploy na Netlify; funciona como app instalável (PWA). Boa parte foi gerada na ferramenta Bolt.new — o nome do projeto no `package.json:2` ainda é o template original `vite-react-typescript-starter`, nunca renomeado.

---

## 2. Perfis de usuário

O sistema tem **dois eixos de papel**: um na **plataforma** (quem manda no SaaS) e um dentro de **cada empresa** (quem opera a agência). A autenticação é própria (não usa login social nem Supabase Auth): usuário e senha validados por uma função na nuvem (`supabase/functions/login-app-user/index.ts`), com sessão guardada por 12h.

| Perfil | Onde vive | O que faz | Como entra |
|---|---|---|---|
| **Super Admin (você / plataforma)** | QuadriBook | Gerencia TODAS as empresas, cria/edita planos, assinaturas e cobrança Asaas, liga/desliga funcionalidades por empresa, cuida do branding da plataforma, acompanha leads comerciais, e pode "entrar" em qualquer empresa sem novo login (impersonação — `src/App.tsx:212-235`) | Login normal com papel `super_admin`, ou e-mail igual ao do fundador (`src/App.tsx:1199-1202`) |
| **Admin da empresa (dono da agência cliente)** | Dentro do tenant | Poder total na sua empresa: cria/edita reservas sem restrição, gerencia usuários e define o que cada um pode fazer, mexe em todas as configurações, branding, promoções, parceiros, relatórios | Login normal, papel `admin` (`src/AdminPage.tsx`) |
| **Gerente** | Dentro do tenant | Opera e vê tudo, permissões amplas, mas **não** pode tudo que o admin pode (ex.: por padrão não exclui reserva) e não vê abas exclusivas de admin (`src/AdminPage.tsx:120-127`) | Login normal, papel `manager` |
| **Operador / funcionário de balcão** | Dentro do tenant | O trabalhador da linha de frente. Só faz o que as **permissões individuais** liberam (por padrão quase tudo desligado, exceto confirmar embarque e ver detalhes — `src/AdminPage.tsx:128-135`). É aqui que o dono controla fino "quem pode criar, editar, excluir, dar desconto, enviar voucher" etc. | Login normal, papel `operator` |
| **Manutenção** | Dentro do tenant | Papel dedicado a bloquear/liberar máquinas para manutenção (`src/App.tsx:2789`) | Login normal, papel `maintenance` |
| **Parceiro / revendedor** | Portal próprio | Hotel, pousada ou guia que vende passeios em nome da agência. Tem portal exclusivo para reservar nos horários permitidos, ver suas vendas e sua comissão (`src/PartnerPortal.tsx`) | Login normal, papel `partner` — ou link público com token, sem login (`src/PartnerPage.tsx`) |
| **Cliente final** | Páginas públicas | Reserva sozinho pelo site da agência, faz o próprio check-in por link, joga a raspadinha, resgata oferta de urgência | Sem login (usa chave pública anônima) |

**Ponto importante de controle de acesso:** as permissões finas do operador (criar, editar, excluir reserva, exportar relatório, gerenciar promoções etc.) são um conjunto de "chaves liga/desliga" por usuário (`src/hooks/usePermissions.ts:6-24`). Elas são aplicadas **no navegador (front-end)**. A segurança de verdade depende das regras do banco (RLS) e das funções na nuvem, que **não foram auditadas nesta varredura** — então trate a matriz de permissões da tela como conveniência de UX, e mande auditar o back-end antes de confiar 100% nela **(verificar)**.

---

## 3. Todas as funcionalidades reais, por módulo

Isto é o que o sistema **faz hoje**, não o que promete. Cada bloco corresponde a código existente.

### 3.1 Reservas / Agenda (o núcleo)
- Grade veículo × horário; criar, editar e excluir reservas; valor por máquina ou valor personalizado; **agrupar várias máquinas numa venda só** (uma família com 4 quadriciclos = 1 grupo); dividir o pagamento entre pessoas; bloquear máquina para manutenção.
- Estados da reserva: **Reservada, Confirmada, Transferida, Check-in feito, Não compareceu (no-show), Inapto para pilotar** (`src/types/index.ts:171-178`).
- Horários configuráveis por empresa; datas de alta demanda; datas especiais/feriados; exceções de capacidade por data.
- **Trava temporária de vaga** enquanto o operador preenche (evita dois funcionários venderem a mesma vaga ao mesmo tempo) e atualização em tempo real da agenda entre telas.
- **Transferência** de reserva para outro horário/data; marcar não comparecimento; marcar cliente inapto.
- Busca de reservas, reservas futuras, alerta de reservas parecidas/duplicadas (checa nome repetido no mesmo dia — `src/App.tsx:1270-1287`).

### 3.2 Operação do dia (check-in e embarque)
- **Dois check-ins distintos e propositais:** (1) o cliente chegou/foi atendido; (2) o cliente **efetivamente embarcou** na máquina (etapa extra, com permissão dedicada `can_confirm_boarding` — `src/App.tsx:3216-3225`).
- Página de **auto check-in do cliente** por link (`?group=...`), sem login — o cliente confirma sozinho pelo celular (`src/CheckInPage.tsx`).
- Painel de operação do dia: contadores de check-in, embarcados, aguardando, não comparecidos, disponíveis (`src/components/DayOperationPanel.tsx`).
- Impressão de **voucher térmico** e envio direto por WhatsApp.

### 3.3 CRM (relacionamento com o cliente)
- Base de clientes, **funil kanban** de estágios, tarefas, **up-sell** com catálogo de produtos ("Fotos +R$50"), lista de espera, templates de mensagem, avaliações (`src/components/CRMAdmin.tsx` + `src/components/crm/*`).
- Detalhe de negócio: o cliente **não era cadastrado** originalmente; o CRM é um acréscimo tardio que **cria o cliente automaticamente a partir das reservas**, deduplicando por telefone (gatilho no banco — `supabase/migrations/20260708163321_extend_crm_module_full.sql:241-280`). Ou seja, a empresa operou muito tempo sem ficha de cliente.

### 3.4 Marketing e retenção
- **Promoções** e envio por WhatsApp (`src/components/PromotionsPanel.tsx`).
- **Raspadinha digital**: campanha com prêmios e probabilidades; o cliente joga por link (`?promo=...`), informa telefone, ganha cupom (`src/ScratchPage.tsx`).
- **Oferta de urgência**: desconto com **contagem regressiva** enviada por link (`?t=...`); expira sozinha (`src/UrgencyOfferPage.tsx`).
- Gatilhos extras: flash promo, incentivo, alerta de alta demanda, pop-up de aviso.

### 3.5 Parceiros / revendedores (canal de venda B2B2C)
- Cadastro de parceiros com **modo de precificação** (preço líquido, comissão percentual ou comissão fixa), horários permitidos, limite de reservas por dia, e um **motor de rotação de vagas** que distribui a disponibilidade entre parceiros concorrentes (`src/components/PartnersAdmin.tsx`, ~1.288 linhas).
- Link público do parceiro (sem login) e portal do parceiro logado com relatório de vendas e comissão (`src/PartnerPortal.tsx`, ~1.582 linhas).

### 3.6 Demais módulos
- **Pacotes** especiais e registro de vendas de pacote.
- **Vouchers**: imagem para impressora térmica, PDF, configuração de título/instruções/rodapé.
- **Branding / white-label**: cada empresa personaliza cores, logo, ícones, tema; o ícone e título do app mudam conforme o domínio acessado.
- **Landing pages públicas** e **construtor de página de reservas** (funil de venda direta ao consumidor).
- **Relatórios** operacionais e exportações (liberados conforme o plano).
- **Base Camp**: experiência premium de pôr do sol atrelada especificamente ao horário das 17h (`supabase/migrations/.../create_base_camp_tables.sql`).
- **Painel Super Admin (QuadriBook)**: dashboard, empresas, planos, assinaturas/Asaas, categorias, recursos, descontos, financeiro, auditoria, branding da plataforma, domínios, e-mails, notificações, PWA, integrações, **leads comerciais** (funil de venda do próprio SaaS) e parceiros comerciais.
- Auxiliares: presença/usuários online, log de atividade (auditoria), avisos de sistema, changelog "novidades", página de diagnóstico.

---

## 4. Como o produto ganha dinheiro

**Regra número um, e a mais importante para você:** o SaaS ganha dinheiro de **uma única forma — assinatura mensal cobrada de cada agência**, processada pela **Asaas** (PIX, boleto, cartão). **Não há cobrança por reserva. Não há comissão da plataforma sobre as vendas da agência.** Você não tira um centavo de cada passeio que a agência vende; você cobra o "aluguel" mensal do software.

A cobrança é criada na Asaas com ciclo mensal, e o valor vem do plano da empresa (`supabase/functions/asaas-billing/index.ts:227-249`), com descrição `Assinatura {PLANO} — QuadriBook`.

### 4.1 Planos vigentes hoje (START / PRO / BUSINESS / ELITE)

Fonte: `supabase/migrations/20260708185504_..._saas_plans_v2_start_pro_business_elite.sql:46-85`.

| Plano | R$/mês | R$/ano | Veículos | Usuários | O que libera de diferente |
|---|---|---|---|---|---|
| **START** | 79 | 790 | 5 | 1 | Reservas, agenda, clientes, horários, disponibilidade, painel admin |
| **PRO** | 149 | 1.490 | 20 | 5 | + CRM inteligente, up-sell, financeiro básico, relatórios operacionais, multiusuário, página pública, multi-atividade, exportações, estatísticas |
| **BUSINESS** | 229 | 2.290 | ilimitado | ilimitado | + financeiro avançado, relatórios avançados, permissões avançadas, dashboard CRM, configuração de empresa |
| **ELITE** | 299 | 2.990 | ilimitado | ilimitado | **Tudo liberado** (`["all"]`) |

O plano anual custa **10× o mensal** — ou seja, ~2 meses de graça para quem paga o ano.

A diferenciação entre planos é feita por dois mecanismos: **limites** (quantos veículos e usuários) e **módulos liberados** (CRM, up-sell, parceiros de venda, financeiro avançado etc.), via um sistema de "chaves de funcionalidade" resolvido em `src/hooks/useTenantFeatures.ts`.

### 4.2 A comissão que existe NÃO é sua

O único mecanismo de comissão no sistema é **da agência sobre o parceiro dela** (o hotel/guia que revende). A agência define quanto o cliente paga, quanto ela recebe líquido e quanto o parceiro fica de comissão (`src/components/PartnersAdmin.tsx:310-328`; campos no banco em `supabase/migrations/20260606001827_..._partners_add_commission_fields.sql:3-11`). A plataforma **não participa** dessa transação. Você lucra com isso **indiretamente**: o módulo "Parceiros de Venda" é premium (liberado só nos planos superiores), então parceiros = motivo para a agência subir de plano — não um percentual por venda.

### 4.3 Alerta sério: existem DOIS sistemas de planos concorrentes

Esta é a maior confusão do modelo de monetização e você precisa saber. Há **duas tabelas de planos** vivendo em paralelo no banco:

- **`tenant_plans`** — é a que **realmente é cobrada** (a função da Asaas lê o preço daqui). A própria migration diz que esta é "a fonte autoritativa em runtime" (`supabase/migrations/20260708185504...:9-12`).
- **`subscription_plans`** — um catálogo comercial "mais bonito", com 4 ciclos de preço (mensal/trimestral/semestral/anual) e limites mais ricos, mas que na prática está **órfão**: os preços dele (ex.: PRO a R$197) **não são o que se cobra**. Ainda alimenta partes das categorias de serviço, o que gera risco de divergência entre "o que é cobrado" e "o que é exibido/limitado".

Além disso, sobraram planos legados na tabela `tenant_plans` (demo, basic R$97, enterprise R$797, starter, custom, lifetime R$4.997 pagamento único), não removidos na atualização (`supabase/migrations/20260702031347_complete_tenant_plans.sql`). E o plano `pro` foi reescrito duas vezes com preços diferentes (R$197 → R$149). **Recomendação de negócio:** decidir qual catálogo é o oficial e limpar o outro, senão em algum momento uma empresa será cobrada um valor e verá outro. **(verificar)** qual das duas tabelas o app consulta para as **categorias de serviço** por plano.

### 4.4 Descontos e ciclo de cobrança
- Descontos têm **fluxo de aprovação**: a empresa pode **solicitar** desconto (fica "pendente") e você, como Super Admin, **aprova ou recusa** (`supabase/functions/saas-admin/index.ts:1442-1497`). Tudo fica auditado.
- O ciclo Asaas hoje é sempre **mensal**, mesmo o banco suportando outros ciclos (`asaas-billing/index.ts:245`). Há período de teste (trial).
- Quando o pagamento é confirmado, a empresa fica ativa; quando atrasa, vira "past_due"; quando cancela, vira inativa — tudo sincronizado por webhook da Asaas (`asaas-billing/index.ts:72-115`).
- **Segurança financeira: boa.** Nenhuma chave secreta de pagamento está no front-end; toda escrita de cobrança/plano/desconto passa por funções na nuvem autenticadas e verificando que quem chama é super admin. Faturas e pagamentos são **somente leitura** pelo app (só a Asaas/serviço grava).

---

## 5. O modelo de dados como retrato do negócio

Aqui traduzo as tabelas do banco para o significado de negócio. Este é o "raio-X" da sua operação.

- **O que é uma "reserva":** cuidado, não é "um cliente comprou um passeio". No sistema, **uma reserva = um veículo ocupado num horário** (`bookings`). A prova: a regra de unicidade no banco é `(data, horário, máquina)` (`supabase/migrations/.../add_unique_constraint_prevent_overbooking.sql:22`). Uma venda para uma família com 4 quadriciclos vira **4 registros**, amarrados por um `group_id`. O nome do cliente e o valor são **repetidos** em cada linha. O controle de sinal/saldo mora dentro da própria reserva (`paid_value` vs `total_value`), não numa tabela de pagamentos separada.

- **O que é um "recurso/máquina":** um veículo físico (`machine_configs`). Nasceu como quadriciclo numerado 1 a 8. Cada máquina comporta, implicitamente, **1 ocupação por horário**. Recentemente ganhou (no banco) a ideia de "modo individual" vs "capacidade compartilhada" com número de assentos — mas isso está **inativo** (ver seção 7).

- **O que é um "passeio":** **não existe uma tabela de passeios/produtos de primeira classe.** O passeio é implícito no par (veículo + horário) mais "adornos" espalhados: combo, base camp (17h), contagem de passageiros. Isso é dívida de modelagem herdada do MVP de quadriciclo — o "produto vendável" está fragmentado, não centralizado.

- **O que é uma "empresa/tenant":** a agência cliente do SaaS (`tenants`), com plano, limites (máx. veículos/usuários), status de assinatura e subdomínio. É a fronteira de isolamento entre as empresas. **Ponto de atenção de segurança:** a empresa original "Trip Experience" tem um **ID fixo/hardcoded** (`00000001-0000-0000-0000-000000000001`) e todos os dados antigos sem dono foram atribuídos a ela. Combinado com a forma como o isolamento funciona, um acesso **sem sessão** pode cair de volta nessa empresa — daí o comentário de alerta no próprio código: "NUNCA servir uma reserva sem tenant no domínio da plataforma" (`src/App.tsx:1223-1235`). **(verificar)** no back-end/RLS.

- **O que é um "cliente":** nas reservas, é só texto solto (nome e telefone). Como **entidade de verdade**, o cliente só existe no CRM, e é **gerado automaticamente** a partir das reservas.

- **O que é um "parceiro":** um canal de revenda B2B2C (`partners`) com modelo econômico sofisticado — três valores por reserva (público, líquido, comissão), cotas diárias, horários permitidos e motor de rotação de vagas. É o segundo módulo mais elaborado do sistema, sinal de que a receita via parceiros é estratégica **para a agência**.

**Riscos do modelo de dados a registrar:**
- Apagar uma empresa apaga **todas** as reservas dela em cascata (`add_tenant_id_to_core_tables.sql:8`) — risco operacional real.
- Duas tabelas `subscriptions` conflitantes e dois catálogos de plano (dívida de refatoração de cobrança inacabada).
- Algumas tabelas do CRM não têm o "CREATE TABLE" neste conjunto de migrations — provavelmente criadas fora dele **(verificar)**.

---

## 6. Fluxo de uma reserva do início ao fim

Passo a passo, do jeito que acontece na vida real:

1. **Vaga livre** — um cruzamento (veículo + data + horário) sem reserva ativa.
2. **Operador (ou parceiro) abre a tela** — o sistema cria uma **trava temporária de 30 segundos** naquela vaga para ninguém vender por cima (`slot_locks`).
3. **Preenche a reserva** — cliente, máquina(s), valor (sugerido ou personalizado), divisão de pagamento. O sistema alerta se há nome repetido no dia e se a máquina está em manutenção.
4. **Salva** — nasce a reserva com status **Reservada**. Um gatilho gera um código legível (ex.: "TR-2026-00001") e outro cria/atualiza o cliente no CRM pelo telefone. Se houver disputa pela mesma vaga, o sistema tenta de novo automaticamente.
5. **Pagamento** — pode entrar sinal (paid_value parcial); com pagamento confirmado, a reserva vira **Confirmada**.
6. **No dia, chegada** — o cliente (por link no celular) ou o operador faz o **1º check-in** → status **Check-in feito**.
7. **Embarque** — o operador com permissão confirma o **embarque efetivo** (2º check-in), gravando quem liberou e registrando log.
8. **Passeio realizado.**
9. **Exceções possíveis a qualquer momento:** **Transferir** para outro horário (operação atômica que recria a reserva no novo slot e apaga a antiga, guardando o histórico); **Não compareceu** (no-show, reversível); **Inapto para pilotar** (cliente chegou mas não pode andar, com motivo registrado).

Observação de auditoria: como os operadores usam chave anônima (não login forte individual no banco), quem fez cada ação é registrado por **nome digitado**, não por identidade forte. É rastreabilidade "fraca" — suficiente para o dia a dia, frágil para disputa séria **(verificar)**.

---

## 7. O que o sistema NÃO resolve hoje / dores do dono

Esta seção é a mais valiosa para decisões. São limitações reais, com evidência.

### 7.1 A dor central: capacidade travada em "1 por veículo" — o caso JEEP

Hoje o sistema assume, em toda parte, que **uma reserva ocupa um veículo inteiro** num horário. Isso funciona para quadriciclo (1 piloto = 1 máquina). **Mas quebra para qualquer veículo coletivo** — o exemplo concreto é o **JEEP** (ou UTV, van, trenzinho): uma jeep de 6 lugares deveria aceitar **6 passageiros de reservas diferentes** no mesmo horário. O sistema **não sabe fazer isso**.

Por quê, em termos de negócio:
- A "vaga" é tratada como **cheia ou vazia** (booleano). O sistema conta ocupação como "número de veículos usados", nunca "número de assentos ocupados" (`src/App.tsx:2935-2941`, `src/components/DayOperationPanel.tsx:24-25`).
- O banco **proíbe** uma segunda reserva no mesmo veículo/horário, por duas regras de unicidade redundantes (`supabase/migrations/20260704014914...:9-12` e `20260703183947...:28-30`). Ou seja, mesmo que a tela tentasse, o banco recusaria a 2ª pessoa na jeep.

O mais frustrante: **já existe um embrião pronto no banco** para capacidade compartilhada — foram criadas as colunas "modo de reserva" (individual vs. compartilhado), "assentos" e "nº de passageiros" (`supabase/migrations/20260709191130_..._add_shared_capacity_booking_mode.sql`). **Mas está 100% morto:** nenhuma linha do front-end usa essas colunas, os tipos nem as declaram, e — pior — **as travas de unicidade não foram alteradas**, então o recurso nunca poderia funcionar. O comentário da migration diz que a lógica está "implementada no front-end". **Isso não é verdade; nunca foi implementado.** É promessa não cumprida no próprio código.

Resumo da dor: **a jeep (e todo passeio coletivo) hoje só pode ser vendida como "veículo inteiro", desperdiçando assentos** — ou exige gambiarra manual do operador.

### 7.2 Horários: configuráveis, mas frágeis e globais

Os horários da agenda **podem ser editados** por empresa, mas a fonte da verdade está **espalhada em quatro lugares divergentes** (dois valores fixos no código, um em configurações, mais duas tabelas novas **abandonadas**) — `src/types/index.ts:182`, `src/hooks/useTimeSlots.ts`, e tabelas `time_slots`/`company_schedule_times` órfãs. E são **globais por empresa**: **não existe horário por tipo de passeio nem por veículo**. Uma agência que roda quadriciclo o dia todo **e** jeep só às 10h e 14h **não tem como expressar isso** hoje.

### 7.3 Fluxos manuais e dívida operacional
- Cliente vira ficha só depois (CRM bolt-on); a empresa operou sem cadastro de cliente.
- Divisão de pagamento e saldo moram dentro da reserva, não num módulo financeiro dedicado.
- "Passeio" não é uma entidade — dificulta relatório por tipo de produto, precificação por produto, etc.

### 7.4 Saúde do software (dores que afetam o negócio)

| Dor | Gravidade | O que significa para o negócio |
|---|---|---|
| **Página de diagnóstico exposta** (`?diagnostic=true` em qualquer rota — `src/main.tsx:122`, `src/DiagnosticPage.tsx`) | **ALTO / segurança** | Qualquer visitante anônimo pode abrir uma tela de debug que tenta listar usuários de `app_users` e exibe a credencial de teste `admin/admin123`. Se a regra do banco permitir leitura anônima, isso **vaza usuários e hash de senha**. É lixo do Bolt que vazou para produção — deve ser removido. **(verificar)** a regra RLS de `app_users`. |
| **Logs com dados pessoais no console** (`src/App.tsx:247` loga login; outros em AdminPage/PartnerPortal) | MÉDIO | Identidade/credencial e dados operacionais visíveis no console do navegador de qualquer usuário. |
| **Monólito de 5.489 linhas** (`src/App.tsx`) | ALTO / manutenção | Qualquer mudança tem alto risco de quebrar outra coisa; dificulta contratar/terceirizar; encarece evolução. |
| **Zero testes automatizados** | ALTO / qualidade | Num SaaS com pagamentos e multi-empresa, não há rede de segurança; toda validação é manual. |
| **Sem telemetria de erros** (nenhum Sentry) | MÉDIO | Erros em produção são invisíveis para você; só descobre quando o cliente reclama. |
| **~2,3 MB de entulho** (5 pastas `public*` mortas) e nome de projeto ainda template | BAIXO | Higiene; confunde quem for mexer. Só `public3` é usada no build (`vite.config.ts:105`). |
| **Hack de PNGs corrompidos no build** (`vite.config.ts:7-27`) | MÉDIO | Há imagens corrompidas dentro de `public3` que o build precisa apagar por gambiarra; um novo arquivo ruim pode quebrar o build silenciosamente. |

---

## 8. Oportunidades

O que dá para vender e evoluir, em ordem aproximada de valor:

1. **Ativar capacidade variável (JEEP/UTV/van) — a maior oportunidade de receita.** Transforma o produto de "só quadriciclo/individual" em "qualquer passeio coletivo", abrindo um mercado inteiro (jipe-tour, buggy compartilhado, trilha em van, barco). O caminho técnico já está meio pavimentado (as colunas existem); falta: (a) **trocar as duas travas de unicidade do banco** para permitir N passageiros por veículo quando o modo for "compartilhado", mantendo "individual" como padrão para não quebrar os clientes atuais; (b) um **gatilho no banco** que garanta que a soma de passageiros não passe dos assentos (anti-overbooking real); (c) contagem por **assentos** em vez de por veículo no front; (d) UI para escolher nº de passageiros. Risco principal: concorrência (duas pessoas comprando o último assento) — resolvível com validação no banco. Estimativa de esforço: o "coração" (banco) é **grande**; o resto é **médio**. Referências completas em `supabase/migrations/20260709191130...` e nos pontos de contagem em `src/App.tsx`.

2. **Horários por tipo de passeio e por veículo.** Desbloqueia agências com mix de produtos (quadriciclo o dia todo + jeep às 10h/14h). Requer uma tabela de horários ligada a categoria/veículo (hoje inexistente) e limpar as 4 fontes de horário divergentes.

3. **Elevar "passeio/produto" a entidade de primeira classe.** Permite catálogo de produtos, preço por produto, relatório por produto, pacotes de verdade — e vira base para upsell/cross-sell mais forte. Também melhora a narrativa de venda do SaaS.

4. **Limpar e unificar os planos de cobrança.** Resolver a duplicidade `tenant_plans` vs `subscription_plans` reduz risco de cobrar um valor e mostrar outro, e permite oferecer ciclos anuais/semestrais de verdade (o banco já suporta) — alavanca de caixa (venda anual antecipada).

5. **Monetizar módulos premium com mais clareza.** O motor de parceiros, CRM, up-sell e financeiro avançado já são gated por plano; dá para criar add-ons pagos ou um degrau intermediário entre PRO e BUSINESS.

6. **Endurecer segurança e confiança (pré-requisito para vender para clientes maiores).** Remover a página de diagnóstico, tirar logs com dados pessoais, auditar as regras de isolamento entre empresas (o alerta de "vazamento tenantless" é sério), adicionar testes e telemetria. Isso não gera receita direta, mas é o que impede um incidente que destruiria a reputação do SaaS.

7. **Formalizar o produto.** Renomear o projeto, versionar, criar changelog público (já existe base "novidades"), telemetria de erro — profissionaliza a operação e facilita contratar/terceirizar dev.

---

## Resumo executivo do negócio

Você é dono de **dois negócios no mesmo código**: uma **agenda de reservas por horário** que uma agência de turismo usa para operar (o produto), e um **SaaS multi-empresa (QuadriBook)** que revende esse produto para outras agências (o negócio). O sistema **nasceu de uma operação real de quadriciclo** (Trip Experience, veículos Q1–Q8 gravados no código) e foi generalizado depois — o que explica suas forças e suas dívidas. A monetização é **simples e limpa: assinatura mensal por agência via Asaas**, em quatro planos (START R$79 → PRO R$149 → BUSINESS R$229 → ELITE R$299), diferenciados por limites de veículos/usuários e por módulos liberados. **Não há take-rate por reserva**; a única comissão do sistema é da agência sobre seus próprios revendedores. O produto é surpreendentemente **completo**: agenda, dois check-ins, CRM automático, promoções, raspadinha, ofertas de urgência, parceiros com rotação de vagas, páginas públicas white-label e um painel de super admin robusto. A **maior dor e a maior oportunidade são a mesma coisa**: hoje toda reserva ocupa um veículo inteiro (modelo de quadriciclo), então **jeeps e passeios coletivos não podem ser vendidos por assento** — e o embrião técnico para resolver isso já existe no banco, porém está **morto e mal-acabado**. As dívidas mais urgentes são de **segurança e manutenção**: uma página de diagnóstico exposta que pode vazar usuários, logs com dados pessoais, um arquivo central de 5.489 linhas, zero testes e nenhuma telemetria de erro. A dívida mais perigosa para o caixa é a **duplicidade de catálogos de planos**, que pode fazer o valor cobrado divergir do exibido. Em uma frase: **um SaaS de reservas maduro em funcionalidades, sólido no faturamento por assinatura, mas travado num modelo de "1 veículo = 1 reserva" e carregando dívidas de segurança que precisam ser fechadas antes de crescer.**