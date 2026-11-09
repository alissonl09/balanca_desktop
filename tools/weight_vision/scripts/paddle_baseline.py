"""PaddleOCR 3.x static local baseline, invoked only by development tools."""
import json
import os
from pathlib import Path
import re
import sys
import time


def run(image):
    from importlib.util import find_spec
    if find_spec('paddleocr') is None or find_spec('paddle') is None:
        return {'error': 'PADDLE_NOT_INSTALLED'}
    paths = [os.environ.get('WEIGHT_PADDLE_DET_DIR', ''),
             os.environ.get('WEIGHT_PADDLE_REC_DIR', '')]
    if not all(p and Path(p).is_dir() for p in paths):
        return {'error': 'PADDLE_LOCAL_MODELS_REQUIRED'}
    # Avoid model discovery/download. All enabled components have local paths.
    os.environ['PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK'] = 'True'
    from paddleocr import PaddleOCR
    from importlib.metadata import version
    start = time.perf_counter()
    ocr = PaddleOCR(
        text_detection_model_name='PP-OCRv5_mobile_det',
        text_detection_model_dir=paths[0],
        text_recognition_model_name='PP-OCRv5_mobile_rec',
        text_recognition_model_dir=paths[1],
        use_doc_orientation_classify=False, use_doc_unwarping=False,
        use_textline_orientation=False, device='cpu')
    load_ms = (time.perf_counter() - start) * 1000
    start = time.perf_counter()
    results = list(ocr.predict(input=str(Path(image).resolve())))
    inference_ms = (time.perf_counter() - start) * 1000
    candidates = []
    for result in results:
        data = result.json
        if isinstance(data, str):
            data = json.loads(data)
        data = data.get('res', data)
        candidates.extend(zip(data.get('rec_texts', []), data.get('rec_scores', [])))
    # Ambiguous multiple lines fail instead of choosing/completing a number.
    if len(candidates) != 1:
        return {'error': 'PADDLE_AMBIGUOUS_OR_EMPTY', 'candidates': candidates,
                'inferenceMs': inference_ms, 'loadMs': load_ms}
    sequence, confidence = candidates[0]
    sequence = sequence.strip()
    return {'sequence': sequence, 'confidence': float(confidence),
            'error': None if re.fullmatch(r'\d+(\.\d+)?', sequence) else 'PADDLE_INVALID_SEQUENCE',
            'inferenceMs': inference_ms, 'loadMs': load_ms,
            'paddleocrVersion': version('paddleocr'),
            'paddleVersion': version('paddlepaddle'), 'modelDirectories': paths}


if __name__ == '__main__':
    # Keep stdout machine-readable even if the framework logs to stdout.
    from contextlib import redirect_stdout
    try:
        with redirect_stdout(sys.stderr):
            output = run(sys.argv[1])
    except Exception as error:
        output = {'error': 'PADDLE_ERROR', 'details': str(error)}
    print(json.dumps(output, ensure_ascii=False))
