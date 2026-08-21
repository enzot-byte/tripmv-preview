# PLANO DE ATAQUE — Design System + Reorganização
## QuadriBook / Trip Experience Quadriciclos MV

> Documento de execução. Escrito para ser revisado por outro modelo e executado
> em uma passada. Toda decisão aqui é sustentada por evidência levantada no
> banco de produção e no código — as fontes estão citadas.

---

# 0. CONTEXTO

Sistema de reservas de turismo de aventura em Monte Verde/MG. React + TypeScript
+ Vite + Supabase. Nasceu no Bolt, cresceu sem arquitetura, e hoje atende uma
operação real: **R$ 619.634,94 em 2.394 reservas**.

O projeto vai virar SaaS revendável. Antes disso precisa parar de ser um
amontoado de telas empilhadas.

**Repositório:** `C:\Users\Zicap\OneDrive\Desktop\quadribook-live`
**Produção:** `quadribook.com.br` (deploy automático via GitHub → Netlify)
**Banco:** Supabase, projeto `zpmlmjxlbrksanpycpyv`

---

# 1. EVIDÊNCIA — por que este trabalho existe

Tudo abaixo foi medido, não suposto.

## 1.1 Onde o dinheiro entra

| Canal | Reservas | Faturamento | % |
|---|---|---|---|
| Balcão (`internal`) | 2.317 | R$ 608.034,94 | **98,1%** |
| Parceiro (`partner`) | 77 | R$ 11.600,00 | 1,9% |
| Site (`public`) | **0** | R$ 0,00 | **0%** |

**Consequência de projeto:** a agenda do balcão é o coração absoluto. Tudo o mais
é periferia. O canal do site está zerado — é oportunidade, não fracasso.

## 1.2 Módulos que não têm dado

```
CRM clientes ............. 96   (provavelmente automático das reservas)
Usuários (tenant Marius) . 19
Parceiros ................  4
Promoções relâmpago ......  3
Upsell produtos ..........  3
Vouchers promo ...........  1
Experiência — itens ......  0   ← tela inteira, zero registro
Experiência — pacotes ....  0   ← idem
CRM oportunidades ........  0   ← funil nunca usado
```

## 1.3 Duplicação de configuração

Inventário completo em `INVENTARIO-CONFIGURACOES.md` (779 campos catalogados,
branch `feat/inventario-configuracoes`).

- **16 grupos de colisão**, cobrindo **29 chaves** editáveis em 2+ telas
- `whatsapp_url` tem **4 editores**: `App.tsx:4989`, `VisualSettings.tsx:659`,
  `AdminPage.tsx:737`, `VoucherSettings.tsx:512`
- `location_url` idem
- `configToUpsertRows` (`useConfig.ts:89`) grava **12 chaves de uma vez**, tocadas
  ou não — não é o campo editado que colide, são os 11 que vão junto
- `reservation_fee` e `default_machine_value` são chaves de **dinheiro** que
  **nenhuma tela edita**, mas todo save reescreve. `default_machine_value` é lido
  em `App.tsx:2035` como preço padrão de reserva

## 1.4 O menu contém a si mesmo

Existem **duas navegações de configuração empilhadas**:

1. Modal "Configurações" em `App.tsx` (~4940) — 6 abas
2. `AdminPage.tsx` `NAV_GROUPS` (~159) — 8 grupos

A aba **Admin** do modal abre a `AdminPage` inteira dentro dele. **8 itens
aparecem nos dois caminhos** (Links, Horários, Manutenção, Aparência,
VisualSettings, Ícones, Experiência, Tema).

Três são o mesmo componente com props diferentes — e **"Horários" perde o aviso
"este horário tem reservas" no caminho Admin**, porque `bookings` chega vazio.

## 1.5 Cor sem sistema

Valores reais lidos da produção:

