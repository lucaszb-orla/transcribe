# Transcribe

App nativo de macOS (menu bar + janela) que **transcreve reuniões on-device** e gera resumo/follow-up
com IA local. Zero nuvem, zero dependências externas. A UI é localizável (pt-BR, en, es, fr; ver
Localização); **a saída de IA continua sempre em português do Brasil (pt-BR)**, independente do idioma
da interface (ver Localização).

> **Exceção deliberada:** a feature de "Specs de implementação" (ver Arquitetura e Gotchas) sai desse
> princípio de propósito, chamando o CLI real `claude` (e `gh`) para transformar itens de reunião em
> PRs. É opt-in, visível (abre um Terminal de verdade) e vive isolada em `ClaudeCodeRunner.swift`. O
> resto do app (transcrição, resumo, armazenamento) continua 100% on-device.

## Stack

- **Swift 5 / SwiftUI**, deployment target **macOS 26**, Apple Silicon.
- Projeto gerado por **XcodeGen**: a fonte da verdade é `project.yml`, não o `.xcodeproj`.
- APIs da Apple usadas (todas on-device):
  - `Speech` (`SpeechAnalyzer` / `SpeechTranscriber`): transcrição ao vivo.
  - `FoundationModels` (Apple Intelligence): resumo e rascunho de follow-up.
  - `ScreenCaptureKit`: captura do áudio do sistema (outros participantes).
  - `AVAudioEngine`: captura do microfone.
  - `EventKit`: sugere gravação a partir de reuniões do calendário com link de chamada.
  - `TipKit`: dica contextual de primeiro uso (`DevSpecsTips.swift`).

## Build & Run

```sh
xcodegen generate
xcodebuild -project Transcribe.xcodeproj -scheme Transcribe -configuration Debug -allowProvisioningUpdates build
open ~/Library/Developer/Xcode/DerivedData/Transcribe-*/Build/Products/Debug/Transcribe.app
```

- **Cuidado com o glob `Transcribe-*` do DerivedData:** o hash muda de vez em quando (ex.: depois de um
  `xcodegen generate` que mexe bastante no projeto), e pastas antigas ficam pra trás. `ls -d .../Transcribe-*`
  ordena alfabeticamente, não por data. Já rolou de pegar um build **desatualizado** sem querer (ex.: um
  recurso novo "sumindo" porque a cópia usada não era a mais recente). Pegue o caminho certo assim:
  ```sh
  xcodebuild -project Transcribe.xcodeproj -scheme Transcribe -configuration Debug -showBuildSettings \
    | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}'
  ```
  E de vez em quando limpe as pastas `Transcribe-*` que não batem com esse caminho (é só cache de build).
- **Pra aparecer no Spotlight/Launchpad:** o build fica em `DerivedData`, que não é indexado. Depois de
  buildar, copia pro caminho acima (não o glob) pra `/Applications` (preserva a assinatura com `ditto`,
  não `cp`):
  ```sh
  ditto "$CANONICAL/Transcribe.app" /Applications/Transcribe.app
  ```
  A partir daí abra/rode o de `/Applications` (não o de `DerivedData`), pra não ter duas cópias
  divergentes. Repita a cada rebuild.
- **Assinatura (crítico):** `DEVELOPMENT_TEAM` em `project.yml` = `7QTC8MU95P` (personal team). Sem uma
  identidade estável, cada rebuild muda a assinatura ad-hoc e o macOS **zera as permissões (TCC)**,
  que era a causa do "toda vez pede permissão de novo". Sempre buildar com `-allowProvisioningUpdates`.
- Logs do app: `log show --predicate 'subsystem == "com.lucasbaggiotto.Transcribe"' --last 5m --info`
  (os `logger.debug` não persistem; use `.notice`/`.error` para depurar via `log show`).

## Workflow com Claude Code

- **Commitar a cada fix ou feature.** Não acumular várias mudanças num commit só: assim que uma
  correção ou funcionalidade nova builda e roda, commita antes de seguir pra próxima coisa.
