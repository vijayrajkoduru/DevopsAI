from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from pydantic import BaseModel
import anthropic
import os, re, json, sqlite3, boto3, subprocess
import secrets, tempfile, shutil, html, logging
from datetime import datetime, timedelta
from dotenv import load_dotenv
import bcrypt

load_dotenv()

# ── LOGGING ────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("devopsai")

# ── RATE LIMITER ───────────────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address)

app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── SECURITY HEADERS MIDDLEWARE ────────────────────────────────────────────────
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"]        = "DENY"
    response.headers["X-XSS-Protection"]       = "1; mode=block"
    response.headers["Referrer-Policy"]         = "strict-origin-when-cross-origin"
    return response
client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

# Always resolve paths relative to this file — works no matter where uvicorn is started from
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(BASE_DIR, "generated")
DB_PATH    = os.path.join(BASE_DIR, "data", "canvas.db")

def _open(filename):
    return open(os.path.join(BASE_DIR, filename), "r", encoding="utf-8")

# ── DATABASE INIT ──────────────────────────────────────────────────────────────

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS canvases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        user_id INTEGER
    )''')
    # Migration: add user_id column if it doesn't exist yet (for existing databases)
    try:
        c.execute("ALTER TABLE canvases ADD COLUMN user_id INTEGER")
    except Exception:
        pass  # Column already exists
    c.execute('''CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        plan TEXT NOT NULL DEFAULT 'free',
        created_at TEXT NOT NULL
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
    )''')
    # Only remove expired sessions — keep valid ones so users stay logged in after restart
    c.execute("DELETE FROM sessions WHERE expires_at < ?", (datetime.now().isoformat(),))
    c.execute('''CREATE TABLE IF NOT EXISTS aws_credentials (
        user_id INTEGER PRIMARY KEY,
        access_key TEXT NOT NULL,
        secret_key TEXT NOT NULL,
        region TEXT NOT NULL DEFAULT 'us-east-1',
        updated_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
    )''')
    conn.commit()
    conn.close()

init_db()

# ── HELPERS ────────────────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

def verify_password(password: str, hashed: str) -> bool:
    try:
        # Support legacy SHA256 hashes during migration
        if len(hashed) == 64 and re.match(r'^[a-f0-9]+$', hashed):
            import hashlib
            return hashlib.sha256(password.encode()).hexdigest() == hashed
        return bcrypt.checkpw(password.encode(), hashed.encode())
    except Exception:
        return False

def safe_path(base: str, user_path: str) -> str:
    """Resolve path and ensure it stays within base directory (prevent path traversal)."""
    full = os.path.realpath(os.path.join(base, user_path))
    base_real = os.path.realpath(base)
    if not full.startswith(base_real + os.sep) and full != base_real:
        raise HTTPException(status_code=400, detail="Invalid path")
    return full

def sanitize_tf_var(value: str) -> str:
    """Strip shell metacharacters from terraform variable values."""
    return re.sub(r'[;&|`$<>\\\'"]', '', value)[:200]

def require_auth(request: Request):
    """Raise 401 if not logged in."""
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user

def get_current_user(request: Request):
    token = request.cookies.get("session_token")
    if not token:
        return None
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''SELECT u.id, u.name, u.email, u.plan
                 FROM sessions s JOIN users u ON s.user_id = u.id
                 WHERE s.token = ? AND s.expires_at > ?''', (token, datetime.now().isoformat()))
    row = c.fetchone()
    conn.close()
    if not row:
        return None
    return {"id": row[0], "name": row[1], "email": row[2], "plan": row[3]}

# ── PYDANTIC MODELS ────────────────────────────────────────────────────────────

class PromptRequest(BaseModel):
    prompt: str

class AWSResource(BaseModel):
    resource_type: str
    config: dict

class AWSRegionRequest(BaseModel):
    region: str = "us-east-1"

class CanvasSave(BaseModel):
    name: str
    data: str

class CanvasUpdate(BaseModel):
    data: str

class AuthLogin(BaseModel):
    email: str
    password: str

class AuthRegister(BaseModel):
    name: str
    email: str
    password: str

class AWSCreds(BaseModel):
    access_key: str
    secret_key: str
    region: str = "us-east-1"

def get_user_aws_creds(user_id: int):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT access_key, secret_key, region FROM aws_credentials WHERE user_id=?", (user_id,))
    row = c.fetchone()
    conn.close()
    if row:
        return {"access_key": row[0], "secret_key": row[1], "region": row[2]}
    return None


# ── PAGE ROUTES ────────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
def root():
    with _open("ui.html") as f:
        return f.read()

@app.get("/login", response_class=HTMLResponse)
def login_page():
    with _open("login.html") as f:
        return f.read()

@app.get("/landing", response_class=HTMLResponse)
def landing_page():
    with _open("landing.html") as f:
        return f.read()

@app.get("/app", response_class=HTMLResponse)
def app_page(request: Request):
    from fastapi.responses import RedirectResponse
    user = get_current_user(request)
    if not user:
        return RedirectResponse(url="/login", status_code=302)
    with _open("ui.html") as f:
        return f.read()

ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "awsvijju5@gmail.com")

@app.get("/admin", response_class=HTMLResponse)
def admin_dashboard(request: Request):
    user = get_current_user(request)
    if not user or user["email"] != ADMIN_EMAIL:
        return HTMLResponse("<h2 style='font-family:sans-serif;color:red;padding:40px'>Access Denied</h2>", status_code=403)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, name, email, plan, created_at FROM users ORDER BY id DESC")
    users = c.fetchall()
    c.execute("SELECT plan, COUNT(*) FROM users GROUP BY plan")
    plan_counts = dict(c.fetchall())
    conn.close()
    free_count  = plan_counts.get("free",  0)
    pro_count   = plan_counts.get("pro",   0)
    team_count  = plan_counts.get("team",  0)
    mrr = pro_count * 29 + team_count * 99
    def plan_bg(p):
        return "#0d2d1a" if p == "team" else ("#1e1442" if p == "pro" else "#1a1a2e")
    def plan_color(p):
        return "#4ade80" if p == "team" else ("#a78bfa" if p == "pro" else "#666")
    rows = "".join(
        f"<tr><td>{u[0]}</td><td>{html.escape(str(u[1]))}</td><td>{html.escape(str(u[2]))}</td>"
        f"<td><span style='padding:2px 8px;border-radius:10px;font-size:11px;"
        f"background:{plan_bg(u[3])};color:{plan_color(u[3])}'>{html.escape(str(u[3]))}</span></td>"
        f"<td style='color:#555;font-size:11px'>{html.escape(str(u[4][:10]))}</td></tr>"
        for u in users
    )
    return f"""<!DOCTYPE html><html><head><title>Admin — AI DevOps</title>
<style>*{{margin:0;padding:0;box-sizing:border-box}}body{{background:#0a0a12;color:#e0e0e0;font-family:'Segoe UI',sans-serif;padding:32px}}
h1{{color:#a78bfa;margin-bottom:24px}}
.cards{{display:flex;gap:16px;margin-bottom:32px}}
.card{{background:#0f0f1a;border:1px solid #1a1a2e;border-radius:12px;padding:20px 28px;min-width:150px}}
.card-n{{font-size:32px;font-weight:700;color:#fff}}
.card-l{{font-size:11px;color:#555;margin-top:4px;text-transform:uppercase;letter-spacing:1px}}
table{{width:100%;border-collapse:collapse;background:#0f0f1a;border-radius:12px;overflow:hidden;border:1px solid #1a1a2e}}
th{{background:#13131f;padding:10px 14px;text-align:left;font-size:11px;color:#555;text-transform:uppercase;letter-spacing:1px;border-bottom:1px solid #1a1a2e}}
td{{padding:10px 14px;font-size:12px;border-bottom:1px solid #0d0d1a}}
tr:last-child td{{border-bottom:none}}
tr:hover td{{background:#0d0d18}}</style></head>
<body>
<h1>⚡ Admin Dashboard</h1>
<div class="cards">
  <div class="card"><div class="card-n">{len(users)}</div><div class="card-l">Total Users</div></div>
  <div class="card"><div class="card-n" style="color:#666">{free_count}</div><div class="card-l">Free</div></div>
  <div class="card"><div class="card-n" style="color:#a78bfa">{pro_count}</div><div class="card-l">Pro ($29)</div></div>
  <div class="card"><div class="card-n" style="color:#4ade80">{team_count}</div><div class="card-l">Team ($99)</div></div>
  <div class="card"><div class="card-n" style="color:#fbbf24">${mrr}</div><div class="card-l">MRR</div></div>
</div>
<table><thead><tr><th>#</th><th>Name</th><th>Email</th><th>Plan</th><th>Joined</th></tr></thead>
<tbody>{rows}</tbody></table>
</body></html>"""

# ── AUTH ROUTES ────────────────────────────────────────────────────────────────

@app.post("/auth/register")
@limiter.limit("5/minute")
def auth_register(req: AuthRegister, request: Request, response: Response):
    if not req.name or not req.email or not req.password:
        raise HTTPException(status_code=400, detail="All fields are required.")
    if not re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', req.email):
        raise HTTPException(status_code=400, detail="Invalid email address.")
    if len(req.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters.")
    if len(req.name) > 100 or len(req.email) > 200:
        raise HTTPException(status_code=400, detail="Input too long.")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id FROM users WHERE email = ?", (req.email,))
    if c.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="Email already registered.")
    now = datetime.now().isoformat()
    pw_hash = hash_password(req.password)
    c.execute("INSERT INTO users (name, email, password_hash, plan, created_at) VALUES (?, ?, ?, 'free', ?)",
              (req.name, req.email, pw_hash, now))
    user_id = c.lastrowid
    token = secrets.token_hex(32)
    expires = (datetime.now() + timedelta(days=30)).isoformat()
    c.execute("INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)", (token, user_id, now, expires))
    conn.commit()
    conn.close()
    response.set_cookie(key="session_token", value=token, httponly=True, samesite="strict", max_age=86400 * 30)
    logger.info(f"New user registered: {req.email}")
    return {"id": user_id, "name": req.name, "email": req.email, "plan": "free"}

@app.post("/auth/login")
@limiter.limit("10/minute")
def auth_login(req: AuthLogin, request: Request, response: Response):
    if not req.email or not req.password:
        raise HTTPException(status_code=400, detail="Email and password required.")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    # Fetch by email only, then verify password — prevents timing attacks
    c.execute("SELECT id, name, email, plan, password_hash FROM users WHERE email = ?", (req.email,))
    row = c.fetchone()
    if not row or not verify_password(req.password, row[4]):
        conn.close()
        logger.warning(f"Failed login attempt for: {req.email}")
        raise HTTPException(status_code=401, detail="Invalid email or password.")
    user_id, name, email, plan, _ = row
    # Upgrade legacy SHA256 hash to bcrypt on successful login
    if len(row[4]) == 64 and re.match(r'^[a-f0-9]+$', row[4]):
        c.execute("UPDATE users SET password_hash=? WHERE id=?", (hash_password(req.password), user_id))
    token = secrets.token_hex(32)
    now = datetime.now().isoformat()
    expires = (datetime.now() + timedelta(days=30)).isoformat()
    c.execute("INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)", (token, user_id, now, expires))
    conn.commit()
    conn.close()
    response.set_cookie(key="session_token", value=token, httponly=True, samesite="strict", max_age=86400 * 30)
    logger.info(f"User logged in: {email}")
    return {"id": user_id, "name": name, "email": email, "plan": plan}

@app.get("/auth/me")
def auth_me(request: Request):
    user = get_current_user(request)
    if not user:
        return {"authenticated": False}
    return {"authenticated": True, **user}

@app.post("/auth/logout")
def auth_logout(request: Request, response: Response):
    token = request.cookies.get("session_token")
    if token:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("DELETE FROM sessions WHERE token = ?", (token,))
        conn.commit()
        conn.close()
    response.delete_cookie("session_token")
    return {"logged_out": True}

# ── CANVAS ROUTES ──────────────────────────────────────────────────────────────

@app.post("/canvas/save")
def save_canvas(req: CanvasSave, request: Request):
    user = require_auth(request)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    now = datetime.now().isoformat()
    c.execute("INSERT INTO canvases (name, data, created_at, updated_at, user_id) VALUES (?, ?, ?, ?, ?)",
              (req.name, req.data, now, now, user["id"]))
    canvas_id = c.lastrowid
    conn.commit()
    conn.close()
    return {"id": canvas_id, "name": req.name, "saved_at": now}

@app.put("/canvas/{canvas_id}")
def update_canvas(canvas_id: int, req: CanvasUpdate, request: Request):
    user = require_auth(request)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    now = datetime.now().isoformat()
    # Only update canvases owned by this user
    c.execute("UPDATE canvases SET data=?, updated_at=? WHERE id=? AND user_id=?",
              (req.data, now, canvas_id, user["id"]))
    conn.commit()
    conn.close()
    return {"id": canvas_id, "updated_at": now}

