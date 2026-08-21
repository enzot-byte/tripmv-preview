-- ============================================================
-- JEEP — 6 migrations consolidadas para aplicar no STAGING
-- Projeto STAGING (NAO rodar em producao zpmlmjxlbrksanpycpyv)
-- Cole tudo no SQL Editor do Supabase de staging e rode uma vez.
-- Todas sao aditivas e idempotentes.
-- ============================================================



-- ############################################################
-- ARQUIVO: 20260729090000_add_vehicle_type.sql
-- ############################################################

-- =============================================================================
-- VEHICLE_TYPE — separa Quadriciclo de Jeep na camada de UI/UX.
-- =============================================================================
--
-- Ate aqui, quadriciclo e jeep sao distinguidos apenas por
-- machine_configs.booking_mode ('individual' vs 'shared_capacity'), que e a
-- coluna que o banco (triggers/indices) usa para capacidade. Isso deixou a UI
-- ambigua: nao ha como o frontend saber "isto e um jeep" sem reusar a mesma
-- coluna que controla lotacao.
--
-- Esta migration so adiciona uma coluna nova para rotulagem de UI. NAO mexe em
-- booking_mode, nos indices ou nos triggers de capacidade (20260717120000).
--
-- Backfill: qualquer veiculo ja configurado como 'shared_capacity' vira 'jeep'
-- automaticamente, para nao quebrar quem ja usa jeep em producao.
-- =============================================================================

BEGIN;

ALTER TABLE machine_configs
  ADD COLUMN IF NOT EXISTS vehicle_type text NOT NULL DEFAULT 'quadriciclo'
  CHECK (vehicle_type IN ('quadriciclo','jeep'));

UPDATE machine_configs
  SET vehicle_type = 'jeep'
  WHERE booking_mode = 'shared_capacity';

COMMIT;


-- ############################################################
-- ARQUIVO: 20260729093000_add_jeep_closed_price.sql
-- ############################################################

-- =============================================================================
-- JEEP FECHADO — preco configuravel por veiculo/temporada.
-- =============================================================================
--
-- Ate aqui o preco do "jeep fechado" era sempre a formula fixa
-- valor_unitario x assentos, duplicada em varios pontos do frontend. Esta
-- coluna deixa o dono digitar um valor fixo por veiculo (ex: temporada alta).
--
-- NULL (default) preserva o comportamento atual: o frontend cai na formula
-- antiga quando closed_price esta vazio — ver getClosedTotal() em src/App.tsx.
-- =============================================================================

BEGIN;

ALTER TABLE machine_configs
  ADD COLUMN IF NOT EXISTS closed_price numeric(10,2) NULL;

COMMIT;


-- ############################################################
-- ARQUIVO: 20260729100000_jeep_hardening.sql
-- ############################################################

