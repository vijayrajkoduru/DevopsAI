from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel
import anthropic
import os
import re
import json
import sqlite3
import boto3
import subprocess
import hashlib
import secrets
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()
client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
OUTPUT_DIR = "generated"
DB_PATH = "canvas.db"

# ── DATABASE INIT ──────────────────────────────────────────────────────────────

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS canvases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        plan TEXT NOT NULL DEFAULT 'free',
        created_at TEXT NOT NULL
    )''')
    c.execute('''DROP TABLE IF EXISTS sessions''')
    c.execute('''CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
    )''')
    conn.commit()
    conn.close()

init_db()

# ── HELPERS ────────────────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def get_current_user(request: Request):
    token = request.cookies.get("session_token")
    if not token:
        return None
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''SELECT u.id, u.name, u.email, u.plan
                 FROM sessions s JOIN users u ON s.user_id = u.id
                 WHERE s.token = ?''', (token,))
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

# ── PAGE ROUTES ────────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
def root():
    with open("ui.html", "r", encoding="utf-8") as f:
        return f.read()

@app.get("/login", response_class=HTMLResponse)
def login_page():
    with open("login.html", "r", encoding="utf-8") as f:
        return f.read()

@app.get("/landing", response_class=HTMLResponse)
def landing_page():
    with open("landing.html", "r", encoding="utf-8") as f:
        return f.read()

@app.get("/app", response_class=HTMLResponse)
def app_page():
    with open("ui.html", "r", encoding="utf-8") as f:
        return f.read()

# ── AUTH ROUTES ────────────────────────────────────────────────────────────────

@app.post("/auth/register")
def auth_register(req: AuthRegister, response: Response):
    if not req.name or not req.email or not req.password:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="All fields are required.")
    if len(req.password) < 6:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters.")
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id FROM users WHERE email = ?", (req.email,))
    if c.fetchone():
        conn.close()
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="Email already registered.")
    now = datetime.now().isoformat()
    pw_hash = hash_password(req.password)
    c.execute("INSERT INTO users (name, email, password_hash, plan, created_at) VALUES (?, ?, ?, 'free', ?)",
              (req.name, req.email, pw_hash, now))
    user_id = c.lastrowid
    token = secrets.token_hex(32)
    from datetime import timedelta
    expires = (datetime.now() + timedelta(days=30)).isoformat()
    c.execute("INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)", (token, user_id, now, expires))
    conn.commit()
    conn.close()
    response.set_cookie(key="session_token", value=token, httponly=True, max_age=86400 * 30)
    return {"id": user_id, "name": req.name, "email": req.email, "plan": "free"}

@app.post("/auth/login")
def auth_login(req: AuthLogin, response: Response):
    from fastapi import HTTPException
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    pw_hash = hash_password(req.password)
    c.execute("SELECT id, name, email, plan FROM users WHERE email = ? AND password_hash = ?",
              (req.email, pw_hash))
    row = c.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=401, detail="Invalid email or password.")
    user_id, name, email, plan = row
    token = secrets.token_hex(32)
    now = datetime.now().isoformat()
    from datetime import timedelta
    expires = (datetime.now() + timedelta(days=30)).isoformat()
    c.execute("INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)", (token, user_id, now, expires))
    conn.commit()
    conn.close()
    response.set_cookie(key="session_token", value=token, httponly=True, max_age=86400 * 30)
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
def save_canvas(req: CanvasSave):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    now = datetime.now().isoformat()
    c.execute("INSERT INTO canvases (name, data, created_at, updated_at) VALUES (?, ?, ?, ?)",
              (req.name, req.data, now, now))
    canvas_id = c.lastrowid
    conn.commit()
    conn.close()
    return {"id": canvas_id, "name": req.name, "saved_at": now}

