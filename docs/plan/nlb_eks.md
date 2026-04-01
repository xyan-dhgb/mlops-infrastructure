# MỐI QUAN HỆ LOGIC GIỮA TÀI NGUYÊN AWS NLB VÀ KUBERNETES NAMESPACE

## Cách hoạt động

- NLB không thật sự "nằm trong" namespace của EKS. Namespace là một cơ chế phân vùng logic của Kubernetes tồn tại trong tầng **control plane** (etcd). Thứ nằm trong namespace chỉ là Kubernetes Service object - một bản ghi metadata mô tả ý định tạo load balancer.

- Bản thân **AWS Network Load Balancer** là tài nguyên hạ tầng thuộc tầng **AWS**, được triển khai trên hai public subnet ở hai Availability Zone khác nhau để đảm bảo tính sẵn sẵng cao. NLB được tạo ra bởi **AWS Load Balancer Controller** - một Pod chạy trong cụm EKS có quyền gọi AWS API. Khi nhận ra có Service kiểu LoadBalancer mới, controller sẽ gọi API để tạo NLB, rồi ghi địa chỉ DNS của NLB đó ngược lại vào trường status.loadBalancer.ingress của Service object.

- Như vậy, mối quan hệ đúng là: Service object trong namespace là "đại diện" (proxy) của NLB trong thế giới Kubernetes, còn NLB vật lý hoàn toàn nằm ngoài cụm, do AWS quản lý và vận hành độc lập.

## Liên hệ ví dụ thực tế

### Đặt món ăn qua app GrabFood

- Đơn hàng trên app (nằm trong tài khoản Grab) = Kubernetes Service object trong namespace
- Tài xế Grab ngoài đường thực sự giao đồ ăn = AWS NLB nằm trên hạ tầng thật.
- Hệ thống điều phối của Grab (nhận đơn → tìm tài xế → phân công) = AWS Load Balancer Controller

### Khi đặt đơn

- Đơn hàng xuất hiện trong app (trong namespace), nhưng đó chỉ là thông tin, không phải tài xế thật.
- Hệ thống Grab gọi ra ngoài để tìm và phân công tài xế thật ngoài đường.
- Tài xế đến giao hàng, hoạt động hoàn toàn độc lập, không "nằm trong" app.
- App chỉ cập nhật trạng thái "tài xế đang đến, biển số ABC-123", đó là lúc Service object được ghi DNS của NLB vào.

### Điểm mấu chốt

- App Grab không chứa tài xế, nó chỉ chứa thông tin về tài xế.
- Tương tự, namespace không chứa NLB, nó chỉ chứa thông tin về NLB.
