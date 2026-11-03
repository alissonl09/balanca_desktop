# Configurações e Relatórios: interface local

Esta etapa não acessa SGV, Libra-API, equipamentos, OCR, serviço de voz, impressoras,
arquivos de imagem, bancos ou exportadores. Não há novos endpoints ou dependências.

## Pesagem

`VisualFieldLabel` concentra tipografia dos rótulos. Placa e Carreta, inclusive
no modo de seleção do bitrem, usam o mesmo componente, altura e espaçamento.
Os estados e eventos da consulta não foram alterados.

## Estado e Configurações Gerais

`SettingsState` e os modelos de impressão ficam em `settings_models.dart`.
O shell mantém uma instância durante a sessão para conservar escolhas ao navegar.
Alterações são imediatas no rascunho local. Salvar configurações valida os valores e
confirma que permanecem somente na sessão; não persiste nem aplica integrações.

`settings_mock_data.dart` separa unidades, cancelas e impressoras de demonstração.
As unidades são 4 - JAPY, 1 - MATRIZ e 7 - ARMAZÉM; o estado guarda o código inteiro.
Ambiente aceita somente Produção, Homologação e Desenvolvimento, sem mudar URLs
ou configurações reais. A demonstração inicia em Homologação.

As abas são Configurações Gerais, Gestão de Veículos (condicional), Impressão,
Indicadores de Peso e Modelos de Indicadores. As duas últimas entradas existentes
foram conservadas; a base anterior tinha somente sua apresentação visual, sem
campos ou comunicação implementados.

Ativar Integrado ao sistema SGV acrescenta imediatamente Gestão de Veículos.
Desativar remove a aba e, se necessário, retorna para Gerais. Os valores específicos
são conservados no rascunho, sem qualquer efeito em equipamentos.

## Gestão de Veículos

Cancelas habilita a seleção por identificador de uma cancela de entrada e outra de
saída. As opções são Entrada 01, Saída 01 e Apoio, todas simuladas. Desativar oculta
as seleções. Semáforo, Display de Informações e Serviço de Voz guardam somente
Ativo/Inativo.

OCR habilita endereço/host, porta TCP numérica entre 1 e 65535 e token. O token
inicia oculto e possui controle de exibição. Ele existe apenas na memória desta
interface, sem comunicação, autenticação real ou armazenamento definitivo.

## Impressão

`printing_settings.dart` concentra as seções e `print_layout_preview.dart` conserva
a miniatura da logomarca configurada. As prévias Ticket/A4 agora usam o modelo e
os layouts descritos em [Ticket de Pesagem](ticket-pesagem.md), sem impressão física.

A logomarca padrão reutiliza o asset existente `logo-topo.svg`. Alterar imagem
oferece uma imagem de demonstração com ícone Material; Restaurar padrão desfaz
a escolha. A seleção de arquivo local e seu tratamento serão conectados depois.

Há quatro perfis de impressoras simuladas, sem consulta ao Windows:

| Perfil | Status simulado | Tipo | Conexão |
|---|---|---|---|
| Ticket USB | Online | Ticket/Cupom, Local | USB001 |
| Ticket Rede | Offline | Ticket/Cupom, Rede | 192.168.1.50 |
| A4 USB | Online | A4, Local | USB002 |
| A4 Rede | Indisponível | A4, Rede | 192.168.1.60 |

Tamanho, origem e orientação do papel pertencem ao perfil selecionado. O estado
conserva ajustes separadamente por impressora. Impressora A4 de contingência é
uma seleção separada; nenhuma falha é detectada ou tratada automaticamente.

Entrada e Saída guardam preferências de emissão. Cópias aceita de 1 a 10.
Ticket Windows guarda somente um estado reservado, sem regra de impressão.
Cabeçalho e Rodapé compartilham os textos com as duas prévias. Um formatter limita
cada valor a três linhas explícitas, inclusive em colagem, normaliza CRLF/CR e
atualiza o contador 0/3 a 3/3. Quebra visual, papel e paginação definitivos dependem
do layout oficial que será fornecido posteriormente.

## Relatórios

## Indicadores de Peso

`IndicatorModel` descreve o equipamento e as capacidades declaradas pelo perfil:
transportes permitidos, parâmetros seriais e protocolos/formats de saída. O catálogo
é extensível; modelos sem documentação permanecem sem capacidades selecionáveis.
`IndicatorInstallation` guarda cada instalação local, incluindo nome, modelo,
transporte, protocolo e parâmetros específicos. `toJson`/`fromJson` preservam os
valores configurados para serialização local. Os parâmetros reais da instalação
prevalecem sobre referências e exemplos; 1701 é apenas uma referência do perfil
IND570.

Transporte significa o caminho físico (Serial ou TCP/IP). `IndicatorTransport`
recebe bytes; `IndicatorDriver` e seu parser interpretam o protocolo do modelo.
`IndicatorReading` entrega peso, unidade, estabilidade opcional, estado de
comunicação, instante da leitura e erro sem expor o transporte à Pesagem. Peso zero
é válido e não sinaliza desconexão. Sem parser documentado, bytes não são
convertidos em peso. TCP usa socket assíncrono; o backend Serial Windows está
preparado por interface, mas ainda depende de uma dependência apropriada.

O diagnóstico TCP abre e fecha uma conexão temporária e não dispara ações de
pesagem. Não comprova que o indicador enviou um frame válido. O diagnóstico Serial
retorna indisponibilidade até haver backend. A configuração da instalação é um
rascunho local da estação, sem chamada à Libra-API.

O menu usa `Icons.assessment_outlined` entre Cadastros e Configurações.
`report_catalog.dart` define doze opções e seus filtros de apresentação:

- Pesagens por Período;
- Pesagens por Veículo;
- Pesagens por Motorista;
- Pesagens por Transportadora;
- Pesagens por Remetente / Destinatário;
- Pesagens por Produto / Item;
- Pesagens em Aberto;
- Pesagens Finalizadas;
- Divergências de Peso;
- Pesagens Manuais;
- Histórico de Operações por Placa;
- Movimento Diário da Balança.

Selecionar um card abre a área correspondente de filtros e resultados futuros.
Datas usam calendário; unidade usa as opções mock; situação usa lista fixa.
Outros filtros são critérios textuais locais. Cada opção conserva seu rascunho
enquanto a página está aberta. Não são contratos ou parâmetros de API.

Gerar relatório, Imprimir e Exportar ficam desabilitados com explicação visível.
Não existem resultados fictícios, regras de tolerância, consultas, PDF, Excel ou
impressão real. O catálogo descreve a identificação futura das pesagens manuais
e os totais previstos no movimento diário, sem calcular valores.

Configurações e Relatórios utilizam rolagem vertical na área de conteúdo do shell.
Abas possuem rolagem horizontal; cards e campos reorganizam colunas conforme
a largura disponível, preservando a legibilidade.

## Próximas conexões

Ficam pendentes fontes reais de unidades/equipamentos/impressoras, persistência
das configurações, proteção definitiva do token, aplicação dos ambientes,
integrações SGV/OCR/voz, capacidades/padrões do Windows, desenho oficial dos
layouts, envio à impressora, tratamento de contingência e camada de consultas,
resultados e exportação dos relatórios. Nenhum desses serviços foi simulado como
se estivesse operacional.
