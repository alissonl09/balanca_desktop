# Ticket de Pesagem: modelo e prévias

Configurações > Impressão oferece **Visualizar Ticket** e **Visualizar A4**.
Ambos usam a mesma instância de `TicketPesagem` dentro da prévia e permitem
alternar formato sem refazer mapeamento ou cálculos. Não há impressão física,
Windows Print Spooler, descoberta de impressoras ou fallback automático.

## Separação do código

- `ticket_pesagem.dart`: modelo Dart independente de Flutter, enum de origem do
  peso e dados do cabeçalho/rodapé. Listas de documentos, emissores e textos são
  imutáveis. Campos sem origem definida são opcionais.
- `ticket_session.dart`: ponte somente em memória entre Pesagem e Configurações.
- `ticket_mapper.dart`: adaptação do estado disponível para o modelo, incluindo
  configurações de Impressão e código/descrição da unidade simulada.
- `ticket_traceability.dart`: função substituível de composição do identificador
  e codificação Code 39, sem dependências nativas ou pacotes adicionais.
- `ticket_sections.dart`: seções visuais, datas/números, texto integral e barras.
- `thermal_ticket.dart`: cupom de largura estreita e altura variável.
- `a4_ticket.dart`: cabeçalho maior e dados reorganizados em duas colunas.
- `ticket_preview.dart`: janela limitada à área útil, rolagem interna e escolha
  de formato/fonte dos dados.
- `ticket_mock_data.dart`: três exemplos tipados e explicitamente simulados.

## Dados mapeados

O número é o mesmo da Pesagem atual (318875 na demonstração existente).
São mapeados documentos múltiplos, tipo do documento, placas do cavalo/carreta,
motorista, transportador, emissores múltiplos, depósito, embalagem, peso N.F.,
Observação, os quatro pesos do resumo e operador, quando preenchido no estado.
Os documentos/emissores atuais, apresentados como texto na interface, são
separados por ponto e vírgula/quebra de linha. Esta é uma adaptação da UI atual,
não um contrato de backend.

Produto/Item, Remetente, Destinatário, Cidade, UF, Quantidade, Tipo da Operação,
referência XFER/OC e identificação formal da empresa continuam opcionais, sem
fonte inventada. Linhas ausentes são omitidas. O modelo/layout já as aceita se
uma origem real vier a fornecê-las. A identificação da unidade utiliza a escolha
local existente; a logomarca e até três linhas de cabeçalho/rodapé vêm de Impressão.

## Pesos, abertura e fechamento

O ticket não calcula líquido, seco ou regras da operação: consome os valores do
estado. O zero inicial do resumo é um placeholder sem captura; não cria Peso Final.
Pesagens com valor positivo ou data de captura explícita são consideradas disponíveis.
Datas desconhecidas permanecem ausentes, nunca substituídas pela data de emissão.

Sem segunda pesagem, a coluna Saída fica sem valores e o comprovante identifica
Abertura de Peso. Com uma segunda captura disponível, identifica Fechamento de Peso.
Essa identificação visual do ticket não altera a heurística anterior do modal de
confirmação nem as regras reais da aplicação.

O fluxo manual existente guarda o instante em que o peso foi informado, mas só
disponibiliza a captura ao ticket após confirmar Salvar Pesagem. A captura preenche
Entrada quando não há peso inicial; se já houver peso inicial, preenche Saída.
Não produz líquido enquanto o resumo não o tiver calculado. A tela mantém agora
fase aberta/fechada e duas leituras em memória após confirmação manual. O mapeador
não duplica captura cujo instante já aparece no resumo. Não há avanço ou
persistência real na Libra-API. Salvar metadados não cria uma nova captura.

Uma captura manual mostra **Pesagem Manual** e o autorizador do fluxo existente.
Justificativa é opcional e atualmente não é solicitada nesse fluxo: fica ausente,
sem texto fictício. Autorizador não é tratado automaticamente como Operador.
Confirmar com o indicador desconectado não apaga uma captura manual já disponível.

A sessão conserva o estado ao navegar para Configurações e voltar. Alterar a
composição ou limpar/Nova Pesagem invalida a captura confirmada anterior.
Cancelar o fluxo não confirma dados novos. Tudo permanece somente em memória.

## Apresentação

O térmico tem largura de prévia de 340 pixels lógicos; o A4 usa 720. Textos crescem
em altura, sem reticências ou redução de fonte para esconder informações.
Entrada e Saída compartilham data, hora e peso; o líquido tem destaque maior e Kg
associado. Peso Seco, Observações e Operador aparecem apenas quando disponíveis.
Emissão do comprovante usa seu próprio instante, separado da captura.

O A4 é uma preparação visual para contingência, não um documento paginado enviado
ao Windows. Conteúdo extenso pode aumentar a altura da prévia; paginação física,
margens reais e capacidades do equipamento serão tratados na futura impressão.

A janela oferece Estado atual da aplicação por padrão. Exemplos de Abertura,
Fechamento e Manual exigem seleção explícita e exibem aviso **EXEMPLO SIMULADO**.
Dados fictícios não são mesclados ao estado atual nem gravados na operação.

## Código de barras

`previewTicketIdentifier` retorna somente o número do ticket. A função é injetável
no mapeador e deverá ser substituída pela composição oficial, com unicidade e
rastreabilidade definidas pela fonte real. Não adiciona datas, hashes ou sequências
como se fossem uma regra definitiva.

O desenho usa módulos Code 39, delimitadores e zonas de silêncio; mostra também o
texto original. A tabela foi conferida na implementação de referência
[ZXing Code39Reader](https://github.com/zxing/zxing/blob/master/core/src/main/java/com/google/zxing/oned/Code39Reader.java).
Caracteres não suportados conservam o identificador textual sem desenhar barras
inválidas. A compatibilidade com leitores/impressoras reais ainda será validada
na integração física. Nenhum pacote novo foi adicionado.

## Testes

Testes cobrem abertura/fechamento, fidelidade ao líquido informado/calculado no
estado, carreta opcional, múltiplos documentos/emissores, texto longo, identificação
manual, datas de emissão/captura, código e origem dos dados nos dois formatos.
