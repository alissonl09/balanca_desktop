# Visão local de peso — IND560 e IND570

Fluxo operacional atual: [fotografia preservada antes da análise](../../docs/ocr-foto-estatica.md),
com múltiplos pipelines sobre uma mesma foto e confirmação humana, sem OCR no preview.

Atualização: o caminho com escala decimal configurada e Tesseract persistente está
documentado em [OCR de dígitos](../../docs/ocr-digitos-decimal-configurado.md).
Essa é a etapa operacional mais recente; os modelos/Paddle descritos abaixo
continuam apenas infraestrutura/benchmark futuro.

Esta etapa prepara coleta, anotação, benchmark e contrato de inferência. Não há
modelo customizado treinado, runtime ONNX instalado nem troca da engine operacional.
Treinamento é ferramenta de desenvolvimento, fora do Flutter. Nenhuma imagem é
enviada para serviço externo. Não há dependência Python nova no aplicativo.

## Motivação e limites

Tesseract genérico/especializado e geometria não atingiram a confiabilidade exigida
nas imagens reais/similares relatadas. Mais parâmetros não substituem exemplos
representativos. O próximo caminho é detectar cada um dos dez dígitos e o ponto,
com caixas, confiança e validação. O benchmark mede essa hipótese; não promete
qualidade antes de coletar dados reais.

## Estrutura e captura

```
tools/weight_vision/
  dataset/         # local, ignorado pelo Git
  annotations/     # local, ignorado pelo Git
  models/          # pesos locais, ignorado pelo Git
  reports/         # relatórios locais, ignorado pelo Git
  scripts/         # ferramentas de desenvolvimento
  classes.json
  manifest.example.json
```

Em Configurações → Webcam da Pesagem Manual, selecione perfil IND560 ou IND570.
Abra **Testar câmera**, calibre a ROI e clique **Capturar amostra para dataset**.
O botão aparece em debug ou com diagnóstico habilitado. Funciona sem OCR habilitado;
o perfil precisa ter sido selecionado (habilite OCR temporariamente nas configurações
se necessário para selecionar o perfil). Cada clique captura um frame novo, sem
pesagem e sem acionar a API ou os registros de evidência operacional.

O caminho é exibido no diálogo: diretório de suporte da aplicação Windows,
`weight_vision/dataset/ind560_*` ou `ind570_*`. Copie as pastas para `dataset/` para
trabalhar no repositório. Não há exclusão automática; planeje espaço e retenção.

Cada amostra contém:

- `camera_original.bin`: bytes originais do driver (conteúdo JPEG/PNG, sem extensão presumida).
- `original.png`: frame normalizado por EXIF e correção de espelhamento da estação, sem carimbo.
- `roi_original.png`: recorte antes da perspectiva/inclinação.
- `roi.png`: recorte corrigido, entrada de anotação e do modelo.
- `metadata.json`: UTC, modelo, resolução do frame/ROI, calibração, ground truth vazio.

Nenhum timestamp é desenhado nessas imagens de treinamento. A foto operacional
continua com seu timestamp e fluxo anteriores. A coleta não deve usar prints do preview.

## Ground truth e coleta real

Preencha manualmente em `metadata.json`: `expected` como string inteira em kg
(`"570"`) e `expectedSequence` como sequência visível completa (`"570.0"`).
Não use a previsão como verdade. Registre também `sessionId`, unidade/câmera,
condições e `split` (train/validation/test). Remova informações sensíveis antes de
compartilhar qualquer imagem. O benchmark usa um manifesto JSON separado, seguindo
`manifest.example.json`; caminhos são relativos à raiz do repositório.

Comece com algumas centenas de imagens reais da instalação e expanda conforme
falhas. Não existe quantidade garantida. Cubra todos os dígitos e o decimal em
ambos os indicadores: zero, números curtos/longos, diversos pesos e precisões,
luz clara/escura, reflexos, diferentes ângulos moderados, foco e qualidade imperfeitos.
Registre o modelo real, sem inferi-lo automaticamente pela cor. Internet e síntese
podem complementar; não substituem fotos reais da unidade.

Separe por sessão/dia/câmera antes de augmentations. Frames consecutivos de uma
mesma captura nunca devem vazar entre treino e teste. Reserve teste real imutável
com ambos os indicadores, condições difíceis e casos negativos/visor cortado.

## Anotação COCO

Use CVAT/Label Studio local ou ferramenta equivalente com exportação COCO detection.
Instalação e licença da ferramenta são avaliação separada. Não há vínculo com Ultralytics.
Anote cada dígito visível, inclusive depois do ponto; ponto também tem caixa.
As coordenadas são em pixels de `roi.png`, não do frame completo.
Mapeamento canônico é **0..9 = dígitos; 10 = decimal_point**, conforme `classes.json`.
Alguns exportadores usam IDs a partir de 1: remapeie explicitamente.