@app.put("/canvas/{canvas_id}")
def update_canvas(canvas_id: int, req: CanvasUpdate):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    now = datetime.now().isoformat()
    c.execute("UPDATE canvases SET data=?, updated_at=? WHERE id=?", (req.data, now, canvas_id))
    conn.commit()
    conn.close()
    return {"id": canvas_id, "updated_at": now}

@app.get("/canvas/list")
def list_canvases():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, name, created_at, updated_at FROM canvases ORDER BY updated_at DESC")
    rows = c.fetchall()
    conn.close()
    return {"canvases": [{"id": r[0], "name": r[1], "created_at": r[2], "updated_at": r[3]} for r in rows]}

@app.get("/canvas/{canvas_id}")
def load_canvas(canvas_id: int):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, name, data, created_at, updated_at FROM canvases WHERE id=?", (canvas_id,))
    row = c.fetchone()
    conn.close()
    if not row:
        return {"error": "Canvas not found"}
    return {"id": row[0], "name": row[1], "data": row[2], "created_at": row[3], "updated_at": row[4]}

@app.delete("/canvas/{canvas_id}")
def delete_canvas(canvas_id: int):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM canvases WHERE id=?", (canvas_id,))
    conn.commit()
    conn.close()
    return {"deleted": canvas_id}

# ── AWS SCAN ───────────────────────────────────────────────────────────────────

def get_boto3_client(service, region):
    return boto3.client(service, region_name=region)

