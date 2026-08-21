# 🎯 Guia de Configuração - Sistema de Usuários

## Etapa 1: Acessar com o Admin Padrão

1. Abra o sistema
2. Na tela de login, clique em **"Admin"**
3. Você agora está logado como administrador do sistema

---

## Etapa 2: Acessar o Gerenciamento de Usuários

1. Clique no ícone de **engrenagem (Settings)** no topo
2. No menu, clique em **"Configurar Máquinas"** (ícone de ferramenta)
3. Você verá 2 abas: **"Valores das Máquinas"** e **"Gerenciar Usuários"**
4. Clique na aba **"Gerenciar Usuários"**

---

## Etapa 3: Criar Seus Primeiros Usuários

### **Exemplo: Criar um Gerente**

1. Clique no botão **"+ Novo Usuário"**
2. Preencha:
   - **Nome:** Maria Silva
   - **Função:** Gerente
3. Clique em **"Salvar"**
4. O usuário "Maria Silva" aparecerá na lista

### **Exemplo: Criar um Operador**

1. Clique no botão **"+ Novo Usuário"** novamente
2. Preencha:
   - **Nome:** João Santos
   - **Função:** Operador
3. Clique em **"Salvar"**
4. O usuário "João Santos" aparecerá na lista

**💡 Dica:** Crie todos os usuários que você precisa (gerentes do turno da manhã, tarde, noite, operadores, etc.)

---

## Etapa 4: Configurar Permissões Personalizadas

### **Para cada usuário criado:**

1. Localize o usuário na lista
2. Clique no botão **"Permissões"** (azul)
3. Você verá checkboxes com todas as permissões disponíveis

### **Exemplo: Configurar Gerente de Turno**

✅ Marque:
- Ver estatísticas operacionais
- Ver valores financeiros
- Exportar relatórios
- Bloquear/Desbloquear reservas
- Marcar NO-SHOW
- Transferir máquinas
- Ver logs de atividades
- Criar novas reservas
- Editar reservas existentes
- Confirmar check-in
- Adicionar observações
- Editar nome do cliente

❌ Deixe DESMARCADO:
- Alterar valores de máquinas (só Admin)
- Deletar reservas (só Admin)
- Gerenciar usuários (só Admin)

### **Exemplo: Configurar Operador Básico**

✅ Marque apenas:
- Confirmar check-in
- Adicionar observações
- Transferir máquinas (se necessário)

❌ Deixe DESMARCADO tudo relacionado a:
- Valores financeiros
- Estatísticas
- Edição de reservas
- Deletar

**💡 Dica:** Você pode customizar as permissões conforme a confiança/necessidade de cada pessoa

---

## Etapa 5: Testar e Ajustar

### **Teste com cada perfil:**

1. Clique em **"Sair"** (ícone de usuário vermelho no topo)
2. Na tela de login, escolha um usuário diferente (ex: "João Santos - Operador")
3. Observe que:
   - Botões aparecem/desaparecem conforme as permissões
   - Operador não vê valores financeiros
   - Gerente vê relatórios e estatísticas
   - Admin vê tudo

### **Ajuste conforme necessário:**

1. Volte para o Admin
2. Acesse "Gerenciar Usuários" novamente
3. Clique em "Permissões" do usuário que quer ajustar
4. Marque/Desmarque conforme necessário

---

## 📋 Resumo de Permissões por Função

### 🔴 **ADMINISTRADOR (Admin)**
- ✅ TODAS as permissões
- ✅ Gerenciar usuários
- ✅ Alterar valores de máquinas
- ✅ Deletar reservas

### 🟡 **GERENTE (Personalizável)**
- ✅ Ver tudo exceto gerenciar usuários
- ✅ Exportar relatórios
- ✅ Marcar NO-SHOW
- ✅ Ver logs e estatísticas
- ❌ Não pode deletar
- ❌ Não pode gerenciar usuários
- ❌ Não pode alterar valores das máquinas

### ⚪ **OPERADOR (Personalizável)**
- ✅ Check-in
- ✅ Adicionar observações
- ✅ Transferir máquinas (opcional)
- ❌ Não vê valores financeiros
- ❌ Não pode criar/editar reservas
- ❌ Não vê estatísticas

---

## 🔧 Operações Comuns

### **Desativar um usuário (férias, saída):**
1. Localize o usuário
2. Clique em **"Desativar"**
3. O usuário some da tela de login (mas não é deletado)

### **Reativar um usuário:**
1. Usuários inativos aparecem com fundo cinza
2. Clique em **"Ativar"**
3. O usuário volta para a tela de login

### **Deletar um usuário:**
1. Clique no ícone de **lixeira (vermelho)**
2. Confirme a exclusão
3. ⚠️ **Esta ação não pode ser desfeita!**

---

## ❓ Perguntas Frequentes

**P: Posso ter vários gerentes com permissões diferentes?**
R: Sim! Crie "Gerente Noturno" e "Gerente Diurno" com permissões customizadas.

**P: Como faço para um operador virar gerente?**
R: Acesse como Admin > Gerenciar Usuários > Permissões > Marque as permissões de gerente.

**P: O que acontece se eu desativar todos os admins?**
R: Sempre existe o usuário "Admin" padrão que não pode ser deletado.

**P: Posso mudar a senha do sistema?**
R: As senhas antigas (2597, 1234) não são mais necessárias. O login é feito por seleção de usuário.

**P: Como faço backup dos usuários?**
R: Os usuários ficam salvos no banco de dados Supabase automaticamente.

---

## ✅ Checklist Final

- [ ] Criei o Admin padrão está funcionando
- [ ] Criei todos os gerentes necessários
- [ ] Criei todos os operadores necessários
- [ ] Configurei as permissões de cada gerente
- [ ] Configurei as permissões de cada operador
- [ ] Testei login com cada tipo de usuário
- [ ] Verifiquei que os botões aparecem/desaparecem corretamente
- [ ] Todos os usuários sabem como fazer login

---

**🎉 Pronto! Seu sistema está configurado para múltiplos usuários com permissões personalizadas!**
