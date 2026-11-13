# Consulta de pré-ticket da Libra

## Diagnóstico inicial

A tela chamava `DemoOperationLookupService`, usando apenas fixtures locais.
`PreTicketResolver.remotePath` já declarava a rota, mas não implementava HTTP.
Não havia cliente HTTP comum, interceptor, base URL, API key, DTO remoto ou
configuração de integração por ambiente. `KnownPreTicket` é um modelo mínimo
offline, não o DTO da Libra, e foi preservado.

Unidade e ambiente já existiam em `SettingsState`: unidade inicial 4 (JAPY)
e ambiente inicial Homologação. A unidade continua em memória; o ambiente
selecionado e os parâmetros da Libra agora podem ser salvos localmente.

## Fluxo implementado

`PesagemPage._lookup` → `PreTicketService` → `LibraApiClient` →
`GET /api/v1/pre-tickets?cdUnidadeBalanca=...&placa=...`.

O serviço lê unidade e ambiente a cada consulta. A placa vem do campo Placa,
com a normalização existente (maiúsculas, remoção de espaços e hífens).
Respostas tardias de outra placa, unidade ou ambiente são descartadas.
Trocar unidade/ambiente invalida uma consulta anterior, inclusive ao retornar
da página de Configurações. Não há fallback para mock após erro real.

## Configuração temporária na aplicação

**SOLUÇÃO TEMPORÁRIA PARA AMBIENTE CONTROLADO DE TESTES.** Em
**Configurações → Configurações Gerais → Integração Libra**, configure:

- **Ambiente:** use o seletor já existente, acima da seção, na unidade da balança.
- **Base URL:** a origem HTTPS do ambiente selecionado.
- **Auth Key:** inicialmente `x-api-key`, editável.
- **Auth Value:** inicialmente vazio, mascarado, com opção mostrar/ocultar.
- **Placa de teste:** informada pelo operador; não é persistida.

As edições passam a valer na sessão imediatamente. **Salvar configurações**
grava o ambiente selecionado e URL/Key/Value por ambiente em
`libra-settings.json`, na pasta de suporte do aplicativo no perfil local do
Windows, obtida por `PathProviderWindows.getApplicationSupportPath()`.
O padrão de escrita é o mesmo da webcam: JSON local, arquivo `.pending` e
substituição após escrita concluída. O aplicativo carrega esses dados ao iniciar.
O Value é armazenado em **texto simples**, sem criptografia nesta etapa. A
máscara protege somente a apresentação na tela. Não copie esse arquivo para
o repositório, fixtures, documentação, backups compartilhados ou Git.

Cada ambiente mantém seus próprios campos. Ao mudar de ambiente, o Value volta
a ficar mascarado. Nenhuma credencial real é fornecida pelo código ou pelos testes.
Falhas ao carregar/salvar mostram mensagem genérica, sem conteúdo ou exceção bruta.

## Prioridade e variáveis de ambiente

Para a URL: valor local não vazio → variável do ambiente → padrão DSV somente
em Desenvolvimento. HML e PRD não usam fallback DSV.

Para a autenticação: edição local de Key ou Value → variável de ambiente
enquanto não houver edição local → nenhuma credencial. Uma edição local é
persistida com `authOverride`; limpar Key ou Value explicitamente também
substitui o fallback. Nesse caso, sem o par completo, nenhum header de
autenticação é enviado. O Value vindo de variável de ambiente não é copiado
automaticamente para o campo da tela. O fallback usa Key `x-api-key`.
Mudanças em variáveis de ambiente exigem reiniciar o processo.

| Ambiente selecionado na estação | Fallback da Base URL | Fallback da credencial |
| --- | --- | --- |
| Desenvolvimento | `LIBRA_BASE_URL_DSV` (opcional) | `LIBRA_API_KEY_DSV` |
| Homologação | `LIBRA_BASE_URL_HML` | `LIBRA_API_KEY_HML` |
| Produção | `LIBRA_BASE_URL_PRD` | `LIBRA_API_KEY_PRD` |

A URL padrão de Desenvolvimento fica centralizada em
`LibraConfiguration.developmentBaseUrl`. HML e PRD não usam fallback DSV.
Somente origens HTTPS, sem credenciais, query, fragmento ou caminho adicional,
são aceitas. `SettingsState.libra` → `LibraConfiguration` resolve os campos
do ambiente atual e os fornece ao `LibraApiClient`, que não conhece a UI.
Com Key e Value preenchidos, o cliente envia `<Key>: <Value>`.
Não há interceptor que registre headers ou corpos. Redirecionamentos não são
seguidos para evitar encaminhar a credencial para outro destino.

`LIBRA_MODE=mock` habilita explicitamente os exemplos. Sem esse valor, o modo
é real. Testes de interface que precisam de exemplos injetam o serviço demo.
`LIBRA_OFFLINE=true` bloqueia a consulta real, sem criar cache ou pré-ticket.
Na aplicação, uma estação própria em modo real inicia no estado operacional
online; isso expressa a configuração, não uma sondagem de conectividade.
Estações injetadas preservam seu estado. Não foi criada sincronização automática.
Sem comunicação, a consulta falha e conserva a entrada manual.

Para usar DSV, selecione **Desenvolvimento**, informe o Value na aplicação e
salve as configurações. Sem configuração salva, o ambiente inicial continua
Homologação; uma seleção salva é restaurada na inicialização.

## Testar conexão

O botão usa `PreTicketService.testConnection` e o mesmo método de requisição,
`LibraConfiguration` e `LibraApiClient` usados na Pesagem. Envia a unidade
atualmente selecionada e a placa de teste normalizada pela regra existente.
Não cria operação, cache ou pesagem. Sem credencial completa, informa
**Credencial não configurada** e não inicia a sondagem. Em modo mock, o teste
real fica bloqueado. Alterações durante uma chamada invalidam o diagnóstico.

