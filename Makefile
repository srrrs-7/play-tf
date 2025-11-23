.PHONY: init fmt validate plan apply

# 初期化
init:
	terraform init

# フォーマット確認
fmt:
	terraform fmt -check

# 検証
validate:
	terraform validate

# プラン確認
plan:
	terraform plan

# 適用
apply:
	terraform apply