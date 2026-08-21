# ANÁLISE TÉCNICA — TripMV

## 0. Sumário executivo técnico

O TripMV/QuadriBook é um SaaS multi-tenant de gestão de reservas por horário (React 18 + Vite + Supabase + Asaas), nascido de uma operação single-tenant de quadriciclos ("Trip Experience") e retrofitado para multiempresa em julho/2026. O produto é funcionalmente rico (agenda, CRM, parceiros, promoções, página pública white-label, painel Super Admin), mas a **camada de isolamento multiempresa está efetivamente neutralizada** e há **overbooking estrutural** — os dois problemas que o cliente relata.

O isolamento por RLS existe no papel (90+ tabelas com `ENABLE ROW LEVEL SECURITY`), porém é anulado por duas falhas sistêmicas: (a) a função `get_session_tenant_id()` retorna NULL para o papel `anon` — que é o único papel usado pelo app — e (b) as políticas foram reescritas com o ramo `USING (get_session_tenant_id() IS NULL OR ...)`, que abre TODAS as linhas de TODOS os tenants quando não há sessão. Some-se a isso um `user_sessions` com `SELECT USING(true)` (sequestro de sessão / super admin), edge functions que aceitam `tenant_id` do corpo (`admin-users` permite criar super_admin em qualquer tenant), e um fallback tenantless no front que serve/grava dados sob o tenant de dev hardcoded `00000001-0000-0000-0000-000000000001`. O resultado é vazamento bidirecional real e possibilidade de takeover global.

O overbooking decorre de escrita read-then-write não-atômica em todos os caminhos (agenda, público, parceiro), protegida apenas por um índice UNIQUE parcial que não cobre override de capacidade reduzida, modo `shared_capacity` e divergências de chave. A infra atômica (`create_temporary_hold`) existe mas não é usada. O "não veem em tempo real" aponta para `bookings` provavelmente ausente da publicação `supabase_realtime`.

No financeiro, a integração Asaas funciona no caminho feliz, mas o webhook é *fail-open*, sem idempotência, e a inadimplência não bloqueia nada (status é cosmético). Saúde geral: monólito `App.tsx` de 5.489 linhas, zero testes, `DiagnosticPage` de debug exposta, 5 pastas `public*` mortas.

**Contagem de achados por gravidade (após deduplicação):**
- **CRÍTICO:** 11
- **ALTO:** 14
- **MÉDIO:** 15
- **BAIXO:** 12

O sistema **não deve ser considerado seguro para operação multiempresa** no estado atual. A Onda 1 (isolamento) é pré-requisito de tudo.

---

## 1. Achados por área

### 1.1 Isolamento multiempresa

#### 1.1.1 `get_session_tenant_id()` retorna NULL para o papel anon (CAUSA-RAIZ)
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/migrations/20260711010943_20260711_add_session_expiry_and_needs_reset.sql:27-66` (função final); `src/lib/supabase.ts:24` (cliente anon); `supabase/migrations/20260708221745_20260708_etapa1_multitenant_rls_isolation.sql:164-165` (`app_users_select TO authenticated`).
- **Evidência:** a versão final da função é `SECURITY INVOKER` (herdada de `20260709155341:39-43`) mas voltou a fazer JOIN com `app_users` (`...010943:54-62`). Sob INVOKER, roda com privilégios de `anon`, que não tem SELECT em `app_users` → JOIN vazio → retorna NULL mesmo com sessão válida. A versão que funcionava lia `user_sessions.tenant_id` direto (`20260709155341:67-72`).
- **Impacto:** para 100% do app (anon), a função retorna NULL. Todas as políticas `IS NULL OR =tenant_id` viram abertas (vazamento de leitura); todas as `=tenant_id` estritas bloqueiam escrita (origem das gambiarras `allow_anon_write`). É o mascarador de qualquer outro ajuste de policy.
- **Correção:** resolver tenant a partir de `user_sessions.tenant_id` (coluna existe desde `20260709060900`) sem tocar em `app_users`, OU marcar `SECURITY DEFINER` com `search_path` fixo. Corrigir isto ANTES de qualquer outro ajuste de RLS.

#### 1.1.2 `user_sessions` SELECT `USING(true)` — sequestro de sessão / super admin
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/migrations/20260709144407_20260709_security_fix_rls_and_secdef_functions.sql:56-58`; RLS anon confirmada também em `supabase/migrations/20260501223336_fix_user_sessions_rls_for_anon.sql:15-18`.
- **Evidência:** `CREATE POLICY "user_sessions_select" ON user_sessions FOR SELECT TO anon, authenticated USING (true);`. O `x-session-id` É o token de autenticação (base de `get_session_tenant_id`/`is_super_admin_session`).
- **Impacto:** qualquer um com o anon key lê `SELECT id, user_id, tenant_id, is_super_admin FROM user_sessions` e obtém todos os session IDs ativos, inclusive de super_admin. Basta setar `x-session-id` para o de um admin para operar como aquele tenant ou como super admin da plataforma. Escalonamento total.
- **Correção:** restringir SELECT a `id::text = header x-session-id` (padrão que existia em `20260708221745:187-193` e foi revertido). Nunca `USING(true)`.

#### 1.1.3 `admin-users` `create_user`/`update_user` — criação/elevação de super_admin em qualquer tenant
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/functions/admin-users/index.ts:82`, `:158`, `:197`, `:220-234` (create); `:243-337`, esp. `:259`, `:265`, `:300-324` (update).
- **Evidência:** único gate é `session.role === "admin"|"manager"` (`:82`), sem checar super_admin. `tenant_id` e `saas_role` vêm do corpo do cliente (`:158`, `:197`); se `saas_role === "super_admin"` grava `user_roles.insert({ tenant_id: null })` (`:231`, `:319-323`). No update, o bloqueio de `:265` olha o app role, não o `saas_role`, então um admin apontando para o próprio `user_id` passa.
- **Impacto:** qualquer admin/manager de qualquer empresa (ou quem tenha um session UUID admin — ver 1.1.2) cria um admin em outra empresa (controle total daquela empresa) ou um super_admin de plataforma (takeover global do SaaS). Vetor real de takeover multiempresa.
- **Correção:** exigir super_admin para aceitar `bodyTenantId ≠ session.tenantId` e para atribuir qualquer `saas_role`; para admin/manager comum, ignorar `tenant_id` do corpo e forçar `session.tenantId`; proibir auto-promoção.

#### 1.1.4 CRM (`crm_customers` e demais `crm_*`) SELECT com fallback IS NULL — PII em escala
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/migrations/20260709212437_20260709230001_fix_crm_select_rls_tenant_isolation_v2.sql:5-62`.
- **Evidência:** todas as `crm_*_select ... TO anon, authenticated USING (get_session_tenant_id() IS NULL OR = tenant_id)`. O próprio cabeçalho (`:1`) admite que corrigia `USING(true)` mas manteve o ramo `IS NULL`.
- **Impacto:** base de clientes completa (nome, contato, histórico, oportunidades, avaliações) de todas as agências legível por qualquer anon sem sessão. Vazamento de dados pessoais em escala (LGPD). CRM nunca é fluxo público.
- **Correção:** remover `IS NULL`; políticas `TO authenticated` com `=tenant_id`.

