# OCR de dígitos com escala configurada na estação

O fluxo padrão passou a usar [uma foto preservada e consenso entre pipelines](ocr-foto-estatica.md).
Esta documentação registra a etapa anterior de consenso temporal e as regras de
escala que continuam válidas. O controller atual não inicia mais OCR contínuo.

## Ativação

Em Configurações → Webcam da Pesagem Manual → **Casas decimais do visor**, selecione
0, 1, 2 ou 3 conforme a configuração física do indicador. O campo é compacto e fica
fora das opções avançadas. Para o visor `570.0`, selecione **1**. Salve/calibre a ROI
somente na linha dos dígitos grandes. A seleção é persistida no JSON local da
estação como `decimalPlaces`; não muda configurações da API ou de outras estações.

Configurações antigas não recebem uma escala presumida: `decimalPlaces=null`
mantém o leitor legado até a seleção explícita. `expectedDecimalPlaces` antigo
era somente validação e não é migrado automaticamente para uma escala física.
Trocar câmera/indicador exige conferir novamente a precisão física selecionada.
As antigas opções de decimal visual e consenso variável são ocultadas quando
a escala nova é escolhida; nesse modo são sempre cinco fotos e quatro votos.

## Onde a leitura anterior era rejeitada

`decimal_detector.dart/reconcileVisualDecimal` dependia de confirmar o ponto na
imagem para reconciliar leituras como `5700`. O seletor de variantes e a validação
de casas esperadas podiam rejeitar esse resultado, assim como a confiança bruta
abaixo de 90%. O resumo ainda podia mostrar a última variante vazia, apesar de
outras lerem `5700`. Nada disso provava ausência dos dígitos na fotografia.

No modo configurado, `WeightRecognitionService` encaminha diretamente ao
`ConfiguredDigitsService`: não usa reconciliação visual de ponto nem validação
de quantidade de casas lida pelo OCR. O leitor legado permanece disponível para
estações ainda não configuradas. A geometria fica como fallback quando o motor
nativo falha, e só é aproveitada se o resultado geométrico for válido: por exemplo,
`SEGMENT_CLIPPED` nunca é resgatado por sua confiança isolada.

## Sequência, interpretação e auditoria

Whitelist nativa: `0123456789`. O texto retornado continua em `rawText`.
`rawDigits`/`normalizedText` preservam a sequência integral, inclusive zeros à
esquerda. Um único ponto/vírgula interno pode ser removido de texto numérico;
letras, unidades, sinais, espaços internos, pontuação inicial/final ou múltipla
são rejeitados. Não há correções de O→0 nem preenchimento de dígito faltante.

`interpretedValue = int.parse(rawDigits) / 10^decimalPlaces` é calculado como
candidato para checagem de faixa e diagnóstico. **Nenhum peso é liberado nessa
etapa**: `weight` e `finalWeight` ficam nulos até o consenso. A votação compara
as sequências brutas e a escala, nunca pesos já truncados. Depois da aceitação,
`finalWeight = interpretedValue.truncate()`. Não arredonda.

| Dígitos | Casas | Peso final |
|---|---:|---:|
| 13880 | 0 | 13880 |
| 5700 | 1 | 570 |
| 138805 / 138809 | 1 | 13880 |
| 1342 / 1399 | 2 | 13 |
| 1388099 | 2 | 13880 |
| 000 | 1 | 0 |

Diagnóstico mostra sequência, casas, valor interpretado, peso liberado, confiança
OCR, votos, confiança final e status. O registro de evidência inclui `ocrRawText`,
`ocrRawDigits`, `ocrDecimalPlaces`, `ocrInterpretedValue` e os diagnósticos completos.
Autorização, fotografia com timestamp, confirmação do operador e fallback manual
continuam nos mesmos fluxos. Nenhum peso é registrado automaticamente pelo motor.

## Consenso e confiança

Janela de **cinco fotos independentes**, mínimo **quatro sequências iguais**;
a foto atual precisa pertencer ao grupo concordante. Leituras inválidas e erros
de captura contam como fotos sem voto. Uma escala diferente não se soma ao grupo.
Até quatro fotos nenhuma leitura é liberada, mesmo com confiança OCR alta.

Regras internas iniciais, ajustáveis no código:

- Gramática numérica válida e valor interpretado na faixa configurada.
- Cada voto tem confiança OCR >= 0,40; média dos votos >= 0,45.
- `score = 0,35 × médiaOCR + 0,55 × (votos/5) + 0,10 × validaçãoNuméricaEFaixa`.
- Exige score >= 0,69, cinco fotos e quatro votos. Todos os requisitos são cumulativos.

Assim, `5700,5700,5700,5708,5700` com confiança 0,58 passa com 4/5, score 0,743.
`5680,5690,5700,5710,5720` não passa. Confiança 0,20 repetida também não passa;
nem 0,40 repetida, pois a média mínima é 0,45. A confiança original continua
separada em `ocrConfidence`; não é sobrescrita por um percentual artificial de 90%.
O score final é uma regra de decisão, **não probabilidade calibrada de acerto**.
Repetições podem concordar em erro sistemático: validar com fotos reais de vários
pesos continua necessário, assim como a confirmação do operador.

## Por que eram aproximadamente dez segundos

O serviço anterior podia percorrer geometria, Tesseract especializado com várias
variantes/PSM e fallback genérico, incluindo mais variantes. Cada
`TesseractWeightOcrService.recognizeVariant` iniciava `tesseract.exe` com arquivo
temporário e recarregava o modelo. O orçamento especializado não limitava toda a
cascata. A janela de frescor de dois segundos também torna quadros de dez segundos
inadequados para acumular consenso na leitura contínua.

