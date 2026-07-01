#!/usr/bin/env python3
# ============================================================================
# integration-test.py — 真实环境端到端联调证明(不是"endpoint 存在"探测,是真跑通一条流)
#
# seam-smoke 只证「前端声明的 endpoint 在真后端可达」;这脚本更进一步:
# 对【真在跑的后端】跑一条真 happy-path(注册→拿 token→带 token 取受保护数据),
# 断言真 HTTP round-trip 成功 —— 这才叫「联调成功」。
#
# 两种模式:
#   flow 模式:有 api/integration-flow.json → 按步骤执行(backend-forge 产的黄金流,最可靠)
#   auto 模式:无 flow 文件 → 从【live 后端的 /openapi.json】(FastAPI 等自带)派生:
#     1. 找注册 endpoint(post + security:[] + 路径含 register/signup),按 requestBody
#        required 字段建最小请求体(email→随机邮箱 / password→合规密码 / ...)
#     2. POST 注册;若已存在(409)→ POST 登录同凭证
#     3. 从响应递归抽 token(access_token/token/access/jwt...)
#     4. 找一个受保护 GET(有 security、无 path 参数)带 Bearer 取数据,断言 2xx
#   拿不到 /openapi.json → 退回路径约定(/api/auth/register、/api/positions...)
#
# 产 .claude/state/integration-test.json:
#   { result:"PASS"|"FAIL", mode, base_url, token_obtained:bool,
#     steps:[{name,method,path,status,ok}], notes }
#   result = PASS iff 拿到 token 且 受保护 GET 返回 2xx
#
# 仅用标准库(urllib+json)。读 $CLAUDE_PROJECT_DIR 当项目根,缺则 pwd。
# 用法: integration-test.py --base-url http://127.0.0.1:8000 [--flow api/integration-flow.json]
# ============================================================================
import argparse, json, os, sys, time, random, string
import urllib.request, urllib.error

ROOT = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
STATE_DIR = os.path.join(ROOT, ".claude", "state")
OUT = os.path.join(STATE_DIR, "integration-test.json")

TOKEN_KEYS = {"access_token", "accesstoken", "token", "access", "jwt", "id_token", "idtoken"}
AUTHED_GET_FALLBACK = ["/api/users/me", "/api/me", "/api/user", "/api/profile",
                       "/api/positions", "/api/account", "/api/dashboard"]
REGISTER_FALLBACK = ["/api/auth/register", "/api/auth/signup", "/api/register",
                     "/api/signup", "/auth/register", "/register", "/api/users"]
LOGIN_FALLBACK = ["/api/auth/login", "/api/auth/token", "/api/login",
                  "/auth/login", "/login", "/api/token"]


def _rand(n=6):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def http(method, url, body=None, token=None, timeout=8):
    """返回 (status_code, parsed_json_or_text)。连接失败 status=0。"""
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            try:
                return r.status, json.loads(raw)
            except Exception:
                return r.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw
    except Exception as e:
        return 0, str(e)


def find_token(obj):
    """递归找 token 字段值(str 且够长)。"""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.lower().replace("_", "") in {t.replace("_", "") for t in TOKEN_KEYS} \
               and isinstance(v, str) and len(v) >= 10:
                return v
        for v in obj.values():
            t = find_token(v)
            if t:
                return t
    elif isinstance(obj, list):
        for v in obj:
            t = find_token(v)
            if t:
                return t
    return None


def resolve_ref(spec, node):
    if isinstance(node, dict) and "$ref" in node:
        parts = node["$ref"].lstrip("#/").split("/")
        cur = spec
        for p in parts:
            cur = cur.get(p, {})
        return cur
    return node


def dummy_for(spec, schema, propname=""):
    schema = resolve_ref(spec, schema or {})
    t = schema.get("type")
    fmt = schema.get("format", "")
    if schema.get("enum"):
        return schema["enum"][0]
    if fmt == "email" or "email" in propname.lower():
        return "itest_%s@example.com" % _rand()
    if "password" in propname.lower() or fmt == "password":
        return "Itest_%s!aB9" % _rand()
    if t == "integer" or t == "number":
        return schema.get("minimum", 1) or 1
    if t == "boolean":
        return False
    if t == "array":
        return []
    if t == "object":
        return build_body(spec, schema)
    # string 默认
    if "name" in propname.lower():
        return "itest %s" % _rand()
    return "itest_%s" % _rand()


def build_body(spec, schema):
    """按 required 建最小请求体(避免 extra-field 被 forbid)。"""
    schema = resolve_ref(spec, schema or {})
    props = schema.get("properties", {})
    required = schema.get("required", list(props.keys()))
    body = {}
    for name in required:
        body[name] = dummy_for(spec, props.get(name, {}), name)
    return body


def op_request_schema(spec, op):
    try:
        content = op["requestBody"]["content"]
        for ct in ("application/json", "application/x-www-form-urlencoded"):
            if ct in content:
                return content[ct].get("schema", {})
        # 取第一个
        return next(iter(content.values())).get("schema", {})
    except Exception:
        return {}


def is_secured(spec, op):
    if "security" in op:
        return len(op["security"]) > 0
    return len(spec.get("security", [])) > 0


