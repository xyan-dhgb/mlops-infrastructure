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
from PIL import Image, ImageDraw, ImageFont
import tf_keras as keras   # Keras 2.x legacy — tương thích với model .h5 train bằng TF 2.x
import tensorflow as tf
from kserve import Model, ModelServer
from prometheus_client import Counter, Histogram


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
            # Keras 3.x may store batch_shape with a leading concrete batch size
            # e.g. (1, None, 224, 224, 3) → tf_keras expects (None, 224, 224, 3).
            # Strip the leading dim if it is a concrete integer (not None).
            if isinstance(shape, (list, tuple)) and len(shape) >= 2 and shape[0] is not None:
                shape = tuple(shape[1:])
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
            # Fix InputLayer 5D shape directly in model config
            if layer_config.get("class_name") == "InputLayer":
                l_cfg = layer_config.get("config", {})
                shape = l_cfg.pop("batch_shape", None) or l_cfg.pop("shape", None)
                if isinstance(shape, str) and shape.startswith("(") and shape.endswith(")"):
                    try:
                        shape = eval(shape, {"None": None})
                    except Exception:
                        pass
                if shape is not None:
                    if isinstance(shape, (list, tuple)) and len(shape) >= 2 and shape[0] is not None:
                        shape = tuple(shape[1:])
                    l_cfg["batch_input_shape"] = shape
                l_cfg.pop("optional", None)

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

# ── Custom Prometheus Metrics ────────────────────────────────────────────────
# KServe ModelServer đã expose /metrics với request_count, request_duration_ms.
# Chỉ thêm các metrics về prediction outcome mà KServe không tự track.

_PRED_LABEL_TOTAL = Counter(
    "skin_prediction_label_total",
    "Total predictions grouped by outcome label (Malignant / Benign)",
    ["model", "label"],
)

