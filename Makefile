# --------------------------------------------------------------------
# Copyright (c) 2020 Anthony Potappel - LINKIT, The Netherlands.
# SPDX-License-Identifier: MIT
# --------------------------------------------------------------------

NAME := CloudFormation Makefile
VERSION := 0.91.20200122
SHELL := /bin/bash

# profile=
_AWS_PROFILE = \
	$(if $(profile),$(profile),$(if $(AWS_PROFILE),$(AWS_PROFILE),default))

_GIT_REPOSITORY = $(if $(git),$(git),)


.PHONY: help
help: show_help
	@# target: help


.PHONY: deploy
deploy: set_environment pre_process stack post_process
	@# target: deploy
	@#  main target, deploy or update a stack via dependency targets:
	@#  set_environment, pre_process, stack and post_process
	@echo Deployed succesfully: $(_DEPLOYSTACK)


.PHONY: stack
stack: read_configuration package
	@# target: stack
	@#  ensure configuration is read, and stack is packaged
	@#	then deploys stack via AWS CLI
	@# verify if Configuration Outputs are complete and non-empty
	@([ ! -z $(ArtifactBucket) ] && [ ! -z $(IAMServiceRole) ]) || \
		(echo "Configuration Outputs incomplete"; exit 1)
	@# deploy Stack -- include parameters.ini if file exists
	( \
		[ -s "$(_BUILDDIR)"/parameters.ini ] && \
			params=--parameter-overrides\ $$(cat "$(_BUILDDIR)"/parameters.ini); \
		aws cloudformation deploy \
			--profile $(_AWS_PROFILE) \
	        --stack-name $(_DEPLOYSTACK) \
			--role-arn $(IAMServiceRole) \
			--template-file $(_BUILDDIR)/template.yaml \
	        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
			--tags \
				_CONFIGSTACK="$(_CONFIGSTACK)" \
				_GIT_REPOSITORY="$(if $(_GIT_REPOSITORY),$(_GIT_REPOSITORY),None)" \
			$${params} \
	)


.PHONY: set_workdir
set_workdir:
	@# target: set_workdir
	@#   setup a workingspace in ${PATH_OF_THIS_MAKEFILE}/.build
	$(eval _WORKDIR = $(shell \
    	cd $$(dirname "$${BASH_SOURCE[0]}" || echo ".") && pwd || echo ""))
	@[ -d .build ] || mkdir .build
	@tmpfile=.build/tmpfile; \
	   cat <<< "$${GIT_IGNORE}" >$${tmpfile}; \
	   sh $${tmpfile}; \
	   rm $${tmpfile}
	@cat <<< "$${CFN_FUNCTIONS}" >.build/cfn_functions.sh
	@cat <<< "$${GIT_FUNCTIONS}" >.build/git_functions.sh


.PHONY: set_environment_local
set_environment_local: set_workdir
	@# target: set_environment_local
	@#   _TEMPLATE points to a CloudFormation Template -- typically a Rootstack
	@#   set by passing template=${path} -- defaults to template.yaml
	@#   _TEMPLATE_ROOT points to the directory where _TEMPLATE is located
	$(eval _TEMPLATE = $(if $(template),$(template),template.yaml))
	$(eval _TEMPLATE_ROOT = $(shell dirname "$(_TEMPLATE)"))
ifneq ($(_GIT_REPOSITORY),)
	@# if git=${repository} is passed, pull from repository into .build/_GIT_ROOT
	@# can be used together with template={path} -- ${path} starts from _GIT_ROOT
	$(git-env) pull_from_git "$(_GIT_REPOSITORY)" "$(_WORKDIR)"
	$(eval _GIT_ROOT = $(shell \
		$(git-env) printf "$$(git_namestring "$(_GIT_REPOSITORY)" "$(_WORKDIR)")" \
	))
	$(if $(_GIT_ROOT),,$(error _GIT_ROOT))
	@# reconstruct _TEMPLATE_ROOT by putting _GIT_ROOT in front of it
	@# if no template={path} is given the latter (shell printf) part must be empty
	# feed_GIT_COMMIT to derive_stackname so it can be pushed to the end
	$(eval _TEMPLATE_ROOT = .build/$(_GIT_ROOT)$(shell \
		printf "$$(printf "$(_TEMPLATE_ROOT)" \
				   |sed 's/^[\/]*/\//g;s/^[\/\.]*$$//g')" \
	))
	@# idem. to _TEMPLATE
	$(eval _TEMPLATE = $(_TEMPLATE_ROOT)/$(shell basename "$(_TEMPLATE)"))