def fetch_openapi(base):
    for p in ("/openapi.json", "/api/openapi.json", "/v3/api-docs", "/swagger.json"):
        code, body = http("GET", base + p)
        if code == 200 and isinstance(body, dict) and "paths" in body:
            return body
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--flow", default=os.path.join(ROOT, "api", "integration-flow.json"))
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    base = args.base_url.rstrip("/")

    os.makedirs(STATE_DIR, exist_ok=True)
    steps = []
    notes = ""
    token = None
    result = "FAIL"
    mode = "auto"

    def record(name, method, path, status, ok):
        steps.append({"name": name, "method": method, "path": path,
                      "status": status, "ok": ok})

    # 后端可达?
    hc, _ = http("GET", base + "/")
    if hc == 0:
        notes = "后端不可达(%s)—— 先 stack-up 起后端" % base
        write(args.out, result, mode, base, False, steps, notes)
        return 1

    # ---- flow 模式 --------------------------------------------------------
    flow = None
    if os.path.isfile(args.flow):
        try:
            flow = json.load(open(args.flow))
            mode = "flow"
        except Exception as e:
            notes = "flow 文件读失败(%s),退回 auto;" % e

    if mode == "flow" and isinstance(flow, dict) and flow.get("steps"):
        saved = {}
        all_ok = True
        for st in flow["steps"]:
            path = st["path"]
            for k, v in saved.items():
                path = path.replace("{%s}" % k, str(v))
            body = st.get("body")
            use_tok = token if st.get("auth") else None
            code, resp = http(st.get("method", "GET").upper(), base + path, body, use_tok)
            expect = st.get("expect", [200, 201, 204])
            if isinstance(expect, int):
                expect = [expect]
            ok = code in expect
            record(st.get("name", path), st.get("method", "GET").upper(), path, code, ok)
            # 保存 token / 字段
            if st.get("save_token") and isinstance(resp, (dict, list)):
                token = find_token(resp) or token
            for save_key, json_key in (st.get("save") or {}).items():
                if isinstance(resp, dict):
                    saved[save_key] = resp.get(json_key)
            if not ok:
                all_ok = False
                break
        result = "PASS" if all_ok and token else ("PASS" if all_ok else "FAIL")
        notes = notes + ("flow 全绿" if all_ok else "flow 有步骤失败")
        write(args.out, result, mode, base, bool(token), steps, notes)
        return 0 if result == "PASS" else 1

    # ---- auto 模式 --------------------------------------------------------
    spec = fetch_openapi(base)
    reg_path, reg_body, login_path, authed_get = None, None, None, None

    if spec:
        paths = spec.get("paths", {})
        for p, ops in paths.items():
            post = ops.get("post")
            if post and any(x in p.lower() for x in ("register", "signup")) and reg_path is None:
                reg_path = p
                reg_body = build_body(spec, op_request_schema(spec, post))
            if post and any(x in p.lower() for x in ("login", "token", "signin")) and login_path is None:
                login_path = p
        # 受保护 GET,无 path 参数优先
        for p, ops in paths.items():
            get = ops.get("get")
            if get and "{" not in p and is_secured(spec, get):
                authed_get = p
                break
        if authed_get is None:  # 放宽:任意无参 GET
            for p, ops in paths.items():
                if ops.get("get") and "{" not in p and p not in ("/", "/openapi.json"):
                    authed_get = p
                    break

    # 兜底猜路径
    if reg_path is None:
        reg_path = REGISTER_FALLBACK[0]
    if reg_body is None:
        reg_body = {"email": "itest_%s@example.com" % _rand(), "password": "Itest_%s!aB9" % _rand()}
    if authed_get is None:
        authed_get = AUTHED_GET_FALLBACK[0]

    # 1. 注册
    code, resp = http("POST", base + reg_path, reg_body)
    record("register", "POST", reg_path, code, code in (200, 201))
    if isinstance(resp, (dict, list)):
        token = find_token(resp)
    creds = {k: v for k, v in reg_body.items() if k.lower() in ("email", "username", "password")}

    # 2. 已存在 / 没给 token → 登录
    if not token:
        lp = login_path or LOGIN_FALLBACK[0]
        code, resp = http("POST", base + lp, creds)
        record("login", "POST", lp, code, code == 200)
        if isinstance(resp, (dict, list)):
            token = find_token(resp)

    # 3. 带 token 取受保护数据
    if token:
        code, resp = http("GET", base + authed_get, token=token)
        ok = 200 <= code < 300
        record("authed_get", "GET", authed_get, code, ok)
        if ok:
            result = "PASS"
            notes = "联调成功:注册→拿 token→带 token 取 %s 返回 %d" % (authed_get, code)
        else:
            notes = "拿到 token 但受保护 GET %s 返回 %d(非 2xx)" % (authed_get, code)
    else:
        notes = "没拿到 token(注册/登录都没返回 token)—— 联调断在鉴权"

    write(args.out, result, mode, base, bool(token), steps, notes)
    return 0 if result == "PASS" else 1


def write(out, result, mode, base, token_obtained, steps, notes):
    data = {"result": result, "mode": mode, "base_url": base,
            "token_obtained": token_obtained, "steps": steps, "notes": notes}
    with open(out, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("[integration-test] 写出: %s" % out, file=sys.stderr)
    print(json.dumps({"result": result, "mode": mode, "token_obtained": token_obtained,
                      "steps": len(steps), "notes": notes}, ensure_ascii=False), file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
