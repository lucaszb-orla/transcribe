# Transcribe

App nativo de macOS (menu bar + janela) que **transcreve reuniões on-device** e gera resumo/follow-up
com IA local. Zero nuvem, zero dependências externas. Toda a UI e a saída de IA são em **português do
Brasil (pt-BR)**.

## Stack

- **Swift 5 / SwiftUI**, deployment target **macOS 26**, Apple Silicon.
- Projeto gerado por **XcodeGen**: a fonte da verdade é `project.yml`, não o `.xcodeproj`.
- APIs da Apple usadas (todas on-device):
  - `Speech` (`SpeechAnalyzer` / `SpeechTranscriber`): transcrição ao vivo.
  - `FoundationModels` (Apple Intelligence): resumo e rascunho de follow-up.
  - `ScreenCaptureKit`: captura do áudio do sistema (outros participantes).
  - `AVAudioEngine`: captura do microfone.
  - `EventKit`: sugere gravação a partir de reuniões do calendário com link de chamada.

## Build & Run

```sh
xcodegen generate
xcodebuild -project Transcribe.xcodeproj -scheme Transcribe -configuration Debug -allowProvisioningUpdates build
open ~/Library/Developer/Xcode/DerivedData/Transcribe-*/Build/Products/Debug/Transcribe.app
```

- **Pra aparecer no Spotlight/Launchpad:** o build fica em `DerivedData`, que não é indexado. Depois de
  buildar, copia pra `/Applications` (preserva a assinatura com `ditto`, não `cp`):
  ```sh
  ditto ~/Library/Developer/Xcode/DerivedData/Transcribe-*/Build/Products/Debug/Transcribe.app /Applications/Transcribe.app
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
  direto na working copy principal.

## Direção de UI e texto

- Não adicionar borda decorativa ao onboarding. A arte cromada é o único destaque material.
- Não usar travessão longo em textos da interface, documentação, comentários ou conteúdo exportado.
  Preferir ponto, vírgula, dois-pontos ou parênteses conforme o contexto.

## Arquitetura

```
Sources/Transcribe/
  App/
    TranscribeApp.swift     # @main: MenuBarExtra + Window(RootView) + Settings(SettingsView)
    AppState.swift          # @MainActor @Observable, estado central, orquestra tudo
  Models/
    Meeting.swift           # Meeting + TranscriptSegment (Codable, salvos em JSON)
    MeetingSummary.swift    # SummaryOptions, SummaryResult, @Generable dos resumos
  Services/
    RecordingSession.swift  # junta mic + áudio do sistema, alimenta o transcritor; pause/resume; micLevel
    MicrophoneCapture.swift # tap no inputNode do AVAudioEngine; seleção de dispositivo
    SystemAudioCapture.swift# ScreenCaptureKit (áudio do sistema, sem gravar vídeo)
    Transcriber.swift       # SpeechAnalyzer + resultados finais e "volatile" (ao vivo)
    CMSampleBuffer+PCM.swift # conversão de buffer do ScreenCaptureKit
    Summarizer.swift        # resumo via FoundationModels (bullets/prosa + itens de ação)
    SummaryPresets.swift    # presets nomeados de SummaryOptions (persistidos)
    CalendarMonitor.swift   # EventKit: sugere reunião a começar
    CallLinkDetector.swift  # detecta link de chamada em evento do calendário
    PermissionsManager.swift# 3 acessos essenciais + Calendário opcional + conclusão do onboarding
    AudioDevices.swift      # enumera dispositivos de entrada (Core Audio) + AppSettings
    MeetingExporter.swift   # Markdown/texto, copiar, exportar arquivo, salvamento automático em pasta
  Storage/
    MeetingStore.swift      # persistência local: 1 JSON por reunião em Application Support
  Views/
    RootView.swift          # gate de onboarding → RecordingView (gravando) ou MeetingListView
    OnboardingView.swift    # fluxo editorial: 3 acessos essenciais + Calendário opcional
    OnboardingPermissionPanel.swift # etapa ativa, progresso 0/3...3/3 e ações de permissão
    RecordingView.swift     # tela "Gravando": status, cronômetro, transcrição ao vivo, medidor de nível, pause/stop
    MeetingListView.swift   # lista + busca + excluir; abre a reunião recém-gravada
    MeetingDetailView.swift # título/participantes; gerar resumo (opções+presets); follow-up; transcrição editável; exportar
    SettingsView.swift      # ⌘,: microfone + idioma da transcrição
    MenuBarView.swift       # controles rápidos na barra de menu
Tests/TranscribeTests/      # CallLinkDetectorTests + PermissionPolicyTests
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

- Onboarding editorial com arte cromada e progresso 0/3...3/3; pede os três acessos essenciais em
  sequência e oferece Calendário como extra pulável.
- Gravação: mic + áudio do sistema mixados no transcritor, **transcrição ao vivo**, **pause/retomar**,
  **medidor de nível** do microfone.
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
- **Continuar transcrição** depois de encerrada, sem precisar criar uma reunião nova.
- Confirmação antes de encerrar gravação ou apagar qualquer coisa (reunião, preset).
- Lista com busca, excluir, e navegação automática pra reunião recém-gravada.
- Ajustes acessível por botão visível (menu da barra + toolbar), além de ⌘,.
- Ícone do app e ícone da menu bar (`quote.bubble` / `quote.bubble.fill` gravando).

Nota: o "rascunho de follow-up" foi removido (não ficou bom). A ideia de direcionar a IA por
linguagem natural continua no campo **Instruções adicionais** do resumo, sem toggles de tom.

## Gotchas conhecidos

- **`AVAudioEngine` mixer + `outputVolume = 0`:** se você fizer tap no `mainMixerNode` e zerar o volume,
  o tap recebe **silêncio** (era o bug "transcrição não pega"). Por isso o mic é capturado com tap direto
  no `inputNode`, sem rota de saída: sem playback, sem eco, sem gravar em disco.
- **Idioma:** `Locale.current` transcrevia em inglês. Agora o idioma vem de `AppSettings` (padrão `pt-BR`,
  que é suportado e já vem instalado neste Mac).
- **FoundationModels exige Apple Intelligence ativado**: se não estiver, resumo/follow-up lançam erro
  legível (`appleIntelligenceNotEnabled`) sem quebrar a transcrição.

## Próximos passos possíveis

- Diarização de verdade entre os participantes remotos (hoje só separa "Você" de "Participantes";
  dentro de "Participantes" ainda é todo mundo misturado, exigiria modelo de embeddings/clustering,
  dependência externa real, avaliado e descartado por ora).
- Exportar PDF; enviar direto pra e-mail/Slack.
- Melhorar vocabulário (nomes próprios/siglas): WhisperKit avaliado como fallback e descartado por
  ora (sem streaming nativo e exigiria manter áudio em memória, já que o app não grava em disco).