endif


.PHONY: set_environment_aws
set_environment_aws: set_workdir set_environment_local
	@# target: set_environment_aws
	@#   define name of _DEPLOYSTACK and _CONFIGSTACK based on _USERID and template
	@#   location (_TEMPLATE_ROOT). If sourced from GIT, append branchname and commit
	@# get last 8 chars of USERID
	$(eval _USERID = $(if $(userid),$(userid),$(shell \
        aws sts get-caller-identity \
          --query UserId \
          --output text \
          --profile "$(_AWS_PROFILE)" \
        |sed 's/:.*//g;s/None//g;s/[^a-zA-Z0-9_]//g' \
		|awk '{print substr($$0,length($$0) - 7,8)}' \
	)))
	$(if $(_USERID),,$(error _USERID))
	@# if stackname={} option is passed: use this name for DEPLOYSTACK
	@# else derive stackname from TEMPLATE_ROOT
	$(eval _DEPLOYSTACK = $(if $(stackname),$(stackname),$(shell \
	 	$(cfn-env) derive_stackname "$(_TEMPLATE_ROOT)" "$(_GIT_ROOT)" "$(_WORKDIR)" "$(_USERID)" \
	)))
	$(if $(_DEPLOYSTACK),,$(error _DEPLOYSTACK))
	$(eval _BUILDDIR = .build/$(_DEPLOYSTACK))
	$(eval _CONFIGSTACK = ConfigStack-$(_USERID))
	@[ -d $(_BUILDDIR) ] || mkdir $(_BUILDDIR)


.PHONY: set_environment
set_environment: set_environment_local set_environment_aws
	@# target: set_environment
	@#   wrapper to set local and  aws environment via dependency rules
	@#   note: keep three separate targets to ensure ordering is enforced


.PHONY: package
package: set_environment
	@# target: package
	@# 	package CloudFormation (nested) Stacks and Lambdas
	aws cloudformation package \
		--profile $(_AWS_PROFILE) \
		--template-file $(_TEMPLATE) \
		--s3-bucket $(ArtifactBucket) \
		--s3-prefix $(_DEPLOYSTACK) \
		--output-template-file $(_BUILDDIR)/template.yaml


.PHONY: pre_process
pre_process: set_environment read_configuration
	@# target: pre_process
	@#	calls ./pre_process.sh
	@# parameters.ini is sourced from _BUILDDIR as it may be auto-generated
	@# only copy when source is an update
	[ ! -s "$(_TEMPLATE_ROOT)"/parameters.ini ] || \
		(cp -u "$(_TEMPLATE_ROOT)"/parameters.ini "$(_BUILDDIR)/parameters.ini")
	@# run pre_process.sh if it exist
	[ ! -s "$(_TEMPLATE_ROOT)/pre_process.sh" ] || \
	( \
		cd "$(_TEMPLATE_ROOT)" && \
        export AWS_PROFILE=$(_AWS_PROFILE); \
        export CONFIGURATION_BUCKET=$(ArtifactBucket); \
        export STACKNAME=$(_DEPLOYSTACK); \
        export BUILDDIR=$(_WORKDIR)/$(_BUILDDIR); \
		echo "RUNSCRIPT:$(_TEMPLATE_ROOT)/pre_process.sh"; \
		bash ./pre_process.sh; \
		exit_code="$$?"; \
		echo "FINISHED:$(_TEMPLATE_ROOT)/pre_process.sh (exit=$${exit_code})"; \
		exit $${exit_code}; \
	)


.PHONY: post_process
post_process: set_environment read_configuration
	@# target: post_process
	@#	exports Stack Outputs to environment
	@#	calls ./post_process.sh
	$(eval _STACK_OUTPUTS = $(shell \
		aws cloudformation describe-stacks \
			--profile $(_AWS_PROFILE) \
			--stack-name $(_DEPLOYSTACK) \
			--query 'Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}' \
			--output text 2>/dev/null |awk -F '\t' '{print $$1"="$$2}' |sed 's/^None=$$//g'; \
	))
	[ ! -s "$(_TEMPLATE_ROOT)/post_process.sh" ] || \
	( \
		cd "$(_TEMPLATE_ROOT)" && \
        export AWS_PROFILE=$(_AWS_PROFILE); \
        export CONFIGURATION_BUCKET=$(ArtifactBucket); \
        export STACKNAME=$(_DEPLOYSTACK); \
        export BUILDDIR=$(_WORKDIR)/$(_BUILDDIR); \
		[ ! -z "$(_STACK_OUTPUTS)" ] && export $(_STACK_OUTPUTS); \
		echo "RUNSCRIPT:$(_TEMPLATE_ROOT)/post_process.sh"; \
		bash ./post_process.sh; \
		exit_code="$$?"; \
		echo "FINISHED:$(_TEMPLATE_ROOT)/post_process.sh (exit=$${exit_code})"; \
		exit $${exit_code}; \
	)


