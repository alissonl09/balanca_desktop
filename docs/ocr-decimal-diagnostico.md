# OCR da Pesagem Manual — decimal e distância

> Atualização posterior: [modos foto/OCR e leitura contínua](ocr-modos-leitura-continua.md).
> O texto abaixo registra a cascata de diagnóstico anterior; a operação agora
> usa dois passes rápidos e OCR opcional, desligado por padrão.

Rodada de 05/11/2026, somente em `balanca_desktop`. Sem commit/push.
Evidências numéricas: [resumo](ocr-decimal-evaluation/summary.json),
[passes anteriores](ocr-decimal-evaluation/before.csv) e
[passes comparados](ocr-decimal-evaluation/after.csv).

## 1. Diagnóstico antes das alterações

O fluxo já utilizava `CameraController.takePicture()`, correção EXIF/espelho,
crop proporcional do frame original e PNG limpo para OCR. Não havia screenshot
do preview. Data/hora eram desenhadas somente na cópia de evidência.

| Item | Comportamento anterior |
| --- | --- |
| Câmera | `ResolutionPreset.high`; preview Windows limitado a 720p |
| Foto efetiva conhecida | 1280×720, conforme proveniência da fixture real |
| ROI histórica | x=.1, y=.25, largura=.8, altura=.5 → 1024×360 |
| Modelos | `7seg` prioritário; `eng` anterior como fallback; `ssd`/`ssd_int` somente comparador |
| Tesseract | OEM 1, PSM 7 e alternativa 13; comparador também usa 8 |
| Whitelist especializada | `0123456789.-` |
| Upscale | Cúbico, alvo 2x, limitado a 1600×600; fator podia ficar abaixo de 1 em ROI grande |
| Threshold | Grayscale/contraste, Otsu, adaptativo média 31×31 com deslocamento 8 |
| Morfologia | Fechamento de raio 1 em alternativa; erosão/dilatação/sharpen só na grade experimental |
| Decimal | Dependia do texto do Tesseract; nenhuma detecção geométrica independente |
| Confiança | Mínimo dos passes especializados aceitos; corte de 90%; final zero antes de consenso |
| Consenso | Mesmo valor numérico em N fotos consecutivas; falha imediata ao primeiro desacordo |

A inspeção do código instalado de `camera_windows 0.3.0+1` confirmou um detalhe:
o preset limita o preview; a fotografia já busca o melhor modo nativo suportado.
Portanto, alterar o preset não comprova aumento da resolução fotográfica. A
resolução real é agora medida ao decodificar cada foto e exibida no diagnóstico.
Não foi feita nova captura física nesta rodada; 1280×720 é a medição histórica,
não uma promessa sobre outra câmera ou estação.

## 2. Por que 570.0 chegava como 5700

A reprodução usa a fixture óptica real `ind570_webcam_570.png`. Dentro dela,
o recorte dos dígitos foi x=307, y=137, largura=317, altura=104. Isso é um
recorte de avaliação, não uma mudança automática na configuração da estação.

Na versão anterior do pré-processador, `eng`/PSM 7 devolveu `5700` com
**94,69%** no grayscale 2x e **95,47%** no Otsu 2x. O ponto continua visível
na imagem Otsu entregue ao motor: neste caso reproduzido, a omissão ocorre na
interpretação do Tesseract, não no parser e nem na whitelist. O parser anterior
já preservava um ponto quando ele constava no texto recebido.

Não existe evidência para atribuir toda perda de ponto a uma única operação:
resize para baixo, limiarização ou morfologia também podem eliminar pontos em
outras imagens. O fallback genérico ainda tinha recorte/resize próprios, e em
uma ROI ampla pode reduzir os dígitos junto com o painel. A ROI histórica inclui
capacidade, textos, ícones e teclado, dificultando segmentação e enquadramento.
O log exato da tentativa de aproximadamente 50% citada no pedido não foi
fornecido; não se afirma que essa tentativa usou exatamente o mesmo passe.

## 3. Detecção visual e reconstrução

`decimal_detector.dart` analisa a ROI limpa antes de upscale/morfologia:

* estima polaridade pelo perímetro, evitando inverter um recorte cheio de segmentos;
* localiza uma linha dominante somente quando o localizador existente a considera inequívoca;
* usa projeção no corpo superior para separar dígitos sem unir rótulos da base;
* percorre componentes conexos incluindo componentes de um pixel;
* procura componente compacto, pequeno em relação à altura dos dígitos, junto à base e entre duas caixas reais;
* reconstrói somente se a quantidade de caixas corresponder à sequência reconhecida e houver um único ponto coerente;
* rejeita pontos múltiplos, conflito de posição ou ponto sem resolução suficiente.

Na ROI real de 317×104: altura média dos dígitos **97,75 px**; caixas
`(17,5,62,99)`, `(82,6,63,98)`, `(147,7,64,97)`, `(233,7,65,97)`;
ponto **(213,82,18,18)**. O separador fica após o terceiro dígito.