- **Usar worktree separada por padrão.** Pra não dar conflito de arquivo quando há mais de uma tarefa
  mexendo no repo ao mesmo tempo, cada tarefa nova roda em uma `git worktree` própria em vez de tudo
  direto na working copy principal. Essas worktrees vivem em `.claude/worktrees/` (gitignored: são
  checkouts de verdade, não devem ser versionadas a partir do repo principal).
- **Múltiplas sessões mexem neste repo ao mesmo tempo** (você não é o único agente trabalhando aqui).
  Antes de `git push`, sempre `git fetch` + `git pull --no-rebase` primeiro; espere divergência.
  Conflito quase sempre cai no `Transcribe.xcodeproj/project.pbxproj` (é gerado): não resolva na mão,
  pegue um dos dois lados (`git checkout --theirs` ou `--ours`) e rode `xcodegen generate` de novo.
  Depois builda e roda os testes antes de empurrar, mesmo que o merge não tenha dado conflito.
- **Mantenha este arquivo atualizado.** Sempre que você (agente) terminar uma feature, um fix não óbvio,
  ou aprender um gotcha novo, atualize este `CLAUDE.md` na mesma sessão (arquitetura, "Feito até agora",
  "Gotchas conhecidos") antes de considerar a tarefa concluída — é a única memória persistente entre
  sessões/agentes diferentes trabalhando neste projeto. Prefira editar as seções existentes a duplicar
  informação; se algo documentado aqui ficou obsoleto (feature removida, decisão revertida), corrija em
  vez de deixar o arquivo mentir.

## Direção de UI e texto

- Não adicionar borda decorativa ao onboarding. A arte cromada é o único destaque material.
- Não usar travessão longo em textos da interface, documentação, comentários ou conteúdo exportado.
  Preferir ponto, vírgula, dois-pontos ou parênteses conforme o contexto.

## Localização

A UI usa **String Catalogs** (`Sources/Transcribe/Localizable.xcstrings` e `InfoPlist.xcstrings`), o
mecanismo atual da Apple (substitui `Localizable.strings`/`.lproj` manuais). `pt-BR` é o idioma-fonte
(`developmentLanguage: pt-BR` em `project.yml`); `en`, `es`, `fr` são traduzidos no catálogo.

**O que é localizado:** todo o texto de UI (views, alerts, tips, nomes de seção do exportador de
reunião) e as mensagens de erro mostradas ao usuário (`SummarizerError`, `ClaudeCodeRunner.RunnerError`,
`AppState.errorMessage`).

**O que fica sempre em pt-BR, de propósito:** os prompts que instruem o modelo (`Summarizer.swift`,
`ClaudeCodeRunner.swift` — incluindo o script que roda o `claude` autônomo) e `Speaker.label`
("Você"/"Participantes", usado tanto na UI quanto embutido no texto que vai pro modelo). Esses textos
conversam com a IA sobre uma reunião em português, não são "chrome" de interface, então não seguem o
idioma da UI. Ver a exceção deliberada no topo deste arquivo.

**Como funciona a extração:** `Text("literal")` / `Button("literal")` / `Label("literal", ...)` etc.
já são localizáveis de graça (SwiftUI trata o literal como `LocalizedStringKey`). Qualquer string que
passa por uma propriedade/variável do tipo `String` antes de chegar na view (label de enum via
`switch`, `errorMessage = "..."`, `A ?? "literal"` onde `A` não é literal) **não** é extraída
automaticamente — precisa envolver o literal em `String(localized: "...")` no ponto onde ele aparece
como literal de verdade (não no call site que só recebe a variável já resolvida).

**Fluxo pra adicionar/atualizar strings** (a extração automática do Xcode só roda dentro do editor, não
via `xcodebuild` puro — ver Gotchas):
```sh
xcodegen generate
xcodebuild -project Transcribe.xcodeproj -scheme Transcribe -configuration Debug -allowProvisioningUpdates build
STRDATA_DIR=$(xcodebuild -showBuildSettings -project Transcribe.xcodeproj -scheme Transcribe -configuration Debug \
  | awk -F'= ' '/ PER_VARIANT_OBJECT_FILE_DIR /{print $2; exit}')/arm64
args=(); for f in "$STRDATA_DIR"/*.stringsdata; do args+=(--stringsdata "$f"); done
/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool sync Sources/Transcribe/Localizable.xcstrings "${args[@]}"
```
Isso atualiza as chaves em `Localizable.xcstrings` (novas entram como `"state": "new"`, sem tradução);
traduza à mão pra `en`/`es`/`fr` editando o JSON. `InfoPlist.xcstrings` não é populado por esse fluxo
(as strings de `Info.plist` não passam pelo compilador Swift); edite esse arquivo manualmente, chaveado
pelo nome da chave do `Info.plist` (`NSMicrophoneUsageDescription` etc.), não pelo texto.