#### 1.1.5 `bookings`: INSERT `WITH CHECK(true)` + SELECT/UPDATE/DELETE fallback IS NULL
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/migrations/20260711012053_20260711_revert_bookings_rls_to_working_state.sql:31-54` (estado final), esp. `:37-39` (INSERT).
- **Evidência:** `bookings_insert ... WITH CHECK (true)` → qualquer anon insere reserva com qualquer `tenant_id`; SEL/UPD/DEL com `IS NULL OR = tenant_id`.
- **Impacto:** leitura/edição/exclusão de reservas (PII de clientes, valores) de todos os tenants por qualquer visitante; gravação de reservas forjadas em qualquer empresa.
- **Correção:** remover `IS NULL`; INSERT deve exigir `get_session_tenant_id() = tenant_id`; fluxo público deve passar por Edge Function com service_role e tenant resolvido do host.

#### 1.1.6 `machine_configs`: escrita anon com fallback IS NULL (escrita cross-tenant)
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/migrations/20260709202516_20260709220000_fix_machine_configs_rls_allow_anon_write.sql:9-31`; SELECT em `20260708221745:115-116`.
- **Evidência:** `machine_configs_insert/update/delete ... TO anon ... USING/WITH CHECK (get_session_tenant_id() IS NULL OR = tenant_id)`.
- **Impacto:** anon sem sessão cria/altera/exclui configuração de veículos (capacidade, valor) de qualquer empresa.
- **Correção:** remover ramo `IS NULL`; escrita só com sessão de mesmo tenant.

#### 1.1.7 `vehicle_capacity_overrides`: escrita anon com fallback IS NULL
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/migrations/20260709201927_20260709210000_fix_capacity_overrides_rls_allow_anon_write.sql:12-43`; SELECT em `20260708221745:372-373`.
- **Evidência:** INSERT `WITH CHECK (... get_session_tenant_id() = tenant_id OR get_session_tenant_id() IS NULL)`; UPD/DEL idem.
- **Impacto:** anon manipula overrides de capacidade (habilita/lota datas) de outras empresas — impacto direto em disponibilidade/overbooking cross-tenant.
- **Correção:** remover `IS NULL`.

#### 1.1.8 `OnlineUsersPanel` — query e Realtime sem filtro de tenant sobre RLS permissiva
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `src/components/OnlineUsersPanel.tsx:26-39` (canal) e `:49-52` (query); RLS `20260501223336:15-18` + coluna adicionada tarde em `20260709060900:5`.
- **Evidência:** `.channel('user_sessions_changes').on('postgres_changes', { table:'user_sessions' }, …)` sem `filter`; `supabase.from('user_sessions').select('*').order(...)` sem `.eq('tenant_id')`. RLS `USING(true)`.
- **Impacto:** vazamento em 3 camadas simultâneas (query + canal + RLS): o painel "Usuários Online" de um operador lista usuários/sessões de TODAS as empresas, e cada INSERT/UPDATE/DELETE de sessões de qualquer tenant é transmitido ao navegador. O componente sequer recebe `tenantId` por prop.
- **Correção:** (a) `.eq('tenant_id', activeTenantId)` na query; (b) `filter: tenant_id=eq.${activeTenantId}` no canal + tenant no nome do canal; (c) corrigir RLS (ver 1.1.2). Passar `tenantId` por prop.

#### 1.1.9 Fallback tenantless no front → serve/grava sob "Trip Experience"
- **Gravidade:** ALTO
- **Arquivo:linha:** `src/PublicBookingPage.tsx:219-220` (`resolvedTenantId = tenantId || FALLBACK_TENANT_ID`); `src/PublicEntryPage.tsx:76-83,116-117`; guard parcial em `src/App.tsx:1213-1235` (comentário `:1224`).
- **Evidência:** quando o host não resolve tenant, `PublicEntryPage` faz `setTenantId(null)` e ainda renderiza `<PublicBookingPage tenantId={null}>`, que substitui por `00000001-...`. O guard de `App.tsx:1231/1235` só cobre `_isDevHost`/domínio de plataforma, não um domínio de empresa mal configurado.
- **Impacto:** domínio de cliente não cadastrado em produção serve a página da Trip Experience (branding/slots/settings) e grava reservas sob `tenant_id = 00000001-...`. Combinado com as policies `IS NULL`, produz vazamento bidirecional. `ReportExport.tsx:71` tem o mesmo defeito (`tenantId || DEFAULT_TENANT_ID`).
- **Correção:** eliminar `|| FALLBACK_TENANT_ID`; quando tenant null, renderizar erro "empresa não encontrada". Resolver `tenant_id` server-side pelo host. Aplicar fallback só sob `brand === 'trip-experience'` explícito.

#### 1.1.10 `slot-hold` edge function totalmente aberta, aceita `tenant_id` do corpo
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/functions/slot-hold/index.ts:40-124`, esp. `:56-68`, `:103-111`.
- **Evidência:** nenhuma validação de sessão; `p_tenant_id` vem do corpo (só valida formato UUID) e vai direto ao RPC `create_temporary_hold` via service_role; `p_locked_by` arbitrário.
- **Impacto:** qualquer um cria bloqueios de slot (até 1800s) para qualquer tenant/data/máquina, sem rate limit — DoS de disponibilidade (travar a grade de um concorrente).
- **Correção:** exigir contexto autenticado ou token de sessão pública emitido pela própria página + rate limit por IP/tenant.

#### 1.1.11 `slot_locks` RLS: INSERT `WITH CHECK(true)`, DELETE fallback IS NULL
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/migrations/20260711021816_20260711_fix_slot_locks_insert_rls.sql:7-9`; SEL/DEL em `20260708221745:292-299`.
- **Impacto:** anon cria/derruba travas de horário de qualquer tenant → DoS de reservas e leitura de ocupação alheia.
- **Correção:** escopar INSERT/DELETE por `get_session_tenant_id() = tenant_id`.

#### 1.1.12 `upload-company-asset` sem namespacing por tenant
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/functions/upload-company-asset/index.ts:18`, `:115-124`, `:161-163`.
- **Evidência:** `ADD_PATHS = ["logos/company_logo", ...]` strings fixas sem tenant, `upsert:true` em bucket compartilhado `company-assets`; nada injeta `session.tenantId`.
- **Impacto:** admin da empresa A envia `logos/company_logo.png` e sobrescreve o logo da empresa B. Adulteração de branding entre tenants.
- **Correção:** prefixar `filePath` com `session.tenantId` e validar pertencimento.

#### 1.1.13 `company_settings` SELECT fallback IS NULL (leitura pública ampla)
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/migrations/20260708221745:93-94` (escrita OK em `20260709132623:10-18`).
- **Impacto:** leitura de config da empresa (contato, integrações, possíveis chaves) de todos os tenants por anon. A página pública precisa ler só o config do tenant do host.
- **Correção:** SELECT escopado ao tenant resolvido pelo host; expor só campos públicos via view/Edge Function.

#### 1.1.14 `partners` SELECT fallback IS NULL (exposição de tokens)
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/migrations/20260708221745:251-252`.
- **Impacto:** leitura de parceiros e possíveis tokens de acesso de outros tenants por anon (tabela guarda `token`, há `partner_password_views`/`partner_sessions`).
- **Correção:** remover `IS NULL`; não retornar colunas de token na policy pública (view sem segredos).

#### 1.1.15 Tabelas da plataforma com SELECT `USING(true)`/`TO anon`
- **Gravidade:** ALTO
- **Arquivo:linha:** `tenants` SELECT `USING(true)` `20260701052138:27`; `user_roles` SELECT `USING(true)` `...052138:79`; `invoices`/`payments`/`subscriptions`/`subscription_discounts` SELECT `TO anon USING(true)` `20260701131610:56-73` e `20260701124402:23,56`.
- **Impacto:** lista completa de empresas-clientes, planos, quem é super_admin (alvo para 1.1.2) e dados financeiros de todos os tenants legíveis por anon.
- **Correção:** escopar SELECT por tenant/`is_super_admin_session()`.

