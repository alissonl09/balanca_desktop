# SQLite local e manutenção

## Escopo e arquitetura

A infraestrutura utiliza `sqlite3` 3.9.2, com SQLite nativo incorporado ao
pacote Windows. O cliente não precisa instalar SQLite, serviço ou listener.
`file_selector` fornece a seleção de arquivos SQL e `crypto` calcula SHA-256.

`DatabaseManager` é a API assíncrona da conexão central. A conexão pertence a
um isolate de `database_worker.dart`, cuja fila serializa leituras, gravações,
backups, migrations e manutenção. Nenhuma tela recebe uma conexão ou executa
SQL diretamente. Um lock de arquivo impede dois gerenciadores de assumirem a
mesma estação. Aberturas concorrentes no mesmo gerenciador compartilham a
inicialização.

O bootstrap de produção injeta `SqlitePesagemStore` na `OfflineStation`.
Pesagem e eventos da outbox são confirmados na mesma transação. O adaptador
preserva `LocalWeighing`, `SyncEvent` e as políticas operacionais existentes.
Não há envio HTTP, retries ou confirmação remota presumida nesta camada.
Eventos que estavam em envio continuam exigindo resolução pelo adaptador de
sincronização; não são reenviados automaticamente após reiniciar.

**Limite desta etapa:** a tela atual de captura ainda mantém a simulação em
`TicketSession`. A conexão entre essa simulação e os comandos de domínio da
`OfflineStation` não foi remodelada. A infraestrutura durável está disponível
para o fluxo de contingência existente; esta entrega não transforma toda a
interface de pesagem em um fluxo operacional durável completo.

## Arquivo e durabilidade

No Windows, o Known Folder `LocalAppData` fornece a raiz:

```text
%LOCALAPPDATA%/Cooxupe/Balanca/data/balanca.db
%LOCALAPPDATA%/Cooxupe/Balanca/backup/
```

O caminho real é exibido na aba Banco de Dados. A aplicação verifica a unidade
física resolvida e rejeita UNC, caminhos relativos e unidades que não sejam
discos locais fixos. O diretório fica fora do executável e herda as permissões
do perfil Windows. Não há alteração automática de ACL ou criptografia.
Essa escolha evita exigir administrador e cria um banco por usuário Windows;
uma implantação com vários usuários deve definir posteriormente uma pasta de
máquina e provisionar suas ACLs no instalador.

Na abertura são configurados `foreign_keys=ON`, `journal_mode=WAL`,
`busy_timeout=5000`, `synchronous=FULL`, `trusted_schema=OFF` e o modo defensivo
do SQLite. A aplicação não substitui um banco indisponível por armazenamento
volátil silenciosamente. Na aba Banco de Dados, **Testar conexão** consulta a
conexão já aberta. A abertura e a inicialização do banco continuam no início
do aplicativo.

O SQLite depende também do funcionamento do disco, do sistema operacional e
do hardware para cumprir as garantias de persistência. Não há segredo de
integração ou JWT migrado para tabelas.

## Schema e migrations

`database_migrations.dart` contém migrations sequenciais, versionadas com o
código. Cada migration e sua atualização de `user_version` são transacionais.
O histórico registra versão, nome, horário UTC, resultado e hash. Uma migration
aplicada não pode ter seu conteúdo alterado; novas alterações exigem uma nova
migration. Schemas mais novos e arquivos com outro `application_id` são recusados.

A V001 cria somente as estruturas necessárias nesta etapa:

- `BAL_SCHEMA_VERSION`: migrations aplicadas;
- `BAL_DB_SCRIPT_HIST`: auditoria de migrations, scripts e restaurações;
- `BAL_DB_META`: últimos resultados administrativos;
- `BAL_PESAGEM` e `BAL_SYNC_EVENTO`: agregado atual e outbox, com foreign key.

As duas leituras atuais foram preservadas para não remodelar o domínio.
Uma futura tabela de leituras pode ser introduzida por migration específica.

## Backup e restauração

A aba mostra o caminho do banco em somente leitura. Backup e restauração são
ações individuais. O esquema, o tamanho em disco, a verificação de integridade,
a compactação, os scripts e o histórico ficam recolhidos em **Manutenção
avançada**.

Backups usam a API de backup do SQLite, incluindo dados confirmados no WAL.
Cada snapshot é aberto e submetido a `integrity_check` e `foreign_key_check`.
Não se copia cegamente um arquivo aberto. Os nomes contêm data/hora UTC;
a interface apresenta os horários no fuso local.

`DatabaseManager.backupRetention` centraliza a retenção, inicialmente dez
snapshots. O expurgo de backups ocorre somente após criar e validar um novo.
Backups de segurança durante restauração não são removidos nessa operação.

A restauração aceita apenas snapshots gerenciados na pasta de backup. Mostra
data e tamanho e exige digitar `RESTAURAR`. Verifica integridade, identidade e
compatibilidade; cria snapshot do estado atual; restaura pela API SQLite;
reabre, aplica migrations pendentes e verifica novamente. Se uma etapa falhar,
recupera o snapshot anterior. Um marcador persistido permite recuperar o estado
anterior no próximo início se o processo for interrompido durante a restauração.
Após sucesso, as projeções da estação e a sessão de apresentação são recarregadas.

