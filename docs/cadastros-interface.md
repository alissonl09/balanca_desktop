# Cadastros

Os cadastros compartilham pesquisa, seleção visual, rolagem interna e ações
de manutenção. A lupa ou Enter aplica o filtro. Unidades continua provisório.

## Origem dos registros

A aba abre em modo real e consulta somente registros oficiais que tenham sido
disponibilizados à aplicação. A versão atual não tem uma fonte de consulta
cadastral conectada. A Libra fornece pré-tickets que podem trazer o nome do
motorista e dados da operação. Esses valores são exibidos na pesagem e não
identificam registros oficiais de motoristas ou veículos.

O controle **Modo simulado** habilita explicitamente a demonstração. Ela usa
outra instância em memória, com exemplos fictícios, e conserva as alterações
durante a sessão. Voltar ao modo real exibe apenas a origem oficial. Encerrar o
aplicativo descarta a sessão simulada.

## Motoristas

A tabela apresenta matrícula, nome, cidade e UF. A busca usa matrícula ou nome.
Um clique seleciona a linha e um duplo clique abre o formulário em consulta.
Inserir e Alterar abrem o mesmo formulário em manutenção quando autorizados.

O formulário mostra os dados pessoais à esquerda e as placas vinculadas à
direita quando houver largura. Em janelas menores, a lista de placas fica
abaixo dos campos. O nome completo é obrigatório. Endereço, número, complemento,
cidade, UF, CEP e observações são opcionais. O vínculo preexistente com
transportadora continua disponível. A consulta preserva valores legados de UF.
O CPF fica fora do cadastro de motoristas e do escopo da integração.

A matrícula é um texto somente leitura e é independente do identificador do
registro. Matrículas iniciadas por `SIM-` pertencem aos exemplos e à numeração
temporária da demonstração. O contrato central definirá a matrícula oficial.

O seletor de placas usa veículos cadastrados. Aceita os formatos brasileiros
antigo e Mercosul, seguindo a normalização existente. O vínculo usa o ID do
veículo e impede repetições da mesma placa no motorista. Veículos podem aparecer
em mais de um motorista. Incluir ou remover um vínculo altera o rascunho do
formulário. Salvar aplica o rascunho completo. Cancelar pede confirmação se
houver alterações. Remover um vínculo preserva o registro do veículo. Se um
veículo vinculado sair do catálogo simulado, a referência permanece indicada
como indisponível.

## Catálogos XBAL

- **Itens / Produtos** classifica materiais para a balança, incluindo Sacaria.
  A fonte central prevista é `XCXP_BAL_ITEM`.
- **Operações** representa os roteiros (`XCXP_BAL_ROTEIRO`), com dados gerais,
  tolerância associada e informações complementares associadas. A natureza do
  roteiro é independente da primeira ou da segunda leitura.
- **Regras de Tolerância** separa os parâmetros da operação e distingue a
  dispensa explícita, o zero e a ausência de referência. Usar regra padrão
  com BAG ou GRANEL é inválido. Referências incompletas geram pendência.
- **Informações Complementares** define os sete tipos reutilizáveis. Cada
  associação pertence a um roteiro e pode filtrar produto ou acondicionamento.
  O protótipo sinaliza conflitos de contexto sem escolher precedência.

Os códigos `SIM-` dos quatro catálogos identificam dados da demonstração. A
inativação nessa fonte preserva o registro e suas referências.

## Permissões e manutenção

As ações usam `PermissionState`. Cada categoria implementada exige a permissão
geral de consulta e a consulta da categoria. Inserir, alterar e excluir exigem,
além da consulta, a permissão geral da ação e a permissão correspondente da
categoria. Mudar vínculos de placa exige uma autorização própria. Adicionar
uma placa também exige consulta ao cadastro de placas.

Na matriz inicial, Master e Administrador têm manutenção. Supervisor, Líder e
Operador têm consulta cadastral. As permissões podem ser configuradas na matriz
existente. Uma ação sem a concessão necessária é bloqueada pelo serviço e fica
desabilitada na interface.

Manutenção oficial, inclusive offline, fica indisponível mesmo para um perfil
autorizado. A exclusão exige confirmação e só opera na demonstração. Não há
persistência local dos cadastros oficiais nem exclusão de pesagens pelo cadastro.

## Integração central pendente

- Origem e atribuição da matrícula oficial, identificadores estáveis de motorista
  e veículo e representação dos vínculos.
- Fonte de consulta, critérios de busca, sincronização e disponibilidade de
  registros oficiais para consulta em cada unidade.
- Campos obrigatórios, validações e tratamento de valores legados.
- Contratos para as operações de manutenção e os vínculos, com validação de
  permissões no servidor e tratamento de concorrência.
- Política de inativação ou exclusão, integridade de referências e auditoria.
- Cache SQLite cadastral, revisão dos 21 roteiros, metadados centrais dos
  atributos e precedência completa de exceções. A coleta na pesagem e a
  apresentação no ticket dependem de regras e layouts homologados.
