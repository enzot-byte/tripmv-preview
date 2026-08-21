# Plano de Ataque — Jeep (fechar) + Upsell/Cross-sell (expandir)
> Fundamentado na recon multi-agente de 2026-07-25 do repo `quadribook-live`. Cada bloco é um prompt escopado pro Sonnet, pequeno e testável. Ordem = de cima pra baixo.

## 🔑 Descoberta-chave da recon
**O upsell/CRM NÃO é do zero.** Já existe e funciona no lado do operador:
- Tabelas `crm_upsell_products` (catálogo: nome, preço, comissão) e `crm_upsell_offers` (oferta por reserva, com snapshots + quantity).
- Hook `useCRMUpsell`, painel admin `UpsellPanel` (catálogo + registro + relatório de conversão).
- Oferta embutida na reserva nova (bloco "Oportunidades de Venda", App.tsx:5631-5703) que soma no total e grava em `booking_upsell_value`.
- CRM inteiro funcional (clientes vindos de trigger `bookings→crm_customers`, funil, tarefas, templates) atrás da feature premium `crm_clientes`.

➡️ **O trabalho de upsell é EXPANDIR (público + edição + quantidade) e POLIR, não construir.**

---

# TRACK A — Fechar 100% o jeep (4 blocos, rápidos)

## A1 — Nome do veículo cravado nas telas internas (J4b)
**Objetivo:** rename de veículo já funciona na agenda, mas ~9 telas ainda mostram "Q{id}" cravado.
**Já existe:** `getMachineName(id)` em `useMachineConfigs.ts:167-169`. Padrão de passar por prop: `HighDemandAlert.tsx:11,47,151`.

```
Contexto: React+TS+Vite+Supabase. Branch feat/jeep-shared-capacity — working tree, NÃO commite. Valida com `npm run build` (ignora os 147 erros de tsc pré-existentes). NÃO leia arquivos gigantes inteiros — grep + faixas.

OBJETIVO: trocar nomes de veículo cravados "Q"+id por getMachineName(id) nas telas internas (o rename já funciona na agenda, falta propagar).

Nestes locais, o rótulo do veículo está hardcoded como `Q${id}` / `Q{id}` — troque por getMachineName(id):
- src/CheckInPage.tsx: linhas 143, 368, 386, 425, 443
- src/PartnerPortal.tsx: 268
- src/components/FutureBookingsPanel.tsx: 86, 404
- src/VoucherImageWrapper.tsx: 39
- src/VoucherPDFWrapper.tsx: 41, 67
- src/components/PaymentDivisionPanel.tsx: 269
- src/components/UnfitToRideModal.tsx: 122

Padrão: se o componente não tem acesso a getMachineName, passe-o por PROP a partir do pai (siga o padrão de src/components/HighDemandAlert.tsx:11,47,151 — recebe getMachineName por prop). NÃO toque em useMachineConfigs.ts:169 nem :135 (lá o "Q"+id é o fallback canônico e está correto).

Valida com `npm run build`. NÃO commite. Se algum local não bater, PARA e pergunta.
```

## A2 — Preço do jeep fechado configurável (`closed_price`) — pedido do Marius
**Objetivo:** hoje "jeep fechado" = `suggested_value × lugares`. Marius quer um valor próprio, mudável por temporada.
**Já existe:** cálculo em App.tsx:1576-1581 e 1874-1886; config do veículo em `VehicleCapacityRow` App.tsx:345-357; preço via `getSuggestedValue` (useMachineConfigs.ts:155-165).

