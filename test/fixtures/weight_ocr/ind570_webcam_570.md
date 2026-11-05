# Captura real da webcam — IND570, 570.0

`ind570_webcam_570.png` deriva de uma evidência capturada pelo aplicativo em
05/11/2026 às 12:32:11, horário local da estação. Valor visual: **570.0**.

Foi preservado somente o recorte normalizado da ROI utilizada na tentativa:
X=0.1, Y=0.25, largura=0.8, altura=0.5 de uma fotografia 1280×720.
O PNG final mede 1024×360. Contém o painel, sem pessoa, ambiente, autorizador,
credenciais, placa ou timestamp. A fotografia original não foi versionada.
SHA-256 da evidência original:
`15a7b9abc3cb0a39272af308e6957214ec6933bf6c81e3cfaf2e51387d7d6d29`.

É uma captura óptica real do painel mostrado à webcam, não uma imagem sintética.
Não comprova que o instrumento estava conectado a uma balança em operação.
A ROI ampla inclui capacidade, ícones e teclado: reproduz o problema observado.

No registro original, os passes retornaram `5700` com confiança insuficiente e
`-570.0` com confiança zero. A validação sobrescrevia `OCR_BAIXA_CONFIANCA` com
`OCR_FORA_DA_FAIXA`. A regressão exige preservar a falha de OCR; leituras negativas
confiáveis continuam sendo rejeitadas pela faixa. Não se aplica valor absoluto,
divisão por dez ou redução de confiança para forçar 570.0.
