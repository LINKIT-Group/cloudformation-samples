# --------------------------------------------------------------------
# Copyright (c) 2020 Anthony Potappel - LINKIT, The Netherlands.
# SPDX-License-Identifier: MIT
# --------------------------------------------------------------------
ACCOUNT_INIT_STACKNAME := AccountInit
OUTPUTS_BUCKET := S3BucketName
OUTPUTS_ROLE := CloudFormationIAMRole

STACKNAME_DEFAULT :=

ifeq ($(profile),)
AWS_PROFILE = default
else
AWS_PROFILE = $(profile)
endif

ifeq ($(template),)
TEMPLATE = template.yaml
else
TEMPLATE = $(template)
endif

ifneq ($(stackname),)
STACKNAME = $(stackname)
endif


check_template = \
	$(if $(wildcard $(TEMPLATE)),,\
	$(error "Cant find template: $(TEMPLATE)"))

retrieve_account = \
	$(eval $1 = $(word 2,$(shell \
		aws cloudformation describe-stacks \
    		--profile $(AWS_PROFILE) \
        	--stack-name "$(ACCOUNT_INIT_STACKNAME)" \
        	--query 'Stacks[0].Outputs[?OutputKey==`$(2)`]' \
			--output text) \
	)) $(if $(value $1),,$(error Cant find: $(ACCOUNT_INIT_STACKNAME).Outputs.$2))
retrieve_input = \
	$(if $(value $1),,\
	$(eval $1 = $(shell read -p "Type in $(2):" tmp;echo $$tmp)) \
	$(if $(value $1),,$(error Undefined $1, add $1=$${VALUE})))


.PHONY: help
help:
	@echo ''
	@echo 'Usage: make [TARGET] [EXTRA_ARGUMENTS]'
	@echo 'Targets:'
	@echo '  stack    	Build a CloudFormation stack'
	@echo '  delete  	Delete a CloudFormation stack'
	@echo '  status  	Get a status on a CloudFormation stack'
	@echo '  account	Create Inital AWS account configuration'
	@echo ''
	@echo 'Extra arguments:'
	@echo 'stackname=$${STACKNAME}, allowed-chars=[a-zA-Z0-9-]'
	@echo 'template=$${FILENAME}, CloudFormation template file, defaults to template.yaml'
	@echo 'profile=$${AWS_PROFILE}, if unset the default is used'


.PHONY: stack
stack:
	$(call check_template)
	$(call retrieve_input,STACKNAME,stackname)
	$(call retrieve_account,BUCKET,$(OUTPUTS_BUCKET))
	$(call retrieve_account,ROLE,$(OUTPUTS_ROLE))
	@[ -d ./build ] || mkdir -p ./build
	# package
	aws cloudformation package \
		--profile $(AWS_PROFILE) \
		--template-file $(TEMPLATE) \
		--s3-bucket $(BUCKET) \
		--s3-prefix cfn \
		--output-template-file ./build/template-generated.yaml
	# deploy
	aws cloudformation deploy \
		--profile $(AWS_PROFILE) \
		--template-file ./build/template-generated.yaml \
		--role-arn $(ROLE) \
		--stack-name $(STACKNAME) \
		--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND

.PHONY: delete
delete:
	$(call retrieve_input,STACKNAME,stackname)
	aws cloudformation delete-stack \
    	--profile $(AWS_PROFILE) \
        --stack-name $(STACKNAME)

.PHONY: status
status:
	$(call retrieve_input,STACKNAME,stackname)
	aws cloudformation describe-stacks \
    	--profile $(AWS_PROFILE) \
        --stack-name $(STACKNAME)

.PHONY: account
account:
	$(call check_template)
	aws cloudformation deploy \
		--profile $(AWS_PROFILE) \
		--stack-name $(ACCOUNT_INIT_STACKNAME) \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_IAM \
		--template-file $(TEMPLATE)

.PHONY: clean
clean:
	[ ! -d ./build ] || rm -rf ./build