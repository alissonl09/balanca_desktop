# Pesagem Manual assistida por webcam (Windows)

> Atualização de 05/11/2026: a cascata especializada, modelos offline,
> pré-processamentos, comparação e diagnóstico atuais estão descritos em
> [OCR de sete segmentos](ocr-sete-segmentos.md). As seções anteriores abaixo
> preservam o histórico das etapas de implementação.

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

### Orientação da webcam

O `camera_windows 0.3.0+1` espelha por padrão somente a textura nativa do
preview (`TextureHandler::mirror_preview_ = true`), sem expor setter Dart.
`UnmirroredCameraPreview` compensa esse comportamento no Windows. O photo sink
é independente e não aplica esse mirror de software: não se deve inferir que
a foto está espelhada pelo preview ou por `lensDirection.front`.

`normalizeCameraImage` normaliza os pixels com EXIF (rotação e reflexão),
remove a orientação já aplicada e, depois, aplica somente o ajuste explícito
da estação. OCR e evidência derivam dessa mesma imagem; o timestamp é desenhado
depois de todas as transformações. A opção local **Inverter horizontalmente**
fica desativada por padrão, inclusive para configurações antigas. Ative somente
se o próprio driver entregar imagem invertida após a orientação EXIF; ela afeta
preview e captura, inclusive no diagnóstico.

A biblioteca Windows informa `sensorOrientation: 0` e lente frontal para todas
as webcams, e fixa a orientação do dispositivo em landscapeRight. Esses valores
são placeholders, não metadados reais do sensor, e não provocam rotação/flip
adicional. Sem EXIF não há detecção automática da montagem física da webcam.
Ao atualizar o plugin, revalidar o mirror nativo. Validar na estação com um
visor assimétrico (por exemplo `12190`) e abrir também a evidência salva.

Preview contém relógio atualizado por segundo com `DateTime.now()` local do
Windows (`dd/MM/yyyy HH:mm:ss`). A foto tem o horário do snapshot desenhado
nos pixels, em faixa preta com letras brancas, antes da codificação JPEG.
Não depende de EXIF. O timestamp fica fora da região enviada ao OCR.

`DisplayRegion` usa coordenadas normalizadas (0 a 1), persistidas em `webcam.json`.
O retângulo amarelo e o crop usam a mesma configuração. O preview respeita a
proporção informada pela câmera, evitando deslocar a ROI em webcams 4:3.
Em Configurações → Webcam da Pesagem Manual → Ajustar ROI e validação OCR,
edite X, Y, largura e altura; pressione Enter em cada campo para salvar.
Reduza largura/altura antes de mover uma região que ultrapassaria a imagem.
A configuração antiga mantém a ROI central de 80% por 50% como padrão compatível.
É necessário calibrar esse padrão. Dentro da ROI, o processamento agora tenta
isolar uma linha de caracteres claramente maiores antes do OCR. Isso não é
detecção do modelo do indicador nem substitui o enquadramento da estação.

Para os exemplos IND560/IND570, enquadrar o número principal inteiro, incluindo
sinal e separador decimal. Deixar fora capacidade, tara/PT, segunda leitura,
menus e teclado. Nos exemplos anexados, os pesos principais são 570.0, 0.00 e
0.000. O parser interpreta ponto/vírgula sempre como DECIMAL: 12.190 significa
12,19 kg, nunca 12.190 kg inteiros. Para 12190, o visor deve mostrar 12190 ou
12 190; não inferimos separador de milhares. A evidência mantém a foto inteira
corrigida e o timestamp; o OCR recebe o crop sem timestamp.

## OCR real, diagnóstico e instalação

A implementação anterior já executava **Tesseract local**, não mock.
Recebia uma ROI fixa em grayscale, executava PSM 7 e aceitava somente inteiros.
Não havia upscale, variantes, ROI configurável ou estabilidade entre frames.
Isso rejeitava os decimais dos exemplos mesmo quando o OCR os reconhecia.
O texto/confiança da tentativa anterior não foram fornecidos; não é possível
atribuir uma causa única retroativamente. Na investigação inicial, o executável não foi
encontrado no PATH: sem ele a execução retorna OCR_ENGINE_INDISPONIVEL,
texto vazio e confiança zero. Erro de modelo/engine é OCR_ENGINE_ERRO,
com stderr limitado a 1000 caracteres no diagnóstico/auditoria.

