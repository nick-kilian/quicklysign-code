.PHONY: bootstrap deploy-control-plane create-template open-coder forward plan fmt validate destroy

bootstrap: ## Enable GCP APIs, verify auth
	./scripts/bootstrap-gcp.sh

deploy-control-plane: ## Terraform apply: VPC, Cloud SQL, control plane VM
	./scripts/deploy-coder.sh

create-template: ## Push the quicklysign-dev template to Coder
	./scripts/create-template.sh

open-coder: ## Open the Coder dashboard
	./scripts/open-coder.sh

forward: ## Mirror a workspace's app/admin ports to localhost (follows dynamic devcontainer ports)
	./scripts/forward-ports.sh

plan: ## Terraform plan only
	terraform -chdir=infra/terraform init -input=false
	terraform -chdir=infra/terraform plan

fmt: ## Format all Terraform
	terraform -chdir=infra/terraform fmt -recursive
	terraform -chdir=coder/templates/quicklysign-dev fmt

validate: fmt ## Validate Terraform + shell syntax
	terraform -chdir=infra/terraform validate
	bash -n scripts/*.sh coder/templates/quicklysign-dev/scripts/*

destroy: ## Tear everything down (interactive confirm; Cloud SQL is deletion-protected)
	terraform -chdir=infra/terraform destroy
