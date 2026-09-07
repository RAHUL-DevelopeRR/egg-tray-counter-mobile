"""Call the documented Roboflow MCP endpoint without storing credentials."""
import argparse
import json
import os
from pathlib import Path
import httpx


def rpc(method, params):
    key = os.environ['ROBOFLOW_API_KEY']
    with httpx.Client(timeout=120) as client:
        response = client.post('https://mcp.roboflow.com/mcp',
            headers={'x-api-key': key, 'Accept': 'application/json, text/event-stream'},
            json={'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params})
        if response.is_error:
            raise RuntimeError(f'Roboflow MCP HTTP {response.status_code}')
        if 'text/event-stream' in response.headers.get('content-type', ''):
            messages = [json.loads(line[6:]) for line in response.text.splitlines() if line.startswith('data: ')]
            payload = next(m for m in messages if m.get('id') == 1)
        else:
            payload = response.json()
        if 'error' in payload:
            raise RuntimeError(str(payload['error']).replace(key, '[REDACTED]'))
        return payload['result']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--tool')
    parser.add_argument('--arguments', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = rpc('tools/list', {}) if args.list else rpc('tools/call', {'name': args.tool,
        'arguments': json.loads(args.arguments.read_text())})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('Saved', args.output, 'error:', result.get('isError', False))
