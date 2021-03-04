 
# PostIt example on Lambda
Simple example of how to create a POST request on AWS Lambda.


## Deploy
To deploy this stack in your AWS environment, follow this [HowTo](https://github.com/LINKIT-Group/cloudformation-samples#deploy-a-stack). As the template-file input use: ApiGateway/PostIt/template.yaml.


## Test
```
replace ${EndpointUrl} by the value retrieved from previous step
curl -X POST 'https://${EndpointUrl}}/prod/message' -d 'Message=test'
```