200/204 indicam **Conexão realizada**; 401/403, **Falha de autenticação**;
404 e outros status inesperados, **Endpoint indisponível**. Há mensagens para
timeout, comunicação, configuração e TLS. Na consulta operacional de placa,
404 continua significando ausência de pré-ticket, conforme a regra anterior.
Sucesso de conexão não comprova existência de documento nem valida todo o DTO.

## PENDÊNCIA DE SEGURANÇA

O armazenamento e a autenticação definitivos serão revisados futuramente com
a Segurança da Informação. Poderão usar mecanismo seguro do Windows, OAuth2,
Guardian ou outra solução definida pela área. Nenhum desses mecanismos foi
implementado nesta etapa. Nunca colocar uma credencial real em código Dart,
constantes, testes, fixtures, documentação, arquivos versionados ou Git.

## Contrato e preenchimento

`PreTicketDto` mapeia `tipoDocumento`, `nota`, `emissor`, `motorista`,
`transportador`, `quantidadeTotal`, `embalagem`, `deposito`, `sequencia`,
`tipoOperacao`, `numeroTicketOrigem`, `codigoUnidadeOrigem` e
`pesoLiquidoOrigem`. Os DTOs completos ficam em `TicketSession.preTickets`;
XFER não é convertido em uma pesagem física ou em campos inexistentes da tela.

Campos de apresentação são preenchidos em Dados da Operação e seguem a regra
existente de somente leitura para dados integrados. Valores ausentes continuam
manuais. O DTO aceita um objeto ou lista de documentos com esses campos;
campos textuais aceitam também listas de valores, preservadas com `; `.
Em uma lista de documentos, `quantidadeTotal` é somada para Peso N.F.
Não é deduzida nenhuma carreta; a composição informada pelo operador é mantida.

**Limite de validação:** não foi fornecido um JSON real autenticado. O parser
implementa os campos informados no pedido e objetos/listas diretos. Envelopes
ou objetos aninhados de pessoas/documentos não documentados são rejeitados
como resposta incompatível, sem inventar nomes de propriedades. Confirmar a
estrutura exata e a semântica/unidade de `quantidadeTotal` com uma resposta
autenticada antes da homologação operacional.

## Estados e diagnóstico

Há indicador de carregamento e bloqueio de clique duplicado. Timeout total:
15 segundos, com fechamento da conexão. 401/403 mostram falha de autenticação;
404/204/resposta vazia mostram ausência de pré-ticket; outros status inesperados,
rede, timeout, TLS e resposta inválida têm mensagens funcionais específicas.
404 sozinho não prova que a rota foi encontrada pelo servidor.

Logs de desenvolvimento contêm origem/rota, status, duração e resultado.
Não incluem placa, query, headers, corpo, chave ou texto bruto de exceções.
O cliente mantém a validação TLS padrão, sem bypass de certificado.

Em 09/11/2026, nesta máquina:

- DNS resolveu o host de DSV para `172.16.241.68`.
- Cliente Dart: HTTPS validado, HTTP 400 sem parâmetros; HTTP 404 com unidade 4
  e placa de exemplo, em requisições sem credencial.
- `curl`/Schannel falhou localmente com `SEC_E_NO_CREDENTIALS`; isso não se
  reproduziu no Dart e não foi interpretado como certificado inválido do servidor.
- API key configurada: não.
- Não foi possível validar autenticação, um retorno 200 real ou o preenchimento
  com dados reais de uma placa conhecida. Esses testes funcionais estão pendentes.

`tool/check_libra_connectivity.dart` permite repetir a sondagem sem header de
credencial, recebendo a URL HTTPS como único argumento. Só imprime status e
classe de erro; não imprime URL, corpo ou detalhes de exceção.

## Validação automatizada

Resultado final em 09/11/2026: `dart format` executado;
`flutter analyze --no-pub` sem problemas;
`flutter test --no-pub --timeout 60s` com **374 testes aprovados**.

`test/libra_pre_ticket_test.dart` cobre URL, parâmetros, header sintético,
redirecionamentos, ausência de segredo nos logs, 200/vazio, 401, 403, 404,
500, timeout, rede, TLS, DTO, XFER, ambiente e mudança da unidade.
`test/pesagem_operational_flow_test.dart` cobre a resposta HTTP controlada
preenchendo a tela, campos somente leitura, carregamento, composição preservada
e nova consulta após mudança de unidade. Esses testes não acessam a Libra real.

`test/libra_settings_test.dart` acrescenta 12 testes de padrões, isolamento de
ambientes, prioridade/fallback, persistência/restauração/sobrescrita local,
salvamento pela interface, máscara, largura dos campos, header personalizado,
logs sem Value, ausência de credencial e teste de conexão em modo real/mock.
Somente valores sintéticos são utilizados; nenhuma credencial real foi gravada.

Nenhuma alteração na Libra-API ou no balanca-web. Sem commit ou push.

## Arquivos alterados ou adicionados nesta etapa de autenticação temporária

- `lib/main.dart`
- `lib/features/configuracoes/configuracoes_page.dart`
- `lib/features/configuracoes/settings_models.dart`
- `lib/features/configuracoes/libra_settings.dart`
- `lib/core/libra/libra_settings_store.dart`
- `lib/core/libra/libra_configuration.dart`
- `lib/core/libra/libra_api_client.dart`
- `lib/features/pesagem/pre_ticket_service.dart`
- `lib/app/app_shell.dart`
- `lib/app/balanca_app.dart`
- `test/libra_settings_test.dart`
- `docs/libra-pre-ticket.md`

As alterações anteriores da integração de pré-ticket foram preservadas.