.PHONY: init_configuration
init_configuration: set_environment
	@# target: init_configuration
	@#	deploy Configuration Stack if no matching version is found,
	@#	determined by output check on ArtifactBucket.
	@#	init is skipped with noconfig=true variable set when called via make clean
ifneq ($(noconfig),true)
	$(cfn-env) \
	create_configuration_template || exit 1; \
	output=$$(configstack_output $(_CONFIGSTACK) "ArtifactBucket" || true); \
	[ ! -z $${output} ] || \
		aws cloudformation deploy \
			--profile $(_AWS_PROFILE) \
			--no-fail-on-empty-changeset \
			--template-file .build/configstack.yaml \
			--capabilities CAPABILITY_NAMED_IAM \
			--stack-name $(_CONFIGSTACK) \
			--parameter-overrides \
				RoleName=ConfigStackDeployRole-$(_USERID)
endif


.PHONY: read_configuration
read_configuration: init_configuration
	@# target: read_configuration
	@#	retrieve configuration vars ArtifactBucket and IAMServiceRole,
	@#	set vars in Makefile environment so other targets can access them
	$(eval ArtifactBucket = $(shell \
		$(cfn-env) printf $$(configstack_output $(_CONFIGSTACK) ArtifactBucket) \
	))
	$(if $(ArtifactBucket),,$(error ConfigStack missing parameter: ArtifactBucket))
	$(eval IAMServiceRole = $(shell \
		$(cfn-env) printf $$(configstack_output $(_CONFIGSTACK) IAMServiceRole) \
	))
	$(if $(IAMServiceRole),,$(error ConfigStack missing parameter: IAMServiceRole))


.PHONY: delete
delete: set_environment read_configuration
	@# target=delete:
	@#	get IAMServiceRole (supplied by Configuration Stack) and delete stack
	@#	if no Configuration Stack exists, one is created (init_configuration)
	@$(cfn-env) delete_stack $(_DEPLOYSTACK) $(IAMServiceRole)
	@echo Stack is Deleted: $(_DEPLOYSTACK)


.PHONY: delete_full
delete_full: delete
	@# target=delete_full
	@#	calls delete target via dependency
	@#  removes Configuration Stack and .build dir
	@if [ -z "$(ArtifactBucket)" ] && [ -z "$(IAMServiceRole)" ];then \
		echo "Nothing to erase"; \
	else \
		$(cfn-env) delete_stack_configuration "$(_CONFIGSTACK)"; \
		echo Stack and Configuration are Deleted: $(_DEPLOYSTACK); \
	fi


.PHONY: clean
clean:
	@# target=clean:
	@#  delete local ./.build directory
	@#	add stack=$${DIRECTORY} to also delete stack data
	# Note that configstack cant be deleted as long as there is one stack
#ifneq ($(_TEMPLATE),)
	@# if either _TEMPLATE or _GIT_REPOSITORY is set, do full stack delete
ifneq ($(filter %,$(_TEMPLATE) $(_GIT_REPOSITORY)),)
	make -f "$(lastword $(MAKEFILE_LIST))" delete_full \
		git="$(_GIT_REPOSITORY)" \
		template="$(_TEMPLATE)" \
		noconfig="true"
endif
	rm -rf ./.build


.PHONY: pre
pre: pre_process
	@# target=pre:
	@#	calls target pre_process
	@echo PreProcess ran succesfully: $(_TEMPLATE_ROOT)/pre_process.sh


.PHONY: post
post: post_process
	@# target=post:
	@#	calls target post_process
	@echo PostProcess ran succesfully: $(_TEMPLATE_ROOT)/post_process.sh
	@[ -z "$(_STACK_OUTPUTS)" ] || \
	( \
		echo -e "\e[92mStackOutputs":; \
		for output in $(_STACK_OUTPUTS);do \
			echo -e "\e[37m$$(printf $${output} |sed 's/=/\ =\ /g')"; \
		done \
	)

