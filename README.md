# THIẾT KẾ VÀ TRIỂN KHAI KIẾN TRÚC MLOPS CHO HỆ THỐNG HỌC SÂU ĐA PHƯƠNG THỨC TRONG HỖ TRỢ CHẨN ĐOÁN UNG THƯ DA

- Tên tiếng Anh: Design and implementation of an MLOps architecture for a multimodal deep learning system to support skin cancer diagnosis

- Giảng viên hướng dẫn: ThS. Nguyễn Khánh Thuật (thuatnk@uit.edu.vn)

- Thành viên thực hiện:
  - Đinh Huỳnh Gia Bảo (22520101@gm.uit.edu.vn)
  - Trần Gia Bảo (22520117@gm.uit.edu.vn)

## TỔNG QUAN ĐỀ TÀI

- Trong những năm gần đây, trí tuệ nhân tạo (Artificial Intelligence - AI) và học sâu, đặc biệt là các mô hình đa phương thức, đang phát triển một cách mạnh mẽ trong lĩnh vực chăm sóc sức khỏe.

- Chúng được ứng dụng rộng rãi để hỗ trợ các công tác trong chẩn đoán bệnh như khai thác dữ liệu, trích xuất dữ liệu về hình ảnh y tế, hồ sơ và kết quả xét nghiệm, điều này giúp tăng độ chính xác và cung cấp cho bác sĩ thêm nguồn lực trong quá trình ra quyết định.

- Bên cạnh đó, các phương pháp vận hành học máy (Machine Learning Operations - MLOps) cũng được quan tâm sâu sắc nhằm tự động hóa quá trình huấn luyện, triển khai và giám sát mô hình, giúp rút ngắn khoảng cách giữa nghiên cứu và ứng dụng thực tế.

- Tuy nhiên, dữ liệu y tế thường đến từ nhiều nguồn, có sự khác biệt về định dạng và liên tục thay đổi, gây khó khăn trong việc tích hợp và duy trì hiệu năng mô hình. Ngoài ra, nhiều hệ thống học sâu hiện nay vẫn thiếu quy trình triển khai, giám sát và tái huấn luyện tự động, đồng thời phải đáp ứng các yêu cầu nghiêm ngặt về truy vết, khả năng tái lập và tuân thủ quy định trong môi trường y tế.

## GIẢI PHÁP ĐỀ XUẤT

- Sau khi nghiên cứu vấn đề, chúng tôi đã xây dựng đề tài bằng cách đề xuất phát triển khung MLOps cho hệ thống học sâu đa phương thức, được sử dụng trong chẩn đoán ung thư.

- Toàn bộ quy trình học máy về cơ bản được coi là một ứng dụng phần mềm, và nó có thể được quản lý phiên bản, kiểm thử và triển khai tự động. Ngoài ra, hệ thống được thiết kế với quy trình huấn luyện hoàn toàn tự động, kết hợp cùng model registry để quản lý và theo dõi các phiên bản mô hình, hệ
  thống giám sát hiệu năng trong môi trường vận hành và cơ chế GitOps để triển khai trên hạ tầng đám mây hoặc nền tảng điều phối container.

- Cách tiếp cận này giúp tối đa hóa mức độ tự động hóa, đồng thời đảm bảo toàn bộ vòng đời mô hình luôn có thể được truy vết, tái lập và mở rộng một cách ổn định.

![Hệ thống đề xuất](/docs/diagram/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning-4-ml-automation-ci-cd.png)

## MỤC TIÊU ĐỀ TÀI

### Mục tiêu tổng quát

- Mục tiêu của đề tài là xây dựng một kiến trúc MLOps cho các mô hình học sâu đa phương thức, nhằm hỗ trợ quản lý và tự động hóa vòng đời của mô hình một cách hiệu quả. Hệ thống được định hướng theo nền tảng hiện đại trên nền tảng điện toán đám mây, bảo đảm khả năng mở rộng, tính ổn định và vận hành bền vững.

### Mục tiêu cụ thể

