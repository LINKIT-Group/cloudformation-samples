 # API Gateway x Dyanomdb example

Simple example for how to create an API Gateway to get data from DynamoDB.

## Deploy

To deploy this stack in your AWS environment, follow this [HowTo](https://github.com/LINKIT-Group/cloudformation-samples#deploy-a-stack).

Rootstack Template: ApiGateway/Dynamodb/template.yaml.

## Test

Replace `${EndpointUrl}` by the value retrieved from previous step

```shell
curl -X GET ${EndpointUrl}/dragons
curl -X POST ${EndpointUrl}/dragons -d '{"name":"Mushu","color":"red","size":"small","age":23}' -H "Content-Type: application/json"   
curl -X GET ${EndpointUrl}/dragon/${dragonId}
``` 