@app.post("/aws/scan")
def scan_aws_resources(req: AWSRegionRequest):
    region = req.region
    resources = []
    errors = []
    try:
        ec2 = get_boto3_client("ec2", region)
        resp = ec2.describe_instances()
        for reservation in resp["Reservations"]:
            for inst in reservation["Instances"]:
                name = next((t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Name"), "")
                resources.append({"service": "ec2_instance", "id": inst["InstanceId"], "name": name or inst["InstanceId"], "status": inst["State"]["Name"], "details": {"instance_type": inst.get("InstanceType", ""), "ip": inst.get("PublicIpAddress", ""), "az": inst.get("Placement", {}).get("AvailabilityZone", ""), "vpc_id": inst.get("VpcId", "")}, "region": region, "category": "AWS Compute"})
    except Exception as e:
        errors.append("EC2: " + str(e))
    try:
        s3 = get_boto3_client("s3", region)
        for bucket in s3.list_buckets().get("Buckets", []):
            resources.append({"service": "s3_bucket", "id": bucket["Name"], "name": bucket["Name"], "status": "active", "details": {}, "region": region, "category": "AWS Storage"})
    except Exception as e:
        errors.append("S3: " + str(e))
    try:
        rds = get_boto3_client("rds", region)
        for db in rds.describe_db_instances().get("DBInstances", []):
            resources.append({"service": "rds_instance", "id": db["DBInstanceIdentifier"], "name": db["DBInstanceIdentifier"], "status": db["DBInstanceStatus"], "details": {"engine": db.get("Engine", ""), "instance_class": db.get("DBInstanceClass", "")}, "region": region, "category": "AWS Storage"})
    except Exception as e:
        errors.append("RDS: " + str(e))
    try:
        ec2 = get_boto3_client("ec2", region)
        for vpc in ec2.describe_vpcs().get("Vpcs", []):
            name = next((t["Value"] for t in vpc.get("Tags", []) if t["Key"] == "Name"), "")
            resources.append({"service": "vpc_main", "id": vpc["VpcId"], "name": name or vpc["VpcId"], "status": vpc["State"], "details": {"cidr": vpc.get("CidrBlock", "")}, "region": region, "category": "AWS Networking"})
    except Exception as e:
        errors.append("VPC: " + str(e))
    try:
        eks = get_boto3_client("eks", region)
        for cluster_name in eks.list_clusters().get("clusters", []):
            detail = eks.describe_cluster(name=cluster_name)["cluster"]
            resources.append({"service": "eks_cluster", "id": cluster_name, "name": cluster_name, "status": detail.get("status", ""), "details": {"version": detail.get("version", "")}, "region": region, "category": "AWS Compute"})
    except Exception as e:
        errors.append("EKS: " + str(e))
    try:
        lmb = get_boto3_client("lambda", region)
        for fn in lmb.list_functions().get("Functions", []):
            resources.append({"service": "lambda_fn", "id": fn["FunctionName"], "name": fn["FunctionName"], "status": "active", "details": {"runtime": fn.get("Runtime", ""), "memory": str(fn.get("MemorySize", "")) + " MB"}, "region": region, "category": "AWS Compute"})
    except Exception as e:
        errors.append("Lambda: " + str(e))
    try:
        elb = get_boto3_client("elbv2", region)
        for lb in elb.describe_load_balancers().get("LoadBalancers", []):
            resources.append({"service": "alb", "id": lb["LoadBalancerName"], "name": lb["LoadBalancerName"], "status": lb["State"]["Code"], "details": {"type": lb.get("Type", ""), "dns": lb.get("DNSName", "")}, "region": region, "category": "AWS Networking"})
    except Exception as e:
        errors.append("ALB: " + str(e))
    try:
        ecr = get_boto3_client("ecr", region)
        for repo in ecr.describe_repositories().get("repositories", []):
            resources.append({"service": "ecr_repo", "id": repo["repositoryName"], "name": repo["repositoryName"], "status": "active", "details": {"uri": repo.get("repositoryUri", "")}, "region": region, "category": "AWS Storage"})
    except Exception as e:
        errors.append("ECR: " + str(e))
    try:
        iam = get_boto3_client("iam", region)
        for role in iam.list_roles().get("Roles", [])[:15]:
            resources.append({"service": "iam_role", "id": role["RoleName"], "name": role["RoleName"], "status": "active", "details": {"arn": role.get("Arn", "")}, "region": "global", "category": "AWS Security"})
    except Exception as e:
        errors.append("IAM: " + str(e))
    return {"resources": resources, "total": len(resources), "region": region, "errors": errors}

# ── FILE EXTRACTION HELPER ─────────────────────────────────────────────────────

def extract_and_save_files(response_text, base_dir):
    os.makedirs(base_dir, exist_ok=True)
    pattern = r'###\s*File\s*\d*:?\s*[`]([^\n`]+)[`]\s*\n```(?:\w+)?\n(.*?)```'
    matches = re.findall(pattern, response_text, re.DOTALL)
    saved = []
    for filename, content in matches:
        filename = filename.strip()
        if not filename or '\n' in filename:
            continue
        filepath = os.path.join(base_dir, filename)
        folder = os.path.dirname(filepath)
        if folder:
            os.makedirs(folder, exist_ok=True)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content.strip())
        saved.append(filename)
    return saved

# ── AI GENERATION ROUTES ───────────────────────────────────────────────────────

@app.post("/generate")
def generate(request: PromptRequest):
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        messages=[{"role": "user", "content": "You are an AI DevOps agent. Generate complete production-ready code split into proper separate files.\nUse this exact format for each file:\n### File 1: `filename.ext`\n```language\ncode here\n```\nInstruction: " + request.prompt}]
    )
    response_text = message.content[0].text
    prompt_folder = request.prompt[:40].strip().replace(" ", "_").replace("/", "_")
    save_dir = os.path.join(OUTPUT_DIR, prompt_folder)
    saved_files = extract_and_save_files(response_text, save_dir)
    return {"response": response_text, "saved_files": saved_files, "location": save_dir}