-- =============================================================================
-- JEEP HARDENING — fecha 3 furos de borda da migration 20260717120000
-- (jeep_shared_capacity). NAO edita a migration original, so cria/substitui
-- funcoes e recria os indices parciais afetados.
-- =============================================================================
--
-- FURO 1 — status NULL escapa da soma de lotacao
-- -------------------------------------------------
-- `status NOT IN (...)` em SQL retorna NULL (nao TRUE) quando status e NULL, entao
-- uma reserva com status NULL desaparecia tanto da soma de passageiros no trigger
-- enforce_shared_capacity() quanto dos dois indices parciais que tem esse predicado
-- (idx_bookings_no_overlap, bookings_unique_slot_per_tenant). Troca por
-- COALESCE(status,'') NOT IN (...), que sempre avalia para TRUE/FALSE.
--
-- FURO 2 — trigger de capacidade dispara a toa
-- -----------------------------------------------
-- enforce_shared_capacity() reavalia a soma do slot inteiro em toda UPDATE de
-- passenger_count/machine_id/time_slot/date/status, mesmo quando a escrita so
-- LIBERA vaga (ex: marcar NO_SHOW num veiculo ja lotado — a carga cai, nao sobe,
-- mas o trigger ainda recalculava e podia falhar por causa doutra linha). Dois
-- early-returns: (a) NEW.status em NO_SHOW/NOT_FIT/TRANSFERRED sempre libera vaga,
-- nunca precisa validar; (b) em UPDATE que nao muda o slot (mesmo veiculo/data/
-- horario), se a carga desta linha nao aumentou, o update nao pode ter causado
-- overbooking.
--
-- FURO 3 — reserva fica orfa quando a config do veiculo muda
-- --------------------------------------------------------------
-- bookings.booking_mode e carimbado no INSERT (stamp_booking_mode) e so
-- re-carimbado se o proprio machine_id da reserva mudar. Se o DONO trocar
-- booking_mode/capacity_seats do veiculo DEPOIS que reservas futuras ja existem,
-- essas reservas mantem o booking_mode antigo e escapam dos indices unicos
-- jeep-aware. Trigger novo em machine_configs re-carimba as reservas FUTURAS
-- (date >= hoje) do veiculo sempre que booking_mode/capacity_seats mudam.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- FURO 1 — indices parciais: COALESCE(status,'') em vez de status
-- -----------------------------------------------------------------------------

DROP INDEX IF EXISTS idx_bookings_no_overlap;
CREATE UNIQUE INDEX idx_bookings_no_overlap
  ON bookings (tenant_id, machine_id, date, time_slot)
  WHERE COALESCE(status,'') NOT IN ('NO_SHOW','NOT_FIT','TRANSFERRED')
    AND booking_mode = 'individual';

DROP INDEX IF EXISTS bookings_unique_slot_per_tenant;
CREATE UNIQUE INDEX bookings_unique_slot_per_tenant
  ON bookings (tenant_id, date, time_slot, machine_id)
  WHERE tenant_id IS NOT NULL
    AND COALESCE(status,'') NOT IN ('NO_SHOW','NOT_FIT','TRANSFERRED')
    AND booking_mode = 'individual';

-- bookings_unique_slot_legacy nao tem predicado de status (so tenant_id IS NULL) —
-- nao precisa de correcao.

-- -----------------------------------------------------------------------------
-- FURO 1b + FURO 2 — enforce_shared_capacity(): COALESCE no filtro de soma +
-- early-returns para nao disparar a toa.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION enforce_shared_capacity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_seats integer;
  v_mode text;
  v_load integer;
  v_old_contrib integer;
  v_new_contrib integer;
BEGIN
  -- (a) status que libera assento nunca aumenta carga — nunca precisa validar,
  -- mesmo que o veiculo ja esteja lotado por outras linhas.
  IF NEW.status IN ('NO_SHOW','NOT_FIT','TRANSFERRED') THEN
    RETURN NEW;
  END IF;

  -- (b) UPDATE que nao muda o slot (mesmo veiculo/data/horario): so vale a pena
  -- validar se a carga desta linha CRESCEU. Se caiu ou ficou igual, nao ha como
  -- este update ter causado overbooking.
  IF TG_OP = 'UPDATE'
     AND NEW.machine_id = OLD.machine_id
     AND NEW.date = OLD.date
     AND NEW.time_slot = OLD.time_slot THEN
    v_old_contrib := CASE
      WHEN OLD.is_locked IS TRUE OR COALESCE(OLD.status,'') IN ('NO_SHOW','NOT_FIT','TRANSFERRED')
      THEN 0
      ELSE GREATEST(COALESCE(OLD.passenger_count,1),1)
    END;
    v_new_contrib := GREATEST(COALESCE(NEW.passenger_count,1),1);
    IF v_new_contrib <= v_old_contrib THEN
      RETURN NEW;
    END IF;
  END IF;

  -- IMPORTANTE: consulta o modo/assentos DIRETO do machine_configs, NAO de NEW.booking_mode
  -- (ver comentario original em 20260717120000 sobre ordem de triggers BEFORE).
  SELECT mc.booking_mode, mc.capacity_seats INTO v_mode, v_seats
  FROM machine_configs mc
  WHERE mc.tenant_id = NEW.tenant_id AND mc.id = NEW.machine_id;

  IF v_mode IS DISTINCT FROM 'shared_capacity' OR v_seats IS NULL OR v_seats <= 0 THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    COALESCE(NEW.tenant_id::text,'') || '|' || NEW.machine_id || '|' || NEW.date || '|' || NEW.time_slot, 0));

  SELECT COALESCE(SUM(GREATEST(COALESCE(b.passenger_count,1),1)),0) INTO v_load
  FROM bookings b
  WHERE b.tenant_id = NEW.tenant_id AND b.machine_id = NEW.machine_id
    AND b.date = NEW.date AND b.time_slot = NEW.time_slot
    AND b.id <> NEW.id
    AND (b.is_locked IS NOT TRUE)
    AND COALESCE(b.status,'') NOT IN ('NO_SHOW','NOT_FIT','TRANSFERRED');

  IF v_load + GREATEST(COALESCE(NEW.passenger_count,1),1) > v_seats THEN
    RAISE EXCEPTION 'CAPACIDADE: veiculo % lotado (% de % assentos)', NEW.machine_id, v_load, v_seats
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END $$;