A distribuição Windows agora inclui Tesseract **5.5.3** e o modelo inglês
**tessdata_best 4.1.0** em `ocr/`, ao lado do executável. Não precisa instalar
Tesseract nem mudar PATH na estação. Na máquina de build, preparar o runtime
com `tool/prepare_windows_ocr.ps1` (requer 7-Zip e política de scripts compatível)
antes de `flutter build windows --release`. Fontes e SHA-256 estão fixados no
script. O instalador é somente extraído dentro do projeto, sem executá-lo ou
alterar registro/PATH. `runtime/windows/tesseract/` é ignorado pelo Git; o CMake
copia engine, DLLs, modelo e documentação ao pacote. Distribua a pasta completa.

Resolução: caminho explicitamente configurado (construtor, dart-define ou variável
de ambiente `TESSERACT_PATH`), engine junto ao app, runtime local de desenvolvimento,
instalações Windows conhecidas e, por último, PATH. O caminho do modelo é enviado
explicitamente com `--tessdata-dir`. TSV é ativado por parâmetro, sem depender
de arquivo de configuração `tsv` instalado na estação. Ausência da engine/modelo,
timeout, baixa confiança e divergência agora exibem motivos distintos e código
na tela, inclusive em release. Foto e fallback manual são preservados.

Processamento real, em isolate:

1. Corrigir orientação EXIF e espelhamento configurado, antes do crop.
2. Recortar ROI na imagem original, sem relógio.
3. Localizar componentes de alto contraste dentro da ROI (limiar de Otsu e
   componentes conexos). Quando há pelo menos dois caracteres grandes alinhados
   e os demais são claramente menores, recortar a linha principal, preservando
   margens para sinal, separador e unidade. Traços horizontais à esquerda na
   altura do sinal são incluídos mesmo quando afastados. Duas linhas grandes
   ou geometria ambígua mantêm a ROI inteira para o parser estrito rejeitar.
   A análise geométrica não identifica nem substitui dígitos. O diagnóstico
   registra o prefixo `dominant_line_` quando esse recorte é aplicado.
   A evidência continua sendo a foto inteira, com data e hora.
4. Redimensionar com interpolação cúbica, até 4x, limitado a 1200 x 160 pixels
   (altura de até 100 pixels quando a linha principal foi isolada).
   A ampliação excessiva piorou a leitura nos testes reais da engine e foi limitada.
5. Comparar grayscale com normalização de contraste, sua inversão e inversão
   binarizada em 128. A normalização anterior ao threshold ajuda em contraste baixo.
6. Executar Tesseract offline, PSM 7, dicionários desativados, TSV real.
   A primeira variante mantém letras para detectar rótulos/horários indevidos.
   As outras restringem para `0123456789.,-kgKG`, exceto quando a primeira leitura
   contém unidade kg: nesse caso a whitelist pode zerar a confiança da engine,
   portanto as variantes mantêm reconhecimento livre e o parser estrito.
7. Exigir que a primeira variante seja válida e que pelo menos duas variantes
   tenham confiança >= 0,90 e o mesmo peso. Qualquer valor divergente, mesmo com
   confiança menor, invalida a captura. Não inventar confiança ou corrigir O/I.

PSM 7, inversão, upscale e restrição de caracteres seguem as recomendações da
[documentação do Tesseract](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html).
Nenhuma etapa identifica automaticamente o modelo do indicador.
Não foi aplicada redução de ruído ou correção de perspectiva indiscriminada.
Inclinação/perspectiva devem ser reduzidas pelo posicionamento da câmera.
As fixtures exercitam perspectiva moderada e ruído no pré-processamento,
mas isso NÃO comprova reconhecimento óptico nessas condições.