@app.post("/generate-terraform")
def generate_terraform(resource: AWSResource):
    config_str = json.dumps(resource.config, indent=2)
    prompt = (
        "Generate complete Terraform code for " + resource.resource_type + " with this config:\n"
        + config_str
        + "\n\nIMPORTANT RULES:\n"
        + "1. All variables MUST have default values\n"
        + "2. Generate terraform.tfvars with all actual values\n"
        + "3. For EC2 Ubuntu 22.04 us-east-1 use AMI: ami-0c7217cdde317cfec\n"
        + "4. For EC2 Ubuntu 22.04 ap-south-1 use AMI: ami-0f58b397bc5c1f2e8\n"
        + "5. Never use variables without default values\n"
        + "6. Make ready to deploy with zero manual input\n"
        + "7. Always add lifecycle { ignore_changes = [tags, tags_all] } inside every AWS resource block\n"
        + "8. Use default VPC and default subnets if no VPC specified\n"
        + "\n### File 1: `main.tf`\n```hcl\ncode\n```\n"
        + "### File 2: `variables.tf`\n```hcl\ncode with defaults\n```\n"
        + "### File 3: `outputs.tf`\n```hcl\ncode\n```\n"
        + "### File 4: `providers.tf`\n```hcl\ncode\n```\n"
        + "### File 5: `terraform.tfvars`\n```hcl\nactual values\n```"
    )
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}]
    )
    response_text = message.content[0].text
    save_dir = os.path.join(OUTPUT_DIR, "terraform_" + resource.resource_type + "_" + resource.config.get("name", "res"))
    saved_files = extract_and_save_files(response_text, save_dir)
    return {"response": response_text, "saved_files": saved_files, "location": save_dir}

@app.post("/generate-config")
def generate_config(resource: AWSResource):
    config_str = json.dumps(resource.config, indent=2)
    prompt = "Generate complete config and setup files for " + resource.resource_type + ":\n" + config_str + "\nUse this exact format:\n### File 1: `filename.ext`\n```language\ncode\n```"
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}]
    )
    response_text = message.content[0].text
    save_dir = os.path.join(OUTPUT_DIR, "config_" + resource.resource_type + "_" + resource.config.get("name", "tool"))
    saved_files = extract_and_save_files(response_text, save_dir)
    return {"response": response_text, "saved_files": saved_files, "location": save_dir}

# ── DEPLOY ROUTES ──────────────────────────────────────────────────────────────

def run_terraform_streaming(full_path: str, commands: list):
    cache_dir = os.path.join(os.path.expanduser("~"), ".terraform.d", "plugin-cache")
    os.makedirs(cache_dir, exist_ok=True)
    env = os.environ.copy()
    env["TF_PLUGIN_CACHE_DIR"] = cache_dir
    for cmd in commands:
        yield "data: \n\n"
        yield "data: === Running: " + " ".join(cmd) + " ===\n\n"
        try:
            process = subprocess.Popen(
                cmd, cwd=full_path,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, env=env,
                encoding='utf-8', errors='replace'
            )
            for line in process.stdout:
                line = line.rstrip()
                if line:
                    yield "data: " + line + "\n\n"
            process.wait()
            if process.returncode != 0:
                yield "data: ERROR: Command failed with code " + str(process.returncode) + "\n\n"
                yield "data: DEPLOY_FAILED\n\n"
                return
            yield "data: SUCCESS: " + " ".join(cmd) + " completed!\n\n"
        except FileNotFoundError:
            yield "data: ERROR: terraform not found. Please install Terraform.\n\n"
            yield "data: DEPLOY_FAILED\n\n"
            return

@app.post("/deploy/terraform")
def deploy_terraform(resource: AWSResource):
    folder = resource.config.get("folder", "")
    if not folder:
        return {"error": "No folder specified"}
    full_path = os.path.join(OUTPUT_DIR, folder)
    if not os.path.exists(full_path):
        return {"error": "Folder not found: " + full_path}

    def run():
        yield "data: === Starting Terraform Deploy ===\n\n"
        yield "data: Folder: " + full_path + "\n\n"
        yield from run_terraform_streaming(full_path, [
            ["terraform", "init", "-no-color"],
            ["terraform", "plan", "-no-color"],
            ["terraform", "apply", "-auto-approve", "-no-color"]
        ])
        yield "data: \n\n"
        yield "data: === DEPLOY COMPLETE! AWS resources created successfully! ===\n\n"
        yield "data: DEPLOY_SUCCESS\n\n"

    return StreamingResponse(run(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})