- **Thu thập và chuẩn hóa bộ dữ liệu đa nguồn:** Xây dựng quy trình thu thập, tiền xử lý và chuẩn hóa dữ liệu từ nhiều nguồn dữ liệu khác nhau (ảnh, văn bản, v.v.). Đảm bảo dữ liệu được lưu trữ có cấu trúc, có gắn nhãn, kiểm soát chất lượng và dễ dàng truy xuất phục vụ cho quá trình huấn luyện và đánh giá mô hình.

- **Xây dựng và tự động hóa quy trình huấn luyện mô hình:** Thiết kế pipeline MLOps cho quá trình huấn luyện, đánh giá và triển khai mô hình học sâu đa phương thức. Tích hợp các công cụ tự động hóa giúp giảm thao tác thủ công, đảm bảo khả năng tái lập thí nghiệm và rút ngắn thời gian phát triển mô hình.

- **Thiết lập cơ chế giám sát và tái huấn luyện:** Xây dựng hệ thống theo dõi hiệu suất mô hình sau khi triển khai, phát hiện suy giảm chất lượng (model drift, data drift) và kích hoạt quy trình tái huấn luyện khi cần thiết. Đảm bảo hệ thống hoạt động ổn định và duy trì hiệu suất theo thời gian.

- **Đánh giá và kiểm chứng kết quả mô hình:** Xây dựng quy trình đánh giá mô hình dựa trên các chỉ số phù hợp với bài toán, thực hiện kiểm thử trên các tập dữ liệu độc lập và so sánh với các phương pháp hiện có. Đảm bảo kết quả mô hình có tính tin cậy, ổn định và đáp ứng yêu cầu ứng dụng thực tế.

## PHƯƠNG PHÁP THỰC HIỆN

### Nghiên cứu, phát triển mô hình học sâu đa phương thức

> [!NOTE]
> Phần này định nghĩa các chiến lược xử lý dữ liệu và thiết kế kiến trúc mô hình đa phương thức. Với đặc thù của dữ liệu y khoa, việc tránh rò rỉ dữ liệu (data leakage) và giải quyết mất cân bằng lớp là yếu tố sống còn

#### Thu nhập dữ liệu và tiền xử lý (Data Strategy)

| STT | THUỘC TÍNH            | NỘI DUNG CHÍNH                                                              |
| :-- | :-------------------- | :-------------------------------------------------------------------------- |
| 1   | Tên đầy đủ            | SLICE-3D – Skin Lesion Image Crops Extracted from 3D Total Body Photography |
| 2   | Tổ chức               | International Skin Imaging Collaboration (ISIC)                             |
| 3   | Nền tảng              | Kaggle – ISIC 2024 Grand Challenge                                          |
| 4   | Tổng số mẫu           | 401.059 ảnh tổn thương da                                                   |
| 5   | Kích thước ảnh        | ~128 × 128 pixel, định dạng JPEG                                            |
| 6   | Số đặc trưng metadata | 55 cột trong file train-metadata.csv                                        |
| 7   | Thời gian thu thập    | 2015 – 2024 (10 năm)                                                        |
| 8   | Công bố khoa học      | Scientific Data, Nature Publishing Group, 2024                              |
| 9   | Số cơ sở y tế         | 9 bệnh viện / trường đại học tại Mỹ, Úc, Tây Ban Nha, Áo, Hy Lạp, Thụy Sĩ   |

- Công nghệ chụp toàn thân 3D (3D Total Body Photography - 3D-TBP) sử dụng hệ thống thiết bị Vectra WB360 (của hãng Canfield Scientific).
  - Thực hiện chụp tổng hợp _92 ảnh_ từ _46 cặp camera_ lập thể.
  - Áp dụng thuật toán tái dựng bản đồ lưới (mesh) bề mặt da 3D toàn thân, sau đó tự động phát hiện và trích xuất các tổn thương thành từng mảnh ảnh (tile) kích thước _15mm×15mm_

