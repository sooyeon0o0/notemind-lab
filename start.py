#!/usr/bin/env python3
"""Offline-first, foreground launcher for the course's vLLM / vLLM-Metal APIs."""
from __future__ import annotations
import argparse
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import urllib.parse

ROOT = Path(__file__).resolve().parent


def load_env(path):
    """Literal dotenv values only: never evaluate substitutions or shell commands."""
    result = {}
    if path.is_file():
        for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line.startswith('export '):
                line = line[7:].strip()
            key, sep, value = line.partition('=')
            if not sep or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key.strip()):
                raise ValueError(f'.env {number}행 형식 오류 (내용은 숨김)')
            value = value.strip()
            if len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]:
                value = value[1:-1]
            else:
                value = re.split(r'\s+#', value, maxsplit=1)[0].rstrip()
            result[key.strip()] = value
    return result


def read_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


@dataclass
class Model:
    name: str
    path: Path
    kind: str
    reason: str
    mlx: bool
    complete: bool


def inspect_model(path, name):
    cfg = read_json(path / 'config.json')
    modules = read_json(path / 'modules.json')
    pooling = isinstance(modules, list) and any(
        'Pooling' in str(m.get('type', '')) for m in modules if isinstance(m, dict))
    architectures = cfg.get('architectures', [])
    tokenizer = read_json(path / 'tokenizer_config.json')
    template = tokenizer.get('chat_template') or (path / 'chat_template.jinja').is_file()
    if pooling or (path / 'config_sentence_transformers.json').is_file():
        kind, reason = 'embedding', 'Sentence Transformers 메타데이터'
    elif any(str(a).endswith('ForCausalLM') for a in architectures) and template:
        kind, reason = 'chat', 'CausalLM + 채팅 템플릿'
    else:
        kind, reason = 'unknown', '지원/용도 미확인 (자동 선택 제외)'
    weights = list(path.glob('*.safetensors')) + list(path.glob('pytorch_model*.bin'))
    complete = bool(weights) and all(w.is_file() and w.stat().st_size > 0 for w in weights)
    for index in list(path.glob('*.index.json')):
        index_data = read_json(index)
        if 'weight_map' in index_data:
            complete = complete and all((path / f).is_file() and (path / f).stat().st_size > 0
                                       for f in index_data['weight_map'].values())
    complete = complete and (path / 'config.json').is_file() and any(
        (path / n).is_file() for n in ['tokenizer.json', 'tokenizer.model', 'vocab.json'])
    # MLX's group_size/bits layout differs from CUDA AWQ/GPTQ layouts.
    quant = cfg.get('quantization', cfg.get('quantization_config', {}))
    mlx = isinstance(quant, dict) and 'group_size' in quant and 'bits' in quant and not quant.get('quant_method')
    if not complete:
        reason += '; 가중치/토크나이저 누락'
    return Model(name, path.resolve(), kind, reason, mlx, complete)


def discover(cache_roots, model_dirs):
    found = []
    for cache in cache_roots:
        for config in sorted(cache.expanduser().glob('models--*/snapshots/*/config.json')):
            name = config.parent.parent.parent.name.removeprefix('models--').replace('--', '/')
            found.append(inspect_model(config.parent, name))
    for directory in model_dirs:
        directory = directory.expanduser().resolve()
        candidates = [directory] if (directory / 'config.json').is_file() else sorted(
            p.parent for p in directory.glob('*/config.json'))
        found.extend(inspect_model(p, p.name) for p in candidates)
    unique = {str(m.path): m for m in found}
    return list(unique.values())


def compatible(m, backend):
    return m.complete and m.kind != 'unknown' and (backend == 'metal' or not m.mlx)