```
#2563eb  azul    theme_primary_color        (painel)
#1e40af  azul    theme_header_color         (painel)
#2563eb  azul    tenant_branding.primary
#0284c7  azul    color_primary              (página pública)
#3b82f6  azul    voucher_border_color
#059669  verde   theme_secondary_color
#059669  verde   tenant_branding.secondary
#308232  verde   voucher_border_color_jeep  ← verde solto, digitado uma vez
#f0f9ff  azul    color_background
Inter            font_heading               (default)
```

**5 azuis. 2 verdes. Zero relação com a marca.** Todos são cores padrão do
Tailwind — vieram do template e ficaram. Moram em **4 tabelas diferentes**
(`company_settings`, `public_booking_branding`, `tenant_branding`,
`landing_page_settings`) que não conversam.

## 1.6 Custo operacional da bagunça

Medido com o desenvolvedor do próprio sistema operando:

- **Fluxo principal: ~15 cliques** (criar → pagar → check-in → voucher → excluir)
- **Teste de 10 segundos: 0 de 3 acertos.** Perguntado "quantas reservas hoje /
  quanto falta receber / tem alguém pra embarcar", errou as três
- Se perdeu em 2 dos 5 passos do fluxo
- Não sabia dizer o que 1 dos 6 ícones do topo fazia

Esse fluxo roda **2.394 vezes**.

## 1.7 Sem auditoria interna

`activity_logs` grava **um único tipo de evento** (`booking_updated`, 122
registros) e **só do fluxo de parceiro**. Nenhuma ação interna é registrada:
criar reserva, check-in, no-show, excluir, alterar preço, mudar configuração.

O componente `ActivityLogsViewer` **já existe**. A tabela **já existe**. Falta só
escrever nela.

## 1.8 Permissões que não fazem nada

Consumidas **zero vezes** fora de `usePermissions.ts` / `AdminPage.tsx`:

```
can_clear_locks · can_view_checklist · can_edit_checklist
```

Decisão do dono (21/08/2026): **remover da tela**, não implementar. Checklist
seria parte de mecânica, que ele não tem. Bloqueios são só dele ou do gerente —
que já é o comportamento.

---

# 2. O DESIGN SYSTEM — já definido, não reabrir

Aprovado. Chamado **"Luz da Mantiqueira"**. Derivado da fotografia da marca
(424 publicações: névoa na serra, fogueira, pôr do sol), não do logo.

## 2.1 Cor

```css
/* FUNDO — a neblina da manhã. Nunca branco puro. */
--paper:    #FAF7F1;   /* fundo geral            */
--paper-2:  #F3ECE1;   /* faixas e blocos        */
--paper-3:  #E9E0D2;   /* divisórias             */
--line:     #DED4C3;   /* bordas                 */

/* TINTA — a serra ao longe */
--ink:      #141F29;   /* títulos                */
--ink-2:    #3B4B59;   /* texto corrido          */
--ink-3:    #6D7D8B;   /* secundário             */
--ink-4:    #9CA8B2;   /* legendas               */

/* AÇÃO — o pôr do sol e a fogueira. SÓ onde se clica. */
--ember:      #DC5F16; /* botão principal        */
--ember-600:  #C24F13; /* pressionado            */
--ember-700:  #A03D08; /* texto em laranja       */
--ember-100:  #FBE7D7; /* destaque suave         */

/* APOIO — o azul da serra */
--mist:      #3E7391;  /* links                  */
--mist-700:  #2A5670;  /* links escuros          */
--mist-200:  #D4E2EB;  /* caixa de aviso         */

/* SITUAÇÃO — significam estado, nunca estética */
--ok:      #2F7D4F;  --ok-bg:      #E2F0E7;  --ok-line:      #B5D6C1;
--warn:    #B8791A;  --warn-bg:    #FBEFD8;  --warn-line:    #EBD5A6;
--danger:  #B33A2B;  --danger-bg:  #F9E3DF;  --danger-line:  #EDC1B9;
```

## 2.2 Tipografia