- **Tiền xử lý và Feature Store:** Hình ảnh được chuẩn hóa, thay đổi kích thước (resize về 224×224 hoặc 128×128) và tăng cường (augmentation). Dữ liệu dạng bảng được điền khuyết, mã hóa và chuẩn hóa bằng `StandardScaler`. Mọi đặc trưng được quản lý tập trung qua Feature Store nhằm đảm bảo tính nhất quán tuyệt đối giữa môi trường huấn luyện và môi trường thực tế.

- **Chống rò rỉ dữ liệu (Data Leakage)**: Việc phân chia tập train/val/test được thực hiện nghiêm ngặt theo từng cấp độ bệnh nhân (patient-level)

#### Kiến trúc mô hình đa phương thức (Multimodal)

| STT | THUỘC TÍNH           | LỰA CHỌN ĐỀ XUẤT                        | LÝ DO                                                                                                 |
| :-- | :------------------- | :-------------------------------------- | :---------------------------------------------------------------------------------------------------- |
| 1   | Nhánh xử lý ảnh      | EfficientNet-B3 (ImageNet pretrained)   | Accuracy ~97% ISIC 2024, nhẹ, dễ tích hợp Grad-CAM/XRAI                                               |
| 2   | Nhánh xử lý file CSV | MLP (Multi-Layer Perceptron)            | Late fusion đơn giản, dễ debug, SHAP explain được                                                     |
| 3   | Fusion Layer         | Concatenation -> FC -> Dropout (0.3)    | Late fusion hiệu quả, ít risk overfitting                                                             |
| 4   | Loss Function        | Focal Loss + Class weights              | Xử lý mất cân bằng dữ liệu (tỷ lệ melanoma chiếm 11%) và tập trung tối ưu các mẫu khó (hard examples) |
| 5   | XAI Layer            | XRAI (region-based) + SHAP cho metadata | XRAI tốt hơn Grad-CAM cho medical imaging                                                             |

#### Khả năng giải thích (XAI)

> [!NOTE]
> Trong hệ thống MLOps này, khả năng giải thích được mô hình (Explainability) là yếu tố sống còn để hỗ trợ các bác sĩ trong việc đưa ra quyết định lâm sàng. Chúng tôi đề xuất sử dụng kết hợp hai phương pháp XRAI cho dữ liệu hình ảnh và SHAP cho dữ liệu metadata.

- **XRAI (eXplanation with Ranked Area Insertions):** XRAI cung cấp khả năng giải thích trực quan dựa trên vùng tổn thương, thay vì chỉ tập trung vào từng pixel đơn lẻ.
  - **Cơ chế hoạt động**: Tạo ra các region-based attributions (đóng góp theo vùng), khắc phục nhược điểm của các phương pháp pixel-level truyền thống như Grad-CAM (thường bị nhiễu và khó đọc đối với chuyên gia y tế).
  - **Sự kết hợp hoàn hảo**: Sử dụng EfficientNet-B3 + XRAI để đạt kết quả giải thích mạch lạc, trực quan và dễ hiểu hơn cho bác sĩ.
  - **Kỹ thuật Superpixels**: XRAI chia hình ảnh thành các superpixels (siêu điểm ảnh) và xếp hạng chúng theo mức độ quan trọng. Phương pháp này đặc biệt phù hợp với các loại ảnh nội soi da (dermoscopic images) vì nó khoanh vùng được chính xác các vùng mô bệnh lý.

- **SHAP (SHapley Additive exPlanations):** SHAP được tích hợp để giải thích tầm ảnh hưởng của các yếu tố phi hình ảnh (metadata) lên kết quả dự đoán cuối cùng.
  - **Vai trò chính**: Dùng SHAP để định lượng mức đóng góp (contribution) của từng thuộc tính metadata (như tuổi, vị trí tổn thương, giới tính...) vào xác suất dự đoán ung thư.

#### Chỉ số đánh giá

- Đánh giá hiệu suất trên tập test sử dụng các metrics: Accuracy, Precision, Recall, F1-score (macro và weighted), AUC-ROC cho từng class, và Confusion Matrix để phân tích chi tiết.