Exemplo de estrutura COCO (inclua todas as 11 categorias no arquivo final):

```json
{
  "images": [{"id": 1, "file_name": "ind570_001/roi.png", "width": 300, "height": 100}],
  "annotations": [{"id": 1, "image_id": 1, "category_id": 1,
    "bbox": [10, 10, 30, 70], "area": 2100, "iscrowd": 0}],
  "categories": [{"id": 0, "name": "0"}, {"id": 1, "name": "1"}]
}
```

Valide IDs, caixas e cobertura: `python tools/weight_vision/scripts/validate_coco.py tools/weight_vision/annotations/train.json`.
Faça também revisão visual e dupla conferência do peso; o validador estrutural não
confirma se as caixas correspondem aos dígitos. Marque visores incompletos como
rejeição em separado; não invente dígitos ocultos.

## Benchmark controlado

Na raiz do projeto, SDK Dart/Flutter no PATH:

```powershell
dart run tool/benchmark_weight_vision.dart tools/weight_vision/dataset/ind570_001/roi.png 570 570.0
dart run tool/benchmark_weight_vision.dart --manifest tools/weight_vision/manifest.example.json
```

Entrada simples é **ROI já recortada**. Para foto completa, informe `region` com
o JSON da calibração no item do manifesto; o processador aplica ROI/perspectiva.
`profile` pode ser `ind560`, `ind570` ou `auto`. Um argumento de sequência decimal
deve representar o que realmente está visível; `13.880` não equivale a `13880`.

Engines independentes: geometria atual, Tesseract 7seg sem fallback genérico,
Tesseract genérico, PaddleOCR opcional e CustomModelEngine. O custom retorna
`CUSTOM_MODEL_UNAVAILABLE` até um adaptador real ser implementado e injetado no
mapa de engines. Não simula uma previsão e não lê detecções pré-gravadas como inferência.
Tesseract usa o runtime/modelos locais já existentes do projeto.

JSON no stdout e em `reports/benchmark_<tempo>.json`: ground truth, sequência,
peso, falha, confiança, distância de edição (inserções/exclusões/substituições),
acerto do peso completo, acerto de imagem/sequência quando anotada, tempo por
imagem e taxa de sucesso por engine. Resultado `1388` para `13880` é falha.
Engines indisponíveis contam como falhas; não compare taxas sem verificar o ambiente.
`imageCorrect` é null sem expectedSequence, nunca uma métrica inventada.
Tempos externos incluem inicialização; Paddle separa carga e inferência em `details`.
Esta comparação estática não comprova estabilidade temporal nem autoriza registro.

Execução inicial na fixture existente `test/fixtures/weight_ocr/ind570_webcam_570.png`,
ground truth `570.0`, ROI adicional normalizada `{left: .305, top: .38, width: .292,
height: .278}` (mesma calibração do teste geométrico):

| Engine | Sequência | Peso | Tempo total observado |
| --- | --- | --- | --- |
| Geometria | 570.0 | 570 | 774 ms |
| Tesseract 7seg | 570.0 | 570 | 6688 ms |
| Tesseract genérico | 570.0 | 570 | 3501 ms |
| PaddleOCR | indisponível | — | pacote não instalado |
| Custom | indisponível | — | modelo não instalado |

Uma única imagem não estima confiabilidade nem latência em campo. Executada também
com a ROI ampla original, geometria e ambos os Tesseract falharam. Nenhum parâmetro
dos algoritmos foi ajustado nesta rodada. Os JSON completos ficam locais em `reports/`.

Reprodução adicional com amostra real coletada pelo operador em 07/11/2026,
17:58:45 local (`ind570_5c581db1/roi.png`, 1024×360, peso visível `570.0`):
geometria falhou com `SEGMENT_POOR_IMAGE` (673 ms), Tesseract 7seg não produziu
leitura aceita (5698 ms) e genérico retornou vazio/`OCR_FORMATO_INVALIDO`
(4927 ms). Paddle não instalado. A amostra foi copiada do armazenamento local
para o dataset ignorado; o original da aplicação não foi alterado. Isso reproduz
a falha em imagem real, apesar dos acertos na fixture anterior.

O diagnóstico da interface passou a mostrar texto/confiança/falha por tentativa
e motivo da falha principal. Corrigida também a seleção da imagem final: o prefixo
`Tesseract fallback:` antes impedia encontrar a estratégia correspondente e a UI
exibia a primeira imagem de outra tentativa. Não houve alteração de limiares nem
de reconhecimento para forçar aceitação de `570`.

### PaddleOCR experimental local

