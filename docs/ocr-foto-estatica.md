# Pesagem Manual por fotografia preservada

## Fluxo anterior e mudança

O fluxo anterior podia iniciar `LiveWeightReader` ao abrir a câmera, consumir
fotos sem clique, exigir consenso temporal e aproveitar uma foto anterior já
aceita. O outro caminho também capturava várias fotos dentro de uma chamada de
`capture()`. Agora o controller não cria, inicia ou consulta leitor contínuo.
O preview continua sendo o preview nativo da webcam, sem OCR pesado.

1. Operador autorizado enquadra a **Área do Peso** e clica **Capturar peso**.
2. Uma única chamada de câmera fornece uma foto com identidade própria.
3. Os bytes originais são copiados e salvos antes de decodificação/processamento.
4. A evidência com data/hora é criada e salva; a interface congela essa foto.
5. **Analisando imagem...** executa ROI, seleção do grupo principal e variantes
   sobre cópias da mesma foto.
6. Concordância entre pipelines libera **Peso identificado: ... kg** ou falha.
7. O operador confirma; nenhuma inferência grava uma pesagem automaticamente.

Após resultado, **Capturar novamente** volta ao preview. O clique seguinte em
**Capturar peso** obtém outra fotografia/identidade. Não há retry automático de
frames nem reaproveitamento silencioso da imagem anterior. O fluxo sem OCR
permanece foto + digitação; a contingência sem câmera continua autorizada.

## Original, evidência e integridade

O armazenamento local existente recebeu `saveOriginal`. Grava os bytes exatos
entregues pelo driver em `manual_weighing/original/pesagem_manual_<id>.bin`.
A extensão `.bin` não presume o codec do driver; o conteúdo pode ser JPEG/PNG.
O caminho fica em `originalImagePath`. A aplicação cria arquivos exclusivamente,
recusa sobrescrita e nunca usa esse arquivo como destino de processamento.

A evidência continua em `manual_weighing/evidence/pesagem_manual_<id>.jpg`,
com timestamp visual local do Windows. `imagePath` permanece compatível e é
também exposto como `evidenceImagePath`. A imagem limpa é a fonte do OCR; o carimbo
nunca passa pelo recorte de análise. O modo foto sem OCR agora também mantém
a versão limpa, além da evidência.

O JSON associa `captureAttemptId`, caminhos, data/hora, autorizador, justificativa,
origem, peso, confiança, método, candidatos e motivo de fallback. A gravação da
fotografia é registrada antes de iniciar OCR; outro registro preserva o resultado.
A confirmação continua possuindo identidade própria e aponta para a mesma captura.
Falha de OCR não apaga/substitui a foto. Falha ao recapturar mantém a última foto
completamente salva e o motivo técnico. Falha de gravação da auditoria final
continua impedindo confirmação silenciosa.

`originalSha256` é um campo opcional reservado; o hash ainda não é calculado.
Exclusividade de criação impede sobrescrita pelo aplicativo, mas não equivale a
verificação criptográfica contra modificações externas. Não há banco ou upload novo.

## Uma função de análise

`analyzeCapturedImage` em `captured_image_analysis.dart` recebe `CapturedPhoto`,
configuração, processador e reconhecedor. Destaca outra cópia dos bytes, aplica o
processador e valida o resultado. É chamada pela Pesagem Manual, pelo botão
**Capturar imagem de teste** em Testar câmera e pela ferramenta de arquivo.
Persistência antecede a chamada no fluxo operacional e na ferramenta de arquivo.
O teste explícito da câmera não cria pesagem nem registros de autorização/peso;
pode salvar o pacote diagnóstico de desenvolvimento.

## ROI e seleção do número principal

Permanece a calibração visual retangular normalizada com movimento/tamanho,
correção de perspectiva/inclinação e persistência por estação/câmera. A interface
nomeia esse recorte como **Área do Peso: ROI e validação OCR**. O OCR começa nessa
ROI, nunca no preview com timestamp.