`rawText` continua contendo a saída original. `normalizedText` pode ser `570.0`
mesmo quando `rawText` foi `5700`, porque existe suporte visual independente.
Sem esse suporte, `5700` não é dividido por dez nem recebe ponto por configuração.
Quando a geometria não segmenta uma fonte/layout, o OCR anterior continua
disponível; uma evidência geométrica contraditória impede aceitação. O detector
nunca adivinha posições usando espaçamento uniforme.

`WeightRecognitionResult` é um alias compatível de `WeightOcrResult`. O contrato
agora mantém texto normalizado, sequência de dígitos, caixas, decimal/posição,
confianças OCR/quadro/final, modelo, pipeline, consenso e motivo de falha.
Esses dados, as dimensões reais e cada tentativa também seguem para a auditoria.

## 4. Captura, ROI e calibração

O preview solicita `ResolutionPreset.max`, como a seleção do modo de foto do
plugin, para manter a preferência de resolução/proporção consistente. O PNG
original decodificado continua sendo a fonte de coordenadas do crop. O teste de
1920×1080 com ROI de 50%×20% produz **960×216**, independentemente do tamanho
visual do preview. O processador não redimensiona a foto para fazer esse crop.

Em **Configurações → Webcam → Testar câmera**:

1. Arrastar o retângulo move a ROI; arrastar o canto amarelo altera seu tamanho.
2. O ajuste opcional de inclinação permite corrigir de −6° a +6°, em passos de 0,5°.
3. **Testar leitura** mostra frame, ROI, grayscale/contraste, Otsu e entrada selecionada do Tesseract lado a lado, além das medidas e resultado.
4. **Salvar ROI** persiste posição/tamanho normalizados e inclinação localmente.

A configuração preserva regiões separadas por ID de câmera nesta estação,
inclusive ao trocar de dispositivo e reabrir a configuração. Os campos numéricos
anteriores também continuam disponíveis. Enquadrar somente os dígitos e os
possíveis sinal/ponto; não cortar a base ou esconder um sinal negativo.

A correção de inclinação gira somente uma cópia da ROI, com interpolação cúbica
e canvas expandido. A foto original e a evidência permanecem iguais. Isso é
deskew de rotação, não homografia para qualquer trapezoide; perspectiva forte
ainda exige melhorar o posicionamento ou futura calibração de quatro cantos.

## 5. Escalas e thresholds comparados

O pré-processador mantém grayscale, Otsu, adaptativo e fechamento alternativo,
adiciona global 128 e polaridade inversa à comparação normal, e não reduz mais
a ROI para cumprir o antigo teto. Não há sharpen/erosão obrigatórios.
O fator efetivo é registrado: limites de memória reduzem a ampliação pretendida,
mas não a resolução nativa. Borda branca de 10 px continua fora do conteúdo.

Foram comparados **288 passes anteriores** e **324 passes novos**, com os quatro
modelos, PSM 7/8/13 e alvos 2x/3x/4x. A ROI real produz entradas:

| Alvo | Entrada com padding | Passes eng corretos após detecção visual |
| --- | --- | ---: |
| 2x | 654×228 | 20 |
| 3x | 971×332 | 17 |
| 4x | 1288×436 | 15 |

Não são contagens de fotos independentes nem uma taxa de acurácia de produção.
2x permanece a primeira opção. Para dígitos nativos abaixo de 48 px, a cascata
também tenta 3x/4x dentro do orçamento. Dígitos já grandes não percorrem escalas
redundantes na operação. O fallback `eng` conserva seus passes anteriores e
também pode analisar variantes da ROI preservada com whitelist numérica.

No caso principal, a seleção foi **eng / PSM 7 / grayscale com contraste 2x**,
com concordância de outro pré-processamento. O Otsu foi importante para a
comparação e para localizar componentes, mas não foi declarado vencedor global
para toda câmera/iluminação.

## 6. Comparação de modelos e referência geométrica

Na grade deste único recorte, `7seg` não atingiu 90%. `ssd` e `ssd_int` voltaram
a produzir erros de dígitos com confiança alta. A detecção do ponto não corrige
uma classificação de `5` como `6`, por exemplo. Permanecem fora da seleção
automática padrão, disponíveis no comparador offline.

| Modelo | Passes | Aceitos brutos / errados | Aceitos híbridos / errados |
| --- | ---: | --- | --- |
| 7seg | 81 | 0 / 0 | 0 / 0 |
| ssd | 81 | 25 / 25 | 16 / 16 |
| ssd_int | 81 | 13 / 13 | 13 / 13 |
| eng | 81 | 52 / 48 | 52 / 0 |

São resultados individuais da grade, sujeitos às regras adicionais da cascata
e ao consenso temporal. Não são autorização de pesagem nem comparação ampla de
modelos. Os CSVs preservam saídas erradas e baixas confianças.