@app.get("/canvas/list")
def list_canvases(request: Request):
    user = require_auth(request)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, name, created_at, updated_at FROM canvases WHERE user_id=? ORDER BY updated_at DESC",
              (user["id"],))
    rows = c.fetchall()
    conn.close()
    return {"canvases": [{"id": r[0], "name": r[1], "created_at": r[2], "updated_at": r[3]} for r in rows]}

@app.get("/canvas/{canvas_id}")
def load_canvas(canvas_id: int, request: Request):
    user = require_auth(request)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, name, data, created_at, updated_at FROM canvases WHERE id=? AND user_id=?",
              (canvas_id, user["id"]))
    row = c.fetchone()
    conn.close()
    if not row:
        return {"error": "Canvas not found"}
    return {"id": row[0], "name": row[1], "data": row[2], "created_at": row[3], "updated_at": row[4]}

@app.delete("/canvas/{canvas_id}")
def delete_canvas(canvas_id: int, request: Request):
    user = require_auth(request)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM canvases WHERE id=? AND user_id=?", (canvas_id, user["id"]))
    conn.commit()
    conn.close()
    return {"deleted": canvas_id}

# ── AWS SCAN ───────────────────────────────────────────────────────────────────

def get_boto3_client(service, region, creds=None):
    if creds:
        return boto3.client(service, region_name=region,
            aws_access_key_id=creds["access_key"],
            aws_secret_access_key=creds["secret_key"])
    return boto3.client(service, region_name=region)

