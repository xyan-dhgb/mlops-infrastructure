# THIẾT KẾ VÀ TRIỂN KHAI KIẾN TRÚC MLOPS CHO HỆ THỐNG HỌC SÂU ĐA PHƯƠNG THỨC TRONG HỖ TRỢ CHẨN ĐOÁN UNG THƯ DA

- Tên tiếng Anh: Design and implementation of an MLOps architecture for a multimodal deep learning system to support skin cancer diagnosis
- Giảng viên hướng dẫn: ThS. Nguyễn Khánh Thuật (thuatnk@uit.edu.vn)
- Thành viên thực hiện:
    - Đinh Huỳnh Gia Bảo (22520101@gm.uit.edu.vn)
    - Trần Gia Bảo (22520117@gm.uit.edu.vn)
- [Bản báo cáo tiếng Anh ở đây](/README.en.md)

## MỤC LỤC

- [Tóm tắt](#tóm-tắt)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Tình hình bệnh ung thư da](#tình-hình-bệnh-ung-thư-da)
- [Cơ sở lý thuyết](#cơ-sở-lý-thuyết)
    - [Tổng quan về ung thư da](#tổng-quan-về-ung-thư-da)
    - [Bộ dữ liệu SLICE-3D](#bộ-dữ-liệu-slice-3d)
- [Tổng quan mô hình học sâu đa phương thức](#tổng-quan-mô-hình-học-sâu-đa-phương-thức)
- [Xây dựng hạ tầng MLOps](#xây-dựng-hạ-tầng-mlops)
    - [Xây dựng và quản hạ tầng dưới dạng mã nguồn](#xây-dựng-và-quản-hạ-tầng-dưới-dạng-mã-nguồn)
    - [Xây dựng hạ tầng EKS](#xây-dựng-hạ-tầng-eks)
    - [Tích hợp các ứng dụng nền tảng trên cụm EKS](#tích-hợp-các-ứng-dụng-nền-tảng-trên-cụm-eks)
        - [Xây dựng cơ chế Helm Bootstrap thông qua AWS Systems Manager](#xây-dựng-cơ-chế-helm-bootstrap-thông-qua-aws-systems-manager)
        - [Triển khai các thành phần nền tảng MLOps](#triển-khai-các-thành-phần-nền-tảng-mlops)
    - [Truy cập giao diện nội bộ của các ứng dụng trên cụm EKS](#truy-cập-giao-diện-nội-bộ-của-các-ứng-dụng-trên-cụm-eks)
    - [Kích hoạt điều phối GitOps trên cụm EKS](#kích-hoạt-điều-phối-gitops-trên-cụm-eks)
        - [Mô hình App-of-Apps và AppProject](#mô-hình-app-of-apps-và-appproject)
        - [Quy trình bootstrap tự động bằng GitHub Actions](#quy-trình-bootstrap-tự-động-bằng-github-actions)
    - [Tích hợp liên tục cho mã nguồn học sâu đa phương thức](#tích-hợp-liên-tục-cho-mã-nguồn-học-sâu-đa-phương-thức)
    - [Triển khai training pipeline trên Argo Workflows](#triển-khai-training-pipeline-trên-argo-workflows)
    - [Quản lý và theo dõi thí nghiệm huấn luyện](#quản-lý-và-theo-dõi-thí-nghiệm-huấn-luyện)
    - [Xây dựng dịch vụ suy luận mô hình bằng KServe Custom Predictor](#xây-dựng-dịch-vụ-suy-luận-mô-hình-bằng-kserve-custom-predictor)
    - [Xây dựng quy trình tích hợp và triển khai liên tục cho dịch vụ suy luận](#xây-dựng-quy-trình-tích-hợp-và-triển-khai-liên-tục-cho-dịch-vụ-suy-luận)
    - [Phát triển hệ thống giám sát và trực quan hóa dữ liệu](#phát-triển-hệ-thống-giám-sát-và-trực-quan-hóa-dữ-liệu)
- [Giới hạn đề tài](#giới-hạn-đề-tài)
- [Hạn chế](#hạn-chế)
- [Hướng phát triển](#hướng-phát-triển)
- [Tài liệu tham khảo](#tài-liệu-tham-khảo)

## TÓM TẮT

**Ung thư da** là một trong những bệnh lý về da phổ biến trên thế giới, được định nghĩa bởi sự phát triển một cách bất thường và mất kiểm soát của tế bào da, chủ yếu là do tiếp xúc với tia cực tím. Mặc dù có nhiều trường hợp có thể được điều trị hiệu quả nếu được phát hiện ở giai đoạn sớm, việc nhận biết và phân loại chính xác các tổn thương da vẫn là một thách thức trong y học do các đặc thù từ việc đánh giá đồng thời nhiều nguồn dữ liệu lâm sàng khác nhau và sự phụ thuộc vào kinh nghiệm chuyên môn của bác sĩ.

Trong những năm gần đây, sự phát triển của các **mô hình học sâu đa phương thức** đã phát huy tiềm năng khi hỗ trợ bác sĩ trong việc phân tích các nguồn dữ liệu đa dạng nhằm nâng cao độ chính xác trong việc chẩn đoán. Tuy nhiên, phần lớn các nghiên cứu hiện nay tập trung vào việc cải thiện hiệu năng mô hình mà chưa quan tâm đầy đủ đến các thách thức trong triển khai, vận hành và giám sát mô hình trong môi trường thực tế.

Sau khi tìm hiểu và nghiên cứu vấn đề, nhóm sinh viên đã tiến hành xây dựng một **hệ thống vận hành học máy - MLOps** cho mô hình học sâu đa phương thức nhằm hỗ trợ phát hiện ung thư da, cho phép tự động hóa toàn bộ vòng đời mô hình từ quản lý dữ liệu, huấn luyện, triển khai đến giám sát sau triển khai. Đồng thời, nhóm đã kết hợp **hai nguồn dữ liệu là hình ảnh da liễu và dữ liệu lâm sàng** nhằm nâng cao hiệu quả dự đoán.

Trong đề tài này sử dụng bộ dữ liệu **SLICE-3D** của tổ chức **ISIC** đến từ nền tảng Kaggle gồm các loại hình ảnh ảnh tổn thương da và các đặc trưng lâm sàng. Sau khi xử lý mất cân bằng dữ liệu, nhóm sinh viên tiến hành xây dựng mô hình học sâu đa phương thức kết hợp thông tin từ ảnh da liễu và dữ liệu lâm sàng. Nhánh ảnh sử dụng **EfficientNetB3** để trích xuất đặc trưng hình ảnh, trong khi nhánh dữ liệu bảng được xây dựng trên mạng **MLP**. Các đặc trưng từ hai nhánh được hợp nhất với nhau trước khi đưa vào bộ phân loại nhằm dự đoán tổn thương da thuộc nhóm **ác tính (Malignant)** hay **lành tính (Benign)**.

Kết quả thực nghiệm cho thấy mô hình đa phương thức đạt hiệu quả cao hơn trong việc cân bằng giữa khả năng phát hiện ung thư và tỷ lệ cảnh báo nhầm so với nhiều mô hình đơn phương thức. Ngoài ra, trên phương diện hạ tầng, kiến trúc MLOps được xây dựng giúp tự động hóa quy trình phát triển và triển khai mô hình, nâng cao khả năng tái lập, quản lý và mở rộng hệ thống.

## CẤU TRÚC THƯ MỤC

```text
.
├── .github/          # GitHub Actions workflows cho quy trình CI/CD hạ tầng và mô hình
├── asset/            # Chứa các tệp hình ảnh được sử dụng trong tài liệu
├── docs/             # Tài liệu thiết kế hệ thống, sơ đồ, hướng dẫn và kế hoạch
├── environments/     # Cấu hình Terraform (thông số, backend) cho các môi trường (dev)
├── gitops/           # Các manifest Kubernetes được quản lý bởi ArgoCD (App-of-Apps, Helm values)
├── modules/          # Các module Terraform độc lập để xây dựng hạ tầng AWS (VPC, EKS, MLflow, Argo, KServe...)
├── src/              # Mã nguồn phục vụ mô hình học máy (Serving, XAI, ...)
└── web/              # Mã nguồn giao diện web Frontend (React/Vite) phục vụ dự đoán
```

## TÌNH HÌNH BỆNH UNG THƯ DA

Ung thư da là một bệnh trong đó các tế bào da phát triển bất thường và ngoài tầm kiểm soát. Hầu hết các trường hợp ung thư da là do tiếp xúc quá nhiều với tia cực tím (UV) từ mặt trời, giường tắm nắng hoặc đèn chiếu tia cực tím [[1](https://www.cdc.gov/skin-cancer/about/index.html)]. Mặc dù trong nhiều trường hợp có thể được điều trị hiệu quả khi được phát hiện sớm, bệnh vẫn có nguy cơ xảy ra do các dấu hiệu ban đầu thường rất khó để nhận biết. Về mặt y học, ung thư da được chia thành hai nhóm chính: Ung thư hắc tố (Melanoma) và ung thư da không phải hắc tố (Non-melanoma) [[2](https://www.wcrf.org/preventing-cancer/cancer-types/skin-cancer/)].

Theo dữ liệu từ Cơ quan Nghiên cứu Ung thư Quốc tế (IARC) thuộc Tổ chức Y tế Thế giới (WHO) được phân tích chuyên sâu, ung thư da đang tạo ra một gánh nặng y tế lẫn tài chính khổng lồ trên phạm vi toàn cầu. Tính đến hết năm 2022, ung thư da không phải hắc tố là một trong những dạng ung thư phổ biến nhất thế giới với gánh nặng vượt ngưỡng **1,2 triệu ca** mắc mới được ghi nhận mỗi năm [[3](https://gco.iarc.who.int/media/globocan/factsheets/cancers/17-non-melanoma-skin-cancer-fact-sheet.pdf)]. Các nghiên cứu dịch tễ học được diễn ra ở quy mô lớn chỉ ra rằng xu hướng phân bố ca bệnh có sự phân hóa sâu sắc theo đặc điểm chủng tộc và khu vực địa lý [[4](https://acsjournals.onlinelibrary.wiley.com/doi/10.3322/caac.21834)]. Nhóm quần thể dân cư da trắng sinh sống tại các khu vực có cường độ bức xạ tia UV cao như **Châu Úc, Bắc Mỹ và Châu Âu** có nguy cơ tổn thương da cao nhất.

Tại Việt Nam, nhờ đặc trưng sở hữu làn da vàng có hàm lượng sắc tố melanin tự nhiên cao giúp phân tán bức xạ có hại, tỷ lệ mắc ung thư da thấp hơn đáng kể so với các quốc gia phương Tây [[5](https://tamanhhospital.vn/co-the-nguoi/melanin/)]. Tuy nhiên, có một sự thật đáng lo ngại là dù tỷ lệ mắc thấp, tỷ lệ tử vong và biến chứng nặng do ung thư da ở người Việt lại tương đối cao. Khác biệt cốt lõi nằm ở đặc điểm biểu hiện lâm sàng: trong khi người da trắng thường bị u da ở vùng hở tiếp xúc ánh nắng trực tiếp, ung thư hắc tố ở người Việt Nam và người châu Á nói chung lại chủ yếu khởi phát tại vùng đầu chi (như lòng bàn tay, lòng bàn chân, các gốc móng) [[6](https://dalieu.vn/ung-thu-da-hac-to-nhan-biet-som-nhu-the-nao-5537.html)] Do xuất hiện ở các vị trí kín đáo, dễ bị nhầm lẫn với nốt ruồi lành tính hoặc vết chai chân, phần lớn bệnh nhân tại Việt Nam chỉ đến khám khi bệnh đã tiến triển sang giai đoạn muộn. Số liệu được thống kê thực tế tại Bệnh viện Da liễu Thành phố Hồ Chí Minh cho thấy đơn vị này tiếp nhận gần 3.000 lượt bệnh nhân đến khám và điều trị ung thư da mỗi năm, trong đó nhóm đối tượng từ 60 tuổi trở lên chiếm tỷ lệ áp đảo trên 90% [[6](https://dalieu.vn/ung-thu-da-hac-to-nhan-biet-som-nhu-the-nao-5537.html)].

## CƠ SỞ LÝ THUYẾT

### Tổng quan về ung thư da

Về mặt lâm sàng và phân loại bệnh học, ung thư da được chia thành hai nhóm lớn dựa trên nguồn gốc tế bào: ung thư da không phải u hắc tố (NMSC) và u hắc tố (Melanoma). Hai nhóm này khác biệt đáng kể về mức độ nguy hiểm, tốc độ tiến triển và tiên lượng điều trị [[7](https://www.nature.com/articles/s41598-025-90485-3)].

- **Ung thư da không phải u hắc tố (NMSC)** là nhóm phổ biến nhất, bao gồm chủ yếu hai loại:
    - **Ung thư tế bào đáy (BCC - Basal Cell Carcinoma)**: Đây là loại ung thư da phổ biến nhất, thường phát triển ở những người có làn da trắng. Người có làn da sẫm màu cũng có thể mắc loại ung thư da này [[8](https://www.aad.org/public/diseases/skin-cancer/types/common)]. Khoảng 75% trong số 100 trường hợp ung thư da không phải u hắc tố là BCC. Chúng phát triển từ các tế bào đáy và các tế bào này được tìm thấy ở phần sâu nhất của lớp ngoài cùng của da (biểu bì). Chủ yếu phát triển ở những vùng da tiếp xúc với ánh nắng mặt trời như đầu và cổ, nhưng vẫn có thể phát triển ở các bộ phận khác của cơ thể [[9](https://www.cancerresearchuk.org/about-cancer/skin-cancer/types)].

    - **Ung thư tế bào vảy (SCC - Squamous Cell Carcinoma)**: Là loại ung thư da phổ biến thứ hai. Những người có làn da sáng màu có nguy cơ mắc SCC cao hơn và cũng có thể phát triển ở những người có làn da sẫm màu [[8](https://www.aad.org/public/diseases/skin-cancer/types/common)]. Ung thư biểu bì tế bào vảy SCC thường phát triển nhanh hơn so với BCC. Khoảng 25% trong số 100 trường hợp ung thư da là SCC. Chúng bắt đầu từ các tế bào gọi là tế bào sừng, nằm trong lớp biểu bì và phát triển trên các vùng da tiếp xúc với ánh nắng mặt trời. Những vùng này bao gồm một phần đầu, cổ, mu bàn tay và cẳng tay [[9](https://www.cancerresearchuk.org/about-cancer/skin-cancer/types)].

- **Ung thư da u hắc tố (Melanoma)** là nhóm nguy hiểm nhất, tuy có tỷ lệ mắc thấp hơn nhưng sở hữu khả năng di căn nhanh và tỷ lệ tử vong cao nếu không được phát hiện sớm. Ung thư u hắc tố da xảy ra khi một yếu tố nào đó biến đổi các tế bào hắc tố khỏe mạnh thành tế bào ung thư. Tế bào hắc tố là các tế bào da tạo ra sắc tố mang lại màu sắc cho da. Sắc tố này được gọi là melanin [[10](https://www.mayoclinic.org/diseases-conditions/melanoma/symptoms-causes/syc-20374884)].

### Bộ dữ liệu SLICE-3D

Bộ dữ liệu được nhóm sinh viên sử dụng trong khóa luận này là **SLICE-3D**, được công bố bởi tổ chức **ISIC** vào năm **2024** trên tạp chí **Scientific Data** thuộc nhà xuất bản Nature. Đây cũng là bộ dữ liệu chính thức của **cuộc thi ISIC 2024 Grand Challenge** trên nền tảng **Kaggle**.

Bộ dữ liệu này được thu thập trong **10 năm**, từ 2015 đến 2024, đến từ 9 bệnh viện và trường đại học tại Mỹ, Úc, Tây Ban Nha, Áo, Hy Lạp và Thụy Sĩ. Điều này đảm bảo sự đa dạng về sắc tộc, điều kiện chụp và thiết bị y tế. Tổng cộng bộ dữ liệu bao gồm **401.059 ảnh tổn thương da** ảnh tổn thương da được cắt từ ảnh TBP toàn thân 3D, với kích thước khoảng **128x128** pixel ở định dạng **JPEG** [[11](https://www.kaggle.com/competitions/isic-2024-challenge/overview)].

Mỗi ảnh đều có thông tin lâm sàng đi kèm trong một tập tin tổng hợp riêng. Thông tin này bao gồm **55 đặc trưng**, như tuổi, giới tính, vị trí giải phẫu của tổn thương và **hơn 30 chỉ số TBP**. Các chỉ số này được trích xuất tự động từ ảnh chụp toàn thân 3D, bao gồm kích thước, độ tương phản màu sắc và đặc điểm bề mặt. Sự kết hợp giữa các hình ảnh tổn thương và thông tin lâm sàng này tạo nền tảng cho hướng tiếp cận đa phương thức được đề xuất trong khóa luận.

![Bộ dữ liệu SLICE-3D](/asset/image/isic-pics.png)

Công nghệ chụp toàn thân **3D (3D Total Body Photography - 3D-TBP)** sử dụng hệ thống thiết bị **Vectra WB360** (của hãng Canfield Scientific), áp dụng thuật toán tái dựng bản đồ lưới (mesh) bề mặt da 3D toàn thân, sau đó tự động phát hiện và trích xuất các tổn thương thành từng mảnh ảnh (tile) kích thước _15mm×15mm_

## TỔNG QUAN MÔ HÌNH HỌC SÂU ĐA PHƯƠNG THỨC

> [!NOTE]
> Để hiện thực hóa hai thành phần trên tạo thành một hệ thống hoàn chỉnh, đề tài đề xuất kiến trúc tổng quát được trình bày trong hình sau:

![Mô hình tổng quan của dự án](/asset/image/thesis-project-overview-final.png)

Mô hình học sâu đa phương thức cho bài toán **phân loại tổn thương da nhị phân** (Benign/Malignant) trên bộ dữ liệu SLICE-3D được xây dựng thông qua các bước sau:

- Thu thập dữ liệu, tiền xử lý dữ liệu, phân chia dữ liệu và xử lý mất cân bằng,
- Trích xuất đặc trưng cho 2 loại dữ liệu riêng biệt:
    - Nhánh xử lý đặc trưng hình ảnh: sử dụng mô hình EfficientNetB3.
    - Nhánh xử lý đặc trưng lâm sàng: sử dụng mô hình MLP.
- Huấn luyện mô hình đa phương thức, đánh giá, tích hợp XAI và giám sát sau triển khai.

Kiến trúc được thiết kế nhằm khai thác đồng thời cả thông tin hình ảnh tổn thương da và dữ liệu lâm sàng của bệnh nhân, từ đó nâng cao khả năng chẩn đoán so với các phương pháp chỉ sử dụng một nguồn dữ liệu đơn lẻ.

![Kiến trúc của mô hình học sâu đa phương thức](/asset/image/multimodal-architecture.png)

Quy trình bắt đầu từ việc tải dữ liệu từ Kaggle. Dữ liệu sau đó được trải qua giai đoạn tiền xử lý, trong đó ảnh được tăng cường chất lượng bằng các kỹ thuật như CLAHE và Gaussian Blur, còn dữ liệu bảng được làm sạch, mã hóa và chuẩn hóa.

Tiếp theo, tập dữ liệu được phân chia theo tỷ lệ **64%/16%/20%** cho các tập huấn luyện, xác thực và kiểm thử bằng phương pháp **stratified split** nhằm duy trì tỷ lệ phân bố lớp. Do bộ dữ liệu có mức độ mất cân bằng cao giữa hai lớp Benign và Malignant, đề tài áp dụng cơ chế xử lý mất cân bằng dữ liệu trước khi huấn luyện để cải thiện khả năng nhận diện các mẫu ác tính.

Mô hình được xây dựng theo kiến trúc đa phương thức gồm hai nhánh xử lý song song. Nhánh ảnh sử dụng EfficientNetB3, nhánh dữ liệu lâm sàng sử dụng mạng MLP. Đặc trưng từ hai nhánh được kết hợp thông qua tầng Fusion Head để tạo thành biểu diễn đa phương thức thống nhất phục vụ cho quá trình phân loại.

Quá trình huấn luyện được thực hiện theo hai giai đoạn. Ở giai đoạn đầu, phần backbone của EfficientNetB3 được đóng băng và mô hình được huấn luyện với hàm mất mát Focal Loss kết hợp kỹ thuật oversampling nhằm tập trung vào các mẫu khó học. Ở giai đoạn thứ hai, các lớp của backbone được mở khóa để thực hiện fine-tuning, giúp mô hình thích nghi tốt hơn với miền dữ liệu da liễu trong khi vẫn duy trì các đặc trưng đã học từ ImageNet.

Sau khi hoàn tất huấn luyện, mô hình được đánh giá bằng các chỉ số như **pAUC, AUC, Recall và F1-score**. Ngưỡng phân loại tối ưu được xác định thông qua quá trình **threshold tuning** nhằm cân bằng giữa khả năng phát hiện ca ác tính và tỷ lệ cảnh báo sai. Để nâng cao tính minh bạch của hệ thống, đề tài tích hợp các kỹ thuật **XAI** nhằm giải thích cơ sở đưa ra dự đoán của mô hình.

Bên cạnh đó, cơ chế giám sát **data drift** được xây dựng nhằm theo dõi sự thay đổi phân phối dữ liệu trước và sau quá trình huấn luyện.

## XÂY DỰNG HẠ TẦNG MLOPS

> [!NOTE]
> Hệ thống Ops được xây dựng dựa trên nền tảng Cloud-native, tự động hóa từ khâu tích hợp mã nguồn, huấn luyện đến giám sát và phân phối mô hình.

### Xây dựng và quản hạ tầng dưới dạng mã nguồn

_Mã nguồn tham khảo: [environments/dev](/environments/dev), [modules/](/modules)_

![Kế hoạch quản lý hạ tầng](/asset/image/git-workflow.png)

Hình trên mô tả kế hoạch triển khai hạ tầng dưới dạng mã (IaC) sử dụng **Terraform** kết hợp với **GitHub Actions**. Quy trình được xây dựng nhằm tự động hóa các bước kiểm tra, đánh giá và triển khai hạ tầng trên nền tảng **AWS**, giúp giảm thiểu sai sót thủ công, tính nhất quán và nâng cao khả năng quản lý thay đổi trong suốt vòng đời phát triển.

Quy trình bắt đầu khi nhà phát triển đồng bộ mã nguồn từ nhánh **DEV** và tạo một nhánh tính năng (feature branch) để thực hiện các thay đổi. Sau khi hoàn thành, mã nguồn được đẩy lên **GitHub** và tạo **Pull Request** vào nhánh **DEV**. Hành động này kích hoạt **workflow** trên **GitHub Actions** để tiến hành kiểm tra mã nguồn hạ tầng (giai đoạn **Build and Test Infrastructure as Code** ở [file workflow kiểm tra mã nguồn](/.github/workflows/terraform-ci.yml)) trước khi cho phép hợp nhất thay đổi.

- **Checkov:** Thực hiện phân tích tĩnh trên mã nguồn Terraform nhằm phát hiện các lỗ hổng bảo mật và cấu hình không phù hợp.
- **Terraform Validate:** Kiểm tra tính hợp lệ của cú pháp, cấu trúc và các tham chiếu trong mã nguồn Terraform.
- **Terraform Plan:** Phân tích trạng thái hạ tầng hiện tại và mã nguồn Terraform mới để tạo ra một kế hoạch triển khai chi tiết.
- **Upload Plan to Amazon S3:** Tập tin Terraform plan được lưu trữ trên Amazon S3 nhằm bảo đảm rằng bản plan đã được kiểm tra và phê duyệt trong quá trình Pull Request, sẽ chính là bản được sử dụng trong giai đoạn triển khai.

Khi Pull Request được chấp nhận và được hợp nhất vào nhánh DEV, nhóm sinh viên có thể kích hoạt thủ công pipeline triển khai. Trong giai đoạn **Provision AWS Infrastructure** ở [file khởi tạo hạ tầng](.github/workflows/terraform-apply.yml), hệ thống sẽ:

- **Verify:** Nhóm sinh viên thực hiện bước xác nhận cuối cùng trước khi triển khai nhằm bảo đảm rằng các thay đổi đã được kiểm tra và phê duyệt.
- **Download Plan from Amazon S3:** Hệ thống tải về tệp Terraform Plan đã được tạo và lưu trữ ở giai đoạn kiểm tra trước đó.
- **Terraform Apply:** Thực thi tệp Terraform Plan đã tải về. Terraform sẽ tương tác với các dịch vụ AWS thông qua API để tạo mới, cập nhật hoặc xóa các tài nguyên cần thiết, đưa trạng thái hạ tầng thực tế về đúng trạng thái được mô tả trong mã nguồn Terraform.

Trong quá trình phát triển, kiểm thử hoặc khi môi trường không còn cần thiết, việc dọn dẹp tài nguyên để tối ưu chi phí là bắt buộc. Nhóm sinh viên đã thiết kế một pipeline riêng biệt ([file phá hủy hạ tầng](.github/workflows/terraform-destroy.yml)) để hủy hạ tầng một cách an toàn:

- **Verify:** Yêu cầu nhà phát triển xác nhận rõ ràng trước khi thực hiện quá trình hủy hạ tầng.
- **Terraform Plan Destroy:** Tạo một kế hoạch hủy hạ tầng, liệt kê chi tiết toàn bộ các tài nguyên sẽ bị xóa.
- **Terraform Destroy:** Thực hiện quá trình xóa các tài nguyên AWS được quản lý bởi Terraform dựa trên thông tin trong tệp trạng thái Terraform State.

### Xây dựng hạ tầng EKS

_Mã nguồn tham khảo: [modules/eks](/modules/eks), [modules/vpc](/modules/vpc)_

Đây là kiến trúc triển khai một cụm **Kubernetes** trên **AWS** theo mô hình **Multi-AZ** nhằm đảm bảo tính sẵn sàng, khả năng chịu lỗi và đảm bảo tính liên tục của dịch vụ.

![Kiến trúc của cụm EKS](/asset/image/eks-infrastructure-final.png)

Về phân vùng mạng, toàn bộ hạ tầng được triển khai trong một **VPC** với dải địa chỉ mạng **10.0.0.0/16**. **VPC** được phân bố trên hai **Availability Zone** là **ap-southeast-1a** và **ap-southeast-1b** nhằm bảo đảm tính sẵn sàng cao và giảm thiểu ảnh hưởng khi một vùng gặp sự cố. Chia subnet thành 2 loại để hạn chế khả năng truy cập trực tiếp từ **Internet** đến các thành phần quan trọng của hệ thống.

Mỗi public subnet được triển khai một **NAT Gateway** nhằm cung cấp khả năng truy cập **Internet** cho các tài nguyên nằm trong private subnet. Thông qua **NAT Gateway**, các **Worker Node** có thể thực hiện các tác vụ hoặc truy cập các dịch vụ **AWS** cần thiết mà không cần sử dụng địa chỉ **IP** công khai.

Bên cạnh đó, hệ thống sử dụng **Bastion Host** làm điểm truy cập quản trị tập trung. Nhóm sinh viên có thể kết nối đến **Bastion Host** thông qua giao thức **SSH**, sau đó thực hiện các thao tác quản trị đối với các tài nguyên nằm trong private subnet. Các kết nối được kiểm soát bởi **Security Group** nhằm giới hạn truy cập theo các nguyên tắc đặc quyền tối thiểu mà nhóm lập ra.

Sau khi hoàn thành cấu hình mạng, nhóm sinh viên tiến hành triển khai cụm **Kubernetes** thông qua dịch vụ **EKS** của **AWS**. Thành phần **EKS Control Plane** đóng vai trò điều phối toàn bộ hoạt động của cụm **Kubernetes**, bao gồm quản lý tài nguyên, lập lịch Pod và duy trì trạng thái mong muốn của hệ thống. Để tăng cường bảo mật, cụm **EKS** được cấu hình với:

```terraform
endpoint_public_access = false
endpoint_private_access = true
```

Cấu hình này bảo đảm API Server của **Kubernetes** chỉ có thể được truy cập từ bên trong **VPC** thông qua **Bastion Host**.

Hệ thống sử dụng **OIDC Provider** kết hợp với cơ chế **IRSA (IAM Roles for Service Accounts)** để cấp quyền truy cập AWS cho các Pod Kubernetes. Thông qua **IRSA**, mỗi ứng dụng hoặc dịch vụ trong **Kubernetes** có thể được gán một **IAM Role** riêng biệt. Điều này cho phép các **Pod** truy cập trực tiếp đến các dịch vụ **AWS** không cần sử dụng quyền của toàn bộ **Worker Node**.

Phần **Data Plane** của **Kubernetes** được triển khai thông qua **EKS Managed Node Groups** và được phân bố trên cả hai **Availability Zone** nhằm tăng khả năng chịu lỗi và bảo đảm tính liên tục của dịch vụ. Các **Worker Node** được chia thành ba nhóm chức năng riêng biệt:

- **Infra Node Group**: Chạy các dịch vụ nền tảng như **ArgoCD**, **Prometheus**, **Grafana**, **MLflow** và **KServe Controller**.
- **GPU Node Group**: Chuyên phục vụ các tác vụ huấn luyện mô hình học sâu yêu cầu tài nguyên **GPU NVIDIA**.
- **CPU Node Group**: Dành cho các tác vụ xử lý dữ liệu không yêu cầu **GPU**.

Cuối cùng, hệ thống sử dụng các **IAM Role** riêng biệt cho **EKS Control Plane** và **Worker Node** nhằm thực hiện cơ chế phân quyền theo chức năng:

- **EKS Cluster Role**: Cho phép **EKS** quản lý các tài nguyên **AWS** liên quan.
- **Worker Node Role**: Cho phép các **Worker Node** truy cập sử dụng các tài nguyên **AWS** cần thiết.

### Tích hợp các ứng dụng nền tảng trên cụm EKS

#### Xây dựng cơ chế Helm Bootstrap thông qua AWS Systems Manager

_Mã nguồn tham khảo: [modules/bastion-host](/modules/bastion-host), [.github/workflows/helm-bootstrap.yml](/.github/workflows/helm-bootstrap.yml), [.github/scripts/bash/phase2-install-addons.sh](/.github/scripts/bash/phase2-install-addons.sh)_

![Kiến trúc Helm Bootstrap sử dụng AWS Systems Manager](/asset/image/SSM-Bastion_host.png)

Nhằm đảm bảo quá trình khởi tạo các ứng dụng cần thiết trên cụm **EKS** được thực hiện tự động, bảo mật và không phụ thuộc vào truy cập **SSH** trực tiếp, nhóm sinh viên đã triển khai cơ chế Helm Bootstrap thông qua **AWS Systems Manager**. Kiến trúc này cho phép nhóm kích hoạt một pipeline từ **GitHub Actions**, sau đó sử dụng **AWS Systems Manager** để thiết lập kết nối bảo mật đến các máy chủ **Bastion** trong **VPC**.

Các **Bastion Host** được triển khai trong các **public subnet** thuộc nhiều **Availability Zone** nhằm tăng tính sẵn sàng của hệ thống. Thông qua **SSM Agent** được cài đặt trên **Bastion Host**, pipeline có thể tạo các phiên **SSM Tunnel** để thực thi các lệnh quản trị **Kubernetes** mà không cần mở cổng **SSH** ra **Internet**. Từ **Bastion Host**, các lệnh **Helm** được sử dụng để tương tác với cụm **EKS** nằm hoàn toàn trong **private subnet**.

#### Triển khai các thành phần nền tảng MLOps

_Mã nguồn tham khảo: [gitops/apps](/gitops/apps)_

![Kết quả triển khai các ứng dụng](/asset/image/helm-bootstrap-result.png)

Sau khi thiết lập thành công cơ chế Helm Bootstrap, nhóm tiến hành triển khai các thành phần nền tảng phục vụ vòng đời phát triển và vận hành mô hình học máy trên cụm EKS. Toàn bộ ứng dụng được đóng gói dưới dạng Helm Chart và được cài đặt tự động thông qua pipeline đã xây dựng.

Hệ thống bao gồm các thành phần chính sau:

- **ArgoCD**: Quản lý triển khai ứng dụng theo mô hình GitOps, đồng bộ trạng thái cụm Kubernetes với cấu hình được lưu trữ trên Git repository.
- **Argo Workflows**: Điều phối và thực thi các quy trình xử lý dữ liệu, huấn luyện mô hình và các tác vụ MLOps dưới dạng workflow.
- **MLflow**: Theo dõi thí nghiệm, quản lý tham số huấn luyện, lưu trữ mô hình và quản lý vòng đời mô hình học máy.
- **Prometheus**: Thu thập và lưu trữ các chỉ số giám sát từ Kubernetes và các ứng dụng trong hệ thống.
- **Grafana**: Trực quan hóa dữ liệu giám sát, hỗ trợ xây dựng các dashboard phục vụ vận hành.
- **cert-manager**: Tự động quản lý và gia hạn chứng chỉ TLS cho các dịch vụ trong cụm.
- **KServe**: Cung cấp nền tảng triển khai và phục vụ mô hình học máy trên Kubernetes.
- **Cloudflare Tunnel**: Cung cấp cơ chế truy cập an toàn từ bên ngoài vào các dịch vụ nội bộ.

Bên cạnh đó, MLflow được cấu hình sử dụng hai thành phần lưu trữ riêng biệt:

- **Artifact Store**: Lưu trữ mô hình, tập tin huấn luyện được tạo ra trong quá trình thực nghiệm.
- **Backend Store**: Lưu trữ metadata của các thí nghiệm và thông tin quản lý mô hình.

### Truy cập giao diện nội bộ của các ứng dụng trên cụm EKS

_Mã nguồn tham khảo: [modules/cloudflare](/modules/cloudflare), [gitops/apps/cloudflare.yaml](/gitops/apps/cloudflare.yaml)_

![Cấu hình Cloudflare Tunnel triển khai trong cụm EKS](/asset/image/cloudflare-eks.png)

Trong hệ thống mà nhóm sinh viên đang triển khai, việc công khai các giao diện quản trị nội bộ như **ArgoCD, MLflow, Grafana hay Argo Workflows** ra ngoài Internet thường mang lại nhiều rủi ro về bảo mật. Để giải quyết bài toán bảo mật và tối ưu chi phí khi vận hành, nhóm đã ứng dụng giải pháp **Cloudflare Tunnel**. Giải pháp này cho phép kết nối các dịch vụ nội bộ bên trong cụm EKS ra môi trường Internet thông qua một đường hầm bảo mật mã hóa một chiều từ trong ra ngoài (outbound connection). Nhờ đó, cụm EKS không cần mở bất kỳ cổng inbound nào trên tường lửa hay cấp phát IP public, giúp hệ thống miễn nhiễm hoàn toàn với các cuộc tấn công rà quét mạng.

Luồng mạng được thiết lập như sau:

- **Tại Cloudflare Edge**: Một **Tunnel** có tên **eks-tunnel** được khởi tạo đóng vai trò như một gateway trung chuyển và phân giải tên miền.
- **Tại cụm EKS**: Một **Deployment** có tên **cloudflared-deployment** được triển khai với tính sẵn sàng cao. Các **Pod** cloudflared này chạy ngầm và duy trì kết nối liên tục tới **Cloudflare Edge** thông qua **Tunnel token**.

Thay vì sử dụng **Ingress Controller** nội bộ phức tạp, việc định tuyến được cấu hình bằng một tập tin **Ingress** đặc biệt của **Cloudflare** và được áp dụng thông qua **Helm Bootstrap pipeline**. Khi người dùng truy cập vào các tên miền tùy chỉnh, **Cloudflare** sẽ định tuyến request qua đường hầm mạng tới các dịch vụ **ClusterIP** tương ứng bên trong **EKS** mà không cần đi ra ngoài mạng công cộng.

Tuy nhiên, không phải mọi ứng dụng trên cụm đều phù hợp để đưa ra một tên miền công khai qua **Cloudflare Tunnel**. Ví dụ như **Prometheus**, theo mặc định không có lớp xác thực nào ở giao diện web của chính nó, bất kỳ ai có được URL đều có thể truy vấn trực tiếp toàn bộ metrics, bao gồm cả những chỉ số hạ tầng nhạy cảm (địa chỉ IP nội bộ, tên node, cấu hình tài nguyên).

![Phương pháp port-forward](/asset/image/port-forward.png)

Nhược điểm của cách làm này là **tính thủ công**: nhóm sinh viên phải giữ đồng thời hai phiên **SSH** sống trong suốt thời gian truy cập, và chỉ một người có thể sử dụng tại một thời điểm.

### Kích hoạt điều phối GitOps trên cụm EKS

Sau khi hoàn tất quá trình Helm bootstrap thông qua bước [Tích hợp các ứng dụng nền tảng trên cụm EKS](#tích-hợp-các-ứng-dụng-nền-tảng-trên-cụm-eks), các ứng dụng nền tảng đã được triển khai thành công trên cụm **Amazon EKS**, đồng thời **Cloudflare Tunnel** cung cấp khả năng truy cập từ bên ngoài tới các giao diện quản trị. Tuy nhiên, ở giai đoạn này **ArgoCD** mới chỉ được cài đặt và chưa quản lý bất kỳ ứng dụng nào theo mô hình **GitOps**. Do đó, hệ thống cần thực hiện bước bootstrap nhằm khởi tạo cấu hình ban đầu, đưa **ArgoCD** trở thành bộ điều phối trung tâm cho quá trình triển khai và đồng bộ toàn bộ ứng dụng trên cụm.

#### Mô hình App-of-Apps và AppProject

_Mã nguồn tham khảo: [gitops/app-of-apps.yaml](/gitops/app-of-apps.yaml), [gitops/projects/appproject.yaml](/gitops/projects/appproject.yaml)_

Hệ thống bao gồm nhiều thành phần hạ tầng như và pipeline huấn luyện mô hình. Nếu mỗi thành phần được khai báo độc lập trong ArgoCD, việc quản lý sẽ trở nên vô cùng phức tạp khi số lượng ứng dụng tăng lên hoặc khi tồn tại quan hệ phụ thuộc giữa chúng. Vì vậy, nhóm sinh viên đã áp dụng mẫu thiết kế **App-of-Apps**, trong đó chỉ một ứng dụng cha duy nhất có tên **k8s-infra-addons** được khai báo và trỏ tới thư mục **gitops/apps/** trong kho mã nguồn Git. ArgoCD sẽ tự động đọc các manifest trong thư mục này để tạo và quản lý các ứng dụng con tương ứng.

![Mô hình App-of-Apps](/asset/image/appofapp.png)

Bên cạnh đó, một **AppProject** có tên **platform** được thiết lập nhằm giới hạn phạm vi hoạt động của các ứng dụng. Chỉ các kho lưu trũ đã được cho phép và các namespace được chỉ định trước mới có quyền triển khai lên cụm. Cơ chế này hoạt động độc lập với hệ thống RBAC của Kubernetes, cung cấp thêm một lớp kiểm soát nhằm ngăn chặn việc triển khai ngoài phạm vi cho phép trước khi các thay đổi từ Git được áp dụng lên môi trường thực tế.

![Các Application thuộc AppProject platform](/asset/image/platform-scope.png)

#### Quy trình bootstrap tự động bằng GitHub Actions

_Mã nguồn tham khảo: [.github/workflows/argocd-bootstrap.yml](/.github/workflows/argocd-bootstrap.yml), [.github/scripts/bash/phase3-argocd-bootstrap.sh](/.github/scripts/bash/phase3-argocd-bootstrap.sh)_

Quá trình bootstrap được tự động hóa thông qua workflow trên GitHub Actions. Workflow này sử dụng AWS SSM để thực thi lệnh từ xa trên Bastion Host mà không cần mở cổng SSH, tương tự như quy trình Helm bootstrap đã trình bày ở mục trước.

Trước hết, hai manifest nền tảng là **appproject.yaml** và **app-of-apps.yaml** được chuyển tới Bastion dưới dạng Base64 và áp dụng bằng câu lệnh thích hợp của Kubernetes. Sau khi các manifest được tạo thành công, ArgoCD nhận diện ứng dụng cha và bắt đầu đồng bộ cấu hình từ kho lưu trữ Git.

Tiếp theo, workflow kích hoạt quá trình đồng bộ của ứng dụng con thuộc ứng dụng cha **k8s-infra-addons** và định kỳ kiểm tra sự xuất hiện của các ứng dụng con trong khoảng thời gian nhất định. Cơ chế này bảo đảm ArgoCD hoàn tất việc khởi tạo các ứng dụng trước khi chuyển sang các bước tiếp theo. Các ứng dụng sau đó được đồng bộ theo đúng thứ tự phụ thuộc của nhau.

![Quá trình bootstrap bằng ArgoCD](/asset/image/argocd-bootstrap.png)

Ngoài các cấu hình tĩnh được lưu trong Git, một số tham số chỉ được xác định sau khi Terraform hoàn tất quá trình khởi tạo hạ tầng, chẳng hạn như ARN của IRSA, ID của Amazon EFS hoặc tên cụm EKS. Thay vì lưu trực tiếp các giá trị này trong kho Git, workflow đọc chúng từ Terraform Output và cập nhật vào các đối tượng Application thông qua lệnh _kubectl patch_. Cách tiếp cận này giúp tách biệt cấu hình tĩnh khỏi các giá trị phụ thuộc môi trường, đồng thời duy trì khả năng tái sử dụng của kho Git giữa nhiều môi trường triển khai khác nhau.

### Tích hợp liên tục cho mã nguồn học sâu đa phương thức

_Mã nguồn tham khảo: [.github/workflows/](https://github.com/xyan-dhgb/mlops-model/blob/main/.github/workflows/ml-ci-cd.yml)_

![Tích hợp liên tục cho mã nguồn học sâu đa phương thức](/asset/image/mul-ci-pipeline-final.png)

Quy trình tích hợp liên tục (CI) được thiết kế nhằm tự động hóa toàn bộ các bước kiểm tra, đóng gói mã nguồn mô hình học sâu đa phương thức, đảm bảo mỗi thay đổi được đưa vào nhánh chính đều trải qua các lần kiểm soát chất lượng trước khi triển khai.

Pipeline được kích hoạt tự động mỗi khi nhóm đẩy lên các thay đổi mới nhất của mã nguồn lên kho lưu trữ GitHub. Ở giai đoạn đầu, **Job 1** thực hiện phân tích tĩnh mã nguồn bằng hai công cụ là flake8 và mypy. Trong khi flake8 kiểm tra các vi phạm trong cách thiết kế lập trình thì mypy đảm nhận việc kiểm tra kiểu dữ liệu tĩnh.

Tiếp theo, **Job 2** thực hiện Unit Test bằng pytest để xác minh tính đúng đắn của các thành phần quan trọng như hàm tiền xử lý dữ liệu, logic tổng hợp đặc trưng đa phương thức và các hàm tính toán chỉ số đánh giá. Chỉ khi vượt qua toàn bộ test case, pipeline mới tiến sang các bước tiếp theo.

**Job 3** đảm bảo kết nối Amazon ECR - một kho lưu trữ Docker image riêng tư trên AWS. **Job 4** sau đó thực thi theo chiến lược ma trận, song song hóa quá trình xây dựng Docker image và quét bảo mật. Image sau khi build được kiểm tra bằng công cụ quét lỗ hổng bảo mật để phát hiện các CVE trong các dependency của môi trường huấn luyện. Nếu không phát sinh vấn đề, image được đẩy lên ECR và phiên bản image mới được cập nhật vào các file manifest Helm tại nơi lưu trữ mã nguồn của hạ tầng MLOps.

Về mặt hạ tầng, ArgoCD liên tục theo dõi kho lưu trữ các tập tin Helm manifest và tự động đồng bộ trạng thái cụm EKS về đúng cấu hình được khai báo.

### Triển khai training pipeline trên Argo Workflows

_Mã nguồn tham khảo: [gitops/mlops-pipeline/isic](/gitops/mlops-pipeline/isic)_

Sau khi quy trình CI của mã nguồn học sâu đa phương thức hoàn tất và Docker image chứa toàn bộ môi trường huấn luyện được đẩy lên Amazon ECR, Argo Workflows tiếp nhận image đó để thực thi pipeline huấn luyện mô hình học sâu đa phương thức trên cụm EKS.

Mỗi bước trong pipeline được ánh xạ thành một Pod Kubernetes độc lập, cho phép kiểm soát tài nguyên tính toán ở mức độ chi tiết và dễ dàng tái thực thi từng bước khi xảy ra lỗi mà không cần chạy lại toàn bộ quy trình. Log thực thi của tất cả các bước được ghi và lưu trữ trên Amazon S3 thông qua bucket có tên là kltn-argo-workflows-logs, phục vụ cho mục đích kiểm tra và gỡ lỗi về sau.

Pipeline được bắt đầu bằng bước **Download data**, tải tập dữ liệu SLICE-3D 2024 từ nguồn lưu trữ về môi trường thực thi. Tiếp theo, hai bước tiền xử lý được thực hiện song song: **Preprocess CSV** xử lý dữ liệu dạng bảng trong khi **Preprocess Image** thực hiện các phép biến đổi trên ảnh nội soi da. Việc song song hóa hai luồng này rút ngắn đáng kể tổng thời gian tiền xử lý so với thực hiện tuần tự.

Kết quả từ hai nhánh tiền xử lý được hợp nhất tại bước xây dựng bộ dữ liệu huấn luyện (_Dataloader and Imbalance Handling_). Tại đây, hệ thống thực hiện việc phân chia tập train/val/test và áp dụng các kỹ thuật xử lý mất cân bằng dữ liệu nhằm giảm ảnh hưởng của sự chênh lệch số lượng mẫu giữa các lớp trong tập dữ liệu.

Tiếp theo, luồng hoạt động tiến hành xây dựng hai thành phần của mô hình đa phương thức. Đối với dữ liệu bảng, một mạng **MLP** được khởi tạo để trích xuất đặc trưng từ các thuộc tính dạng bảng. Đối với dữ liệu ảnh, mô hình **EfficientNet-B3** được sử dụng làm bộ trích xuất đặc trưng thị giác. Hai nhánh mô hình này được kết hợp trong giai đoạn huấn luyện nhằm tạo thành kiến trúc học sâu đa phương thức.

Sau khi cả hai nhánh sẵn sàng, bước **Train** tiến hành huấn luyện mô hình hợp nhất với cơ chế fusion đặc trưng từ hai luồng dữ liệu. Trong quá trình huấn luyện, các chỉ số đánh giá, siêu tham số và thông tin mô hình được ghi nhận tự động vào MLflow Tracking Server.

Sau khi hoàn thành huấn luyện, mô hình được đánh giá trên tập dữ liệu kiểm thử thông qua bước **Evaluate**. Cuối cùng, hệ thống thực hiện bước _XAI (Explainable AI)_ nhằm phân tích và trực quan hóa các yếu tố ảnh hưởng đến quyết định dự đoán của mô hình.

![Pipeline Argo Workflow trên cụm EKS](/asset/image/multimodal-mlops-eks-pipeline.png)

Nhờ được triển khai dưới dạng Argo Workflow trên Kubernetes, toàn bộ quy trình có khả năng tái sử dụng, mở rộng và tự động hóa cao, đồng thời đảm bảo khả năng theo dõi thí nghiệm và quản lý mô hình.

### Quản lý và theo dõi thí nghiệm huấn luyện

_Mã nguồn tham khảo: [modules/mlflow](/modules/mlflow), [gitops/apps/mlflow.yaml](/gitops/apps/mlflow.yaml)_

Để hỗ trợ quản lý vòng đời mô hình học máy và tăng khả năng tái lập kết quả nghiên cứu, nhóm sinh viên đã tích hợp **MLflow** như một nền tảng theo dõi và quản lý các thí nghiệm huấn luyện. **MLflow** cho phép ghi nhận toàn bộ thông tin liên quan đến quá trình huấn luyện, bao gồm siêu tham số (hyperparameters), chỉ số đánh giá (metrics) và lịch sử thực thi của từng lần chạy.

Trong khóa luận, **MLflow** được triển khai trên cụm **Amazon EKS** và được tích hợp trực tiếp vào pipeline huấn luyện. Mỗi khi quy trình huấn luyện được kích hoạt từ **Argo Workflows**, các thông tin như kích thước ảnh đầu vào, số lượng mẫu huấn luyện, trọng số lớp, thời gian thực thi và các chỉ số đánh giá sẽ được tự động ghi nhận vào **MLflow**. Điều này giúp giảm thiểu thao tác thủ công, đồng thời đảm bảo tính nhất quán trong việc quản lý các thí nghiệm.

Hình dưới đây minh họa giao diện **MLflow Tracking** của hệ thống. Giao diện hiển thị danh sách các lần huấn luyện đã thực hiện cùng với các siêu tham số và chỉ số liên quan. Người dùng có thể truy cập từng lần chạy để xem chi tiết quá trình huấn luyện, kết quả đánh giá mô hình được sinh ra.

![Quản lý các thí nghiệm trên MLflow](/asset/image/mlflow-exp.png)

### Xây dựng dịch vụ suy luận mô hình bằng KServe Custom Predictor

_Mã nguồn tham khảo: [src/model-serving](/src/model-serving)_

Để đưa mô hình học sâu đa phương thức vào môi trường vận hành, nhóm xây dựng một dịch vụ suy luận tùy chỉnh dựa trên KServe Custom Predictor.

Dịch vụ được hiện thực bằng ngôn ngữ Python, trong đó lớp SkinPredictionModel kế thừa từ lớp cơ sở **kserve.Model** và ghi đè ba phương thức vòng đời: load(), preprocess() và predict(). Khi khởi tạo, dịch vụ tự động tải các đối tượng phục vụ suy luận từ Amazon S3 thông qua cơ chế **Storage Initializer** của KServe.

Khi khởi động, **load()** đọc ba artifact được KServe Storage Initializer mount sẵn từ S3 vào **/mnt/models**: trọng số mô hình .h5, bộ preprocessor encoders.pkl và ngưỡng phân loại tối ưu best-threshold.txt.

Trong **preprocess()**, ảnh đầu vào được giải mã và đưa qua pipeline tiền xử lý giống hệt giai đoạn huấn luyện và dữ liệu bảng được mã hóa, điền khuyết và chuẩn hóa bằng các transformer đã tích hợp sẵn trong **encoders.pkl**. Phương thức **predict()** sau đó chạy suy luận, áp dụng ngưỡng tối ưu thay vì 0.5 mặc định, và trả về kết quả kèm bản đồ nhiệt GradCAM nếu kích hoạt XAI.

Dịch vụ suy luận giao tiếp với bên ngoài tuân theo **KServe V1 Protocol** - một chuẩn HTTP/JSON được KServe định nghĩa sẵn, giúp dịch vụ tương thích với các client không phụ thuộc vào framework mô hình cụ thể. Người dùng nhập request được gửi đến endpoint **POST /v1/models/skin-prediction:predict** với payload chứa đồng thời ảnh nội soi da dưới dạng base64 và thông tin lâm sàng dạng JSON. Response trả về nhãn phân loại, xác suất dự đoán, thời gian suy luận và tùy chọn bản đồ nhiệt GradCAM.

![Endpoint của dịch vụ suy luận mô hình](/asset/image/api-syntax.png)

### Xây dựng quy trình tích hợp và triển khai liên tục cho dịch vụ suy luận

_Mã nguồn tham khảo: [.github/workflows/](/.github/workflows)_

![Mô hình tích hợp và triển khai liên tục cho dịch vụ suy luận](/asset/image/serving-cicd-pipeline.png)

Sau khi hoàn thiện dịch vụ suy luận mô hình bằng **KServe Custom Predictor**, nhóm tiến hành xây dựng quy trình **CI/CD** nhằm tự động hóa quá trình triển khai phiên bản mới của dịch vụ lên môi trường **Kubernetes**. Quy trình được thiết kế dựa trên nguyên tắc **GitOps**, kết hợp giữa **GitHub Actions**, **Amazon ECR**, **ArgoCD** và **KServe** để đảm bảo tính nhất quán, khả năng truy vết và giảm thiểu các thao tác triển khai thủ công.

Quá trình bắt đầu khi nhóm sinh viên cập nhật mã nguồn của dịch vụ suy luận và đẩy các thay đổi lên kho mã nguồn GitHub. Sau khi **Pull Request** được tạo, rà soát mã nguồn và hợp nhất vào nhánh chính, **GitHub Actions** sẽ tự động kích hoạt pipeline CI. Trong giai đoạn đầu tiên, mã nguồn của **KServe Custom Predictor** được đóng gói thành **Docker Image** và đẩy lên **Amazon ECR**.

Sau khi image mới được tạo thành công, pipeline chuyển sang giai đoạn cập nhật cấu hình triển khai. Tại bước này, **GitHub Actions** tự động thay image tag trong tệp khai báo **InferenceService** của **KServe**. Thay vì triển khai trực tiếp lên cụm Kubernetes, toàn bộ trạng thái mong muốn của hệ thống được quản lý dưới dạng mã nguồn, cho phép dễ dàng kiểm soát lịch sử thay đổi, thực hiện kiểm thử và khôi phục khi cần thiết.

**ArgoCD** tự động đồng bộ trạng thái mong muốn xuống cụm **Amazon EKS**. **KServe Controller** sau đó tiếp nhận tài nguyên **InferenceService** và thực hiện tạo các thành phần cần thiết bao gồm Service, Deployment và Pod theo chế độ **RawDeployment** phục vụ suy luận mô hình.

Khi Pod predictor khởi động, container **storage-initializer** chạy trước như một init container, tải các artifact mô hình từ S3 bucket về thư mục **/mnt/models** trước khi container serving chính bắt đầu nhận yêu cầu. Luồng dữ liệu từ S3 vào Pod diễn ra hoàn toàn tự động theo cấu hình **storageUri** trong manifest, không cần can thiệp thủ công.

Sau khi quá trình đồng bộ hoàn tất, dịch vụ suy luận được cung cấp thông qua endpoint của KServe và sẵn sàng phục vụ các yêu cầu từ người dùng. Nhóm sinh viên sử dụng công cụ kiểm thử API để gửi dữ liệu đầu vào và nhận kết quả dự đoán từ mô hình.

![Kiểm thử trạng thái của API](/asset/image/precheck-api.png)

![Kiểm thử kết quả trả về của API](/asset/image/post-method-result.png)

### Phát triển hệ thống giám sát và trực quan hóa dữ liệu

_Mã nguồn tham khảo: [modules/monitoring](/modules/monitoring)_

Trong môi trường MLOps, việc giám sát không chỉ dừng lại ở quá trình huấn luyện hay triển khai mô hình mà còn phải quan sát đồng thời nhiều lớp hệ thống khác nhau, từ trạng thái vật lý của cụm Kubernetes, tính khả dụng của các dịch vụ ứng dụng, tiến trình và chi phí của vòng huấn luyện, cho đến chất lượng của quy trình CI/CD của hạ tầng. Một sự cố xuất hiện ở bất kỳ tầng nào đều có thể ảnh hưởng trực tiếp đến tính ổn định của hệ thống. Vì vậy, nhóm đã xây dựng hệ thống giám sát tập trung dựa trên Prometheus và Grafana nhằm cung cấp khả năng quan sát toàn diện cho nền tảng MLOps.

Việc thu thập dữ liệu được thực hiện tự động bằng các tài nguyên **ServiceMonitor** và **PodMonitor**, cho phép Prometheus phát hiện và lấy dữ liệu từ các **exporter** mà không cần cấu hình thủ công trên từng dịch vụ. Các nguồn dữ liệu bao gồm **kube-state-metrics** và **cAdvisor** phục vụ giám sát Kubernetes, **NVIDIA DCGM Exporter** cung cấp thông tin phần cứng GPU, **Argo Workflows Controller** theo dõi các pipeline huấn luyện, ML Pod cung cấp các chỉ số liên quan đến quá trình học máy và một số **custom exporter** phục vụ giám sát quy trình triển khai hạ tầng.

![Hệ thống giám sát và theo dõi tài nguyên](/asset/image/monitoring-and-visualizing.png)

## GIỚI HẠN ĐỀ TÀI

- Mặc dù hệ thống MLOps được xây dựng nhằm đáp ứng các yêu cầu về tự động hóa và quản lý vòng đời mô hình, đề tài vẫn tồn tại một số hạn chế. Do giới hạn về thời gian và nguồn lực, dữ liệu và phạm vi thực nghiệm chưa đủ lớn để phản ánh toàn diện các tình huống thực tế.
- Tài nguyên tính toán còn hạn chế nên chưa thể thực hiện các thí nghiệm và tối ưu ở quy mô sâu và đa dạng. Ngoài ra, hệ thống mới được kiểm chứng ở mức thử nghiệm, chưa đánh giá đầy đủ trong môi trường vận hành thực tế với quy mô lớn và thời gian dài.

## HẠN CHẾ

- **Quy mô dữ liệu**: chỉ sử dụng tập dữ liệu nhỏ 10.393 mẫu trên tổng 401.059 mẫu (2.6%). Kết quả cần được kiểm chứng trên toàn bộ dataset để đánh giá khả năng tổng quát hóa thực sự. Chưa kiểm chứng được tính khách quan khi áp dụng cho các loại da khác nhau ở các quốc gia, khu vực địa lý và chủng tộc khác nhau.
- **XAI chưa hoạt động ổn định khi serving**: XAI có xu hướng học theo artifact từ augmentation thay vì đặc trưng bệnh lý thực sự.
- **pAUC chưa đạt mục tiêu**: pAUC ≈ 0.080 (sau chuẩn hóa) chưa đạt ngưỡng ≥ 0.15 của kịch bản sàng lọc cộng đồng. AUC-ROC = 0.892 và F1 = 0.3488 cho thấy tiềm năng lớn cần khai thác.
- **Recall Malignant = 62%**: còn 30 ca Malignant bị bỏ sót (FN) trên tập Test. Trong môi trường lâm sàng thực tế, con số này cần tiếp tục cải thiện.
- **Data drift**: chức năng này chỉ mới áp dụng ở môi trường cục bộ, chưa được đưa lên hạ tầng MLOps.
- **Chưa xây dựng cơ chế học liên tục**: hệ thống hiện tại mới hỗ trợ tự động hóa quy trình huấn luyện, đánh giá và triển khai mô hình dựa trên dữ liệu đã được chuẩn bị trước. Cần xây dựng cơ chế học liên tục để tự động phát hiện dữ liệu mới, tái huấn luyện mô hình và cập nhật phiên bản mô hình đang phục vụ.
- **Đối tượng sử dụng bị giới hạn**: dừng lại ở việc cung cấp các cổng giao tiếp API để kiểm thử và tích hợp, chưa xây dựng giao diện người dùng trực quan.

## HƯỚNG PHÁT TRIỂN

- **Mở rộng dữ liệu**: huấn luyện trên toàn bộ 401.059 mẫu SLICE-3D với hạ tầng phân tán, dự kiến cải thiện đáng kể pAUC và Recall.
- **Nâng cấp backbone**: thử nghiệm EfficientNetB4/B5, EfficientNetV2, hoặc Vision Transformer (ViT) cho nhánh ảnh, có thể cải thiện chất lượng đặc trưng hình ảnh.
- **Cơ chế Attention cho Fusion**: thay Concatenate đơn giản bằng Cross-Modal Attention hoặc Transformer-based Fusion để mô hình học tương tác động giữa hai modality.
- **Cải thiện xử lý mất cân bằng**: tích hợp Mixup augmentation, CutMix, Asymmetric Loss, hoặc GAN-based oversampling để tạo mẫu Malignant tổng hợp chất lượng cao.
- **Đánh giá lâm sàng thực tế**: hợp tác với cơ sở y tế để thu thập dữ liệu thực tế, đánh giá prospectively trên bệnh nhân Việt Nam - điều chỉnh mô hình cho phù hợp với đặc điểm da liễu người Việt.
- **Xây dựng pipeline học liên tục**: xây dựng cơ chế cảnh báo tự động và tự động kích hoạt chu trình tái huấn luyện mô hình khi phát hiện có sự suy giảm nghiêm trọng về chất lượng dữ liệu đầu vào.
- **Xây dựng ứng dụng**: trực quan hóa các kết quả đầu ra của mô hình học sâu đa phương thức.
- **Ứng dụng Federated Learning**: huấn luyện phân tán bảo vệ quyền riêng tư bệnh nhân giữa nhiều bệnh viện.

## TÀI LIỆU THAM KHẢO

- [1]: Centers for Disease Control and Prevention. Skin Cancer Basics. [Online]. Available: https://www.cdc.gov/skin-cancer/about/index.html.[Accessed: Jun. 14, 2026]. July 2024.

- [2]: World Cancer Research Fund International. Skin Cancer. [Online]. Available: https://www.wcrf.org/preventing-cancer/cancer-types/skin-cancer/. [Accessed: Jun. 14, 2026]. 2024.

- [3]: International Agency for Research on Cancer. Non-Melanoma Skin Cancer Fact Sheet. [Online]. Available: https://gco.iarc.who.int/media/globocan/factsheets/cancers/17-non-melanoma-skin-cancer-fact-sheet.pdf. [Accessed: Jun. 14, 2026]. 2024

- [4]: Freddie Bray, Mathieu Laversanne, Hyuna Sung, Jacques Ferlay, Rebecca L. Siegel, Isabelle Soerjomataram, và Ahmedin Jemal. “Global cancer statistics 2022: GLOBOCAN estimates of incidence and mortality worldwide for 36 cancers in 185 countries”. In: CA: A Cancer Journal for Clinicians 74.3 (2024), pp. 229–263. DOI: 10.3322/caac.21834.

- [5]: Bệnh viện Đa khoa Tâm Anh. Melanin là gì? Cơ chế hình thành, vai trò và tác dụng. [Online]. Available: https://tamanhhospital.vn/co-the-nguoi/melanin/. [Accessed: Jun. 14, 2026]. Feb. 2026.

- [6]: Bệnh viện Da liễu Trung ương. Ung thư da hắc tố: Nhận biết sớm như thế nào? [Online]. Available: https://dalieu.vn/ung-thu-da-hac-to-nhanbiet-som-nhu-the-nao-5537.html. [Accessed: Jun. 14, 2026]. Jan. 2026.

- [7]: L. Zhou, Y. Zhong, L. Han, Y. Xie, và M. Wan. “Global, regional, and national trends in the burden of melanoma and non-melanoma skin cancer: Insights from the global burden of disease study 1990–2021”. In: Scientific Reports 15.1 (Feb. 2025), p. 5996. DOI: 10.1038/s41598-025-90485-3.

- [8]: American Academy of Dermatology Association. Types of Skin Cancer. [Online]. Available: https://www.aad.org/public/diseases/skin-cancer/types/common. [Accessed: Jun. 14, 2026]. 2024

- [9]: Cancer Research UK. Types of Non Melanoma Skin Cancer. [Online]. Available: https://www.cancerresearchuk.org/about-cancer/skin-cancer/types. [Accessed: Jun. 14, 2026]. 2024.

- [10]: Mayo Clinic Staff. Melanoma: Symptoms and Causes. [Online]. Available: https://www.mayoclinic.org/diseases-conditions/melanoma/symptoms-causes/syc-20374884. [Accessed: Jun. 14, 2026]. 2023

- [11]: International Skin Imaging Collaboration. ISIC 2024 - Skin Cancer Detection with 3D-TBP. [Online]. Available: https://www.kaggle.com/competitions/ isic-2024-challenge/overview. [Accessed: Jun. 14, 2026]. 2024.
