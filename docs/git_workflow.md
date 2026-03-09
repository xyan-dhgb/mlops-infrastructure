# Tài liệu Quy trình Quản lý Hạ tầng trên Git

## 1. Tổng quan

Tài liệu này quy chuẩn hóa quy trình triển khai và phối hợp làm việc trên hệ thống quản lý hạ tầng bằng công cụ `Terraform` gắn chặt với nền tảng `GitHub Actions`. Quy trình được thiết kế chuyên biệt cho nhóm gồm hai sinh viên nhằm đảm bảo tính toàn vẹn, khả năng kiểm toán mã nguồn và mức độ an toàn khi làm việc nhằm ngăn ngừa sự cố khi can thiệp vào tài nguyên hạ tầng đám mây.

## 2. Chiến lược phân nhánh (branching strategy)

Kho lưu trữ mã nguồn hạ tầng vận hành trên ba nhóm nhánh chính:

- **Nhánh `master`**: Hệ quy chiếu cao nhất, đại diện cho trạng thái ổn định nhất của hệ thống. Mã nguồn trên nhánh này phản ánh chính xác trạng thái hạ tầng đã được kiểm duyệt và triển khai thành công trên môi trường thực tế.
- **Nhánh `dev`**: Nhánh hội nhập trung gian (integration branch). Được sử dụng để chứa các thay đổi mã nguồn đã vượt qua bước kiểm định liên tục (CI) và đang trực chờ được áp dụng lên môi trường hạ tầng.
- **Nhánh `feature/*`**: Các nhánh vòng đời ngắn hạn (ephemeral branches), được phân tách từ nhánh `master`. Sinh viên sử dụng nhánh này để phát triển và cập nhật cấu trúc hạ tầng độc lập.

## 3. Lịch trình triển khai cốt lõi

### Giai đoạn 1: Phát triển tính năng (feature development)

1. Sinh viên chịu trách nhiệm tải (pull) mã nguồn phiên bản mới nhất từ nhánh `master` về môi trường cục bộ.
2. Thiết lập một nhánh làm việc mới dưới tiền tố `feature/` (ví dụ: `feature/update-eks-cluster`) nhằm ngăn cách hoàn toàn với mã định dạng trên nhánh chính.
3. Cần lưu ý rằng, sinh viên bắt buộc thực hiện việc căn chỉnh cấu hình Terraform cục bộ cho tới khi đáp ứng yêu cầu kỹ thuật.

### Giai đoạn 2: Tích hợp liên tục (continuous integration - CI)

1. Sinh viên hoàn tất phần mã nguồn tại nhánh `feature` chủ động khởi tạo một Pull Request - PR hướng về nhánh `dev`.
2. Thao tác mở PR tự động kích hoạt chuỗi tiến trình `Terraform CI` (`terraform-ci.yml`) trực thuộc hệ thống GitHub Actions. Hệ thống tuần tự thực thi khâu kiểm thử trên môi trường hạ tầng giả định:
   - `terraform init`: Khởi tạo môi trường Terraform.
   - `terraform fmt`: Kiểm tra và đối chiếu các chuẩn định dạng mã.
   - `terraform validate`: Kiểm tra tính hợp lệ về cú pháp khai báo hạ tầng.
   - `terraform plan`: Xây dựng một bản kế hoạch thực thi để phân tích sự thay đổi giữa mã nguồn và hạ tầng hiện hữu.
3. **Lưu trữ căn cứ đối chiếu**:
   - Bản kế hoạch (`tfplan`) do chuỗi tiến trình sinh ra sẽ được lưu trữ an toàn tại máy chủ Amazon S3 (`kltn-tfstate-dev/plans/dev/`) làm hiện vật truy vết.
   - Đồng thời, một bản tóm tắt kế hoạch sẽ được tạo tự động thông qua Github Bot, gắn kết trực tiếp vào bình luận trên PR để hỗ trợ thảo luận.
4. **Phê duyệt đối chiếu**: Sinh viên còn lại có trách nhiệm xem xét, đánh giá rủi ro từ bản kế hoạch. Chỉ khi kết quả kiểm thử **báo xanh** và người bình duyệt chấp thuận, PR đính kèm mới được hợp nhất (merge) vào nhánh `dev`.

### Giai đoạn 3: Áp dụng môi trường hạ tầng (infrastructure apply)

1. **Kích hoạt Thủ công**: Việc mã nguồn được đưa vào nhánh `dev` không tự động thay đổi tài nguyên vật lý. Một sinh viên áp dụng môi trường, kích hoạt thủ công chu trình triển khai `Terraform Apply` trên Github Actions.
2. **Khai báo tham số thực thi**:
   - Tiến trình bắt buộc khởi chạy tại nhánh `dev`.
   - Sinh viên cần điền trực tiếp mã băm (`plan_commit_sha`) được lưu trữ từ Giai đoạn 2 nhằm chỉ thị cho hệ thống tải về phiên bản chính xác của bản kế hoạch trực thuộc S3.
3. **Thực thi kiến trúc mới**: Hệ thống đảm trách tải xuống bản kế hoạch Terraform tương thích, tái kiểm tra và bắt đầu thực hiện lệnh `terraform apply`. Mã nguồn và kế hoạch được phê duyệt sẽ hóa thân thành các thành phần AWS vật lý.
4. **Hậu kiểm**: Trạng thái chi tiết của việc áp dụng mới tài nguyên sẽ được in thành bản báo cáo sơ kết của tiến trình GitHub.

![Terraform Apply](/asset/image/terraform-apply.png)

### Giai đoạn 4: Đồng bộ đường cơ sở (baseline synchronization)

- Khi hệ thống hạ tầng ứng dụng ổn định mà không nảy sinh lỗi sau Giai đoạn 3, mã nguồn trên nhánh `dev` sẽ được hợp nhất vòng về nhánh `master` thông qua một Pull Request tiếp theo. Bằng phương pháp này, nhánh `master` luôn theo sát tiến độ dự án theo thời gian thực và đóng vai trò làm điểm khôi phục bảo mật.

### Phụ lục: Quy trình thu hồi hạ tầng toàn cục (Infrastructure Destruction)

Nếu cần thiết gỡ bỏ toàn cục hệ sinh thái hạ tầng AWS phục vụ cho môi trường tương ứng, quy định kích hoạt tiến trình `Terraform Destroy` cung cấp màng lọc phòng hộ chuyên sâu.

1. Sinh viên bắt buộc kích hoạt tiến trình trực tiếp từ nhánh `dev`.
2. Hệ thống thiết lập rào cản nhân lực và yêu cầu sinh viên gõ thủ công chuỗi ký tự chính xác "destroy". Nếu cung cấp sai tham số, hệ thống sẽ tự động bãi bỏ.
3. Hệ thống chạy tuần tự `terraform plan -destroy` để dự báo cấu trúc cần phá hủy và chỉ sau đó, hạ lệnh phá hủy cấu trúc bằng câu lệnh `terraform destroy`, xóa tan hoàn toàn tài nguyên AWS có trong kế hoạch hạ tầng.

![Terraform Destroy](/asset/image/terraform-destroy.png)
