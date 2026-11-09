"""Validate local COCO digit annotations without external dependencies."""
import json
import math
from pathlib import Path
import sys


def validate(path):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    expected = [str(i) for i in range(10)] + ['decimal_point']
    categories = {c['id']: c['name'] for c in data['categories']}
    if categories != dict(enumerate(expected)):
        raise ValueError('Categories must be IDs 0..10 in classes.json order')
    images = {i['id']: i for i in data['images']}
    if len(images) != len(data['images']):
        raise ValueError('Duplicate image IDs')
    ids = set()
    counts = {c: 0 for c in expected}
    for a in data['annotations']:
        if a['id'] in ids:
            raise ValueError('Duplicate annotation ID')
        ids.add(a['id'])
        image = images[a['image_id']]
        x, y, w, h = a['bbox']
        if (not all(math.isfinite(v) for v in [x, y, w, h]) or
                x < 0 or y < 0 or w <= 0 or h <= 0 or
                x + w > image['width'] or y + h > image['height']):
            raise ValueError(f"Invalid bbox: {a['id']}")
        counts[categories[a['category_id']]] += 1
    return {'images': len(images), 'annotations': len(ids),
            'classCounts': counts, 'missingClasses': [c for c, n in counts.items() if n == 0]}


if __name__ == '__main__':
    print(json.dumps(validate(sys.argv[1]), indent=2))
