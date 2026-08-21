# TAREFA: Separar Jeep de Quadriciclo e fechar o módulo Jeep

Repositório: `C:\Users\Zicap\OneDrive\Desktop\quadribook-live`
Branch base: `main` (atualizado). Crie a branch `feat/jeep-separado`.

## CONTEXTO

O app é o QuadriBook, sistema de reservas de passeios. Hoje **quadriciclo e jeep usam o mesmo código**, diferenciados só por `machine_configs.booking_mode` (`individual` vs `shared_capacity`). Isso ficou confuso: o operador vê opções de jeep em linha de quadriciclo e vice-versa.

**Regra de ouro deste trabalho:**
- **Quadriciclo = comportamento ATUAL, intocado.** Vai 1 ou 2 pessoas, quase sempre 2. Nenhuma mudança de comportamento, nenhuma "melhoria" não pedida. Se você encontrar bug real no quadriciclo, **reporte, não conserte** sem autorização.
- **Jeep = a lógica nova** (capacidade compartilhada, preço por cabeça ou fechado, embarque em pousada). Toda a UI específica de jeep deve aparecer **apenas** em veículo do tipo jeep.

Não é pra reescrever nada. É separação por tipo + fechar os itens que faltam.

---

## BLOCO 0 — Separar os tipos (faça este primeiro, é a base)

Hoje não existe campo de tipo de veículo (`grep vehicle_type` retorna vazio).

1. **Migration nova e aditiva** (nunca edite migration existente):
   - `ALTER TABLE machine_configs ADD COLUMN IF NOT EXISTS vehicle_type text NOT NULL DEFAULT 'quadriciclo';`
   - `CHECK (vehicle_type IN ('quadriciclo','jeep'))`.
   - **Backfill:** `UPDATE machine_configs SET vehicle_type = 'jeep' WHERE booking_mode = 'shared_capacity';` — assim nada quebra pra quem já configurou jeep.
2. Adicione `vehicle_type?: 'quadriciclo' | 'jeep'` ao tipo `MachineConfig` em `src/types/index.ts` (~linha 178) e inclua no select/map do hook `src/hooks/useMachineConfigs.ts`.
3. Na config de veículo (`VehicleCapacityRow`, `src/App.tsx:188-361`): adicione um seletor **Tipo: Quadriciclo | Jeep** como o **primeiro** campo da linha.
   - Tipo **Quadriciclo** → esconde TODOS os campos de jeep (assentos/capacidade, modo de preço padrão, compartilhado). A linha fica igual ao que era antes do jeep existir.
   - Tipo **Jeep** → mostra os campos de jeep que já existem hoje. Ao marcar Jeep pela primeira vez, sugira **4 assentos** como padrão (é a frota real do cliente), mas deixe editável.
4. No modal de reserva (`src/App.tsx`), tudo que é específico de jeep passa a ser gated por `vehicle_type === 'jeep'`, não mais por `booking_mode`:
   - Toggle "Por cabeça / Jeep fechado" (~`App.tsx:4899-4958`)
   - Controle de assentos livres / lotação (~`App.tsx:4877-4979`)
   - Campo de local de embarque (~`App.tsx:5013-5021`)
   Em quadriciclo esses blocos **não renderizam**, exatamente como antes.
5. Mantenha `booking_mode` funcionando como está (é ele que o trigger do banco usa). `vehicle_type` é a camada de UI/UX; não troque a lógica de capacidade do banco por ele.

**Critério de aceite do Bloco 0:** abrir a config, marcar um veículo como Quadriciclo → a tela dele fica idêntica ao comportamento antigo; marcar outro como Jeep → aparecem assentos, modo de preço e embarque. Reservas existentes continuam funcionando nos dois.

Commit: `feat(jeep): separa tipo de veiculo quadriciclo vs jeep`

---

## BLOCO 1 — Jeep exclusivo: paga o carro cheio, mas leva quem quiser

**Regra de negócio confirmada pelo dono:** o jeep tem **4 lugares**. "Exclusivo" significa **pagar pelos 4 lugares**, mesmo que vão **menos pessoas** (ex: 2 pessoas pagam por 4 e ninguém mais entra no carro). Também existe o caso de 4 passageiros separados dividindo o mesmo carro (isso já funciona hoje).

**O comportamento atual está ERRADO pra essa regra:** hoje o modo "Jeep fechado" força `passenger_count = assentos` (`App.tsx:1893-1895, 4935`). Isso faz a reserva de 2 pessoas aparecer como **4 passageiros** na lista de embarque, no check-in e no voucher — informação falsa pro operador na hora de embarcar.

Separe os dois conceitos:

1. Migration aditiva em `bookings`: `seats_blocked int NULL`.
   - `passenger_count` = **quantas pessoas vão de verdade** (o que o operador digita).
   - `seats_blocked` = **quantos lugares a reserva ocupa** no carro. No modo exclusivo, `seats_blocked = capacity_seats` (4). No modo por-cabeça, `seats_blocked = passenger_count`.
