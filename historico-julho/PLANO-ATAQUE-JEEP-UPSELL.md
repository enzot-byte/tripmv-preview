# PLANO DE ATAQUE — Jeep Completo + Upsell/Cross-sell

**Escopo fechado:** R$2.000 · 2–3 semanas · Cliente: Marius (Trip MV)
**Confirmado por ele:** *"o importante é o Jeep e cross-sell e upsell"* — o resto do spec gigante fica no roadmap.

---

## PARTE 1 — JEEP COMPLETO

### O que JÁ existe (entregue em 20/07, no ar)
- `booking_mode` (individual | shared_capacity) por veículo + carimbado na reserva
- `capacity_seats` por veículo, `passenger_count` por reserva
- `pricing_mode` (per_vehicle = fechado | per_head = por cabeça)
- Trigger de capacidade (trava ao lotar) + índices únicos jeep-aware
- UI "Capacidade por Veículo" (Individual/Compartilhado + lugares + preço)
- Grade mostra lotação (ex: 2/3) e bloqueia quando lota
- Fix C5 (dobra de preço ao editar reserva por cabeça)

### O que FALTA pro "Jeep completo de fato"

| # | Gap | Por que importa | Tam |
|---|---|---|---|
| **J1** | **Ver/editar cada passageiro do veículo** — hoje, enquanto tem vaga, clicar na célula só abre reserva NOVA; a reserva existente não é acessível pelo clique (só quando lota) | O operador não consegue abrir/editar/cancelar o passageiro que já está lá. É o maior buraco de operação. | **G** |
| **J2** | **Pagar por todos / carro exclusivo** — uma pessoa reserva N lugares e paga tudo; ou casal; ou pagantes separados | Pedido explícito do Marius (print). Hoje cada passageiro é uma reserva solta, sem "dono do pagamento". | **G** |
| **J3** | **Proteger troca de modo** (compartilhado ↔ individual) — trocar com reservas futuras existentes deixa reservas órfãs e desliga a trava de capacidade | Risco de overbooking/inconsistência. Bloquear a troca (ou re-carimbar) quando houver reservas. | **M** |
| **J4** | **Nome do veículo editável** (Q1 → "Jeep Toyota") — a coluna `machine_name` já existe no banco, mas **não há tela pra editar** e ~10 arquivos cravam `Q{id}` no voucher, WhatsApp e relatório | Um jeep não pode se chamar "Q3" no comprovante do cliente. Vale pro SaaS também. | **M** |
| **J5** | **Pickup na pousada** — campo de local de embarque na reserva do jeep | Pedido do Marius na call. | **P** |
| **J6** | **Ajustes finos** — drift de centavos no por-cabeça quando o total não divide exato (100÷3 = 99,99) e rótulo "/máq." aparecendo no modo por cabeça | Polimento; aparece pro operador. | **P** |

> **Fora do "jeep completo"** (é o módulo "Saída Compartilhada" do doc de 64pg → roadmap): lista de espera, motorista/guia por saída, distribuição inteligente entre veículos, múltiplos veículos por horário.

---

## PARTE 2 — UPSELL / CROSS-SELL (Camada 1)

O spec do Marius tem 5 módulos. **Esta é a fatia que vende de verdade** e cabe no combinado.

| # | Item | Tam |
|---|---|---|
| **U1** | **Migration**: tabelas de complementos, categorias, compatibilidade por atividade, vendas de upsell | **M** |
| **U2** | **Cadastro de complementos** — nome, categoria, descrição, imagem/ícone, valor, valor promo, comissão, ativo, ordem | **G** |
| **U3** | **Categorias personalizadas** (Seguro, Equipamento, Foto, Alimentação, Ingresso...) | **P** |
| **U4** | **Compatibilidade por atividade** — GoPro só em quadri/jeep/UTV; Seguro em todas | **M** |
| **U5** | **Limite por reserva** — máx 1 GoPro, máx 4 balaclava | **P** |
| **U6** | **Oferta dentro do modal de reserva** + aceite/recusa **com motivo da recusa** | **G** |
| **U7** | **Soma no total + comissão do vendedor** (integração financeira confiável) | **M** |
| **U8** | **Cross-sell simples** — sugerir outro passeio após a reserva, com lista **configurável manualmente** (não é IA) | **M** |
| **U9** | **Relatório**: receita de upsell, ofertas aceitas × recusadas, produtos mais vendidos | **M** |

> **Fora de escopo (roadmap, com preço próprio):** motor de regras visual (IF/THEN/AND/OR), público-alvo (VIP/casais/recorrente), **automações temporais + WhatsApp** (precisa de agendador e WhatsApp Business API, com custo e aprovação próprios), recomendação inteligente/ML, estoque, combos, seguro com tratamento especial, ingressos com vagas por data/horário, dashboard de 18 métricas.

---

## CRONOGRAMA (3 semanas)

### Semana 1 — Jeep completo
- **Dia 0 (30 min):** criar **2º projeto Supabase grátis** como staging (NÃO usar Docker) e apontar o dev local pra ele
- **Dias 1–3:** J1 (ver/editar passageiros do slot compartilhado) — o maior gap
- **Dia 4:** J2 (pagar por todos / carro exclusivo)
- **Dia 5:** J3 (proteção da troca de modo) + J6 (ajustes finos)

### Semana 2 — Fechamento do Jeep + base do Upsell
- **Dias 1–2:** J4 (nome de veículo editável + tirar `Q{id}` de voucher/WhatsApp/relatório) + J5 (pickup pousada)
- **Dia 3:** **Demo do Jeep pro Marius** (vídeo) → fecha a Parte 1
- **Dias 4–5:** U1 (migration) + U3 (categorias) + U2 (cadastro de complementos)

### Semana 3 — Upsell no fluxo + entrega
- **Dias 1–2:** U4 (compatibilidade) + U5 (limites) + U6 (oferta no modal com aceite/recusa/motivo)
- **Dia 3:** U7 (total + comissão) + U8 (cross-sell simples)
- **Dia 4:** U9 (relatório)
- **Dia 5:** regressão, demo, deploy, vídeo pro Marius

---

## REGRAS DE OPERAÇÃO (evitar o desastre de tokens)

1. **Staging = 2º projeto Supabase grátis.** Sem Docker, sem container local.
2. **PROIBIDO ler arquivo inteiro:** `src/App.tsx` (5.821 linhas/304KB), `src/SuperAdminPage.tsx` (8.090/425KB), `package-lock.json` (318KB). Só `grep` + leitura por trecho.
3. **Sessões curtas e escopadas** — uma tarefa por vez. Nada de "trabalhe 1h sozinho".
4. **Não rodar `typecheck` completo em loop** — o repo tem 148 erros de baseline que poluem o contexto toda vez. O build de produção é `vite build` e passa.
5. **Dono por arquivo (3 agentes trabalhando):**
   - **Jeep (J1–J6)** = mexe em `src/App.tsx` → **UM agente só, sequencial**
   - **Upsell (U1–U5, U9)** = **arquivos NOVOS** (migration, painel de complementos, relatório) → pode rodar **em paralelo**, outro agente
   - **U6/U7 (upsell dentro do modal)** = toca `App.tsx` → **só depois** que o Jeep terminar, mesmo agente do Jeep
6. **Feature paga primeiro.** Infra só quando doer de verdade.

---

## ORDEM DE ATAQUE IMEDIATA (próximas 48h)

1. Criar o 2º Supabase (staging) — 30 min
2. **J1** — ver/editar passageiros do veículo compartilhado
3. **J2** — pagar por todos / carro exclusivo
4. Só então seguir a sequência acima