Restaurar pode remover operações e eventos pendentes posteriores ao snapshot.
A confirmação alerta explicitamente sobre isso. O snapshot de segurança deve
ser preservado para reconciliação antes de retomar uma integração futura.

## Scripts administrativos

Fluxo: selecionar `.sql` → preview imutável → resumo e SHA-256 → digitar
`APLICAR` → backup íntegro obrigatório → transação única → auditoria.
O schema oficial não muda de versão por um DDL manual.

São aceitos, em um subconjunto conservador:

- `CREATE TABLE`;
- `ALTER TABLE ... ADD [COLUMN]`;
- `CREATE [UNIQUE] INDEX`;
- `DROP INDEX` fora dos objetos protegidos.

São bloqueados DML, `DROP TABLE`, `DROP COLUMN`, renomeações, views, triggers,
tabelas virtuais, `ATTACH`, `DETACH`, pragmas, controle de transação, `VACUUM`,
consultas e funções arbitrárias. Os metadados, o histórico e seus índices são
protegidos. O parser distingue strings, identificadores, comentários e pontos
e vírgulas; não é uma busca ingênua por palavras. SQL não transacional não é
executado pelo recurso. Limites: 1 MB e 200 comandos por arquivo.

Um hash manual já aplicado é bloqueado, mesmo se o arquivo tiver outro nome.
SQL sintaticamente inválido provoca rollback integral, com registro de falha
fora da transação revertida. Falha de backup impede a execução.

Erros completos são registrados em `data/database-maintenance.log`.
A interface mostra mensagem simples e detalhes técnicos expansíveis.

## Permissões, operação ativa e expurgo futuro

As ações reutilizam o modelo existente: `maintainDatabase`,
`executeDatabaseDdl` e `restoreDatabase`. Não foi criada autenticação paralela.
O diretório e os perfis atuais continuam sendo os mecanismos de demonstração
existentes, não uma autenticação corporativa nova.

VACUUM, restauração e DDL verificam o estado operacional por callback e também
as pesagens duráveis abertas ou com ticket pendente. Escritas operacionais não
são admitidas enquanto uma manutenção exclusiva está em andamento. Os estados
das cancelas também participam da proteção configurada pelo AppShell.

`DatabaseRetentionPolicy` prepara somente a elegibilidade para expurgo:
conclusão, todos os eventos confirmados, ausência de acesso ativo e retenção
configurável vencida. Exige uma data explícita de conclusão; não usa a data de
criação como substituta. Não existe exclusão automática nesta etapa.

## Validação local

Os testes usam arquivos temporários, SQLite real embarcado e serviços simulados
na interface. Não dependem de Libra, Guardian, Oracle ou bancos corporativos.
Cobrem criação, reabertura, migrations, rollback, concorrência, WAL, backup,
retenção, integridade, DDL, duplicação de hash, restauração e recuperação de falhas,
permissões e confirmações fortes.

Validação desta implementação: 451 testes aprovados na suíte completa;
`flutter analyze --no-pub` sem problemas; build Windows Release gerado com
`sqlite3.dll` e o manifesto de assets nativos incluídos na distribuição.

## Arquivos da entrega

| Arquivo | Responsabilidade |
| --- | --- |
| `lib/core/database/database_manager.dart` | API central, isolate, pasta local e proteção operacional |
| `lib/core/database/database_worker.dart` | Conexão, transações, manutenção, backup e recuperação |
| `lib/core/database/database_migrations.dart` | Schema inicial e migrations versionadas |
| `lib/core/database/ddl_policy.dart` | Análise lexical, preview, limites e DDL permitido |
| `lib/core/database/database_retention_policy.dart` | Elegibilidade futura para expurgo |
| `lib/core/offline/sqlite_pesagem_store.dart` | Adaptador durável do contrato existente |
| `lib/core/offline/offline_station.dart` | Recarga após restauração |
| `lib/features/configuracoes/database_settings.dart` | Painel, ações e confirmações administrativas |
| `lib/features/configuracoes/configuracoes_page.dart` | Aba Banco de Dados |
| `lib/features/configuracoes/settings_models.dart` | Injeção da infraestrutura |
| `lib/core/permissions/permission_models.dart` | Permissões específicas no modelo existente |
| `lib/main.dart`, `lib/app/balanca_app.dart`, `lib/app/app_shell.dart` | Inicialização, injeção e carregamento offline |
| `pubspec.yaml`, `pubspec.lock` | Dependências e versões resolvidas |
| `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake` | Registro gerado do seletor de arquivos Windows |
| `test/database_test.dart` | SQLite real em pastas temporárias |
| `test/ddl_policy_test.dart` | Scripts permitidos e bloqueios |
| `test/database_settings_test.dart` | Interface, permissões, confirmações e inicialização offline |
| `test/database_retention_policy_test.dart` | Proteções para expurgo futuro |

As alterações anteriores de autenticação Libra e nomenclatura de cancelas foram
preservadas; não fazem parte da implementação SQLite descrita aqui.