@app.post("/aws/scan")
def scan_aws_resources(req: AWSRegionRequest, request: Request):
    region = req.region
    user = get_current_user(request)
    creds = get_user_aws_creds(user["id"]) if user else None
    resources = []
    errors = []
    try:
        ec2 = get_boto3_client("ec2", region, creds)
        resp = ec2.describe_instances()
        for reservation in resp["Reservations"]:
            for inst in reservation["Instances"]:
                name = next((t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Name"), "")
                resources.append({"service": "ec2_instance", "id": inst["InstanceId"], "name": name or inst["InstanceId"], "status": inst["State"]["Name"], "details": {"instance_type": inst.get("InstanceType", ""), "ip": inst.get("PublicIpAddress", ""), "az": inst.get("Placement", {}).get("AvailabilityZone", ""), "vpc_id": inst.get("VpcId", "")}, "region": region, "category": "AWS Compute"})
    except Exception as e:
        errors.append("EC2: " + str(e))
    try:
        s3 = get_boto3_client("s3", region, creds)
        for bucket in s3.list_buckets().get("Buckets", []):
            resources.append({"service": "s3_bucket", "id": bucket["Name"], "name": bucket["Name"], "status": "active", "details": {}, "region": region, "category": "AWS Storage"})
    except Exception as e:
        errors.append("S3: " + str(e))
    try:
        rds = get_boto3_client("rds", region, creds)
        for db in rds.describe_db_instances().get("DBInstances", []):
            resources.append({"service": "rds_instance", "id": db["DBInstanceIdentifier"], "name": db["DBInstanceIdentifier"], "status": db["DBInstanceStatus"], "details": {"engine": db.get("Engine", ""), "instance_class": db.get("DBInstanceClass", "")}, "region": region, "category": "AWS Storage"})
    except Exception as e:
        errors.append("RDS: " + str(e))
    try:
        ec2 = get_boto3_client("ec2", region, creds)
        for vpc in ec2.describe_vpcs().get("Vpcs", []):
            name = next((t["Value"] for t in vpc.get("Tags", []) if t["Key"] == "Name"), "")
            resources.append({"service": "vpc_main", "id": vpc["VpcId"], "name": name or vpc["VpcId"], "status": vpc["State"], "details": {"cidr": vpc.get("CidrBlock", "")}, "region": region, "category": "AWS Networking"})
    except Exception as e:
        errors.append("VPC: " + str(e))
    try:
        eks = get_boto3_client("eks", region, creds)
        for cluster_name in eks.list_clusters().get("clusters", []):
            detail = eks.describe_cluster(name=cluster_name)["cluster"]
            resources.append({"service": "eks_cluster", "id": cluster_name, "name": cluster_name, "status": detail.get("status", ""), "details": {"version": detail.get("version", "")}, "region": region, "category": "AWS Compute"})
    except Exception as e:
        errors.append("EKS: " + str(e))
    try:
        lmb = get_boto3_client("lambda", region, creds)
        for fn in lmb.list_functions().get("Functions", []):
            resources.append({"service": "lambda_fn", "id": fn["FunctionName"], "name": fn["FunctionName"], "status": "active", "details": {"runtime": fn.get("Runtime", ""), "memory": str(fn.get("MemorySize", "")) + " MB"}, "region": region, "category": "AWS Compute"})
    except Exception as e:
        errors.append("Lambda: " + str(e))
    try:
        elb = get_boto3_client("elbv2", region, creds)
        for lb in elb.describe_load_balancers().get("LoadBalancers", []):
            resources.append({"service": "alb", "id": lb["LoadBalancerName"], "name": lb["LoadBalancerName"], "status": lb["State"]["Code"], "details": {"type": lb.get("Type", ""), "dns": lb.get("DNSName", "")}, "region": region, "category": "AWS Networking"})
    except Exception as e:
        errors.append("ALB: " + str(e))
    try:
        ecr = get_boto3_client("ecr", region, creds)
        for repo in ecr.describe_repositories().get("repositories", []):
            resources.append({"service": "ecr_repo", "id": repo["repositoryName"], "name": repo["repositoryName"], "status": "active", "details": {"uri": repo.get("repositoryUri", "")}, "region": region, "category": "AWS Storage"})
    except Exception as e:
        errors.append("ECR: " + str(e))
    try:
        iam = get_boto3_client("iam", region, creds)
        for role in iam.list_roles().get("Roles", [])[:15]:
            resources.append({"service": "iam_role", "id": role["RoleName"], "name": role["RoleName"], "status": "active", "details": {"arn": role.get("Arn", "")}, "region": "global", "category": "AWS Security"})
    except Exception as e:
        errors.append("IAM: " + str(e))
    return {"resources": resources, "total": len(resources), "region": region, "errors": errors}

# ── FILE EXTRACTION HELPER ─────────────────────────────────────────────────────

def extract_and_save_files(response_text, base_dir):
    os.makedirs(base_dir, exist_ok=True)
    text = response_text.replace('\r\n', '\n').replace('\r', '\n')
    saved = []

    # Primary parser: split on <<FILE:name>> markers
    if '<<FILE:' in text:
        parts = text.split('<<FILE:')
        for part in parts[1:]:             # skip first empty chunk
            if '>>' not in part:
                continue
            fname   = part[:part.index('>>')].strip()
            rest    = part[part.index('>>') + 2:]
            # content ends at <</FILE>>, or at next <<FILE: if no closing marker
            end_explicit = rest.find('<</FILE>>')
            end_next     = rest.find('<<FILE:')
            if end_explicit != -1:
                content = rest[:end_explicit].strip()
            elif end_next != -1:
                content = rest[:end_next].strip()
            else:
                content = rest.strip()
            if not fname or not content:
                continue
            # Normalize path separators and create subdirs if needed (e.g. .github/workflows/ci.yml)
            fname = fname.replace('\\', '/')
            filepath = os.path.join(base_dir, *fname.split('/'))
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            saved.append(fname)
            logger.info(f"Saved {fname}")

    # Fallback: markdown code blocks — try to extract filename from ### File N: `name` headers
    if not saved:
        # First try to extract filenames from markdown headers: ### File 1: `filename.ext`
        header_files = re.findall(r'###\s*File\s*\d+\s*:\s*[`"]?([^\s`"\n]+)[`"]?', text)
        blocks = re.findall(r'```[a-zA-Z]*\n(.*?)```', text, re.DOTALL)
        DEFAULT_TF = ['main.tf', 'variables.tf', 'outputs.tf', 'providers.tf', 'terraform.tfvars']
        for i, content in enumerate(blocks):
            content = content.strip()
            if not content:
                continue
            if i < len(header_files):
                fname = header_files[i]
            elif i < len(DEFAULT_TF):
                fname = DEFAULT_TF[i]
            else:
                fname = f'file_{i+1}.txt'
            filepath = os.path.join(base_dir, fname)
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            saved.append(fname)
            logger.info(f"Fallback saved {fname}")

    logger.info(f"Total saved: {saved}")
    return saved

# ── MASTER SETUP SCRIPT GENERATOR ─────────────────────────────────────────────

class SetupScriptRequest(BaseModel):
    services: list        # list of {id, label, folder} from canvas nodes
    region: str = "us-east-1"
    cluster_name: str = "my-eks-cluster"

@app.post("/generate-setup-script")
@limiter.limit("10/minute")
def generate_setup_script(req: SetupScriptRequest, request: Request):
    require_auth(request)

    has_eks     = any(s.get("id","") in ("eks_cluster","eks_nodegroup","eks_fargate","eks_addon") for s in req.services)
    has_k8s     = any(s.get("id","").startswith("k8s_") for s in req.services)
    has_helm    = any(s.get("id","").startswith("helm_") for s in req.services)
    has_argocd  = any("argocd" in s.get("id","") for s in req.services)
    has_monitor = any(s.get("id","") in ("prom_cfg","prom_docker","grafana_ds","grafana_app_dash") for s in req.services)
    has_ingress = any(s.get("id","") in ("nginx_proxy","nginx_k8s","traefik_k8s","alb") for s in req.services)
    has_vault   = any("vault" in s.get("id","") for s in req.services)

    tf_folders = [s.get("folder","") for s in req.services if s.get("folder")]

    region       = req.region or "us-east-1"
    cluster_name = req.cluster_name or "my-eks-cluster"

    lines = ["#!/bin/bash", "set -e", "",
             "# ============================================================",
             "# AUTO-GENERATED MASTER DEPLOY SCRIPT",
             "# Generated by AI DevOps Platform",
             "# ============================================================", ""]

    # 1. Prerequisites check
    lines += [
        "echo '=== Checking prerequisites ==='",
        "command -v terraform >/dev/null 2>&1 || { echo 'ERROR: terraform not found. Install from https://terraform.io'; exit 1; }",
        "command -v aws >/dev/null 2>&1 || { echo 'ERROR: aws cli not found. Install from https://aws.amazon.com/cli/'; exit 1; }",
    ]
    if has_eks or has_k8s:
        lines += [
            "command -v kubectl >/dev/null 2>&1 || { echo 'Installing kubectl...'; curl -LO 'https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl' && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl; }",
        ]
    if has_helm or has_argocd or has_monitor or has_ingress:
        lines += [
            "command -v helm >/dev/null 2>&1 || { echo 'Installing helm...'; curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }",
        ]
    lines += ["echo 'All prerequisites met!'", ""]

    # 2. Terraform apply for each folder
    if tf_folders:
        lines += ["echo ''", "echo '=== Step 1: Applying Terraform (all services) ==='"]
        for folder in tf_folders:
            safe = folder.replace("'", "")
            lines += [
                f"echo '  → Deploying {safe}...'",
                f"cd generated/{safe}",
                "terraform init -no-color -input=false",
                "terraform apply -auto-approve -no-color -input=false",
                "cd ../..",
                ""
            ]

    # 3. EKS kubeconfig + dependency install
    if has_eks:
        lines += [
            "echo ''",
            "echo '=== Step 2: Configuring EKS cluster ==='",
            f"echo 'Updating kubeconfig for cluster: {cluster_name}'",
            f"aws eks update-kubeconfig --region {region} --name {cluster_name}",
            "echo 'Waiting for nodes to be ready...'",
            "kubectl wait --for=condition=Ready nodes --all --timeout=300s",
            "kubectl get nodes",
            "",
            "echo '=== Step 3: Installing EKS core add-ons ==='",
            "",
            "# AWS Load Balancer Controller",
            "helm repo add eks https://aws.github.io/eks-charts --force-update",
            "helm repo update",
            "helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \\",
            f"  -n kube-system --set clusterName={cluster_name} \\",
            "  --set serviceAccount.create=true \\",
            "  --wait",
            "",
            "# EBS CSI Driver (for persistent volumes)",
            "helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver --force-update",
            "helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \\",
            "  -n kube-system --wait",
            "",
            "# CoreDNS + kube-proxy (managed by EKS, verify running)",
            "kubectl get pods -n kube-system",
            "",
            "# Default StorageClass",
            "kubectl apply -f - <<'EOF'",
            "apiVersion: storage.k8s.io/v1",
            "kind: StorageClass",
            "metadata:",
            "  name: gp3",
            "  annotations:",
            "    storageclass.kubernetes.io/is-default-class: 'true'",
            "provisioner: ebs.csi.aws.com",
            "volumeBindingMode: WaitForFirstConsumer",
            "parameters:",
            "  type: gp3",
            "  encrypted: 'true'",
            "EOF",
            "",
        ]

    # 4. Monitoring stack
    if has_monitor and has_eks:
        lines += [
            "echo '=== Step 4: Installing Monitoring Stack ==='",
            "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update",
            "helm repo update",
            "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -",
            "helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \\",
            "  -n monitoring \\",
            "  --set prometheus.prometheusSpec.retention=15d \\",
            "  --set grafana.adminPassword=admin123 \\",
            "  --wait",
            "echo 'Grafana available: kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring'",
            "",
        ]

    # 5. ArgoCD
    if has_argocd and has_eks:
        lines += [
            "echo '=== Step 5: Installing ArgoCD ==='",
            "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -",
            "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml",
            "kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s",
            "echo 'ArgoCD admin password:'",
            "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo",
            "",
        ]

    # 6. Vault
    if has_vault and has_eks:
        lines += [
            "echo '=== Installing HashiCorp Vault ==='",
            "helm repo add hashicorp https://helm.releases.hashicorp.com --force-update",
            "kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -",
            "helm upgrade --install vault hashicorp/vault -n vault \\",
            "  --set server.dev.enabled=false \\",
            "  --set server.ha.enabled=true \\",
            "  --set server.ha.replicas=3 \\",
            "  --wait",
            "",
        ]

    # 7. Apply K8s manifests
    if has_k8s:
        k8s_folders = [s.get("folder","") for s in req.services
                       if s.get("folder") and s.get("id","").startswith("k8s_")]
        if k8s_folders:
            lines += ["echo '=== Applying Kubernetes Manifests ==='"]
            for folder in k8s_folders:
                safe = folder.replace("'","")
                lines += [
                    f"echo '  → Applying {safe}...'",
                    f"kubectl apply -f generated/{safe}/",
                    ""
                ]

    lines += [
        "echo ''",
        "echo '============================================================'",
        "echo 'DEPLOYMENT COMPLETE!'",
        "echo '============================================================'",
        "kubectl get all --all-namespaces 2>/dev/null || true",
    ]

    script = "\n".join(lines)
    # Save to generated/
    script_path = os.path.join(OUTPUT_DIR, "deploy-all.sh")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(script_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(script)

    return {
        "saved": True,
        "path": "generated/deploy-all.sh",
        "has_eks": has_eks,
        "has_k8s": has_k8s,
        "has_helm": has_helm,
        "has_argocd": has_argocd,
        "has_monitoring": has_monitor,
        "script_preview": script[:500]
    }

# ── AI GENERATION ROUTES ───────────────────────────────────────────────────────

@app.post("/generate")
@limiter.limit("20/minute")
def generate(req: PromptRequest, request: Request):
    require_auth(request)
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        messages=[{"role": "user", "content": "You are an AI DevOps agent. Generate complete production-ready code split into proper separate files.\nUse this exact format for each file:\n### File 1: `filename.ext`\n```language\ncode here\n```\nInstruction: " + req.prompt}]
    )
    response_text = message.content[0].text
    user_dir = get_user_output_dir(request)
    save_dir = os.path.join(user_dir, clean_folder_name(req.prompt[:40]))
    saved_files = extract_and_save_files(response_text, save_dir)
    rel_folder = os.path.relpath(save_dir, OUTPUT_DIR).replace("\\", "/")
    return {"response": response_text, "saved_files": saved_files, "location": save_dir, "folder": rel_folder}

def get_user_output_dir(request: Request) -> str:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    return OUTPUT_DIR

def clean_folder_name(name: str) -> str:
    """Convert node label to clean folder name: 'EC2 Instance' → 'ec2-instance'"""
    name = name.strip().lower()
    name = re.sub(r'[^a-z0-9\s-]', '', name)   # remove special chars
    name = re.sub(r'\s+', '-', name)             # spaces → dashes
    name = re.sub(r'-+', '-', name)              # collapse multiple dashes
    return name.strip('-') or 'resource'

@app.post("/generate-terraform")
@limiter.limit("20/minute")
def generate_terraform(resource: AWSResource, request: Request):
    require_auth(request)
    cfg = resource.config
    config_str = json.dumps(cfg, indent=2)

    # Resolve domain name — use node config, or fall back to global canvas domain
    domain_name = cfg.get("domain_name") or cfg.get("global_domain_name") or "devopsai.com"
    namespace   = cfg.get("namespace") or cfg.get("k8s_namespace") or ""

    # Build requirements section from what the user filled in
    req_lines = [
        f"- Domain name: {domain_name} — declare as variable 'domain_name' with this default. "
        f"For EC2/ALB modules add aws_route53_zone, aws_acm_certificate (DNS validation), "
        f"aws_route53_record pointing the domain to the ALB.",
    ]
    if namespace:
        req_lines.append(f"- Kubernetes namespace: {namespace} — use this namespace in all k8s resources and Helm values")
    if cfg.get("size_tier"):
        size_map = {"small": "t3.micro / db.t3.micro — minimal cost", "medium": "t3.medium / db.t3.medium — balanced", "large": "t3.large / db.t3.large — high performance", "enterprise": "t3.xlarge / db.r5.xlarge — maximum"}
        req_lines.append(f"- Instance size tier: {size_map.get(cfg['size_tier'], cfg['size_tier'])}")
    if cfg.get("traffic_level"):
        traffic_map = {"low": "single instance, no auto-scaling needed", "medium": "min 2 instances, basic auto-scaling", "high": "min 3 instances, aggressive auto-scaling, read replicas", "very_high": "min 5 instances, multi-region consideration, CDN required"}
        req_lines.append(f"- Traffic level: {traffic_map.get(cfg['traffic_level'], cfg['traffic_level'])}")
    if cfg.get("multi_az"):
        req_lines.append("- Multi-AZ: YES — deploy across multiple availability zones for high availability")
    if cfg.get("enable_ssl"):
        req_lines.append("- SSL/HTTPS: YES — include ACM certificate and HTTPS listeners")
    if cfg.get("db_password"):
        req_lines.append(f"- Database password: use exactly '{cfg['db_password']}' in terraform.tfvars")
    if cfg.get("extra_requirements"):
        req_lines.append(f"- Extra requirements: {cfg['extra_requirements']}")

    req_section = ""
    if req_lines:
        req_section = "\n\nUSER REQUIREMENTS (implement ALL of these):\n" + "\n".join(req_lines)

    # Detect connected resources to add smart EC2 user_data and IAM policies
    connected     = cfg.get("connected_resources", [])
    conn_ids      = [c.get("type","") for c in connected]
    has_docker    = any("docker" in c for c in conn_ids)
    has_s3_conn   = any("s3" in c for c in conn_ids)
    has_rds_conn  = any("rds" in c or "aurora" in c for c in conn_ids)
    has_redis_conn= any("redis" in c or "elasticache" in c for c in conn_ids)

    conn_section = ""
    if resource.resource_type in ("ec2_instance", "ec2_asg") and (has_docker or has_s3_conn):
        conn_section = "\n\nCONNECTED RESOURCES (implement ALL of these automatically):\n"
        if has_docker:
            conn_section += (
                "- Docker is connected: Add user_data that installs Docker + Docker Compose on boot:\n"
                "  #!/bin/bash\n"
                "  apt-get update -y\n"
                "  apt-get install -y docker.io docker-compose-plugin awscli\n"
                "  systemctl enable docker && systemctl start docker\n"
                "  usermod -aG docker ubuntu\n"
                "  # Pull and start containers\n"
                "  cd /home/ubuntu && docker compose up -d\n"
            )
        if has_s3_conn:
            conn_section += (
                "- S3 Bucket is connected: Add an aws_iam_role + aws_iam_instance_profile that gives EC2\n"
                "  full s3:GetObject, s3:PutObject, s3:DeleteObject, s3:ListBucket permissions.\n"
                "  Attach the instance profile to the EC2 instance.\n"
                "  Export S3_BUCKET_NAME as environment variable in user_data.\n"
            )
        if has_rds_conn:
            conn_section += "- RDS is connected: Add security group rule allowing EC2 to reach RDS on port 5432/3306.\n"
        if has_redis_conn:
            conn_section += "- Redis/ElastiCache is connected: Add security group rule allowing EC2 to reach Redis on port 6379.\n"

    # S3 bucket — generate IAM for ALL connected EC2 instances specifically
    if resource.resource_type == "s3_bucket" and connected:
        ec2_instances = [c for c in connected if "ec2" in c.get("type","") or "instance" in c.get("type","")]
        if ec2_instances:
            conn_section = "\n\nCONNECTED EC2 INSTANCES (create separate IAM role per instance):\n"
            for i, ec2 in enumerate(ec2_instances, 1):
                label = ec2.get("label", f"EC2 Instance {i}")
                node_id = ec2.get("config", {}).get("node_id", f"ec2_{i}")
                conn_section += (
                    f"- {label} (id: {node_id}): create aws_iam_role named 'ec2-s3-role-{node_id}' "
                    f"with s3:GetObject, s3:PutObject, s3:DeleteObject on this bucket. "
                    f"Create aws_iam_instance_profile named 'ec2-s3-profile-{node_id}'.\n"
                )

    namespace_rule = (
        f"8. ALWAYS declare a variable named 'namespace' in variables.tf with default = \"{namespace}\" and use it in all k8s/Helm resources\n"
        if namespace else ""
    )

    prompt = (
        "Generate complete production-ready Terraform code for " + resource.resource_type + ".\n"
        + f"Domain: {domain_name}\n"
        + (f"Namespace: {namespace}\n" if namespace else "")
        + "Config: " + config_str
        + req_section
        + conn_section
        + "\n\nRULES:\n"
        + "1. All variables MUST have default values\n"
        + "2. For EC2 Ubuntu 22.04 us-east-1 use AMI: ami-0c7217cdde317cfec\n"
        + "3. Use default VPC and subnets if none specified\n"
        + "4. Add lifecycle { ignore_changes = [tags, tags_all] } ONLY to resources that support tagging. NEVER add it to: aws_autoscaling_group, aws_s3_bucket_public_access_block, aws_s3_bucket_versioning, aws_s3_bucket_server_side_encryption_configuration, aws_iam_role_policy, aws_route53_record, aws_acm_certificate_validation\n"
        + "5. Ready to deploy with zero manual edits\n"
        + "6. NEVER use semicolons inside blocks — always use newlines between arguments\n"
        + "7. NEVER write single-line blocks like `ingress { a=1; b=2 }` — always expand to multi-line\n"
        + "8. Use resource \"aws_route53_zone\" to CREATE the zone, never data source\n"
        + "9. ALWAYS add allow_overwrite = true to every aws_route53_record resource\n"
        + "10. For cert_validation for_each, use this EXACT pattern to handle duplicate keys from wildcard+root certs:\n"
        + "    for_each = { for dvo in aws_acm_certificate.main.domain_validation_options : dvo.resource_record_name => { name=dvo.resource_record_name, record=dvo.resource_record_value, type=dvo.resource_record_type }... }\n"
        + "    Then use each.value[0].name, each.value[0].type, each.value[0].record\n"
        + f"6. ALWAYS declare variable 'domain_name' in variables.tf with default = \"{domain_name}\"\n"
        + f"7. ALWAYS set domain_name = \"{domain_name}\" in terraform.tfvars\n"
        + namespace_rule
        + "\nOUTPUT FORMAT — you MUST use exactly this format. IMPORTANT: keep each file SHORT (main.tf ≤ 80 lines, others ≤ 40 lines). Use variables for all values.\n"
        + "<<FILE:main.tf>>\n"
        + "# terraform main.tf content here\n"
        + "<</FILE>>\n"
        + "<<FILE:variables.tf>>\n"
        + "# terraform variables.tf content here\n"
        + "<</FILE>>\n"
        + "<<FILE:outputs.tf>>\n"
        + "# terraform outputs.tf content here\n"
        + "<</FILE>>\n"
        + "<<FILE:providers.tf>>\n"
        + "# terraform providers.tf content here\n"
        + "<</FILE>>\n"
        + "<<FILE:terraform.tfvars>>\n"
        + "# actual variable values here\n"
        + "<</FILE>>\n"
        + "Do not use markdown code blocks. Only use the <<FILE:name>> and <</FILE>> markers. ALL 5 FILES ARE REQUIRED."
    )
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=8192,
        messages=[{"role": "user", "content": prompt}]
    )
    response_text = message.content[0].text
    # DEBUG: save raw response to see what AI returns
    debug_path = os.path.join(BASE_DIR, "debug_response.txt")
    with open(debug_path, 'w', encoding='utf-8') as f:
        f.write(response_text)
    logger.info(f"DEBUG: raw response saved to {debug_path}")
    logger.info(f"DEBUG: first 500 chars: {response_text[:500]}")
    user_dir = get_user_output_dir(request)
    node_label = resource.config.get("label") or resource.config.get("name") or resource.resource_type
    node_id    = resource.config.get("node_id", "")
    base_name  = clean_folder_name(node_label)
    # Append node_id suffix to keep same-type nodes in separate folders (e.g. ec2-instance-n1)
    if node_id:
        base_name = base_name + "-" + node_id
    save_dir = os.path.join(user_dir, base_name)
    saved_files = extract_and_save_files(response_text, save_dir)
    # Return relative folder name for deploy panel
    rel_folder = os.path.relpath(save_dir, OUTPUT_DIR).replace("\\", "/")
    return {"response": response_text, "saved_files": saved_files, "location": save_dir, "folder": rel_folder}

@app.post("/generate-config")
@limiter.limit("20/minute")
def generate_config(resource: AWSResource, request: Request):
    require_auth(request)
    cfg_raw    = resource.config
    domain_name = cfg_raw.get("domain_name") or cfg_raw.get("global_domain_name") or "devopsai.com"
    namespace   = cfg_raw.get("namespace") or cfg_raw.get("k8s_namespace") or ""
    config_str = json.dumps(cfg_raw, indent=2)
    rt = resource.resource_type

    # Determine the expected file set based on service type
    FILE_HINTS = {
        # Docker
        "docker_file":          "Dockerfile",
        "docker_multistage":    "Dockerfile (multi-stage)",
        "docker_compose_dev":   "docker-compose.yml, .env",
        "docker_compose_prod":  "docker-compose.prod.yml, .env.example, Makefile",
        "docker_ignore":        ".dockerignore",
        "docker_network":       "docker-compose.yml",
        "docker_volume":        "docker-compose.yml",
        # Kubernetes
        "k8s_deploy":           "deployment.yaml, service.yaml, configmap.yaml",
        "k8s_statefulset":      "statefulset.yaml, service.yaml, pvc.yaml",
        "k8s_daemonset":        "daemonset.yaml, service.yaml",
        "k8s_job":              "job.yaml, configmap.yaml",
        "k8s_cronjob":          "cronjob.yaml",
        "k8s_ingress":          "ingress.yaml, service.yaml",
        "k8s_hpa":              "hpa.yaml, deployment.yaml",
        "k8s_pv":               "pv.yaml, pvc.yaml",
        "k8s_namespace":        "namespace.yaml, resource-quota.yaml",
        "k8s_configmap":        "configmap.yaml",
        "k8s_secret":           "secret.yaml",
        "k8s_rbac":             "serviceaccount.yaml, role.yaml, rolebinding.yaml",
        "k8s_networkpolicy":    "networkpolicy.yaml",
        "k8s_deploy_k8s":       "deployment.yaml, service.yaml",
        # EKS / K8s workloads
        "eks_fargate":          "fargate-profile.yaml, namespace.yaml",
        "eks_addon":            "addon.yaml",
        # CI/CD
        "gha_ci":               ".github/workflows/ci.yml",
        "gha_cd":               ".github/workflows/cd.yml",
        "gha_docker":           ".github/workflows/docker.yml",
        "gha_ecr":              ".github/workflows/ecr.yml",
        "gha_eks_deploy":       ".github/workflows/deploy-eks.yml",
        "gha_terraform":        ".github/workflows/terraform.yml",
        "gha_security":         ".github/workflows/security.yml",
        "gha_release":          ".github/workflows/release.yml",
        "jenkins_decl":         "Jenkinsfile",
        "jenkins_lib":          "vars/pipeline.groovy, src/org/Pipeline.groovy",
        "jenkins_docker_agent": "Jenkinsfile, agent.yaml",
        "jenkins_k8s_agent":    "Jenkinsfile, kubernetes-agent.yaml",
        "jenkins_sonar":        "Jenkinsfile, sonar-project.properties",
        "argocd_app":           "application.yaml",
        "argocd_project":       "appproject.yaml",
        "argocd_rbac":          "argocd-rbac-cm.yaml",
        "argocd_img_updater":   "image-updater-config.yaml",
        "gitlab_ci":            ".gitlab-ci.yml",
        "gitlab_docker":        ".gitlab-ci.yml",
        # Ansible
        "ansible_site":         "site.yml, ansible.cfg, requirements.yml",
        "ansible_nginx":        "playbook.yml, inventory.ini",
        "ansible_docker":       "playbook.yml, inventory.ini",
        "ansible_k8s":          "playbook.yml, inventory.ini",
        "ansible_ssl":          "playbook.yml",
        "ansible_harden":       "playbook.yml, handlers/main.yml",
        "ansible_deploy":       "playbook.yml, inventory.ini, group_vars/all.yml",
        "ansible_role":         "tasks/main.yml, defaults/main.yml, handlers/main.yml, README.md",
        "ansible_inv":          "inventory.ini, group_vars/all.yml, host_vars/host1.yml",
        "ansible_vault_enc":    "vault.yml, ansible.cfg",
        # Monitoring
        "prom_cfg":             "prometheus.yml, alerts.yml",
        "prom_rules":           "alert-rules.yml",
        "prom_alertmgr":        "alertmanager.yml",
        "prom_node_exp":        "docker-compose.yml",
        "prom_docker":          "docker-compose.yml, prometheus.yml",
        "grafana_ds":           "datasource.yaml",
        "grafana_k8s_dash":     "dashboard.json, configmap.yaml",
        "grafana_app_dash":     "dashboard.json",
        "loki_cfg":             "loki.yaml",
        "promtail_cfg":         "promtail.yaml",
        "jaeger":               "docker-compose.yml",
        # Web Servers
        "nginx_proxy":          "nginx.conf, sites-available/app.conf",
        "nginx_ssl":            "nginx.conf, ssl.conf",
        "nginx_lb":             "nginx.conf",
        "nginx_cache":          "nginx.conf",
        "nginx_rate":           "nginx.conf",
        "nginx_sec":            "nginx.conf, security-headers.conf",
        "nginx_docker":         "Dockerfile, nginx.conf",
        "apache_vhost":         "vhost.conf",
        "apache_ssl":           "ssl.conf",
        # Databases
        "redis_standalone":     "docker-compose.yml, redis.conf",
        "redis_cluster":        "docker-compose.yml, redis-cluster.conf",
        "redis_docker":         "docker-compose.yml, redis.conf",
        "postgres_docker":      "docker-compose.yml, init.sql",
        "postgres_init":        "init.sql, seed.sql",
        "postgres_backup":      "backup.sh, restore.sh",
        "mongo_docker":         "docker-compose.yml, mongod.conf",
        "mysql_docker":         "docker-compose.yml, my.cnf, init.sql",
        "mariadb_docker":       "docker-compose.yml, my.cnf",
        "mariadb_k8s":          "statefulset.yaml, service.yaml, secret.yaml",
        "cockroach_cluster":    "docker-compose.yml, cockroach.conf",
        "cockroach_docker":     "docker-compose.yml",
        "cockroach_k8s":        "statefulset.yaml, service.yaml",
        # Messaging
        "rabbitmq_broker":      "docker-compose.yml, rabbitmq.conf",
        "rabbitmq_cluster":     "docker-compose.yml, rabbitmq-cluster.conf",
        "rabbitmq_docker":      "docker-compose.yml, rabbitmq.conf",
        "rabbitmq_k8s":         "statefulset.yaml, service.yaml, configmap.yaml",
        "kafka_cluster":        "docker-compose.yml, server.properties",
        "kafka_topic":          "topic-config.properties",
        "kafka_consumer":       "consumer.properties",
        "kafka_docker":         "docker-compose.yml",
        "kafka_k8s":            "statefulset.yaml, service.yaml",
        "zookeeper":            "docker-compose.yml, zoo.cfg",
        "nats_server":          "nats-server.conf, docker-compose.yml",
        "nats_cluster":         "nats-cluster.conf, docker-compose.yml",
        "nats_docker":          "docker-compose.yml, nats.conf",
        "celery_worker":        "celery_worker.py, docker-compose.yml",
        "celery_beat":          "celery_beat.py, docker-compose.yml",
        "celery_flower":        "docker-compose.yml",
        "celery_docker":        "docker-compose.yml, celeryconfig.py",
        # Storage
        "minio_server":         "docker-compose.yml",
        "minio_docker":         "docker-compose.yml",
        "minio_k8s":            "deployment.yaml, service.yaml, pvc.yaml",
        "minio_bucket":         "bucket-policy.json",
        "harbor_registry":      "docker-compose.yml, harbor.yml",
        "harbor_docker":        "docker-compose.yml, harbor.yml",
        "harbor_k8s":           "values.yaml, namespace.yaml",
        "nexus_repo":           "docker-compose.yml",
        "nexus_docker":         "docker-compose.yml",
        "portainer_ce":         "docker-compose.yml",
        "portainer_docker":     "docker-compose.yml",
        # Security
        "vault_cfg":            "vault.hcl, docker-compose.yml",
        "vault_policy":         "policy.hcl",
        "vault_k8s_auth":       "auth-config.hcl, serviceaccount.yaml",
        "vault_kv":             "kv-config.hcl",
        "vault_pki":            "pki-config.hcl",
        "vault_docker":         "docker-compose.yml, vault.hcl",
        "trivy_scan":           ".github/workflows/trivy.yml, trivy.yaml",
        "sonarqube":            "docker-compose.yml, sonar-project.properties",
        "certbot":              "docker-compose.yml, renew.sh",
        "certmgr_issuer":       "clusterissuer.yaml, certificate.yaml",
        # Logging
        "es_cluster":           "elasticsearch.yml, docker-compose.yml",
        "es_docker":            "docker-compose.yml, elasticsearch.yml",
        "es_k8s":               "statefulset.yaml, service.yaml, configmap.yaml",
        "es_index":             "index-template.json",
        "kibana_docker":        "docker-compose.yml, kibana.yml",
        "kibana_k8s":           "deployment.yaml, service.yaml, configmap.yaml",
        "kibana_dashboard":     "dashboard.ndjson",
        "opensearch_cluster":   "docker-compose.yml, opensearch.yml",
        "opensearch_docker":    "docker-compose.yml",
        "fluentd_cfg":          "fluent.conf",
        "fluentd_docker":       "docker-compose.yml, fluent.conf, Dockerfile",
        "fluent_bit":           "fluent-bit.conf, parsers.conf",
        "fluentd_k8s":          "daemonset.yaml, configmap.yaml",
        "otel_collector":       "otel-collector.yaml",
        "otel_docker":          "docker-compose.yml, otel-collector.yaml",
        "otel_k8s":             "deployment.yaml, configmap.yaml",
        "tempo_cfg":            "tempo.yaml",
        "tempo_docker":         "docker-compose.yml, tempo.yaml",
        # Proxy
        "traefik_proxy":        "traefik.yml, docker-compose.yml",
        "traefik_docker":       "docker-compose.yml, traefik.yml",
        "traefik_k8s":          "deployment.yaml, ingressroute.yaml",
        "traefik_middleware":   "middleware.yaml",
        "haproxy_cfg":          "haproxy.cfg",
        "haproxy_docker":       "docker-compose.yml, haproxy.cfg",
        "haproxy_k8s":          "deployment.yaml, configmap.yaml",
        # Auth
        "keycloak_server":      "docker-compose.yml, keycloak.conf",
        "keycloak_docker":      "docker-compose.yml",
        "keycloak_k8s":         "deployment.yaml, service.yaml, configmap.yaml",
        "keycloak_realm":       "realm.json",
        # Service Mesh
        "linkerd_mesh":         "install.sh, values.yaml",
        "linkerd_profile":      "serviceprofile.yaml",
        "linkerd_docker":       "docker-compose.yml",
        "consul_server":        "consul.hcl, docker-compose.yml",
        "consul_docker":        "docker-compose.yml, consul.hcl",
        "consul_k8s":           "values.yaml, service-defaults.yaml",
        "consul_svcmesh":       "service-defaults.yaml, intentions.yaml",
    }

    file_hint = FILE_HINTS.get(rt, "")
    hint_line = (f"\nExpected files for this service: {file_hint}" if file_hint else "")

    # Build connected resources context
    connected = resource.config.get("connected_resources", [])
    conn_ids   = [c.get("type","") for c in connected]
    has_ec2    = any("ec2" in c for c in conn_ids)
    has_s3     = any("s3" in c for c in conn_ids)
    has_rds    = any("rds" in c or "aurora" in c or "db" in c for c in conn_ids)
    has_redis  = any("redis" in c or "elasticache" in c for c in conn_ids)

    # ── Special case: Docker Compose — generate a FULL production stack ──────────
    if rt in ("docker_compose_prod", "docker_compose_dev", "docker_file", "docker_multistage"):
        db_type   = "postgres"  # default
        if any("mysql" in c or "aurora" in c for c in conn_ids): db_type = "mysql"
        if any("mongo" in c for c in conn_ids): db_type = "mongodb"

        s3_env = ""
        if has_s3:
            s3_env = "\n        - AWS_S3_BUCKET=${S3_BUCKET_NAME}\n        - AWS_REGION=${AWS_REGION:-us-east-1}"

        compose_context = (
            f"\nConnected to: {'EC2 instance (deploy target), ' if has_ec2 else ''}"
            f"{'S3 bucket (file storage), ' if has_s3 else ''}"
            f"{'RDS database, ' if has_rds else ''}"
            f"{'Redis cache, ' if has_redis else ''}"
        ).rstrip(", ")

        prompt = (
            "Generate a COMPLETE production-ready Docker Compose stack.\n"
            + "Service type: " + rt + "\n"
            + f"Domain: {domain_name}\n"
            + (f"Namespace: {namespace}\n" if namespace else "")
            + "Config: " + config_str
            + compose_context + "\n\n"
            + "REQUIRED SERVICES IN docker-compose.prod.yml:\n"
            + "1. nginx — reverse proxy on port 80/443, proxies to app on port 3000\n"
            + "2. app — the main application (node:18-alpine or python:3.11-slim)\n"
            + f"3. {db_type} — database with persistent volume\n"
            + ("4. redis — cache/session store\n" if not has_redis else "")
            + ("5. aws-cli sidecar OR env vars for S3 access\n" if has_s3 else "")
            + "\nREQUIRED FILES:\n"
            + "<<FILE:docker-compose.prod.yml>> — full stack with all services, healthchecks, restart policies, volumes, networks\n"
            + "<<FILE:nginx/nginx.conf>> — nginx reverse proxy config with upstream to app\n"
            + f"<<FILE:nginx/ssl.conf>> — SSL config placeholder\n"
            + "<<FILE:.env.example>> — all environment variables with example values\n"
            + "<<FILE:Makefile>> — make up, make down, make logs, make deploy shortcuts\n"
            + "<<FILE:docker-compose.override.yml>> — dev overrides (hot reload, debug ports)\n\n"
            + "RULES:\n"
            + "1. All services must have healthchecks\n"
            + "2. All services use restart: unless-stopped\n"
            + "3. Use named volumes for database persistence\n"
            + "4. Use a custom bridge network\n"
            + "5. App reads DB connection from environment variables\n"
            + ("6. Include AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_BUCKET_NAME in .env.example\n" if has_s3 else "")
            + "\nOUTPUT FORMAT — use EXACTLY these markers:\n"
            + "<<FILE:filename>>\nfile content\n<</FILE>>\n"
            + "Repeat for each file. No markdown."
        )

    else:
        # ── All other non-AWS services ────────────────────────────────────────────
        conn_context = ""
        if connected:
            conn_labels = [c.get("label", c.get("type","")) for c in connected]
            conn_context = f"\nConnected resources on canvas: {', '.join(conn_labels)}"

        prompt = (
            "Generate complete production-ready config files for " + rt + ".\n"
            + f"Domain: {domain_name}\n"
            + (f"Namespace: {namespace}\n" if namespace else "")
            + "Config: " + config_str
            + hint_line
            + conn_context + "\n\n"
            + "RULES:\n"
            + "1. Use EXACT proper filenames and extensions for this service type\n"
            + "2. Keep each file concise (≤ 60 lines) and production-ready\n"
            + "3. All values must have sensible defaults\n"
            + f"4. Use domain '{domain_name}' wherever a hostname or domain is needed\n"
            + (f"5. Use namespace '{namespace}' in all Kubernetes resource metadata\n" if namespace else "")
            + "6. Do NOT use Terraform format (.tf files) for non-AWS services\n\n"
            + "OUTPUT FORMAT — use EXACTLY these markers, no markdown code blocks:\n"
            + "<<FILE:filename.ext>>\n"
            + "file content here\n"
            + "<</FILE>>\n"
            + "Repeat <<FILE:name>> ... <</FILE>> for each file."
        )
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=8192,
        messages=[{"role": "user", "content": prompt}]
    )
    response_text = message.content[0].text
    user_dir = get_user_output_dir(request)
    node_label = resource.config.get("label") or resource.config.get("name") or resource.resource_type
    node_id    = resource.config.get("node_id", "")
    base_name  = clean_folder_name(node_label)
    if node_id:
        base_name = base_name + "-" + node_id
    save_dir = os.path.join(user_dir, base_name)
    saved_files = extract_and_save_files(response_text, save_dir)
    rel_folder = os.path.relpath(save_dir, OUTPUT_DIR).replace("\\", "/")
    return {"response": response_text, "saved_files": saved_files, "location": save_dir, "folder": rel_folder}