Os exemplos têm dígitos luminosos verdes/ciano, incluindo matriz de pontos;
não são todos visores clássicos de sete segmentos. Um decodificador por sete
regiões fixas não é uma alternativa segura universal para eles. Nesta entrega
não há classificador de sete segmentos nem modelo treinado para IND560/570.
Tesseract convencional ainda pode falhar nesses displays: se a calibração
física mostrar isso, será necessário treinamento/modelo específico com corpus
rotulado, sem usar heurística para inventar dígitos.

Parser: uma única expressão numérica, sinal opcional, até sete dígitos inteiros
(ou agrupamento explícito por espaços), até três decimais e unidade kg opcional.
Rejeita horários, rótulos e dois valores independentes. A faixa da estação é
configurável (padrão 0–100000 kg). Negativos são reconhecidos pelo parser para
diagnóstico, mas rejeitados na proposta, preservando a regra operacional vigente.
Nenhum algoritmo impede que um número de série isolado pareça peso: ROI correta
e confirmação humana continuam essenciais.

Ao clicar Capturar peso, o controlador captura até três fotografias distintas,
com intervalo mínimo de 200 ms após cada análise. Cada frame precisa passar
consenso/confiança/faixa. Os três valores devem ser exatamente iguais; qualquer
falha ou mudança encerra a sequência e libera manual, sem votação por maioria.
Todos os frames processados têm foto com timestamp e JSON próprios; a revisão
final aponta para o último frame. A auditoria registra o contador de leituras
estáveis e as variantes (texto, confiança, peso, erro), sem bytes de imagens.
Não é streaming: o plugin Windows utiliza snapshots sequenciais. O timeout é
15 segundos por processo, até três variantes por frame; a latência real precisa
ser medida na estação. A UI permanece assíncrona e mostra Analisando visor.
O operador deve manter o visor estável durante toda a sequência e confirmar
humanamente o peso proposto. Leituras iguais não garantem acurácia metrológica.

Para ativar o diagnóstico, execute uma compilação debug (`flutter run -d windows`),
abra a seção Ajustar ROI e validação OCR e ligue Diagnóstico OCR. Após a autorização
habitual, em Pesagem Manual capture e expanda Diagnóstico OCR: mostra imagem
corrigida sem timestamp, crop, grayscale, inversão, threshold, texto bruto,
confiança e resultado/falha da última captura. O console registra as mesmas
informações por frame, sem binário. Em release, painel, chave e logs ficam ocultos.
Testar câmera continua sendo somente preview, agora com a ROI configurada.

Na balança física, validar IND560 e IND570 com zero, 12190, 10000, casas decimais,
carga variando, sinal negativo, tara/capacidade visíveis fora da ROI, distância,
foco, reflexos, luminosidade, orientação, mirror e ângulo. Conferir peso visível,
OCR e foto salva. Medir rejeições, leituras erradas e latência. Repetir com folha
impressa e monitor, sabendo que não reproduzem refresh, reflexos e luminosidade
do visor físico. Não há alegação de acurácia validada nos anexos ou no hardware.

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

Validação da revisão OCR: `dart format` aplicado, `flutter analyze` sem problemas,
suíte `flutter test` com 219 testes aprovados, sem testes ignorados, incluindo
a engine real. `git diff --check` sem erros.
`flutter build windows --release` concluído. Pacote completo gerado em
`build/windows/balanca_desktop-ocr-2026-11-04.zip`, com engine, DLLs, modelo
e instruções para a estação. A engine copiada para o Release foi executada
com a fixture verde 570.0: as três variantes concordaram, com confiança acima
de 96%. Isso não confirma o resultado na outra estação nem no visor físico.
As 11 fixtures PNG sintéticas são reproduzíveis com
`dart tool/generate_ocr_fixtures.dart`. Cobrem números, decimais verde/ciano,
contraste baixo, mirror, perspectiva, ruído, ausência e dois números.
Os testes de fixtures validam crop/pré-processamento real; cinco fixtures também
passam pelo Tesseract real (12190, 0, 10000, 0.000 ciano e 570.0 verde).
Há ainda integração real para texto preto em branco com unidade kg.
Os testes de parser, consenso e estabilidade validam regras com resultados controlados. Não são
uma medição de acurácia do Tesseract sobre fotografias dos indicadores.
A validação com fotografias reais da outra estação e com o indicador físico
permanece pendente. A mensagem genérica fornecida pelo operador não contém o
código técnico; não permite concluir que a engine estava ausente naquela estação.