Em 07/11/2026, Python 3.12 estava disponível, mas `pip show paddleocr paddlepaddle`
não encontrou os pacotes. O script executado contra a fixture IND570 retornou
`PADDLE_NOT_INSTALLED`. Portanto **não foi medida precisão do PaddleOCR**.

Prepare um venv de desenvolvimento (não na estação de produção). Instale versões
compatíveis de `paddlepaddle` CPU e `paddleocr` 3.x conforme a documentação oficial,
fixe versões e guarde `pip freeze` com o relatório. Baixe previamente somente os
artefatos licenciados PP-OCRv5_mobile_det e PP-OCRv5_mobile_rec. Downloads de pacotes
e pesos exigem conectividade no preparo; imagens não são enviadas. Para inferência,
use ambos os diretórios locais, CPU, sem orientação/unwarping extras:

```powershell
$env:WEIGHT_VISION_PYTHON = 'tools/weight_vision/.venv/Scripts/python.exe'
$env:WEIGHT_PADDLE_DET_DIR = 'D:/modelos/PP-OCRv5_mobile_det'
$env:WEIGHT_PADDLE_REC_DIR = 'D:/modelos/PP-OCRv5_mobile_rec'
python tools/weight_vision/scripts/paddle_baseline.py imagem_roi.png
```

O script recusa diretórios ausentes, desativa descoberta de fonte, usa modelos
locais explícitos e não contém cliente cloud. Execute em ambiente sem saída de
rede para comprovar o comportamento da versão instalada. Múltiplas linhas falham
por ambiguidade; não escolhemos arbitrariamente o maior número. É baseline OCR
de string, separado da proposta de detecção por dígito. Melhorias gerais de OCR
não constituem evidência de adequação aos Toledo.

## Treinamento e exportação futuros

Candidato inicial: YOLOX nano/tiny com cabeça de 11 classes e dataset COCO próprio;
comparar RT-DETR/PaddleDetection se a detecção de pontos pequenos for insuficiente.
São famílias gerais de detecção a treinar; não são modelos Toledo prontos.
Teste resolução que preserve o ponto, cobertura por classe e recall de dígitos.
Use augmentations moderadas de brilho, contraste, exposição, blur, ruído, escala e
perspectiva leve, sempre transformando também as caixas. Nunca espelhe ou rotacione
de modo a alterar o significado dos números. Não treine só com imagem limpa.

Antes de treinar: revisar dataset/splits/licenças, fixar seed/configuração/versões,
escolher hardware de treino, revisar erros do baseline. Não incluímos um comando de
treino fictício antes de escolher arquitetura e dados. Exportar ONNX após treino,
comprovar paridade framework/ONNX no teste reservado. Guardar hash, proveniência,
licença, classes, layout NCHW/NHWC, resolução, RGB/BGR, normalização, letterboxing,
opset, saídas, NMS e limiares num manifesto de modelo versionado. Quantização
somente após comparar impacto no ponto e no peso completo.

## Inferência e diagnóstico no Flutter

`weight_vision_engine.dart` define `WeightRecognitionEngine`, `LocalDigitModel`,
`DigitDetection`, `DigitModelOutput`, `CustomModelEngine` e `WeightEngineCascade`.
O adaptador futuro recebe ROI limpa já corrigida e devolve caixas normalizadas,
classes 0..10 e confiança. Deve desfazer letterbox, fazer NMS e sinalizar
`complete=false` quando recorte/detecções forem incompletos ou ambíguos.
Completude não pode ser deduzida apenas de um número válido; dígito faltante exige
avaliação de cobertura/recorte e teste real. Nenhuma heurística completa números.

Reconstrução ordena X, valida caixas/confiança/sobreposição/sequência, preserva
sequência decimal para consenso e usa só a parte anterior ao ponto como peso:
`570.0 → 570`, `13.42 → 13`, `13.99 → 13`, `12190 → 12190`.
O contrato de resultado já expõe caixas, classe, confiança e sequência para
diagnóstico; não há overlay custom novo na tela sem modelo para demonstrá-lo.
O diagnóstico geométrico/ROI existente continua disponível.

Após qualificação, injetar cascata custom → Tesseract/legado no serviço e conservar
LiveWeightReader/WeightTemporalConsensus, validação e confirmação do operador.
Consenso atual é configurável, exige pelo menos 80% de concordância e duas últimas
leituras concordantes. Os testes incluem quatro votos em cinco frames, mantendo
decimais distintos como votos diferentes. Nenhuma engine grava pesagem sozinha.
Ausência/erro/baixa confiança do modelo permite fallback; falha geral mantém manual.