def select_model(models, kind, requested, backend):
    candidates = [m for m in models if m.kind == kind and compatible(m, backend)]
    if requested:
        matches = [m for m in candidates if requested in (m.name, str(m.path))]
        if len(matches) != 1:
            raise ValueError(f'{kind}: 모델 ID가 없거나 여러 revision입니다. 목록의 snapshot 절대 경로를 지정하세요.')
        return matches[0]
    if not candidates:
        raise ValueError(f'{kind}: 사용 가능한 로컬 모델 없음. --model-dir 또는 --cache-dir로 완전한 모델을 지정하세요. 자동 다운로드하지 않습니다.')
    if not sys.stdin.isatty():
        raise ValueError('비대화형 실행에서는 --chat-model 및 --embedding-model을 지정하세요.')
    print(f'\n{kind} 선택:')
    for i, m in enumerate(candidates, 1):
        print(f'  {i}. {m.name} [{m.path.name}]')
    while True:
        choice = input('번호: ').strip()
        if choice.isdigit() and 1 <= int(choice) <= len(candidates):
            return candidates[int(choice)-1]
        print('목록의 번호를 입력하세요.')


def command(executable, model, kind, port, backend):
    cmd = [executable, 'serve', str(model.path), '--served-model-name', model.name,
           '--host', '127.0.0.1', '--port', str(port), '--max-model-len', '8192' if kind == 'chat' else '1024']
    if kind == 'embedding':
        cmd += ['--runner', 'pooling']
    if backend == 'cuda':
        cmd += ['--gpu-memory-utilization', '0.65' if kind == 'chat' else '0.20',
                '--max-num-seqs', '4', '--enforce-eager']
    return cmd


def require_free_ports(ports):
    if len(set(ports)) != len(ports):
        raise ValueError('채팅/임베딩 포트는 달라야 합니다.')
    for port in ports:
        if not 1 <= port <= 65535:
            raise ValueError('포트 범위는 1~65535입니다.')
        with socket.socket() as sock:
            try:
                sock.bind(('127.0.0.1', port))
            except OSError:
                raise ValueError(f'포트 {port} 사용 중. 기존 서비스를 중지하지 않습니다. 다른 --chat-port/--embedding-port를 지정하세요.') from None


def request(port, route, key, body=None, timeout=5):
    payload = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(f'http://127.0.0.1:{port}{route}', data=payload,
        headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    # Local readiness must not traverse a user-configured HTTP proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=timeout) as response:
        content = response.read(2_000_000)
        return json.loads(content) if content else {}


def probe(port, kind, model, key, timeout=5):
    request(port, '/health', key, timeout=timeout)
    listing = request(port, '/v1/models', key, timeout=timeout)
    if not isinstance(listing, dict) or not isinstance(listing.get('data'), list):
        raise ValueError('모델 목록 응답 형식 불일치')
    if model not in [m.get('id') for m in listing['data'] if isinstance(m, dict)]:
        raise ValueError('선택한 모델 ID가 /v1/models에 없음')
    if kind == 'chat':
        result = request(port, '/v1/chat/completions', key,
            {'model': model, 'messages': [{'role': 'user', 'content': 'Hi'}], 'max_tokens': 1}, timeout)
        choices = result.get('choices') if isinstance(result, dict) else None
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict) or not isinstance(choices[0].get('message'), dict):
            raise ValueError('채팅 응답 형식 불일치')
    else:
        result = request(port, '/v1/embeddings', key, {'model': model, 'input': ['test']}, timeout)
        data = result.get('data', []) if isinstance(result, dict) else []
        vector = data[0].get('embedding') if isinstance(data, list) and data and isinstance(data[0], dict) else None
        if not isinstance(vector, list) or not vector or not all(
            isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) for v in vector):
            raise ValueError('임베딩 벡터 응답 형식 불일치')


def await_ready(child, port, kind, model, key, seconds):
    deadline = time.monotonic() + seconds
    last = '아직 응답 없음'
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise RuntimeError(f'{kind} 프로세스 종료 (code={child.returncode}). 설치 버전, 모델 지원 및 메모리를 확인하세요.')
        try:
            probe(port, kind, model, key, timeout=min(10, max(0.1, deadline-time.monotonic())))
            if child.poll() is not None:
                raise RuntimeError(f'{kind} 프로세스가 준비 확인 중 종료되었습니다.')
            return
        except urllib.error.HTTPError as exc:
            last = f'HTTP {exc.code}'
            if exc.code in (401, 403):
                raise RuntimeError(f'{kind}: 인증 실패; 키/런타임 설정 확인') from None
        except (OSError, ValueError, KeyError, TypeError) as exc:
            last = type(exc).__name__
        time.sleep(min(1, max(0, deadline-time.monotonic())))
    raise RuntimeError(f'{kind} 준비 시간 초과 ({last}). 모델 지원/메모리/--timeout을 확인하세요.')


