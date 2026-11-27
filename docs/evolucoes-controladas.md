# Evoluções controladas — UI, domínio, estados e mocks

## Escopo e componentes preservados

Reutilizados SettingsSection, SettingsFields, SettingsToggle, VisualCard,
VisualField, ReadOnlyValueField, diálogos de pesagem, PesagemActionScope e
PesagemActionDispatcher. Sem redesenho, novos pacotes, HTTP, endpoints, hardware,
banco, AD ou commit. A fila offline e a conectividade da estação não foram
vinculadas ao estado de comunicação do indicador.

## PRJ 2524 — Indicadores Toledo via porta COM

A Pesagem recebe a saída contínua padrão dos Toledo IND560 e IND570 por uma
porta COM do Windows. O adaptador recebe bytes em um isolate, a camada de
protocolo delimita e valida os frames e o serviço publica o estado do
indicador para o painel, o F12 e a política do F11. A fila da estação continua
com seu próprio estado de conectividade.

### Configurar e operar

1. Em **Configurações Gerais**, selecione a unidade e o ambiente da estação.
   Salve a aba Geral caso também queira conservar a seleção do ambiente ao reabrir.
2. Em **Indicadores de Peso**, crie ou selecione a instalação, informe o nome,
   escolha **Mettler Toledo IND560** ou **IND570** e selecione **Serial RS232**.
   Use **Atualizar portas COM** e selecione a porta do Windows. O canal interno
   do terminal é um campo separado. Uma COM salva que esteja ausente fica
   marcada como indisponível.
3. Uma nova instalação Toledo preenche 4800 baud, paridade Even, 7 bits de
   dados, 2 bits de parada e fluxo None. Confirme os valores no equipamento.
   Em **Configuração serial avançada** ficam protocolo, checksum, escala,
   canal, interface, timeout (2000 ms) e reconexão (3000 ms). Para a balança
   da captura `leitura_peso.txt`, use MT Continuous e **Captura ComTool
   (kg inteiros)**, que ativa o checksum. Confirme o peso contra o visor
   antes de habilitar a captura operacional. Instalações salvas conservam
   os parâmetros e a escala selecionados.
4. Use **Testar conexão**. Um teste pode mostrar a porta aberta com zero bytes
   ou com bytes que não formam frames válidos. O resultado inclui parâmetros,
   contadores, horário, peso, estabilidade e amostra de até 96 bytes em HEX e
   ASCII escapado. Para uma COM ocupada, feche ComTool, Portaria ou outro leitor
   e repita. Alguns drivers retornam o mesmo código Win32 5 para porta ocupada
   e acesso negado.
5. Selecione **Real**, escolha o **Indicador operacional**, marque a instalação
   como ativa e salve. O perfil local é vinculado ao par ambiente/unidade.
   A estação recupera a última unidade salva na área de indicadores para o
   ambiente. **Simulado** mantém a apresentação anterior de demonstração.

Em modo real, o painel mostra o valor na unidade original e indica movimento.
O F12 exige peso bruto, estável, recente e positivo após conversão em kg.
O zero continua sendo uma leitura válida para a comunicação. O valor inteiro
em kg, seu horário e sua origem ficam congelados na confirmação da sessão.
Se a sessão perder comunicação ou mudar de configuração durante a confirmação,
cancele e faça nova captura. A reconexão é automática. O F11 continua usando as
permissões e a autorização existentes. Com peso manual desabilitado, a
contingência fica disponível após a perda de comunicação. Peso em movimento
continua contando como comunicação.

### Protocolo e frame de referência

