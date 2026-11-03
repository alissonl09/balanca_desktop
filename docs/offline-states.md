# Base de estados offline da estação

Esta etapa implementa modelo, comandos locais, store substituível, indicação
global e testes. Não implementa operação offline durável: o store em memória
perde dados ao encerrar o processo. Não há HTTP, cache automático, retry,
timer, sondagem de rede, banco, SGV, impressão, Serial/TCP ou credenciais reais.

## Componentes

- `core/offline/offline_models.dart`: fases físicas, projeção visual, situação de
  envio e eventos com snapshots JSON profundamente imutáveis.
- `local_pesagem_store.dart`: `LocalPesagemStore` assíncrono e implementação em
  memória. Cada `save` deve gravar atomicamente leituras e outbox da mesma
  pesagem. Um adaptador de banco futuro deve cumprir essa garantia transacional.
- `offline_station.dart`: `OfflineStation`, um `ChangeNotifier` global injetável
  no `AppShell`. Serializa comandos locais e publica somente após o store
  aceitar o agregado. Não faz transporte. `load()` restaura agregados; a seleção
  visual pode ser definida com `selectWeighing`, sem ser alterada por acks de
  outras pesagens. O shell é dono da instância padrão; quem injeta outra é
  responsável por seu descarte.
- `pre_ticket_source.dart`: fontes e resolver sem transporte. O futuro adaptador
  remoto usará `GET /api/v1/pre-tickets`. Não foi presumido seu DTO. Pesagens e
  tickets usarão seus endpoints próprios da Libra, a definir no adaptador; não
  foram criadas rotas. Não se usa Saturno, Acessos ou SGV para pesar.
- `StationConnectionIndicator`: cabeçalho global, fora da navegação, com texto,
  ícone e cor; sempre aparece, inclusive nas demais abas.
- `LocalWeighingNotice`: substitui apenas o subtítulo da Pesagem quando existe
  agregado ativo, sem acrescentar altura à grade principal.

## Estado físico e sincronização são dimensões distintas

`WeighingPhase`: `nova`, `aberta`, `fechada`, `ticketPendente`, `concluida`.
`WeighingSyncStatus`: `semEventos`, `pendente`, `sincronizando`, `sincronizada`,
`erro`. O segundo é derivado dos eventos, evitando campo `status` ambíguo ou
informações divergentes armazenadas em dois lugares.

| Estado solicitado | Representação |
|---|---|
| NOVA | fase `nova`, sem eventos |
| ABERTA_LOCAL | fase `aberta`, abertura não confirmada |
| ABERTA_SINCRONIZADA | fase `aberta`, abertura confirmada |
| FECHADA_LOCAL | fase `fechada`, fechamento não confirmado |
| FECHADA_SINCRONIZADA | fase `fechada`, fechamento confirmado |
| TICKET_PENDENTE | fase `ticketPendente`, solicitação de ticket sem confirmação |
| CONCLUIDA | fase `concluida`, última solicitação de ticket confirmada |
| ERRO_SINCRONIZACAO | `syncStatus == erro`, mantendo a fase física e leituras |

`LocalWeighingState` fornece as sete projeções visuais da tabela. Erro é uma
situação de envio, não uma fase que faz esquecer que o veículo já foi pesado.
Confirmar uma abertura atrasada não regride uma pesagem fechada para aberta.
Concluída significa confirmação da última operação de ticket, inclusive seu
cancelamento; o tipo do evento conserva essa distinção. Cancelar ticket não é
cancelar pesagem, reabrir operação nem acionar cancela.

## Eventos e ordem

Cada `SyncEvent` tem `idLocal`, `tipoEvento`, `idPesagemLocal`, `payload`,
`status`, `dataHoraCriacao`, `tentativas`, `ultimoErro`, `idRemoto`, `ordem` e
`dependeDe`. A fila é parte do agregado em vez de um segundo store independente,
para permitir atomicidade entre a alteração física e seu evento.

Fluxo: ABERTURA → FECHAMENTO → REGISTRO_TICKET → CANCELAMENTO_TICKET (opcional).

- Abertura/fechamento geram eventos pendentes, mesmo estando online.
- Fechar localmente é permitido com abertura ainda pendente, inclusive offline.
- Solicitar ticket exige fechamento local; enviá-lo exige fechamento confirmado.
- Cancelamento de ticket exige registro de ticket confirmado; não inventa
  reabertura ou novos ciclos de emissão nesta etapa.
