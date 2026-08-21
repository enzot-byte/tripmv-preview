# PROMPT P0 — Fixes críticos do J1/J2 (colar no agente executor)

```
Repo: C:/Users/Zicap/OneDrive/Desktop/quadribook-live, branch feat/jeep-shared-capacity.

REGRA DE CUSTO: NUNCA leia src/App.tsx inteiro (5.900 linhas), nem package-lock.json,
nem SuperAdminPage.tsx. Use grep e leia SO os intervalos indicados (+-30 linhas se precisar
de contexto). src/components/SharedSlotPassengers.tsx pode ler inteiro (120 linhas).

Aplique os 6 fixes abaixo, em ordem. Nao refatore nada alem do pedido. Ao final rode
`npx tsc --noEmit -p tsconfig.app.json` e confirme que os erros TS2304 do App.tsx sumiram
(erros TS6133/pre-existentes de outros arquivos podem ficar), e `npm run build`.

--- FIX 1 (2 linhas) — ReferenceError: `groupId` fora de escopo ---
App.tsx:1324 `setOpenModalBookingId(groupId);` esta fora do if/else que declara groupId
(unico `const groupId` relevante em 1263, dentro do `else`). Confirmado por tsc:
`src/App.tsx(1324,27): error TS2304`. Isso mata o guard de edicao concorrente.
- No topo de openBookingModal (perto de 1187), declarar:
  const modalTrackId = existing ? (existing.group_id || existing.id) : `${Date.now()}`;
- No ramo `else` (1263), usar `modalTrackId` no lugar de criar um novo `${Date.now()}`
  (manter os usos em id/group_id apontando para ele, para nao mudar o formato do id).
- Trocar 1324 por `setOpenModalBookingId(modalTrackId);`

--- FIX 2 — auto NO_SHOW esvazia o jeep ---
Hoje getSlotBookings === getActiveSlotBookings (1126-1127), entao passageiros NO_SHOW/NOT_FIT
somem da celula e da lista, e o slot volta a aceitar nova reserva (o job automatico roda a
cada 60s, 15 min apos o horario).
- Manter getActiveSlotBookings/getSlotLoad EXATAMENTE como estao (assento liberado = correto).
- Criar `getSlotRows(time, machineId)`: mesmo filtro, mas SEM excluir NO_SHOW e NOT_FIT
  (continua excluindo is_locked e TRANSFERRED). Ordenar por created_at (fallback id).
- getSlotBookings passa a retornar getSlotRows (alimenta handleSlotClick e a lista).
- Na celula (~3265): `const slotRowsCount = isShared ? getSlotRows(time, machine).length : 0;`
  e `const hasSharedPassengers = isShared && !isOccupied && slotRowsCount > 0;`
- No badge (~3558): quando isShared e `slotRowsCount > slotLoad`, mostrar
  `${slotLoad}/${seats} · ${slotRowsCount - slotLoad} no-show`.
- Em SharedSlotPassengers.tsx: detectar `b.status === 'NO_SHOW' || b.status === 'NOT_FIT'` e
  renderizar o item com opacity-60 + badge cinza "Nao compareceu"/"Nao apto", mantendo o
  botao Editar ativo. O contador `load`/`isFull` continua usando getSlotLoad. NAO mudar.

--- FIX 3 — manutencao / presenca de parceiro / slot_lock escondem o jeep com gente ---
Em veiculo shared parcialmente cheio isOccupied=false, entao os 3 guards de "celula vazia"
vencem e o operador NAO consegue nem VER quem esta a bordo. Os guards valem para CRIAR,
nunca para LER.
- App.tsx ~3322 (estilo): `if (isMaintenance && !isOccupied && !hasSharedPassengers)`.
- App.tsx ~3317 (estilo sky do jeep): remover `&& !slotPresence && !adminSlotLock`.
- App.tsx ~3400-3407 (onClick):
    if (isMaintenance && !isOccupied && !hasSharedPassengers) { alert(...); return; }
    if (slotPresence && !hasSharedPassengers) return;
    if (adminSlotLock && !adminLockOwnedByMe && !hasSharedPassengers) return;
    void handleSlotClick(time, machine).catch(console.error);
- App.tsx ~3443 e ~3535-3560 (conteudo): mover o ramo `hasSharedPassengers ?` para ANTES
  dos ramos `slotPresence ?`, `adminSlotLock ?` e do de manutencao. Quando hasSharedPassengers
  E (slotPresence || adminSlotLock || isMaintenance), renderizar "N a bordo" + selo pequeno
  ("parceiro preenchendo" / "operador reservando" / "manutencao").
- Badge X/N (~3558): remover `&& !slotPresence && !adminSlotLock && !isMaintenance` quando
  isShared && hasSharedPassengers.
- Calcular um `blockedReason` (string|null) a partir de manutencao/presenca/lock e passar
  para SharedSlotPassengers como prop. Quando presente, desabilitar SO o botao
  "Adicionar passageiro" com o texto do motivo. Ler/editar continua liberado.

--- FIX 4 — gate de permissao trocado no ramo shared (VER no lugar de CRIAR) ---
App.tsx:1332-1343. Substituir por:

  if (getMachineMode(machineId).mode === 'shared_capacity') {
    const slotBookings = getSlotBookings(time, machineId);
    if (slotBookings.length > 0) {
      const canSeeList = isManagerMode || isAdminMode || livePermissions.can_view_booking_details;
      if (!canSeeList) {
        const { seats } = getMachineMode(machineId);
        if (canCreateBooking && getSlotLoad(time, machineId) < seats) {
          await openBookingModal(time, machineId, undefined);
          return;
        }
        error('Você não tem permissão para visualizar os detalhes desta reserva.');
        return;
      }
      setSharedPassengersSlot({ date: selectedDate, time, machineId });
      return;
    }
    await openBookingModal(time, machineId, undefined);
    return;
  }

(Nota: `date: selectedDate` — ver FIX 6.)

--- FIX 5 — "+ Adicionar passageiro" ignora canCreateBooking e destroi a lista ---
Atinge o preset PADRAO `funcionario` (can_view_booking_details: true + can_create_booking: false).
- SharedSlotPassengers.tsx: adicionar props `canAdd: boolean` e `blockedReason?: string`.
  Botao: `disabled={isFull || !canAdd || !!blockedReason}` e label
  `isFull ? 'Veículo lotado' : !canAdd ? 'Sem permissão' : blockedReason ?? 'Adicionar passageiro'`.
- App.tsx (~3607): passar `canAdd={canCreateBooking}` e o blockedReason do FIX 3.
- App.tsx:1355-1367: validar ANTES de fechar a lista, com async/await + catch:

  const handleAddSharedPassenger = async () => {
    if (!sharedPassengersSlot) return;
    if (!canCreateBooking) { error('Você não tem permissão para criar reservas.'); return; }
    const { time, machineId } = sharedPassengersSlot;
    setSharedPassengersSlot(null);
    try { await openBookingModal(time, machineId, undefined); }
    catch (e) { console.error(e); error('Falha ao abrir a reserva.'); }
  };

  const handleEditSharedPassenger = async (booking: Booking) => {
    setSharedPassengersSlot(null);
    try { await openBookingModal(booking.time_slot, booking.machine_id, booking); }
    catch (e) { console.error(e); error('Falha ao abrir a reserva.'); }
  };

--- FIX 6 — o modal mente sobre lugares livres + estado da lista sem data ---
(a) Bloco J2 (~4655-4712): separar os dois numeros:
    const freeSeats = Math.max(0, seats - othersLoad);   // para o TEXTO
    const maxPassengers = Math.max(1, freeSeats);        // so para o clamp do input
- Titulo: freeSeats === 0 -> "Veículo Compartilhado — Lotado", senao
  "Veículo Compartilhado — {freeSeats} de {seats} lugares livres".
- Texto auxiliar: usar freeSeats, nao maxPassengers.
- Nao renderizar o bloco quando seats <= 1. Em SharedSlotPassengers.tsx trocar por
  `const isExclusive = seats > 1 && seatsCount >= seats;`
- No handler de erro do save, ANTES da mensagem generica de conflito de maquina, checar
  `if ((err.message || '').includes('CAPACIDADE:'))` e mostrar
  "O veículo lotou enquanto você preenchia. Revise a quantidade de passageiros."
  MANTENDO o modal aberto.

(b) sharedPassengersSlot sem data:
- App.tsx:469: `useState<{ date: string; time: string; machineId: number } | null>(null)`
- Render (~3605): so renderizar se `sharedPassengersSlot.date === selectedDate`.
- Adicionar `setSharedPassengersSlot(null)` em closeModal (~1369) e em
  handleBookingSelectFromHeader (~800), defensivo.

--- NAO FACA ---
- Nao mexa em TransferModal.tsx nem nas edge functions public-booking/partner-booking.
- Nao crie migration nesta rodada.
- Nao commite nem faca push.

AO TERMINAR: rode `git diff --stat` e me mostre a saida.
```

---

## FICA PRA SEGUNDA RODADA (P1)
- **FIX 7** — jeep lotado mostra linha arbitrária (nome "pula" entre passageiros)
- **FIX 9** — `runAutoNoShow` em lote: 1 linha ruim derruba o dia inteiro, falha silenciosa
- **FIX 10** — migration `jeep_capacity_hardening`: enforce só quando a carga AUMENTA,
  `COALESCE(status,'RESERVED')`, re-carimbar `booking_mode` quando a config muda,
  e travar redução de assentos abaixo da carga
- **FORA DE ESCOPO (decisão de produto)** — TransferModal + edge functions públicas ignoram
  capacidade: jeep com 1 passageiro **some do site público**, e `public-booking` grava sem
  `passenger_count`. Se o Marius vende jeep pelo site, isso vira blocker comercial.
