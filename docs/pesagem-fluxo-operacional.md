# Fluxo operacional local de Pesagem

Esta etapa evolui a demonstração descrita em `pesagem-interface.md`. Não adiciona
HTTP, endpoints, persistência definitiva ou impressão física. Não altera backend
ou Angular. `TicketSession` conserva contexto, rascunho e fase mock entre abas;
não é uma gravação Libra nem conversão automática em eventos de OfflineStation.

## Consulta e autoridade dos campos

`OperationLookupService` separa consulta da tela. A implementação de demonstração
usa somente as fixtures locais já existentes. Placa desconhecida retorna null,
não cria pré-ticket e não preenche dados. O operador pode digitar manualmente.
Resultado remoto não é aceito estando offline; geração e placa da consulta
impedem aplicar resposta atrasada em outra composição/tela desmontada.

`OperationMode` distingue manual/integrada e `officialOperation` identifica os
campos protegidos individualmente. Campos retornados são readonly, inclusive
Observação se vier oficial. Os ausentes continuam editáveis. Carreta conserva
autopreenchimento único, LOV múltipla e entrada manual, com as mesmas dimensões.

São manuais quando não oficiais: Motorista, Transportador, Emissor(es), Depósito,
Item, Tipo do documento, Nº Nota(s) / Documento(s), Peso N.F., Embalagem
e Observação. Operador continua reservado à identidade, sem valor inventado.
Destino permanece no domínio, temporariamente oculto na interface operacional.

## Texto e teclado

Editáveis usam TextField nativo, sem reticências no valor ou botão de expansão;
cursor, seleção, setas, Home/End e rolagem horizontal permanecem normais. Readonly
reutiliza ReadOnlyValueField, com texto normal/legível e botão de expansão apenas
se houver overflow. O modal mostra nome/valor completo e fecha por Fechar, ESC
ou dismiss padrão. Somente o botão participa do TAB quando há overflow, sem
parada adicional no campo readonly.

OrderedTraversalPolicy segue Placa → Carreta → Motorista → Transportador →
Emissor(es) → Depósito → Item → Tipo do documento → documentos → Peso NF →
Embalagem → Observação. Operador reservado é pulado. Pesquisa lateral/botões vêm
depois dos campos; placa recebe foco inicial e TAB de consulta sem resultado
conserva o foco em Carreta.

PesagemAction é a definição única para botão e teclado: F2 Resumo Pesagem,
F5 Impr. Pesagem, F6 Nova Pesagem, F10 Salvar Pesagem, F11 Peso Manual e F12 Pesagem. F2 abre resumo
local; F5 reutiliza a prévia existente, sem enviar à impressora. F11/F12 mantêm
autenticação/entrada/confirmar/cancelar já existentes. A autorização de Peso Manual
exige justificativa específica da leitura, mantida no preview, ticket e auditoria
local por captura confirmada. F10 salva somente os dados
de uma pesagem aberta, usando o mesmo callback e habilitação do botão lateral.
Repetição de tecla, outro modal e ação/consulta em andamento não disparam novo
fluxo. Atalhos não bypassam permissão ou confirmação. A área de ações pode rolar
em alturas pequenas, sem reposicionar as demais seções.

PesagemActionScope usa Shortcuts + Actions no AppShell inteiro enquanto a aba
Pesagem está ativa; cabeçalho e menu também ficam dentro do alcance dos atalhos.
PesagemActionDispatcher encaminha clique/tecla para o mesmo _runAction da página.
A página isolada instala o mesmo escopo local, sem instalar dois no AppShell.
Antes, o escopo interno da página perdia F12 quando o foco estava no cabeçalho;
esse cenário foi reproduzido por teste antes da correção. Campos de texto já
estavam dentro do escopo antigo e seguem cobertos por testes de todas as teclas.
Modais são outras rotas, e o callback também verifica rota atual/fluxo em curso.
Não há listener nativo nem captura de teclado em outras abas.

Na lista lateral, carreta null, vazia ou só com espaços é exibida como “-”, sem
alterar o valor de origem. O ícone de Salvar usa a mesma caixa e escala dos SVGs
ilustrados de Resumo/Impressão, preservando texto, estilo e dimensões do botão.

## Captura e edição de dados são ações diferentes

O botão Salvar Pesagem dentro da confirmação mantém a confirmação de captura.
Uma leitura manual positiva confirmada atualiza o primeiro/segundo peso e a fase
mock de TicketSession (aberta/fechada). O zero do indicador desconectado não abre
nem fecha; cancelar não confirma. O mapeador de ticket não duplica uma captura
cujo instante já esteja no resumo, evitando inventar Peso 2 depois da abertura.

Salvar Pesagem na área de ações só é habilitado em WeighingPhase.aberta e com
permissão de editar dados manuais de pesagem aberta. Chama
PesagemEditService, hoje MemoryPesagemEditService; não presume PATCH ou endpoint
de atualização. O serviço rejeita alteração de campo oficial/de Operador e copia
somente o mapa de operação. Mantém as instâncias de resumo e captura, os pesos,
datas e fase, sem chamar abrir/fechar, criar ticket ou gerar evento de peso.

Rascunho é separado do estado confirmado durante uma pesagem aberta. Sucesso
informa “Dados da pesagem atualizados.” Falha não é apresentada como sucesso.
O teste crítico abre com 18.500 kg, corrige Motorista e salva dados: continua
ABERTA, Peso 1 = 18.500, Peso 2 ausente e captura intacta. Após confirmação da
segunda leitura, a ação de editar dados fica desabilitada.

Permanecem pendentes contrato corporativo de consulta/edição, autorização real,
indicador, persistência e eventual outbox de metadados. A fila e o indicador de
conectividade da base offline permanecem independentes e inalterados.

## Verificação dos ajustes de atalhos e apresentação

Na rodada de ajustes dos atalhos, `dart format`, `flutter analyze` e `flutter test`
foram executados; análise sem apontamentos e 104 testes aprovados. A cobertura inclui carreta null/vazia/espaços,
padrão do ícone de Salvar, badge F10, paridade clique/tecla para as seis ações,
foco em Placa/Carreta/Motorista/Observação/cabeçalho, repetição de tecla, bloqueio
de modais, save em andamento e retorno da navegação entre abas.

A revisão conceitual manteve F12 no fluxo de confirmação, F11 no fluxo de
autenticação e F10 exclusivamente na edição de dados da pesagem aberta. A
verificação manual no aplicativo Windows não pôde ser concluída nesta sessão:
o controle nativo retornou “Computer Use native pipe is unavailable”. Os testes
de widgets com plataforma Windows não substituem essa verificação nativa.