```
Contexto: React+TS+Vite+Supabase. Branch feat/jeep-shared-capacity — working tree, NÃO commite. Valida com `npm run build`. NÃO leia App.tsx inteiro — grep + faixas.

OBJETIVO: dar um valor CONFIGURÁVEL pro "jeep fechado" (per_vehicle), por veículo. Hoje o fechado = suggested_value × lugares; passa a ser closed_price (fixo) quando preenchido, senão cai no cálculo atual.

1) MIGRATION nova (aditiva): ALTER TABLE public.machine_configs ADD COLUMN IF NOT EXISTS closed_price numeric; COMMENT explicando "preço do jeep fechado; NULL = usa suggested_value × lugares".
2) TYPE: MachineConfig em src/types/index.ts (~170-181): closed_price?: number | null.
3) LEITURA: garanta que closed_price entra no select/map de machine_configs (useMachineConfigs.ts ~linha 31, onde monta o objeto).
4) CONFIG UI: em VehicleCapacityRow (App.tsx ~345-357), quando shared_capacity, adicione um <input type="number"> "Valor jeep fechado (R$)" ligado a mc.closed_price → updateMachineConfig(mc.id, { closed_price: valor || null }). Placeholder "auto (assento × lugares)".
5) CÁLCULO: crie o valor fechado efetivo closedTotal = (machineConfig.closed_price != null ? machineConfig.closed_price : unitValue * seats). Use em TODOS os 3 lugares onde hoje o fechado = unit × seats:
   - Toggle "Jeep fechado" (perVehicleTotal, ~App.tsx:4899) → mostra closedTotal.
   - useEffect de preview (App.tsx:1576-1581): quando shared_capacity && effPricing==='per_vehicle', newTotal = closedTotal (não unit × previewUnits).
   - handleSaveBooking (App.tsx:1874-1886): mesma coisa pro total do fechado.
   Mantenha per_head e individual idênticos.

Valida com `npm run build`. NÃO commite. Se não bater, PARA e pergunta.
```

## A3 — Local de embarque como seletor configurável
**Objetivo:** hoje é texto livre; virar lista pré-configurada (pousadas).
**Já existe:** padrão a clonar → `useTimeSlots.ts:1-81` (chave `agenda_time_slots` em company_settings, CSV, realtime) + `TimeSlotManager.tsx:1-167` (chips+input). Input atual: App.tsx:5013-5021. Save (1997/2121) e comprovante já prontos.

```
Contexto: React+TS+Vite+Supabase. Branch feat/jeep-shared-capacity — working tree, NÃO commite. Valida com `npm run build`. NÃO leia App.tsx inteiro — grep + faixas.

OBJETIVO: transformar "Local de embarque" (hoje texto livre) num seletor de uma lista configurável de pousadas.

1) Clone src/hooks/useTimeSlots.ts → src/hooks/usePickupLocations.ts, trocando a chave para setting_key='pickup_locations' (mesmo padrão: company_settings, CSV, realtime, upsert onConflict setting_key,tenant_id). Validação: não permitir vazio/duplicado.
2) Clone src/components/TimeSlotManager.tsx → src/components/PickupLocationManager.tsx (chips + input de texto pra adicionar/remover pousadas). Monte-o na área de settings: App.tsx ~4129 e/ou AdminPage.tsx ~780 (onde o TimeSlotManager é montado).
3) Troque o <input> de pickup (App.tsx:5013-5021) por um <select> que mapeia a lista de usePickupLocations. Mantenha uma opção "Outro" que revela um input livre (fallback), pra não travar quem quer digitar algo fora da lista.
4) NÃO mexa no save (App.tsx:1997/2121) nem no comprovante — pickup_location continua string.

Valida com `npm run build`. NÃO commite. Se não bater, PARA e pergunta.
```

## A4 — Hardening dos triggers (migration SQL, integridade no banco)
**Objetivo:** fechar 3 buracos que permitem overbooking em casos de borda.
**Já existe:** `stamp_booking_mode` e `enforce_shared_capacity` em `20260717120000_jeep_shared_capacity.sql` (:102-119 e :145-185); índices unique :122-139.