_PRED_PROBABILITY = Histogram(
    "skin_prediction_probability",
    "Distribution of raw probability scores from the model",
    ["model", "label"],
    buckets=[0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
)

_GRADCAM_TOTAL = Counter(
    "skin_prediction_gradcam_total",
    "Grad-CAM generation outcomes (success / skipped / failed)",
    ["model", "status"],
)
# ─────────────────────────────────────────────────────────────────────────────

# Constants – same as data_preprocessing.py in mlops-model
TARGET_SIZE    = (224, 224)
CLAHE_CLIP     = 2.0
GAUSS_KERNEL   = (3, 3)
CATEGORICAL_COLS = ["sex", "anatom_site_general"]

# XAI – Grad-CAM (from mlops-model/Multimodal/utils/xai.py)
CONV_LAST  = os.environ.get("GRADCAM_LAYER", "top_conv")  # last conv layer of EfficientNetB3
ENABLE_XAI = os.environ.get("ENABLE_XAI", "true").lower() == "true"

# Font for XAI overlay text (Vietnamese diacritics support)
_FONT_PATH = os.path.join(os.path.dirname(__file__), "DejaVuSans-Bold.ttf")
try:
    _FONT_LABEL = ImageFont.truetype(_FONT_PATH, 14)
    _FONT_CONF  = ImageFont.truetype(_FONT_PATH, 12)
except (OSError, IOError):
    logger.warning("DejaVuSans-Bold.ttf not found, falling back to default font")
    _FONT_LABEL = ImageFont.load_default()
    _FONT_CONF  = ImageFont.load_default()


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
        self.model      = None
        self.grad_model  = None   # Grad-CAM sub-model (built once after load)
        self.preproc    = None
        self.threshold  = float(os.environ.get("THRESHOLD", "0.5"))
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

        # Build Grad-CAM sub-model once (avoids rebuilding on every predict)
        if ENABLE_XAI:
            try:
                self.grad_model = keras.Model(
                    inputs=self.model.inputs,
                    outputs=[self.model.get_layer(CONV_LAST).output, self.model.output],
                )
                logger.info("[load] Grad-CAM sub-model built (layer=%s)", CONV_LAST)
            except Exception as e:
                logger.warning("[load] Grad-CAM init failed: %s", e)
                self.grad_model = None

        n_features = len(self.preproc.get("feature_cols", []))
        logger.info(
            "[load] Ready. features=%d  threshold=%.4f  xai=%s",
            n_features, self.threshold, ENABLE_XAI and self.grad_model is not None,
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

    # ── Grad-CAM helpers (adapted from mlops-model/Multimodal/utils/xai.py) ──

    def _compute_gradcam(self, img_tensor, tab_tensor):
        """
        Compute Grad-CAM heatmap on the last conv layer.
        img_tensor: shape (1, 224, 224, 3)  float32
        tab_tensor: shape (1, N)            float32
        Returns: cam np.ndarray (H_conv, W_conv) in [0, 1]
        """
        with tf.GradientTape() as tape:
            conv_out, pred = self.grad_model({
                "image_input":   tf.constant(img_tensor),
                "tabular_input": tf.constant(tab_tensor),
            })
            loss = pred[:, 0]
        grads   = tape.gradient(loss, conv_out)[0]      # (H, W, C)
        weights = tf.reduce_mean(grads, axis=(0, 1))     # (C,)
        cam     = tf.reduce_sum(conv_out[0] * weights, axis=-1)  # (H, W)
        cam     = tf.nn.relu(cam).numpy()
        cam     = (cam - cam.min()) / (cam.max() - cam.min() + 1e-8)
        return cam

    def _gradcam_to_base64(self, cam, img_float, label="", probability=0.0):
        """
        Overlay Grad-CAM heatmap on the preprocessed image with bounding box
        around the highest-activation region and text annotation → base64 PNG.
        cam:         (H_conv, W_conv) float in [0, 1]
        img_float:   (224, 224, 3)    float in [0, 1]
        label:       prediction label string
        probability: prediction confidence (0-1)
        Returns: base64-encoded PNG string
        """
        orig = (img_float * 255).astype(np.uint8)  # (224, 224, 3) uint8

        # Resize cam to image dimensions
        cam_resized = cv2.resize(
            (cam * 255).astype(np.uint8),
            (orig.shape[1], orig.shape[0]),
            interpolation=cv2.INTER_LINEAR,
        )

        # ── Bounding box around highest activation region ──
        # Threshold at top 20% activation to find the "hot zone"
        threshold = int(0.8 * 255)
        _, binary = cv2.threshold(cam_resized, threshold, 255, cv2.THRESH_BINARY)
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # Work directly on original RGB image for drawing
        canvas = orig.copy()

        if contours:
            # Merge all contour points to find one bounding rect
            all_pts = np.concatenate(contours)
            x, y, w, h = cv2.boundingRect(all_pts)
            # Pad slightly for visibility
            pad = 4
            x, y = max(0, x - pad), max(0, y - pad)
            w, h = min(canvas.shape[1] - x, w + 2 * pad), min(canvas.shape[0] - y, h + 2 * pad)
            cv2.rectangle(canvas, (x, y), (x + w, y + h), (255, 140, 0), 2)  # orange box (RGB)

        # ── Text annotation (PIL for Vietnamese Unicode support) ──
        # Convert canvas RGB → PIL Image for text drawing
        pil_img = Image.fromarray(canvas)
        draw = ImageDraw.Draw(pil_img)

        label_vi = "Ác tính" if label == "Malignant" else "Lành tính"
        text_label = f"{label} ({label_vi})"
        text_conf  = f"Độ tin cậy: {probability * 100:.2f}%"

        color_label = (255, 60, 60) if label == "Malignant" else (60, 200, 60)  # RGB
        color_conf  = (255, 255, 255)

        # Measure text bounding boxes
        bbox1 = draw.textbbox((0, 0), text_label, font=_FONT_LABEL)
        tw1, th1 = bbox1[2] - bbox1[0], bbox1[3] - bbox1[1]
        bbox2 = draw.textbbox((0, 0), text_conf, font=_FONT_CONF)
        tw2, th2 = bbox2[2] - bbox2[0], bbox2[3] - bbox2[1]

        img_w = pil_img.width
        pad_x, pad_y = 6, 3

        # Line 1: label (centered, top)
        x1 = (img_w - tw1) // 2
        y1 = 6
        draw.rectangle([x1 - pad_x, y1 - pad_y, x1 + tw1 + pad_x, y1 + th1 + pad_y],
                       fill=(0, 0, 0, 200))
        draw.text((x1, y1), text_label, font=_FONT_LABEL, fill=color_label)

        # Line 2: confidence (centered, below label)
        x2 = (img_w - tw2) // 2
        y2 = y1 + th1 + pad_y * 2 + 4
        draw.rectangle([x2 - pad_x, y2 - pad_y, x2 + tw2 + pad_x, y2 + th2 + pad_y],
                       fill=(0, 0, 0, 200))
        draw.text((x2, y2), text_conf, font=_FONT_CONF, fill=color_conf)

        # Convert PIL back to numpy for final encoding
        result_rgb = np.array(pil_img)

        # Encode to base64 PNG
        img_pil = Image.fromarray(result_rgb)
        buf = io.BytesIO()
        img_pil.save(buf, format="PNG", optimize=True)
        buf.seek(0)
        return base64.b64encode(buf.read()).decode("utf-8")

    # ── Predict ───────────────────────────────────────────────────────────

    def predict(self, data: dict, headers=None):
        # Binary prediction: Benign (0) / Malignant (1).
        t0 = time.perf_counter()

        inputs = {"image_input": data["image"], "tabular_input": data["tabular"]}
        prob   = float(self.model.predict(inputs, verbose=0)[0, 0])

        pred_class = int(prob >= self.threshold)
        label      = "Malignant" if pred_class == 1 else "Benign"

        # Grad-CAM (optional, controlled by ENABLE_XAI env)
        gradcam_b64 = None
        gradcam_status = "skipped"
        if self.grad_model is not None:
            try:
                cam = self._compute_gradcam(data["image"], data["tabular"])
                gradcam_b64 = self._gradcam_to_base64(cam, data["image"][0], label, prob)
                gradcam_status = "success"
            except Exception as e:
                logger.warning("[predict] Grad-CAM failed: %s", e)
                gradcam_status = "failed"

        elapsed_ms = (time.perf_counter() - t0) * 1000

        logger.info(
            "[predict] %s  prob=%.4f  threshold=%.2f  xai=%s  ms=%.1f",
            label, prob, self.threshold, gradcam_b64 is not None, elapsed_ms,
        )

        # ── Record custom Prometheus metrics ──────────────────────────────────
        _PRED_LABEL_TOTAL.labels(model=self.name, label=label).inc()
        _PRED_PROBABILITY.labels(model=self.name, label=label).observe(prob)
        _GRADCAM_TOTAL.labels(model=self.name, status=gradcam_status).inc()
        # ─────────────────────────────────────────────────────────────────────

        result = {
            "label":       label,
            "probability": round(prob, 4),
            "inference_ms": round(elapsed_ms, 1),
        }
        if gradcam_b64:
            result["gradcam_base64"] = gradcam_b64

        return {"predictions": [result]}


if __name__ == "__main__":
  # The name of the model must be fit to metadata.name in inference-service.yaml
    ModelServer().start([SkinPredictionModel("skin-prediction")])