# ── SECURITY SCAN ─────────────────────────────────────────────────────────────

SECURITY_RULES = [
    {"id": "S001", "severity": "HIGH",   "pattern": r'0\.0\.0\.0/0',          "message": "Security group open to the world (0.0.0.0/0) — restrict to known IPs"},
    {"id": "S002", "severity": "HIGH",   "pattern": r'password\s*=\s*"[^$][^"]{3,}"', "message": "Hardcoded password in Terraform — use variables or Secrets Manager"},
    {"id": "S003", "severity": "HIGH",   "pattern": r'secret\s*=\s*"[^$][^"]{3,}"',   "message": "Hardcoded secret value — use AWS Secrets Manager or SSM"},
    {"id": "S004", "severity": "MEDIUM", "pattern": r'publicly_accessible\s*=\s*true', "message": "RDS instance is publicly accessible — disable unless required"},
    {"id": "S005", "severity": "MEDIUM", "pattern": r'encrypted\s*=\s*false',  "message": "Storage not encrypted — enable encryption at rest"},
    {"id": "S006", "severity": "MEDIUM", "pattern": r'skip_final_snapshot\s*=\s*true', "message": "RDS skip_final_snapshot=true — enable snapshots for production"},
    {"id": "S007", "severity": "MEDIUM", "pattern": r'deletion_protection\s*=\s*false',"message": "Deletion protection disabled — enable for production databases"},
    {"id": "S008", "severity": "LOW",    "pattern": r'enable_dns_hostnames\s*=\s*false',"message": "DNS hostnames disabled in VPC — may cause service discovery issues"},
    {"id": "S009", "severity": "LOW",    "pattern": r'versioning\s*\{[^}]*enabled\s*=\s*false', "message": "S3 bucket versioning disabled — enable for data protection"},
    {"id": "S010", "severity": "HIGH",   "pattern": r'acl\s*=\s*"public-read"',"message": "S3 bucket is publicly readable — make private unless intentional"},
]

