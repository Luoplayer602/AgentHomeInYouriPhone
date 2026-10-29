#!/usr/bin/env python3
"""Run against iPhone socket, or a socket forwarded with SSH -L."""
import argparse
import json
import socket
import uuid


def call(path, method, params):
    identifier = str(uuid.uuid4())
    request = dict(id=identifier, method=method, params=params)
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(8)
        client.connect(path)
        # Fragment writes intentionally: framing must survive partial reads.
        frame = json.dumps(request).encode() + b'\n'
        for offset in range(0, len(frame), 7):
            client.sendall(frame[offset:offset + 7])
        with client.makefile('rb') as stream:
            reply = json.loads(stream.readline(256 * 1024))
    assert reply['id'] == identifier, reply
    return reply


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--socket', default='/var/mobile/Library/AgentHome/agent.sock')
    parser.add_argument('--write-test', action='store_true', help='Append a test message to history')
    args = parser.parse_args()
    info = call(args.socket, 'system.info', {})['result']
    assert 0 <= info['free_bytes'] <= info['total_bytes']
    assert info['uid'] == 501, info
    assert 'error' in call(args.socket, 'shell.exec', {'command': 'id'})
    assert 'error' in call(args.socket, 'chat.append', {'role': 'system', 'content': 'invalid'})
    assert isinstance(call(args.socket, 'chat.list', {})['result']['messages'], list)
    if args.write_test:
        marker = 'IPC smoke ' + str(uuid.uuid4())
        assert call(args.socket, 'chat.append', {'role': 'user', 'content': marker})['result']['saved']
        assert call(args.socket, 'chat.list', {})['result']['messages'][-1]['content'] == marker
    print('PASS: storage, peer UID, deny policy, validation, history' + (', persistence' if args.write_test else ''))


if __name__ == '__main__':
    main()