### Xây dựng hạ tầng triển khai mô hình học sâu đa phương thức

> [!NOTE]
> Hệ thống Ops được xây dựng dựa trên nền tảng Cloud-native, tự động hóa từ khâu tích hợp mã nguồn, huấn luyện đến giám sát và phân phối mô hình.

- **Infrastructure as Code (IaC):** Toàn bộ hạ tầng bao gồm cụm Kubernetes (AWS EKS), Object Storage (S3), và Container Registry (AWS ECR) được định nghĩa và triển khai bằng mã qua Terraform.

- **CI/CD Pipeline cho mô hình học sâu đa phương thức**: Xây dựng một pipeline tự động hóa toàn bộ quy trình từ thu thập dữ liệu đến triển khai mô hình. Sử dụng các công cụ như `GitHub Actions` để quản lý phiên bản và tự động hóa CI/CD, và `MLflow` để điều phối luồng công việc và quản lý vòng đời mô hình. Mỗi lần commit mã nguồn sẽ kích hoạt quy trình kiểm thử tự động (bao gồm unit test và integration test), huấn luyện mô hình trên một tập dữ liệu con (subset) để kiểm chứng tính đúng đắn của mã nguồn, và thực hiện đánh giá mô hình tự động (automated model evaluation).

- **Chỉ só đánh giá CI/CD pipeline**: pipeline execution time (thời gian từ commit đến khi hoàn tất pipeline), pipeline success rate (tỷ lệ pipeline chạy thành công), automated test pass rate (tỷ lệ các bài kiểm thử vượt qua) và model performance stability (mức độ ổn định của các chỉ số như accuracy hoặc F1-score giữa các lần huấn luyện).

#### Triển khai hạ tầng MLOps

> [!NOTE]
> Giai đoạn này nhằm xây dựng nền tảng hạ tầng cloud-native làm cơ sở cho toàn bộ hệ thống MLOps, đảm bảo các đặc tính về khả năng mở rộng, tính sẵn sàng cao, tự động hoá và khả năng tái lập môi trường. Cụ thể, các mục tiêu chính bao gồm:

- **Triển khai cụm Kubernetes:** Sử dụng dịch vụ **Amazon EKS** (Elastic Kubernetes Service) làm nền tảng điều phối container để quản lý các dịch vụ và pipeline.
- **Áp dụng Terraform:** Định nghĩa và triển khai hạ tầng dưới dạng mã (**Infrastructure as Code - IaC**) để đảm bảo tính tự động hóa và đồng bộ.
- **Triển khai Object Storage:** Sử dụng các dịch vụ lưu trữ (như Amazon S3) để lưu trữ dữ liệu, model artifacts và logs.
- **Thiết lập Container Registry:** Sử dụng **Amazon ECR** để quản lý và lưu trữ các Docker images.
- **Triển khai MLflow Tracking Server:** Quản lý vòng đời mô hình, theo dõi các thí nghiệm (experiments) và thông số huấn luyện.
- **Thiết lập Git repository:** Sử dụng làm nguồn quản lý mã nguồn tập trung (Source Control Management).
- **Cấu hình CI pipeline:** Sử dụng **GitHub Actions** để tự động hóa quy trình tích hợp liên tục.
- **Triển khai ArgoCD:** Quản lý việc triển khai ứng dụng lên Kubernetes theo mô hình **GitOps**, đảm bảo trạng thái của cluster luôn đồng nhất với cấu hình trong Git.

#### Xây dựng CI/CD pipeline

> [!NOTE]
> Giai đoạn này nhằm xây dựng quy trình xử lý dữ liệu và phát triển mô hình học máy theo hướng có thể tái lập, theo dõi và tự động hoá. Cụ thể, mục tiêu bao gồm:

