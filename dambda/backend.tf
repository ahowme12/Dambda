terraform {
  backend "s3" {
    bucket         = "dambda-bootstrap-bucket"          # S3 버킷 이름
    key            = "path/to/my/key/terraform.tfstate" # 버킷 내 저장 경로
    region         = "ap-northeast-2"                   # 버킷이 위치한 리전
    dynamodb_table = "terraform-lock-table"             # DynamoDB 테이블 이름
    encrypt        = true                               # 상태 파일 암호화
  }
  # 이 S3 버킷/DynamoDB 테이블은 dambda-bootstrap이 만들고 관리함 (dambda-bootstrap/main.tf).
  # 버킷이 지워지면 여기서 terraform init 자체가 안 되니 bootstrap을 먼저 재적용해야 함
}