@app.post("/security/scan")
def security_scan(resource: AWSResource, request: Request):
    folder = resource.config.get("folder", "")
    if not folder:
        return {"error": "No folder specified", "score": 0, "issues": []}

    # Resolve path — try user dir first, then root output dir
    user_dir  = get_user_output_dir(request)
    full_path = os.path.join(user_dir, folder)
    if not os.path.exists(full_path):
        full_path = os.path.join(OUTPUT_DIR, folder)
    if not os.path.exists(full_path):
        return {"error": f"Folder not found: {folder}", "score": 0, "issues": []}

    # Collect all .tf file contents
    tf_content = ""
    files_scanned = 0
    for root, dirs, files in os.walk(full_path):
        dirs[:] = [d for d in dirs if d != ".terraform"]
        for fname in files:
            if fname.endswith(".tf"):
                try:
                    with open(os.path.join(root, fname), "r", encoding="utf-8", errors="replace") as f:
                        tf_content += f.read() + "\n"
                    files_scanned += 1
                except:
                    pass

    if not tf_content:
        return {"error": "No Terraform files found in folder", "score": 0, "issues": []}

    # Run rules
    issues = []
    for rule in SECURITY_RULES:
        if re.search(rule["pattern"], tf_content, re.IGNORECASE):
            issues.append({"id": rule["id"], "severity": rule["severity"], "message": rule["message"]})

    # Calculate score
    high   = sum(1 for i in issues if i["severity"] == "HIGH")
    medium = sum(1 for i in issues if i["severity"] == "MEDIUM")
    low    = sum(1 for i in issues if i["severity"] == "LOW")
    score  = max(0, 100 - (high * 20) - (medium * 8) - (low * 3))

    return {
        "score": score,
        "issues": issues,
        "files_scanned": files_scanned,
        "high": high,
        "medium": medium,
        "low": low
    }

# ── DEPLOY ROUTES ──────────────────────────────────────────────────────────────

def run_terraform_streaming(full_path: str, commands: list, aws_creds: dict = None):
    cache_dir = os.path.join(os.path.expanduser("~"), ".terraform.d", "plugin-cache")
    os.makedirs(cache_dir, exist_ok=True)
    # Use forward slashes — Terraform on Windows fails silently with backslash cache paths
    cache_dir_fwd = cache_dir.replace("\\", "/")
    env = os.environ.copy()
    env["TF_PLUGIN_CACHE_DIR"] = cache_dir_fwd
    # Allow cache to work even when lock file has different hashes
    env["TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE"] = "1"
    if aws_creds:
        env["AWS_ACCESS_KEY_ID"]     = aws_creds["access_key"]
        env["AWS_SECRET_ACCESS_KEY"] = aws_creds["secret_key"]
        env["AWS_DEFAULT_REGION"]    = aws_creds["region"]
    for cmd in commands:
        yield "data: \n\n"
        yield "data: === Running: " + " ".join(cmd) + " ===\n\n"
        is_init = "init" in cmd
        max_attempts = 5 if is_init else 1
        retry_wait   = 30  # seconds between retries — gives slow networks time to recover
        last_returncode = 0
        for attempt in range(1, max_attempts + 1):
            try:
                process = subprocess.Popen(
                    cmd, cwd=full_path,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, bufsize=1, env=env,
                    encoding='utf-8', errors='replace'
                )
                output_lines = []
                for line in process.stdout:
                    line = line.rstrip()
                    if line:
                        output_lines.append(line)
                        yield "data: " + line + "\n\n"
                process.wait()
                last_returncode = process.returncode
                if process.returncode == 0:
                    break
                # Retry on network errors during init
                is_network_err = any(
                    kw in "\n".join(output_lines)
                    for kw in ["context deadline exceeded", "connection refused",
                               "no such host", "timeout", "could not connect",
                               "request canceled", "dial tcp", "i/o timeout"]
                )
                if is_init and is_network_err and attempt < max_attempts:
                    yield f"data: ⚠ Network error — waiting {retry_wait}s then retrying (attempt {attempt}/{max_attempts-1})...\n\n"
                    import time; time.sleep(retry_wait)
                    continue
                break
            except FileNotFoundError:
                yield "data: ERROR: terraform not found. Please install Terraform.\n\n"
                yield "data: DEPLOY_FAILED\n\n"
                return
        if last_returncode != 0:
            yield "data: ERROR: Command failed with code " + str(last_returncode) + "\n\n"
            yield "data: DEPLOY_FAILED\n\n"
            return
        yield "data: SUCCESS: " + " ".join(cmd) + " completed!\n\n"