| Papel | Fonte | Pesos |
|---|---|---|
| Display (títulos, números grandes) | **Anton** | 400 (peso único) |
| Corpo, formulários, interface | **Figtree** | 400 · 500 · 600 · 700 · 800 |

Ambas gratuitas (Google Fonts). **Números e datas usam Figtree com
`font-variant-numeric: tabular-nums`** — nunca fonte monoespaçada, que é escolha
de programador e não de marca.

Escala:

```
Display grande .... 44–56px / line-height .94
Título de seção ... 25–30px
Corpo ............. 16px / line-height 1.6
Apoio ............. 13–14px
Legenda ........... 11–12px
```

## 2.3 Espaçamento

Escala fixa: **4 · 8 · 12 · 16 · 24 · 32 · 48 · 64**. Nada fora dela.

Raio de canto: **3px** (elementos pequenos), **6–7px** (cards), **999px** (pílulas).

## 2.4 Regras invioláveis

1. **A foto é a estrela.** Interface clara e neutra; nada compete com a fotografia.
2. **Âmbar só para ação.** Botão principal, item selecionado, valor a pagar. Se
   aparecer em tudo, deixa de indicar qualquer coisa.
3. **Cor = situação da pessoa. Dinheiro = selo.** A cor do card diz onde a pessoa
   está (reservado / esperando / embarcou / faltou). O que ela deve aparece como
   etiqueta no canto.
4. **Nada de branco puro** (`#ffffff`) como fundo de página.
5. **Uma fonte de verdade.** Toda cor sai de um token. Nenhum hex solto no código.
6. **Botão sem rótulo não existe.** Ícone sozinho só quando o significado é
   universal (fechar, voltar).

## 2.5 Logo

```
company_logo_url = https://zpmlmjxlbrksanpycpyv.supabase.co/storage/v1/object/public/company-assets/logos/company_logo.png
app_icon_url     = https://zpmlmjxlbrksanpycpyv.supabase.co/storage/v1/object/public/company-assets/logos/app_icon.png
```

O logo é **selo**, não paleta. As cores dele (ciano, magenta, amarelo) não viram
cor de interface.

---

# 3. ESCOPO — as telas

| # | Tela | Arquivo | Prioridade | Por quê |
|---|---|---|---|---|
| 1 | Agenda (painel) | `App.tsx` | **P0** | 98% do negócio passa aqui |
| 2 | Modal de reserva | `App.tsx` (~5490–7060) | **P0** | ~15 cliques, roda 2.394× |
| 3 | Configurações | `App.tsx` (~4940) + `AdminPage.tsx` | **P0** | duas navegações empilhadas |
| 4 | Voucher (3 formatos) | `VoucherImage/PDF/texto` | **P1** | é o que o cliente recebe |
| 5 | Portal do parceiro | `PartnerPortal.tsx` | **P1** | 2% do faturamento, mas é dinheiro |
| 6 | Página pública | `PublicBookingPage.tsx` | **P1** | canal zerado = oportunidade |
| 7 | Login | `App.tsx` | **P2** | primeira impressão |
| 8 | Check-in | `CheckInPage.tsx` | **P2** | usado no campo |
| 9 | Super Admin | `SuperAdminPage.tsx` | **fora** | não é do cliente |

---

# 4. FASES DE EXECUÇÃO

> Cada fase é uma branch, com verificação própria. **Nenhuma fase começa antes da
> anterior estar verificada.**

## FASE 0 — Fonte única de tokens
**Branch:** `feat/ds-tokens`

Criar `src/styles/tokens.css` com todas as variáveis da seção 2.1, e
`src/styles/typography.css` com as fontes e a escala.

- Fontes carregadas via `<link>` no `index.html` (Google Fonts)
- Tokens aplicados em `:root`
- **Nenhum componente alterado nesta fase.** Só os arquivos passam a existir e
  ser importados.

**Verificação:** `npm run typecheck` = 150 · `npm run build` passa · app
visualmente idêntico.

**Entregável:** os dois arquivos + import no `main.tsx`.

---

