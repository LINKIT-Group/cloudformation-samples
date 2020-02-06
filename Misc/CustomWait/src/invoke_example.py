# Copyright (c) 2020 Anthony Potappel - LINKIT, The Netherlands.
# SPDX-License-Identifier: MIT


import logging
import json
import boto3
import uuid
import urllib.request

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client('ssm')


def resource_status(payload):
    """Retrieve status of resource"""
    logger.info('all is well, payload=')
    logger.info(json.dumps( payload) )

    #raise ValueError('test-error')
    return {'keyresp': 'keyval'}


def create_resource(payload):
    """Create resource"""
    return {'Dummy': 'ResourceCreated'}


def update_resource(payload):
    """Update resource"""
    return {'Dummy': 'ResourceUpdated'}


def delete_resource(payload):
    """Delete resource"""
    return {'Dummy': 'ResourceDeleted'}


def handler(event, context):
    """Called by Lambda"""
    try:
        request_type = event['RequestType']

        function_map = {
            'Create': create_resource,
            'Update': update_resource,
            'Delete': delete_resource
        }

        if request_type in function_map:
            function = function_map[request_type]
        elif request_type == 'StatusUpdate':
            # bypass default routine if not directly called from CloudFormation
            try:
                response = resource_status(event['ResourceProperties'])
                # only send SUCCESS if response contains data
                if response:
                    logger.info(json.dumps(
                        {'ResponseStatus': 'SUCCESS', 'ResponseData': response}))
                    send_status(event, context, 'SUCCESS', response)
                else:
                    logger.info(json.dumps(
                        {'ResponseStatus': 'N/A', 'ResponseData': {}}))
            except Exception as e:
                logger.info(f'Unexpected RuntimeError:{str(e)}')
                send_status(event, context, 'FAILED', {'Message': str(e)})
            return {}
        else:
            raise ValueError(f'RequestType \'{request_type}\' invalid')

        send_cfnresponse(
             event, context, 'SUCCESS',
             function(event['ResourceProperties']),
             event['LogicalResourceId']
        )

    except Exception as e:
        send_cfnresponse(event, context, 'FAILED', {'Message': str(e)})


def send_status(event, context, response_status, response_data):
    """Send status by writing back the response to an S3 PreSigned URL"""
    try:
        url = event['ResponseUrlData']['Url']
        formdata = event['ResponseUrlData']['FormData']
        request_id = event['RequestId']

        """
        Encode formdata and data as multipart/form-data as per AWS spec for S3 PreSigned.
        While this is trivial in Python requests module, the request module is not
        included in the default library set. Using urllib.request allows re-use of this
        function without (pip-)build requirements, which is useful for simple custom resources.
        """

        # Generate random string to pass as boundary
        boundary = str(uuid.uuid4())
    
        # Encode base formdata (fields)
        flatten = lambda l: [item for sublist in l for item in sublist]
        content_items = flatten([
            [f'--{boundary}', f'Content-Disposition: form-data; name="{name}"', '', str(value)]
            for name, value in formdata.items()
        ])
    
        # Append (encoded) response data
        content_items = content_items + [
            f'--{boundary}',
            'Content-Disposition: form-data; name="file";',
            f'Content-Type: application/octet-stream',
            '',
            json.dumps({
                'ResponseStatus': response_status,
                'ResponseData': response_data,
                'RequestId': request_id
            }),
            f'--{boundary}--',
            ''
        ]
    
        # Merge items to a single body, separated by '\r\n'
        response_body = '\r\n'.join(content_items)

        headers = {
            'Content-Type': f'multipart/form-data; boundary={boundary}',
            'Content-Length': str(len(response_body)),
        }

        req = urllib.request.Request(
            url,
            headers=headers,
            data=response_body.encode(),
            method='POST'
        )

        with urllib.request.urlopen(req) as response:
            logger.info(f'Status code: {str(response.getcode())}')

    except Exception as e:
        logger.info(f'send_status(..) failed: {str(e)}')


def send_cfnresponse(
        event, context, response_status, response_data,
        physicalResourceId=None, noEcho=False
    ):
    """Send response back to CloudFormation
    Urllib.requests used instead of requests to increase portability
    """

    responseUrl = event['ResponseURL']
    logger.info(responseUrl)

    response_body = {
        'Status' : response_status,
        'Reason': f'See the details in CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': physicalResourceId or context.log_stream_name,
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'NoEcho': noEcho,
        'Data': response_data
    }

    json_responseBody = json.dumps(response_body)
    logger.info('Response body:\n' + json_responseBody)

    headers = {
        'content-type': '',
        'content-length': str(len(json_responseBody))
    }

    try:
        req = urllib.request.Request(
            responseUrl,
            data=json_responseBody.encode(),
            headers=headers,
            method='PUT'
        )
        with urllib.request.urlopen(req) as response:
            logger.info(f'Status code: {str(response.getcode())}')
    except Exception as e:
        logger.info(f'send_cfnresponse(..) failed executing requests.put(..): {str(e)}')