O localizador inspeciona componentes em duas polaridades em uma cópia limitada a
1000×600. Forma grupos com alturas compatíveis, baseline próximo e distância
horizontal limitada. O ranking considera altura, área ocupada e extensão do grupo;
coordenadas e proximidade determinam alinhamento/agrupamento. O primeiro número
encontrado não ganha prioridade. Grupos distintos de força semelhante são
rejeitados como ambíguos. Um traço compatível com sinal negativo antes do grupo
também é rejeitado.

Caixas dos corpos dos caracteres ficam em coordenadas da ROI corrigida e são
salvas em `characterPositions`/`principalBoxes`. Elas localizam; não classificam
dígitos. Para um único dígito, ou quando a localização não encontra grupo,
permanece a ROI calibrada pelo operador. O algoritmo não garante completude em
uma ROI que já cortou algum dígito; calibrar somente o peso completo continua
fundamental. Não há preenchimento de dígitos ausentes.

## Processamento e engines

Na cópia do grupo principal são geradas quatro variantes com o processador
existente, limites de dimensão, margem e upscale limitado:

- grayscale com contraste e polaridade normalizada;
- Otsu;
- threshold adaptativo;
- contraste invertido.

Nenhuma delas é a evidência oficial. Não se aumenta a fotografia de auditoria
para tentar OCR, nem se a substitui por preto e branco.

O Tesseract genérico persistente recebe cada variante pronta, com whitelist
`0123456789`, sem aplicar novamente a seleção automática de linha/polaridade.
Um único handle/modelo permanece no isolate serializado e é reutilizado entre
variantes e sessões. A geometria é executada adicionalmente na mesma ROI principal.
Resultado geométrico rejeitado, inclusive `SEGMENT_CLIPPED`, não vota.

Tesseract especializado, genérico legado e leitor geométrico continuam no projeto
e nas ferramentas estáticas existentes. Não foram removidos nem instaladas novas
engines. O caminho padrão usa quatro variantes nativas + geometria para limitar
custo; não executa toda a antiga cascata de subprocessos especializados por foto.
Os leitores temporais e seus testes permanecem isolados como legado, sem serem
acionados pelo controller ou pela composição local da Pesagem Manual.

## Concordância e casas decimais

`decimalPlaces` da estação continua obrigatório para o novo reconhecedor: 0 a 3,
conforme o indicador físico. Não é presumido nem obtido de ponto visual.
Exemplos: `5700` + 1 → `570`; `1342` + 2 → `13`; nunca arredonda.
Texto bruto de cada tentativa é preservado. Um separador interno isolado pode
ser removido de uma sequência válida; letras, unidades e sinais não viram números.

Cada pipeline pode votar uma vez por sequência. Candidatos precisam de gramática,
escala/faixa válidas e confiança OCR de pelo menos 0,40. Requer:

- pelo menos dois pipelines distintos concordantes;
- suporte estritamente maior que o próximo candidato e pelo menos 2/3 dos votos
  elegíveis (vazios, fora de faixa e inválidos não votam);
- média de confiança OCR do grupo >= 0,45;
- score >= 0,65: `0,40 × médiaOCR + 0,50 × concordância + 0,10 × validação`.

`5700, 5700, 5708, vazio` pode passar com média suficiente; empate, retorno único
ou resultados muito fracos não passam. O score é uma regra de decisão, não uma
probabilidade calibrada. Pipelines da mesma foto são correlacionados; não são
apresentados como fotos independentes ou garantia de peso correto.

Somente após aprovação, `int(rawDigits) / 10^decimalPlaces` é truncado e liberado.
O valor fracionário pode aparecer como candidato no diagnóstico para a validação
de faixa. A votação é sobre os dígitos integrais, não sobre pesos truncados.
Metadados de snapshot não promovem uma leitura fraca isolada de uma engine legada.
Retornos rejeitados permanecem com peso final nulo, com seus textos nas tentativas.

## Interface, teste e fallback

O preview não apresenta indicador verde derivado de frames invisíveis. Antes da
captura há status e botão; durante a análise, foto congelada e progresso. Uma
leitura aprovada mostra peso e **Confirmar**; contingência mantém a confirmação
manual existente. **Capturar novamente** não destrói os arquivos já salvos.

