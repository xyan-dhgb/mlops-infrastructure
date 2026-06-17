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
# Keras 3.x to Keras 2.x (tf_keras) loading fixes

# Shim 1: Handle InputLayer config changes
class _CompatInputLayer(keras.layers.InputLayer):
    @classmethod
    def from_config(cls, config):
        # Keras 3 saves 'batch_shape' or 'shape' sometimes as string "(None, 224, 224, 3)"
        shape = config.pop("batch_shape", None) or config.pop("shape", None)
        if isinstance(shape, str) and shape.startswith("(") and shape.endswith(")"):
            try:
                shape = eval(shape, {"None": None})
            except Exception:
                pass
        if shape is not None:
            config["batch_input_shape"] = shape
            
        config.pop("optional", None)
        return super().from_config(config)

# Shim 2: Stub for DTypePolicy
class _DTypePolicy:
    """Minimal stub to deserialize Keras 3.x DTypePolicy saved in .h5 files."""
    def __init__(self, name: str = "float32", **_):
        self.name = name
        self.compute_dtype = name
        self.variable_dtype = name

    @classmethod
    def from_config(cls, config: dict):
        return cls(name=config.get("name", "float32"))

    def get_config(self):
        return {"name": self.name}

# Shim 3: Strip Keras 3 specific kwargs and fix stringified shapes recursively
_original_layer_from_config = keras.layers.Layer.from_config

import sys

def _fix_stringified_shapes(obj):
    """Recursively converts stringified tuples/lists back to Python objects in config."""
    if isinstance(obj, dict):
        for k, v in list(obj.items()):
            if isinstance(v, str) and (
                (v.startswith("(") and v.endswith(")")) or 
                (v.startswith("[") and v.endswith("]"))
            ):
                try:
                    obj[k] = eval(v, {"None": None, "null": None})
                except Exception:
                    pass
            else:
                _fix_stringified_shapes(v)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            if isinstance(v, str) and (
                (v.startswith("(") and v.endswith(")")) or 
                (v.startswith("[") and v.endswith("]"))
            ):
                try:
                    obj[i] = eval(v, {"None": None, "null": None})
                except Exception:
                    pass
            else:
                _fix_stringified_shapes(v)

@classmethod
def _patched_layer_from_config(cls, config):
    config.pop("quantization_config", None)
    _fix_stringified_shapes(config)
    return _original_layer_from_config.__func__(cls, config)

keras.layers.Layer.from_config = _patched_layer_from_config

# Shim 4: Fix Keras 3 inbound_nodes and wrap in try-except to dump locals
_original_model_from_config = keras.models.Model.from_config


def _convert_keras3_node(node):
    """Convert a single Keras 3.x inbound_node (dict with 'args'/'kwargs')
    to the Keras 2.x format ([[layer_name, node_index, tensor_index, kwargs]])."""
    if not (isinstance(node, dict) and "args" in node):
        return None  # Not a Keras 3 node

    converted = []
    for arg in node.get("args", []):
        if isinstance(arg, dict) and arg.get("class_name") == "__keras_tensor__":
            history = arg["config"]["keras_history"]
            # history = [layer_name, node_index, tensor_index]
            converted.append([history[0], history[1], history[2], {}])
        elif isinstance(arg, list):
            # List of __keras_tensor__ (e.g. Concatenate, Add, Multiply)
            sub = []
            for item in arg:
                if isinstance(item, dict) and item.get("class_name") == "__keras_tensor__":
                    h = item["config"]["keras_history"]
                    sub.append([h[0], h[1], h[2], {}])
            if sub:
                converted.extend(sub)

    # kwargs may also contain __keras_tensor__ refs — drop them
    # (training, mask, etc. are runtime-only, not needed for topology)

    return converted if converted else None


@classmethod
def _patched_model_from_config(cls, config, custom_objects=None):
    _fix_stringified_shapes(config)
    
    if "layers" in config:
        for layer_config in config["layers"]:
            inbound_nodes = layer_config.get("inbound_nodes", [])
            new_inbound = []
            for node in inbound_nodes:
                # ── Keras 3.x dict format ──
                k3 = _convert_keras3_node(node)
                if k3 is not None:
                    new_inbound.append(k3)
                # ── Keras 3.x bare-string shortcut ──
                elif isinstance(node, str):
                    new_inbound.append([[node, 0, 0, {}]])
                # ── Keras 2.x list format (may need wrapping) ──
                elif isinstance(node, list):
                    if len(node) > 0 and isinstance(node[0], str):
                        new_inbound.append([node])
                    else:
                        new_inbound.append(node)
                else:
                    new_inbound.append(node)
            if new_inbound:
                layer_config["inbound_nodes"] = new_inbound
                
    try:
        return _original_model_from_config.__func__(cls, config, custom_objects)
    except AttributeError as e:
        if "'str' object has no attribute 'as_list'" in str(e):
            _, _, tb = sys.exc_info()
            while tb.tb_next:
                tb = tb.tb_next
            logger.error("CRASH in from_config. Locals: %s", tb.tb_frame.f_locals)
        raise e

keras.models.Model.from_config = _patched_model_from_config
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

    # imputer was fit on numeric-only columns (excludes categoricals already label-encoded).
    # Apply imputer only on those columns to avoid shape mismatch.
    cat_cols = set(label_encoders.keys())
    numeric_idx = [i for i, c in enumerate(feature_cols) if c not in cat_cols]
    if X.shape[1] != imputer.n_features_in_:
        # Selective imputation: only numeric columns
        X[:, numeric_idx] = imputer.transform(X[:, numeric_idx])
    else:
        X = imputer.transform(X)   # fill NaN with median (all cols)

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
