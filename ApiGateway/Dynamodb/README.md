 
# API Gateway x Dyanomdb example
Simple example for how to create an API Gateway to get data from DynamoDB.

## Quickstart 
Based on [AWS Workspace environment](https://github.com/LINKIT-Group/aws-workspace)

```shell
# ensure AWS credentials are in the HOST environment
# change the variables within brackets
export AWS_SECRET_ACCESS_KEY="${YOUR_AWS_SECRET_ACCESS_KEY}"
export AWS_ACCESS_KEY_ID="${YOUR_AWS_ACCESS_KEY_ID}"

# setting (default) region via environment is highly recommended
export AWS_DEFAULT_REGION="${YOUR_AWS_DEFAULT_REGION}"

# option A -- add when security credentials are temporary
# export AWS_SESSION_TOKEN="${YOUR_AWS_SESSION_TOKEN}"

# option B -- add to get new (temporary) credentials via assume-role
# export AWS_ROLE_ARN="${YOUR_AWS_ROLE_ARN}"

# start shell
make shell

# get code
[ ! -d cloudformation-samples ] && git clone https://github.com/LINKIT-Group/cloudformation-samples.git

# change directory
cd cloudformation-samples

# deploy
make stack template=ApiGateway/Dynamodb/template.yaml

# cleanup
make delete template=ApiGateway/Dynamodb/template.yaml
```

## test

replace `${EndpointUrl}` by the value retrieved from previous step

```shell
curl -X GET https://${EndpointUrl}/prod/dragons
curl -X POST https://${EndpointUrl}/prod/dragons -d '{"dragonName":"Mushu"}' -H "Content-Type: application/json"   
``` 