Em falha, o peso automático não é preenchido. O operador pode voltar ao preview
ou digitar peso conforme a autorização existente, preservando a foto e a origem
`MANUAL_FALLBACK`. Aprovação automática usa `CAMERA_OCR`, mas ainda exige clique.
Sem OCR configurado continua `MANUAL_WITH_PHOTO`. Serial/TCP, fechamento, ticket,
Libra e controle de acesso não receberam alterações de implementação.

Testar câmera permite ajustar a região e **Capturar imagem de teste**, uma foto
por clique. Exibe original limpa, ROI, variantes, caixas/resultados em diagnóstico,
candidato, peso e falha. A foto de teste fica congelada; mudar a ROI limpa essa
análise para evitar confundir configurações. Diagnóstico debug habilitado usa o
store existente (até dez pacotes por execução), com JSON e imagens das tentativas.

## Arquivo estático reproduzível

Na raiz, com o mesmo SDK Dart do projeto no PATH:

```powershell
dart run tool/analyze_weight_photo.dart foto.jpg --config webcam.json --output build/photo_analysis
```

`webcam.json` é a configuração local da estação (inclui ROI, perfil, casas e faixa).
Use a **foto completa**, não uma ROI que seria recortada novamente. Imagens JPEG
e PNG são lidas pelo mesmo decodificador da câmera. Cada execução cria diretório
novo; preserva original binário, evidência JPEG, original normalizada PNG, ROI
original/corrigida, variantes e `result.json`. Não registra pesagem ou simula
confirmação humana. Tudo roda local, sem Python/API/cloud.

Reprodução realizada com `ind570_5c581db1/original.png`, ROI da amostra, casas=1:
`rawDigits=5700`, peso final `570`, duas variantes elegíveis concordantes,
score 97,2%; geometria rejeitada e variante fraca ficaram fora da votação.
Tempo medido da análise: **4061 ms**, incluindo partida do Tesseract (2051 ms na
primeira variante). As variantes seguintes levaram 54, 28 e 76 ms no motor;
o restante inclui seleção/preprocessamento e geometria. Essa medição é de uma
foto estática, não avaliação de precisão em campo nem latência garantida.
Artefatos locais: `build/snapshot_analysis/photo_7c9dce01/result.json`.

## Arquivos desta rodada

Novos:

- `lib/features/pesagem/manual_capture/captured_image_analysis.dart`;
- `lib/features/pesagem/manual_capture/snapshot_weight_recognition.dart`;
- `tool/analyze_weight_photo.dart`;
- `test/snapshot_weight_capture_test.dart`;
- `docs/ocr-foto-estatica.md`.

Alterados no fluxo: `capture_controller.dart`, `capture_dialog.dart`,
`capture_models.dart`, `evidence_store.dart`, `image_processor.dart`,
`manual_capture_services.dart`, `persistent_digits_ocr.dart`,
`tesseract_runtime.dart` e `manual_webcam_settings.dart`.
Testes ajustados: `manual_capture_test.dart`, `manual_capture_modes_test.dart`,
`configured_digits_test.dart`, `seven_segment_ocr_test.dart` e mocks de captura.
README/documentação anterior receberam referência a esta estratégia atual.

As alterações locais anteriores foram preservadas. Nenhum commit, push,
integração com banco ou alteração em projetos vizinhos foi realizado.

## Validação final

- `dart format`: formatação concluída nos arquivos Dart desta rodada.
- `flutter analyze --no-pub`: nenhum problema encontrado.
- `flutter test --no-pub --concurrency=1`: **345 testes aprovados**, sem falhas.
- Nove testes específicos de snapshot cobrem original imutável, imagem processada
  separada, timestamp, ROI, maior grupo, variantes, consenso, escala, bloqueio de
  leitura fraca isolada, recaptura, fallback, mesma função para arquivo/câmera,
  confirmação humana e exclusividade do armazenamento.
- Os testes existentes de captura foram adaptados de múltiplos frames para uma
  foto. Os testes isolados das engines/consenso temporal legado foram preservados.
- CLI executado com a amostra real: `5700 → 570 kg`, conforme a medição acima.

Não foi realizada validação física da webcam/unidade nesta execução. A amostra
estática confirma reprodução do pipeline; homologação operacional ainda precisa
variar pesos, iluminação, foco, indicador e configuração física de casas decimais.