```
Contexto: Supabase Postgres. Branch feat/jeep-shared-capacity — working tree, NÃO commite. Crie UMA migration nova aditiva (não edite a antiga).

OBJETIVO: fechar 3 buracos de integridade no controle de lotação do jeep. Baseie-se na migration existente supabase/migrations/20260717120000_jeep_shared_capacity.sql (funções stamp_booking_mode :102-119 e enforce_shared_capacity :145-185; índices :122-139).

Crie supabase/migrations/2026072X_jeep_hardening.sql com:
1) RE-CARIMBAR booking_mode quando a config muda: novo trigger AFTER UPDATE OF booking_mode, capacity_seats ON machine_configs que atualiza bookings.booking_mode das reservas FUTURAS (date >= current_date) daquele machine_id, pra não sobrar linha shared órfã escapando dos índices unique.
2) ENFORCE só quando a carga AUMENTA: em enforce_shared_capacity, early-return (NEW sem bloqueio) quando NEW.status IN ('NO_SHOW','NOT_FIT','TRANSFERRED'), e/ou só RAISE quando o delta de ocupação for > 0 (não bloquear operações que não aumentam a carga).
3) STATUS NULL não pode escapar do somatório: troque a condição do somatório de carga para COALESCE(b.status,'') NOT IN (...) (função enforce ~linha 173) e ajuste os índices parciais (:131,:138) do mesmo jeito.

Reescreva as funções com CREATE OR REPLACE. NÃO commite. Se a estrutura real não bater, PARA e pergunta.
```

---

# TRACK B — Upsell / Cross-sell (expandir o existente)

## ⚠️ B0 — BUG DE COBRANÇA: upsell some na EDIÇÃO (PRIORIDADE)
**Achado da recon (App.tsx:1878-1882):** ao EDITAR uma reserva, `acceptedUpsellTotalForSave = 0`, então o recálculo (unit × veículos) **descarta o upsell já embutido e SUBCOBRA.** Isso é dinheiro perdido — corrigir antes de expandir.

```
Contexto: React+TS+Vite+Supabase. Branch atual — working tree, NÃO commite. Valida com `npm run build`. NÃO leia App.tsx inteiro — grep + faixas.

BUG: em handleSaveBooking, no ramo de EDIÇÃO (isEditing), acceptedUpsellTotalForSave é forçado a 0 (App.tsx:1878-1882). Como o safeTotal recalcula unit × unidades + acceptedUpsell, editar uma reserva que tinha upsell DESCARTA o valor do upsell e subcobra.

OBJETIVO: ao editar, preservar o upsell já vendido.
1) No ramo isEditing, em vez de 0, use o booking_upsell_value já salvo na reserva (currentBooking.booking_upsell_value ?? 0) como acceptedUpsellTotalForSave — OU releia via fetchBookingUpsellOffers(bookingId, tenantId) somando os result='accepted'.
2) Garanta que o safeTotal na edição = base recalculada + upsell preservado (não zere).
3) Não altere o comportamento de reserva NOVA.

Confirme lendo App.tsx:1874-1903 e useCRM.ts:153-164 antes de mexer. Valida com `npm run build`. NÃO commite. Se algo não bater, PARA e pergunta.
```

## B1 — Vender quantidade > 1 do mesmo adicional
**Achado:** schema (`crm_upsell_offers.quantity`), tipo e voucher já suportam qty>1, mas a UI grava sempre 1 (App.tsx:2052).

```
OBJETIVO: permitir quantidade > 1 por adicional no upsell.
1) Na UI de oferta (App.tsx:5631-5703), adicione um seletor de quantidade por produto aceito (default 1).
2) Propague a quantidade: no cálculo do total use price × quantidade; em logUpsellOffer (App.tsx:2052) grave a quantity real (não 1 fixo).
3) O voucher já renderiza x{qty} e price×qty (App.tsx:2635-2636) — não precisa mexer lá.
Valida com `npm run build`. NÃO commite.
```

