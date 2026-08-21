# Proposta de Parceria — QuadriBook → Plataforma SaaS (Trip MV)

## Onde estamos
O sistema de reservas da Trip MV já está **no ar e funcionando**, com o módulo de **jeep/saída compartilhada** (vários passageiros por veículo, trava ao lotar, preço por cabeça/fechado), **agenda em tempo real** entre operadores e **correções de bugs** entregues. A operação já roda (~500 reservas/mês).

**Próximo passo:** transformar essa base em um **SaaS vendável** para outras operadoras de turismo — mantendo a Trip MV como cliente-vitrine.

---

## Modelo de parceria (recomendado)

O foco é **abrir o SaaS**, não manutenção. Então:

- ❌ **Sem mensalidade fixa** — você não paga "aluguel" de sistema.
- ✅ **Pagamento por entrega** (blocos com escopo e preço fechado) — você paga conforme cada bloco fica pronto.
- ✅ **+ % da receita recorrente do SaaS** — quando começar a vender pra outras operadoras, eu ganho um percentual. **Se você ganha, eu ganho; se não vende, eu não cobro esse percentual.** É o risco dividido que você propôs.
- ✅ **Manutenção pós-lançamento sai da receita do SaaS** (coberta pelo meu %), **não do seu bolso**.

### Por que "por entrega" é justo pros dois
Normalmente cobrar por entrega sai **mais caro** (o dev embute o risco de escopo). Mas como a gente vai **dividir a receita do SaaS**, eu **mantenho o preço de cada bloco enxuto** — esse é o "se você ganha, eu ganho" na prática. Você paga menos agora porque eu aposto no upside com você.

### A oferta (escolhe o nível de parceria)

| | **Plano A — Sócio de Produto** *(recomendado)* | **Plano B — Só serviço** |
|---|---|---|
| Mensalidade | Nenhuma | Nenhuma |
| Preço por entrega | **Enxuto** (abaixo) | Cheio (+~30%) |
| Minha % do SaaS | **20%** da receita recorrente | 0% |
| Risco | Dividido (você quer) | Todo seu |
| Ideal se | Você quer sócio técnico no produto | Você quer só executar e ser dono de 100% |

> Recomendo o **Plano A**: menos caixa agora, e eu viro parceiro do sucesso do SaaS. Quanto **menos você paga por entrega**, **maior a minha %** — é a alavanca que a gente ajusta.

---

## Preço por bloco (Plano A)

| Bloco | O que entrega | Valor |
|---|---|---|
| **Bloco 1 — Dinheiro + Modal** | Correções financeiras da auditoria + reorganização do modal de reserva (divisão de pagamento, compartilhado, upsell, nomes de veículo editáveis) | **R$ 1.500** |
| **Bloco 2 — Saída Compartilhada completa** | Módulo completo do doc: lista de espera, distribuição inteligente, motorista/guia por saída, pickup na pousada, upsell de city tour | **R$ 4.000** |
| **Bloco 3 — Plataforma SaaS** | Multi-empresa isolada + assinatura/cobrança (Asaas) + cadastro de nova operadora + personalização (logo/cor/nomes) + painel super-admin + CRM no Comercial | **R$ 7.000** |
| | **Total (parcelado por entrega)** | **~R$ 12.500** + 20% do SaaS |

*Ajuste de risco:* se quiser **aliviar o caixa agora**, dá pra reduzir os blocos (ex.: −30%) em troca de **subir minha % pra 25%**. Menos hoje, mais no upside.

---

## Roadmap detalhado

### ✅ Fase 0 — Entregue (prova de valor)
- Jeep/saída compartilhada v1 (capacidade, preço 2 modos, lotação, tempo real)
- 6 correções de bug + fix do preço por cabeça
- Auditoria (10 problemas mapeados, vários de dinheiro)
- Deploy no ar (Netlify Pro + Supabase)

### 🔴 Bloco 1 — Dinheiro + Modal de Reserva
**Correções financeiras (da auditoria):**
- Motor de comissão de parceiro ajustado pro **modelo real** (R$30 fixo + alocação inteligente — confirmar a regra exata)
- Pagamento por grupo entra no total/caixa do dia
- Voucher de parceiro não cobra cliente de novo
- "Reverter — Cliente Apto" para de apagar a reserva
- Salvar com tela antiga para de sobrescrever pagamento de outro operador

**Reorganização do modal (pedidos da call + prints):**
- **Compartilhado dentro do modal de reserva** — permitir 1 pessoa pagar por todos (carro exclusivo), casais, ou passageiros separados
- **Upsell dentro do modal** — selecionar upsell na hora da reserva
- **Divisão de pagamento só no modal** (tirar de onde está hoje)
- **Nomes de veículo editáveis** (Q1/Q2 → qualquer nome)

### 🟠 Bloco 2 — Módulo Saída Compartilhada completo (a visão do doc)
- Tipo de atividade: **Individual** vs **Saída Compartilhada**
- Saída com: capacidade, lugares disponíveis, **motorista, guia, veículo, status LOTADO**
- Cliente reserva **lugares** (não o veículo)
- **Fechamento automático** ao lotar
- **Lista de espera** (fila + promoção automática no cancelamento)
- **Múltiplos veículos** no mesmo horário
- **Distribuição inteligente** (manual / automática — encher um antes do outro)
- Jeep: **pickup na pousada** + **upsell de city tour**
- Começa cobrindo os passeios atuais: **bike, quadri, UTV, cavalo**

### 🟢 Bloco 3 — Plataforma SaaS (vendável)
- **Isolamento entre empresas** — hoje há brechas de segurança; sem corrigir, uma operadora poderia ver dados de outra. **Obrigatório antes de vender pra terceiros.**
- **Cadastro self-service** de nova operadora (onboarding)
- **Assinatura + cobrança recorrente** via Asaas (já implementei checkout Asaas em outro projeto → reaproveito, mais rápido/barato)
- **Personalização por empresa**: logo, cores, nomes dos recursos
- **Painel super-admin** (gerir operadoras e assinaturas)
- **CRM / Central de Parceiros** movida pra aba **Comercial**
- **Cadastro de produtos/serviços de upsell** (dentro do Upsell) que aparecem no modal de reserva

### 🔵 Fase 4 — Crescimento (depois, opcional)
- Portal público de reservas white-label por operadora
- Relatórios / BI
- App / notificações

---

## Sobre os planos do SaaS (sua ideia: R$80 / 150 / 260)
Faixa boa pra começar. Sugestão de diferenciação:

| Plano | ~Preço | Pra quem |
|---|---|---|
| **Essencial** | R$80 | 1 tipo de atividade, agenda + reservas, poucos operadores |
| **Pro** | R$150 | Múltiplas atividades, saída compartilhada (jeep), parceiros, upsell |
| **Premium** | R$260 | Multi-unidade, personalização white-label, relatórios, operadores ilimitados |

*Obs.: R$80 de entrada é um bom gancho; o dinheiro real vem do Pro/Premium.*

---

## Próximos passos
1. Alinhar o modelo (Plano A ou B) e a %
2. Confirmar a **regra exata da comissão** (R$30 fixo + quando aloca parceiro)
3. Eu começo pelo **Bloco 1** (rápido, é dinheiro seu em jogo)
4. Contrato simples registrando: entregas, valores e o % do SaaS (o que é %, sobre o quê, por quanto tempo)
