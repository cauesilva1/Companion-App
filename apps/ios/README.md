# Companion iOS

App SwiftUI + WidgetKit (Home / Lock Screen) + Live Activity (Dynamic Island).

## Requisitos

- macOS com **Xcode 15+** (iOS 16.2+ no simulador/device)
- API local: na raiz do monorepo, `npm run dev:api`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) para regenerar o `.xcodeproj` se editar `project.yml`

## Gerar / abrir o projeto

```bash
# na raiz do repo
chmod +x scripts/generate-ios-project.sh
./scripts/generate-ios-project.sh
open apps/ios/Companion.xcodeproj
```

Se `brew install xcodegen` falhar, baixe o release:
https://github.com/yonaskolb/XcodeGen/releases

No Xcode: selecione o target **Companion** → Signing & Capabilities → seu Team, e confirme o App Group `group.com.companion.tamagotchi` nos dois targets (app + widget).

## Rodar

1. Em um terminal: `npm run dev:api`
2. No Xcode: scheme **Companion**, simulador iPhone
3. No app: **Atualizar** — deve mostrar “API ok”
4. Cole o Companion ID (ex. o do desktop em `data/companions.json`) se não achar sozinho
5. **Dynamic Island** inicia a Live Activity (no simulador: Features → Live Activities)
6. Adicione o widget: tela de início / bloqueio → widgets → Companion

### Device físico

No campo **API base**, use o IP do Mac na Wi‑Fi, ex. `http://192.168.0.10:3333`  
(e garanta ATS / firewall liberando a porta 3333).

## Estrutura

```
apps/ios/
├── Companion/           # app SwiftUI + cliente HTTP
├── CompanionWidget/     # Home, Lock Screen, Live Activity UI
├── Shared/              # snapshot + ActivityAttributes (App Group)
├── project.yml          # fonte do XcodeGen
└── Companion.xcodeproj  # gerado
```

App Group: `group.com.companion.tamagotchi`

---

## Checklist de aceite (antes de pagar a nuvem)

Só compre o dia no MacinCloud quando **tudo** abaixo estiver ok no código / checklist:

- [ ] Branch `feature/ios` no GitHub (`git push -u origin feature/ios`)
- [ ] App Icon presente (`Companion/Assets.xcassets/AppIcon.appiconset/AppIcon.png`)
- [ ] Sprites Mort/Doux/Vita/Olaf/Kuro em `Shared/Media.xcassets`
- [ ] App mostra **dino** (não só emoji) + energia/afeto
- [ ] Campos **API base** + **Companion ID** + botão **Colar**
- [ ] Fallback de storage (App Group ou UserDefaults standard)
- [ ] Widgets Home + Lock + Live Activity usam `DinoAvatar`
- [ ] No MacinCloud (&lt;2h): Archive → IPA sem erro de ícone
- [ ] No iPhone: Atualizar → API ok → Poke → Island → widgets
- [ ] Chat “qual a temperatura?” responde com °C real (API no Mac)

**Não** é bloqueio para a 1ª compra: quiz, missões, config, SFX, skins picker.

---

## Mac na nuvem (MacinCloud) + iPhone sem pagar Developer

Use quando o Mac local **não** roda Xcode novo (ex. macOS 12) mas você tem iPhone recente + cabo.

**Não precisa** dos US$99/ano da Apple. Conta Apple ID **grátis** + Sideloadly/AltStore bastam para instalar no **seu** aparelho (~7 dias por assinatura).

### Como o MacinCloud funciona

1. Você aluga um **Mac remoto** (navegador ou app Remote Desktop).
2. Nesse Mac já costuma ter **Xcode** / você instala pela App Store.
3. Compila o Companion **lá** e gera um **IPA**.
4. Baixa o IPA no seu Mac de casa.
5. No Mac de casa: **Sideloadly** assina com sua Apple ID grátis e manda pro iPhone **por cabo**.
6. Cancela a nuvem (pay-as-you-go ou trial) quando terminar.

Preços mudam — confira em [macincloud.com](https://www.macincloud.com):

- Trial managed ~US$0,99 / 24h (novos usuários)
- Pay-as-you-go ~US$1/h ou ~US$4/dia (bom para 1–2 dias)
- Managed mensal ~US$25–35 (só se for mexer muito)

### Checklist neste projeto

**A) No MacinCloud**

1. Crie conta → escolha **Pay-as-you-go** ou **Managed trial**.
2. Entre no desktop remoto (eles enviam host/usuário/senha por e-mail).
3. Abra o Terminal e clone o repo (HTTPS):

```bash
git clone https://github.com/cauesilva1/Companion-App.git
cd Companion-App
git checkout feature/ios
open apps/ios/Companion.xcodeproj
```

4. No Xcode (remoto):
   - Scheme **Companion**
   - Signing: sua **Apple ID** (Add Account) → Team **Personal Team** (grátis)
   - Mesmo Team no target **CompanionWidget**
   - App Group `group.com.companion.tamagotchi` nos dois
5. Menu **Product → Archive** → **Distribute App** → **Ad Hoc** ou **Development** → exportar **IPA**.
6. Copie o IPA para o Mac de casa (AirDrop não rola; use Google Drive / Dropbox / `scp` / download pelo painel).

**B) No seu Mac (casa) + iPhone**

1. Instale [Sideloadly](https://sideloadly.io) (roda em macOS mais antigo).
2. Conecte o **iPhone por cabo**, confie no computador.
3. No iPhone: Ajustes → Geral → VPN e gerenciamento de dispositivo → confiar no seu Apple ID.
4. Sideloadly: arraste o IPA → Apple ID → Start.
5. Abra o Companion no iPhone.

**C) API (humor / chat / clima)**

No Mac de casa, na mesma Wi‑Fi do iPhone:

```bash
npm run dev:api
```

No app iOS, **API base** = `http://IP_DO_SEU_MAC:3333` (não use `127.0.0.1` no telefone).

**D) Renovar (~7 dias)**

Reabra o Sideloadly com o mesmo IPA + Apple ID (sem nuvem). Se mudar muito o código, gere IPA de novo na nuvem.

### Limitações

- Personal Team: app some/expira ~7 dias; limite de apps assinados.
- MacinCloud managed muitas vezes **sem root** — Xcode pela conta deles costuma bastar.
- Sem USB no Mac da nuvem: por isso o Sideloadly é no Mac de casa.