-- Trigger ja existe (criado em 20260717120000); CREATE OR REPLACE FUNCTION acima
-- ja atualiza o corpo. Recriar o trigger so por clareza/idempotencia.
DROP TRIGGER IF EXISTS trg_enforce_shared_capacity ON bookings;
CREATE TRIGGER trg_enforce_shared_capacity
  BEFORE INSERT OR UPDATE OF passenger_count, machine_id, time_slot, date, status ON bookings
  FOR EACH ROW EXECUTE FUNCTION enforce_shared_capacity();

-- -----------------------------------------------------------------------------
-- FURO 3 — re-carimba booking_mode das reservas FUTURAS quando a config do
-- veiculo muda (booking_mode ou capacity_seats).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION restamp_future_bookings_on_config_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new_mode text;
BEGIN
  v_new_mode := CASE
    WHEN NEW.booking_mode = 'shared_capacity' AND NEW.capacity_seats IS NOT NULL AND NEW.capacity_seats > 0
    THEN 'shared_capacity'
    ELSE 'individual'
  END;

  -- So reservas futuras (o passado nao afeta disponibilidade nem indices vigentes).
  -- Se houver 2+ passageiros futuros no mesmo slot e o modo estiver voltando para
  -- 'individual', o indice unico jeep-aware vai rejeitar esta UPDATE — esperado:
  -- e o mesmo cenario ja avisado pelo confirm() de VehicleCapacityRow no frontend
  -- antes de trocar o modo pra individual.
  UPDATE bookings
  SET booking_mode = v_new_mode
  WHERE tenant_id = NEW.tenant_id
    AND machine_id = NEW.id
    AND date >= CURRENT_DATE
    AND booking_mode IS DISTINCT FROM v_new_mode;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_restamp_future_bookings_on_config_change ON machine_configs;
CREATE TRIGGER trg_restamp_future_bookings_on_config_change
  AFTER UPDATE OF booking_mode, capacity_seats ON machine_configs
  FOR EACH ROW
  WHEN (NEW.booking_mode IS DISTINCT FROM OLD.booking_mode OR NEW.capacity_seats IS DISTINCT FROM OLD.capacity_seats)
  EXECUTE FUNCTION restamp_future_bookings_on_config_change();

COMMIT;


-- ############################################################
-- ARQUIVO: 20260730080000_add_seats_blocked.sql
-- ############################################################

