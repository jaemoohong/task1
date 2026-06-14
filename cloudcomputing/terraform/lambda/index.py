import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def _response(status, body):
    # ALB(Lambda target) 통합 응답 형식
    return {
        "statusCode": status,
        "statusDescription": f"{status}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    """GET /v1/book?client_id=C001 -> DynamoDB(wsc-table) 조회."""
    params = event.get("queryStringParameters") or {}
    client_id = params.get("client_id")

    if not client_id:
        return _response(400, {"msg": "client_id is required"})

    result = table.get_item(Key={"client_id": client_id})
    item = result.get("Item")

    # 데이터가 존재하지 않을 시 404 + {"msg": "Item not found"} (요구사항 15)
    if not item:
        return _response(404, {"msg": "Item not found"})

    return _response(
        200,
        {
            "username": item.get("username"),
            "booking_id": item.get("booking_id"),
            "email": item.get("email"),
            "client_id": item.get("client_id"),
            "concert_name": item.get("concert_name"),
        },
    )
