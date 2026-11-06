# Pesagem manual: foto ou OCR contínuo

Atualização de 05/11/2026. O diagnóstico anterior da cascata continua em
[OCR decimal](ocr-decimal-diagnostico.md); a operação agora usa o fluxo abaixo.

## Configuração

Em **Configurações → Configurações Gerais → Webcam da Pesagem Manual**, com
**Pesagem manual** habilitada, selecionar **Leitura do peso na pesagem manual**:

* **Ler a imagem por OCR:** abre a câmera e inicia a leitura contínua do visor.
* **Não ler a imagem: foto e digitação do peso:** captura uma foto, salva a
  evidência com data/hora e libera o campo de peso, sem executar Tesseract.

A escolha é salva imediatamente no `webcam.json` local da estação, junto com a
configuração existente. OCR fica **desligado por padrão**, inclusive para
configurações antigas que não possuem o campo `ocrEnabled`. Desativar a pesagem
manual oculta a opção; não altera a preferência salva para futura reativação.
O OCR de Gestão de Veículos/SGV é uma configuração separada e não foi alterado.

## Foto com digitação

Após autorização, **Capturar foto** salva uma única foto e libera o campo vazio.
Não são feitos crop da ROI, PNGs de diagnóstico, threshold, consenso ou chamadas
ao Tesseract. Somente normalização e carimbo da foto são necessários.
A evidência usa `MANUAL_WITH_PHOTO`, `ocrEnabled=false` e não registra falha OCR
fictícia. Falha real de câmera/armazenamento continua no tratamento existente.
O operador informa o peso e confirma antes de prosseguir.

## OCR contínuo

O preview permanece fluido enquanto um serviço separado analisa fotos originais
da câmera, uma por vez. A ROI salva é aplicada ao frame nativo, sem screenshot
do preview. Não há fila de trabalhos nem OCR simultâneo sobre múltiplos frames.

O caminho operacional usa **eng / PSM 7**, whitelist **`0123456789.-`**,
grayscale/contraste e Otsu em 2x: **dois passes por quadro**. Mantém a detecção
visual do ponto, validação de faixa/casas decimais, confiança mínima de 90% e
consenso entre fotografias. Cada processo Tesseract tem limite de **900 ms**;
ao excedê-lo, o processo é encerrado e a leitura não fica verde.
A cascata longa de modelos, escalas e filtros permanece disponível para
diagnóstico offline, mas não roda no preview operacional.

O intervalo mínimo entre análises é de 250 ms após concluir a anterior. Em
condições favoráveis, três leituras concordantes produzem a indicação verde em
alguns segundos. O número de leituras continua configurável; repetir uma saída
de baixa confiança não a promove para válida.

* **Amarelo:** procurando número/estabilidade; campo bloqueado e sem sugestão aceita.
* **Verde:** leitura confiável com consenso; retângulo e ícone verdes, peso
  preenchido automaticamente no campo e edição bloqueada.
* Uma leitura inválida remove a sugestão e o verde. Sem atualização por dois
  segundos, a sugestão expira; observações muito espaçadas reiniciam o consenso.
* **Capturar peso** congela a leitura aceita e salva exatamente a foto que a
  produziu, sem repetir o OCR. A confirmação humana continua obrigatória.
* Sem verde, **Capturar foto e digitar peso** preserva a foto e libera o fallback
  manual. Não é necessário aguardar a antiga sequência de tentativas.
* **Retomar leitura ao vivo** reabre o acompanhamento após uma captura, descartando
  o peso congelado e exigindo novo consenso. Fechar o diálogo cancela os timers,
  encerra a câmera e ignora resultados atrasados.

As fotos transitórias do preview não são gravadas como evidências de pesagem.
A foto e o JSON de auditoria são persistidos ao capturar/confirmar. O plugin da
câmera pode usar seus próprios arquivos temporários, removidos após cada snapshot.

## Medição e validação

[Benchmark registrado](ocr-live-benchmark.json), com o Tesseract real nesta máquina:

| Controle | Resultado |
| --- | --- |
| Imagem | Recorte 317×104 da fixture real histórica de 570.0 |
| Passes por quadro | 2 |
| Análises sucessivas | 695, 644 e 604 ms |
| Tempo até verde | **2475 ms**, três leituras concordantes |
| Peso / confiança final | **570.0 / 94,69%** |

Esse benchmark repete o mesmo arquivo histórico, simulando os snapshots; não
inclui latência física de uma nova webcam, nem comprova estabilidade óptica no
indicador instalado. Em execução concorrente da suíte, um quadro demorou cerca
de 1,2–1,3 s. Distância, foco, reflexos e tamanho da ROI ainda afetam o resultado.

Reproduzir o benchmark:

```powershell
flutter test tool/live_ocr_benchmark_test.dart --reporter expanded
```

Os testes cobrem persistência/default, opção oculta com pesagem manual desligada,
foto única sem OCR, campo editável após foto, duas variantes rápidas, decimal
real, verde/campo bloqueado, expiração, baixa confiança, cancelamento e foto
correspondente à leitura sem novo OCR. Serial/TCP, autorização, confirmação,
`balanca-web` e Libra-API permanecem sem alterações. Não foi feito commit/push.

Verificação final: `dart format` em 25 arquivos sem ajustes restantes,
`flutter analyze` sem apontamentos e `flutter test` com **274 aprovados**, zero
falhas e zero testes ignorados. `git diff --check` sem erros de whitespace.
`flutter build windows --debug --no-pub` concluído; executável em
`build/windows/x64/runner/Debug/balanca_desktop.exe`.
