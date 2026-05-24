# Hướng phát triển: Kiến trúc Model Serving tinh gọn bằng KServe (RawDeployment Mode)

> [!NOTE]
> KServe là một công cụ cực mạnh trong hệ sinh thái MLOps. Mặc định KServe sử dụng **Serverless Mode** (đòi hỏi Istio và Knative), nhưng điều này gây nặng nề và phức tạp không cần thiết cho Khóa luận.
> Do đó, kiến trúc này sử dụng **KServe RawDeployment Mode** — một tính năng giúp loại bỏ hoàn toàn Knative và Istio, chỉ sinh ra các tài nguyên Kubernetes tiêu chuẩn (Deployment, Service) nhưng vẫn giữ được bộ khung (SDK) chuẩn mực của KServe.

## 1. Tại sao lại chọn RawDeployment Mode?

- **Không Over-engineer**: Không phải cài đặt và maintain Service Mesh (Istio) hay Serverless framework (Knative) nặng nề.
- **Vẫn chuẩn MLOps**: Vẫn tận dụng được KServe SDK (`kserve.Model`) để code Custom Predictor một cách quy chuẩn. Mọi API endpoint vẫn tuân thủ đúng giao thức của KServe.
- **Nhẹ và an toàn**: Khi được deploy, KServe chỉ ngầm sinh ra một Kubernetes Deployment và một Service bình thường. Hoàn toàn nằm trong tầm kiểm soát của kiến thức Kubernetes nền tảng.

## 2. Kế hoạch triển khai KServe Custom Predictor

Để KServe xử lý được cả Ảnh và Tabular data (Mô hình Đa phương thức), ta định nghĩa một Custom Predictor. Predictor này sẽ tái hiện chính xác logic trong `predict_skin_lesion` trên Jupyter Notebook.

### Bước 1: Chuẩn bị Artifacts trên S3

Đảm bảo mô hình `model.h5` và file tiền xử lý `encoders.pkl` đã nằm sẵn trên S3 Bucket (do MLflow đẩy lên).

### Bước 2: Viết mã nguồn Predictor (`model.py`)

File này nhận JSON thô từ App, dùng `encoders.pkl` tiền xử lý Metadata, decode ảnh từ Base64, rồi đưa vào `model.h5`.

```python
import io
import base64
import joblib
import pandas as pd
import numpy as np
from PIL import Image
from tensorflow import keras
from kserve import Model, ModelServer

class SkinLesionModel(Model):
    def __init__(self, name: str):
        super().__init__(name)
        self.model = None
        self.encoders = None
        self.load()

    def load(self):
        # Mặc định KServe sẽ tự mount file từ S3 vào /mnt/models
        self.model = keras.models.load_model("/mnt/models/best_model_isic2024.h5")
        self.encoders = joblib.load("/mnt/models/encoders.pkl")
        self.ready = True

    def preprocess(self, payload: dict, headers=None):
        instance = payload["instances"][0]

        # 1. Decode ảnh từ Base64
        img_bytes = base64.b64decode(instance["image"])
        img = Image.open(io.BytesIO(img_bytes)).resize((224, 224))
        img_array = np.expand_dims(np.array(img) / 255.0, axis=0)

        # 2. Xử lý Dữ liệu thô bằng Encoders
        raw_dict = instance["tabular_raw"]
        raw_df = pd.DataFrame([raw_dict])
        meta = self.encoders.transform(raw_df)

        return {"image": img_array, "tabular": meta}

    def predict(self, data: dict, headers=None):
        prob = float(self.model.predict([data["image"], data["tabular"]])[0][0])
        label = "Malignant" if prob >= 0.5 else "Benign"
        return {
            "predictions": [{"label": label, "probability": prob}]
        }

if __name__ == "__main__":
    ModelServer().start([SkinLesionModel("skin-lesion")])
```

**`requirements.txt`**

```text
kserve
tensorflow
pillow
numpy
pandas
scikit-learn
joblib
```

### Bước 3: Triển khai qua KServe InferenceService (Raw Mode)

Sau khi Build Docker Image và đẩy lên ECR, ta khai báo `InferenceService`.
**Điểm mấu chốt**: Ta thêm Annotation `"serving.kserve.io/deploymentMode": "RawDeployment"` để báo cho KServe biết không được dùng Knative.

