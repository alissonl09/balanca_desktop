# Pesagem Manual assistida por webcam (Windows)

## Fluxos e escopo

Serial/TCP continua com as regras atuais do indicador. A webcam só participa da ação
Peso Manual; não passa a fornecer o peso normal do sistema. A autorização existente
(usuário, senha, permissão de autorizar e justificativa obrigatória por leitura)
permanece em `weighing_dialogs.dart` e `pesagem_page.dart`. O driver visual é aberto
somente depois dessa autorização e da revalidação das permissões. A justificativa
humana não é substituída pelo motivo técnico. Senhas nunca entram na evidência.

Fluxo: autorização → inicializar webcam → enquadrar visor → Capturar peso →
salvar foto com timestamp → OCR local → confirmação humana. Não há captura
automática inicial: o operador confere o enquadramento antes do snapshot.
Durante inicialização, captura e OCR o campo manual fica bloqueado. OCR válido
também mantém o campo bloqueado. Capturar novamente gera outra tentativa.

Fallback: câmera não configurada/desabilitada/indisponível, falha de captura,
imagem inválida, engine ausente, OCR sem leitura ou confiança insuficiente
liberam a digitação. Quando houve foto, ela permanece ligada ao peso digitado.
Se uma nova tentativa falhar, a última foto salva é preservada, com seu horário
original e o motivo da nova falha. Sem câmera, permite continuar e grava ausência
da foto e motivo técnico. Não gera imagem sintética para substituí-la.

Peso zero é leitura válida no serviço e no diálogo; o ciclo operacional anterior
continua exigindo peso positivo para avançar a fase de entrada/saída. Essa regra
do ciclo não foi substituída por regras do OCR.

`Prosseguir` confirma a revisão do valor e persiste a auditoria visual; depois
continua a confirmação operacional já existente (`Salvar Pesagem`). Cancelar
essa segunda confirmação não elimina imagens ou registros de revisão anteriores.
O JSON usa `CAPTURE_ATTEMPT` e `WEIGHT_REVIEWED`, sem afirmar que houve gravação
operacional na API. Leituras efetivamente aceitas mantêm a evidência em
`WeighingPreview.manualEvidence` e `ManualReadingRecord.evidence` na sessão.

## Configurar a estação

Em Configurações → Configurações Gerais → Webcam da Pesagem Manual:

1. Atualizar webcams enumera os dispositivos reais via `availableCameras()`.
2. Selecionar webcam pelo nome amigável fornecido pelo Windows. O identificador
   completo inclui o link do dispositivo, permitindo distinguir nomes repetidos.
3. Habilitar/desabilitar a função conforme a estação.
4. Testar câmera abre somente o preview e o relógio; não fotografa, não executa
   OCR, não exige autorização de pesagem e não altera o ciclo operacional.

Seleção e habilitação são salvas imediatamente; erros de gravação aparecem na
própria seção. Nenhuma câmera é escolhida automaticamente. Dispositivo removido
permanece identificado como configurado, mas indisponível. Sem dispositivos,
mostra `Nenhuma webcam encontrada.` O botão de salvar configurações preexistente
continua responsável somente pelos demais rascunhos da sessão.

O armazenamento resolve `getApplicationSupportPath()` via `path_provider_windows`
e usa a subpasta `manual_weighing/` dessa aplicação. `webcam.json` contém a
configuração da estação e é carregado em `main` antes de construir a interface.
Falha de leitura não trava o aplicativo: fica sem câmera configurada e informa
o problema nas configurações. Não usa a configuração de OCR de veículos/SGV.

## Arquitetura

| Componente | Responsabilidade |
| --- | --- |
| `WeighingCameraService` | Enumeração, iniciar, preview, snapshot, encerrar |
| `DesktopWeighingCameraService` | Adaptador real `camera` + `camera_windows`, sem áudio/vídeo gravado |
| `CaptureImageProcessor` | Decodificar, corrigir orientação, recortar ROI e gerar evidência com timestamp |
| `LocalCaptureImageProcessor` | Executa processamento pesado em isolate |
| `WeightOcrService` | Receber imagem e devolver texto, peso, confiança e erro |
| `TesseractWeightOcrService` | Processo local assíncrono com timeout e TSV real |
| `ManualCaptureController` | Estados, validação, fallback, confirmação e coordenação |
| `ManualWeighingEvidenceStore` | Fotos e auditoria imutáveis |
| `WebcamConfigurationStore` | Configuração persistente local da estação |
| `ManualCaptureServices` | Composição e injeção de dependências |

