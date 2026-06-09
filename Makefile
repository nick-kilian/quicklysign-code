.PHONY: bootstrap deploy-infra deploy-template open-coder clean

bootstrap:
	./scripts/bootstrap-gcp.sh

deploy-infra:
	cd infra/terraform && terraform init && terraform apply -auto-approve

deploy-template:
	./scripts/create-template.sh

open-coder:
	./scripts/open-coder.sh

clean:
	cd infra/terraform && terraform destroy -auto-approve