## Arquitetura

```
Sources/Transcribe/
  Localizable.xcstrings    # String Catalog da UI: pt-BR (fonte) + en/es/fr; ver Localização
  InfoPlist.xcstrings      # String Catalog das strings do Info.plist (descrições de permissão)
  App/
    TranscribeApp.swift     # @main: MenuBarExtra + Window(RootView) + Settings(SettingsView); Tips.configure()
    AppState.swift          # @MainActor @Observable, estado central, orquestra tudo
  Models/
    Meeting.swift           # Meeting + TranscriptSegment + Speaker (Codable, salvos em JSON)
    MeetingSummary.swift    # SummaryOptions, SummaryResult, @Generable dos resumos
    DevSpec.swift            # tarefa de implementação extraída de uma reunião, pra virar PR
    DevSpecOptions.swift     # modelo/effort do `claude` usado pra gerar e rodar as specs
  Services/
    RecordingSession.swift  # mic + áudio do sistema em dois Transcriber separados; pause/resume; micLevel; dedup de eco
    MicrophoneCapture.swift # tap no inputNode do AVAudioEngine; seleção de dispositivo
    SystemAudioCapture.swift# ScreenCaptureKit (áudio do sistema, sem gravar vídeo)
    Transcriber.swift       # SpeechAnalyzer, tagueado por Speaker; resultados finais e "volatile" (ao vivo)
    CMSampleBuffer+PCM.swift # conversão de buffer do ScreenCaptureKit
    Summarizer.swift        # resumo via FoundationModels (bullets/prosa + itens de ação)
    SummaryPresets.swift    # presets nomeados de SummaryOptions (persistidos)
    CalendarMonitor.swift   # EventKit: sugere reunião a começar
    CallLinkDetector.swift  # detecta link de chamada em evento do calendário
    PermissionsManager.swift# 3 acessos essenciais + Calendário opcional + conclusão do onboarding
    AudioDevices.swift      # enumera dispositivos de entrada (Core Audio) + AppSettings
    MeetingExporter.swift   # Markdown/texto, copiar, exportar arquivo, salvamento automático em pasta
    ClaudeCodeRunner.swift   # gera DevSpecs via `claude -p` headless; abre Terminal visível rodando
                             # `claude` autônomo (implementa + push + `gh pr create`); ver Gotchas
  Storage/
    MeetingStore.swift      # persistência local: 1 JSON por reunião em Application Support
  Views/
    RootView.swift          # gate de onboarding → RecordingView (gravando) ou MeetingListView
    OnboardingView.swift    # fluxo editorial: 3 acessos essenciais + Calendário opcional + logo animado
    OnboardingPermissionPanel.swift # etapa ativa, progresso 0/3...3/3 e ações de permissão
    LoopingVideoView.swift   # AVQueuePlayer + AVPlayerLooper: logo animado em loop mudo (ver Gotchas)
    RecordingView.swift     # tela "Gravando": status, cronômetro, transcrição em balões, medidor, pause/stop
    TranscriptBubbles.swift  # transcrição em formato chat (Você à direita, Participantes à esquerda)
    MeetingListView.swift   # lista + busca + excluir; abre a reunião recém-gravada
    MeetingDetailView.swift # título/participantes; gerar resumo (opções+presets); specs de implementação;
                             # transcrição em balões (editável); exportar
    DevSpecsView.swift       # lista de specs extraídas da reunião; dispara o ClaudeCodeRunner por spec
    DevSpecsTips.swift       # TipKit: dica contextual pro botão "Specs de implementação"
    SettingsView.swift      # ⌘,: microfone, idioma, salvamento automático, rever onboarding
    MenuBarView.swift       # controles rápidos na barra de menu
    ConfirmationDialogs.swift # diálogos compartilhados de confirmação (encerrar gravação, apagar)
Tests/TranscribeTests/      # testes de links, permissões, Claude Code, transcriber, resumo e recuperação do mic
```