#### 1.1.16 `login-app-user` não checa status/deleted_at do tenant no login
- **Gravidade:** ALTO (também financeiro — ver 1.3)
- **Arquivo:linha:** `supabase/functions/login-app-user/index.ts:166-283`.
- **Evidência:** o login só lê `app_users` (filtro por `is_active`/`deleted_at` do usuário), sem join em `tenants`. Um usuário de tenant suspenso/cancelado/soft-deleted ainda autentica.
- **Correção:** bloquear login se `tenants.deleted_at IS NOT NULL` ou `status IN ('suspended','inactive','cancelled')`.

#### 1.1.17 `get_allowed_categories_for_tenant(uuid)` SECURITY DEFINER legível por anon cross-tenant
- **Gravidade:** MÉDIO
- **Arquivo:linha:** definição `supabase/migrations/20260701223512:7`; grant anon `supabase/migrations/20260710221603_grant_anon_get_allowed_categories.sql:1`.
- **Evidência:** SD com `p_tenant_id` do cliente e sem verificar que o chamador pertence ao tenant.
- **Impacto:** anon enumera categorias ativas de qualquer tenant (dado semi-público; vazamento de configuração, não PII).
- **Correção:** validar `get_session_tenant_id() = p_tenant_id OR sessão nula`, ou documentar como público explícito.

#### 1.1.18 `admin-users` `get_permissions` — IDOR cross-tenant
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `supabase/functions/admin-users/index.ts:436-455`.
- **Evidência:** `.eq("id", user_id)` sem validar `tenant_id` contra `session.tenantId` (diferente de `update_user:259`).
- **Impacto:** admin lê flags de permissão/`is_active` de usuários de outros tenants enumerando UUIDs.
- **Correção:** adicionar `.eq("tenant_id", session.tenantId)`.

#### 1.1.19 `admin-slot-unlock` — bypass de tenant quando admin tem `tenant_id` nulo
- **Gravidade:** BAIXO
- **Arquivo:linha:** `supabase/functions/admin-slot-unlock/index.ts:77`, `:99-101`.
- **Evidência:** `if (!isSuperAdmin && adminTenantId && adminTenantId !== tenant_id) return 403` — curto-circuita se `adminTenantId` for null.
- **Correção:** falhar fechado quando `adminTenantId` nulo e não super_admin.

#### 1.1.20 `user_sessions` UPDATE/DELETE anon `USING (user_id IS NOT NULL)`
- **Gravidade:** BAIXO
- **Arquivo:linha:** `src/hooks/useSessionHeartbeat.ts:42-49`; RLS `20260501223336:25-34`.
- **Impacto:** qualquer cliente pode atualizar/deletar sessão de usuário de outro tenant conhecendo o `id` (escrita cross-tenant, não leitura).
- **Correção:** amarrar policy ao próprio `id`/tenant. Corrigir junto com 1.1.2/1.1.8.

**Notas de estado final (SECDEF — já endurecidas, sem ação):** `create_temporary_hold`, `check_slot_availability`, `execute_booking_transfer` (com guard `current_role`, `20260702170921:33`), `apply_plan_change`, `log_access_violation`, `capture_tenant_health_snapshot`, `get_rls_status`, `get_tenant_access`, `grant/revoke_super_admin` (`search_path=''`, revogadas), `sync_crm_customer_from_booking`, `partner_login/set_password` — todas restritas a `service_role`/interno no estado final. **Fragilidade residual (MÉDIO):** `increment/decrement_package_sold_quantity(uuid)` (`20260402073916:20,31`) são SD sem filtro de tenant nem guard `current_role`; hoje só `postgres` executa, mas um GRANT futuro reabriria fraude de estoque. **A verificar:** `partner_login`/`partner_set_password` não têm `CREATE` versionado em `supabase/migrations/` (só a migration de revoke `20260710165315`); confirmar corpo/`search_path` no banco.

---

### 1.2 Reservas / Overbooking / Concorrência

#### 1.2.1 Escrita read-then-write não-atômica em todos os caminhos; única proteção é índice UNIQUE parcial
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `src/App.tsx:1359-1365` (re-check) → `:1578` (insert) → `:1581-1607` (trata 23505); índices em `supabase/migrations/20260703183947:28-30` e `20260704014914:9-12`.
- **Evidência:** `handleSave` consulta banco + estado local e insere, com `await loadData()` e `setTimeout(1500)` (`:1391`, `:1444`) entre SELECT e INSERT — janela de corrida grande. Nenhuma transação, lock de linha ou consulta a `slot_locks`. A proteção real é o índice `bookings_unique_slot_per_tenant`.
- **Impacto:** o caso clássico (mesmo tenant/máquina/slot) é barrado pelo índice (2º operador recebe 23505 "CONFLITO"), mas toda a integridade depende de um único índice parcial; qualquer buraco no predicado (1.2.2–1.2.5) escapa.
- **Correção:** substituir os read-then-write por uma RPC `SECURITY DEFINER` única que valide disponibilidade + capacidade + `SUM(passenger_count)` e faça o INSERT na mesma transação, deixando o índice como backstop. Reaproveitar/estender `create_temporary_hold` e chamá-la de fato nos 3 caminhos.

#### 1.2.2 `bookings` provavelmente ausente da publicação `supabase_realtime` ("não veem em tempo real")
- **Gravidade:** CRÍTICO (verificar no banco)
- **Arquivo:linha:** grep `ADD TABLE|CREATE PUBLICATION` em `supabase/migrations/` retorna 6 tabelas (`system_announcements`, `partner_date_extra_slots`, `partner_date_strategies`, `slot_locks`, `partner_mode_strategies`, `reservation_presence`) e nenhuma para `bookings`. Única migration tocando realtime de bookings: `20260704155142_fix_bookings_replica_identity_full.sql:5` (`REPLICA IDENTITY FULL`), que NÃO publica.
- **Evidência:** `REPLICA IDENTITY FULL` só controla o payload de UPDATE/DELETE; para `postgres_changes` disparar é preciso `ALTER PUBLICATION supabase_realtime ADD TABLE bookings`, inexistente no versionamento.
- **Impacto:** se a publicação não incluir `bookings`, zero eventos chegam ao cliente; operadores só veem a reserva do outro ao trocar de data/recarregar. O código de Realtime está correto (`useBookings.ts:65-131` re-busca a cada evento), logo o defeito é de configuração. O indicador "SINCRONIZADO" (`App.tsx:2795-2798`) pode ficar verde mesmo assim (canal conecta, tabela não emite).
- **Correção:** verificar `SELECT * FROM pg_publication_tables WHERE pubname='supabase_realtime'`; se faltar, `ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;` em migration versionada (modelo: `20260703192236:1` de `slot_locks`).

#### 1.2.3 Modo `shared_capacity` declarado no banco mas sem enforcement (nem front nem trigger)
- **Gravidade:** CRÍTICO (se o modo for usado)
- **Arquivo:linha:** `supabase/migrations/20260709191130_20260709200000_add_shared_capacity_booking_mode.sql:23-28,47-73`; grep `shared_capacity|booking_mode|passenger_count|capacity_seats` em `src/` → 0 ocorrências.
- **Evidência:** a migration declara "Availability logic (implemented in frontend)" (`:23`) — falso; nada em `src/` implementa. Não há constraint/trigger garantindo `SUM(passenger_count) <= capacity_seats`. Os índices UNIQUE não foram tocados.
- **Impacto duplo:** múltiplas reservas no mesmo veículo/slot são barradas pelo índice (subbooking — não vende os 4 assentos do Jeep); se contornarem o índice, não há teto de assentos (overbooking silencioso).
- **Correção:** ver Seção 2 (JEEP). Implementar ou remover as colunas para não induzir configuração perigosa.

