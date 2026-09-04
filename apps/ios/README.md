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