**`inference-service.yaml`**

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: skin-lesion
  namespace: kserve
  annotations:
    # Lệnh vô hiệu hóa Knative/Istio, sử dụng K8s Deployment tiêu chuẩn
    "serving.kserve.io/deploymentMode": "RawDeployment"
spec:
  predictor:
    containers:
      - name: kserve-container
        image: <account_id>.dkr.ecr.<region>.amazonaws.com/skin-lesion-predictor:v1
        env:
          - name: STORAGE_URI
            value: "s3://kltn-isic-2024-colab/preprocessed"
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
```

ArgoCD sẽ tự động apply file YAML này lên cluster. KServe sẽ đọc annotation và tự sinh ra 1 Deployment và 1 Service thay vì đi gọi Istio.

## 3. Demo Kiểm thử luồng Serving bằng Bruno

Với RawDeployment Mode, KServe sẽ mở port trực tiếp qua K8s Service thông thường.

### Payload JSON (Đa phương thức)

```json
{
  "instances": [
    {
      "image": "iVBORw0KGgoAAAANSUhEUgAA...<chuỗi_base64>...",
      "tabular_raw": {
        "age_approx": 45,
        "sex": "male",
        "anatom_site_general": "anterior torso",
        "clin_size_long_diam_mm": 5.0
      }
    }
  ]
}
```

### Lệnh Test (cURL)

_(Port-forward Service do KServe tạo ra: `kubectl port-forward svc/skin-lesion-predictor 8080:80 -n kserve`)_

```bash
curl -X POST http://localhost:8080/v1/models/skin-lesion:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [{
      "image": "iVBORw0KGgoAAAAN...",
      "tabular_raw": {
        "age_approx": 45,
        "sex": "male",
        "anatom_site_general": "anterior torso"
      }
    }]
  }'
```

### Kết quả

```json
{
  "predictions": [
    {
      "label": "Malignant",
      "probability": 0.637
    }
  ]
}
```

## 4. So sánh với các công cụ khác

| Tiêu chí                           | KServe RawDeployment          | Tự làm (Pod + Deployment + Service + Ingress) | FastAPI + Docker                 |
| ---------------------------------- | ----------------------------- | --------------------------------------------- | -------------------------------- |
| **Độ phức tạp setup**              | Trung bình                    | Trung bình                                    | Thấp nhất                        |
| **Cần Knative / Istio**            | ❌ Không                      | ❌ Không                                      | ❌ Không                         |
| **Cần Ingress Controller**         | ⚠️ Chỉ khi expose ra ngoài    | ⚠️ Chỉ khi expose ra ngoài                    | ⚠️ Chỉ khi expose ra ngoài       |
| **Test nội bộ (port-forward)**     | ✅ Được                       | ✅ Được                                       | ✅ Được                          |
| **Tách model khỏi Docker image**   | ✅ `storageUri` tự load từ S3 | ❌ Phải tự mount hoặc bake vào image          | ❌ Phải tự xử lý                 |
| **Update model mới**               | ✅ Patch 1 dòng YAML          | ❌ Rebuild image + redeploy                   | ❌ Rebuild image + redeploy      |
| **Cần Docker-in-Docker / Kaniko**  | ❌ Không                      | ✅ Nếu tự động hóa bằng pipeline              | ✅ Nếu tự động hóa bằng pipeline |
| **Autoscaling (HPA)**              | ✅ Tự động tạo                | ❌ Tự viết                                    | ❌ Tự viết                       |
| **Health check / Readiness probe** | ✅ Có sẵn                     | ❌ Tự viết                                    | ❌ Tự viết                       |
| **Chuẩn Inference API (V1/V2)**    | ✅ Có sẵn                     | ❌ Tự định nghĩa                              | ❌ Tự định nghĩa                 |
| **Tích hợp MLflow Registry**       | ✅ Tự nhiên qua `storageUri`  | ❌ Tự viết script                             | ❌ Tự viết script                |
| **Phù hợp EKS pipeline**           | ✅ Native                     | ⚠️ Được nhưng boilerplate nhiều               | ❌ Lạc lõng trong K8s            |
| **Phù hợp khóa luận MLOps**        | ✅ Chuẩn                      | ⚠️ Được nhưng tự reinvent                     | ⚠️ Chỉ phù hợp nếu có app/web    |
| **Thời gian implement**            | Ngắn                          | Dài                                           | Ngắn nhất                        |
| **Rủi ro khi demo**                | Thấp                          | Trung bình                                    | Thấp                             |