def cleanup(children):
    for child in reversed(children):
        # The server may have exited while leaving its own worker processes alive.
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for child in reversed(children):
        try:
            child.wait(timeout=8)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()


def example_urls(ports, chat_url=None, embedding_url=None):
    """Client URLs only; these never change the servers' localhost binding."""
    urls = [chat_url or f'http://127.0.0.1:{ports[0]}',
            embedding_url or f'http://127.0.0.1:{ports[1]}']
    for url in urls:
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme not in ('http', 'https') or not parsed.hostname or
                parsed.username is not None or parsed.password is not None or
                parsed.query or parsed.fragment or any(ord(c) < 33 or ord(c) == 127 for c in url)):
            raise ValueError('예제 URL은 인증정보/공백/query/fragment 없는 http(s) 주소여야 합니다.')
        try:
            parsed.port
        except ValueError:
            raise ValueError('예제 URL 포트 형식 오류') from None
    return [url.rstrip('/') for url in urls]


def example_shell(requested, actual_os):
    # The server's --os/backend selection does not identify the client shell.
    return ('powershell' if actual_os == 'windows' else 'posix') if requested == 'auto' else requested


def powershell_literal(value):
    return "'" + value.replace("'", "''") + "'"


def examples(chat, embedding, ports, client_shell, urls=None):
    urls = urls or example_urls(ports)
    print('\n통신 예제 (서버 OS와 별개로, 붙여 넣을 클라이언트 셸 기준 / 실제 키는 출력하지 않음):')
    if client_shell == 'powershell':
        print('# Windows PowerShell 5.1 / PowerShell 7: Invoke-RestMethod 사용 (curl 별칭 사용 안 함)')
        print("$secret = Read-Host 'VLLM_API_KEY (same value as server)' -AsSecureString")
        print("$env:VLLM_API_KEY = [System.Net.NetworkCredential]::new('', $secret).Password")
        print('$headers = @{ Authorization = "Bearer $env:VLLM_API_KEY" }')
    else:
        print('# Mac zsh/bash 또는 Linux/WSL bash: curl 사용')
        print("printf 'VLLM_API_KEY: '; stty -echo; IFS= read -r VLLM_API_KEY; stty echo; printf '\\n'; export VLLM_API_KEY")
    print('# 127.0.0.1은 이 명령을 실행하는 환경을 가리킵니다.')
    print('# WSL 서버는 먼저 WSL 셸에서 테스트하세요. Windows 호스트의 localhost 연결은 WSL 설정에 따라 다릅니다.')
    print('# 다른 접근 주소가 이미 있다면 --examples-chat-url / --examples-embedding-url로 지정하세요.')
    print('# 이 옵션은 예제 주소만 변경하며 서버 바인딩/네트워크/방화벽은 변경하지 않습니다.')
    for base in urls:
        for route in ['/health', '/v1/models']:
            url = base + route
            print(f'Invoke-RestMethod -Method Get -Uri {powershell_literal(url)} -Headers $headers' if client_shell == 'powershell' else
                  f'curl --fail {shlex.quote(url)} -H "Authorization: Bearer $VLLM_API_KEY"')
    calls = [('chat', urls[0] + '/v1/chat/completions',
              {'model': chat.name, 'messages': [{'role': 'user', 'content': '안녕하세요. 한 문장으로 소개해 주세요.'}], 'max_tokens': 64}),
             ('embedding', urls[1] + '/v1/embeddings',
              {'model': embedding.name, 'input': ['강의 노트를 검색합니다.']})]
    for label, url, body in calls:
        # ASCII JSON escapes survive clipboard/file encodings; the receiver decodes Unicode.
        payload = json.dumps(body, ensure_ascii=True)
        if client_shell == 'powershell':
            print(f'${label}Body = {powershell_literal(payload)} | ConvertFrom-Json | ConvertTo-Json -Depth 10')
            print(f"Invoke-RestMethod -Method Post -Uri {powershell_literal(url)} -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes(${label}Body))")
        else:
            print(f'curl --fail {shlex.quote(url)} -H "Authorization: Bearer $VLLM_API_KEY" -H \'Content-Type: application/json; charset=utf-8\' --data-binary {shlex.quote(payload)}')