2. Migration aditiva: `machine_configs.closed_price numeric(10,2) NULL` + campo no tipo `MachineConfig` + select/map do hook.
3. Input **"Valor do carro exclusivo (R$)"** na `VehicleCapacityRow` (~`App.tsx:345-357`), visível só quando `vehicle_type === 'jeep'`. Vazio = usa a fórmula antiga `valor × assentos`.
4. Crie **uma única função** `getClosedTotal(machineId, unitValue, seats)` = `closed_price ?? unitValue * seats` e use nos 3 pontos que hoje duplicam a conta: `App.tsx:1578-1581` (preview), `1887-1889` (save), `4907` (display do toggle).
5. No modo exclusivo, **pare de sobrescrever `passenger_count`**. Em vez disso grave `seats_blocked = capacity_seats`. O botão "Carro exclusivo" **deixa de ser desabilitado quando já tem gente a bordo** — só bloqueie se os lugares livres forem menos que a capacidade total (aí não dá pra fechar mesmo).
6. **A trava de lotação do banco passa a somar `seats_blocked`**, não `passenger_count` — faça isso na migration do Bloco 3, com `COALESCE(seats_blocked, passenger_count)` pra não quebrar as reservas antigas.
7. Na tela, mostre os dois quando forem diferentes: *"2 pessoas · carro exclusivo (4 lugares)"*.

**Aceite:** criar reserva de 2 pessoas em carro exclusivo → cobra o valor do carro cheio, o jeep some da grade pra outros clientes, e o check-in/voucher mostram **2 passageiros**, não 4.

Commit: `feat(jeep): carro exclusivo cobra 4 lugares sem inflar a lista de passageiros`

---

## BLOCO 2 — Buscar no hotel: sim/não + campo que aprende

**Regra de negócio confirmada pelo dono:** eles **não têm pousada parceira fixa**. Na hora da venda perguntam se o cliente quer a comodidade de ser buscado no hotel/pousada. Ou seja: **não construa lista fixa cadastrada** — seria cadastro morto.

O que fazer, bem mais simples do que parece:

1. No modal de reserva, antes do campo de embarque, coloque um toggle **"Buscar no hotel/pousada?"** (Sim / Não). Padrão: **Não**.
2. Marcou **Não** → o campo de local nem aparece, `pickup_location` fica vazio (comportamento de hoje pra quem não usa).
3. Marcou **Sim** → aparece o campo de texto livre que já existe (`App.tsx:5013-5021`), **com sugestões dos locais já usados antes**: faça um `SELECT DISTINCT pickup_location FROM bookings WHERE tenant_id = ... AND pickup_location IS NOT NULL AND pickup_location <> '' ORDER BY ... LIMIT 20` e ligue num `<datalist>` no input. O operador digita "Pous" e aparece "Pousada do Sol — recepção" que ele já usou.
4. Assim a lista **se constrói sozinha** com o uso, sem tela de cadastro nenhuma.
5. `bookings.pickup_location` continua string — **não mude** o save, o WhatsApp nem o voucher.

**Não crie** `usePickupLocations.ts` nem `PickupLocationManager.tsx`. Não é lista cadastrada.

**ATENÇÃO — armadilha conhecida:** se você criar qualquer subscription de realtime, o nome do canal **precisa** de sufixo único por instância (`` `nome-${Date.now()}-${Math.random().toString(36).slice(2)}` ``). Canal com nome fixo derruba o app inteiro com `cannot add postgres_changes callbacks after subscribe()` — isso já quebrou a produção uma vez. Copie o padrão do `useTimeSlots.ts`. (Aqui você provavelmente não precisa de realtime nenhum: basta buscar as sugestões uma vez ao abrir o modal.)

**Aceite:** reserva sem pickup fica igual a hoje; marcando "Sim", digitar 3 letras sugere os locais já usados; o voucher mostra o local certo.

Commit: `feat(jeep): opcao de buscar no hotel com sugestao dos locais ja usados`

---

## BLOCO 3 — Migration de blindagem do jeep

A migration `supabase/migrations/20260717120000_jeep_shared_capacity.sql` protege contra overbooking, mas tem 3 furos de borda. **Crie uma migration NOVA** (`2026072X_jeep_hardening.sql`), nunca edite a existente.

1. **Status NULL escapa da soma:** em `20260717120000...:173` o filtro é `b.status NOT IN (...)`. Em SQL, `NULL NOT IN (...)` é NULL, não TRUE — reserva com status nulo some da conta de lotação. Troque por `COALESCE(b.status,'') NOT IN (...)`. Mesma correção nos índices parciais (linhas ~131 e ~138).
2. **Trigger dispara à toa:** `enforce_shared_capacity` (~linha 175) valida em toda escrita. Faça early-return quando `NEW.status` for `NO_SHOW`, `NOT_FIT` ou `TRANSFERRED`, e quando a carga **não aumenta** (só valide se a soma de passageiros cresceu).
3. **Config muda e reserva fica órfã:** se o dono trocar `booking_mode`/`capacity_seats` do veículo, reservas futuras mantêm o `booking_mode` antigo e escapam dos índices únicos. Crie trigger que re-carimba `bookings.booking_mode` das reservas **futuras** quando a config do veículo muda.
4. **Lotação passa a somar lugares, não pessoas** (vem do Bloco 1): troque a soma de `passenger_count` por `COALESCE(seats_blocked, passenger_count)`. O `COALESCE` é obrigatório — sem ele toda reserva antiga (que tem `seats_blocked` NULL) sai da conta e o jeep fica aceitando overbooking.