@app.post("/deploy/terraform")
def deploy_terraform(resource: AWSResource, request: Request):
    folder = resource.config.get("folder", "")
    if not folder:
        return {"error": "No folder specified"}
    # Support both relative (user_1/terraform_...) and bare folder names
    full_path = os.path.join(OUTPUT_DIR, folder)
    if not os.path.exists(full_path):
        # Try inside user dir
        user_dir = get_user_output_dir(request)
        full_path = os.path.join(user_dir, folder)
    if not os.path.exists(full_path):
        return {"error": "Folder not found: " + folder}
    environment = sanitize_tf_var(resource.config.get("environment", "dev"))
    region      = sanitize_tf_var(resource.config.get("region", "us-east-1"))
    domain      = sanitize_tf_var(resource.config.get("domain_name", ""))
    user = require_auth(request)
    aws_creds = get_user_aws_creds(user["id"])
    logger.info(f"Deploy started by {user['email']} for folder: {folder}")

    def run():
        yield "data: === Starting Terraform Deploy ===\n\n"
        yield f"data: Environment: {environment} | Region: {region}\n\n"
        if domain:
            yield f"data: Domain: {domain}\n\n"
        if aws_creds:
            yield f"data: Using credentials for user: {user['email']}\n\n"
        else:
            yield "data: WARNING: No AWS credentials configured — using system defaults\n\n"
        yield "data: Folder: " + os.path.basename(full_path) + "\n\n"
        # Only pass -var flags that are actually declared in this module's variables.tf
        vars_tf_path = os.path.join(full_path, "variables.tf")
        declared_vars: set = set()
        if os.path.exists(vars_tf_path):
            with open(vars_tf_path, encoding="utf-8") as _vf:
                for _m in re.findall(r'variable\s+"(\w+)"', _vf.read()):
                    declared_vars.add(_m)
        tf_vars = []
        if "environment" in declared_vars:
            tf_vars += ["-var", f"environment={environment}"]
        if "aws_region" in declared_vars:
            tf_vars += ["-var", f"aws_region={region}"]
        if domain and "domain_name" in declared_vars:
            tf_vars += ["-var", f"domain_name={domain}"]
        # Check if module has ACM cert + cert_validation (needs two-phase apply)
        main_tf_path = os.path.join(full_path, "main.tf")
        has_acm_validation = False
        if os.path.exists(main_tf_path):
            with open(main_tf_path, encoding="utf-8") as _mf:
                _content = _mf.read()
                has_acm_validation = ("aws_acm_certificate" in _content and
                                      "cert_validation" in _content)

        if has_acm_validation:
            # Phase 1: create ACM cert + Route53 zone so validation options become known
            yield "data: === Phase 1: Creating ACM certificate and Route53 zone ===\n\n"
            phase1_failed = False
            for chunk in run_terraform_streaming(full_path, [
                ["terraform", "init", "-no-color"],
                ["terraform", "apply", "-auto-approve", "-no-color",
                 "-target=aws_acm_certificate.main",
                 "-target=aws_route53_zone.main"] + tf_vars
            ], aws_creds=aws_creds):
                if "DEPLOY_FAILED" in chunk:
                    phase1_failed = True
                yield chunk
            if phase1_failed:
                return
            yield "data: === Phase 2: Creating all remaining resources ===\n\n"
            yield from run_terraform_streaming(full_path, [
                ["terraform", "apply", "-auto-approve", "-no-color"] + tf_vars
            ], aws_creds=aws_creds)
        else:
            yield from run_terraform_streaming(full_path, [
                ["terraform", "init", "-no-color"],
                ["terraform", "plan", "-no-color"] + tf_vars,
                ["terraform", "apply", "-auto-approve", "-no-color"] + tf_vars
            ], aws_creds=aws_creds)
        # Capture terraform outputs
        yield "data: \n\n"
        yield "data: === TERRAFORM OUTPUTS ===\n\n"
        try:
            tf_env = os.environ.copy()
            if aws_creds:
                tf_env["AWS_ACCESS_KEY_ID"]     = aws_creds["access_key"]
                tf_env["AWS_SECRET_ACCESS_KEY"] = aws_creds["secret_key"]
                tf_env["AWS_DEFAULT_REGION"]    = aws_creds["region"]
            out_result = subprocess.run(
                ["terraform", "output", "-json"],
                cwd=full_path, capture_output=True, text=True, env=tf_env
            )
            if out_result.returncode == 0 and out_result.stdout.strip():
                try:
                    outputs = json.loads(out_result.stdout)
                    if outputs:
                        for key, val in outputs.items():
                            v = val.get("value", "") if isinstance(val, dict) else val
                            yield f"data: {key}: {v}\n\n"
                        # Highlight key outputs
                        alb = next((outputs[k]["value"] for k in outputs if "alb" in k.lower() or "lb_dns" in k.lower() or "load_balancer" in k.lower()), None)
                        ip  = next((outputs[k]["value"] for k in outputs if "public_ip" in k.lower() or "elastic_ip" in k.lower()), None)
                        url = next((outputs[k]["value"] for k in outputs if "url" in k.lower() or "endpoint" in k.lower()), None)
                        ns  = next((outputs[k]["value"] for k in outputs if "nameserver" in k.lower() or "name_server" in k.lower()), None)
                        if alb:  yield f"data: ALB DNS → {alb}\n\n"
                        if ip:   yield f"data: Public IP → {ip}\n\n"
                        if url:  yield f"data: Endpoint → {url}\n\n"
                        if ns:   yield f"data: Route53 Nameservers → {ns}\n\n"
                    else:
                        yield "data: (no outputs defined in outputs.tf)\n\n"
                except:
                    yield f"data: {out_result.stdout[:500]}\n\n"
            else:
                yield "data: (no outputs available)\n\n"
        except Exception as e:
            yield f"data: Could not read outputs: {e}\n\n"
        yield "data: \n\n"
        yield "data: === DEPLOY COMPLETE! AWS resources created successfully! ===\n\n"
        if domain:
            yield f"data: Your app → https://{domain}\n\n"
        yield "data: DEPLOY_SUCCESS\n\n"

    return StreamingResponse(run(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})

def boto3_destroy_resources(full_path: str, aws_creds: dict, region: str):
    """Read terraform.tfstate and delete every tracked AWS resource using boto3."""
    import json, time
    state_path = os.path.join(full_path, "terraform.tfstate")
    if not os.path.exists(state_path):
        yield "data: ⚠ No state file found — nothing to destroy\n\n"
        return

    with open(state_path) as f:
        state = json.load(f)

    resources = state.get("resources", [])
    if not resources:
        yield "data: ⚠ State file is empty — nothing to destroy\n\n"
        return

    # Build boto3 session
    if aws_creds:
        import boto3
        session = boto3.Session(
            aws_access_key_id=aws_creds["access_key"],
            aws_secret_access_key=aws_creds["secret_key"],
            region_name=region
        )
    else:
        import boto3
        session = boto3.Session(region_name=region)

    # Collect resource IDs by type
    def get_ids(rtype):
        ids = []
        for r in resources:
            if r.get("type") == rtype:
                for inst in r.get("instances", []):
                    att = inst.get("attributes", {})
                    ids.append(att.get("id", ""))
        return [i for i in ids if i]

    def get_attr(rtype, attr):
        for r in resources:
            if r.get("type") == rtype:
                for inst in r.get("instances", []):
                    val = inst.get("attributes", {}).get(attr)
                    if val:
                        return val
        return None

    errors = []

    # 1. Remove acm_certificate_validation (skip — no real AWS resource to delete)
    yield "data: → Skipping ACM certificate validation (DNS only)\n\n"

    # 2. Delete ALB listeners
    try:
        ec2lbc = session.client("elbv2")
        for lb_arn in get_ids("aws_lb"):
            try:
                listeners = ec2lbc.describe_listeners(LoadBalancerArn=lb_arn)["Listeners"]
                for l in listeners:
                    ec2lbc.delete_listener(ListenerArn=l["ListenerArn"])
                    yield f"data: ✓ Deleted listener {l['ListenerArn'][-30:]}\n\n"
            except Exception as e:
                errors.append(f"listener: {e}")
    except Exception as e:
        errors.append(f"elbv2 client: {e}")

    # 3. Delete Auto Scaling Groups (force — terminates instances)
    try:
        asgc = session.client("autoscaling")
        for asg_id in get_ids("aws_autoscaling_group"):
            try:
                asgc.delete_auto_scaling_group(AutoScalingGroupName=asg_id, ForceDelete=True)
                yield f"data: ✓ Deleted ASG {asg_id} (instances terminating)\n\n"
            except Exception as e:
                if "not found" not in str(e).lower():
                    errors.append(f"ASG {asg_id}: {e}")
    except Exception as e:
        errors.append(f"autoscaling client: {e}")

    # 4. Delete Load Balancers
    try:
        elbv2 = session.client("elbv2")
        for lb_arn in get_ids("aws_lb"):
            try:
                elbv2.delete_load_balancer(LoadBalancerArn=lb_arn)
                yield f"data: ✓ Deleted ALB {lb_arn[-40:]}\n\n"
                time.sleep(2)
            except Exception as e:
                if "not found" not in str(e).lower():
                    errors.append(f"ALB {lb_arn}: {e}")
    except Exception as e:
        errors.append(f"elbv2 delete: {e}")

    # 5. Delete Target Groups
    try:
        for tg_arn in get_ids("aws_lb_target_group"):
            try:
                elbv2.delete_target_group(TargetGroupArn=tg_arn)
                yield f"data: ✓ Deleted target group {tg_arn[-40:]}\n\n"
            except Exception as e:
                if "not found" not in str(e).lower():
                    errors.append(f"TG {tg_arn}: {e}")
    except Exception as e:
        errors.append(f"TG delete: {e}")

    # 6. Delete Launch Templates
    try:
        ec2 = session.client("ec2")
        for lt_id in get_ids("aws_launch_template"):
            try:
                ec2.delete_launch_template(LaunchTemplateId=lt_id)
                yield f"data: ✓ Deleted launch template {lt_id}\n\n"
            except Exception as e:
                if "not found" not in str(e).lower() and "InvalidLaunchTemplateId" not in str(e):
                    errors.append(f"LT {lt_id}: {e}")
    except Exception as e:
        errors.append(f"LT delete: {e}")

    # 7. Wait a bit for ASG instances to start terminating before deleting SGs
    yield "data: ⏳ Waiting 15s for ASG instances to begin termination...\n\n"
    time.sleep(15)

    # 8. Delete Security Groups
    try:
        for sg_id in get_ids("aws_security_group"):
            try:
                ec2.delete_security_group(GroupId=sg_id)
                yield f"data: ✓ Deleted security group {sg_id}\n\n"
            except Exception as e:
                if "not found" not in str(e).lower() and "InvalidGroup" not in str(e):
                    errors.append(f"SG {sg_id}: {e}")
    except Exception as e:
        errors.append(f"SG delete: {e}")

    # 9. Delete IAM instance profiles (detach role first)
    try:
        iam = session.client("iam")
        for profile_id in get_ids("aws_iam_instance_profile"):
            try:
                profile = iam.get_instance_profile(InstanceProfileName=profile_id)
                for role in profile["InstanceProfile"]["Roles"]:
                    iam.remove_role_from_instance_profile(
                        InstanceProfileName=profile_id, RoleName=role["RoleName"])
                iam.delete_instance_profile(InstanceProfileName=profile_id)
                yield f"data: ✓ Deleted instance profile {profile_id}\n\n"
            except Exception as e:
                if "NoSuchEntity" not in str(e):
                    errors.append(f"Profile {profile_id}: {e}")
    except Exception as e:
        errors.append(f"IAM profile: {e}")

    # 10. Delete IAM role policies then roles
    try:
        for role_id in get_ids("aws_iam_role"):
            try:
                # Delete inline policies
                policies = iam.list_role_policies(RoleName=role_id)["PolicyNames"]
                for p in policies:
                    iam.delete_role_policy(RoleName=role_id, PolicyName=p)
                iam.delete_role(RoleName=role_id)
                yield f"data: ✓ Deleted IAM role {role_id}\n\n"
            except Exception as e:
                if "NoSuchEntity" not in str(e):
                    errors.append(f"Role {role_id}: {e}")
    except Exception as e:
        errors.append(f"IAM role: {e}")

    # 11. Delete S3 buckets (empty first)
    try:
        s3 = session.resource("s3")
        for bucket_id in get_ids("aws_s3_bucket"):
            try:
                bucket = s3.Bucket(bucket_id)
                bucket.object_versions.delete()
                bucket.objects.all().delete()
                bucket.delete()
                yield f"data: ✓ Deleted S3 bucket {bucket_id}\n\n"
            except Exception as e:
                if "NoSuchBucket" not in str(e):
                    errors.append(f"S3 {bucket_id}: {e}")
    except Exception as e:
        errors.append(f"S3: {e}")

    # 12. Delete ACM certificates
    try:
        acm = session.client("acm")
        for cert_arn in get_ids("aws_acm_certificate"):
            try:
                acm.delete_certificate(CertificateArn=cert_arn)
                yield f"data: ✓ Deleted ACM certificate {cert_arn[-30:]}\n\n"
            except Exception as e:
                if "ResourceNotFoundException" not in str(e):
                    errors.append(f"ACM {cert_arn}: {e}")
    except Exception as e:
        errors.append(f"ACM: {e}")

    # 13. Delete Route53 records then zones
    try:
        r53 = session.client("route53")
        for zone_id in get_ids("aws_route53_zone"):
            try:
                # Delete all non-NS/SOA records first
                records = r53.list_resource_record_sets(HostedZoneId=zone_id)["ResourceRecordSets"]
                deletable = [r for r in records if r["Type"] not in ("NS", "SOA")]
                if deletable:
                    changes = [{"Action": "DELETE", "ResourceRecordSet": r} for r in deletable]
                    r53.change_resource_record_sets(HostedZoneId=zone_id,
                        ChangeBatch={"Changes": changes})
                r53.delete_hosted_zone(Id=zone_id)
                yield f"data: ✓ Deleted Route53 zone {zone_id}\n\n"
            except Exception as e:
                if "NoSuchHostedZone" not in str(e):
                    errors.append(f"R53 {zone_id}: {e}")
    except Exception as e:
        errors.append(f"R53: {e}")

    if errors:
        for err in errors:
            yield f"data: ⚠ {err}\n\n"
    else:
        yield "data: ✓ All resources deleted successfully\n\n"


