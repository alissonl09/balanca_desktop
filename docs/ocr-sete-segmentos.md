# OCR local para displays digitais — 05/11/2026

## Inspeção anterior à mudança

O código já havia evoluído além da primeira implementação da webcam:

* `TesseractWeightOcrService` usava somente `eng`, PSM 7, TSV, confiança >= 90%.
* `prepareOcrVariants` recortava geometricamente a linha dominante dentro da ROI,
  normalizava contraste, invertia e aplicava threshold fixo 128 (três variantes).
* O primeiro passe não tinha whitelist; os demais podiam usar
  `0123456789.,-kgKG`. Os dicionários já eram desabilitados.
* Exigia duas variantes coerentes **e sucesso da primeira variante**.
* A configuração local já tinha ROI numérica, espelhamento e limites de peso.
* O controlador fazia três fotografias consecutivas iguais, salvando evidência
  com timestamp separadamente do PNG limpo enviado ao OCR.

As causas prováveis da falha eram fontes/gaps diferentes do treinamento do
`eng`, enquadramento, pré-processamento inadequado e seleção muito restrita da
primeira variante. Nesta máquina também foi encontrada uma diferença de modelo:
o `eng` instalado tinha 4.113.088 bytes; o projeto espera `tessdata_best` 4.1.0,
SHA-256 `8280aed0782fe27257a68ea10fe7ef324ca0f8d85bd2fd145d1c2b560bcb66ba`.
O replay do código anterior, sem alteração, confirmou baixa confiança em `zero`,
`ind570_decimal` e `panel_570` com o modelo instalado. Preparar o runtime com o
`eng` já fixado pelo projeto fez esses testes voltarem a passar. Não houve
redução do limite de confiança para contornar essas falhas.

## Modelos incorporados e licença