Os testes reais também revelaram duas causas de rejeição corrigidas nesta revisão:
modelo rápido com baixa precisão nos dígitos verdes e confiança zero introduzida
pela whitelist em tokens misturando número e kg. O modelo best e o uso condicional
da whitelist corrigiram esses casos sem reduzir o limite de confiança de 90%.

Para analisar uma fotografia salva sem webcam e sem alterá-la:
`dart tool/diagnose_weight_ocr.dart foto.jpg x y largura altura`.
Sem coordenadas, a ferramenta analisa toda a imagem. Não incluir o timestamp na
ROI. A ferramenta exibe engine/modelo, texto/confiança e resultados por variante.

Arquivos desta revisão OCR (alterações preexistentes foram preservadas):

* `lib/features/configuracoes/manual_webcam_settings.dart`
* `lib/features/pesagem/manual_capture/camera_service.dart`
* `lib/features/pesagem/manual_capture/capture_controller.dart`
* `lib/features/pesagem/manual_capture/capture_dialog.dart`
* `lib/features/pesagem/manual_capture/capture_models.dart`
* `lib/features/pesagem/manual_capture/image_processor.dart`
* `lib/features/pesagem/manual_capture/manual_capture_services.dart`
* `lib/features/pesagem/manual_capture/weight_ocr_service.dart`
* `test/manual_capture_test.dart`
* `test/support/manual_capture_mocks.dart`
* `test/weight_ocr_pipeline_test.dart` (novo)
* `test/fixtures/weight_ocr/*.png` (11 novas imagens sintéticas)
* `tool/generate_ocr_fixtures.dart` (novo)
* `lib/features/pesagem/manual_capture/tesseract_runtime.dart` (novo)
* `test/tesseract_runtime_test.dart` (novo)
* `tool/diagnose_weight_ocr.dart` (novo)
* `tool/prepare_windows_ocr.ps1` (novo)
* `runtime/windows/README.md` (novo)
* `.gitignore` e `windows/CMakeLists.txt`: runtime local ignorado e incluído no build
* `docs/pesagem-manual-webcam.md`

Somente `balanca_desktop` foi editado. Sem commit ou push.

### Revisão após o print com `OCR_SEM_LEITURA` (04/11/2026)

No print, a ROI inclui capacidade, tara e parte do teclado, além de `570.0`.
O PSM 7 anterior recebia toda essa área como uma única linha. Foi adicionada
a localização geométrica descrita acima em `dominant_weight_line.dart`, antes
do redimensionamento e das três variantes existentes. A confiança mínima de
90%, o consenso e a estabilidade entre fotografias continuam exigidos.

As novas fixtures `panel_570.png` e `panel_negative.png` são sintéticas e
reproduzíveis pelo gerador: incluem marca, capacidade, tara e teclado.
O painel positivo passa pela engine real; a regressão do negativo exige que
ele não seja aceito como positivo. Há também verificação nos pixels de que
um sinal afastado permanece no recorte e de que duas linhas igualmente grandes
não são isoladas seletivamente. Total: 13 fixtures e 223 testes aprovados,
sem testes ignorados; `flutter analyze` sem problemas e build Windows Release
concluído. O arquivo original da foto mostrada no print não estava disponível
no workspace para replay; não se afirma validação óptica dessa fotografia.

Pacote desta revisão:
`build/windows/balanca_desktop-ocr-linha-principal-2026-11-04.zip`.
Extrair a pasta completa e abrir o executável dessa nova pasta na estação.
