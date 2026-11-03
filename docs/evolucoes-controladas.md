# Evoluções controladas — UI, domínio, estados e mocks

## Escopo e componentes preservados

Reutilizados SettingsSection, SettingsFields, SettingsToggle, VisualCard,
VisualField, ReadOnlyValueField, diálogos de pesagem, PesagemActionScope e
PesagemActionDispatcher. Sem redesenho, novos pacotes, HTTP, endpoints, hardware,
banco, AD ou commit. A fila offline e a conectividade da estação não foram
vinculadas ao estado de comunicação do indicador.

## Modelos e instalações de indicadores

IndicatorModel define código, fabricante, modelo, descrição, ativo, observação,
capacidades Serial/TCP e protocolos. IndicatorConfiguration mantém catálogo e
instalações separadas em memória. É possível cadastrar/editar modelos. Uma
instalação depende de um modelo existente; trocar modelo limpa parâmetros que
poderiam pertencer ao equipamento anterior. Instalação ativa incompleta ou
incompatível não passa pela validação ao salvar a aba Indicadores de Peso.

SerialCapabilities limita baud rates, bits, paridades, flow control e interfaces
por canal. Porta COM da estação é texto informado, sem enumeração. Canal do
terminal (COM1/2/3/4) é separado da porta COM do Windows. TcpCapabilities controla
suporte a DHCP e referência documental da porta; a instalação guarda IP/host,
máscara, gateway, porta e timeout. Timeout é positivo e porta deve estar entre
1 e 65535. Não há socket, teste físico ou parser. Diagnóstico permanece inativo.

Parâmetros IND570 fornecidos no pedido:

- Baud: 300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200.
- Data Bits: 7/8; Parity: None/Odd/Even; Flow: None/XON-XOFF.
- COM1/COM3: RS-232/422/485; COM2/COM4: RS-232. COM4 depende da instalação.
- TCP/IP e DHCP preparados. 1701 é referência primária, não default obrigatório;
  uma porta secundária/física diferente é permitida.
- Saídas: MT Continuous / Continuous Output, Continuous Template e Demand Output.
  MT Continuous é o candidato para a futura captura contínua; nada é interpretado.
- Stop Bits não foi criado como parâmetro universal. O cenário 4800,E,7,2 não
  virou default. Valores de Serial não são preenchidos automaticamente.

IND560 permanece disponível sem capacidades inventadas: PLC Manual é insuficiente.
G10K e Tolflux 9700 também aguardam documentação para fechar capacidades. Não
herdam regras do IND570. O cadastro permite informar capacidades posteriormente.

IndicatorDriver é contrato de driver por modelo, com stream de IndicatorReading
normalizada (peso, unidade, estabilidade, conexão, instante e erro). Não existem
implementações ToledoInd570Driver/ToledoInd560Driver/GenovaG10KDriver/Tolflux9700Driver
nesta etapa. A Pesagem recebe estado normalizado, sem fabricante ou transporte.
MemoryIndicatorState começa desconectado, sem leitura inventada. A captura
automática anterior continua em demonstração/zero: não foi ligada a hardware.

## Pesagem manual e permissões

Configurações Gerais inclui Habilitado/Desabilitado. ManualWeighingPolicy aplica
`(manualHabilitado || !indicadorConectado) && realizarPesagem && utilizarPesoManual`.
Isso controla botão/F11 pela mesma ação. Estação offline e indicador desconectado
são conceitos separados. Configuração desabilitada com indicador conectado bloqueia
F11; perda de comunicação libera contingência somente a perfil compatível.

O modal mantém autenticação provisória já existente e acrescenta justificativa
obrigatória, rejeitando vazio/espaços. Valida também a permissão do autorizador.
Depois vêm entrada do peso e confirmação. Cada tentativa pede uma nova autorização;
senha não é guardada no domínio. Justificativa é mantida no preview, ticket e
ManualReadingRecord por captura confirmada. A segunda leitura não apaga a razão
da primeira. Cancelar não registra captura. Não é justificativa de tolerância nem
de cancelamento. Permissões são rechecadas antes da confirmação da captura.

Perfis iniciais:

| Código | Perfil | Defaults |
|---|---|---|
| 0 | Master | Todos; acesso total preservado |
| 1 | Administrador | Todos inicialmente; administração de sistema/perfis/usuários |
| 2 | Supervisor de Balança | Pesagem, usar/autorizar manual, cancelar ticket, liberar divergência, reimprimir, editar dados manuais abertos |
| 3 | Líder de Operação | Pesagem, liberar divergência, reimprimir; sem autorizar manual/cancelar ticket |
| 4 | Operador | Pesagem e reimpressão |

A aba Permissões tem matriz de checkboxes por perfil e grupos Pesagem, Tickets,
Cadastros, Relatórios, Configurações e Usuários. Defaults são parametrizáveis;
Master mantém total. PermissionState centraliza concessões e atribuições e impede
alterações sem a permissão correspondente. UserDirectory é abstração de pesquisa
por nome/matrícula; os usuários atuais são mocks tipados, sem senha ou AD. Perfil é
selecionado por LOV. O contexto padrão continua Administrador para preservar a
demonstração existente; não foi criado login corporativo nem troca de sessão.

Foram ligados os pontos já operacionais: Pesagem, Peso Manual, salvar edição,
prévia/impressão, acesso aos menus, abas de configuração, ações dos cadastros,
administração da matriz e atribuição. Recursos ainda não implementados, como
cancelar ticket, corrigir/repesar e exportar, têm permissão preparada na matriz,
sem uma operação fictícia. A regra de Salvar continua sem tocar pesos ou fase.