-- =============================================================================
-- SEATS_BLOCKED — separa "quantas PESSOAS vao" de "quantos LUGARES a reserva ocupa".
-- =============================================================================
--
-- Ate aqui, o modo "Jeep fechado" (carro exclusivo) forcava
-- bookings.passenger_count = capacity_seats no save, mesmo quando iam menos
-- pessoas que os lugares comprados. Isso fazia o check-in e o voucher mostrarem
-- gente que nao existe (2 pessoas apareciam como 4 passageiros).
--
-- Esta coluna nova guarda separadamente quantos LUGARES a reserva ocupa no
-- carro (pra lotacao/overbooking), deixando passenger_count = pessoas reais:
--   - Por cabeca:      seats_blocked = passenger_count (cada pessoa ocupa 1 lugar)
--   - Carro exclusivo: seats_blocked = capacity_seats do veiculo (4), mesmo que
--                       va menos gente
--
-- NULL (reservas antigas, quadriciclo, ou qualquer linha que o frontend nao
-- preencheu) cai no fallback COALESCE(seats_blocked, passenger_count) em todo
-- lugar que soma lotacao — ver migration de hardening seguinte. Metadata-only,
-- nao reescreve linhas existentes.
-- =============================================================================

BEGIN;

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS seats_blocked int NULL;

COMMIT;


-- ############################################################
-- ARQUIVO: 20260730090000_jeep_hardening_seats_blocked.sql
-- ############################################################

-- =============================================================================
-- JEEP HARDENING (parte 2) — lotacao passa a somar LUGARES, nao PESSOAS.
-- NAO edita 20260717120000 nem 20260729100000 — so redefine enforce_shared_capacity()
-- mais uma vez (CREATE OR REPLACE, mesma tecnica das migrations anteriores).
-- =============================================================================
--
-- FURO 4 — bookings.seats_blocked (migration 20260730080000) separa "quantas
-- pessoas vao" (passenger_count, agora sempre real — nunca mais forcado pro modo
-- exclusivo) de "quantos lugares a reserva ocupa" (seats_blocked). O trigger de
-- capacidade ainda somava passenger_count: um carro exclusivo com 2 pessoas
-- reais e seats_blocked=4 escaparia do controle de lotacao e permitiria overbooking
-- (outro cliente conseguiria reservar os "2 lugares restantes" que na verdade
-- nao existem, porque o carro foi vendido inteiro).
--
-- Troca a soma e a contribuicao de NEW por
-- COALESCE(seats_blocked, passenger_count, 1) em vez de so passenger_count.
-- O COALESCE cai em passenger_count pra reservas anteriores a esta migration
-- (seats_blocked NULL) — continuam contando exatamente como contavam antes,
-- nenhuma reserva antiga muda de comportamento.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION enforce_shared_capacity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_seats integer;
  v_mode text;
  v_load integer;
  v_old_contrib integer;
  v_new_contrib integer;