#### 1.2.4 `create_temporary_hold` (trava atômica) existe mas os caminhos de escrita não a usam
- **Gravidade:** ALTO
- **Arquivo:linha:** RPC em `supabase/migrations/20260703183947:76-133` e `20260704010555:4-62`; `supabase/functions/slot-hold/index.ts:103-111`. Caminhos reais NÃO a chamam: `public-booking/index.ts:415-459`, `partner-booking/index.ts:412-495`, `App.tsx:1119`.
- **Evidência:** `public-booking` faz `slot_locks.insert(...)` não-atômico sem tratar erro (`:415`), deleta o lock (`:459`) e confia no 23505. O hold do admin (`App.tsx:1119-1133`) insere direto em `slot_locks` e `handleSave` nunca consulta `slot_locks`. A RPC atômica só é chamada por `useSlotLocks.ts:76`.
- **Impacto:** a única invariância forte fica de fora dos caminhos críticos; um insert interno atropela um hold ativo de parceiro/público (cliente perde a vaga que "segurava" ao converter, recebendo 23505).
- **Correção:** rotear os 3 caminhos pela RPC atômica (ver 1.2.1).

#### 1.2.5 Override de capacidade REDUZIDA ignorado no caminho interno
- **Gravidade:** ALTO
- **Arquivo:linha:** `src/App.tsx:963-968` (`getMachinesForSlot`) vs `supabase/functions/public-booking/index.ts:172-174`.
- **Evidência:** interno: `if (slotCapacity <= machinesList.length) { result = machinesList; }` — override de redução não tem efeito; overrides só adicionam máquinas (`App.tsx:969-983`). Público respeita: `if (slotOverride) total = slotOverride.capacity`.
- **Impacto:** admin define capacidade 3 (5 quadris em manutenção); página pública bloqueia em 3, operadores internos continuam reservando Q1..Q8 = overbooking. O índice não protege porque cada máquina é chave distinta.
- **Correção:** em `getMachinesForSlot`, quando `slotCapacity < machinesList.length`, restringir o conjunto reservável; idealmente mover para a RPC de 1.2.1.

#### 1.2.6 Divergência de `tenant_id`/`time_slot`/`status` fura o índice parcial
- **Gravidade:** ALTO (verificar em produção)
- **Arquivo:linha:** `src/App.tsx:252` (`activeTenantId = ... ?? null`); índice legado `20260701181752:21-23`; predicado de status `20260704014914:12`.
- **Evidência:** (a) **tenant_id null:** insert cai no índice `bookings_unique_slot_legacy` (`WHERE tenant_id IS NULL`) e não colide com o tenant real; `loadData` aborta com tenant vazio (`useBookings.ts:34`) → operador não vê reservas dos outros (unifica os dois sintomas). (b) **time_slot:** `"9:00"` vs `"09:00"` são chaves distintas (público valida `^\d{2}:\d{2}$` em `public-booking:113`, interno usa slots livres). (c) **status NULL:** `NULL NOT IN (...)` = NULL, exclui a linha do índice.
- **Impacto:** cada divergência gera duas linhas ativas no mesmo slot real sem violar o índice.
- **Correção:** `tenant_id NOT NULL` + rejeitar insert com tenant vazio; canonicalizar `time_slot` (`HH:MM`) por CHECK; `status NOT NULL DEFAULT 'RESERVED'`.

#### 1.2.7 Histórico de RLS instável em `bookings` + isolamento de Realtime só client-side
- **Gravidade:** ALTO
- **Arquivo:linha:** `20260708221745:72-73` → `20260711011145:16-22` → `20260711012053:31-39`.
- **Evidência:** SELECT foi trocado para exigir sessão (`bookings_select_tenant ... IS NOT NULL AND = tenant_id`), o que bloqueou todas as leituras, e foi revertido (cabeçalho de `20260711012053` diz que o cliente "does not send x-session-id headers on regular queries"). O REST envia `x-session-id` (`src/lib/supabase.ts:10-22`), mas o WebSocket do Realtime não (o override `global.fetch` não se aplica), então na RLS do Realtime `get_session_tenant_id()` = NULL → passa pelo ramo `IS NULL` e entrega linhas de todos os tenants, isoladas só pelo filtro de canal `tenant_id=eq.` (`useBookings.ts:71`).
- **Impacto:** fragilidade recorrente (visibilidade já quebrou por RLS antes) + vazamento cross-tenant no Realtime (dados de outros tenants trafegam ao cliente).
- **Correção:** propagar `x-session-id` ao canal via `supabase.realtime.setAuth` antes de reintroduzir política restritiva; documentar que o isolamento de tenant no Realtime hoje é só client-side.

**Verificações a rodar em produção:** `pg_publication_tables` (confirma 1.2.2); existência dos índices UNIQUE com predicado de status; `GROUP BY tenant_id,date,time_slot,machine_id HAVING count(*)>1` (duplicados reais); `count(*) FROM bookings WHERE tenant_id IS NULL` (vetor tenantless).

---

### 1.3 Financeiro / Asaas

#### 1.3.1 Webhook com validação de token *fail-open*
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/functions/asaas-billing/index.ts:49-58` (token de `Deno.env ?? ""` em `:35`).
- **Evidência:** `if (ASAAS_WEBHOOK_TOKEN) { ...valida... }` — se a secret não estiver setada, o bloco é pulado e qualquer POST anônimo em `/webhook` é aceito. Como o próprio Asaas não manda JWT Supabase, `verify_jwt` está desligado para esta function (verificar no dashboard — não versionado).
- **Impacto:** conhecendo um `tenant_id` (que vaza pelo `externalReference` e pelo front), um atacante forja `PAYMENT_CONFIRMED` para ativar qualquer tenant de graça (`:72-73`) ou `SUBSCRIPTION_DELETED` para desativar (DoS) qualquer concorrente (`:109-115`).
- **Correção:** exigir o token sempre (`if (!ASAAS_WEBHOOK_TOKEN) return 503`); validar assinatura HMAC do Asaas; confirmar o evento na API do Asaas antes de mutar status.

#### 1.3.2 Inadimplência não bloqueia nada — status financeiro é cosmético
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/functions/login-app-user/index.ts:166-283`; badges em `src/SuperAdminPage.tsx:923-926,2810-2812`.
- **Evidência:** o webhook seta `tenants.status` para `past_due`/`inactive`, mas nada consome como gate. O login não lê `tenants.status`/`deleted_at`/`subscriptions.status`. Grep por gate de status em `src/` não retorna nenhum ponto que negue acesso por billing; no SuperAdmin o status é só badge visual. Nenhum `pg_cron` de auto-suspensão (grep `cron.schedule` = 0).
- **Impacto:** empresa que para de pagar recebe `PAYMENT_OVERDUE`, vira `past_due`/`inactive` e continua operando reservas indefinidamente. Idem tenant cancelado/soft-deleted. Perda de receita direta.
- **Correção:** gate no `login-app-user` (bloquear por `status`/`deleted_at`) + revalidação contínua de `tenant.status` (sessão dura 12h, `:10`) nas functions sensíveis.

