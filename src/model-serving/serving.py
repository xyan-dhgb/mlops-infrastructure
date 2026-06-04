"""
src/model-serving/serving.py
Request (KServe V1 protocol):
  POST /v1/models/skin-prediction:predict
  {
    "instances": [{
      "image": "<base64 JPEG/PNG>",
      "tabular_raw": {
        "age_approx": 45,
        "sex": "male",
        "anatom_site_general": "anterior torso",
      }
    }]
  }

Response:
  {
    "predictions": [{
      "label": "Malignant" | "Benign",
      "probability": 0.8341,
      "inference_ms": 120.5
    }]
  }
"""

from __future__ import annotations

import base64
import io
import logging
import os
import pickle
import time

import cv2
import numpy as np
import pandas as pd
from PIL import Image
import tf_keras as keras   # Keras 2.x legacy — tương thích với model .h5 train bằng TF 2.x
import tensorflow as tf
from kserve import Model, ModelServer


# ── Compatibility shims ──────────────────────────────────────────────────────
# Shim 1: Model .h5 được train bằng TF cũ hơn có InputLayer config chứa
# 'batch_shape' và 'optional' — hai kwargs này đã bị xóa khỏi tf_keras 2.15.
class _CompatInputLayer(keras.layers.InputLayer):
    @classmethod
    def from_config(cls, config):
        config.pop("batch_shape", None)
        config.pop("optional", None)
        return super().from_config(config)

# Shim 2: Model .h5 được save bằng Keras 3.x (standalone `keras` package) sẽ
# serialize dtype của mỗi layer thành DTypePolicy({'name': 'float32', ...}).
# tf_keras (Keras 2.x) không khai báo class này → TypeError khi deserialize.
# Stub tối giản: chỉ cần from_config() trả về đúng tên policy để tf_keras
# resolve dtype nội bộ.
class _DTypePolicy:
    """Minimal stub to deserialize Keras 3.x DTypePolicy saved in .h5 files."""
    def __init__(self, name: str = "float32", **_):
        self.name = name

    @classmethod
    def from_config(cls, config: dict):
        return cls(name=config.get("name", "float32"))

    def get_config(self):
        return {"name": self.name}
# ───────────────────────────────────────────────────────────────────────────────

logger = logging.getLogger("kserve-serving")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

# Constants – same as data_preprocessing.py in mlops-model
TARGET_SIZE    = (224, 224)
CLAHE_CLIP     = 2.0
GAUSS_KERNEL   = (3, 3)
CATEGORICAL_COLS = ["sex", "anatom_site_general"]


def _dummy_focal_loss(y_true, y_pred):
    """Placeholder to load model without missing custom object error."""
    return tf.reduce_mean(y_pred)  # type: ignore[return-value]


# Image helpers
def _preprocess_image(img_bytes: bytes) -> np.ndarray:
    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    img = img.resize(TARGET_SIZE, Image.Resampling.LANCZOS)
    uint8 = np.array(img, dtype=np.uint8)

    # CLAHE on L channel (LAB color space)
    lab = cv2.cvtColor(uint8, cv2.COLOR_RGB2LAB)
    clahe = cv2.createCLAHE(clipLimit=CLAHE_CLIP, tileGridSize=(8, 8))
    lab[:, :, 0] = clahe.apply(lab[:, :, 0])
    uint8 = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)

    # Gaussian blur
    uint8 = cv2.GaussianBlur(uint8, GAUSS_KERNEL, 0)

    # Contrast ×1.2
    from PIL import ImageEnhance
    pil = Image.fromarray(uint8)
    uint8 = np.array(ImageEnhance.Contrast(pil).enhance(1.2))

    return uint8.astype(np.float32) / 255.0


# Tabular helper
def _preprocess_tabular(raw_dict: dict, preproc: dict) -> np.ndarray:
    """
    Transform raw metadata dict → standardized float32 vector (38 features).

    preproc is a dict loaded from preprocessors.pkl:
      - feature_cols:   danh sách tên cột sau khi xử lý
      - label_encoders: dict LabelEncoder (fit trên train)
      - scaler:         StandardScaler (fit trên train)
      - imputer:        SimpleImputer strategy=median (fit trên train)
    """
    feature_cols   = preproc["feature_cols"]
    label_encoders = preproc["label_encoders"]
    scaler         = preproc["scaler"]
    imputer        = preproc["imputer"]

    # Create 1 DataFrame from raw dict, missing columns will be NaN
    row = {col: raw_dict.get(col, np.nan) for col in feature_cols}
    df  = pd.DataFrame([row])

    # Encode categorical columns using LabelEncoder fitted during training
    for col, le in label_encoders.items():
        if col not in df.columns:
            continue
        val = str(df[col].iloc[0])
        # If the value is unknown (never seen during training) → fallback to the first class
        val = val if val in set(le.classes_) else le.classes_[0]
        df[col] = le.transform([val])

    X = df.values.astype(np.float32)
    X = imputer.transform(X)   # fill NaN with median
    X = scaler.transform(X)    # standardize
    return X.astype(np.float32)