- **Xây dựng quy trình CI/CD:** Kết hợp kiến trúc pipeline tự động với mô hình **GitOps** để tối ưu hóa việc triển khai.
- **Quản lý mã nguồn tập trung:** Toàn bộ mã nguồn của pipeline, cấu hình hạ tầng (IaC) và các thành phần triển khai được lưu trữ và quản lý trên **GitHub**.
- **Tự động kích hoạt quy trình CI:** Hệ thống tự động kích hoạt CI (Continuous Integration) ngay khi có thay đổi mã nguồn, thực hiện kiểm thử (Unit Test), build Docker image và đóng gói các thành phần phục vụ huấn luyện/triển khai mô hình.
- **Quản lý Docker Image:** Đẩy các Docker image sau khi build thành công lên **Container Registry** (như Amazon ECR) để sẵn sàng phục vụ cho các môi trường triển khai khác nhau.
- **Triển khai CD theo mô hình GitOps:** Trạng thái mong muốn (desired state) của hệ thống được định nghĩa bằng các tập tin **K8s manifest** hoặc **Helm chart** lưu trữ trong repository.
- **Tự động đồng bộ hóa:** Hệ thống tự động đồng bộ cấu hình từ repository vào cụm **Kubernetes** để triển khai mới hoặc cập nhật pipeline và các dịch vụ model serving mà không cần can thiệp thủ công.

#### Giám sát và ghi nhận kết quả

> [!NOTE]
> Giai đoạn này nhằm thiết lập cơ chế giám sát toàn diện cho hệ thống MLOps và đánh giá hiệu quả của mô hình trong môi trường thực tế. Mục tiêu chính bao gồm: Theo dõi trạng thái hoạt động của hệ thống và dịch vụ mô hình.

- **Triển khai hệ thống giám sát hai lớp:** Thiết lập cơ chế giám sát toàn diện bao gồm cả giám sát hạ tầng (Infrastructure Monitoring) và giám sát mô hình (Model Monitoring).
- **Trực quan hóa chỉ số hạ tầng:** Thu thập và theo dõi các thông số kỹ thuật thời thực như CPU, bộ nhớ (RAM), độ trễ (latency) và số lượng yêu cầu (request) của dịch vụ suy luận.
- **Giám sát dữ liệu và mô hình:** Kiểm soát dữ liệu đầu vào và đầu ra của mô hình nhằm phát hiện kịp thời các hiện tượng như **Data Drift** (sự thay đổi phân phối dữ liệu theo thời gian).
- **Kích hoạt tái huấn luyện tự động:** Hệ thống tự động kích hoạt lại pipeline huấn luyện (re-training) khi phát hiện các dấu hiệu suy giảm chất lượng hoặc hiệu suất của mô hình.

![Hệ thống triển khai](/docs/diagram/sketching%20system.png)

## CẤU TRÚC THƯ MỤC