## Relatórios

O catálogo tem nove relatórios: Pesagens, Tickets, Itens, Remetentes/Destinatários,
Transportadoras, Motoristas, Depósitos, Unidades e Operações. Pesagens é a consulta
operacional única, com todas as variações como filtros: datas, placa, carreta,
motorista, transportadora, parte, produto, unidade, operação, documento, status,
manual, divergência e operador. Tickets tem filtros independentes de número de
ticket e pesagem, placa, datas, tipo, documento, emissor e status. Status separa
pesagem aberta/finalizada, ticket emitido/cancelado e cadastro ativo/inativo.
Gerar/Imprimir/Exportar continuam desabilitados sem camada real de resultados.

## Controle de acesso

SGV desabilitado oculta o Controle de acesso. Habilitado mostra o card na coluna
lateral, abaixo de Veículos; os componentes seguem Gestão de Veículos. A barra
de ações fica na área principal, abaixo dos painéis de peso.

AccessControlState mantém entrada/saída independentes, GateState
closed/open/moving/error. Um pequeno botão de simulação aparece
somente em debug ou ambiente Desenvolvimento e abre controles em modal separado.
Não há comandos de equipamento. Fechamento mostra vermelho vivo/verde apagado;
abertura mostra verde vivo/vermelho apagado. Movimento/erro conservam vermelho.
Semáforo pode aparecer mesmo sem o desenho de cancela, se habilitado separadamente.

GateVisual anima a haste em uma caixa de 100x70 com recorte: toda a trajetória
fica reservada, sem sobrepor títulos ou textos. InformationDisplay usa a mesma
fonte digital do peso e move da direita para a esquerda o texto configurado
localmente, com COOXUPÉ como padrão. Gestão de Veículos seleciona
explicitamente os IDs dos equipamentos de Entrada e Saída. GateEquipmentSource
fornece opções tipadas em memória e pode ser substituído por configuração real.
O mesmo ID não pode ocupar os dois papéis. AccessControlState vincula cada papel
ao ID selecionado; simulação e semáforo acompanham esse equipamento. O botão de
inversão troca os IDs de Entrada e Saída apenas quando Cancelas está habilitado,
preservando o estado por ID. Entrada fica à esquerda e Saída à direita, com a
haste de Saída espelhada pelo desenho.
OCR e Serviço de Voz continuam como configurações, sem integração real.

## Compatibilidades e limites preservados

- TicketSession ainda atende a prévia existente com um ticket representativo;
  não foi substituído por repositório 1:N. O relatório de Tickets é independente
  e não presume Pesagem = Ticket. A geração/consulta real de vários tickets por
  pesagem aguarda contrato/camada de dados. EPA BAG não foi inventado.
- CadastrosMemory ainda usa remoção da lista temporária como antes. A permissão
  de inativação/exclusão lógica está preparada; exclusão lógica persistente não
  foi simulada nem substituiu silenciosamente o comportamento existente.
- Cancelamento de ticket é conceito de permissão/status, sem exclusão física e
  sem nova implementação de cancelamento.
- Tudo é memória, formulário ou mock. Não há conexão serial/TCP, parser, SGV,
  autenticação corporativa, AD, COM real, criptografia, persistência ou driver físico.

## Manifesto de arquivos

Criados:

- lib/core/indicators/indicator_models.dart
- lib/core/indicators/indicator_driver.dart
- lib/core/permissions/permission_models.dart
- lib/features/access_control/access_control_state.dart
- lib/features/access_control/access_control_panel.dart
- lib/features/configuracoes/indicator_settings.dart
- lib/features/configuracoes/permissions_settings.dart
- lib/features/pesagem/manual_weighing_policy.dart
- test/controlled_evolution_models_test.dart
- test/controlled_evolution_widgets_test.dart
- docs/evolucoes-controladas.md

Alterados:

- lib/app/app_shell.dart
- lib/features/cadastros/cadastros_page.dart
- lib/features/cadastros/cadastro_panel.dart
- lib/features/configuracoes/configuracoes_page.dart
- lib/features/configuracoes/settings_models.dart
- lib/features/configuracoes/settings_widgets.dart
- lib/features/pesagem/pesagem_page.dart
- lib/features/pesagem/weighing_dialogs.dart
- lib/features/pesagem/weighing_preview.dart
- lib/features/pesagem/weight_panels.dart
- lib/features/ticket/ticket_session.dart
- lib/features/relatorios/report_catalog.dart
- lib/features/relatorios/relatorios_page.dart
- test/pesagem_operational_flow_test.dart
- test/settings_reports_test.dart
- test/ticket_test.dart
- test/widget_test.dart
- docs/pesagem-fluxo-operacional.md

## Validação

Os testes novos cobrem capacidades/modelos, validação da instalação, restrições
IND570, tipos de saída, permissões/defaults, atribuição, contingência, motivo de
cada leitura, relatórios separados, visibilidade SGV, estados independentes,
simulação, vínculo explícito dos equipamentos e animação/layout em 1920x1080, 1366x768, 1280x680 e 600x800.
A suíte existente continua cobrindo atalhos, TAB, salvar sem alterar Peso 1,
modais, offline, cadastros e prévias de ticket.

Na etapa inicial deste documento, `dart format lib test`, `flutter analyze
--no-pub` e `flutter test --no-pub` concluíram com 147 testes aprovados. Após
a configuração explícita das cancelas, a validação final foi repetida: análise
sem apontamentos e **149 testes aprovados**, incluindo os dois cenários novos
de vínculo e simulação dos equipamentos. Nenhum commit foi realizado.