## FASE 1 — Varredura de cor: hex solto → token
**Branch:** `feat/ds-aplica-tokens`

Trocar **todo** hex literal do `src/` pelo token correspondente. São centenas.

- Mapear cada hex existente para o token mais próximo (tabela de-para no PR)
- `#2563eb`, `#1e40af`, `#0284c7`, `#3b82f6` → `--mist` / `--ink` conforme papel
- `#059669`, `#308232` → `--ok`
- Verdes/vermelhos/âmbares de estado → tokens de situação
- **Se um hex não tiver token equivalente, PARE e reporte** — não invente cor

**Regra crítica:** as cores gravadas em `company_settings` /
`public_booking_branding` continuam sendo lidas normalmente. Esta fase troca os
**defaults do código**, não os valores do banco. Atualizar o banco é a Fase 6.

**Verificação:** typecheck 150 · build · **captura antes/depois de 8 telas**
(agenda, modal, configurações, voucher, parceiro, pública, login, check-in).

---

## FASE 2 — Matar a navegação duplicada
**Branch:** `feat/nav-unificada`

O modal de Configurações do `App.tsx` **deixa de existir**. Tudo vira `AdminPage`.

Nova estrutura (5 grupos, cada item em um lugar só):

```
OPERAÇÃO      Agenda · Horários · Veículos e valores · Manutenção · Experiência
COMERCIAL     Parceiros · CRM · Promoções e vouchers
MARCA         Identidade · Voucher · Página pública
DOCUMENTOS    Termo de riscos
SISTEMA       Usuários · Backup · Monitoramento · Avisos
```

Mudanças concretas:
- "Manutenção" deixa de ser aba e vira seção dentro de **Veículos**
- "Aparência" + "Visual" fundem em **Identidade**
- **`whatsapp_url` e `location_url` passam a ter UM editor** (em Identidade).
  Os outros 3 somem da tela — a chave no banco continua a mesma
- "Experiência" ganha nome que diz o que é (hoje o rótulo da aba vem do primeiro
  campo de texto da própria tela, e só no caminho do modal)

**Risco:** `useConfig.configToUpsertRows` grava 12 chaves de uma vez. Ao remover
editores, garantir que a tela remanescente **não regrave as outras 11 com valor
velho**. Isso já foi parcialmente endurecido na branch `feat/fix-rotulo-atividade`.

**Verificação:** typecheck 150 · build · **teste manual obrigatório**: editar
WhatsApp em Identidade e confirmar no banco que `location_url`, `voucher_title`,
`voucher_footer` e `vehicle_label` **não mudaram**.

---

## FASE 3 — Hierarquia do painel
**Branch:** `feat/painel-hierarquia`

Duas propostas foram apresentadas ao dono. **Executar a que ele aprovar.**

**Proposta 1 — "Organizar a casa"** (mais conservadora)
- Os 7 cartões continuam onde estão
- Dois ganham cor de atenção: "Aguardando embarque" (âmbar) e "Falta receber"
  (âmbar-100)
- Os 6 ícones do topo ganham rótulo em texto
- Calendário próprio substitui o `<input type="date">` nativo

**Proposta 2 — "Reorganizar de verdade"** (mais agressiva)
- 2 números grandes (esperando embarque · falta receber) + 4 pequenos
- Ação dentro do card: "Confirmar embarque" sem abrir a reserva
- Cor do card = situação da pessoa; dinheiro vira etiqueta no canto
- Vaga livre diz "Toque para reservar" em vez de ícone cinza

**Comum às duas:**
- Calendário próprio, marcando com ponto os dias que têm reserva
- Botões com rótulo
- Paleta e tipografia novas

**Verificação:** typecheck 150 · build · **refazer o teste de 10 segundos** com
alguém que não construiu a tela. Meta: **3 de 3**.

---

## FASE 4 — Modal de reserva: menos cliques, menos rolagem
**Branch:** `feat/modal-reserva`