```text
mlops-infr/
├── .git/                                         # Metadata của Git, phục vụ quản lý phiên bản
├── .github/                                      # Cấu hình CI/CD và script tự động hóa trên GitHub
│   ├── scripts/                                  # Script hỗ trợ cho workflow
│   │   ├── bash/                                 # Shell script bootstrap hạ tầng và add-ons
│   │   │   ├── phase1-start-ssm-agent.sh         # Khởi tạo SSM Agent để quản trị từ xa
│   │   │   ├── phase2-install-addons.sh          # Cài add-ons cần thiết cho cluster
│   │   │   ├── phase3-argocd-bootstrap.sh        # Bootstrap ArgoCD sau khi cluster sẵn sàng
│   │   │   └── ssm-run.sh                        # Wrapper chạy lệnh qua AWS SSM
│   │   ├── notify-failure.js                     # Xử lý/gửi thông báo khi pipeline thất bại
│   │   └── post-plan-comment.js                  # Đăng kết quả Terraform plan vào PR/comment
│   └── workflows/                                # Các workflow GitHub Actions
│       ├── argocd-bootstrap.yml                  # Workflow bootstrap ArgoCD
│       ├── helm-bootstrap.yml                    # Workflow cài đặt thành phần bằng Helm
│       ├── terraform-apply.yml                   # Workflow apply hạ tầng Terraform
│       ├── terraform-ci.yml                      # Workflow kiểm tra/validate/plan Terraform
│       └── terraform-destroy.yml                 # Workflow hủy tài nguyên hạ tầng
├── asset/                                        # Tài nguyên tĩnh dùng trong README/tài liệu
│   ├── image/                                    # Ảnh minh họa, flow, screenshot
│   │   ├── argocd_portforward_flow.svg           # Sơ đồ truy cập ArgoCD qua port-forward
│   │   ├── mlflow_architecture_flow.svg          # Sơ đồ kiến trúc MLflow
│   │   ├── terraform-apply.png                   # Ảnh minh họa quá trình Terraform apply
│   │   └── terraform-destroy.png                 # Ảnh minh họa quá trình Terraform destroy
│   └── link/
│       └── working-resource.md                   # Danh sách link tham khảo/tài nguyên làm việc
├── docs/                                         # Tài liệu thiết kế, triển khai và ghi chú vận hành
│   ├── diagram/                                  # Các sơ đồ kiến trúc/hạ tầng
│   │   ├── EKS-Infrastructure.drawio.png         # Sơ đồ hạ tầng EKS
│   │   ├── helm-bootstrap.drawio.png             # Sơ đồ luồng bootstrap Helm
│   │   ├── infra-management-workflow.drawio.png  # Sơ đồ quản lý hạ tầng
│   │   ├── Kubernetes-trafic.drawio.png          # Sơ đồ lưu lượng trong Kubernetes
│   │   ├── mlops-continuous-delivery-and-automation-pipelines-in-machine-learning-4-ml-automation-ci-cd.png
│   │   │                                         # Hình tham chiếu về pipeline MLOps
│   │   ├── port-forward.drawio.png               # Sơ đồ truy cập dịch vụ bằng port-forward
│   │   ├── sketching system.png                  # Phác thảo kiến trúc hệ thống tổng thể
│   │   └── SSM-Bastion_host.drawio.png           # Sơ đồ bastion host và SSM
│   ├── error/
│   │   └── mlflow-deployment.md                  # Ghi chú lỗi/sự cố khi triển khai MLflow
│   ├── plan/                                     # Tài liệu kế hoạch và hướng dẫn triển khai
│   │   ├── pdf/
│   │   │   └── Using a Network Load Balancer with the NGINX Ingress Controller on Amazon EKS.pdf
│   │   │                                         # Tài liệu tham khảo ngoài về NLB + NGINX
│   │   ├── argocd-port-forward.md                # Hướng dẫn truy cập ArgoCD nội bộ
│   │   ├── cloudflare-tunnel-eks.md              # Kế hoạch dùng Cloudflare Tunnel với EKS
│   │   ├── eks_infrastructure.md                 # Mô tả chi tiết hạ tầng EKS
│   │   ├── git_workflow.md                       # Quy ước làm việc với Git
│   │   ├── mlflow-port-forward.md                # Hướng dẫn port-forward cho MLflow
│   │   ├── mlflow-techstack.md                   # Tài liệu tech stack của MLflow
│   │   ├── monitoring-port-forward.md            # Hướng dẫn truy cập stack monitoring
│   │   └── nlb_eks.md                            # Ghi chú cấu hình Network Load Balancer
│   └── repo-structure.md                         # Tài liệu mô tả cấu trúc thư mục (file này)
├── environments/                                 # Điểm vào Terraform theo từng môi trường triển khai
│   ├── DEV.md                                    # Tài liệu mô tả môi trường DEV
│   └── dev/                                      # Cấu hình Terraform cho môi trường phát triển
│       ├── .terraform/                           # Cache/provider/module cục bộ do Terraform sinh ra
│       ├── .terraform.lock.hcl                   # File khóa version provider Terraform
│       ├── backend.tf                            # Cấu hình backend lưu state từ xa
│       ├── main.tf                               # Ghép các module hạ tầng chính
│       ├── outputs.tf                            # Output sau khi apply
│       ├── provider.tf                           # Khai báo provider AWS/Kubernetes/Helm
│       ├── terraform.tfvars                      # Giá trị biến cho môi trường DEV
│       └── variables.tf                          # Danh sách biến đầu vào của môi trường
├── gitops/                                       # Cấu hình GitOps để ArgoCD đồng bộ lên cluster
│   ├── apps/                                     # Từng ArgoCD Application cho từng dịch vụ
│   │   ├── argocd.yaml                           # Khai báo ứng dụng ArgoCD
│   │   ├── cloudflare.yaml                       # Khai báo ứng dụng Cloudflare Tunnel
│   │   ├── grafana.yaml                          # Khai báo ứng dụng Grafana
│   │   ├── mlflow.yaml                           # Khai báo ứng dụng MLflow
│   │   └── prometheus.yaml                       # Khai báo ứng dụng Prometheus
│   ├── projects/
│   │   └── appproject.yaml                       # ArgoCD AppProject quản lý phạm vi deploy
│   └── app-of-apps.yaml                          # Root manifest theo mô hình app-of-apps
├── modules/                                      # Các module hạ tầng dùng lại được
│   ├── argocd/
│   │   └── values.yaml                           # Giá trị Helm để cài ArgoCD
│   ├── bastion-host/
│   │   ├── scripts/
│   │   │   └── user_data.sh                      # Script khởi tạo bastion khi EC2 boot
│   │   ├── main.tf                               # Tạo bastion host và tài nguyên liên quan
│   │   ├── outputs.tf                            # Output phục vụ kết nối/quản trị
│   │   └── variables.tf                          # Biến cấu hình bastion
│   ├── cloudflare/
│   │   └── cloudflare-values.yaml                # Giá trị triển khai Cloudflare Tunnel/ingress
│   ├── ecr/
│   │   ├── main.tf                               # Tạo registry chứa Docker image
│   │   ├── outputs.tf                            # Output của ECR
│   │   └── variables.tf                          # Biến cấu hình ECR
│   ├── eks/
│   │   ├── iam.tf                                # IAM policy/role cho EKS và node group
│   │   ├── main.tf                               # Tạo cluster EKS và node groups
│   │   ├── outputs.tf                            # Output cluster endpoint, kubeconfig info...
│   │   └── variables.tf                          # Biến cấu hình EKS
│   ├── ingress-nginx/
│   │   └── values.yaml                           # Giá trị Helm cho NGINX Ingress Controller
│   ├── load-balancer-controller/
│   │   ├── iam_policy.json                       # IAM policy cho AWS Load Balancer Controller
│   │   ├── main.tf                               # Tài nguyên triển khai controller
│   │   ├── outputs.tf                            # Output phục vụ tích hợp controller
│   │   └── variables.tf                          # Biến cấu hình controller
│   ├── mlflow/
│   │   ├── iam/                                  # Module con cấp quyền IAM/IRSA cho MLflow
│   │   │   ├── main.tf                           # Tạo IAM role/policy cho MLflow
│   │   │   ├── outputs.tf                        # Output IAM dùng cho tích hợp
│   │   │   └── variables.tf                      # Biến cấu hình IAM
│   │   ├── rds-postgresql/                       # Module con tạo database backend cho MLflow
│   │   │   ├── main.tf                           # Tạo RDS PostgreSQL
│   │   │   ├── outputs.tf                        # Output endpoint/thông tin DB
│   │   │   └── variables.tf                      # Biến cấu hình RDS
│   │   ├── s3/                                   # Module con tạo bucket chứa artifacts
│   │   │   ├── main.tf                           # Tạo S3 bucket cho MLflow artifacts
│   │   │   ├── outputs.tf                        # Output của bucket
│   │   │   └── variables.tf                      # Biến cấu hình S3
│   │   ├── main.tf                               # Ghép các thành phần MLflow lại thành một stack
│   │   ├── outputs.tf                            # Output tổng của module MLflow
│   │   ├── values.yaml                           # Helm values tĩnh cho MLflow
│   │   ├── values.yaml.tpl                       # Template values có biến động theo môi trường
│   │   └── variables.tf                          # Biến đầu vào của module MLflow
│   ├── monitoring/
│   │   ├── grafana/
│   │   │   └── grafana-values.yaml               # Helm values cho Grafana
│   │   └── prometheus/
│   │       └── prometheus-values.yaml            # Helm values cho Prometheus
│   ├── security_group/
│   │   ├── main.tf                               # Quản lý security group dùng chung
│   │   ├── outputs.tf                            # Output của security group
│   │   └── variables.tf                          # Biến cấu hình security group
│   └── vpc/
│       ├── main.tf                               # Tạo VPC, subnet, route, NAT/Internet Gateway
│       ├── outputs.tf                            # Output mạng dùng cho module khác
│       └── variables.tf                          # Biến cấu hình mạng
├── .gitignore                                    # Quy tắc bỏ qua file/thư mục không commit
├── log.txt                                       # File log/ghi chú cục bộ trong quá trình làm việc
├── new-bastion-key                               # SSH private key cho bastion host (nhạy cảm)
├── new-bastion-key.pub                           # SSH public key tương ứng
├── README.en.md                                  # Tài liệu giới thiệu dự án bằng tiếng Anh
└── README.md                                     # Tài liệu giới thiệu dự án bằng tiếng Việt
```

