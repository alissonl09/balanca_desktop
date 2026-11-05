# OCR portátil Windows

Execute `tool/prepare_windows_ocr.ps1 -SevenZipPath 'C:/Program Files/7-Zip/7z.exe'`
na máquina de build e depois `flutter build windows --release`.

O script extrai o pacote oficial Tesseract 5.5.3 (SHA-256 verificado), DLLs,
modelo inglês `tessdata_best` 4.1.0 (SHA-256 verificado) e documentação/licença
em `tesseract/`, ignorado pelo Git.
Não executa instalador, não altera registro e não muda PATH.
O 7-Zip é necessário somente para preparar o build.

O CMake copia esse runtime para `ocr/` ao lado de `balanca_desktop.exe`.
Distribua a pasta Release inteira, incluindo `ocr/`, `data/` e as DLLs.
Não copie apenas o executável para a estação.

Os modelos especializados ficam versionados em `assets/ocr/tessdata/`:
`7seg`, `ssd` e `ssd_int`. O script valida os hashes e os copia para o runtime;
o CMake também valida e instala esses modelos em `ocr/tessdata/`, mesmo quando
a engine usada no desenvolvimento vem de uma instalação existente. Nenhum
download ocorre em runtime. `7seg` é prioritário, `eng` continua como fallback;
`ssd`/`ssd_int` são reservados ao comparador até calibração com fotos reais.
Licença, proveniência e avaliação: `docs/ocr-sete-segmentos.md`.