Problemas medidos:
- Modal com ~1.100px de largura e **todo campo ocupando linha inteira** — metade
  da tela vazia à direita, forçando rolagem que não precisava existir
- Depois do check-in aparecem **10 botões empilhados**, todos do mesmo tamanho:
  Salvar · Excluir · Desfazer Check-in · Não Apto · Transferir · WhatsApp ·
  Texto · PDF · Documentos · Imprimir Térmica
- "Excluir" (destrutivo, raro) tem o mesmo peso visual que "WhatsApp" (o mais usado)
- Bloco de upsell ocupa espaço enorme com 4 linhas de cobertura de seguro em
  letra miúda, para uma decisão de 1 clique

Fazer:
- Agrupar campos em 2 colunas onde faz sentido (nome + telefone lado a lado)
- Hierarquia nos botões: **1 primário** (Salvar), **2–3 secundários**, o resto
  agrupado em "Mais ações"
- Destrutivo (Excluir) separado visualmente e por último
- Upsell compacto: nome + preço + 3 botões. Detalhe da cobertura em "ver mais"

**REGRA DE DINHEIRO INVIOLÁVEL:** não alterar **nenhum** cálculo. Nada de
`total_value`, `paid_value`, comissão, `seats_blocked`, `pricing_mode`. Só
posição e tamanho. Este projeto já teve a fórmula de comissão de parceiro
invertida **3 vezes**.

**Verificação:** typecheck 150 · build · **recontar os cliques** do fluxo
(criar → pagar → check-in → voucher → excluir). Meta: **de ~15 para ≤10**.

---

## FASE 5 — Limpeza
**Branch:** `feat/limpeza`

1. **Remover da tela** as 3 permissões mortas (`can_clear_locks`,
   `can_view_checklist`, `can_edit_checklist`). **Não** remover colunas do banco,
   **não** escrever migration. Deixar comentário em `usePermissions.ts`
   explicando a decisão e a data, para ninguém "reativar" achando esquecimento.
2. **Decidir com o dono** o destino de: aba Experiência (0 registros), CRM
   oportunidades (0 registros). Recolher ou remover.
3. `App.tsx:7266` — `qtdQuadri = ativos.length - qtdJeep` assume "tudo que não é
   jeep é quadriciclo". Com uma 3ª atividade o contador fica errado em silêncio.
   **Corrigir para contar diretamente.**
4. `useMachineConfigs.ts:38` normaliza silenciosamente qualquer `vehicle_type`
   desconhecido para `'quadriciclo'` ao ler do banco. **Trocar por erro explícito
   ou log** — é o ponto mais cedo onde uma 3ª atividade seria mascarada.

---

## FASE 6 — Sincronizar o banco com o design system
**Branch:** `feat/ds-banco` · **NÃO EXECUTAR SEM APROVAÇÃO**

As cores do Marius no `company_settings` ainda são as antigas. Gerar o SQL que
atualiza para a paleta nova.

- **Só gerar o arquivo. Não executar.** O dono roda no SQL Editor.
- Incluir SELECT de conferência antes e depois
- Incluir o SQL de reversão

⚠️ **A pasta `supabase/migrations/` NÃO reflete o banco real.** O projeto nasceu
no Bolt e várias mudanças foram aplicadas direto no dashboard. Divergência já
confirmada (`bookings_insert`). **Ler sempre de `pg_policies` / do banco, nunca
deduzir de migration.**

---

# 5. REGRAS DE EXECUÇÃO

## 5.1 Verificação — obrigatória em toda fase

```bash
npm run typecheck    # tsc --noEmit -p tsconfig.app.json
npm run build
```

- **Baseline: exatamente 150 erros TS6133 pré-existentes.** Nenhum a mais.
- ⚠️ **NÃO usar `npx tsc --noEmit` sozinho.** O `tsconfig.json` da raiz é
  "solution style" (`files: []`, só `references`) e **checa ZERO arquivos** —
  passa sempre, mesmo com o código quebrado. Já enganou uma sessão inteira.

