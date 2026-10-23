"""Минимальный клиент PocketBase на стандартной библиотеке Python — для тестов и демо-данных."""
import json
import os
import struct
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zlib

BASE_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")


class Response:
    def __init__(self, status, body):
        self.status = status
        self.body = body

    @property
    def ok(self):
        return 200 <= self.status < 300

    def __repr__(self):
        return f"<{self.status} {json.dumps(self.body, ensure_ascii=False)[:300]}>"


def _multipart(payload, files):
    boundary = f"----deshielo{uuid.uuid4().hex}"
    parts = []
    if payload is not None:
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="@jsonPayload"\r\n'
            f"Content-Type: application/json\r\n\r\n".encode()
            + json.dumps(payload, ensure_ascii=False).encode()
            + b"\r\n"
        )
    for field, filename, content, mime in files:
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n".encode()
            + content
            + b"\r\n"
        )
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def request(method, path, token=None, json_body=None, files=None, query=None, retries=20):
    """Отправляет запрос. Если сервер ограничил частоту запросов (429), ждёт и повторяет."""
    url = BASE_URL + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {}
    data = None
    if files:
        data, headers["Content-Type"] = _multipart(json_body, files)
    elif json_body is not None:
        data = json.dumps(json_body, ensure_ascii=False).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = token
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
                status = resp.status
        except urllib.error.HTTPError as error:
            raw = error.read()
            status = error.code
        if status == 429 and attempt < retries - 1:
            time.sleep(1.5)
            continue
        try:
            body = json.loads(raw) if raw else None
        except ValueError:
            body = raw
        return Response(status, body)
    raise RuntimeError("unreachable")


def wait_until_healthy(timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if request("GET", "/api/health", retries=1).ok:
                return
        except OSError:
            pass
        time.sleep(0.5)
    raise SystemExit(f"PocketBase не отвечает по адресу {BASE_URL}")


def sign_up(email, password, name, accepted_terms=True):
    return request("POST", "/api/collections/users/records", json_body={
        "email": email,
        "password": password,
        "passwordConfirm": password,
        "name": name,
        "accepted_terms": accepted_terms,
    })


def sign_in(email, password):
    return request("POST", "/api/collections/users/auth-with-password",
                   json_body={"identity": email, "password": password})


def make_png(width=64, height=48, colors=((233, 185, 73), (200, 36, 59))):
    """Настоящий PNG с градиентом: сервер проверяет тип файла по содержимому."""
    (r1, g1, b1), (r2, g2, b2) = colors
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            t = (x + y) / (width + height - 2)
            row += bytes((int(r1 + (r2 - r1) * t), int(g1 + (g2 - g1) * t), int(b1 + (b2 - b1) * t)))
        rows.append(bytes(row))

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