@app.post("/destroy/terraform")
def destroy_terraform(resource: AWSResource):
    folder = resource.config.get("folder", "")
    if not folder:
        return {"error": "No folder specified"}
    full_path = os.path.join(OUTPUT_DIR, folder)
    if not os.path.exists(full_path):
        return {"error": "Folder not found: " + full_path}

    def run():
        yield "data: === Starting Terraform Destroy ===\n\n"
        yield "data: Folder: " + full_path + "\n\n"
        yield from run_terraform_streaming(full_path, [
            ["terraform", "init", "-no-color"],
            ["terraform", "destroy", "-auto-approve", "-no-color"]
        ])
        yield "data: \n\n"
        yield "data: === DESTROY COMPLETE! AWS resources deleted successfully! ===\n\n"
        yield "data: DEPLOY_SUCCESS\n\n"

    return StreamingResponse(run(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})

# ── GITHUB PUSH ───────────────────────────────────────────────────────────────

class GitHubPushRequest(BaseModel):
    folder: str = ""
    repo_name: str
    commit_message: str = "Auto-push from AI DevOps Platform"

@app.post("/github/push")
def github_push(req: GitHubPushRequest):
    github_token    = os.getenv("GITHUB_TOKEN", "")
    github_username = os.getenv("GITHUB_USERNAME", "")

    if not github_token:
        from fastapi import HTTPException
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
            from fastapi import HTTPException
            raise HTTPException(status_code=400, detail="Invalid GitHub URL. Use: https://github.com/username/reponame")
    else:
        # Just repo name provided — use username from .env
        repo_name = repo_input.replace(".git", "")
        if not github_username:
            from fastapi import HTTPException
            raise HTTPException(status_code=400, detail=(
                "Step 1: Add this to your .env file:\n"
                "  GITHUB_USERNAME=yourGitHubUsername\n\n"
                "Step 2: Restart the server:\n"
                "  uvicorn main:app --reload\n\n"
                "OR paste the full URL in the field:\n"
                "  https://github.com/vijayrajkoduru/DevopsAI"
            ))

    if not repo_name:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="Could not extract repo name. Provide full URL or just repo name.")

    # Always push the entire generated/ directory as one repo
    full_path = os.path.abspath(OUTPUT_DIR)
    os.makedirs(full_path, exist_ok=True)

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
def get_deploy_folders():
    folders = []
    if os.path.exists(OUTPUT_DIR):
        for f in os.listdir(OUTPUT_DIR):
            full = os.path.join(OUTPUT_DIR, f)
            if os.path.isdir(full):
                has_tf = any(file.endswith(".tf") for file in os.listdir(full))
                if has_tf:
                    folders.append({"name": f, "path": full})
    return {"folders": folders}

# ── VS CODE OPENER ─────────────────────────────────────────────────────────────

class VSCodeRequest(BaseModel):
    folder: str

@app.post("/open-in-vscode")
def open_in_vscode(req: VSCodeRequest):
    folder = req.folder
    full_path = os.path.join(OUTPUT_DIR, folder) if not os.path.isabs(folder) else folder
    full_path = os.path.abspath(full_path)
    if not os.path.exists(full_path):
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Folder not found: " + full_path)
    try:
        # Try 'code' CLI (works on Windows, Mac, Linux if VS Code is in PATH)
        subprocess.Popen(["code", full_path], shell=(os.name == "nt"))
        return {"opened": True, "path": full_path}
    except FileNotFoundError:
        # Fallback: try common Windows VS Code path
        vscode_paths = [
            r"C:\Users\\" + os.environ.get("USERNAME", "") + r"\AppData\Local\Programs\Microsoft VS Code\Code.exe",
            r"C:\Program Files\Microsoft VS Code\Code.exe",
        ]
        for vspath in vscode_paths:
            if os.path.exists(vspath):
                subprocess.Popen([vspath, full_path])
                return {"opened": True, "path": full_path}
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail="VS Code not found. Make sure 'code' is in your PATH.")

