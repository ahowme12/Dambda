variable "region_name" {
  description = "리소스 이름 태그용 접두어 (홈 리전 기준)"
  type        = string
}

variable "replica_region" {
  description = "Global Table 복제 대상 리전 (예: us-east-1). pilot light DR이라도 데이터는 이 리전에 실시간 동기화됨"
  type        = string
}
