# --------------------------------------------------------------------
# Copyright (c) 2020 Anthony Potappel - LINKIT, The Netherlands.
# SPDX-License-Identifier: MIT
# --------------------------------------------------------------------
ACCOUNT_INIT_STACKNAME := AccountInit
OUTPUTS_BUCKET := S3BucketName
OUTPUTS_ROLE := CloudFormationIAMRole

ifeq ($(profile),)
AWS_PROFILE = default
else
AWS_PROFILE = $(profile)
endif

ifneq ($(stackname),)
STACKNAME = $(stackname)
endif

ifeq ($(template),)
TEMPLATE = template.yaml
else
TEMPLATE = $(template)
endif

retrieve_variable = \
	$(eval $(1) = $(word 2,$(shell \
		aws cloudformation describe-stacks \
    		--profile $(AWS_PROFILE) \
        	--stack-name "$(ACCOUNT_INIT_STACKNAME)" \
        	--query 'Stacks[0].Outputs[?OutputKey==`$(2)`]' \
			--output text) \
	))

check_defined = \
    $(if $(value $1),,$(error Undefined $1, add $1=$${VALUE}))
check_account = \
    $(if $(value $1),,$(error Cant find: $(ACCOUNT_INIT_STACKNAME).Outputs.$2))

.PHONY: stack
stack:
	$(call check_defined,stackname)
	$(call retrieve_variable,BUCKET,$(OUTPUTS_BUCKET))
	$(call check_account,BUCKET,$(OUTPUTS_BUCKET))
	$(call retrieve_variable,ROLE,$(OUTPUTS_ROLE))
	$(call check_account,ROLE,$(OUTPUTS_ROLE))
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
	$(call check_defined,stackname)
	aws cloudformation delete-stack \
    	--profile $(AWS_PROFILE) \
        --stack-name $(STACKNAME)

.PHONY: account_init
account_init:
	aws cloudformation deploy \
		--profile $(AWS_PROFILE) \
		--stack-name $(ACCOUNT_INIT_STACKNAME) \
		--no-fail-on-empty-changeset \
		--capabilities CAPABILITY_IAM \
		--template-file Account/account-basic-serverless.yaml

.PHONY: clean
clean:
	[ ! -d ./build ] || rm -rf ./build