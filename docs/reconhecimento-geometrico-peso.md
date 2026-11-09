# Reconhecimento geometrico local do peso

A estrategia operacional e `WeightRecognitionService`: geometria -> Tesseract especializado -> Tesseract generico -> digitacao manual. O servico e injetado tanto na captura quanto no leitor continuo; a tela consome o contrato existente `WeightRecognitionResult` (alias compativel com `WeightOcrResult`). Nao houve alteracao de dependencias, API, projeto web, autorizacao ou justificativa.

## Por que mudar

O antigo `SevenSegmentWeightOcrService` ainda era Tesseract: modelos, PSM e variantes de preprocessing. A fixture optica IND570 inclui logo, capacidade, teclado, unidade e outros numeros na ROI antiga. Alem disso, os numeros grandes do IND570 sao glifos graficos arredondados, incluindo um 7 diagonal, e nao sete barras convencionais. Um traineddata de sete segmentos nao representa necessariamente essa fonte.

Referencias estudadas, sem importar ou copiar codigo:

- [OCR7Segment](https://github.com/lsmllw/OCR7Segment): densidade por regiao, normalizacao, pontos decimais, barras e dicionario. Licenca MIT verificada.
- [SegoDec](https://github.com/scottmudge/SegoDec): amostragem local do estado de segmentos e tabela de padroes. Licenca Apache-2.0 verificada.
- [Manual oficial IND570](https://www.mt.com/dam/product_organizations/industry/IndustrialTerminals/30205308_U_MAN_UG_IND570_EN.pdf): display grafico matricial, OLED/LCD conforme versao.
- [Manual oficial IND560](https://www.mt.com/mt_ext_files/Editorial/Generic/5/IND560_Install_Instructions_Editorial-Generic_1129137712195_files/IND560_Installation_Manual_EN.pdf): versao com display VFD grafico.
- [Referencia visual IND560](https://www.southernscientificinstruments.com/store/p7100/_blank): zeros arredondados em matriz ciano. A imagem externa foi inspecionada somente como referencia e nao incorporada como fixture ou asset distribuido.

## Calibracao obrigatoria

Em Configuracoes, selecione a webcam, habilite a leitura e escolha o perfil: Automatico, IND560, IND570 ou Generico. Abra **Testar camera**, mova/redimensione o retangulo amarelo para conter somente os numeros grandes e o ponto. Deixe uma pequena margem sem incluir kg, capacidade ou icones. Pressione **Salvar ROI**.

`DisplayRegion` persiste x/y/largura/altura em 0-1 e o estado `calibrated`. Regioes antigas precisam ser salvas novamente para habilitar o motor geometrico. Ate isso ocorrer, o fallback anterior continua disponivel sobre o recorte, nunca sobre o frame completo. A regiao e restaurada por identificador da camera. A resolucao e o espelhamento continuam compartilhados pelo preview e pelo processador.

Ative **Corrigir perspectiva (quatro cantos)** para posicionar os pontos ciano: superior esquerdo, superior direito, inferior direito, inferior esquerdo. Os cantos sao normalizados dentro da ROI. Somente quadrilateros convexos, nao cruzados e dentro da imagem sao aceitos. Uma homografia projeta o quadrilatero num retangulo, com amostragem bilinear inversa. O ajuste angular existente continua disponivel depois da retificacao. A foto de evidencia nao sofre essas transformacoes.

## Algoritmo

1. O processador normaliza EXIF/espelhamento e fornece somente a ROI limpa, sem timestamp. O motor limita o tamanho a 1200x180 e amplia em no maximo 3x.
2. Selecao de cor por canais RGB oponentes: verde (IND570), ciano (IND560), canal adaptativo baseado no maximo/minimo RGB, ou luminancia no Generico. Nao se presume verde em todos os equipamentos. Otsu escolhe o threshold sobre esse canal. Nao se aplica indiscriminadamente CLAHE, erosion ou closing: eles podem apagar pontos ou unir glifos.
3. Projecao horizontal delimita a faixa dos digitos; projecao vertical separa slots, da esquerda para a direita. Componentes conectados refinam glifos graficos sem unir segmentos fisicamente desconectados. Altura, proporcao e alinhamento filtram componentes pequenos.
4. Cada bounding box possui coordenadas locais normalizadas. Sete janelas medem densidade A/B/C/D/E/F/G. A tabela explicita 0-9 esta em `sevenSegmentPatterns`. Nao ha escolha do digito mais proximo por tolerancia arbitraria. Um padrao inexistente ou proximo da fronteira de ativacao falha.
5. O 1 estreito tem verificacao propria de continuidade superior/inferior; nao e descartado pela largura. Os perfis Toledo tambem podem experimentar janelas para a fonte grafica, incluindo o 7 diagonal. Corpos conectados com altura completa selecionam a geometria grafica antes da decodificacao: isso evita confundir um 5 arredondado isolado com um 6 segmentado. Na ausencia dessa estrutura, a geometria pura e tentada primeiro. Resultados validos divergentes entre perfis sao rejeitados.
6. Componentes pequenos, compactos e proximos da base entre dois digitos sao candidatos a ponto. Mais de um ponto produz falha. Seu indice determina o corte da parte inteira. `rawText` mantem, por exemplo, 13.42 e `weight` e 13. Nao existe arredondamento nem divisao global por dez. `expectedDecimalPlaces` continua sendo validacao, nao inventa separadores ausentes.
7. Falta de nitidez/contraste util, glifos muito pequenos, cortes importantes e ambiguidades produzem falha. Um sinal negativo identificado geometricamente bloqueia a promocao para peso positivo, inclusive pelo fallback.

## Confianca e estabilidade

A confianca e uma heuristica explicita, nao uma probabilidade estatisticamente calibrada: margem das densidades em relacao ao threshold, contraste, estrutura e qualidade da ROI; o 1 exige suas proprias proporcoes. As parcelas sao combinadas conservadoramente pelo minimo. Os segmentos, densidades e janelas ficam no diagnostico. A faixa configuravel continua sendo aplicada e peso zero continua valido.

O consenso temporal existente foi preservado: 2-5 leituras requeridas (default 3), janela limitada a N+2, acordo minimo de 80% e as duas ultimas leituras iguais. Assim 4/5 supera uma divergencia isolada, mas valores continuamente variaveis nao confirmam. Votos consideram a leitura com separador; uma troca das casas exibidas reinicia a estabilidade. O resultado fornece frameCount e consensusCount. A captura de evidencia corresponde a um frame efetivamente aceito. Ha expiracao das leituras e nenhuma confirmacao automatica sem revisao humana.

O leitor continuo trabalha serialmente, em isolate para processamento, com intervalo minimo de 250 ms entre analises e sem fila de frames. Nao acompanha os 30/60 FPS da webcam. Tentativas de fallback podem reduzir essa taxa; a UI permanece assincrona.

## Tesseract secundario

O motor geometrico bem-sucedido evita completamente Tesseract. Caso contrario, o servico utiliza a cascata especializada existente (7seg, PSM 7/13, whitelist numerica com ponto), seguida do generico existente. Ha limites de tempo por processo e orcamento para as tentativas especializadas. O resultado registra metodo, falha primaria e diagnostico. A saida numerica de qualquer fallback e truncada antes de preencher a pesagem. Contratos antigos dos parsers e ferramentas de comparacao foram preservados.

Falha total preserva a foto e libera digitacao. Sucesso exige consenso, bloqueia digitacao e aguarda confirmacao humana. Autorizador, justificativa, auditoria, timestamp local do Windows e foto original com timestamp continuam no fluxo existente. Imagens binarizadas nao substituem evidencia.

## Diagnostico e replay

**Testar leitura** agora coleta varios frames para mostrar peso inteiro, metodo, confianca e consenso. Exibe frame original, ROI original, ROI corrigida, canal selecionado, binarizacao e overlay com caixas, indices, digitos, bits ativos e peso. Isso nao registra uma pesagem. O modo operacional nao exibe overlays. O armazenamento opcional de diagnostico continua local, em debug, limitado a dez sessoes por inicializacao; inclui JSON e imagens intermediarias.

Para uma foto PNG/JPG, indique explicitamente a ROI (nao ha inferencia sobre a camera inteira):

```powershell
dart run tool/recognize_display.dart foto.jpg 0.30 0.38 0.30 0.28 ind570 build/display_diagnostics
```

Ou use o JSON de configuracao, incluindo perspectiva:

```powershell
dart run tool/recognize_display.dart foto.jpg --config webcam.json --output build/display_diagnostics
```

O replay executa somente geometria, grava JSON e PNGs locais, nao precisa de webcam/Tesseract e nao confirma estabilidade de uma imagem unica. Os parametros devem representar uma ROI validada. O arquivo de entrada nao e alterado.

Regressao optica incluida com a fixture preexistente:

```powershell
dart run tool/recognize_display.dart test/fixtures/weight_ocr/ind570_webcam_570.png .305 .38 .292 .278 ind570 build/ind570_geometry
```

Resultado verificado nesta estacao: `570.0 -> 570`, confianca geometrica aproximadamente 92%, sem Tesseract. A ROI desses numeros e relativa a fixture de 1024x360, nao a fotografia original.

Para adicionar fixtures: recorte somente o visor, remova dados sensiveis, registre modelo, fonte/cor, ROI, resolucao e valor esperado em Markdown, e acrescente uma regressao que compare o peso e o sucesso. Imagens sinteticas analiticas e fotografias devem continuar identificadas separadamente.

## Arquivos e verificacao

Novos arquivos:

- `lib/features/pesagem/manual_capture/seven_segment_recognition_engine.dart`: perfis, isolamento, segmentacao e decodificacao.
- `lib/features/pesagem/manual_capture/weight_recognition_service.dart`: prioridade e fallback.
- `lib/features/pesagem/manual_capture/display_perspective.dart`: homografia.
- `tool/recognize_display.dart`: replay local com diagnostico.
- `test/geometric_weight_recognition_test.dart`: 29 cenarios novos, incluindo 0-9, sequencias, decimais, fixture optica, consenso, fallback, zero, faixa, ROI obrigatoria, negativo, homografia e evidencia, alem do 5 grafico isolado.
- Este relatorio.

Arquivos existentes alterados:

- `capture_models.dart`, `manual_capture_services.dart`: contrato, persistencia e composicao.
- `image_processor.dart`, `decimal_detector.dart`: ROI/correcao e reutilizacao da geometria sem busca automatica externa a ROI.
- `roi_editor.dart`, `capture_dialog.dart`, `manual_webcam_settings.dart`: calibracao, perfis, teste temporal e diagnostico.
- `capture_controller.dart`: preenchimento operacional somente com a parte inteira.
- `ocr_diagnostics_store.dart`: preserva tambem a ROI antes da correcao.
- `manual_capture_test.dart`, `manual_capture_modes_test.dart`, `seven_segment_ocr_test.dart`: expectativas ajustadas para perfil adicional, peso inteiro e diagnostico temporal.

Validacao: dart format, flutter analyze e flutter test. Resultados da execucao final sao registrados no retorno da tarefa; logs locais em build/geometric_analyze.log e build/geometric_full_test_final.log. O teste legado de Tesseract com timeout curto tambem foi executado isoladamente apos falhar por timeout sob concorrencia.

## Limites conhecidos

Nao houve validacao com uma webcam fisica conectada aos indicadores nesta tarefa. Ha uma fotografia optica IND570 preexistente; a referencia IND560 foi inspecionada visualmente, mas nao representa um dataset de regressao optica proprio. Os perfis iniciais precisam ser confrontados com novos numeros/fontes dos equipamentos da unidade, especialmente 1, 4, 6, 7 e 9. Nenhum conjunto sintetico garante confiabilidade industrial.

Reflexos, saturacao, desfoque, digitos tocando, perspectiva severa, fontes nao suportadas e pontos ausentes podem exigir recalibracao ou cair no fallback. O metodo assume digitos luminosos sobre fundo escuro. Nao se tenta resolver OCR textual generico. A ausencia fisica/optica do ponto nao pode ser inferida com seguranca sem uma configuracao especifica; nao ha hardcode global de casas decimais. A UI de perspectiva depende da correspondencia do preview do driver com a captura normalizada.

Tudo e local. Nenhum runtime de OpenCV, pacote novo, treinamento, ONNX ou servico cloud foi adicionado. A biblioteca equivalente de visao utilizada e `image`, ja presente no projeto. Nao houve commit nem push.
## Resultado da execucao final

- `dart format`: 28 arquivos verificados, sem mudancas pendentes de formatacao.
- `flutter analyze`: No issues found.
- `flutter test --concurrency=1 --reporter expanded`: 306 testes aprovados, incluindo 29 novos; duracao aproximada de 3min38s.
- Replay local da fixture IND570 com o motor final: success=true, rawText=570.0, weight=570, confidence=0.9230381105743425, metodo=Seven Segment.
- `git diff --check`: sem erros de whitespace.

A execucao sem concorrencia evita disputar CPU entre testes que iniciam processos Tesseract com timeout curto. Nao foi necessario aumentar o timeout do teste legado nem remover suas verificacoes.