- `readyEvents` libera somente o primeiro pendente de cada pesagem, se seu
  predecessor existe, possui o tipo esperado e está confirmado. Evento em envio,
  com erro ou predecessor ausente bloqueia os sucessores. A sequência não depende
  de timestamps; pesagens independentes não precisam bloquear umas às outras.
- `beginEvent` só aceita evento pronto e incrementa tentativas. **Iniciar envio
  não confirma nada.** `confirmEvent` exige envio iniciado, ID remoto não vazio
  e predecessores confirmados. Repetir o mesmo ack é idempotente; outro ID é erro.
- `failEvent` guarda a falha sem descartar dados ou agendar retry. Não existe
  botão, loop ou comando de retry real; reconciliação será outra etapa.
- A fábrica padrão de IDs é provisória, única nesta execução. `idFactory` é
  injetável e rejeita colisões. Um store durável precisará de identidade adequada
  entre processos/estações; nenhum identificador de produção foi presumido.

Payloads são dados locais de domínio, **não bodies HTTP presumidos**. Leituras
devem ser positivas e finitas; zero de indicador desconectado não vira captura.
Não foram implementados cálculo de líquido, tara, descontos, regras de repesagem
ou contratos fiscais, nem promessas de idempotência do backend.

## Conectividade, progresso e queda da rede

O estado padrão é **Offline**, sem afirmar conectividade não observada. O
adaptador futuro deverá alimentar `setConnection` explicitamente. Não há detecção
de rede. Online usa verde, Offline âmbar e Sincronizando azul/ícone de sync,
sempre com texto. Pendências contam todos os eventos não confirmados, inclusive
os bloqueados, em envio e com erro.

Para testar um lote, mudar de Online para Sincronizando captura os IDs pendentes
naquele instante. O indicador mostra confirmados/total desse lote fixo, por
exemplo `Sincronizando · 2/3`. Novos eventos entram na contagem de pendências e
aguardam um próximo lote. Finalizar o lote e voltar a Online é explícito: nenhum
callback inicia envio ou transita automaticamente para sucesso.

Cair Offline preserva um envio em curso até confirmação/falha explícita do
adaptador. Voltar Online não confirma, não reinicia e não duplica esse envio.
Ack de resultado já iniciado pode chegar após a queda; erro bloqueia a cadeia.

## Pré-ticket e abertura offline

`PreTicketResolver` escolhe origem `remota` quando há conectividade
(Online/Sincronizando) e adaptador remoto configurado. Offline consulta
**somente** a fonte local. Sem adaptador remoto, consulta a fonte local também
online. Ausência local retorna `ticket == null`; nenhum pré-ticket é criado.
O resolver não preenche cache nem inventa fallback para resposta remota vazia.

`create` exige um `KnownPreTicket` previamente conhecido pelo chamador. Nova
abertura offline exige uma `OfflineOpeningPolicy` injetada que confirme a
suficiência dos dados locais. A política padrão não autoriza novas aberturas
offline, pois os critérios do piloto ainda não foram decididos. O mecanismo
aceita uma política que permita a operação, sem depender de SGV. Os testes usam
política permissiva apenas com fixtures conhecidas; não é uma regra de produção.

Uma pesagem já aberta pode fechar offline sem reavaliar política de nova
abertura. Seu fechamento entra pendente na fila e continua atrás da abertura.

## Limite da integração visual nesta etapa

O shell compartilha uma única `OfflineStation` entre as abas. O cabeçalho observa
conectividade/contagem/progresso e a página reflete o agregado ativo. Os testes
injetam a estação e exercitam abertura/fechamento/acks/falha por comandos locais.

O formulário e o botão Salvar da prévia antiga **continuam sendo demonstração**;
não são convertidos automaticamente em eventos de domínio. A consulta visual
antiga continua com seus exemplos mock e não é tratada como resposta Libra ou
cache real. A abstração de pré-ticket é independente e foi testada sem fabricar
resultado desconhecido. Isso evita usar uma prévia automática de zero, uma senha
mock ou um exemplo de operação como se fossem autorização/dados reais do piloto.
Conectar consulta/capturas/ticket à máquina de estados, com dados/políticas
oficiais, permanece uma etapa posterior de integração do fluxo.

Esta base permite testar o ciclo offline em memória; não deve ser confundida com
uma estação pronta para continuidade operacional após queda/reinício. SQLite,
persistência definitiva, retry, HTTP/background e hardware permanecem fora.
