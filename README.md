
# CloudFormation Samples
This repository contains templates of CloudFormation. These can be used freely, as stand-alone parts or added to a larger cloud project. Or simply used as objects to study and explore. Additions that fit this repository are always welcomed.

## Rules of the Repository
Each individual stack must obey these rules:
1. its pathname should make sense, and (preferably) not change through time
2. completes succesfully as a stand-alone component -- i.e. modular without dependencies
3. completes succesfully by using the [Deploy a Stack](#deploy-a-stack) howto
4. when parameters are used, default inputs must be included
5. comply with the repository LICENSE
6. nested stacks are favored -- except for templates in [/Account/Init](#contents)

## Contents
This repository contains two classes of stacks;
#### 1. Account Stacks
Acccount Stacks are put in the **/Account** folder, and are meant to initialize an account with components that are **unique** within the account, and can or should only be **deployed once** per account. Examples are stacks that secure the account environment, or build support parts to be used in other stacks.

Stacks which are meant to **initialize** an account with essential support parts for CloudFormation to use (e.g. an S3 Bucket, an IAM Role) are put in the **/Account/Init** folder and must consist of a **single-template** (exception to Repository Rule #7). Init templates are meant for empty accounts.

#### 2. Everything Else
**All other stacks**, wether it's a product, service or a component are **grouped** in categories based on **functionality**. Current examples are Network, Security and ApiGateway. And for items that are to unique there is a Misc category. We expect the path to the root-stack to be 
**/${Category}/${Name}/template.yaml**

## Deploy a Stack

### Method I: AWS CLI
#### Default
```
# Package
aws cloudformation package \
    --profile $(AWS_PROFILE) \
    --template-file $(TEMPLATE) \
    --s3-bucket $(S3_BUCKET) \
    --s3-prefix $(S3_PREFIX) \
    --output-template-file ./build/template-generated.yaml

# Deploy
aws cloudformation deploy \
    --profile $(AWS_PROFILE) \
    --template-file ./build/template-generated.yaml \
    --role-arn $(IAM_ROLE) \
    --stack-name $(STACKNAME) \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
```
#### Init stacks only
```
aws cloudformation deploy \
    --profile $(AWS_PROFILE) \
    --template-file $(TEMPLATE) \
    --stack-name $(ACCOUNT_INIT_STACKNAME) \
    --no-fail-on-empty-changeset \
    --capabilities CAPABILITY_IAM
```

### Method II: Makefile

For convenience, this repository includes a Makefile that collects the required input arguments, and executes the AWS cli one-liners as stated.

#### Makefile Instructions
```
make help
```
```
Usage: make [TARGET] [EXTRA_ARGUMENTS]
Targets:
  stack         Build a CloudFormation stack
  delete        Delete a CloudFormation stack
  status        Get a status on a CloudFormation stack
  account       Create Inital AWS account configuration

Extra arguments:
stackname=${STACKNAME}, allowed-chars=[a-zA-Z0-9-]
template=${FILENAME}, CloudFormation template file, defaults to template.yaml
profile=${AWS_PROFILE}, if unset the default is used
```
#### Makefile Examples
Deploy a stack from this repository;
```
make stack stackname=MyApi template=ApiGateway/PostIt/template.yaml
```
Delete a stack in your AWS account -- be careful!
```
make delete stackname=MyApi
```
Initialize an account with this stack, this will get you an S3 Bucket and IAM Role to use;
```
make account template=Account/Init/account-basic-serverless.yaml
```
In any case, a different profile (i.e. not "default") can be passed to the AWS CLI, as long as it is available in your system (~/.aws) configuration;
```
make account profile=Developer template=Account/Init/account-basic-serverless.yaml
```
```
make stack profile=Developer stackname=MyApi template=ApiGateway/PostIt/template.yaml
```