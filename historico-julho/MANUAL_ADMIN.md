# Manual do Administrador - Sistema de Reservas

## Primeiro Acesso

### Credenciais Padrão
- **Usuário:** `admin`
- **Senha:** `admin123`

Use estas credenciais para fazer o primeiro login no sistema.

---

## Painel de Administração

Após fazer login como administrador, você terá acesso ao painel administrativo através do botão de **Configurações** (ícone de engrenagem).

### Como Acessar
1. Faça login no sistema
2. Clique no ícone de **Configurações** no canto superior direito
3. O painel possui duas abas principais:
   - **Valor das Máquinas**
   - **Gerenciar Usuários**

---

## Gerenciar Usuários

### Criar Novo Usuário

1. Acesse a aba **"Gerenciar Usuários"**
2. Clique no botão **"Novo Usuário"** (canto superior direito)
3. Preencha os dados:
   - **Nome Completo:** Nome real do usuário (Ex: João Silva)
   - **Nome de Usuário:** Login do usuário (Ex: joao.silva)
   - **Função:** Selecione o nível de acesso
   - **Permissões de Checklist:** Marque as permissões necessárias

4. Clique em **"Salvar Usuário"**

### Senha Automática

Quando você cria um novo usuário, o sistema:
- ✅ Gera uma **senha aleatória segura** de 8 caracteres
- ✅ Exibe a senha em um modal especial
- ⚠️ **ATENÇÃO:** A senha só é mostrada uma vez!

**Importante:**
- Copie a senha imediatamente (botão de copiar disponível)
- Anote a senha antes de fechar o modal
- Entregue a senha ao novo usuário de forma segura

### Níveis de Acesso (Funções)

#### 1. **Operador** (operator)
- Acesso básico ao sistema
- Pode criar e gerenciar reservas
- Registra o nome em cada operação

#### 2. **Manutenção** (maintenance)
- Acesso de operador
- Pode bloquear/desbloquear máquinas para manutenção
- Gerencia alertas de manutenção

#### 3. **Gerente** (manager)
- Todos os acessos de operador e manutenção
- Pode gerar relatórios financeiros
- Pode exportar dados
- Visualiza estatísticas operacionais

#### 4. **Administrador** (admin)
- **Acesso total ao sistema**
- Pode criar/editar/excluir usuários
- Pode alterar configurações globais
- Pode definir valores de máquinas
- Acessa painel administrativo
- Visualiza logs de atividades

---

## Visualizar Senhas de Usuários

Todos os usuários cadastrados aparecem na lista com suas informações:
- Nome completo
- Nome de usuário (login)
- **Senha visível** (para consulta do admin)
- Função/nível de acesso
- Permissões de checklist
- Status (ativo/inativo)

**Nota:** As senhas ficam sempre visíveis para o administrador no painel, permitindo recuperação caso o usuário esqueça.

---

## Editar Usuário

1. Na lista de usuários, clique no botão **editar** (ícone de lápis)
2. Você pode alterar:
   - Nome do usuário
   - Função/nível de acesso
   - Permissões de checklist
   - Status (ativar/desativar)
3. Clique em **"Salvar"** para confirmar

**Nota:** O nome de usuário (login) não pode ser alterado. A senha também não pode ser mudada - se necessário, exclua e crie um novo usuário.

---

## Desativar Usuário

Para desativar um usuário sem excluí-lo:
1. Clique em **editar** no usuário
2. Desmarque a opção de status ativo
3. Salve as alterações

Usuários inativos:
- ❌ Não conseguem fazer login
- ✅ Seus dados históricos são preservados
- ✅ Podem ser reativados a qualquer momento

---

## Excluir Usuário

1. Clique no botão **excluir** (ícone de lixeira)
2. Confirme a exclusão

⚠️ **ATENÇÃO:** Esta ação é permanente e não pode ser desfeita!

---

## Permissões de Checklist

Ao criar ou editar usuários, você pode configurar:

### Pode Visualizar Checklist
- Permite que o usuário veja checklists de manutenção
- Útil para supervisores que precisam acompanhar

### Pode Editar Checklist
- Permite criar, modificar e completar checklists
- Geralmente para equipe de manutenção

---

## Configurar Valor das Máquinas

Na aba **"Valor das Máquinas"**:

1. Digite o valor sugerido (em reais)
2. Clique em **"Salvar Alterações"**

Este valor será:
- ✅ Aplicado a todas as máquinas (Q1 até Q8)
- ✅ Sugerido automaticamente ao criar reservas
- ✅ Usado como padrão no sistema

---

## Boas Práticas

### Segurança
- ✅ Altere a senha padrão do admin após primeiro acesso
- ✅ Crie usuários individuais para cada pessoa
- ✅ Não compartilhe senhas entre usuários
- ✅ Desative usuários que não trabalham mais na empresa

### Organização
- ✅ Use nomes de usuário padronizados (ex: nome.sobrenome)
- ✅ Atribua funções adequadas a cada usuário
- ✅ Mantenha a lista de usuários atualizada
- ✅ Anote as senhas geradas em local seguro

### Permissões
- ✅ Dê apenas as permissões necessárias
- ✅ Promova usuários conforme necessário
- ✅ Revise periodicamente os níveis de acesso

---

## Hierarquia de Permissões

```
Administrador (acesso total)
    ↓
Gerente (relatórios + operações)
    ↓
Manutenção (bloqueios + operações)
    ↓
Operador (operações básicas)
```

---

## Suporte

Em caso de dúvidas ou problemas:
1. Verifique este manual
2. Entre em contato com o suporte técnico
3. Mantenha backup das senhas importantes

---

**Última atualização:** Março 2026
