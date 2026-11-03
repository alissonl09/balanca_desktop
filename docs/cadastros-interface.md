# Cadastros: interface e estado temporário

Remetentes / Destinatários, Transportadoras, Motoristas e Placas compartilham
pesquisa por código/nome, seleção visual, listagem com rolagem interna e ações
Inserir, Alterar e Excluir. Placas também pesquisa por placa e nome da
transportadora. Pesquisa é aplicada pela lupa ou ENTER; filtro vazio mostra todos.
Operações, Itens / Produtos e Unidades permanecem provisórios.

## Organização do código

- `cadastro_record.dart`: tipos de apresentação, Tipo (Cliente / Fornecedor),
  Vínculo (Autônomo / Transportadora) e valores dos formulários.
- `cadastros_memory.dart`: dados mock e mutações exclusivamente em memória.
  Não é repository, não acessa arquivos ou banco e não representa contratos reais.
- `cadastro_panel.dart`: pesquisa, seleção, ações e confirmação de exclusão.
- `cadastro_form.dart`: mesmo formulário para inclusão/alteração, campos comuns
  de endereço, lista fixa de 27 UFs, validações e normalização da placa.
- `carrier_selection_field.dart`: seleção pesquisável de transportadora existente,
  compartilhada por Motoristas e Placas. Guarda o código, não um nome livre.

O shell mantém uma única instância do estado de demonstração durante a sessão.
Navegar entre páginas ou abas conserva os registros. Reiniciar a aplicação
restaura os exemplos; nada é persistido ou enviado à Libra-API.

## Fluxos

Inserir abre um rascunho com o próximo código somente leitura. A sequência é
inicializada em máximo existente + 1, separadamente por cadastro, e avança apenas
ao salvar. Cancelar não consome código. Exclusão não retrocede a sequência.
Futuramente o identificador deverá vir da persistência real.

Alterar abre uma cópia dos valores. Cancelar descarta o rascunho. Salvar aplica os
valores em memória, preserva o código e destaca o registro salvo na lista.
Excluir exige confirmação com Código - Nome/Placa e botão destrutivo vermelho.
Alterar/Excluir só ficam disponíveis com um registro selecionado e visível no filtro.

Motorista autônomo não exige transportadora. Ao trocar para Autônomo, a seleção
anterior é limpa. Vínculo Transportadora exibe e exige seleção de registro existente.
Placas sempre exige essa seleção. O seletor usa os dados atuais de Transportadoras,
incluindo inclusões e alterações feitas na mesma sessão.

Não há regra definitiva de exclusão de transportadora nem exclusão em cascata.
Referências a uma transportadora excluída são sinalizadas como indisponíveis na
interface; ao editar um cadastro que exige o vínculo, é necessário selecionar uma
transportadora existente. A política definitiva de integridade fica pendente.

Placa aceita os formatos brasileiros antigo/Mercosul com sete caracteres; normaliza
maiúsculas e remove espaços/separadores. Número de endereço é texto. CEP e
CPF/CNPJ possuem indicação visual de formato, sem validação fiscal ou máscara
que modifique o documento. Observação é livre e multilinha.

Os modais mantêm título e ações fixos. O conteúdo rola internamente quando necessário;
em larguras menores, as linhas do formulário se reorganizam sem reduzir as fontes.

## Exemplos mock

- Remetentes / Destinatários: Fazenda Boa Vista (Fornecedor) e Comercial de Café
  Horizonte (Cliente).
- Transportadoras: Transportadora Horizonte, Cargas Serra Azul e Transportes Vale
  do Café.
- Motoristas: João da Silva (Autônomo) e Maria Oliveira (vinculada à Horizonte).
- Placas: ABC1D23 (Horizonte) e DEF4G56 (Serra Azul).

Não são usados documentos fiscais reais.

## Integração futura

Ainda dependem de definição: armazenamento e identificadores reais, carregamento e
pesquisa paginada, contratos de inclusão/alteração/exclusão, tratamento de erros,
concorrência e integridade de vínculos. Modelos, formulários e seleção retornam valores
separados do estado mock para permitir substituir essa fonte. Nenhum endpoint,
banco, autenticação, sincronização ou integração com ERP foi implementado.