Recomendação arquitetural: **ONNX Runtime CPU Windows via C API/FFI ou pequeno
adaptador nativo**. Motivos: suporte Windows documentado, runtime independente de
Python e exportação de múltiplas famílias. Só implementar DLL/gerência de memória,
threads e empacotamento após confirmar modelo e seus operadores. Executar fora da
UI e limitar concorrência. TFLite continua alternativa: `tflite_flutter` documenta
Windows, mas exige bibliotecas nativas e validar operadores/exportação no alvo;
não é motivo suficiente para assumir integração mais simples.

## Fontes e licenças consultadas

Consulta em 07/11/2026; registrar commit e licença exatos antes de incorporar artefatos.
Esta é triagem técnica, não conclusão jurídica sobre uso/distribuição corporativa.

- [PaddleOCR LICENSE](https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE): Apache-2.0 no código; revisar licença/proveniência de cada peso e dependência separadamente.
- [PaddleOCR pipeline local](https://www.paddleocr.ai/main/en/version3.x/pipeline_usage/OCR.html): parâmetros de diretórios locais; baseline PP-OCRv5.
- [YOLOX](https://github.com/Megvii-BaseDetection/YOLOX): Apache-2.0 e exportação ONNX; candidato inicial de treinamento.
- [PaddleDetection](https://github.com/PaddlePaddle/PaddleDetection): Apache-2.0; RT-DETR candidato alternativo, validar exportação/operadores e pesos escolhidos.
- [ONNX Runtime Windows](https://onnxruntime.ai/docs/get-started/with-windows.html) e [licença MIT](https://github.com/microsoft/onnxruntime/blob/main/LICENSE): opção preferida para runtime local; incluir avisos de terceiros.
- [tflite_flutter](https://pub.dev/packages/tflite_flutter): Windows suportado com preparo de runtime nativo; alternativa a validar em máquina alvo.
- [Ultralytics LICENSE](https://github.com/ultralytics/ultralytics/blob/main/LICENSE): AGPL-3.0; não incorporado. Avaliar obrigações ou termos comerciais antes de qualquer adoção.
- [renjithsasidharan/seven-segment-ocr](https://github.com/renjithsasidharan/seven-segment-ocr): referência de pipeline dataset/treino/TFLite. A página consultada não apresenta licença explícita identificável. Código/pesos não foram copiados nem executados; exigir licença/autorização antes de reutilizar. Não há comprovação de desempenho IND560/IND570 ou decimal.

Nenhum modelo público específico foi aprovado para produção nesta rodada. Licença
permissiva do framework não licencia automaticamente dataset, pesos ou imagens.
Manter atribuições e avisos exigidos dos artefatos que forem efetivamente escolhidos.

## Critério de promoção

Definir com operação metas de peso completo correto, taxa de rejeição segura,
falsos aceites e latência p50/p95 no Windows alvo. Avaliar por indicador, sessão,
iluminação e cada classe, comparar com baseline sem regressões, testar consenso e
falhas de runtime. Só então trocar engine principal com mecanismo de reversão.
Primeiros passos concretos: coletar → preencher ground truth → anotar → revisar
splits → executar baselines → escolher arquitetura/versões → treinar → exportar →
avaliar offline → integrar runtime → homologar na unidade.

## Arquivos desta etapa e validação

- `.gitignore`: exclui dados, anotações, pesos, relatórios e venv locais.
- `lib/features/pesagem/manual_capture/capture_dialog.dart`: ação de coleta no diagnóstico.
- `lib/features/pesagem/manual_capture/weight_dataset_store.dart`: persistência limpa e metadados.
- `lib/features/pesagem/manual_capture/weight_vision_engine.dart`: contrato de modelo, reconstrução e cascata opt-in.
- `tool/benchmark_weight_vision.dart`: comparação estática e métricas.
- `test/weight_vision_engine_test.dart`: testes novos.
- `tools/weight_vision/README.md`, `classes.json`, `manifest.example.json`,
  `scripts/paddle_baseline.py`, `scripts/validate_coco.py`, `dataset/.gitkeep` e
  `annotations/.gitkeep`: processo de desenvolvimento.

Alterações locais anteriores em outros arquivos foram preservadas. Não houve commit,
push, alterações nos projetos vizinhos ou novas dependências no pubspec.
`dart format` executado nos cinco arquivos Dart desta etapa. Suíte completa:
316 testes aprovados. `flutter analyze --no-pub`: nenhum problema encontrado.
Análise/testes foram executados pelo snapshot oficial do mesmo SDK Flutter,
pois o inicializador `.bat` estava bloqueado pelo daemon do editor; não foi
necessário interromper o daemon. Cobertura inclui reconstrução/ordenação, decimais obrigatórios,
rejeição de caixas/confiança inválidas, faixa, consenso, fallback, modelo ausente,
erro de runtime, leitura parcial no benchmark e armazenamento sem timestamp.
Não foi realizada captura física com webcam nem inferência Paddle/ONNX real.
