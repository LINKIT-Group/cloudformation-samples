 
# PostIt example on Lambda
Simple example of how to create a POST request on AWS Lambda.


## Quickstart 
Based on [AWS Workspace environment](https://github.com/LINKIT-Group/aws-workspace)
```
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
make deploy template=ApiGateway/PostIt/template.yaml

# cleanup
make delete template=ApiGateway/PostIt/template.yaml
```

## test
```
replace ${EndpointUrl} by the value retrieved from previous step
curl -X POST 'https://${EndpointUrl}}/prod/message' -d 'Message=test'
```

