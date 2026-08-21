# MAPA DA INFRAESTRUTURA — QuadriBook / Trip Experience

> Levantado em 21/08/2026 lendo os repositórios e o banco. Isto é o que existe
> de fato, não o que se imagina que existe.

---

## 1. PASTAS NO SEU COMPUTADOR

### ✅ `Desktop\quadribook-live` — **é esta que vale**

```
GitHub ....... github.com/TripMV/Agenda_Trip_Backup   (conta do Marius)
Branch ....... feat/ds-fundacao
Último ....... a42300a  Merge feat/fix-permissoes-operador
Não salvo .... 14 arquivos
.env aponta .. xivykzcixgrsfvizyiyk.supabase.co   ⚠️ NÃO é a produção
```

É a única ligada ao GitHub. Todo trabalho deve acontecer aqui.

### ⚠️ `Desktop\Agenda_Trip_Backup-main` — **cópia órfã**

```
GitHub ....... NENHUM. Sem remote.
Branch ....... fix/quick-wins
Último ....... ff52a69  fix(realtime): publica bookings em supabase_realtime
Não salvo .... 12 arquivos
```

**Não está ligada a lugar nenhum.** O nome com `-main` no fim é o padrão de ZIP
baixado do GitHub — provavelmente veio daí e foi trabalhada localmente.

Tem **11 documentos de julho que existem só aí**:

```
RELATORIO-2026-07-14.md          PLANO-ATAQUE-JEEP-UPSELL.md
RELATORIO-CLIENTE-2026-07-14.md  PLANO-ATAQUE-POS-RECON.md
RELATORIO-CLIENTE-2026-07-15.md  PROMPT-SONNET-FECHAR-JEEP.md
RELATORIO-CLIENTE-2026-07-19.md  PROPOSTA-PARCERIA-SAAS.md
FIX-J1-J2-P0.md                  diagnostico-supabase.sql
STAGING-JEEP-migrations.sql
```

Se essa pasta for apagada, **some tudo**. Inclusive a proposta de parceria SaaS.

### 📁 `Desktop\PREVIEW-TRIPMV` — apresentações

```
GitHub ....... github.com/enzot-byte/tripmv-preview   (sua conta)
Publica em ... enzot-byte.github.io/tripmv-preview
```

Brandbook, propostas de painel, planos. Push publica sozinho.

---

## 2. GITHUB

| Repositório | Dono | Para quê |
|---|---|---|
| `TripMV/Agenda_Trip_Backup` | Marius | **O produto.** Push no `main` publica em produção |
| `enzot-byte/tripmv-preview` | Você | Apresentações e planos |

---

## 3. SUPABASE — dois bancos

### 🟢 `zpmlmjxlbrksanpycpyv` — **PRODUÇÃO**

```
Nome ......... bolt-native-database-63449481
Organização .. marius@tripexperience.com.br's Org   (plano Free)
Branch ....... main (PRODUCTION)
Contém ....... 2.394 reservas · R$ 619.634,94 · 19 usuários
```

**É o banco real do Marius.** Tudo que a operação usa está aqui.

### 🔴 `xivykzcixgrsfvizyiyk` — **o que o `.env` local aponta**

Não é a produção. Quando você roda `npm run dev`, bate **neste**. Foi por isso
que o totem abriu preto: o tenant não existe lá.

**Não sabemos o que tem dentro.** Precisa ser verificado e então: virar staging
de verdade, ou ser apagado.

⚠️ **O `.env` de produção não fica no repositório.** Quem tem as variáveis reais é
o Netlify. Por isso `npm run dev` local ≠ site no ar.

---

## 4. NETLIFY

```
Time ......... TripMV's team    ← NÃO é o "EnzoTTolissano"
Projeto ...... quadribook.com.br
Deploy ....... automático, do GitHub
```

Você tem acesso (o Marius assinou o Pro pra convidar). Fica no **seletor de time**
no canto superior esquerdo — o time pessoal `enzot` está vazio.

---

## 5. DOMÍNIOS

| Domínio | Serve |
|---|---|
| `quadribook.com.br` | Painel interno, login, portal do parceiro |
| `tripexperience.com.br` | Site público e página de reserva |

Rotas: `/admin` · `/reservar` · `/parceiro/:token` · `/totem` *(ainda não publicado)*

---

## 6. COMO O CÓDIGO CHEGA NA PRODUÇÃO

```
código na branch
      ↓  merge no main
      ↓  git push origin main
GitHub TripMV/Agenda_Trip_Backup
      ↓  gatilho automático
Netlify (time do Marius) faz o build
      ↓
quadribook.com.br no ar
```

**Ninguém precisa entrar no Netlify pra publicar.** Push no `main` = está no ar.

⚠️ **Edge function é exceção.** Mudança em `supabase/functions/` **não** sobe pelo
GitHub. Precisa de `supabase functions deploy <nome>`.

---

## 7. ⚠️ RISCO IMEDIATO — trabalho não salvo

### Em `quadribook-live` (14 arquivos)

| O quê | Arquivos | Pertence a |
|---|---|---|
| Fundação do design system | `src/styles/` `src/design/` `public3/fonts/` `scripts/` `index.html` `package.json` `main.tsx` | `feat/ds-fundacao` (**0 commits**) |
| Conserto do voucher | `src/VoucherImage.tsx` `src/VoucherImageWrapper.tsx` | `fix/voucher-imagem` |
| Inventário de 779 campos | `INVENTARIO-CONFIGURACOES.md` | `feat/inventario-configuracoes` |
| Apresentações | `brandbook-*.html` `redesign-*.html` | já copiados pro repo de preview |

**Três trabalhos diferentes misturados na mesma árvore, nenhum commitado.**
A branch `feat/ds-fundacao` está com **zero commits** — a fundação inteira que o
Fable produziu está solta.

### Em `Agenda_Trip_Backup-main` (12 arquivos)

Os 11 documentos de julho. **Sem GitHub. Sem backup.**

---

## 8. O QUE FAZER — proposta

**1. Salvar o que está solto, cada coisa na sua branch**
Separar os três trabalhos e commitar cada um onde pertence. **Nada vai pra
produção** — só para de correr risco.

**2. Resolver a pasta órfã**
Levar os 11 documentos para o repositório certo (ou para o de preview) e então
apagar a pasta duplicada. Ter duas cópias do mesmo projeto no Desktop é o que
gera confusão.

**3. Decidir o `xivykzcixgrsfvizyiyk`**
Verificar o que tem dentro. Vira staging de verdade ou é apagado. Do jeito que
está, só engana quem roda local.

**4. Padronizar as branches**
Existem ~50, e ~40 já estão no `main`. Apagar as mortas.

---

## 9. NÚMEROS DE REFERÊNCIA

| | |
|---|---|
| Faturamento (Trip Experience) | R$ 619.634,94 · 2.394 reservas |
| Canais | Balcão 98,1% · Parceiro 1,9% · Site 0% |
| Usuários no tenant | 19 |
| Contrato em andamento | R$ 4.200 (totem + LP + pinpad) |
| Pago | R$ 500 (13/08) · R$ 500/semana |
| Quitação prevista | ~08/10/2026 |

---

*Levantado por Tolissano · 21/08/2026*
