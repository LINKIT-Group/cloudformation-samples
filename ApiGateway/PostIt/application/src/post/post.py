
import time
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _raise(exception, error):
    """raises used by lambda functions"""
    raise exception(error)


value_get = lambda dictionary, key: dictionary[key] if key in dictionary else ""
max_length = lambda s, l: s if len(s[:l+1]) <= l else _raise(ValueError, f"String to long (>{l})")


def message(payload, context):
    """Return Message from payload, and some extra context vars
    bad code example used for testing purposes"""
    if 'Message' not in payload:
        raise ValueError("Message not defined in payload")

    if payload['Message'] == "_bad_python_":
        return this_is_bad_python_code

    return {
      "EventTime": int(time.time() * 10**3),
      "SourceIP": max_length(value_get(context['identity'], 'sourceIp'), 39),
      "UserAgent": max_length(value_get(context['identity'], 'userAgent'), 512),
      "Message": max_length(payload['Message'], 10)
    }


def handler(event,_):
    """Main function called by AWS Lambda"""
    try:
        response = message(
            event['body'],
            event['requestContext']
        )
        return response
    except ValueError as error:
        raise ValueError(f"ValueError__{error}")
    except Exception as error:
        logger.error("Exception caught in handler", exc_info=True)
        raise Exception(f"Exception__Oops, something went wrong")
