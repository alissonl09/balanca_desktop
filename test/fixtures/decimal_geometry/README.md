# Controles de geometria decimal

PNGs sintéticos gerados por `dart run tool/generate_decimal_fixtures.dart`.
Não são capturas de webcam e não medem acurácia óptica de produção.
Cada dígito é construído por segmentos geométricos em
`test/support/display_fixture.dart`; os testes passam uma sequência OCR de
controle para verificar exclusivamente a localização do separador na imagem.

Incluem 0.0, 10.0, 100.0, 570.0, 12190, 5700, ponto pequeno, luz baixa e
resoluções menor/maior. A regressão com Tesseract real usa a fotografia
`../weight_ocr/ind570_webcam_570.png`, cuja proveniência fica ao lado dela.