## GIỚI HẠN ĐỀ TÀI

- Mặc dù hệ thống MLOps được xây dựng nhằm đáp ứng các yêu cầu về tự động hóa và quản lý vòng đời mô hình, đề tài vẫn tồn tại một số hạn chế. Do giới hạn về thời gian và nguồn lực, dữ liệu và phạm vi thực nghiệm chưa đủ lớn để phản ánh toàn diện các tình huống thực tế.

- Tài nguyên tính toán còn hạn chế nên chưa thể thực hiện các thí nghiệm và tối ưu ở quy mô sâu và đa dạng. Ngoài ra, hệ thống mới được kiểm chứng ở mức thử nghiệm, chưa đánh giá đầy đủ trong môi trường vận hành thực tế với quy mô lớn và thời gian dài.

## TÀI LIỆU THAM KHẢO

- [1] G Mallardi, L Quaranta, et al. "MLOps in the Healthcare Domain: a Systematic Literature Review". In: Software Engineering and Advanced Applications. SEAA 2025. Vol. 16082. Lecture Notes in Computer Science. [Online; accessed 2025]. Cham: Springer, 2026. URL: https://link.springer.com/chapter/10.1007/978-3-032-04200-2%5C_23.

- [2] P. Rajpurkar, E. Chen, et al. "AI in health and medicine". In: Nature Medicine 28.1 (2022), pp. 31-38. ISSN: 1546-170X. DOI: https://doi.org/10.1038/s41591-021-01614-0.