BEGIN
  -- (a) status que libera assento nunca aumenta carga — nunca precisa validar,
  -- mesmo que o veiculo ja esteja lotado por outras linhas.
  IF NEW.status IN ('NO_SHOW','NOT_FIT','TRANSFERRED') THEN
    RETURN NEW;
  END IF;

  -- (b) UPDATE que nao muda o slot (mesmo veiculo/data/horario): so vale a pena
  -- validar se a carga desta linha CRESCEU. Se caiu ou ficou igual, nao ha como
  -- este update ter causado overbooking. Lugares ocupados (seats_blocked), nao
  -- pessoas — ver FURO 4 acima.
  IF TG_OP = 'UPDATE'
     AND NEW.machine_id = OLD.machine_id
     AND NEW.date = OLD.date
     AND NEW.time_slot = OLD.time_slot THEN
    v_old_contrib := CASE
      WHEN OLD.is_locked IS TRUE OR COALESCE(OLD.status,'') IN ('NO_SHOW','NOT_FIT','TRANSFERRED')
      THEN 0
      ELSE GREATEST(COALESCE(OLD.seats_blocked, OLD.passenger_count, 1), 1)
    END;
    v_new_contrib := GREATEST(COALESCE(NEW.seats_blocked, NEW.passenger_count, 1), 1);
    IF v_new_contrib <= v_old_contrib THEN
      RETURN NEW;
    END IF;
  END IF;

  -- IMPORTANTE: consulta o modo/assentos DIRETO do machine_configs, NAO de NEW.booking_mode
  -- (ver comentario original em 20260717120000 sobre ordem de triggers BEFORE).
  SELECT mc.booking_mode, mc.capacity_seats INTO v_mode, v_seats
  FROM machine_configs mc
  WHERE mc.tenant_id = NEW.tenant_id AND mc.id = NEW.machine_id;

  IF v_mode IS DISTINCT FROM 'shared_capacity' OR v_seats IS NULL OR v_seats <= 0 THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    COALESCE(NEW.tenant_id::text,'') || '|' || NEW.machine_id || '|' || NEW.date || '|' || NEW.time_slot, 0));

  -- Soma LUGARES ocupados pelas outras reservas do slot (carro exclusivo conta
  -- capacity_seats inteiro mesmo com menos gente a bordo) — nao soma pessoas.
  SELECT COALESCE(SUM(GREATEST(COALESCE(b.seats_blocked, b.passenger_count, 1), 1)),0) INTO v_load
  FROM bookings b
  WHERE b.tenant_id = NEW.tenant_id AND b.machine_id = NEW.machine_id
    AND b.date = NEW.date AND b.time_slot = NEW.time_slot
    AND b.id <> NEW.id
    AND (b.is_locked IS NOT TRUE)
    AND COALESCE(b.status,'') NOT IN ('NO_SHOW','NOT_FIT','TRANSFERRED');

  IF v_load + GREATEST(COALESCE(NEW.seats_blocked, NEW.passenger_count, 1), 1) > v_seats THEN
    RAISE EXCEPTION 'CAPACIDADE: veiculo % lotado (% de % assentos)', NEW.machine_id, v_load, v_seats
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END $$;

-- Adiciona seats_blocked na lista de colunas que disparam o trigger (alem das
-- ja existentes) — sem isso, um UPDATE que so muda seats_blocked (sem tocar
-- passenger_count/machine_id/time_slot/date/status) nao revalidaria a lotacao.
DROP TRIGGER IF EXISTS trg_enforce_shared_capacity ON bookings;
CREATE TRIGGER trg_enforce_shared_capacity
  BEFORE INSERT OR UPDATE OF passenger_count, seats_blocked, machine_id, time_slot, date, status ON bookings
  FOR EACH ROW EXECUTE FUNCTION enforce_shared_capacity();

COMMIT;


-- ############################################################
-- ARQUIVO: 20260730120000_jeep_restamp_seats_blocked_on_increase.sql
-- ############################################################

