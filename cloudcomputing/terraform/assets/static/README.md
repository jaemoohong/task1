# static assets

제공된 정적 배포 파일을 이 디렉토리에 그대로 배치하세요.
`terraform apply` 시 S3 버킷 `wsc-static-<ACCOUNT_ID>` 의 `static/` 프리픽스로
SSE-KMS 암호화되어 업로드됩니다. (s3.tf 의 aws_s3_object.static_files)