.PHONY: list
list: set_environment_aws
	@# target=list
	@# iterate over list with describe
	aws cloudformation list-stacks \
		--profile $(_AWS_PROFILE) \
		--no-paginate --query \
			'StackSummaries[?StackStatus!=`DELETE_COMPLETE`] | [?ParentId==`null`] | [?starts_with(StackName,`$(_USERID)-`)].StackName' \
		 --output text


.PHONY: whoami
whoami:
	@# target=whoami:
	@#   verify AWS profile used by this Makefile
	aws sts get-caller-identity --profile "$(_AWS_PROFILE)"


.PHONY: version
version:
	@# target=version:
	@echo Version=$(VERSION)


.PHONY: license
license: version
	@# target=license:
	@echo License notice:
	@cat <<< "$${LICENSE}"


.PHONY: check
check: set_environment
	@echo workdir=$(_WORKDIR)
	@echo templateroot=$(_TEMPLATE_ROOT)
	@echo configstack=$(_CONFIGSTACK)
	@echo deploystack=$(_DEPLOYSTACK)
	@echo template=$(_TEMPLATE)
	@echo TODO List:
	@echo "- (continuous) -- refactor and improve doc-strings"
	@echo "- make clean should delete all related stacks, determined by: make list"
	@echo "- clean s3 config folder as part of stack delete"
	@echo "- if stack is protected, skip deletion (vs. giving an error now)"
	@echo "- test, with cfn-python-lint"
	@echo "- check if tools exist on host, e.g. git and cfn-python-lint -- or error"


export CFN_FUNCTIONS
export GIT_FUNCTIONS
export GIT_IGNORE
export LICENSE


define cfn-env
	source ./.build/cfn_functions.sh; \
	exit_on_error
endef

define git-env
	source .build/git_functions.sh; \
	exit_on_error
endef


define CFN_FUNCTIONS
# repetively called shell functions are added here, contents are exported
# to environment and written to file, and sourced via cfn-env.
#
# vars set via Makefile: _AWS_PROFILE, _STACKNAME_CONFIG, _STACKNAME,
#  _REPOSITORY, _WORKDIR

set -o pipefail

function exit_on_error(){
    "$$@"
    ret=$$?
    if [ ! $$ret -eq 0 ];then
        >&2 echo "ERROR: Command [ $$@ ] returned $$ret"
        exit $$ret
    fi	
}

function configstack_output(){
	# retrieve output value by passing name of OutputKey as input argument
	# input: {STACKNAME} {KEY}
    aws cloudformation describe-stacks \
		--profile $(_AWS_PROFILE) \
		--stack-name "$${1}" \
	    --query 'Stacks[0].Outputs[?OutputKey==`'$${2}'`].OutputValue' \
	    --output text 2>/dev/null || return $$?
}

function stack_status(){
	# retrieve status of stack by passing unique stack-name as input argument
	# input: {STACKNAME}
    aws cloudformation list-stacks \
	    --profile $(_AWS_PROFILE) \
		--no-paginate \
		--query 'StackSummaries[?StackName==`'$${1}'`].[StackStatus][0]' \
		--output text
    return $$?
}

function stack_delete_waiter(){
	# configure waiter for stack deletion by passing stack-name as input argument
    # allow up to ~15 minutes for stack deletion
    # if more time is needed, re-check architecture before raising timeout
    max_rounds=300
    seconds_per_round=3
    round=0

    while [ $${round} -lt $${max_rounds} ];do
        stack_status=$$(stack_status "$${1}")
        echo "WAITER ($${round}/$${max_rounds}):$${1}:$${stack_status}"

        case "$${stack_status}" in
        	DELETE_COMPLETE)	return 0;;
        	*_FAILED)	return 1;;
        	*_IN_PROGRESS|*_COMPLETE);;
        	*)	echo "Stack not found"; return 0;;
        esac

        round=$$[$${round}+1]
        sleep $${seconds_per_round}
    done
    return 1
}

