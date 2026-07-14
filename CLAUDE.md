# Transcribe

App nativo de macOS (menu bar + janela) que **transcreve reuniões on-device** e gera resumo/follow-up
com IA local. Zero nuvem, zero dependências externas. Toda a UI e a saída de IA são em **português do
Brasil (pt-BR)**.

## Stack

- **Swift 5 / SwiftUI**, deployment target **macOS 26**, Apple Silicon.
- Projeto gerado por **XcodeGen** — a fonte da verdade é `project.yml`, não o `.xcodeproj`.
- APIs da Apple usadas (todas on-device):
  - `Speech` (`SpeechAnalyzer` / `SpeechTranscriber`) — transcrição ao vivo.
  - `FoundationModels` (Apple Intelligence) — resumo e rascunho de follow-up.
  - `ScreenCaptureKit` — captura do áudio do sistema (outros participantes).
  - `AVAudioEngine` — captura do microfone.
  - `EventKit` — sugere gravação a partir de reuniões do calendário com link de chamada.

## Build & Run

```sh
xcodegen generate
xcodebuild -project Transcribe.xcodeproj -scheme Transcribe -configuration Debug -allowProvisioningUpdates build
open ~/Library/Developer/Xcode/DerivedData/Transcribe-*/Build/Products/Debug/Transcribe.app
```

- **Assinatura (crítico):** `DEVELOPMENT_TEAM` em `project.yml` = `7QTC8MU95P` (personal team). Sem uma
  identidade estável, cada rebuild muda a assinatura ad-hoc e o macOS **zera as permissões (TCC)** —
  era a causa do "toda vez pede permissão de novo". Sempre buildar com `-allowProvisioningUpdates`.
- Logs do app: `log show --predicate 'subsystem == "com.lucasbaggiotto.Transcribe"' --last 5m --info`
  (os `logger.debug` não persistem; use `.notice`/`.error` para depurar via `log show`).

## Arquitetura

```
Sources/Transcribe/
  App/
    TranscribeApp.swift     # @main: MenuBarExtra + Window(RootView) + Settings(SettingsView)
    AppState.swift          # @MainActor @Observable — estado central, orquestra tudo
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
    FollowUpDrafter.swift   # rascunho de e-mail/mensagem via FoundationModels
    SummaryPresets.swift    # presets nomeados de SummaryOptions (persistidos)
    CalendarMonitor.swift   # EventKit: sugere reunião a começar
    CallLinkDetector.swift  # detecta link de chamada em evento do calendário
    PermissionsManager.swift# mic / fala / calendário / gravação de tela
    AudioDevices.swift      # enumera dispositivos de entrada (Core Audio) + AppSettings
  Storage/
    MeetingStore.swift      # persistência local: 1 JSON por reunião em Application Support
  Views/
    RootView.swift          # gate de onboarding → RecordingView (gravando) ou MeetingListView
    OnboardingView.swift    # concede as 4 permissões
    RecordingView.swift     # tela "Gravando": status, cronômetro, transcrição ao vivo, medidor de nível, pause/stop
    MeetingListView.swift   # lista + busca + excluir; abre a reunião recém-gravada
    MeetingDetailView.swift # título/participantes; gerar resumo (opções+presets); follow-up; transcrição editável; exportar
    SettingsView.swift      # ⌘, — microfone + idioma da transcrição
    MenuBarView.swift       # controles rápidos na barra de menu
Tests/TranscribeTests/      # CallLinkDetectorTests
```

**Fluxo:** Standby (monitorando calendário) ↔ Meeting (gravando). Ao encerrar, a transcrição é salva
na hora; **o resumo é sob demanda** (o usuário escolhe formato/opções na tela da reunião).

## Permissões (TCC)

Quatro, pedidas explicitamente no onboarding: **Microfone**, **Reconhecimento de fala**, **Calendário**,
**Gravação de tela** (esta última necessária pro ScreenCaptureKit capturar o áudio do sistema, mesmo sem
vídeo). A de gravação de tela só é reavaliada no launch — mudou nos Ajustes, precisa reiniciar o app.

## Armazenamento

Um arquivo JSON por reunião em `~/Library/Application Support/Transcribe/Meetings/`. **Não grava áudio em
disco** (por design). Nada de nuvem/sync.

## Feito até agora

- Onboarding com as 4 permissões (+ botão de reiniciar pra gravação de tela).
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
- Lista com busca, excluir, e navegação automática pra reunião recém-gravada.
- Ajustes acessível por botão visível (menu da barra + toolbar), além de ⌘,.

Nota: o "rascunho de follow-up" foi removido (não ficou bom). A ideia de direcionar a IA por
linguagem natural continua no campo **Instruções adicionais** do resumo — sem toggles de tom.

## Gotchas conhecidos

- **`AVAudioEngine` mixer + `outputVolume = 0`:** se você fizer tap no `mainMixerNode` e zerar o volume,
  o tap recebe **silêncio** (era o bug "transcrição não pega"). Por isso o mic é capturado com tap direto
  no `inputNode`, sem rota de saída — sem playback, sem eco, sem gravar em disco.
- **Idioma:** `Locale.current` transcrevia em inglês. Agora o idioma vem de `AppSettings` (padrão `pt-BR`,
  que é suportado e já vem instalado neste Mac).
- **FoundationModels exige Apple Intelligence ativado** — se não estiver, resumo/follow-up lançam erro
  legível (`appleIntelligenceNotEnabled`) sem quebrar a transcrição.

## Próximos passos possíveis

- Diarização (quem falou o quê) — hoje é um stream único mixado, sem separar falantes.
- Itens de ação marcáveis/concluíveis (hoje são texto).
- Exportar PDF; enviar direto pra e-mail/Slack.
- Gerenciar presets (renomear/editar/apagar) e salvar as opções atuais como novo preset.
- Melhorar vocabulário (nomes próprios/siglas) — WhisperKit como fallback se a precisão não bastar.
- Início/fim de gravação automáticos a partir do calendário.
