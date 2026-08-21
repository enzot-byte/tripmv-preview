# 🎨 Como Gerar os Ícones do App para iOS

Os ícones PWA são necessários para que seu app apareça com uma imagem bonita quando adicionado à tela inicial do iPhone.

## Passo a Passo

1. **Abra o gerador de ícones**
   - No navegador, vá para: `http://localhost:5173/generate-icons.html`
   - Ou se já estiver em produção: `https://seu-dominio.com/generate-icons.html`

2. **Gere e baixe os ícones**
   - Clique em "📥 Baixar logo180.png" (este é o mais importante para iOS!)
   - Clique em "📥 Baixar logo192.png"
   - Clique em "📥 Baixar logo512.png"

3. **Substitua os arquivos**
   - Coloque os 3 arquivos baixados na pasta `public/`
   - Substitua os arquivos existentes

4. **Reconstrua o projeto**
   ```bash
   npm run build
   ```

5. **Faça deploy novamente**
   - Após o build, faça deploy da pasta `dist/` para seu servidor

## Testando no iPhone

1. Abra o Safari no iPhone e vá para seu site
2. Toque no botão de compartilhar (quadrado com seta para cima)
3. Role para baixo e toque em "Adicionar à Tela de Início"
4. O ícone do quadriciclo deve aparecer corretamente!

## Arquivos Importantes

- `logo180.png` - Ícone principal do iOS (180x180px)
- `logo192.png` - Ícone Android padrão (192x192px)
- `logo512.png` - Ícone grande para splash screens (512x512px)
- `icon.svg` - Ícone vetorial (usado no navegador)

## Tamanhos Corretos

- **180x180px** - Apple Touch Icon (iOS padrão)
- **192x192px** - Android Chrome
- **512x512px** - Splash screens e lojas de apps

---

**Dica:** O iOS sempre usa o ícone de 180x180px por padrão. Certifique-se de que este arquivo está correto!