## 5.2 Git

- **Uma branch por fase.** Nunca commitar em `main`.
- **Commits pequenos e separados**, um por unidade lógica.
- **Não fazer merge, push nem deploy sem autorização explícita.**
- `main` é produção. É sagrado.

## 5.3 Dinheiro

Nenhuma fase deste plano altera cálculo financeiro. Se a execução exigir tocar
em `total_value`, `paid_value`, comissão, `seats_blocked` ou `pricing_mode` —
**PARE e reporte**. Não decida sozinho.

Histórico: a fórmula de comissão de parceiro foi invertida **3 vezes** neste
projeto.

## 5.4 Leitura de configuração

Regra crítica, já causou bug em produção:

```js
if (chave in settings)     // ✅ presença
if (settings[chave])       // ❌ truthiness — string vazia é valor válido
```

String vazia gravada de propósito **é um valor**. Ex: apagar o texto do voucher
do jeep para não herdar o do quadriciclo.

## 5.5 Antes/depois

Toda fase que muda visual entrega **captura de tela antes e depois** das telas
afetadas. Sem isso não há como provar que nada regrediu.

---

# 6. RISCOS CONHECIDOS

| Risco | Onde | Mitigação |
|---|---|---|
| Gravar 12 chaves de uma vez | `useConfig.ts:89` | Testar no banco após cada save |
| Migrations ≠ banco real | `supabase/migrations/` | Ler sempre de `pg_policies` |
| Cor vinda do banco sobrepõe token | 4 tabelas de branding | Fase 6, com aprovação |
| Fórmula de comissão | `PartnersAdmin` / `partner-booking` | Não tocar |
| PWA serve bundle velho | service worker | Fechar o app por completo ao testar |
| `publicDir` é `public3` | `vite.config.ts` | Não é `public` |
| Dois chats na mesma pasta | working tree compartilhada | Commitar antes de trocar de branch |

---

# 7. BRANCHES EXISTENTES — resolver antes de começar

```
main .............................. produção (a42300a)
feat/totem-quiosque ............... 6 commits  · totem, não testado
feat/multiatividade-fundacao ...... 10 commits · fundação multiatividade
feat/fix-rotulo-atividade ......... 15 commits · toggle jeep (inclui a fundação)
feat/partner-jeep-assentos ........ 17 commits · NÃO REVISADO
fix/voucher-imagem ................ alterações NÃO COMMITADAS
feat/inventario-configuracoes ..... INVENTARIO-CONFIGURACOES.md não commitado
```

⚠️ **Dois arquivos importantes estão soltos, sem commit.** Um `git checkout`
apaga. **Salvar antes de qualquer coisa.**

---

# 8. ORDEM RECOMENDADA

```
0. Salvar o que está solto (voucher + inventário)
1. FASE 0 — tokens
2. FASE 1 — varredura de cor
3. FASE 2 — navegação unificada
4. FASE 3 — hierarquia do painel  (depende da escolha do dono: proposta 1 ou 2)
5. FASE 4 — modal de reserva
6. FASE 5 — limpeza
7. FASE 6 — banco  (só com aprovação, só gerar SQL)
```

**Fases 0 e 1 podem rodar juntas.** As demais são sequenciais.

---

# 9. DEFINIÇÃO DE PRONTO

O trabalho está completo quando:

- [ ] Nenhum hex literal no `src/` — tudo vem de token
- [ ] Uma navegação só; nenhum item em dois caminhos
- [ ] `whatsapp_url` e `location_url` com **um** editor cada
- [ ] Teste de 10 segundos: **3 de 3** com alguém que não construiu a tela
- [ ] Fluxo principal: **≤10 cliques**
- [ ] `npm run typecheck` = **150** · `npm run build` passa
- [ ] Captura antes/depois de todas as telas alteradas
- [ ] Zero alteração em cálculo de dinheiro
- [ ] Nada mergeado em `main` sem aprovação

---

*Tolissano · agosto de 2026 · v1*