Origem: [Shreeshrii/tessdata_ssd](https://github.com/Shreeshrii/tessdata_ssd),
commit **e493a10a4bf81632506cf24ba99d83854afff9f6**. O próprio upstream descreve
o projeto como prova de conceito; a melhor leitura do 7seg numa pequena amostra
real não constitui garantia para os indicadores desta operação.

Os binários foram incorporados **sem modificações** em `assets/ocr/tessdata/`:

| Modelo | Bytes | SHA-256 |
| --- | ---: | --- |
| `7seg.traineddata` | 11435044 | `7e170293e5ac660295d7d3f53346453447bd9c9845f9f384cc1005c791487291` |
| `ssd.traineddata` | 11314684 | `f0060f4d2acb107f7c48c418f60887eddb37656fbbc2c21677df06ecbdf44ca5` |
| `ssd_int.traineddata` | 1442809 | `557759383e030694420ee9f6a88e824abae4acf17f7b94415ca07e1152339339` |

`assets/ocr/` preserva `LICENSE.tessdata_ssd` (Apache-2.0), `UPSTREAM-README.md`,
`SOURCE.json` e `NOTICE.txt`. Não foi adicionado downloader à aplicação.

## Empacotamento offline Windows

Os modelos são arquivos nativos, não precisam de `rootBundle` ou extração no
primeiro uso. `windows/CMakeLists.txt` verifica existência e SHA-256 e os instala
em **`ocr/tessdata/` ao lado de `balanca_desktop.exe`**. Os avisos/licença são
copiados para `ocr/licenses/tessdata_ssd/`. Isso acompanha Debug e Release.

O fluxo anterior de preparar engine/DLLs/eng com `tool/prepare_windows_ocr.ps1`
foi mantido. Esse script também verifica/copía os modelos especializados locais;
somente a preparação da máquina de build pode usar internet. Na estação de
operação, distribuir a pasta completa da aplicação, incluindo engine e DLLs.
Um executável sem engine não se torna autossuficiente apenas por conter modelos.

`TesseractRuntime.resolveModelDirectory()` procura primeiro `ocr/tessdata/`
relativo ao executável; no desenvolvimento usa `assets/ocr/tessdata/` do projeto.
O diretório dos modelos especializados independe do diretório do `eng`, portanto
desenvolvimento com engine instalada não exige alterar `Program Files`.
Nenhum caminho específico desta máquina foi colocado no código de produção.

Modelo ausente/corrompido aparece como falha técnica, com a alternativa genérica
preservada. A construção do pacote falha se os assets especializados estiverem
ausentes ou com hashes diferentes. A operação não consulta a internet.

## Estratégia e validação

`WeightOcrService` continua sendo o contrato da tela. A composição de produção
agora usa `SevenSegmentWeightOcrService`:

1. ROI original limpa → `7seg`, PSM **7**, whitelist **`0123456789.-`**, OEM 1.
2. Outras variantes da mesma ROI; se necessário, PSM **13** (raw line).
3. Sem leitura confiável, chama o adaptador **genérico anterior (`eng`)**.
4. Sem resultado validado/estável, mantém o fallback manual e a foto existente.

`ssd` e `ssd_int` **acompanham o pacote para comparação offline**, mas não são
ativados automaticamente na operação: a avaliação encontrou falsos positivos
de alta confiança com esses modelos. A lista de modelos é injetável para futura
calibração, mantendo a tela independente de Tesseract/ONNX/CNN.

A whitelist especializada pode ser reduzida pelo construtor para `0123456789`
quando o visor não usa sinal/decimal. O padrão conserva o sinal para evitar
converter um negativo em positivo. Um negativo continua sendo rejeitado pela
faixa operacional. `load_system_dawg=0` e `load_freq_dawg=0` são usados.
O genérico preserva sua gramática e seus passes originais, incluindo a unidade
`kg`; não passou a aceitar palavras arbitrárias ou substituir letras por dígitos.

Não há busca do primeiro número. O especializado valida o texto completo,
uma única linha TSV, 1–7 dígitos antes do decimal, até três casas e sinal opcional.
Rejeita rótulos, múltiplas linhas/números, datas de oito dígitos e formatos
inválidos. A ROI define a posição espacial permitida. Não é um detector semântico:
uma etiqueta numérica isolada dentro da ROI ainda exige enquadramento correto.

Para um quadro ser confiável, **dois pré-processamentos diferentes** precisam
concordar, com confiança >= 90%. Dois PSMs sobre a mesma variante não contam
como dois pré-processamentos. Valores divergentes reconhecidos dentro do modelo
vetam essa escolha, mesmo com confiança menor. Leituras confiáveis divergentes
entre o especializado e o fallback também impedem a sugestão.

`WeightRecognitionRules` usa os limites mínimo/máximo configurados na estação.
Não foi criado um novo limite arbitrário de produção; o valor inicial anterior
permanece editável na configuração local. Valores finitos e faixa válida são
exigidos. `20261105` e `99999999` também falham pelo número de dígitos.

## Pré-processamentos comparáveis

`seven_segment_preprocessor.dart` processa a ROI em **isolate** e mantém imagens
alternativas separadas:

* grayscale, normalização de contraste, polaridade baseada nas bordas;
* upscale cúbico, alvo padrão 2x, borda branca de 10 pixels;
* threshold global Otsu;
* threshold adaptativo por média local (janela 31×31, deslocamento 8);
* fechamento morfológico com raio **um pixel**, apenas em uma alternativa.

O comparador `--full` também avalia alvos 3x/4x, polaridade inversa,
redução de ruído + sharpen, dilatação e erosão separadamente. Não se aplica tudo
em sequência. Imagens ficam limitadas a 1600×600 antes da borda para conter
custo/memória; em ROIs grandes, o fator efetivo fica abaixo do alvo.
O genérico mantém seu localizador geométrico de linha e três variantes anteriores.

PSM 7 foi mantido como primeira opção: no controle impresso produziu leitura
correta/confiança suficiente; PSM 8/13 não mostraram vantagem consistente.
PSM 13 é alternativa na cascata; PSM 8 fica no comparador. Sem fotos reais do
indicador, não se afirma que um PSM foi calibrado para a estação.

## ROI, timestamp e evidência

A ROI existente foi reutilizada: posição/tamanho normalizados configuráveis em
Configurações Gerais, com retângulo visível no preview e em Testar câmera.
O editor numérico foi preservado; não foi acrescentado editor de arraste.

O processador primeiro corrige orientação/espelhamento e recorta o **frame limpo**.
Depois desenha data/hora somente na cópia destinada à evidência. O OCR recebe o
PNG limpo da ROI. O timestamp salvo nunca volta como entrada do OCR.
Nenhum pré-processamento/morfologia altera o JPEG de evidência.

Cada foto e JSON de tentativa continuam sendo preservados. Mesmo quando a engine
ou os modelos falham, a digitação só é liberada depois dessa falha. Sem câmera,
continua a contingência autorizada com ausência de evidência registrada.
Autorização, confirmação humana, Serial/TCP e Libra-API não foram alterados.

## Consenso temporal e confiança final

`WeightTemporalConsensus` exige o mesmo peso em **N fotografias independentes
consecutivas**, padrão 3, configurável de 2 a 5 em Configurações Gerais. São
snapshots separados por pelo menos 200 ms, além do tempo de análise. Uma mudança
ou leitura inválida encerra a tentativa em contingência; não se força maioria
durante transição de segmentos. Zero continua válido quando dentro da faixa.

O resultado mantém `rawText`, peso, modelo, PSM, pipeline, tempo, tentativas,
erro, confiança OCR, número de leituras e estado do consenso. A confiança
conservadora é o **mínimo** dos passes/quadros aceitos; `finalConfidence` fica
zero enquanto faltar formato/faixa/confiança/consenso. Repetição não promove
uma confiança baixa. Isso é um critério operacional, não uma probabilidade
estatística calibrada. Leitura estável errada continua sendo possível.

Os JSONs locais agora incluem `ocrModel`, `ocrPsm`, `ocrConfidence`,
`ocrFinalConfidence`, `ocrConsensus` e o número configurado de leituras.
O peso só é proposto após consenso, e **sempre requer confirmação humana**.

## Diagnóstico e reprodução

Em **Testar câmera → Testar leitura**, um quadro é capturado e analisado sem
registrar pesagem. Mostra texto, peso candidato, confiança, modelo, PSM,
pipeline, tempo e falha. É explicitamente um diagnóstico sem consenso temporal.

Em debug, habilitar a configuração de diagnóstico permite salvar opcionalmente
original, ROI, evidência, imagens de cada passe e `result.json`, em
`manual_weighing/diagnostics/` do diretório local da aplicação. Limite de dez
pacotes por execução; não há limpeza automática e nenhuma dessas imagens extras
é salva em Release. Falha desse diagnóstico não interrompe a pesagem. Os arquivos
podem conter o ambiente; revisar antes de compartilhar ou transformar em fixture.

Replay local da cascata (ROI explícita):

```powershell
dart run tool/diagnose_weight_ocr.dart foto.png 0.20 0.30 0.50 0.20
```

Comparar 7seg/ssd/ssd_int/eng na **mesma ROI** (PSM 7/8/13):

```powershell
dart run tool/compare_weight_models.dart foto.png 0.20 0.30 0.50 0.20 --out=build/ocr-comparison
dart run tool/compare_weight_models.dart foto.png 0.20 0.30 0.50 0.20 --full --out=build/ocr-comparison-full
```

`--full` é diagnóstico demorado, nunca roda automaticamente na operação.
O JSON registra cada tentativa, não uma autorização de pesagem. PNGs e relatórios
ficam no diretório indicado, sem alterar a imagem original. Para fixtures que
já contêm somente o visor, usar explicitamente `0 0 1 1`.

As fixtures adicionais em `test/fixtures/seven_segment/` são **sintéticas** e
reproduzíveis com `python tool/generate_seven_segment_fixtures.py` (Pillow,
somente no desenvolvimento, fonte DS-Digital existente). Não são fotografias.
O comparador completo avalia 288 combinações, além da linha de base genérica.

## Evidência empírica e limites

Foi localizada uma fotografia capturada pelo aplicativo na estação, mas ela não
contém visor de indicador. Não foi copiada nem versionada e não serve para medir
acurácia de peso. Não havia fotografia real adequada do indicador no workspace.
Portanto, **a validação óptica com webcam/indicador real permanece pendente**.

Nos testes sintéticos, `7seg` leu o controle impresso `12190` corretamente e foi
aceito pelos passes adequados. Na fixture DS-Digital `12190`, houve leitura correta
com confiança insuficiente; `ssd`/`ssd_int` também produziram `12130` com confiança
acima de 90%. Isso justifica não ativar esses modelos automaticamente e manter
fallback manual. O genérico também não foi confiável nessa fixture digital.
Não se afirma melhora percentual ou modelo vencedor para o indicador físico.

Os resultados por modelo/PSM/pipeline e tempos são preservados no relatório de
comparação desta entrega. Tempos dependem de máquina e concorrência; não são SLA.

Foram executadas **364 tentativas** em quatro fixtures sintéticas, usando
Tesseract 5.5.0 e `eng` tessdata_best 4.1.0. Há 288 combinações mais baseline
na grade digital completa e 25 tentativas em cada uma das outras três fixtures.
Veja [resumo JSON](ocr-evaluation/summary.json) e
[todas as tentativas CSV](ocr-evaluation/attempts.csv).

Melhor confiança bruta observada por modelo em cada fixture (não significa
aceitação da cascata ou consenso temporal):

| Fixture / peso esperado | 7seg | ssd | ssd_int | Genérico anterior (eng) |
| --- | --- | --- | --- | --- |
| Controle impresso / 12190 | 12190 · 93,09% | 12790 · 88,98% | 12790 · 89,47% | 12190 · 96,28% |
| DS-Digital / 12190, grade completa | 12190 · 73,94% | **12130 · 96,17% (errado)** | **12130 · 96,25% (errado)** | 12490 · 46,65% |
| DS-Digital / 570.0 | 570.0 · 82,20% | **510.0 · 96,39% (errado)** | **510.0 · 96,34% (errado)** | 0 · 0% |
| DS-Digital / 0.00 | 0.00 · 61,50% | 0.00 · 93,58% | 0.00 · 93,66% | 0.00 · 94,39% |

Na grade digital completa, 7seg teve zero tentativas acima do limite; ssd teve
11 saídas erradas acima do limite, e ssd_int teve nove. As medianas de execução
por processo nessa grade foram aproximadamente 152/180/112 ms para
7seg/ssd/ssd_int; o tempo de pipeline inclui também preparo e outros passes.
Não há evidência suficiente para proclamar vencedor no indicador real.

O orçamento entre passes especializados é 10 segundos, com timeout de processo
de 15 segundos herdado do adaptador; o fallback genérico tem seus próprios passes.
Processamento ocorre em isolate/processo assíncrono e exibe `Analisando visor...`.
Cancelar encerra a câmera e ignora resultados tardios; o processo OCR pendente
pode concluir antes do timeout, sem registrar pesagem.

Próxima calibração deve usar fotos representativas com peso conhecido, zero,
sinal/decimal, reflexos, mudanças de segmentos e condições de foco/iluminação.
Testar especificamente separadores e sinais para não alterar ordem de grandeza.
Treinamento ou engine local alternativa continuam possíveis pela abstração.

## Arquivos principais da evolução

* `seven_segment_ocr_service.dart`: cascata especializada e seleção coerente.
* `seven_segment_preprocessor.dart`: pipelines de imagem comparáveis.
* `weight_recognition_validation.dart`: faixa e consenso temporal.
* `ocr_diagnostics_store.dart`: persistência opcional e limitada em debug.
* `weight_ocr_service.dart`: adaptador CLI reutilizável por modelo/PSM/whitelist,
  preservando o reconhecimento genérico anterior.
* `capture_models.dart`, `capture_controller.dart`, `manual_capture_services.dart`:
  metadados, consenso configurável e composição local.
* `capture_dialog.dart`, `manual_webcam_settings.dart`: Testar leitura e quantidade
  de leituras consecutivas, mantendo a confirmação operacional existente.
* `tesseract_runtime.dart`, `windows/CMakeLists.txt`, `tool/prepare_windows_ocr.ps1`:
  resolução relativa, integridade e cópia dos modelos/licenças.
* `assets/ocr/`, `test/seven_segment_ocr_test.dart`, `test/fixtures/seven_segment/`,
  `tool/compare_weight_models.dart`, `tool/generate_seven_segment_fixtures.py`:
  binários reais, proveniência, regressões e comparação reproduzível.
* `tool/diagnose_weight_ocr.dart`, `runtime/windows/README.md`,
  `runtime/windows/LEIA-ME-ESTACAO.txt`: replay da cascata e instruções de operação.

Os arquivos Dart acima, salvo configurações e ferramentas explicitadas, ficam em
`lib/features/pesagem/manual_capture/`. A autorização e a integração de indicador
não precisaram de alterações.

## Validação da entrega

* `dart format`: aplicado aos 19 arquivos Dart envolvidos.
* `flutter analyze`: nenhum apontamento.
* `flutter test`: **242 testes aprovados**, sem testes ignorados, incluindo 19
  novos casos e execuções reais do Tesseract local.
* `flutter build windows --debug`: concluído. Engine empacotada lista `7seg`,
  `ssd`, `ssd_int` e `eng`; modelos instalados no diretório esperado.
* Comparador: 364 tentativas registradas, incluindo grade 2x/3x/4x e PSM 7/8/13.
* Nenhum commit, push, alteração em outro repositório ou chamada OCR cloud.

## Correção após captura real de 05/11/2026 às 12:32

Após a avaliação inicial, ficou disponível uma evidência real da webcam mostrando
o painel com **570.0**. Ela usa a ROI padrão ampla, que inclui textos, ícones e
teclado. Foi acrescentada a fixture sanitizada
`test/fixtures/weight_ocr/ind570_webcam_570.png`, com proveniência no arquivo `.md`
adjacente; o original com ambiente/pessoa não foi versionado.

O registro da tentativa tinha `ocrRawText=-570.0`, confiança **0**, erro original
`OCR_BAIXA_CONFIANCA`. A faixa da estação era 0–100000 kg. O validador aplicava
faixa sobre um candidato já inválido e substituía o motivo por
`OCR_FORA_DA_FAIXA`, induzindo diagnóstico incorreto.

`WeightRecognitionRules` agora preserva a falha original quando o resultado OCR
não é confiável; só aplica faixa a uma leitura previamente válida. Negativos
confiáveis continuam rejeitados. O diálogo mostra leitura descartada/confiança
e, nas violações reais de faixa, os limites usados. Evidência e fallback continuam.

A avaliação com recorte fechado encontrou passes corretos e também perda do
ponto decimal (`5700`). Não se alterou automaticamente a ROI da estação, não se
expandiu a faixa, não se aplicou valor absoluto nem conversão de escala inferida.
O ajuste de ROI deve enquadrar somente os dígitos, incluindo sinal/ponto, em
Configurações Gerais → Webcam → Ajustar ROI e validação OCR.

Validação desta correção: `dart format` aplicado, `flutter analyze` sem
apontamentos e `flutter test` com **245 testes aprovados**, incluindo a nova
captura real e a regressão de precedência do motivo de falha.