**Fluxo:** Standby (monitorando calendário somente quando conectado) ↔ Meeting (gravando). Ao
encerrar, a transcrição é salva na hora; **o resumo é sob demanda** (o usuário escolhe
formato/opções na tela da reunião).

## Permissões (TCC)

Três são essenciais e pedidas explicitamente, nessa ordem, no onboarding: **Microfone**,
**Reconhecimento de fala** e **Gravação de tela**. A última é necessária pro ScreenCaptureKit capturar
o áudio do sistema, mesmo sem vídeo, e só é reavaliada no launch: mudou nos Ajustes, precisa reiniciar
o app.

**Calendário é uma integração opcional.** Ele aparece depois de 3/3, pode ser pulado e nunca participa
do gate de gravação. O único prompt de EventKit parte de uma ação explícita em
`AppState.requestCalendarIntegration()`; launch, retorno ao foreground e monitoramento apenas
sincronizam o status existente. Sem acesso, o monitor fica parado, a automação fica desativada e a
lista mantém um aviso para conectar ou abrir os Ajustes.

A conclusão do onboarding fica em `UserDefaults` (`onboardingCompleted`). Instalações anteriores que
já têm os três acessos essenciais são migradas silenciosamente; revogar um essencial reabre o fluxo de
recuperação mesmo se a conclusão já estiver salva.

## Armazenamento

Um arquivo JSON por reunião em `~/Library/Application Support/Transcribe/Meetings/`. **Não grava áudio em
disco** (por design). Nada de nuvem/sync.

## Feito até agora

- **Localização da UI em pt-BR (fonte), inglês, espanhol e francês** via String Catalog; segue o
  idioma do sistema automaticamente (sem seletor de idioma dentro do app). A saída de IA (resumos,
  specs) continua sempre em pt-BR de propósito. Ver Localização.
- Onboarding editorial com arte cromada e progresso 0/3...3/3; pede os três acessos essenciais em
  sequência e oferece Calendário como extra pulável.
- Gravação: mic + áudio do sistema, **transcrição ao vivo**, **pause/retomar**, **medidor de nível** do
  microfone.
- Ajustes: seleção de **microfone** e **idioma** (padrão pt-BR).
- Resumo **sob demanda**: formato **tópicos ou prosa**, toggle de **itens de ação**, **instruções
  personalizadas**, e **presets** (Reunião geral, Daily/Standup, Call de vendas, 1:1).
- **Presets gerenciáveis:** salvar as opções atuais como novo preset (na tela da reunião), renomear e
  apagar (em Ajustes).
- **Itens de ação marcáveis:** checkbox por item, com estado persistido na reunião (`doneActionItems`).
- **Auto-iniciar/encerrar pelo calendário** (opt-in em Ajustes): grava quando o evento com link começa e
  para no fim do evento. `MeetingSuggestion.end` + `CalendarMonitor.onNewCandidate` + auto-stop task no `AppState`.
- **Exportar/compartilhar** (Markdown / texto / arquivo `.md`).
- **Salvamento automático opcional** em Markdown numa pasta escolhida pelo usuário (Ajustes,
  desativado por padrão): a cada reunião encerrada, espelha o `.md` lá além do armazenamento próprio.
- **Transcrição dividida por falante** ("Você" vs. "Participantes"): mic e áudio do sistema passam por
  dois `Transcriber` separados, cada um tagueando seus segmentos, não é diarização de verdade (não
  separa os participantes remotos entre si, que chegam misturados no áudio do sistema).
- **Transcrição em formato chat**: balões estilo WhatsApp/iMessage (Você à direita, Participantes à
  esquerda), largura responsiva por `GeometryReader`, agrupando segmentos consecutivos do mesmo falante.