function delete_stack(){
	# delete stack -- role_arn should be passed as input argument
	# input: {STACKNAME} {ROLE_ARN}
    #role_arn="$${1}"

    # return direct ok if application stack is deleted, or not found
    stack_status=$$(stack_status "$${1}")
    [ -z "$${stack_status}" ] && return 0
    [ "$${stack_status}" == "DELETE_COMPLETE" ] \
		|| [ "$${stack_status}" == "None" ] && return 0

    aws cloudformation delete-stack --profile $(_AWS_PROFILE) \
        --stack-name "$${1}" \
		--role-arn "$${2}"
    stack_delete_waiter "$${1}" || return 1
    return 0
}

function delete_stack_configuration(){
	# delete stack_configuration and wait -- no input arguments
	# input: {CONFIGSTACK}
    aws cloudformation delete-stack --profile $(_AWS_PROFILE) \
        --stack-name "$${1}" 
    stack_delete_waiter "$${1}" || return 1
    return 0
}

function derive_stackname(){
	# derive stackname from name of template directory/ repository
	# input: {_TEMPLATE_ROOT} {_GIT_ROOT} {_WORKDIR} {_USERID}
	# use _TEMPLATE_ROOT and strip of leading and trailing slashes
	# select last, or last two (directory-name) columns
	# if result leads to "." (=working directory): use its name
	# dirname "/pg/abc/def/template.yaml" |sed 's/^\///g;s/\/$$//g' | awk -F '/' '{print NF == 1 ? $NF : $(NF - 1)"/"$(NF)}'
	# UserID{8}-Name{0:80}-Branch{29:*}-Commit{8:*}
    # |awk -F '/' '{print NF == 1 ? $$1 : $$(NF - 1)"/"$$(NF)}'
    if [ ! -z "$${2}" ];then
        # if _GIT_ROOT is passed: _TEMPLATE_ROOT is GIT-based
		# strip off commit -- this is (re-)appended to the end of the string in step_1
		# this gives repositories with deep nested templates more human-readable names
		branch_commit="$$(printf "$${2}" |awk -F "--" '{print $$2"--"$$3}')"
		step_0="$$(\
			printf "$${1}" |sed 's/--'$${branch_commit}'$$//g;s/--'$${branch_commit}'\///g')"
    else
		# no adjustments, define commit as empty string
		branch_commit=""
        step_0="$${1}"
    fi

    step_1="$$(\
    	printf "$${step_0}" \
    	|sed 's/^[\/\.]*//g;s/\/$$//g;s/^\.build\///g' \
    	|awk -F '/' '{
			if ( NF == 0 );
			else if ( NF == 1 ) print $$1;
			else if ( NF == 2) print $$(NF - 1)"/"$$(NF);
			else print $$1"_-_"$$(NF - 1)"/"$$(NF);}' \
	)" || return $$?

    if [ -z "$${step_1}" ];then
		step_1=$$(basename "$${3}") || return $$?
	fi
	[ ! -z "$${branch_commit}" ] && step_1="$${step_1:0:80}-$${branch_commit}"
	# remove non [a-zA-Z-] chars and leading/ trailing dash
	# uppercase first char for cosmetics
    step_2=$$(\
    	printf "$${step_1}" \
    	|sed 's/[^a-zA-Z0-9_]/-/g;s/-\+/-/g;s/^-//g;s/-$$//g;s/_-_/--/g' \
        |awk '{for (i=1;i<=NF;i++) $$i=toupper(substr($$i,1,1)) substr($$i,2)} 1' \
    ) || return $$?
	# if result from step_2 is empty: paste in Unknown-StackName
	# elif char-length >127-9 (127=max naming length on AWS, 9=partial USERID + -)
	#   attain first 109, and last 8 chars (unique commitIDs), separated by double-dash
	#   ensure no leading or trailing dashes remain
	# else no further modifications
    if [ -z "$${step_2}" ];then
    	step_3="Unknown-StackName"
    elif [ "$${#step_2}" -gt 119 ];then
    	step_3a=$$(\
			printf $${step_2:0:109} \
			|sed s'/^-//g;s/-$$//g' \
		) || return $$?
    	step_3b=$$(\
			printf $${step_2:$$(($${#step_2} - 8)):8} \
			|sed s'/^-//g;s/-$$//g' \
		) || return $$?
    	step_3=$${step_3a}--$${step_3b}
    else
		step_3="$${step_2}"
    fi
	# last 8 chars of USERID + result from step_3
    printf "$${4}-$${step_3}"
	return $$?
}


function create_configuration_template(){

cat << CONFIGURATION_STACK >./.build/configstack.yaml
AWSTemplateFormatVersion: 2010-09-09
Transform: AWS::Serverless-2016-10-31
Description: ConfigurationStack
Parameters:
  RoleName:
    Type: String
Resources:
  Bucket:
    Type: AWS::S3::Bucket
    Properties:
      VersioningConfiguration:
        Status: Enabled
      LifecycleConfiguration:
        Rules:
        - ExpirationInDays: 30
          Status: Disabled
        - NoncurrentVersionExpirationInDays: 7
          Status: Enabled
      BucketEncryption:
        ServerSideEncryptionConfiguration:
        - ServerSideEncryptionByDefault:
            SSEAlgorithm: AES256
  ServiceRoleForCloudFormation:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Ref RoleName
      AssumeRolePolicyDocument:
        Statement:
        - Effect: Allow
          Principal:
            Service:
            - cloudformation.amazonaws.com
          Action:
          - sts:AssumeRole
      Policies:
      - PolicyName: AdministratorAccess
        PolicyDocument:
          Version: 2012-10-17
          Statement:
          - Effect: Allow
            Action: "*"
            Resource: "*"
  BucketEmptyLambda:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.7
      Handler: index.handler
      Policies:
      - Version: 2012-10-17
        Statement:
          - Effect: Allow
            Action:
            - s3:List*
            - s3:DeleteObject
            - s3:DeleteObjectVersion
            Resource:
            - !Sub \$${Bucket.Arn}
            - !Sub \$${Bucket.Arn}/*
      InlineCode: |
          import boto3
          import cfnresponse

          s3 = boto3.resource('s3')

          def empty_s3(payload):
              bucket = s3.Bucket(payload['BucketName'])
              bucket.object_versions.all().delete()
              return {}

          def handler(event, context):
              try:
                  if event['RequestType'] in ['Create', 'Update']:
                      # do nothing
                      cfnresponse.send(event, context, cfnresponse.SUCCESS,
                                       {}, event['LogicalResourceId'])
                  elif event['RequestType'] in ['Delete']:
                      response = empty_s3(event['ResourceProperties'])
                      cfnresponse.send(event, context, cfnresponse.SUCCESS, response)

              except Exception as e:
                  cfnresponse.send(event, context, "FAILED", {"Message": str(e)})
  CustomCrlBucketEmpty:
    Type: Custom::CrlBucketEmpty
    Properties:
      ServiceToken: !GetAtt BucketEmptyLambda.Arn
      BucketName: !Ref Bucket
Outputs:
  ArtifactBucket:
    Value: !Ref Bucket
  IAMServiceRole:
    Value: !GetAtt ServiceRoleForCloudFormation.Arn
CONFIGURATION_STACK
}
endef

define GIT_FUNCTIONS

set -o pipefail

function exit_on_error(){
    "$$@"
    ret=$$?
    if [ ! $$ret -eq 0 ];then
        >&2 echo "ERROR: Command [ $$@ ] returned $$ret"
        exit $$ret
    fi	
}
function git_destination(){
    # Return clean repository name -- filter out .git and any parameters
	# input: {GIT_REPOSITORY} {WORKDIR}
    var=$$( 
        basename "$${1}" \
		|sed 's/?.*//g;
        	  s/\.git$$//g;
			  s/[^a-zA-Z0-9_-]//g'
    )
	# if repository is a URL, lowercase
	# urlcheck = sed -n '/^\(http\|ssh\)[s]\?:\/\/\|.*?.*/p'))
	# convert the url part to lowercase to prevent input/ typo mistakes
	# |awk '{print tolower($$0)}' 
	[ ! -z "$${var}" ] && printf "$${var}" \
		|| printf $$(basename "$${2}")
	return $$?
}

function git_parameter(){
    # Return parameter from GIT URL -- return _default if not found
	repository="$${1}"
    filter="$${2}"
    default="$${3}"
    parameter_value=""

    # filter parameter string from url
    # for OSX compatibility: dont use '\|' in sed
    parameter_str=$$(
        basename "$${repository}" \
        |sed 's/?/__/g;
              s/$$/__/g;
              s/\(__[-a-zA-Z0-9=&]*__\)/__\1/g;' \
        |sed -n 's;.*\(__.*__\);\1;p'
    ) || return $$?

    # filter out specific parameter
    if [ ! -z "$${parameter_str}" ];then
		parameter_value=$$(
            printf "$${parameter_str}" \
            |sed -n 's;.*\('$${filter}'=[A-Za-z0-9-]*\).*;\1;p' \
            |sed 's/^'$${filter}'=//g'
        ) || return $$?
	fi

    # if no match, return default
    [ -z "$${parameter_value}" ] && parameter_value="$${default}"
	printf "$${parameter_value}"
    return $$?
}


function git_namestring(){
    # Return a string formatted as RepoName--Branch--Commit
	repository="$${1}"
	workdir="$${2}"
    rname="$$(git_destination "$${repository}" "$${workdir}")" || return $$?
    branch="$$(git_parameter "$${repository}" branch master)" || return $$?
    commit="$$(git_parameter "$${repository}" commit latest)" || return $$?
	if [ "$${commit}" = "latest" ];then
		remote=$$(printf "$${repository}" |sed 's/?.*//g') || return $$?
		# always return true to 
		heads=$$(git ls-remote "$${remote}" refs/heads/"$${branch}")
		commit=$$(printf "$${heads}" |awk '{print $$1}')
		if [ -z "$${commit}" ];then
			>&2 echo "ERROR: cant find branch \"$${branch}\" on \"$${remote}\""
			return 1
		fi
	fi
	printf "$${rname}--$${branch}--$${commit}"
    return $$?
}

function pull_from_git(){
    # pull repository and checkout to specified branch tag/commit
	repository="$${1}"
	workdir="$${2}"
    branch=$$(git_parameter "$${repository}" branch master) || return $$?
    commit=$$(git_parameter "$${repository}" commit) || return $$?
    remote=$$(printf "$${repository}" |sed 's/?.*//g') || return $$?
    destination=.build/"$$(git_namestring "$${repository}" "$${workdir}")" || return $$?
    # fetch if exist or clone if new
    [ -e "$${destination}/.git" ] \
        &&  (
                cd "$${destination}" && git fetch
            ) \
        || git clone -b "$${branch}" "$${remote}" "$${destination}" \
        || return $$?

    # move to correct position in GIT repository
    if [ ! -z "$${commit}" ];then
        # point to given branch commit/tag 
        cd "$${destination}" \
            && git checkout -B $${branch} $${commit} \
            || return $$?
    else
        # point to latest in branch
        cd "$${destination}" \
            && git checkout -B $${branch} \
            && git pull \
            || return $$?
    fi
    return $$?
}
endef

define GIT_IGNORE
    cat << IGNORE_FILE_BUILD >./.build/.gitignore 
# ignore everything under build
# .build/* should only contain generated data
# this file is auto-generated by Makefile
*
IGNORE_FILE_BUILD
endef

define LICENSE
Copyright (c) 2020 Anthony Potappel - LINKIT, The Netherlands.
SPDX-License-Identifier: MIT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
endef

.PHONY: show_help
show_help:
	@echo '$(NAME) - v$(VERSION) (major.minor.lastrevision)'
	@echo '  Makefile to Deploy, Update or Delete Stacks on AWS via CloudFormation'
	@echo 'Usage:'
	@echo '  command: make [TARGET] [CONFIGURATION]'
	@echo ''
	@echo 'Targets:'
	@echo '  deploy             Deploy or Update a Stack (includes Pre- and PostProcess)'
	@echo '  delete             Delete a Stack (excludes related configuration data)'
	@echo '  clean              Delete local ./.build directory'. Add stacks=destroy to
	@echo '                     destroy all (un-protected) Stacks starting with UserId-'
	@echo '                     wipe Stack related configuration data'
	@echo '  pre                Run $${TEMPLATE_ROOT}/pre_process.sh if file exists'
	@echo '  post               Run $${TEMPLATE_ROOT}/post_process.sh if file exists'
	@echo '  help               Show this help'
	@echo ''
	@echo 'Configuration:'
	@echo 'profile=$${AWS_PROFILE}     Set AWS CLI profile (default: "default", '
	@echo '                             check available profiles: "aws configure list")'
	@echo 'template=$${_TEMPLATE}      Name of CloudFormation rootstack template,'
	@echo '                            (default: "./template.yaml")'
	@echo 'git=$${GITURL || GITDIR}    Optionally retrieve stack from Git'
	@echo 'stackname=$${STACKNAME}     Set STACKNAME manually (not recommended)'
	@# echo 'noconfig=true            Skips building Configuration Stack'
	@# echo '                         option hidden, used via "make clean stack={}"'