#### 1.3.3 Webhook sem idempotência + reativação incondicional (eventos fora de ordem)
- **Gravidade:** CRÍTICO
- **Arquivo:linha:** `supabase/functions/asaas-billing/index.ts:60-128`.
- **Evidência:** nenhuma tabela de `event id` processado; `PAYMENT_CONFIRMED/RECEIVED` fazem `UPDATE tenants SET status='active'` sem guarda de status atual (`:72-73`, diferente do update em `subscriptions` que filtra `.eq("status","past_due")`). `activity_logs.insert` roda a cada retry (`:118-126`).
- **Impacto:** entrega tardia/retry de `PAYMENT_RECEIVED` de cobrança antiga reativa incondicionalmente um tenant cancelado/inactive → volta a ter acesso sem pagar. Logs duplicados. Status "pisca" conforme ordem de chegada.
- **Correção:** tabela `asaas_webhook_events(event_id text PRIMARY KEY, processed_at)` para dedupe; guardar todos os `UPDATE tenants` com filtros de status coerentes; tratar transições como máquina de estados.

#### 1.3.4 Troca de plano não sincroniza `tenants.plan`, não grava histórico, não toca no Asaas; `apply_plan_change` é código morto
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/functions/saas-admin/index.ts:954-968` (handler `change_plan`); `apply_plan_change` definida em `supabase/migrations/20260709050509:71-134` (grant só service_role, `:133-134`).
- **Evidência:** o handler só faz `subscriptions.update({ plan_id })`. Não atualiza `tenants.plan`/`active_plan_id`, não grava `plan_change_history`, não chama `apply_plan_change` (grep: função aparece só na migration que a define e na de revoke `20260709060543:122`). Nenhuma action de upgrade/downgrade em `asaas-billing` → sem proration; Asaas continua cobrando o valor antigo.
- **Impacto:** upgrade/downgrade no painel muda `subscriptions.plan_id` mas o Asaas cobra o valor antigo indefinidamente (perda de receita ou cobrança indevida); `tenants.plan` fica no plano antigo → gate de features libera/nega errado; zero rastreabilidade.
- **Correção:** `change_plan` deve chamar `apply_plan_change` (que atualiza tenant + subscription + histórico atomicamente) e disparar ação em `asaas-billing` que atualize a assinatura no Asaas (`PUT /subscriptions/{id}`). Tratar `SUBSCRIPTION_UPDATED` de valor/plano.

#### 1.3.5 Webhook não registra invoice/payment — dashboard financeiro dessincronizado
- **Gravidade:** ALTO
- **Arquivo:linha:** webhook `asaas-billing/index.ts:72-128` vs dashboard `saas-admin/index.ts:202-254`; única inserção em `payments` em `saas-admin:1662`.
- **Evidência:** o dashboard soma `invoices status='paid'` (`:202-216`) e MRR de `subscriptions`; `invoices`/`payments` só são gravados por caminhos manuais (`charge_invoice`, `create_payment`). O webhook Asaas nunca insere invoice/payment.
- **Impacto:** pagamentos reais via Asaas não entram em `invoices`/`payments`; `revenueMonth`/`revenueYear` ficam subestimados/zerados. Decisão de negócio sobre número errado.
- **Correção:** no handler `PAYMENT_CONFIRMED/RECEIVED`, upsert idempotente de `invoices`/`payments` a partir do `payment` do Asaas (chave `payment.id`); estender `current_period_ends_at`.

#### 1.3.6 Dois handlers `cancel_subscription` divergentes
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `asaas-billing/index.ts:288-322` (propaga `DELETE` ao Asaas) vs `saas-admin/index.ts:988-1004` (cancela só a linha, não toca no Asaas).
- **Impacto:** admin cancela pelo módulo de assinaturas e o cliente continua sendo cobrado no Asaas. Também há desync se o `DELETE` no Asaas falhar após já ter removido.
- **Correção:** unificar cancelamento; sempre propagar ao Asaas; só mutar banco após confirmação (2xx ou 404).

#### 1.3.7 Refund/chargeback não tratados
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `asaas-billing/index.ts:60-115` (grep `PAYMENT_REFUNDED`/`CHARGEBACK` = 0).
- **Impacto:** cliente aciona chargeback/estorno → dinheiro sai mas o tenant continua `active` (assina, usa, faz chargeback, mantém acesso).
- **Correção:** tratar `PAYMENT_REFUNDED`, `PAYMENT_CHARGEBACK_REQUESTED` etc. rebaixando o tenant.

#### 1.3.8 Corrida sem atomicidade em `create_customer`/`create_subscription`
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `asaas-billing/index.ts:177-205`, `:218-257`.
- **Evidência:** padrão `SELECT id → if exists return → POST → UPDATE` sem lock condicional.
- **Impacto:** dois cliques concorrentes criam dois clientes/assinaturas no Asaas; o 2º `UPDATE` sobrescreve, deixando órfão e cobranças no cliente errado.
- **Correção:** `UPDATE ... WHERE asaas_customer_id IS NULL` condicional; se `rowCount=0`, deletar o recém-criado no Asaas.

#### 1.3.9 Comparação de token não constant-time + CORS `*` no webhook
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `asaas-billing/index.ts:55` (`!==`), `:4-8` (CORS `*`).
- **Correção:** comparação constant-time; restringir CORS às origens do painel nas rotas admin.

#### 1.3.10 Dois catálogos de planos concorrentes (dívida que afeta cobrança)
- **Gravidade:** MÉDIO
- **Arquivo:linha:** runtime autoritativo `tenant_plans` (`20260708185504:9-12,46-85`) vs catálogo `subscription_plans` (`20260701053950:35-78`); Asaas cobra `tenant_plans.price_monthly` (`asaas-billing/index.ts:227-249`).
- **Evidência:** os hooks leem `tenant_plans`; `subscription_plans` (com 4 ciclos) está praticamente órfã, mas alimenta `plan_service_categories`. Reconciliação por mapa de aliases de slugs (`src/hooks/useTenantFeatures.ts:86-129`). Planos legados (`demo`/`basic`/`enterprise`/`starter`/`custom`/`lifetime`) permanecem em `tenant_plans`; `pro` foi sobrescrito 2×.
- **Impacto:** risco de inconsistência entre o que é cobrado (tenant_plans) e o que é exibido/limitado (parte pende de subscription_plans). `asaas_plan_id` (`20260709000851`) é coluna morta.
- **Correção:** eleger fonte única de plano; remover o catálogo órfão ou conectá-lo; mapear plano-interno→plano-Asaas.

**Positivo (sem ação):** segredos Asaas 100% server-side (`asaas-billing/index.ts:33-35`); nenhuma API key no `src/` (só `VITE_SUPABASE_*` anon). Ações admin protegidas por sessão + super_admin (`:151-160`). Descontos com workflow pendente/aprovado/recusado (`saas-admin/index.ts:1442-1497`).

---

### 1.4 Segurança geral

#### 1.4.1 `DiagnosticPage` de debug exposta em qualquer rota via `?diagnostic=true`
- **Gravidade:** ALTO
- **Arquivo:linha:** `src/DiagnosticPage.tsx` + `src/main.tsx:122,176-177`; `DiagnosticPage.tsx:26-27,44-50,105`.
- **Evidência:** qualquer visitante anônimo adicionando `?diagnostic=true` renderiza página que faz `supabase.from('app_users').select('*')` / `select('username, role, is_active')` e exibe em `<pre>`, além de expor a credencial de teste `admin/admin123`. Se a RLS de `app_users` permitir SELECT anon, dumpa usuários e hash.
- **Impacto:** exposição de estrutura interna e potencialmente de `app_users`. Código de debug do Bolt que vazou para produção.
- **Correção:** remover import/branch em `main.tsx` e apagar `src/DiagnosticPage.tsx` (login real usa PBKDF2, `login-app-user/index.ts:34-98` — a comparação `admin123` já é lixo). Verificar a policy de SELECT anon em `app_users`.

#### 1.4.2 Brute-force de PIN de 4 dígitos sem rate limit; senhas em texto puro
- **Gravidade:** ALTO
- **Arquivo:linha:** `supabase/functions/login-app-user/index.ts:125-210`; `verifyPassword` aceita `stored === plaintext` (`:118`); criação em `admin-users/index.ts:166,204` (PIN 4 dígitos, plaintext até 1º login); `partner_access_password` plaintext permanente (`partner-admin/index.ts:223`).
- **Evidência:** nenhum lockout/delay; espaço de busca 10.000; CORS `*`; endpoint público. Enumeração de usuário: `403 NEEDS_RESET` antes de checar senha (`:197-201`).
- **Impacto:** PIN quebrável por força bruta em minutos; senhas plaintext agravam vazamento de banco.
- **Correção:** rate limit/lockout por username+IP; PIN mais forte/2FA; hashear na criação; eliminar `partner_access_password`; resposta uniforme para NEEDS_RESET.

#### 1.4.3 `public-booking` `create_booking` sem rate limit/CAPTCHA, aceita `tenant_id` arbitrário
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `supabase/functions/public-booking/index.ts:311-315,332-336,454-458`.
- **Impacto:** injeção em massa de reservas `RESERVED` (contam como ocupadas em `getAvailabilityForDate:176`) — griefing de disponibilidade e poluição de dados.
- **Correção:** rate limit por IP+telefone, CAPTCHA, teto de reservas pendentes por origem.

#### 1.4.4 `partner-booking` — sessão de parceiro nunca expira
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `supabase/functions/partner-booking/index.ts:86-94,177-187`.
- **Evidência:** valida só `is_active`+`role==='partner'`, sem `expires_at` (diferente de `partner-admin:57`). `mode:"token"` usa token em URL como credencial.
- **Impacto:** session UUID de parceiro vazado funciona indefinidamente.
- **Correção:** aplicar janela de expiração; tokens com rotação.

#### 1.4.5 `partner-admin` — senha de parceiro em texto puro (feature "revelar PIN")
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `supabase/functions/partner-admin/index.ts:214-223,282-284` (isolamento de tenant correto, `:63`).
- **Impacto:** credenciais de parceiro recuperáveis em claro por qualquer admin do tenant e em vazamento de banco.
- **Correção:** eliminar armazenamento reversível; usar reset em vez de "revelar"; se exigir, cifrar com KMS.

#### 1.4.6 `console.log` de PII em produção
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `src/App.tsx:247` (`[SaaS Auth] Login: { username, email, saasRole }`), `:471`; `src/AdminPage.tsx:392,400`; `src/PartnerPortal.tsx:1013`; `src/hooks/useBookings.ts:41`.
- **Impacto:** exposição de credencial/identidade/tenant_id/session_id no DevTools de qualquer usuário (bundle não remove).
- **Correção:** remover os logs de dados; `esbuild drop:['console']` em produção.

#### 1.4.7 `transfer-booking` — isolamento depende do RPC `execute_booking_transfer`
- **Gravidade:** MÉDIO (verificar)
- **Arquivo:linha:** `supabase/functions/transfer-booking/index.ts:60-104` (tenant forçado do servidor, `:60-67`; `p_source_ids` do cliente, `:87`).
- **Evidência:** o RPC (`20260702154639`) tem guard `current_role` e filtra por `p_tenant_id` — pelo estado final, seguro. A função edge é modelo correto (força tenant da sessão).
- **Correção:** confirmar em runtime que o RPC resolve `p_source_ids` filtrando por `p_tenant_id`.

#### 1.4.8 `fetch-holidays` aberta, `year` sem validação
- **Gravidade:** BAIXO
- **Arquivo:linha:** `supabase/functions/fetch-holidays/index.ts:24-28`.
- **Correção:** validar `year` com `/^\d{4}$/` antes do fetch.

**Positivo (sem ação):** nenhum segredo/JWT/service_role hardcoded em `src/` ou migrations (grep `eyJ...` = 0); `.env` no `.gitignore:23`; edge functions leem segredos só de `Deno.env`; `saas-admin` corretamente restrita a super_admin em todas as ~70 ações (`:155-156`). Observação transversal: `verify_jwt` das edge functions não está versionado (sem `config.toml`) — o controle de acesso é 100% a lógica de sessão custom dentro de cada função (verificar dashboard).

---

### 1.5 Organização / saúde / código morto / entulho / monólito

#### 1.5.1 Monólito `App.tsx` (5.489 linhas / ~280KB)
- **Gravidade:** ALTO (manutenção)
- **Arquivo:linha:** `src/App.tsx`.
- **Impacto:** God component concentrando auth SaaS, roteamento interno, data-fetching e UI; alto risco de regressão, merge conflicts, re-render caro.
- **Correção:** extrair por domínio (auth, bookings, presence, admin) em módulos/hooks; incremental, sem big-bang.

#### 1.5.2 Ausência total de testes
- **Gravidade:** ALTO
- **Evidência:** `*.test.*`/`*.spec.*` = 0 arquivos; nenhum test runner no `package.json`.
- **Impacto:** num SaaS com pagamentos e RLS crítica, zero rede de segurança automatizada.
- **Correção:** testes de fumaça em edge functions de billing/booking e nos utils de hash.

#### 1.5.3 Hack de PNGs corrompidos no build
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `vite.config.ts:7-27,37` (`EXCLUDED_PUBLIC_FILES` + `fs.unlinkSync`).
- **Evidência:** o build deleta do `dist/` 4 PNGs "corrompidos/travados" de `public3` ("image copy copy.png"...).
- **Impacto:** dependência frágil — novo asset corrompido em `public3` quebra o build silenciosamente.
- **Correção:** remover os PNGs ruins de `public3` na origem e deletar o plugin.

#### 1.5.4 Sem telemetria de erro em produção
- **Gravidade:** MÉDIO
- **Evidência:** `ErrorBoundary` global (`main.tsx:192`) e 89 `console.error/warn`, mas nenhum Sentry/logflare.
- **Impacto:** erros de produção invisíveis.

#### 1.5.5 PWA com `skipWaiting`+`clientsClaim`
- **Gravidade:** MÉDIO
- **Arquivo:linha:** `vite.config.ts:43-44`.
- **Impacto:** novo SW assume controle imediato; risco de servir JS/assets desatualizados a abas de longa duração num app de reservas em tempo real. Cache de API bem-feito (`NetworkOnly` para supabase.co, `:53-56`).
- **Correção:** avaliar prompt de update controlado vs `skipWaiting` (já existe `PWAUpdateBanner`, `main.tsx:184`).

#### 1.5.6 5 pastas `public*` mortas (~2.3M, 68 arquivos)
- **Gravidade:** BAIXO
- **Arquivo:linha:** raiz + `vite.config.ts:105` (`publicDir: 'public3'`).
- **Evidência:** só `public3` entra no build; `public/`, `public2/`, `public_clean/`, `public_dist/`, `public_safe/` são entulho (PNGs/ícones duplicados).
- **Correção:** apagar as 5 pastas; idealmente renomear `public3`→`public` e ajustar `vite.config.ts:105`.

#### 1.5.7 Dívidas de schema (inconsistências herdadas)
- **Gravidade:** BAIXO/MÉDIO
- **Evidência:** duas tabelas `subscriptions` conflitantes (`tenants_company_management.sql:41` DROP+recria em `subscriptions_full_schema.sql:6`); `reservation_presence.tenant_id` é `text` enquanto o resto usa `uuid` (`create_reservation_presence_table.sql:4`); quatro fontes de horário divergentes (`TIME_SLOTS` hardcoded `types/index.ts:182`, `DEFAULT_TIME_SLOTS` `useTimeSlots.ts:4`, `company_settings['agenda_time_slots']` — a fonte viva —, e tabelas `time_slots`/`company_schedule_times` órfãs); tabelas-base do CRM sem `CREATE` versionado (só ALTER/RLS em `20260708163321`); `tenant_id` em bookings com `ON DELETE CASCADE` (`add_tenant_id_to_core_tables.sql:8`) — apagar tenant apaga todas as reservas.
- **Correção:** consolidar fontes de horário; padronizar tipo de `reservation_presence.tenant_id`; documentar/limpar catálogos duplicados.

#### 1.5.8 `package.json name` ainda é template
- **Gravidade:** BAIXO
- **Arquivo:linha:** `package.json:2` (`"vite-react-typescript-starter"`, `version: "0.0.0"`).
- **Correção:** renomear para `quadribook`/`tripmv` e versionar.

#### 1.5.9 45 TODO/FIXME/HACK e rota `/raspadinha` (`ScratchPage`) a esclarecer
- **Gravidade:** BAIXO
- **Arquivo:linha:** `src/ScratchPage.tsx` roteada em `main.tsx:123,174-175` (é feature de raspadinha promocional real, confirmada em `biz-features`); 45 ocorrências de TODO/FIXME em `src/`.
- **Correção:** triar os TODO; `ScratchPage` é feature real (sem ação de remoção).

**Positivo (sem ação):** TypeScript `strict: true` + `noUnusedLocals/Parameters` (`tsconfig.app.json:18-21`); `ErrorBoundary` global.

---

## 2. Plano do JEEP (entrega de valor #1)

### 2.1 Modelo atual de disponibilidade/capacidade

Hoje **1 reserva = 1 máquina por horário**, capacidade booleana ("ocupado/livre") por célula `(máquina, horário)`. A "capacidade 1" está cravada em dois níveis:
- **Schema:** `bookings.machine_id NOT NULL CHECK(1..8)` originalmente (`20260206111431:29`); cada máquina selecionada gera uma row (`src/App.tsx:1549-1554`); índices UNIQUE parciais `bookings_unique_slot_per_tenant` (`20260704014914:9-12`) e `idx_bookings_no_overlap` (`20260703183947:28-30`) travam a 2ª reserva no mesmo `(máquina, slot)`; `check_slot_availability` retorna booleano (`20260703183947:49-57`).
- **Client:** `occupied = new Set(machine_id).size` (`App.tsx:2937`); `isOccupied = !!booking` (`:2982-2987`); `getFreeMachinesForSlot` remove a máquina inteira (`:994-999`); `getCapacity` devolve nº de veículos (`useCapacityOverrides.ts:80-88`).

### 2.2 O gap

Não existe a dimensão "assentos/passageiros". Para uma Jeep de N lugares seria preciso somar passageiros de várias reservas contra um teto de assentos — operação inexistente em qualquer camada. Há um **embrião morto** (`20260709191130`) que adicionou `machine_configs.booking_mode`, `machine_configs.capacity_seats` e `bookings.passenger_count`, mas: (a) grep dessas colunas em `src/` = 0; (b) os tipos TS não as declaram (`src/types/index.ts:1-59,159-169`); (c) os índices UNIQUE não foram tocados — mesmo que o front tentasse inserir 6 rows na mesma Jeep/slot, o Postgres rejeitaria a 2ª. O comentário "implemented in frontend" (`:23`) é falso. Além disso, horários são globais por tenant — não há horário por serviço/veículo (a Jeep que só roda 10h/14h não é expressável).

### 2.3 Mini-plano de implementação (sem hardcode; config por tenant/serviço/veículo)

Princípio: **modelar capacidade por assentos**, tratando o modo atual como `capacity_seats = 1`. Reaproveitar o embrião `20260709191130`. Manter `individual` como default (retrocompatível com todos os tenants de quadriciclo).

**(a) SCHEMA**
| # | Onde | O que muda | Esforço |
|---|---|---|---|
| A1 | Nova migration | Substituir os 2 índices UNIQUE por versões condicionais ao modo: unicidade `(tenant,date,slot,machine)` só para `individual`; em `shared_capacity` permitir N rows por `(máquina,slot)`. **Coração do risco.** | **G** |
| A2 | Mesma migration | Reaproveitar `machine_configs.capacity_seats`/`booking_mode`; garantir `capacity_seats >= 1`. | **P** |
| A3 | Mesma migration | Reaproveitar `bookings.passenger_count` (NULL/1=individual; >1=grupo). | **P** |
| A4 | Nova migration | **Trigger `BEFORE INSERT/UPDATE`** que, para `shared_capacity`, rejeita se `SUM(passenger_count) > capacity_seats` (substitui o papel do UNIQUE). Reescrever `check_slot_availability` para retornar assentos livres. | **G** |
| A5 | Nova tabela `service_schedule_times` (ou estender `company_schedule_times` com `service_category_id`/`machine_id`) | Horários por serviço/veículo, sem hardcode. | **M** |
| A6 | Limpeza | Consolidar as 4 fontes de horário numa só; remover `TIME_SLOTS`/`DEFAULT_TIME_SLOTS` hardcoded. | **M** |

**(b) LÓGICA DE DISPONIBILIDADE** — regra unificada: `livres = capacidade_assentos − Σ passenger_count`, onde individual = `nº_máquinas`/`passageiros=1`.
| # | Onde | O que muda | Esforço |
|---|---|---|---|
| B1 | `src/hooks/useCapacityOverrides.ts:80-88` | `getCapacity` devolve assentos quando `shared_capacity`. | **P** |
| B2 | `src/App.tsx:2935-2976` | `occupied = Σ passenger_count`; `total = assentos`. | **M** |
| B3 | `src/App.tsx:994-1000,2980-2987` | célula deixa de ser máquina booleana e vira veículo X/Y assentos; bifurcar render por modo. | **G** |
| B4 | `src/App.tsx:1005,1092-1124,1549-1569` | gravar `passenger_count`; permitir N rows; corrigir `id` composto (`${groupId}-${mId}` colide, `:1550`). | **M** |
| B5 | `src/components/DayOperationPanel.tsx:13-42` | somar assentos. | **P** |
| B6 | `src/PartnerPortal.tsx:754-786`, `src/PartnerPage.tsx` | "X lugares restantes". | **M** |
| B7 | `slot_locks` (`App.tsx:1119-1161`, `useSlotLocks.ts`) | lock reserva N assentos, não a máquina; rever UNIQUE (`20260703183947:19`). | **M** |

**(c) UI / CONFIG**
| # | Onde | O que muda | Esforço |
|---|---|---|---|
| C1 | `src/components/QuadSelector.tsx` | seletor de nº de passageiros no modo compartilhado. | **M** |
| C2 | Painel de veículos (`useMachineConfigs.ts:113`) | definir `booking_mode`/`capacity_seats` por veículo. | **M** |
| C3 | `src/components/TimeSlotManager.tsx` + `useTimeSlots.ts` | editor de horários por serviço/veículo (consome A5). | **M** |
| C4 | `src/types/index.ts:1-59,159-169` | adicionar `passenger_count?`/`booking_mode?`/`capacity_seats?`. **Pré-requisito.** | **P** |
| C5 | `src/components/CapacityOverridesPanel.tsx` | rotular "assentos" no modo compartilhado. | **P** |
| C6 | `src/components/BookingSlot.tsx` | exibir "X de Y lugares". | **P** |

**Ordem sugerida (menor risco → maior valor):** 1) C4 + A2/A3 (tipos + colunas) **P**; 2) A1 + A4 (índices condicionais + trigger — gargalo real) **G**; 3) A5 + C3 (horários por serviço) **M**; 4) B1→B7 + C1/C2/C5/C6 **M–G**; 5) A6 (consolidar horários) **M**.

**Riscos:** com capacidade >1 o UNIQUE deixa de proteger corrida → o trigger A4 (server-side) é obrigatório; `bookings.id` composto colide (`:1550`); não confiar no comentário "implemented in frontend".

---

## 3. Plano de ação priorizado

| Prio | Item | Área | Gravidade | Esforço | Por que primeiro |
|---|---|---|---|---|---|
| 1 | Corrigir `get_session_tenant_id()` (ler `user_sessions.tenant_id` / SECURITY DEFINER) | 1.1.1 | CRÍTICO | P | Mascara qualquer outro ajuste de RLS; sem isto nada mais funciona |
| 2 | Fechar `user_sessions` SELECT (`= header x-session-id`) | 1.1.2 | CRÍTICO | P | Sequestro de sessão/super admin — takeover trivial |
| 3 | `admin-users` create/update: exigir super_admin p/ tenant/saas_role do corpo | 1.1.3 | CRÍTICO | M | Vetor real de takeover global do SaaS |
| 4 | Erradicar ramo `IS NULL` de TODAS as policies (bookings, crm_*, machine_configs, capacity_overrides, company_settings, partners) | 1.1.4–7,13,14 | CRÍTICO | M | Vazamento/gravação cross-tenant de PII e config |
| 5 | Trocar `WITH CHECK(true)` de `bookings_insert` e `slot_locks_insert` | 1.1.5,11 | CRÍTICO/ALTO | P | Grava reserva forjada em qualquer tenant |
| 6 | Escopar SELECT de `tenants`/`user_roles`/`invoices`/`payments`/`subscriptions` | 1.1.15 | ALTO | P | Vaza empresas, papéis e financeiro a anon |
| 7 | Eliminar fallback tenantless (`PublicBookingPage`/`ReportExport`) | 1.1.9 | ALTO | P | Serve/grava sob Trip Experience |
| 8 | Fechar/autenticar `slot-hold`; namespacing de `upload-company-asset` | 1.1.10,12 | ALTO | M | DoS de agenda / sobrescrita de branding |
| 9 | Remover `DiagnosticPage`; rate limit + hash em `login-app-user` | 1.4.1,1.4.2 | ALTO | P/M | Exposição de `app_users`; brute-force de PIN |
| 10 | Publicar `bookings` no Realtime (verificar `pg_publication_tables`) | 1.2.2 | CRÍTICO | P | Resolve "não veem em tempo real" sozinho |
| 11 | RPC atômica de reserva nos 3 caminhos; blindar chaves do índice | 1.2.1,4,6 | CRÍTICO/ALTO | G | Overbooking estrutural |
| 12 | Enforcar capacidade reduzida no interno | 1.2.5 | ALTO | P | Overbooking por override ignorado |
| 13 | Webhook Asaas: token obrigatório + idempotência + gate de inadimplência no login | 1.3.1,2,3 | CRÍTICO | M | Reativação forjada; inadimplente com acesso pleno |
| 14 | Conectar `apply_plan_change` + sync Asaas na troca de plano; registrar invoice/payment no webhook | 1.3.4,5 | ALTO | M | Cobrança divergente; dashboard financeiro falso |
| 15 | Quebrar `App.tsx`; introduzir testes; telemetria | 1.5.1,2,4 | ALTO | G | Reduz risco de regressão das correções acima |
| 16 | JEEP (capacidade por assentos) | Seção 2 | Feature | G | Entrega vendável (planos Pro/Business) |
| 17 | Quick fixes de higiene (pastas mortas, name, console.log, hack PNG) | 1.4.6,1.5.3,6,8 | BAIXO/MÉDIO | P | Baixo risco, ganho de clareza |

**Ondas:**
- **Onda 1 — Isolamento crítico de dados (Prio 1–9):** corrige o vazamento multiempresa e o takeover. Pré-requisito de tudo. A #1 é bloqueante.
- **Onda 2 — Overbooking + tempo real (Prio 10–12):** resolve os dois sintomas operacionais relatados.
- **Onda 3 — Asaas/financeiro (Prio 13–14):** trava inadimplente, protege receita, corrige webhook.
- **Onda 4 — Saúde + JEEP (Prio 15–17):** manutenibilidade e a feature vendável de capacidade variável.

---

## 4. Quick fixes candidatos (triviais e seguros — aprovar antes de aplicar)

| Fix | Arquivo(s) | Mudança | Risco |
|---|---|---|---|
| Remover `DiagnosticPage` | `src/main.tsx:6,122,176-177`, `src/DiagnosticPage.tsx` | apagar branch/import e o arquivo (login real é PBKDF2; página é debug morto) | **Baixo** — testar que `?diagnostic=true` cai no `<App/>` |
| Deletar 5 pastas `public*` mortas | raiz | remover `public/`, `public2/`, `public_clean/`, `public_dist/`, `public_safe/` | **Baixo** — build usa só `public3` (`vite.config.ts:105`) |
| Renomear `package.json name` | `package.json:2,4` | `vite-react-typescript-starter` → `quadribook` + bump version | **Nulo** — cosmético |
| Remover `console.log` de PII | `App.tsx:247,471`, `AdminPage.tsx:392,400`, `PartnerPortal.tsx:1013`, `useBookings.ts:41` | apagar os logs de dados | **Baixo** — só logging |
| Remover PNGs corrompidos + plugin | `public3/`, `vite.config.ts:7-27,37` | apagar `image copy*.png` e o plugin `excludeCorruptedPublicFiles` | **Baixo** — confirmar que nenhum `<img>` referencia esses nomes |
| Validar `year` em `fetch-holidays` | `supabase/functions/fetch-holidays/index.ts:24-28` | `if (!/^\d{4}$/.test(year)) return 400` antes do fetch | **Baixo** |
| Guard antecipado em `useSpecialDates` sem tenant | `src/hooks/useSpecialDates.ts:15` | `return` quando `activeTenantId` falsy em vez de assinar sem filtro | **Baixo** — evita assinar todos os tenants |

**(verificar) pendentes:** policy de SELECT anon em `app_users`; presença de `bookings` em `pg_publication_tables`; existência de `tenant_id`/coluna em `unfit_to_ride_logs` (usado sem filtro em `ReportExport.tsx:117`) e `system_announcements`; `verify_jwt` das edge functions no dashboard; corpo/`search_path` de `partner_login`/`partner_set_password`; conteúdo de `SETUP_USUARIOS.md`/`MANUAL_ADMIN.md` quanto a credenciais de exemplo.