-- =============================================================================
-- JEEP — aumentar assentos re-carimba seats_blocked das reservas EXCLUSIVAS.
-- NAO edita 20260717120000, 20260729100000 nem 20260730090000 — so redefine
-- restamp_future_bookings_on_config_change() mais uma vez (CREATE OR REPLACE).
-- =============================================================================
--
-- FURO 5 — trocar de 4 para 6 assentos deixa as reservas exclusivas travando
-- so os 4 lugares antigos
-- --------------------------------------------------------------------------
-- Cenario: cliente compra o carro exclusivo de 4 lugares (seats_blocked=4). O
-- dono aumenta a capacidade do veiculo de 4 para 6 assentos (reducao ja e
-- bloqueada por commitSeats no frontend; aumento passa direto, nao ha por que
-- bloquear). A celula da agenda passa a mostrar "4 de 6 lugares livres" e outro
-- operador consegue vender 2 lugares DENTRO do carro ja vendido inteiro — o
-- trigger enforce_shared_capacity aprova corretamente 4 (exclusiva) + 2 (novo)
-- <= 6 (capacidade nova), porque seats_blocked da reserva exclusiva nunca foi
-- atualizado pra acompanhar o aumento.
--
-- Corrige redefinindo restamp_future_bookings_on_config_change() (ja
-- responsavel por re-carimbar booking_mode quando a config do veiculo muda)
-- pra TAMBEM atualizar seats_blocked das reservas futuras quando a capacidade
-- AUMENTA: qualquer reserva futura com seats_blocked == capacidade ANTIGA (ou
-- seja, uma exclusiva que travava o carro inteiro) passa a travar a
-- capacidade NOVA. So dispara quando NEW.capacity_seats > OLD.capacity_seats;
-- reducao de assentos ja e bloqueada no frontend antes de chegar aqui, e o
-- caso de zerar capacity_seats (voltar pra quadriciclo) fica de fora da
-- comparacao numerica (NULL nunca e "maior que" nada).
--
-- Este UPDATE em bookings.seats_blocked dispara o trigger de capacidade
-- (enforce_shared_capacity, que ja escuta UPDATE OF seats_blocked desde
-- 20260730090000) — sem risco de rejeitar a propria atualizacao: uma reserva
-- exclusiva legitima e a UNICA no seu slot, entao a soma das OUTRAS reservas
-- (v_load) e sempre 0, e 0 + capacidade_nova <= capacidade_nova nunca estoura.
-- Sem recursao: enforce_shared_capacity so VALIDA (ou levanta excecao), nunca
-- escreve em machine_configs, entao nao ha como reacionar este trigger.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION restamp_future_bookings_on_config_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new_mode text;
BEGIN
  v_new_mode := CASE
    WHEN NEW.booking_mode = 'shared_capacity' AND NEW.capacity_seats IS NOT NULL AND NEW.capacity_seats > 0
    THEN 'shared_capacity'
    ELSE 'individual'
  END;

  -- So reservas futuras (o passado nao afeta disponibilidade nem indices vigentes).
  -- Se houver 2+ passageiros futuros no mesmo slot e o modo estiver voltando para
  -- 'individual', o indice unico jeep-aware vai rejeitar esta UPDATE — esperado:
  -- e o mesmo cenario ja avisado pelo confirm() de VehicleCapacityRow no frontend
  -- antes de trocar o modo pra individual.
  UPDATE bookings
  SET booking_mode = v_new_mode
  WHERE tenant_id = NEW.tenant_id
    AND machine_id = NEW.id
    AND date >= CURRENT_DATE
    AND booking_mode IS DISTINCT FROM v_new_mode;

  -- FURO 5: capacidade AUMENTOU — reservas exclusivas futuras (seats_blocked ==
  -- capacidade ANTIGA) passam a travar a capacidade NOVA. Individual/quadriciclo
  -- nunca tem seats_blocked preenchido, entao nunca casa com este WHERE.
  IF NEW.capacity_seats IS NOT NULL AND OLD.capacity_seats IS NOT NULL AND NEW.capacity_seats > OLD.capacity_seats THEN
    UPDATE bookings
    SET seats_blocked = NEW.capacity_seats
    WHERE tenant_id = NEW.tenant_id
      AND machine_id = NEW.id
      AND date >= CURRENT_DATE
      AND seats_blocked = OLD.capacity_seats;
  END IF;

  RETURN NEW;
END $$;

-- Trigger ja existe (criado em 20260729100000); CREATE OR REPLACE FUNCTION acima
-- ja atualiza o corpo. Recriar o trigger so por clareza/idempotencia.
DROP TRIGGER IF EXISTS trg_restamp_future_bookings_on_config_change ON machine_configs;
CREATE TRIGGER trg_restamp_future_bookings_on_config_change
  AFTER UPDATE OF booking_mode, capacity_seats ON machine_configs
  FOR EACH ROW
  WHEN (NEW.booking_mode IS DISTINCT FROM OLD.booking_mode OR NEW.capacity_seats IS DISTINCT FROM OLD.capacity_seats)
  EXECUTE FUNCTION restamp_future_bookings_on_config_change();

COMMIT;
