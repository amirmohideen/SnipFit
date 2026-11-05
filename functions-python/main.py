"""Coverage service for the AI try-on safety check.

Measures how much of the person in an image is skin versus clothing, using
the same MediaPipe multi-class selfie segmenter (selfie_multiclass_256x256)
that the app runs on the phone. The TypeScript pipeline compares the person
photo with every AI result and blocks any result that shows more skin.

Images arrive in the request body only; nothing is stored or logged.
"""

import base64
import io
import json
import os
import urllib.request

import mediapipe as mp
import numpy as np
from firebase_functions import https_fn, options
from firebase_functions.params import SecretParam
from PIL import Image

TOKEN = SecretParam("COVERAGE_SERVICE_TOKEN")
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/"
    "selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite"
)
MODEL_PATH = "/tmp/selfie_multiclass_256x256.tflite"

# Class indices of the multi-class selfie model.
BACKGROUND, HAIR, BODY_SKIN, FACE_SKIN, CLOTHES, OTHER = range(6)

_segmenter = None


def _get_segmenter():
    global _segmenter
    if _segmenter is None:
        if not os.path.exists(MODEL_PATH):
            urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        options_ = mp.tasks.vision.ImageSegmenterOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=MODEL_PATH),
            output_category_mask=True,
            output_confidence_masks=False,
        )
        _segmenter = mp.tasks.vision.ImageSegmenter.create_from_options(options_)
    return _segmenter


def ratios(image_bytes: bytes) -> dict:
    """Skin and clothing shares of the person's pixels."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    image.thumbnail((1024, 1024))
    frame = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.asarray(image))
    mask = _get_segmenter().segment(frame).category_mask.numpy_view()
    person = mask != BACKGROUND
    n = max(int(person.sum()), 1)
    skin = np.isin(mask, (BODY_SKIN, FACE_SKIN)).sum()
    clothes = np.isin(mask, (CLOTHES, OTHER)).sum()
    return {
        "skin": float(skin) / n,
        "clothes": float(clothes) / n,
        "person": float(person.mean()),
    }


@https_fn.on_request(
    secrets=[TOKEN],
    memory=options.MemoryOption.GB_1,
    max_instances=10,
    region="us-central1",
)
def coverage(req: https_fn.Request) -> https_fn.Response:
    if req.headers.get("Authorization") != f"Bearer {TOKEN.value}":
        return https_fn.Response("unauthorized", status=401)
    body = req.get_json(silent=True) or {}
    try:
        before = ratios(base64.b64decode(body["before"]))
        after = [ratios(base64.b64decode(a)) for a in body.get("after", [])]
    except (KeyError, ValueError, OSError):
        return https_fn.Response("bad request", status=400)
    return https_fn.Response(
        json.dumps({"before": before, "after": after}),
        mimetype="application/json",
    )