Referências primárias consultadas: [Tesseract: qualidade de entrada](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html),
[modelos tessdata_ssd](https://github.com/Shreeshrii/tessdata_ssd) e
[ssocr, projeto e código](https://github.com/auerswal/ssocr).
A documentação do Tesseract motivou comparar limiarização, escala, polaridade e
padding. O ssocr foi avaliado como referência de segmentação, decimal e correção
geométrica. Nenhum código/biblioteca ssocr foi incorporado, nem nova dependência
de runtime. Esta camada mede caixas/componentes; não substitui a classificação
dos sete segmentos por uma nova engine não calibrada.

## 7. Consenso e confiança final

N continua configurável de 2 a 5. São analisadas até N+2 fotos independentes,
uma de cada vez, com intervalo mínimo de 250 ms após cada análise. Não há OCR
a 60 FPS nem tarefas concorrentes acumuladas; o preview segue independente.

Para aceitar, a leitura atual precisa ser confiável, ter pelo menos N votos,
concordância de pelo menos 80% na janela e duas leituras finais concordantes.
`570.0`, `5700` e até `570` mantêm chaves distintas. Quadros inválidos não votam;
um quadro ruim não apaga os anteriores. A foto do último quadro concordante é
a foto associada à sugestão aceita. Cada tentativa continua auditada.

A confiança do quadro é o mínimo entre OCR, qualidade de ROI, estrutura,
suporte ao decimal e estabilidade temporal. Qualidade considera resolução
nativa dos dígitos e contraste. Nitidez por gradiente e saturação são medidas
de diagnóstico, não uma certificação de foco. O quadro de consenso usa o mínimo
das confianças dos votos e um teto temporal `1 − .02 × quadros não concordantes`.
`finalConfidence` fica zero enquanto faltar validação/consenso. O corte operacional
de 90% foi mantido; o consenso nunca promove um OCR de 50%.

O teste `570.0, 570.0, 5700, 570.0, 570.0` produz quatro votos em cinco,
`570.0` e confiança final de 98% para votos OCR de 99%. Isso valida o algoritmo,
não afirma que foram obtidas cinco fotos físicas do indicador nesta rodada.

## 8. Resultado do caso real e limites

| Controle | ROI | Resultado da cascata | Confiança do quadro | Tempo medido |
| --- | --- | --- | ---: | ---: |
| Recorte real nativo | 317×104 | `570.0`, decimal visual após dígito 3 | 94,69% | 5,14 s |
| Redução sintética da foto a 50% | 159×52 | `570.0` | 95,69% | 3,85 s |
| Redução sintética a 25% | 79×26 | Rejeitada: modelos divergentes | Não aceita | 9,61 s |

Um quadro sozinho continua com confiança final temporal zero. Tempos incluem
cascata/fallback e dependem da máquina. O objetivo de 2–5 análises/s não foi
atingido por essa cascata CLI; o limitador impede sobrecarga e preserva o preview.
Uma engine residente/cache de estratégias calibradas pode reduzir a latência em
outra etapa. Não foi reduzida validação para apresentar sucesso mais rápido.

O controle menor rejeitou uma saída `5700` mesmo com confiança OCR bruta alta.
Upscale não recupera detalhe óptico que a câmera não capturou. Montagem real,
foco, reflexos, distâncias, exposição e transições de segmentos precisam ser
validados no indicador físico. A UI mostra medidas/nitidez e permite repetir a
calibração; não há controle invasivo de foco/exposição nem dependência de autofocus.

O fallback manual, evidência fotográfica, autorização e confirmação humana
permanecem. Uma sugestão OCR nunca registra a pesagem sozinha. Serial/TCP,
`balanca-web` e Libra-API não foram alterados.

## 9. Reprodução e validação

Gerar os dez controles geométricos sintéticos (não fotografias):

```powershell
dart run tool/generate_decimal_fixtures.dart
```

Comparar a mesma ROI real com o runner Flutter (os serviços usam `dart:ui`):

```powershell
flutter test tool/run_ocr_comparison_test.dart --dart-define=OCR_IMAGE=test/fixtures/weight_ocr/ind570_webcam_570.png --dart-define=OCR_REGION=0.30,0.38,0.31,0.29 --dart-define=OCR_OUT=build/ocr-comparison --dart-define=OCR_FULL=true
```

Os testes incluem `0.0`, `10.0`, `100.0`, `570.0`, `12190`, `5700`, ponto de dois
pixels, baixa iluminação, polaridades, escalas, ROI menor/ampliada, pontos
ambíguos, ruído à meia altura, deskew, persistência por câmera, arraste, falhas,
consenso decimal e execução do Tesseract real. O controle real exige a string
exata `570.0`; `5700` não passa como equivalente.

Validação final:

* `dart format`: 25 arquivos verificados; nenhum ajuste restante.
* `flutter analyze`: **No issues found**.
* `flutter test`: **262 aprovados**, zero falhas e zero ignorados, com Tesseract real disponível.
* `git diff --check`: sem erros de whitespace.
* Nenhum commit/push, alteração de outro repositório ou nova dependência de OCR.