O estado usa `CaptureStage`, evitando booleans independentes para cada etapa.
Um controlador exige `ManualAuthorization`; o ponto de entrada operacional
somente o constrói depois de verificar a autorização existente. A câmera de
diagnóstico tem ciclo de vida independente. Cancelar, fechar e prosseguir
encerram o recurso; retornos tardios de inicialização/OCR não atualizam diálogo
fechado. Timeout, erro de abertura e falha de captura exibem mensagens amigáveis.

## Timestamp e região do visor

Preview contém relógio atualizado por segundo com `DateTime.now()` local do
Windows (`dd/MM/yyyy HH:mm:ss`). A foto tem o horário do snapshot desenhado
nos pixels, em faixa preta com letras brancas, antes da codificação JPEG.
Não depende de EXIF. O timestamp fica fora da região enviada ao OCR.

`DisplayRegion` é normalizada e extensível; nesta etapa é fixa, central, com
80% da largura e 50% da altura. O retângulo amarelo mostra a região analisada.
Enquadrar **somente o peso** nessa região; relógios, etiquetas e número de série
devem ficar fora. O OCR recebe o recorte original em escala de cinza; a evidência
conserva o enquadramento completo. Não existe editor de ROI persistente ainda.

## OCR real e instalação

Escolha inicial: **Tesseract 5**, executado localmente pelo adaptador CLI.
Instalar separadamente o executável Windows e `eng.traineddata`, e colocar
`tesseract.exe` no PATH da estação antes de iniciar o aplicativo. Validar com
`tesseract --version` e `tesseract --list-langs`. O projeto não baixa executáveis
automaticamente nem contém engine/modelos binários. O construtor do adaptador
também permite definir um caminho absoluto no empacotamento futuro.

Comando usa argumentos estruturados, sem shell: imagem PNG temporária,
`stdout -l eng --psm 7 tsv`. Timeout de 15 segundos encerra o processo. Arquivos
temporários de OCR são removidos ao terminar. O snapshot temporário do plugin
também é removido depois de lido; só a foto com timestamp é preservada.

Opções avaliadas:

* `camera_windows`, mantido no ecossistema Flutter: enumeração, preview e fotos;
  não suporta streaming de frames, portanto snapshot é a estratégia adotada.
* Windows.Media.Ocr: local e sem instalador externo, mas requer ponte WinRT e
  idiomas disponíveis; não entrega a mesma confiança por palavra utilizada aqui.
* Tesseract: local, offline, Windows, licença Apache 2.0, saída TSV com confiança
  por palavra, engine/modelos substituíveis. Exige instalação e calibração.
* Nenhum serviço cloud foi adicionado.

O interpretador TSV não é um OCR: apenas valida a saída **real** da engine.
O perfil inicial aceita exatamente um inteiro de 1 a 7 dígitos, opcionalmente
seguido de `kg`. Não usa o primeiro número de um texto arbitrário. Rejeita
horários, rótulos, múltiplos valores e separadores ambíguos (`12.190`/`12,190`).
A confiança é a menor confiança das palavras do resultado dividida por 100.
Somente valores finitos, não negativos e confiança **>= 0,90 e <= 1** são aceitos.
O operador sempre confirma o valor. Confiança não equivale a garantia metrológica.

Limitação: um número de série isolado, composto apenas por dígitos e situado
dentro da ROI, pode satisfazer esse perfil. É necessário enquadramento correto
e validação com imagens reais de cada modelo. Displays de sete segmentos,
reflexos, casas decimais e separadores podem exigir perfil específico, melhor
pré-processamento ou treinamento. Não existe alegação de precisão calibrada.
Não existe OCR falso quando a engine está ausente: retorna
`OCR_ENGINE_INDISPONIVEL` e libera fallback com a foto preservada.

## Evidência e auditoria

`manual_weighing/evidence/` contém:

* `pesagem_manual_YYYYMMDD_HHMMSS_<micros>_<aleatório>.jpg` por snapshot salvo;
* `<id>_attempt.json` por tentativa processada;
* `<id>_confirmed.json` por valor revisado pelo operador, inclusive sem foto.

IDs têm horário local, microssegundos e aleatoriedade. Criação exclusiva impede
sobrescrita silenciosa. Na tentativa, `finalWeight` fica nulo; na revisão guarda
o valor final. Registros incluem placa, data/hora da foto, instante da revisão,
cameraId/nome, caminho da foto, texto OCR, peso OCR, confiança, erro OCR, peso
final, origem `CAMERA_OCR` ou `MANUAL_FALLBACK`, motivo técnico, autorizador,
justificativa humana e ROI. Uma nova revisão tem identidade própria e referencia
a foto anterior, sem duplicá-la ou alterar o arquivo.