O novo caminho usa a C API oficial da **DLL Tesseract já distribuída no pacote**,
via `dart:ffi`. Um isolate dedicado mantém um `TessBaseAPI` persistente com modelo
`eng`; solicitações são serializadas. O handle/modelo é compartilhado durante a
vida do aplicativo, inclusive entre sessões, sem reabrir o modelo a cada quadro.
Buffers e resultados nativos de cada imagem são liberados; `close()` encerra o
handle, usado também pelo benchmark. Não há Python, cloud ou processo por imagem.
Não foi acrescentado pacote Dart ou nova DLL de terceiros.

Uma preparação de imagem por quadro: localiza corpos dos dígitos grandes pela
geometria já existente, sem classificar dígitos ou exigir ponto; recorta quando
possível, normaliza/inverte grayscale, limita a 1200×180 e não aumenta a resolução.
Não percorre a antiga bateria de pipelines. Uma ROI bem calibrada continua
essencial; recorte automático não garante a completude do número.

O reconhecimento nativo possui deadline de 1500 ms via monitor Tesseract, além
de timeout externo do worker. A inicialização pode custar mais na primeira foto.
Se a DLL/modelo não estiver disponível ou der erro, a falha não vira leitura
aceita; geometria válida pode atuar como fallback, depois permanece o manual.
O pacote Windows precisa conter `ocr/libtesseract-5.dll`, suas dependências e
`ocr/tessdata/eng.traineddata`, já copiados pelo CMake existente.

Referência técnica: [C API oficial Tesseract](https://tesseract-ocr.github.io/tessapi/5.x/a00059.html).

## Medição com a amostra real

Amostra local do operador `ind570_5c581db1/roi.png`, `570.0`, casas=1:

- Antes, no benchmark anterior: genérico 4927 ms sem leitura aceita, mais 5698 ms
  do especializado na comparação independente. Na aplicação foi relatado 10043 ms
  para o quadro da cascata. Não são a mesma medição de um mesmo frame em execução simultânea.
- Depois, execução do novo benchmark: primeira imagem 1049 ms; seguintes 237,
  218, 137 e 124 ms, incluindo preparação, sem intervalo da câmera.
- Cinco retornos `5700`, confiança OCR 92%, valor interpretado `570.0`, peso final
  `570 kg`, score final 97,2%. A primeira execução anterior mediu 675 ms de partida
  e 124–237 ms nas imagens seguintes; latência depende do estado da máquina.

O benchmark repete **a mesma imagem estática** para medir reutilização do motor e
reconstrução. Não comprova consenso de cinco fotos reais ou precisão em campo.
O teste do leitor contínuo usa cinco capturas independentes simuladas. Homologar
com câmera ao vivo, vários pesos/condições e ambos os indicadores ainda é necessário.

```powershell
dart run tool/benchmark_configured_digits.dart tools/weight_vision/dataset/ind570_5c581db1/roi.png 1
```

JSON fica no stdout e em `tools/weight_vision/reports/digits_<tempo>.json`, ignorado
pelo Git. As amostras reais continuam ignoradas e não foram incluídas em commit.

## Arquivos desta rodada

- `capture_models.dart`: configuração persistida, critérios do resultado e auditoria.
- `configured_digits.dart`: gramática, interpretação candidata e consenso.
- `persistent_digits_ocr.dart`: worker e Tesseract nativo persistente.
- `configured_digits_service.dart`, `weight_recognition_service.dart`: composição da engine.
- `weight_recognition_validation.dart`, `live_weight_reader.dart`, `capture_controller.dart`: integração temporal e validação.
- `manual_capture_services.dart`, `manual_webcam_settings.dart`: validação e campo de configuração.
- `capture_dialog.dart`, `tesseract_runtime.dart`: diagnóstico e mensagens.
- `tool/benchmark_configured_digits.dart`, `test/configured_digits_test.dart`: benchmark e testes obrigatórios.
- Este documento e referência no README de visão.

Outras alterações já existentes foram preservadas. PaddleOCR não foi adicionado
nem instalado nesta rodada. Nenhum commit ou push foi realizado.

## Validação executada

- `dart format`: arquivos Dart desta rodada formatados.
- `flutter analyze --no-pub`: nenhum problema encontrado.
- Suíte completa `flutter test --no-pub --concurrency=1`: **334 testes aprovados**.
- Após acrescentar dois testes de integração de captura, executado novamente o
  arquivo `configured_digits_test.dart`: **18 testes aprovados**, incluindo os dois
  adicionais. A análise foi repetida sem problemas.
- A primeira execução concorrente revelou dois problemas de layout do campo novo,
  corrigidos colocando-o ao lado do perfil; houve também timeout em um teste legado
  de Tesseract real. A execução completa sequencial passou sem alterar esse timeout.
- Benchmark nativo com a amostra real: cinco retornos `5700`, peso `570` após consenso.

Relatório local mais recente durante esta rodada:
`tools/weight_vision/reports/digits_1794087312032732.json`: 740 ms na primeira leitura,
294, 288, 159 e 151 ms nas seguintes, OCR 92%, score final 97,2%.
Diferenças entre execuções ilustram variação de carga da máquina, não uma garantia
de desempenho. A inferência foi local, sem captura física automatizada da webcam.