- [3] Oracle. 10 Healthcare Challenges to Solve in 2026. [Online; accessed 2026]. 2026. URL: https://www.oracle.com/health/healthcare-challenges/.

- [4] K Mustafa M Shan. Driving Innovation in AI/ML Healthcare with Scalable AI Workflows MLOps and Cloud-Based Data Engineering. [Online; accessed 2025]. 2025. URL: https://www.researchgate.net/publication/390090254.

- [5] Mehdi Mahdavi. Skin Cancer (PAD-UFES-20). https://www.kaggle.com/datasets/mahdavi1202/skin-cancer. Accessed: 2026-03-05. 2022.

- [6] A Kumar Singh et al. "Using Multimodal Biometrics, Data Hiding, and Encryption for Secure Healthcare Imaging System". In: IET Image Processing (2024). [Online; accessed 2024]. URL: https://ieeexplore.ieee.org/document/10623370.

- [7] Google Cloud. MLOps: Continuous Delivery and Automation Pipelines in Machine Learning. [Online; accessed 2021]. 2021. URL: https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning.

- [8] Berkman Sahiner, Weijie Chen, et al. "Data Drift in Medical Machine Learning: Implications and Potential Remedies". In: The British Journal of Radiology 96.1150 (2023). [Online; accessed 2023], p. 20220878. URL: https://academic.oup.com/bjr/article/96/1150/7499000.