Falhas de gravação nunca são anunciadas como sucesso. Se a auditoria final não
puder ser persistida, a confirmação permite tentar novamente após corrigir
espaço/permissões. Falta da câmera permite continuar normalmente pela contingência.
Gravação de foto e JSON não é uma transação de banco: interrupção de energia pode
deixar foto sem JSON ou arquivo parcial; avaliar armazenamento transacional e
hashes numa próxima etapa. Não há assinatura digital nem proteção contra edição
externa dos arquivos. Aplicar permissões Windows adequadas na implantação.

Não grava vídeo, não envia imagens à internet, não remove evidências ao cancelar
e não faz limpeza automática. **Política de retenção, limites de disco, backup e
controle de acesso deverão ser definidos posteriormente.**

## Contratos, mocks e testes

Nenhum campo/endpoint da Libra-API foi criado. Modelos e arquivos são locais.
O agregado operacional existente continua em memória como antes. Integração
futura de imagem, origem e auditoria com API exigirá definição explícita de
contrato, vínculo ao ID definitivo da pesagem e política de upload/retenção.

Mocks ficam exclusivamente em `test/support/manual_capture_mocks.dart`:
câmera, OCR, processador e armazenamento/configuração. `test/flutter_test_config.dart`
injeta esses mocks na suíte para impedir acesso a hardware e dados da estação.
O aplicativo de produção sempre usa adaptadores reais. Há testes específicos
do processador real, engine ausente, armazenamento real em diretório temporário,
perfil TSV, confiança, zero, captura/fallback, encerramento e diagnóstico.
Os testes anteriores continuam cobrindo senha, permissões, justificativa,
entrada/saída manual e disponibilidade com indicador desconectado.

Validação física pendente: selecionar uma webcam Windows, testar desconexão/uso
concorrente/permissão negada, instalar Tesseract e medir acurácia/latência com os
visores usados na operação. Mocks não certificam hardware nem a acurácia óptica.

Referências: [camera_windows](https://pub.dev/packages/camera_windows),
[Tesseract 5](https://tesseract-ocr.github.io/tessdoc/),
[instalação](https://tesseract-ocr.github.io/tessdoc/Installation.html),
[TSV e uso CLI](https://tesseract-ocr.github.io/tessdoc/Command-Line-Usage.html),
[Windows OCR](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine).

## Arquivos da entrega

Criados:

* `lib/features/pesagem/manual_capture/camera_service.dart`
* `lib/features/pesagem/manual_capture/capture_models.dart`
* `lib/features/pesagem/manual_capture/image_processor.dart`
* `lib/features/pesagem/manual_capture/weight_ocr_service.dart`
* `lib/features/pesagem/manual_capture/evidence_store.dart`
* `lib/features/pesagem/manual_capture/manual_capture_services.dart`
* `lib/features/pesagem/manual_capture/capture_controller.dart`
* `lib/features/pesagem/manual_capture/capture_dialog.dart`
* `lib/features/configuracoes/manual_webcam_settings.dart`
* `test/manual_capture_test.dart`
* `test/support/manual_capture_mocks.dart`
* `test/flutter_test_config.dart`
* `docs/pesagem-manual-webcam.md`

Alterados:

* `lib/main.dart`: carrega configuração local antes de abrir a aplicação.
* `lib/features/configuracoes/settings_models.dart`: injeta os serviços da estação.
* `lib/features/configuracoes/configuracoes_page.dart`: nova seção e descrição de persistência.
* `lib/features/pesagem/pesagem_page.dart`: chama captura somente após autorização existente.
* `lib/features/pesagem/weighing_dialogs.dart`: remove entrada imediata antiga e mostra origem na confirmação.
* `lib/features/pesagem/weighing_preview.dart`: transporta evidência para auditoria da leitura.
* `test/widget_test.dart`: adapta expectativas à etapa nova e mantém regressão da autorização/cancelamento/layout.
* `test/controlled_evolution_widgets_test.dart`: verifica que hardware só inicia depois da autorização e fecha em cada leitura.
* `pubspec.yaml` e `pubspec.lock`: dependências de câmera, processamento e diretório local Windows.
* `windows/flutter/generated_plugin_registrant.cc` e `windows/flutter/generated_plugins.cmake`:
  atualizados pelo Flutter para registrar o plugin Windows.

Os testes também executam o adaptador real do Tesseract com imagem sintética
quando a engine está instalada (caso contrário esse teste específico é marcado
como ignorado). Isso verifica a integração CLI; não representa teste com visor
físico de sete segmentos.

Validação desta entrega: `dart format` aplicado nos 20 arquivos Dart envolvidos;
`flutter analyze` sem problemas; `flutter test` com 184 testes aprovados;
`flutter build windows --debug` concluído. Tesseract 5.5 instalado nesta estação
executou o teste real com imagem sintética. A validação com câmera/visor físicos
permanece pendente.