## B2 — 🎯 CROSS-SELL NO PÚBLICO (o grande ganho de receita)
**Achado:** o cliente final já reserva sozinho (PublicBookingPage + edge function `public-booking`), mas **não recebe nenhuma oferta de adicional.** O mecanismo de upsell (`crm_upsell_products/offers`) existe e funciona no operador — dá pra reusar no público.

```
Contexto: React+TS+Vite (frontend) + Supabase Edge Function (Deno). Branch atual — working tree, NÃO commite. NÃO leia arquivos gigantes inteiros — grep + faixas.

OBJETIVO: oferecer adicionais (upsell) ao cliente final no fluxo público, reusando crm_upsell_products / crm_upsell_offers (que já funcionam no operador).

1) EDGE FUNCTION supabase/functions/public-booking/index.ts: adicione uma action 'get_upsell_products' que retorna crm_upsell_products ativos (is_active) do tenant (id, name, description, price). Siga o padrão das actions existentes (:231-486).
2) FRONTEND src/PublicBookingPage.tsx: adicione um passo "Adicionais / Leve também" entre os steps 'slot' e 'form' (~:753-818), listando os produtos com checkbox + (opcional) quantidade, somando ao valor exibido.
3) EDGE FUNCTION create_booking (:332-483): aceite um array upsell_product_ids (e quantidades); some os preços no total_value da reserva e insira uma linha em crm_upsell_offers por item com result='accepted', offered_by='public', preenchendo price/commission/name_snapshot a partir do produto. Espelhe a lógica do operador em App.tsx:2037-2041.

Resultado: os "Adicionais" já aparecem automaticamente no voucher (VoucherPDF.tsx:533-545) e no WhatsApp. Valida com `npm run build` (frontend). NÃO commite. Se a estrutura não bater, PARA e pergunta.
```

## B3 — Ligações + limpeza (rápido, faz junto com B1/B2)
- Preencher `customer_id` ao logar oferta quando a reserva tiver cliente CRM (App.tsx:2044 — hoje sempre null → destrava relatório de upsell por cliente/LTV).
- Remover `console.log` de debug: `useCRM.ts:411-435` (deleteProduct) e `UpsellPanel.tsx:198` (botão lixeira).

## B4 — Relatório de comissão a pagar (opcional, valor pro Marius)
`commission` já está em `crm_upsell_offers`; falta um card no UpsellDashboard somando comissão devida por operador (offered_by).

---

# 🧱 Dívidas de integridade (flag — não bloqueiam, mas resolver antes de escalar SaaS)
1. **Tabelas base do CRM fora do versionamento** (`crm_customers`, `crm_opportunities`, `crm_tasks`, `crm_contact_logs`, `crm_evaluations`, `crm_message_templates`) — só têm ALTER, nunca CREATE nas migrations. **É a MESMA dívida que travou o staging** (as "tabelas fantasma"). Ação: extrair o DDL real da prod (`pg_dump --schema-only`) e escrever CREATE TABLE IF NOT EXISTS pra trazer ao git.
2. **`special_packages` / `package_sales` = código morto** (hook chamado em App.tsx:500, nunca renderizado). Decidir: remover ou finalizar. Não confundir com o mecanismo real de upsell.
3. **`crm_opportunities` = tabela morta** (RLS sem uso). O plano SaaS vende "clientes e oportunidades" — ou construir a feature ou remover.
4. **Estatísticas do cliente não populam** (`total_bookings`/`total_spent`/`last_booking_date` sempre 0) — o trigger só grava nome+telefone. Implementar via trigger/RPC de agregação.

---

# 📅 Sequência recomendada
**Primeiro (fecha o jeep, entrega a 1ª metade do R$2k):** A1 → A2 → A3 → A4.
**Depois (upsell/cross-sell, a 2ª metade):** B0 (bug!) → B1 → B2 (o grande) → B3.
Cada bloco: Sonnet codifica → Opus revisa (lê só os trechos + build/tsc) → testa no staging → aprova. Um bloco por vez, como no jeep.