@app.post("/destroy/terraform")
def destroy_terraform(resource: AWSResource, request: Request):
    folder = resource.config.get("folder", "")
    if not folder:
        return {"error": "No folder specified"}
    full_path = os.path.join(OUTPUT_DIR, folder)
    if not os.path.exists(full_path):
        user_dir = get_user_output_dir(request)
        full_path = os.path.join(user_dir, folder)
    if not os.path.exists(full_path):
        return {"error": "Folder not found: " + folder}
    environment = resource.config.get("environment", "dev")
    region = resource.config.get("region", "us-east-1")
    user = get_current_user(request)
    aws_creds = get_user_aws_creds(user["id"]) if user else None

    def run():
        yield "data: === Starting Destroy ===\n\n"
        yield f"data: Environment: {environment} | Region: {region}\n\n"
        if aws_creds:
            yield f"data: Using credentials for user: {user['email']}\n\n"
        else:
            yield "data: WARNING: No AWS credentials configured — using system defaults\n\n"
        yield "data: Folder: " + os.path.basename(full_path) + "\n\n"

        # Use boto3 direct deletion (reads state file, no DNS hang)
        yield from boto3_destroy_resources(full_path, aws_creds, region)

        # Clear the terraform state so next deploy starts fresh
        state_path = os.path.join(full_path, "terraform.tfstate")
        backup_path = os.path.join(full_path, "terraform.tfstate.backup")
        for p in [state_path, backup_path]:
            try:
                if os.path.exists(p):
                    os.remove(p)
            except Exception:
                pass

        yield "data: \n\n"
        yield "data: === DESTROY COMPLETE! All AWS resources deleted! ===\n\n"
        yield "data: DEPLOY_SUCCESS\n\n"

    return StreamingResponse(run(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})

# ── AWS CREDENTIALS ROUTES ─────────────────────────────────────────────────────

