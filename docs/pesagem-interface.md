# Pesagem: demonstração local da interface

> Registro da etapa inicial. O comportamento operacional atual (modos, TAB,
> atalhos e edição de dados abertos) está em [Fluxo operacional](pesagem-fluxo-operacional.md).

Esta etapa usa somente estado em memória. Não há novas chamadas de API,
persistência, alterações na comunicação com indicadores ou nas regras reais de pesagem.

## Dados e operações simulados

`lib/features/pesagem/operation_preview.dart` concentra sete operações de exemplo,
os valores extensos dos campos e o resumo inicial de demonstração.
`ABC1D23` oferece duas carretas; `DEF2E34` oferece uma carreta e uma Pesagem 1
preenchida para testar a identificação visual de fechamento.
Limpar a consulta ou iniciar Nova Pesagem restaura os campos e os pesos iniciais.

A lista lateral ocupa sempre cinco alturas de linha, mesmo quando o filtro
encontra poucos registros. Somente a lista rola; cabeçalho, pesquisa e botões
permanecem fixos. Os campos Placa e Carreta compartilham a largura de 190 pixels lógicos.

## Campos e valores extensos

Motorista e Transportador dividem a primeira linha; Emissor(es) e Depósito,
a segunda. A terceira agrupa Item, Destino, Tipo do documento e
Nº Nota(s) / Documento(s), reservando maior largura para documentos. A última
mantém Peso N.F. compacto, Embalagem, Operador e Observação editável e ampla.

`ReadOnlyValueField` mede o texto com fonte, escala e largura atuais. Quando
excede o campo, aplica reticências e oferece um indicador clicável. Tanto o
campo como o indicador abrem um diálogo com texto completo selecionável.
Sem truncamento, não existe indicador.

## Confirmação e Peso Manual

O botão Pesagem abre a confirmação compartilhada dos dois fluxos. O callback
também está preparado para futura ligação do atalho F12. O peso automático
continua em zero, com indicação de equipamento desconectado.

`WeighingSummary.isClosing`, em `weighing_preview.dart`, é uma heurística
provisória de apresentação: quatro pesos zerados identificam abertura;
qualquer peso positivo identifica fechamento. Não calcula nem altera pesos.

Peso Manual abre autenticação, depois entrada numérica e, por fim, a mesma
confirmação. O painel âmbar identifica o valor informado pelo operador. Aceita
vírgula ou ponto decimal, até três casas decimais, e exige valor positivo.
A confirmação identifica a origem manual e o usuário que liberou a entrada.
Cada nova tentativa exige autenticação novamente.

`lib/features/pesagem/preview_authentication.dart` isola a credencial fixa
`balanca / Cxp123`. É exclusivamente um recurso provisório de teste de interface,
sem segurança ou sessão reais. Substituir pela autenticação/autorização real.

Salvar Pesagem existe somente na confirmação. A ação guarda uma prévia em memória
da tela e informa que a confirmação é simulada, sem gravar dados ou modificar o
indicador/resumo. Cancelar qualquer etapa não confirma a pesagem.
Os diálogos têm conteúdo rolável e ações inferiores acessíveis em janelas menores.

## Dependências futuras

- Consulta real de placa, composição, operações abertas e documentos/emissores.
- Valores reais de Motorista, Transportador, Depósito e demais dados da operação.
- Estado e classificação definitivos de abertura/fechamento, validações e pesos.
- Autenticação, autorização de Peso Manual e identificação real do operador.
- Contrato de salvamento, retorno de sucesso/erro e atualização da operação.

Nenhum endpoint ou contrato foi pressuposto. O indicador continua dependendo da
integração de equipamento já prevista pelo projeto, sem mudanças nesta etapa.