# KServe Custom Predictor
class SkinPredictionModel(Model):
    def __init__(self, name: str):
        super().__init__(name)
        self.model    = None  
        self.preproc  = None
        self.threshold = float(os.environ.get("THRESHOLD", "0.5"))
        self.load()

    def load(self):
        # Load artifacts from /mnt/models (KServe Storage Initializer tự mount từ S3).
        model_path     = os.environ.get("MODEL_PATH",          "/mnt/models/best_model_isic2024.h5")
        preproc_path   = os.environ.get("PREPROCESSORS_PATH",  "/mnt/models/encoders.pkl")
        threshold_path = os.environ.get("THRESHOLD_PATH",      "/mnt/models/best_threshold.txt")

        logger.info("[load] Loading Keras model from %s …", model_path)
        self.model = keras.models.load_model(
            model_path,
            custom_objects={
                # Tên phải khớp với fn.__name__ = 'focal_loss' trong train.py
                "focal_loss": _dummy_focal_loss,
                # Shim để bỏ qua batch_shape/optional trong InputLayer config
                "InputLayer": _CompatInputLayer,
                # Shim để deserialize DTypePolicy từ model save bằng Keras 3.x
                # tf_keras (Keras 2.x) không biết class này → TypeError khi load
                "DTypePolicy": _DTypePolicy,
            },
            compile=False,
        )
        logger.info("[load] Model output shape: %s", self.model.output_shape)

        logger.info("[load] Loading preprocessors (encoders.pkl) from %s …", preproc_path)
        with open(preproc_path, "rb") as f:
            self.preproc = pickle.load(f)

        # Threshold loaded from best_threshold.txt by evaluate.py
        if os.path.exists(threshold_path):
            with open(threshold_path) as f:
                self.threshold = float(f.read().strip())
            logger.info("[load] Threshold loaded from best_threshold.txt: %.4f", self.threshold)
        else:
            logger.warning("[load] best_threshold.txt not found, using default %.2f", self.threshold)

        n_features = len(self.preproc.get("feature_cols", []))
        logger.info(
            "[load] Ready. features=%d  threshold=%.4f",
            n_features, self.threshold,
        )
        self.ready = True

    def preprocess(self, payload: dict, headers=None):
        """
        Biến đổi request JSON → (img_tensor, tab_tensor) để model.predict().

        Payload (KServe V1):
        {
          "instances": [{
            "image": "<base64>",
            "tabular_raw": { "age_approx": 45, "sex": "male", ... }
          }]
        }
        """
        instance = payload["instances"][0]

        # Image
        img_bytes = base64.b64decode(instance["image"])
        img_arr   = _preprocess_image(img_bytes)          # shape (224, 224, 3)
        img_t     = img_arr[np.newaxis].astype(np.float32) # shape (1, 224, 224, 3)

        # Tabular
        raw_dict = instance["tabular_raw"]
        tab_t    = _preprocess_tabular(raw_dict, self.preproc)  # shape (1, 38)

        return {"image": img_t, "tabular": tab_t}

    def predict(self, data: dict, headers=None):
        # Binary prediction: Benign (0) / Malignant (1).
        t0 = time.perf_counter()

        prob = float(
            self.model.predict(
                {"image_input": data["image"], "tabular_input": data["tabular"]},
                verbose=0,
            )[0, 0]
        )

        pred_class = int(prob >= self.threshold)
        label      = "Malignant" if pred_class == 1 else "Benign"
        elapsed_ms = (time.perf_counter() - t0) * 1000

        logger.info(
            "[predict] %s  prob=%.4f  threshold=%.2f  ms=%.1f",
            label, prob, self.threshold, elapsed_ms,
        )

        return {
            "predictions": [{
                "label":       label,
                "probability": round(prob, 4),
                "inference_ms": round(elapsed_ms, 1),
            }]
        }


if __name__ == "__main__":
  # The name of the model must be fit to metadata.name in inference-service.yaml
    ModelServer().start([SkinPredictionModel("skin-prediction")])