- **Dedup de eco mic × áudio do sistema**: sem fone, o mic capta o que sai pelo alto-falante do Mac e
  duplicava a fala de participantes como se fosse do usuário; heurística por proximidade de tempo +
  similaridade de texto descarta o lado do mic quando bate com o do áudio do sistema.
- **Continuar transcrição** depois de encerrada, sem precisar criar uma reunião nova.
- Confirmação antes de encerrar gravação ou apagar qualquer coisa (reunião, preset).
- Lista com busca, excluir, e navegação automática pra reunião recém-gravada.
- Ajustes acessível por botão visível (menu da barra + toolbar), além de ⌘,; inclui "Rever onboarding".
- Ícone do app e ícone da menu bar (`quote.bubble` / `quote.bubble.fill` gravando); logo animado (loop
  mudo) na tela de onboarding, com fallback estático se Reduzir Movimento estiver ativo.
- **Specs de implementação (0.1-alpha, exceção "zero cloud")**: extrai tarefas de implementação da
  transcrição via `claude -p` headless, e por spec abre um Terminal visível rodando `claude` autônomo
  que implementa, faz commit/push numa branch `transcribe/...` e abre PR com `gh pr create`. Exige
  `claude` e `gh` instalados e autenticados no PATH; nunca roda escondido. Ver Gotchas.

Nota: o "rascunho de follow-up" foi removido (não ficou bom). A ideia de direcionar a IA por
linguagem natural continua no campo **Instruções adicionais** do resumo, sem toggles de tom.

## Gotchas conhecidos

- **`AVAudioEngine` mixer + `outputVolume = 0`:** se você fizer tap no `mainMixerNode` e zerar o volume,
  o tap recebe **silêncio** (era o bug "transcrição não pega"). Por isso o mic é capturado com tap direto
  no `inputNode`, sem rota de saída: sem playback, sem eco, sem gravar em disco.
- **Mudança de hardware para o `AVAudioEngine`:** Teams, fones, iPhone ou outra rota podem mudar o
  sample rate ou a quantidade de canais durante uma reunião. Nessa situação, o macOS para e
  desinicializa a engine e publica `AVAudioEngineConfigurationChange`. Sem observar essa notificação,
  o tap do microfone morre em silêncio enquanto o áudio do sistema continua normal. O
  `MicrophoneCapture` agora agenda a recuperação numa fila serial, recria a engine e o tap fora do
  callback da notificação e usa o microfone padrão como fallback se o dispositivo escolhido sumir.
  Não destrua a engine dentro do callback da Apple, pois isso pode causar deadlock.
- **Idioma:** `Locale.current` transcrevia em inglês. Agora o idioma vem de `AppSettings` (padrão `pt-BR`,
  que é suportado e já vem instalado neste Mac).
- **`SpeechAnalyzer.finalizeAndFinishThroughEndOfInput()` não tem limite de tempo documentado.** Numa
  reunião de 1h+ isso já travou de verdade: o app fica parado pra sempre em "Encerrar" esperando esse
  `await` retornar, e como o `store.save()` só roda depois disso, a transcrição inteira (que já estava
  toda em `Transcriber.segments`, capturada ao vivo durante a gravação) nunca chega a ser salva —
  mesmo não tendo se perdido de verdade, fica presa atrás de uma espera sem fim. `Transcriber.finish()`
  agora corre essa chamada contra um timeout de 15s (`Transcriber.withTimeout`, ver Tests/TranscriberTests):
  não dá pra usar `withTaskGroup` pra isso porque ele sempre espera todos os filhos terminarem antes de
  retornar, cancelamento ou não (cancelamento é cooperativo, não preemptivo) — por isso o timeout usa
  duas `Task {}` soltas (não estruturadas) competindo por uma `CheckedContinuation`, e simplesmente
  ignora a que ficou pra trás. Se isso disparar (log `.error` avisando), o pior caso é perder só os
  últimos segundos ainda não finalizados, nunca a reunião inteira.
- **FoundationModels exige Apple Intelligence ativado**: se não estiver, resumo/follow-up lançam erro
  legível (`appleIntelligenceNotEnabled`) sem quebrar a transcrição.