**Aceite:** teste no Supabase local/staging — reserva com status NULL passa a contar na lotação; marcar NO_SHOW num jeep lotado não dá erro; trocar o veículo de individual→compartilhado re-carimba as reservas futuras; carro exclusivo de 2 pessoas trava os 4 lugares; e reserva criada **antes** desta migration continua contando certo.

Commit: `fix(jeep): blindagem do trigger de capacidade (status nulo, no-show, troca de config)`

---

## BLOCO 4 — Nome do veículo em todas as telas

O rename de veículo (ex: "Q1" → "Jeep Toyota") já funciona na agenda via `getMachineName(id)` (`useMachineConfigs.ts:171-174`), mas ~9 telas ainda imprimem `` `Q${machine_id}` `` na mão.

Troque por `getMachineName(id)` em:
`CheckInPage.tsx` (143, 303, 368, 386, 425, 443) · `PartnerPortal.tsx` (268, 310, 422, 1453, 1522) · `components/FutureBookingsPanel.tsx` (86, 166, 404, 536, 622) · `VoucherImageWrapper.tsx` (39) · `VoucherPDFWrapper.tsx` (41, 67) · `components/PaymentDivisionPanel.tsx` (269, 328) · `components/UnfitToRideModal.tsx` (122) · `Header.tsx` (171, 301) · `OperationalStats.tsx` (353) · `TransferModal.tsx` (339, 578) · `BookingSearch.tsx` (144) · `SimilarBookingsAlert.tsx` (25)

Onde o componente não tem acesso ao hook, passe `getMachineName` por prop (padrão já usado em `HighDemandAlert`).

**NÃO mexa** em `useMachineConfigs.ts:173` nem no placeholder `Q{id}` da `VehicleCapacityRow` (`App.tsx:293-294`) — esses são o fallback canônico e devem continuar.

**Bônus obrigatório:** `HighDemandAlert.tsx:47` tem fallback `` `Quad ${id}` `` divergente do padrão. Alinhe para `` `Q${id}` ``.

**Aceite:** renomear um veículo na config e o nome novo aparecer no check-in, no portal do parceiro, no voucher PDF e na imagem do voucher.

Commit: `fix(jeep): usa nome real do veiculo em todas as telas`

---

## BLOCO 5 — Acabamentos do modo por-cabeça

1. **Centavo perdido:** no modo por cabeça, valor que não divide certo perde centavo (R$100 ÷ 3 = 99,99). Distribua o resto entre os passageiros (os primeiros N pagam R$0,01 a mais) para que a soma bata **exatamente** com o total. Regra de arredondamento: 2 casas decimais, arredondamento normal (0,005 sobe).
2. **Label errado:** o sufixo "/máq." aparece no modo por cabeça, onde não faz sentido. No modo por cabeça deve ser "/pessoa" (ou nada); "/máq." só no modo fechado.

Commit: `fix(jeep): centavo no rateio por cabeca e label do modo de preco`

---

## REGRAS DE EXECUÇÃO (leia antes de começar)

1. **Um commit por bloco**, na ordem 0 → 5. Não junte tudo num commit só.
2. **Rode `npm run build` antes de cada commit.** Se não compilar, conserte antes de commitar.
3. **Migrations são sempre aditivas.** Nunca edite arquivo de migration já existente — só crie novo.
4. **Canal de realtime SEMPRE com sufixo único** (`Date.now()` + random). Nome fixo derruba a produção inteira. Não crie exceção.
5. **`publicDir` do Vite é `public3`**, não `public`. Se precisar mexer em asset (não deve precisar aqui), é em `public3/`.
6. **Não toque em `.env`** nem em nada de credencial.
7. **Não faça deploy, não faça push pro `main`, não abra PR.** Trabalhe na branch e pare.
8. **Não mexa em CRM, upsell ou cross-sell** — outro módulo, outra tarefa.
9. **Não "melhore" quadriciclo.** Se achar bug lá, escreva no relatório final e siga.
10. Se algum bloco for maior do que parece ou você encontrar algo que contradiz este prompt, **pare e reporte** em vez de improvisar.

## ENTREGÁVEL FINAL

Ao terminar, escreva um resumo curto com:
- O que ficou pronto por bloco (com os commits).
- O que **precisa ser testado manualmente** e o passo a passo exato pra testar (clique-a-clique, assumindo que quem testa não conhece o código).
- Qualquer coisa que você encontrou e **não** consertou, e por quê.