@app.post("/aws/credentials")
def save_aws_credentials(creds: AWSCreds, request: Request):
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not logged in")
    now = datetime.now().isoformat()
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''INSERT INTO aws_credentials (user_id, access_key, secret_key, region, updated_at)
                 VALUES (?, ?, ?, ?, ?)
                 ON CONFLICT(user_id) DO UPDATE SET
                   access_key=excluded.access_key,
                   secret_key=excluded.secret_key,
                   region=excluded.region,
                   updated_at=excluded.updated_at''',
              (user["id"], creds.access_key, creds.secret_key, creds.region, now))
    conn.commit()
    conn.close()
    return {"saved": True, "region": creds.region, "updated_at": now}

@app.get("/aws/credentials")
def get_aws_credentials(request: Request):
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not logged in")
    creds = get_user_aws_creds(user["id"])
    if not creds:
        return {"configured": False}
    # Mask the keys
    ak = creds["access_key"]
    sk = creds["secret_key"]
    return {
        "configured": True,
        "access_key_masked": ak[:4] + "****" + ak[-4:] if len(ak) > 8 else "****",
        "secret_key_masked": "****" + sk[-4:] if len(sk) > 4 else "****",
        "region": creds["region"]
    }

@app.delete("/aws/credentials")
def delete_aws_credentials(request: Request):
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not logged in")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM aws_credentials WHERE user_id=?", (user["id"],))
    conn.commit()
    conn.close()
    return {"deleted": True}

@app.post("/aws/credentials/test")
def test_aws_credentials(request: Request):
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not logged in")
    creds = get_user_aws_creds(user["id"])
    if not creds:
        raise HTTPException(status_code=400, detail="No AWS credentials configured")
    try:
        sts = boto3.client(
            "sts",
            aws_access_key_id=creds["access_key"],
            aws_secret_access_key=creds["secret_key"],
            region_name=creds["region"]
        )
        identity = sts.get_caller_identity()
        return {
            "valid": True,
            "account_id": identity["Account"],
            "arn": identity["Arn"],
            "user_id": identity["UserId"],
            "region": creds["region"]
        }
    except Exception as e:
        return {"valid": False, "error": str(e)}

# ── GITHUB PUSH ───────────────────────────────────────────────────────────────

class GitHubPushRequest(BaseModel):
    folder: str = ""
    repo_name: str
    commit_message: str = "Auto-push from AI DevOps Platform"
    canvas_data: str = ""

@app.post("/github/push")
def github_push(req: GitHubPushRequest):
    github_token    = os.getenv("GITHUB_TOKEN", "")
    github_username = os.getenv("GITHUB_USERNAME", "")

    if not github_token:
        raise HTTPException(status_code=400, detail="GITHUB_TOKEN must be set in .env file. Get it from github.com → Settings → Developer Settings → Personal Access Tokens")

    # Accept full GitHub URL or just repo name
    # e.g. https://github.com/vijayrajkoduru/DevopsAI.git  OR  DevopsAI
    repo_input = req.repo_name.strip()

    # Extract username and repo from full URL if provided
    if "github.com" in repo_input:
        # Parse: https://github.com/username/reponame.git
        parts = repo_input.replace("https://github.com/", "").replace("http://github.com/", "").rstrip("/").rstrip(".git").split("/")
        if len(parts) >= 2:
            github_username = parts[0]  # use username from URL
            repo_name = parts[1].replace(".git", "")
        elif len(parts) == 1:
            repo_name = parts[0].replace(".git", "")
        else:
            raise HTTPException(status_code=400, detail="Invalid GitHub URL. Use: https://github.com/username/reponame")
    else:
        # Just repo name provided — use username from .env
        repo_name = repo_input.replace(".git", "")
        if not github_username:
            raise HTTPException(status_code=400, detail=(
                "Step 1: Add this to your .env file:\n"
                "  GITHUB_USERNAME=yourGitHubUsername\n\n"
                "Step 2: Restart the server:\n"
                "  uvicorn main:app --reload\n\n"
                "OR paste the full URL in the field:\n"
                "  https://github.com/vijayrajkoduru/DevopsAI"
            ))

    if not repo_name:
        raise HTTPException(status_code=400, detail="Could not extract repo name. Provide full URL or just repo name.")

    # Always push the entire generated/ directory as one repo
    full_path = os.path.abspath(OUTPUT_DIR)
    os.makedirs(full_path, exist_ok=True)

    # Save canvas snapshot so it can be restored on import
    if req.canvas_data:
        canvas_file = os.path.join(full_path, "devopsai-canvas.json")
        with open(canvas_file, "w", encoding="utf-8") as f:
            f.write(req.canvas_data)

    remote_url = f"https://{github_username}:{github_token}@github.com/{github_username}/{repo_name}.git"
    safe_url   = f"https://github.com/{github_username}/{repo_name}.git"

    def run():
        yield "data: === Starting GitHub Push (Full Project) ===\n\n"
        yield f"data: Pushing entire generated/ folder to: {safe_url}\n\n"

        # Count files
        total_files = sum(len(files) for _, _, files in os.walk(full_path))
        yield f"data: Total files to push: {total_files}\n\n"

        # Write a README
        readme_path = os.path.join(full_path, "README.md")
        with open(readme_path, "w") as f:
            f.write(f"# {req.repo_name}\n\nGenerated by AI DevOps Platform\n\n")
            f.write(f"Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            f.write("## Structure\n\n")
            for item in sorted(os.listdir(full_path)):
                item_path = os.path.join(full_path, item)
                if os.path.isdir(item_path) and item != ".git":
                    file_count = sum(len(files) for _, _, files in os.walk(item_path))
                    f.write(f"- `{item}/` — {file_count} files\n")
            f.write("\n## Deployment\n\n```bash\ncd <service-folder>\nterraform init && terraform apply\n```\n")

        commands = [
            (["git", "init"],                                    full_path),
            (["git", "config", "user.email", "devops@ai.com"],  full_path),
            (["git", "config", "user.name",  github_username],  full_path),
            (["git", "add", "."],                                full_path),
            (["git", "commit", "-m", req.commit_message],        full_path),
            (["git", "branch", "-M", "main"],                    full_path),
            (["git", "remote", "remove", "origin"],              full_path),
            (["git", "remote", "add", "origin", remote_url],    full_path),
            (["git", "push", "-u", "origin", "main", "--force"], full_path),
        ]

        for cmd, cwd in commands:
            display_cmd = " ".join(cmd).replace(github_token, "***")
            yield f"data: $ {display_cmd}\n\n"
            try:
                result = subprocess.run(
                    cmd, cwd=cwd,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, encoding="utf-8", errors="replace"
                )
                for line in result.stdout.splitlines():
                    if line.strip():
                        yield f"data: {line}\n\n"
                if result.returncode != 0 and "remote remove" not in " ".join(cmd):
                    yield f"data: ERROR: command failed (code {result.returncode})\n\n"
                    yield "data: GITHUB_FAILED\n\n"
                    return
            except FileNotFoundError:
                yield "data: ERROR: git not found. Please install Git.\n\n"
                yield "data: GITHUB_FAILED\n\n"
                return

        yield f"data: \n\n"
        yield f"data: === ALL FILES PUSHED! View at {safe_url} ===\n\n"
        yield "data: GITHUB_SUCCESS\n\n"

    return StreamingResponse(run(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})

@app.get("/deploy/folders")
def get_deploy_folders(request: Request):
    folders = []
    user_dir = get_user_output_dir(request)
    def scan_dir(base, prefix=""):
        if not os.path.exists(base):
            return
        for f in os.listdir(base):
            full = os.path.join(base, f)
            if os.path.isdir(full):
                rel = (prefix + "/" + f).lstrip("/")
                try:
                    files = os.listdir(full)
                    has_tf = any(file.endswith(".tf") for file in files)
                    if has_tf:
                        folders.append({"name": rel, "path": full})
                    else:
                        scan_dir(full, rel)
                except:
                    pass
    scan_dir(user_dir)
    return {"folders": folders}

# ── OPEN IN VS CODE ────────────────────────────────────────────────────────────

class VSCodeRequest(BaseModel):
    folder: str

@app.post("/open-in-vscode")
def open_in_vscode(req: VSCodeRequest, request: Request):
    require_auth(request)
    full_path = safe_path(OUTPUT_DIR, req.folder)  # path traversal check
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Folder not found")
    try:
        subprocess.Popen(["code", full_path], shell=False)  # shell=False always
        return {"opened": True, "path": full_path}
    except FileNotFoundError:
        vscode_paths = [
            os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "Microsoft VS Code", "Code.exe"),
            r"C:\Program Files\Microsoft VS Code\Code.exe",
        ]
        for vspath in vscode_paths:
            if os.path.exists(vspath):
                subprocess.Popen([vspath, full_path], shell=False)
                return {"opened": True, "path": full_path}
        raise HTTPException(status_code=500, detail="VS Code not found in PATH")

# ── DELETE GENERATED FOLDER ────────────────────────────────────────────────────

@app.delete("/generated/{folder_name:path}")
def delete_generated_folder(folder_name: str, request: Request):
    require_auth(request)
    full_path = safe_path(OUTPUT_DIR, folder_name)
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Folder not found")
    if not os.path.isdir(full_path):
        raise HTTPException(status_code=400, detail="Not a directory")
    import stat, time
    def _force_remove(func, path, exc_info):
        try:
            os.chmod(path, stat.S_IWRITE)
            func(path)
        except Exception:
            pass
    # First try Python rmtree
    try:
        shutil.rmtree(full_path, onerror=_force_remove)
    except Exception:
        pass
    # If still exists, use Windows rd /s /q command (bypasses most locks)
    if os.path.exists(full_path):
        try:
            result = subprocess.run(
                f'rd /s /q "{full_path}"',
                shell=True, capture_output=True, timeout=10
            )
            time.sleep(0.5)
        except Exception:
            pass
    # Final check
    if os.path.exists(full_path):
        raise HTTPException(status_code=409, detail="Folder is locked by VS Code. Close VS Code Explorer on that folder and try again.")
    logger.info(f"Deleted generated folder: {full_path}")
    return {"deleted": folder_name}

# ── DOWNLOAD AS ZIP ────────────────────────────────────────────────────────────

@app.get("/download/zip/{folder_name:path}")
def download_zip(folder_name: str, request: Request):
    require_auth(request)
    from fastapi.responses import StreamingResponse as SR
    import zipfile, io
    full_path = safe_path(OUTPUT_DIR, folder_name)  # prevents path traversal
    if not os.path.exists(full_path):
        raise HTTPException(status_code=404, detail="Folder not found")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(full_path):
            # Skip .terraform directories (large provider binaries)
            dirs[:] = [d for d in dirs if d != ".terraform"]
            for file in files:
                if file.endswith(".tfstate") or file.endswith(".tfstate.backup"):
                    continue
                fpath = os.path.join(root, file)
                arcname = os.path.relpath(fpath, os.path.dirname(full_path))
                zf.write(fpath, arcname)
    buf.seek(0)

    safe_name = folder_name.replace("/", "_").replace("\\", "_")
    return SR(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={safe_name}.zip"}
    )


# ── STRIPE PAYMENT ────────────────────────────────────────────────────────────

STRIPE_SECRET_KEY     = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")
APP_BASE_URL          = os.getenv("APP_BASE_URL", "https://devopsai.com")

# Map Stripe Price IDs to plan names — set these in .env
STRIPE_PRICE_PRO      = os.getenv("STRIPE_PRICE_PRO", "")    # e.g. price_xxxx
STRIPE_PRICE_TEAM     = os.getenv("STRIPE_PRICE_TEAM", "")   # e.g. price_yyyy

PLAN_LIMITS = {
    "free":  {"deploys": 3,  "nodes": 10, "ai_calls": 5},
    "pro":   {"deploys": 50, "nodes": 100,"ai_calls": 200},
    "team":  {"deploys": -1, "nodes": -1, "ai_calls": -1},  # unlimited
}

class CheckoutRequest(BaseModel):
    plan: str  # "pro" or "team"

@app.post("/payment/create-checkout")
def create_checkout(req: CheckoutRequest, request: Request):
    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Stripe not configured. Add STRIPE_SECRET_KEY to .env")
    user = get_current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail="Not logged in")

    price_id = STRIPE_PRICE_PRO if req.plan == "pro" else STRIPE_PRICE_TEAM
    if not price_id:
        raise HTTPException(status_code=500, detail=f"STRIPE_PRICE_{req.plan.upper()} not set in .env")

    try:
        import stripe
        stripe.api_key = STRIPE_SECRET_KEY
        session = stripe.checkout.Session.create(
            payment_method_types=["card"],
            mode="subscription",
            line_items=[{"price": price_id, "quantity": 1}],
            customer_email=user["email"],
            metadata={"user_id": str(user["id"]), "plan": req.plan},
            success_url=APP_BASE_URL + "/payment/success?session_id={CHECKOUT_SESSION_ID}",
            cancel_url=APP_BASE_URL + "/landing?payment=cancelled",
        )
        return {"url": session.url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/payment/success", response_class=HTMLResponse)
def payment_success(session_id: str = ""):
    return """<!DOCTYPE html><html><head><title>Payment Successful</title>
<style>body{background:#0a0a12;color:#e0e0e0;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;flex-direction:column;gap:16px;text-align:center}
h1{color:#4ade80;font-size:28px}p{color:#888;max-width:400px}a{color:#a78bfa;text-decoration:none;border:1px solid #6c47ff;padding:8px 20px;border-radius:7px}</style></head>
<body><div style="font-size:48px">🎉</div><h1>Payment Successful!</h1>
<p>Your plan has been upgraded. You can now use all the features of the platform.</p>
<a href="/app">Go to Platform →</a></body></html>"""

@app.post("/payment/webhook")
async def stripe_webhook(request: Request):
    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Stripe not configured")
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature", "")
    if not STRIPE_WEBHOOK_SECRET:
        raise HTTPException(status_code=500, detail="Stripe webhook secret not configured")
    try:
        import stripe
        stripe.api_key = STRIPE_SECRET_KEY
        event = stripe.Webhook.construct_event(payload, sig_header, STRIPE_WEBHOOK_SECRET)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    if event["type"] == "checkout.session.completed":
        # Initial purchase — metadata has user_id and plan
        obj = event["data"]["object"]
        meta = obj.get("metadata", {})
        user_id = meta.get("user_id")
        plan    = meta.get("plan", "pro")
        if user_id:
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute("UPDATE users SET plan=? WHERE id=?", (plan, int(user_id)))
            conn.commit()
            conn.close()

    if event["type"] in ("customer.subscription.deleted", "customer.subscription.paused"):
        # Subscription cancelled — downgrade to free using customer email from Stripe
        obj = event["data"]["object"]
        customer_id = obj.get("customer", "")
        if customer_id:
            try:
                import stripe
                stripe.api_key = STRIPE_SECRET_KEY
                cust = stripe.Customer.retrieve(customer_id)
                cust_email = cust.get("email", "")
                if cust_email:
                    conn = sqlite3.connect(DB_PATH)
                    c = conn.cursor()
                    c.execute("UPDATE users SET plan='free' WHERE email=?", (cust_email,))
                    conn.commit()
                    conn.close()
            except:
                pass

    return {"received": True}

@app.get("/payment/plans")
def get_plans():
    return {
        "plans": [
            {"id": "free",  "name": "Free",  "price": 0,   "currency": "USD", "limits": PLAN_LIMITS["free"]},
            {"id": "pro",   "name": "Pro",   "price": 29,  "currency": "USD", "limits": PLAN_LIMITS["pro"]},
            {"id": "team",  "name": "Team",  "price": 99,  "currency": "USD", "limits": PLAN_LIMITS["team"]},
        ]
    }

# ── CHAT ASSISTANT ─────────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    messages: list
    system: str = ""

@app.post("/chat")
@limiter.limit("30/minute")
def chat(req: ChatRequest, request: Request):
    require_auth(request)
    system_prompt = req.system or (
        "You are an expert DevOps AI Assistant embedded inside an AI DevOps Platform canvas tool. "
        "You help users with AWS architecture, Terraform, Docker, Kubernetes, CI/CD pipelines, "
        "infrastructure design, cost optimization, security best practices, and all things DevOps. "
        "Be concise, practical and professional. Use markdown formatting where helpful."
    )
    max_tok = 4096 if "ARCH" in system_prompt else 1500

    # Ensure messages have proper format (handle both string and array content)
    clean_messages = []
    for msg in req.messages:
        if isinstance(msg, dict):
            clean_messages.append(msg)
        else:
            clean_messages.append({"role": "user", "content": str(msg)})

    def stream():
        try:
            with client.messages.stream(
                model="claude-sonnet-4-6",
                max_tokens=max_tok,
                system=system_prompt,
                messages=clean_messages
            ) as s:
                for text in s.text_stream:
                    safe = text.replace('\n', '\\n')
                    yield f"data: {safe}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            logger.error(f"Chat stream error: {e}")
            err_msg = str(e).replace('\n', ' ')
            yield f"data: [ERROR] {err_msg}\n\n"
            yield "data: [DONE]\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})
# ── GITHUB IMPORT → CANVAS ────────────────────────────────────────────────────

class GitHubImportRequest(BaseModel):
    repo_url: str
    branch: str = "main"

@app.post("/github/import")
def github_import(req: GitHubImportRequest, request: Request):
    """Clone a GitHub repo, scan all Terraform files, return services for canvas"""
    github_token = os.getenv("GITHUB_TOKEN", "")

    # Parse repo URL → extract owner/repo
    repo_input = req.repo_url.strip().rstrip("/").replace(".git", "")
    if "github.com" in repo_input:
        parts = repo_input.split("github.com/")[-1].split("/")
        owner = parts[0]
        repo  = parts[1] if len(parts) > 1 else ""
    else:
        # just repo name — use env username
        owner = os.getenv("GITHUB_USERNAME", "")
        repo  = repo_input

    if not owner or not repo:
        raise HTTPException(status_code=400, detail="Invalid repo URL. Use: https://github.com/username/reponame")

    # Build clone URL
    if github_token:
        clone_url = f"https://{owner}:{github_token}@github.com/{owner}/{repo}.git"
    else:
        clone_url = f"https://github.com/{owner}/{repo}.git"

    # Clone into temp folder
    tmp_dir = tempfile.mkdtemp(prefix="gh_import_")
    try:
        result = subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", req.branch, clone_url, tmp_dir],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode != 0:
            # Try without branch
            result = subprocess.run(
                ["git", "clone", "--depth", "1", clone_url, tmp_dir],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode != 0:
                raise HTTPException(status_code=400, detail=f"Failed to clone repo: {result.stderr[:200]}")

        # Check for canvas snapshot first — full restore takes priority
        canvas_file = os.path.join(tmp_dir, "devopsai-canvas.json")
        if os.path.exists(canvas_file):
            with open(canvas_file, "r", encoding="utf-8") as f:
                canvas_data = f.read()
            user_dir = get_user_output_dir(request)
            dest = os.path.join(user_dir, f"github_{repo}")
            if os.path.exists(dest):
                shutil.rmtree(dest)
            shutil.copytree(tmp_dir, dest, ignore=shutil.ignore_patterns(".git", ".terraform"))
            return {
                "success": True,
                "repo": f"{owner}/{repo}",
                "canvas_data": canvas_data,
                "services": [],
                "total": 0,
                "folders": {},
                "local_path": dest,
                "message": "Canvas snapshot found — restoring full canvas"
            }

        # Scan all .tf files and detect resource types
        services = []
        folders  = {}

        # Map Terraform resource types → canvas service IDs
        TF_MAP = {
            "aws_instance":                  "ec2_instance",
            "aws_autoscaling_group":         "ec2_asg",
            "aws_launch_template":           "ec2_launch_tmpl",
            "aws_spot_instance_request":     "ec2_spot",
            "aws_eks_cluster":               "eks_cluster",
            "aws_eks_node_group":            "eks_nodegroup",
            "aws_ecs_cluster":               "ecs_cluster",
            "aws_ecs_service":               "ecs_service",
            "aws_ecs_task_definition":       "ecs_task",
            "aws_lambda_function":           "lambda_fn",
            "aws_s3_bucket":                 "s3_bucket",
            "aws_db_instance":               "rds_instance",
            "aws_rds_cluster":               "rds_aurora",
            "aws_dynamodb_table":            "dynamodb_table",
            "aws_elasticache_cluster":       "elasticache_redis",
            "aws_elasticache_replication_group": "elasticache_redis",
            "aws_vpc":                       "vpc_main",
            "aws_subnet":                    "vpc_subnet_pub",
            "aws_internet_gateway":          "vpc_igw",
            "aws_nat_gateway":               "vpc_nat",
            "aws_security_group":            "vpc_sg",
            "aws_lb":                        "alb",
            "aws_alb":                       "alb",
            "aws_lb_target_group":           "alb_target_group",
            "aws_cloudfront_distribution":   "cf_dist",
            "aws_route53_zone":              "r53_zone",
            "aws_route53_record":            "r53_record",
            "aws_iam_role":                  "iam_role",
            "aws_iam_policy":                "iam_policy",
            "aws_secretsmanager_secret":     "secrets_mgr",
            "aws_kms_key":                   "kms_key",
            "aws_sqs_queue":                 "sqs_std",
            "aws_sns_topic":                 "sns_topic",
            "aws_cloudwatch_dashboard":      "cw_dashboard",
            "aws_cloudwatch_metric_alarm":   "cw_alarm",
            "aws_cloudwatch_log_group":      "cw_log_group",
            "aws_ecr_repository":            "ecr_repo",
            "aws_wafv2_web_acl":             "waf_webacl",
            "aws_ssm_parameter":             "ssm_param",
            "aws_cloudtrail":                "cloudtrail",
            "aws_kinesis_stream":            "kinesis_stream",
            "aws_api_gateway_rest_api":      "apigw_rest",
            "aws_apigatewayv2_api":          "apigw_http",
            "aws_vpc_endpoint":              "vpc_endpoint",
            "aws_vpc_peering_connection":    "vpc_peering",
        }

        seen = set()
        for root, dirs, files in os.walk(tmp_dir):
            dirs[:] = [d for d in dirs if d not in [".git", ".terraform", "node_modules"]]
            for fname in files:
                if not fname.endswith(".tf"):
                    continue
                fpath = os.path.join(root, fname)
                rel_folder = os.path.relpath(root, tmp_dir)
                try:
                    with open(fpath, "r", encoding="utf-8", errors="replace") as f:
                        content = f.read()
                except:
                    continue

                # Find all resource blocks: resource "aws_xxx" "name"
                matches = re.findall(r'resource\s+"([^"]+)"\s+"([^"]+)"', content)
                for tf_type, res_name in matches:
                    svc_id = TF_MAP.get(tf_type)
                    if not svc_id:
                        continue
                    key = f"{svc_id}:{res_name}"
                    if key in seen:
                        continue
                    seen.add(key)
                    services.append({
                        "id":     svc_id,
                        "name":   res_name.replace("_", " ").title(),
                        "tf_type": tf_type,
                        "folder": rel_folder,
                        "file":   fname
                    })
                    folders[rel_folder] = folders.get(rel_folder, 0) + 1

        # Also copy terraform files into generated/ folder
        user_dir = get_user_output_dir(request)
        dest = os.path.join(user_dir, f"github_{repo}")
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(tmp_dir, dest, ignore=shutil.ignore_patterns(".git", ".terraform"))

        return {
            "success": True,
            "repo": f"{owner}/{repo}",
            "services": services,
            "total": len(services),
            "folders": folders,
            "local_path": dest,
            "message": f"Found {len(services)} AWS resources in {len(folders)} folders"
        }

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