- **DerivedData com hash duplicado:** ver "Build & Run". Sempre confirme o `BUILT_PRODUCTS_DIR` via
  `-showBuildSettings` antes de copiar/abrir o `.app` — um glob alfabético já pegou build velho sem avisar.
- **`AVPlayerLayer` atribuído direto a `view.layer` não acompanha o resize da view sozinho.** Sem
  sobrescrever `layout()` pra fazer `videoLayer.frame = bounds`, o layer fica travado no frame `.zero`
  inicial e o fundo padrão da `NSView` aparece como uma "moldura" ao redor do vídeo (bug real, já
  corrigido em `LoopingVideoView.swift` — se for reusar esse padrão em outro lugar, não esqueça o `layout()`).
- **`.frame(maxWidth:maxHeight:)` num `ZStack` capa o fundo junto com o conteúdo.** No onboarding, isso
  fazia o fundo parar de preencher a janela quando ela era maior que o cap (a janela é compartilhada
  com a lista de reuniões e lembra o tamanho salvo) — o cinza padrão da janela aparecia como borda ao
  redor do conteúdo capado e centralizado. Fix: cap só no conteúdo interno (ex.: o `HStack` das colunas),
  nunca no `ZStack`/`Color.ignoresSafeArea()` que serve de fundo.
- **Merges concorrentes são a norma neste repo**, não exceção — várias sessões/worktrees mexem aqui ao
  mesmo tempo (ver Workflow). `git push` direto em `main` frequentemente é rejeitado por
  non-fast-forward; isso é esperado, não um erro pra investigar, só `fetch` + `pull` + resolver.
- **`Process` com `Pipe()` de stderr nunca lido trava pra sempre.** Se o filho escrever o suficiente em
  stderr e ninguém ler, o buffer enche e ele trava (era o bug "fica só aguardando" na primeira versão
  do `ClaudeCodeRunner`, que rodava o `claude` em background dentro do próprio app). Use
  `FileHandle.nullDevice` quando não for consumir o stream, ou drene ativamente.