def parser():
    p = argparse.ArgumentParser(description='로컬 모델 선택 → vLLM-Metal/CUDA 전경 실행 → API 검증. 자동 설치/다운로드 없음.')
    p.add_argument('--os', choices=['auto', 'macos', 'linux', 'windows'], default='auto')
    p.add_argument('--backend', choices=['auto', 'metal', 'cuda'], default='auto')
    p.add_argument('--cache-dir', type=Path, action='append', default=[])
    p.add_argument('--model-dir', type=Path, action='append', default=[])
    p.add_argument('--chat-model')
    p.add_argument('--embedding-model')
    p.add_argument('--chat-port', type=int)
    p.add_argument('--embedding-port', type=int)
    p.add_argument('--executable', help='설치된 vllm 실행 파일 경로')
    p.add_argument('--timeout', type=float, default=300)
    p.add_argument('--list-only', action='store_true')
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--examples-shell', choices=['auto', 'posix', 'powershell'], default='auto',
                   help='클라이언트 셸; auto는 실행 환경 기준(Mac/Linux/WSL=posix, Windows=powershell)')
    p.add_argument('--examples-chat-url', help='예제에서만 사용할 채팅 API 기본 주소(예: http://127.0.0.1:8000)')
    p.add_argument('--examples-embedding-url', help='예제에서만 사용할 임베딩 API 기본 주소')
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    children = []
    try:
        settings = load_env(ROOT / 'docker/vllm/.env')
        env = {**os.environ, **settings}
        # An explicitly exported key takes precedence, without modifying the file.
        if os.environ.get('VLLM_API_KEY'):
            env['VLLM_API_KEY'] = os.environ['VLLM_API_KEY']
        actual = {'Darwin': 'macos', 'Linux': 'linux', 'Windows': 'windows'}.get(platform.system(), 'unknown')
        target = actual if args.os == 'auto' else args.os
        backend = ('metal' if target == 'macos' else 'cuda') if args.backend == 'auto' else args.backend
        print(f'감지 OS: {actual} ({platform.machine()}) / 선택: {target} / backend: {backend}')
        print('Mac = vLLM-Metal (MLX/Metal), Linux/WSL2 = 설치된 NVIDIA CUDA vLLM')
        if not math.isfinite(args.timeout) or args.timeout <= 0:
            raise ValueError('--timeout은 양수여야 합니다.')
        default_cache = Path(env.get('HF_HUB_CACHE') or env.get('HUGGINGFACE_HUB_CACHE') or
                             str(Path(env.get('HF_HOME', str(Path.home()/'.cache/huggingface'))) / 'hub'))
        models = discover(args.cache_dir or [default_cache], args.model_dir)
        for kind, label in [('chat', '채팅'), ('embedding', '임베딩'), ('unknown', '미확인/지원 제외')]:
            print(f'\n[{label}]')
            for m in [m for m in models if m.kind == kind]:
                status = '선택 가능 후보' if compatible(m, backend) else '선택 제외'
                print(f'  {m.name} | {status} | {m.reason}\n    {m.path}')
        print('\n후보 표시는 실행 보장이 아닙니다. 실제 API 기능 검증을 통과해야 준비 완료입니다.')
        if args.list_only:
            return 0
        if backend == 'metal' and target != 'macos' or backend == 'cuda' and target == 'macos':
            raise ValueError('macOS는 metal, Linux/Windows WSL2는 cuda를 선택하세요.')
        chat = select_model(models, 'chat', args.chat_model, backend)
        embedding = select_model(models, 'embedding', args.embedding_model, backend)
        ports = [args.chat_port if args.chat_port is not None else int(env.get('CHAT_PORT', 8000)),
                 args.embedding_port if args.embedding_port is not None else int(env.get('EMBEDDING_PORT', 8001))]
        urls = example_urls(ports, args.examples_chat_url, args.examples_embedding_url)
        require_free_ports(ports)
        executable = args.executable or (str(Path.home()/'.venv-vllm-metal/bin/vllm') if backend == 'metal' else shutil.which('vllm') or 'vllm')
        resolved = shutil.which(executable)
        executable = str(Path(resolved or executable).expanduser().absolute())
        commands = [command(executable, chat, 'chat', ports[0], backend),
                    command(executable, embedding, 'embedding', ports[1], backend)]
        for cmd in commands:
            print('실행 계획:', shlex.join(cmd))
        client_shell = example_shell(args.examples_shell, actual)
        if args.dry_run:
            print('DRY RUN: 프로세스 실행/준비 확인 없음. 아래는 실행 후 사용할 예제입니다.')
            examples(chat, embedding, ports, client_shell, urls)
            return 0
        if actual == 'windows':
            raise ValueError('Windows 네이티브 실행은 지원하지 않습니다. NVIDIA 지원 WSL2에서 이 프로젝트의 python3 start.py --os windows --backend cuda를 실행하세요. WSL 안의 캐시/설치된 vllm이 필요합니다.')
        if not (target == actual or target == 'windows' and actual == 'linux' and 'microsoft' in platform.release().lower()):
            raise ValueError('--os는 OS를 에뮬레이션하지 않습니다. 현재 OS와 일치시키세요.')
        if backend == 'metal' and platform.machine() != 'arm64':
            raise ValueError('vLLM-Metal은 Apple Silicon 네이티브 arm64 환경이 필요합니다.')
        if not Path(executable).is_file() or not os.access(executable, os.X_OK):
            raise ValueError('설치된 vllm 실행 파일이 없습니다. docker/vllm/README.md의 해당 OS 설치 안내를 확인하고 --executable을 지정하세요. 자동 설치하지 않습니다.')
        key = env.get('VLLM_API_KEY', '')
        if any(ord(char) < 32 or ord(char) > 126 for char in key):
            raise ValueError('VLLM_API_KEY 형식 오류: 제어 문자/비ASCII 문자는 허용하지 않습니다.')
        if not key:
            raise ValueError('VLLM_API_KEY가 없습니다. 기존 docker/vllm/.env 또는 환경변수에 설정하세요.')
        env.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', HF_DATASETS_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1')
        if backend == 'metal':
            env.update(VLLM_ENABLE_V1_MULTIPROCESSING='0', VLLM_METAL_USE_PAGED_ATTENTION='1')
            env.setdefault('VLLM_METAL_MEMORY_FRACTION', '0.3')
        print('순서대로 시작합니다. 서버 출력은 키 노출 방지를 위해 숨깁니다. Ctrl-C로 이 실행기의 자식 프로세스만 종료합니다.')
        for cmd, m, kind, port in zip(commands, [chat, embedding], ['chat', 'embedding'], ports):
            child = subprocess.Popen(cmd, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            children.append(child)
            await_ready(child, port, kind, m.name, key, args.timeout)
            print(f'{kind} 준비 완료: http://127.0.0.1:{port} ({m.name})')
        # Recheck chat after loading the second model, which may exhaust shared memory.
        for child, m, kind, port in zip(children, [chat, embedding], ['chat', 'embedding'], ports):
            if child.poll() is not None:
                raise RuntimeError(f'{kind} 서버 종료')
            probe(port, kind, m.name, key)
        print('두 API 실제 응답 검증 완료. 이 터미널을 유지하세요.')
        examples(chat, embedding, ports, client_shell, urls)
        while True:
            if any(c.poll() is not None for c in children):
                raise RuntimeError('서버가 종료되었습니다. 메모리/런타임/모델 지원을 확인하세요.')
            time.sleep(1)
    except KeyboardInterrupt:
        print('\n종료 요청: 이 실행기에서 시작한 서버만 정리합니다.')
        return 130
    except (ValueError, RuntimeError, OSError) as exc:
        # Never print HTTP bodies or subprocess environment containing credentials.
        print('오류:', str(exc), file=sys.stderr)
        return 1
    finally:
        cleanup(children)


if __name__ == '__main__':
    raise SystemExit(main())
