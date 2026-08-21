# Relatório — QuadriBook / Trip MV (19/07)

Marius, resumo direto do que entregamos e do que a nossa auditoria encontrou.

---

## ✅ Entregue e testado

1. **Agenda em tempo real** — quando um operador faz/muda uma reserva, os outros veem **na hora**, sem recarregar. (já no ar)
2. **JEEP (veículo compartilhado)** — um veículo agora pode receber **vários passageiros no mesmo horário** até lotar os lugares. Cada veículo pode ser configurado como:
   - **Individual** (quadriciclo, como sempre), ou
   - **Compartilhado** (jeep de N lugares).
   - E o **preço do jeep** você escolhe: **fechado** (preço do veículo) ou **por cabeça** (multiplica pelo nº de passageiros). **Testado**: entra passageiro, mostra a lotação (ex: 2/3), **trava quando lota**, e o preço multiplica certo.
3. **6 correções de bugs** já aplicadas (relatório de comissão, cobrança de combo, upsell no total, ações de grupo, etc.).
4. **Tela de configuração mais fluida** (tiramos um travamento ao digitar).

---

## 🔎 O que a auditoria encontrou (10 problemas sérios)

Fizemos uma varredura a fundo. Achamos **10 problemas reais** — priorizei por impacto pra você. **Nada disso é novo/nosso — já estava no sistema.**

### 🔴 CRÍTICO — dinheiro
**1. Comissão de parceiro pode estar invertida.**
No cadastro você define "Empresa recebe R$X", mas o sistema pode estar **creditando esse valor como comissão do parceiro** e não pra empresa. Se for isso, em ~100 reservas/mês a empresa pode estar **pagando milhares de reais a mais** aos parceiros.
👉 **Preciso que você me confirme o certo:** numa reserva de parceiro de R$150 onde "empresa recebe R$120", **quanto fica pro parceiro e quanto pra Trip?** Com isso eu alinho tudo (cadastro, portal do parceiro e relatórios) de uma vez.

### 🟠 IMPORTANTE — dinheiro
**2. Pagamento dividido "por grupos" não soma no total pago** → o comprovante mostra "Pago R$0 / Saldo total" mesmo já tendo recebido, e o **caixa do dia não enxerga esse dinheiro**.
**3. Comprovante de reserva de parceiro mostra "saldo a pagar"** do valor cheio → o operador pode **cobrar de novo** um cliente que já pagou ao parceiro.
**4. Salvar uma reserva com a tela aberta há um tempo apaga o pagamento** que outro operador registrou nesse meio-tempo → dinheiro some do sistema.
**5. Voucher do parceiro chama o valor da empresa de "parceiro recebe"** → confusão no acerto com o parceiro.

### 🟠 IMPORTANTE — reserva / operação
**6. Botão "Reverter — Cliente Apto para Pilotar" APAGA a reserva** (com o pagamento) em vez de só liberar o cliente. Ela some pra sempre.
**7. Ações (check-in, no-show, não-apto) podem afetar a reserva ERRADA** quando dois clientes têm o mesmo nome no mesmo horário.
**8. Público/parceiro pode ver "vaga disponível" que não existe** em dias que você aumenta a capacidade acima do nº de veículos → cliente preenche e dá erro.

### 🟡 MENOR — contagem do dia
**9. Desfazer check-in** não zera o "embarcado" → o painel do dia conta a mais.
**10. Desfazer no-show** pode rebaixar um cliente que já tinha feito check-in.

---

## 📋 Recomendação (próximos passos)

1. **Você me confirma o split da comissão de parceiro** (a pergunta lá em cima) — é a única coisa que depende de você.
2. Com isso, a gente **corrige o crítico + os de dinheiro primeiro**, depois os de operação. Tudo testado antes de subir, como fizemos com o jeep.
3. **Publicar o jeep + correções** no site (falta só acertar como a gente publica — te explico à parte).

**Resumo:** o jeep está pronto e testado, e de brinde a auditoria já te mapeou onde o sistema estava **perdendo/errando dinheiro**. É só decidir a ordem e a gente executa. 👊