- **`SystemLanguageModel.contextSize` é pequeno (~4096 tokens).** Uma reunião de ~30min sozinha já pode
  estourar isso, antes mesmo de contar instruções/saída. Quem gera specs ou resumo on-device precisa
  quebrar a transcrição em pedaços (`Summarizer.chunkedForContext`); trate
  `LanguageModelSession.GenerationError.exceededContextWindowSize` com mensagem própria, não deixe o
  erro cru do framework vazar pra UI. **`generateDevSpecs` já quebrava a transcrição desde o início,
  mas `summarize` (o botão "Resumo") não quebrava** — reunião de 1h+ batia direto no limite e só
  devolvia esse erro, sem alternativa real ("tente de novo" não ajuda, a transcrição não fica menor.
  `summarize` agora resume cada pedaço em tópicos primeiro (formato compacto, independente do formato
  final pedido) e faz uma segunda passada só pra sintetizar esses resumos parciais (bem mais curtos que
  a transcrição original) num resumo único, no formato que o usuário escolheu. Reuniões curtas (cabem
  num pedaço só) continuam indo direto, sem essa segunda passada.
- **App GUI não herda o PATH do shell do usuário.** Rodar `git`/`gh`/`claude` a partir do próprio
  processo do app (não de um Terminal) exige resolver o binário via shell de login
  (`/bin/zsh -l -c "command -v X"`) primeiro. É por isso que `ClaudeCodeRunner` abre um Terminal de
  verdade pra rodar o `claude` autônomo em vez de gerenciar o processo direto: o Terminal já tem o PATH
  normal do usuário, sem essa ginástica.
- **`claude --dangerously-skip-permissions`/`--permission-mode bypassPermissions` é recusado** pela
  própria Anthropic como uso perigoso. Pra automação sem prompt interativo a cada passo, use
  `--permission-mode acceptEdits --allowedTools Bash`.
- **Automação de UI via `osascript`/System Events exige permissão de Acessibilidade**, que não está
  concedida neste Mac pro Terminal/agente: `keystroke` e consultas de janela falham. Screenshot de tela
  inteira (`screencapture -x`) funciona sem essa permissão, mas rouba o foco de qualquer janela que o
  usuário esteja usando de verdade e pode capturar conteúdo alheio à tarefa (outras janelas, outra
  sessão) — evite ativar/focar janelas de outros apps à toa, principalmente com o usuário ativo na
  máquina. Também retorna uma imagem inteiramente preta se a tela estiver bloqueada/em suspensão —
  nesse caso não adianta repetir a captura, é preciso esperar o usuário desbloquear.
- **`SWIFT_EMIT_LOC_STRINGS` não vem `YES` por padrão num projeto gerado pelo XcodeGen.** É o build
  setting que faz o compilador Swift emitir `.stringsdata` (usado pra popular o String Catalog); o
  Xcode liga isso sozinho quando você adiciona um catálogo pela UI, mas o XcodeGen só aplica o que está
  em `project.yml` — sem essa flag explícita, `Localizable.xcstrings` builda mas nunca ganha chaves
  novas, silenciosamente.
- **A extração automática de strings pro String Catalog só roda dentro do Xcode.app, não no
  `xcodebuild` puro.** O `swiftc` com `SWIFT_EMIT_LOC_STRINGS: YES` gera os `.stringsdata`
  normalmente, mas o passo que funde isso de volta no `.xcstrings` é uma feature só da IDE. Pra fazer
  esse fluxo funcionar via linha de comando (obrigatório pra um agente que não abre o Xcode.app), use
  `xcstringstool sync` (`/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool`) apontando
  pros `.stringsdata` gerados — ver Localização.
- **`.confirmationDialog`/`.sheet`/`.alert` do SwiftUI não funcionam de forma confiável dentro do
  painel do `MenuBarExtra(.window)`.** Era o bug "não dá pra encerrar transcrição pela menu bar": o
  painel de `.menuBarExtraStyle(.window)` é uma janela auxiliar não-ativável, então o diálogo de
  confirmação simplesmente não aparecia (ou o painel perdia o key window e fechava sozinho antes do
  usuário conseguir responder), sem erro nenhum, até parecer que o botão "Encerrar transcrição" não
  fazia nada. É uma limitação conhecida da API (sem fix nativo da Apple até o momento). Fix: o botão
  "Encerrar transcrição" do `MenuBarView` usa `MenuBarConfirmation.confirmEndMeeting` (em
  `ConfirmationDialogs.swift`), que chama `NSAlert().runModal()` diretamente, isso abre uma janela modal
  de verdade, independente do ciclo de vida do painel do menu bar. A `RecordingView` (janela real do app)
  continua usando `.confirmationDialog` normalmente, que funciona sem problema numa `Window` de verdade.
- **`.environment(\.locale, ...)` fixo em qualquer `Scene`/view sobrepõe o idioma do sistema pra toda a
  árvore, inclusive a resolução de `Text(LocalizedStringKey)`.** O app tinha um
  `.environment(\.locale, Locale(identifier: "pt_BR"))` fixo em `TranscribeApp.swift` (adicionado só
  pra formatar datas em português mesmo com o Mac em inglês, antes de existir localização de verdade).
  Isso fazia CADA string traduzida no String Catalog ser ignorada silenciosamente: a UI continuava saindo
  em pt-BR não importa o idioma do sistema, porque o `\.locale` do ambiente é exatamente o que o SwiftUI
  usa pra escolher a tradução (é o mesmo mecanismo do `.environment(\.locale, .init(identifier: "fr"))`
  usado pra pré-visualizar outro idioma no Xcode Previews). Foi removido: agora data/número E texto
  seguem o idioma do sistema de forma consistente, sem esse hack.

## Próximos passos possíveis

- Diarização de verdade entre os participantes remotos (hoje só separa "Você" de "Participantes";
  dentro de "Participantes" ainda é todo mundo misturado, exigiria modelo de embeddings/clustering,
  dependência externa real, avaliado e descartado por ora).
- Exportar PDF; enviar direto pra e-mail/Slack.
- Melhorar vocabulário (nomes próprios/siglas): WhisperKit avaliado como fallback e descartado por
  ora (sem streaming nativo e exigiria manter áudio em memória, já que o app não grava em disco).