# ── AWS CONSOLE URL ────────────────────────────────────────────────────────────

AWS_CONSOLE_URLS = {
    "ec2_instance":   "https://console.aws.amazon.com/ec2/v2/home?region={region}#Instances:",
    "s3_bucket":      "https://s3.console.aws.amazon.com/s3/buckets/{name}?region={region}",
    "rds_instance":   "https://console.aws.amazon.com/rds/home?region={region}#databases:",
    "vpc_main":       "https://console.aws.amazon.com/vpc/home?region={region}#vpcs:",
    "eks_cluster":    "https://console.aws.amazon.com/eks/home?region={region}#/clusters/{name}",
    "lambda_fn":      "https://console.aws.amazon.com/lambda/home?region={region}#/functions/{name}",
    "alb":            "https://console.aws.amazon.com/ec2/v2/home?region={region}#LoadBalancers:",
    "ecr_repo":       "https://console.aws.amazon.com/ecr/repositories/{name}?region={region}",
    "iam_role":       "https://console.aws.amazon.com/iam/home#/roles/{name}",
    "cloudfront":     "https://console.aws.amazon.com/cloudfront/v3/home#/distributions",
    "route53":        "https://console.aws.amazon.com/route53/v2/hostedzones",
    "sns":            "https://console.aws.amazon.com/sns/v3/home?region={region}#/topics",
    "sqs":            "https://console.aws.amazon.com/sqs/v2/home?region={region}#/queues",
    "dynamodb":       "https://console.aws.amazon.com/dynamodbv2/home?region={region}#tables",
    "elasticache":    "https://console.aws.amazon.com/elasticache/home?region={region}#/",
    "ecs_cluster":    "https://console.aws.amazon.com/ecs/v2/clusters?region={region}",
    "codepipeline":   "https://console.aws.amazon.com/codesuite/codepipeline/pipelines?region={region}",
    "cloudwatch":     "https://console.aws.amazon.com/cloudwatch/home?region={region}",
    "secretsmanager": "https://console.aws.amazon.com/secretsmanager/home?region={region}#!/listSecrets",
}

@app.get("/aws/console-url")
def get_aws_console_url(resource_type: str, name: str = "", region: str = "us-east-1"):
    template = AWS_CONSOLE_URLS.get(resource_type)
    if not template:
        url = f"https://console.aws.amazon.com/console/home?region={region}"
    else:
        url = template.format(region=region, name=name)
    return {"url": url, "resource_type": resource_type, "region": region}

# ── CHAT ASSISTANT ─────────────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    messages: list
    system: str = ""

@app.post("/chat")
def chat(req: ChatRequest):
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

    return StreamingResponse(stream(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})
# ── GITHUB IMPORT → CANVAS ────────────────────────────────────────────────────

class GitHubImportRequest(BaseModel):
    repo_url: str
    branch: str = "main"

@app.post("/github/import")
def github_import(req: GitHubImportRequest):
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
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="Invalid repo URL. Use: https://github.com/username/reponame")

    # Build clone URL
    if github_token:
        clone_url = f"https://{owner}:{github_token}@github.com/{owner}/{repo}.git"
    else:
        clone_url = f"https://github.com/{owner}/{repo}.git"

    # Clone into temp folder
    import tempfile, shutil
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
                from fastapi import HTTPException
                raise HTTPException(status_code=400, detail=f"Failed to clone repo: {result.stderr[:200]}")

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
        dest = os.path.join(OUTPUT_DIR, f"github_{repo}")
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