O IND560 Technical Manual, apêndice D, tabelas D-3 a D-6, e o IND570 User's
Guide, revisão 16, § C.6.1, tabelas A-6 a A-9, descrevem o mesmo frame de
17 bytes. O checksum opcional ocupa a posição 18. A palavra A dá a escala
decimal. A palavra B informa bruto/líquido, sinal, faixa, movimento e referência
de zero. A palavra C complementa a unidade e indica o modo de dados expandidos.
O peso indicado e a tara são lidos de campos separados. O checksum é o
complemento de dois da soma de STX até CR, limitado a sete bits.
[Manual técnico IND560](https://icdn.tradew.com/file/201606/1569362/pdf/7772233.pdf) ·
[Guia oficial IND570](https://www.mt.com/dam/product_organizations/industry/IndustrialTerminals/30205308_16_MAN_UG_IND570_EN.pdf)

Frame construído a partir dessas tabelas e usado na regressão automatizada.

```text
02 2B 30 20 20 35 37 30 30 39 20 20 20 20 20 30 0D 01
<STX>+0  57009     0<CR>\x01
```

`2B` seleciona uma casa decimal, `30` indica bruto positivo e estável em kg,
`20` fixa a interpretação de unidade pela palavra B e `01` é o checksum.
O painel exibe **5700,9 kg**. O F12 usa **5700 kg**. As unidades aceitas são kg,
lb, g e t métrica. A conversão para kg trunca a fração com aritmética inteira.
Sobrecarga, falta de referência de zero, unidades sem conversão implementada,
status inválido e modo expandido ×10 bloqueiam a captura. Formatos estendido,
template, sob demanda e SICS ficam fora da leitura operacional desta entrega.
O teste TCP/IP continua disponível para verificar a conexão TCP.

O perfil ComTool é específico da instalação capturada. Ele lê os seis bytes
do peso diretamente em kg inteiros quando o status A é `0x29` e o checksum
confere. Assim, o primeiro frame do arquivo representa 30 kg. A escala
padrão usada pelo aplicativo continua interpretando `0x29` com fator ×10.
O frame de 5700,9 kg acima usa **Escala padrão Toledo**. A regressão lê os
bytes da captura em `leitura_peso.txt` na raiz ou no caminho indicado por
`TOLEDO_COMTOOL_FIXTURE`.

### Bancada Windows com com0com

1. Use um par **com0com** já disponível e autorizado pela TI, por exemplo
   COM12/COM13. Configure a aplicação em uma ponta e o transmissor na outra,
   com os mesmos parâmetros. Deixe uma ferramenta por porta.
2. Para verificar o simulador instalado, configure sua ponta para 4800,E,7,2
   quando compatível, informe e confirme um peso. O artefato
   `simulador-ind570.jar` inspecionado, SHA-256 iniciado em `52e353e041d6`,
   envia `PB:…kg PL:…kg T:…kg<CR><LF>` ao confirmar. No diagnóstico do Flutter,
   espere bytes recebidos, ASCII com `PB:` e zero frames válidos. O F12 fica
   bloqueado em modo Real com esse formato.
3. Use a regressão abaixo para transmitir o MT Continuous padrão no mesmo
   par virtual. Feche o simulador instalado e a aplicação antes de rodá-la,
   pois o teste abre as duas pontas. Ajuste os nomes para o seu par.

```powershell
$env:BALANCA_SERIAL_VIRTUAL_RX = 'COM12'
$env:BALANCA_SERIAL_VIRTUAL_TX = 'COM13'
flutter test test/windows_serial_virtual_test.dart --reporter expanded
```

4. Para verificar o F12 pela interface, deixe o Flutter em modo Real com
   COM12, escala padrão Toledo e checksum ativo. Execute este transmissor somente na outra ponta
   do par virtual. Ele mantém o peso de referência por cerca de 20 segundos.

```powershell
$port = [System.IO.Ports.SerialPort]::new('COM13', 4800, 'Even', 7, 'Two')
[byte[]]$frame = 0x02,0x2B,0x30,0x20,0x20,0x35,0x37,0x30,0x30,0x39,0x20,0x20,0x20,0x20,0x20,0x30,0x0D,0x01
try {
    $port.Open()
    for ($i = 0; $i -lt 100; $i++) {
        $port.Write($frame, 0, $frame.Length)
        Start-Sleep -Milliseconds 200
    }
} finally {
    $port.Dispose()
}
```

   Exercite zero, movimento, estabilização e bruto/líquido com os frames
   das regressões. Pare a transmissão para verificar timeout, bloqueio do
   F12, contingência autorizada pelo F11 e reconexão ao retomar. Repita com
   a COM ocupada e com uma troca de configuração salva. A homologação
   física é uma etapa separada.

### Indicador físico Toledo

1. Use bancada ou janela acordada com a operação. Confirme modelo, versão
   do manual, saída MT Continuous padrão, unidade, checksum, interface
   elétrica (RS-232, RS-422 ou RS-485), pinagem e adaptador compatível.
2. Conecte o adaptador à estação e identifique a COM do Windows. Se for
   USB-serial, use o driver adequado ao adaptador. Libere a COM de
   ferramentas que estejam usando a porta na bancada.
3. Configure no Flutter exatamente os parâmetros do terminal. Rode
   **Testar conexão**, confira HEX, contadores, unidade, bruto e estabilidade
   com o visor, então salve o modo Real. A captura é receptora passiva.
4. Compare zero, decimal e cargas estáveis e em movimento. Confirme que
   o F12 grava o valor truncado em kg na sessão e recusa peso líquido,
   instável ou desatualizado. Depois valide perda de comunicação e
   reconexão. Registre frames físicos para regressão, se autorizado.
   [Instalação IND560](https://www.mt.com/mt_ext_files/Editorial/Generic/5/IND560_Install_Instructions_Editorial-Generic_1129137712195_files/IND560_Installation_Manual_EN.pdf) ·
   [Instalação IND570](https://www.mt.com/dam/ind/IND_PDF/2024/ind570%28xx%29/ind570/Installation-Manual/30205319_P_MAN_IM_IND570_ML.pdf)

### Dependências e distribuição

`win32` 6.4.0 (BSD-3-Clause) reutiliza o FFI já presente e chama a API do Windows
diretamente. `ffi_leak_tracker` 0.1.2 (BSD-3-Clause) é transitiva. O isolate
permite leitura assíncrona para o Flutter e mantém
abertura exclusiva, configuração da linha e fechamento sob o mesmo dono. A
alternativa `serial_port_win32` também se baseia em Win32. O
`flutter_libserialport` tem licença MIT e inclui a biblioteca C libserialport
(LGPL). O adaptador Win32 utiliza DLLs do próprio sistema para COM.
[win32](https://pub.dev/packages/win32) ·
[serial_port_win32](https://pub.dev/packages/serial_port_win32) ·
[flutter_libserialport](https://pub.dev/packages/flutter_libserialport/license) ·
[libserialport](https://github.com/sigrokproject/libserialport/blob/master/COPYING)

Distribua a pasta `build/windows/x64/runner/Release` inteira. O cliente
precisa de Windows x64 com a API `GetCommPorts` (Windows 10 1803 ou posterior),
eventual driver USB-serial e, conforme a instalação, o Microsoft Visual C++
Redistributable x64. O Flutter SDK e o Visual Studio são usados no build.
[Build e distribuição Flutter](https://docs.flutter.dev/platform-integration/windows/building) ·
[GetCommPorts](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getcommports) ·
[Visual C++ Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)

## Modelos e instalações de indicadores — etapa anterior ao PRJ 2524

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
