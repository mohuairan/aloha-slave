# pi0.5 在线训练与 ALOHA 实物策略部署指南（Google Colab A100, 单卡 40GB / Colab Pro 10$ 版）  

> 简介：本项目说明如何在 Google Colab（单张 A100，40GB）上进行 **pi0.5（pi05）在线微调** 并将训练得到的策略部署到 ALOHA 机械臂的实机上。核心流程包含：前置准备 → 环境搭建 → 数据集处理 → 模型配置与归一化 → 训练 → Colab 保活与备份 → 模型下载 → 实机部署（Host/Client）→ 常见问题排查。  
> 本文档基于用户提供的工作流笔记整理与补充。

---

## 目录
- [前置准备](#前置准备)  
- [仓库克隆与子模块](#仓库克隆与子模块)  
- [安装 uv 与 OpenPI 依赖（环境搭建）](#安装-uv-与-openpi-依赖环境搭建)  
- [数据集处理（Hugging Face）](#数据集处理hugging-face)

---

## 前置准备

- **注册并登录 Hugging Face**：创建数据集仓库与模型仓库。**保存好 Hugging Face token（API key）——非常重要！**  
  ```bash
  huggingface-cli login
  huggingface-cli whoami
  ```
- **仓库结构要求（极重要）**：上传到 HF 的 dataset repo 进入后**必须**直接包含 `data/` 与 `meta/` 文件夹（**不能**将数据放在子文件夹里）。**强烈提醒：进仓库之后直接就是 data 与 meta 文件夹，不可以是其他结构。**

---

## 仓库克隆与子模块

建议克隆时使用 `--recurse-submodules`，如果已克隆需初始化子模块。

```bash
git clone --recurse-submodules https://github.com/Physical-Intelligence/openpi.git
cd openpi

# 如果已经克隆：
git submodule update --init --recursive
```

---

## 安装 uv 与 OpenPI 依赖（环境搭建）

OpenPI 使用 [uv](https://astral.sh/uv/) 管理依赖。以下为 Colab / 本地（Ubuntu）常用步骤。

### 安装 uv（curl 安装脚本）
```bash
# 安装 uv
curl -LsSf https://astral.sh/uv/install.sh | sh
# 使 cargo / 环境变量生效
source $HOME/.cargo/env

# 验证
uv --version
```

### 安装 OpenPI 依赖（注意 GIT_LFS_SKIP_SMUDGE）
`GIT_LFS_SKIP_SMUDGE=1` 在拉取带大文件依赖（LeRobot 等）时是必要的：

```bash
# 同步依赖（跳过 LFS smudge）
GIT_LFS_SKIP_SMUDGE=1 uv sync

# 安装包（可编辑安装）
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

**注意**：uv 可能会提示 `tool.uv.dev-dependencies` 的弃用警告（可忽略或按提示迁移到 `dependency-groups.dev`）。

---

## 数据集处理（Hugging Face）

### 使用脚本上传（可选）
如果数据在本地、可以使用已有的 `push_to_huggingface.py` 上传到仓库（原文提到有该脚本）。确保仓库结构遵守：根目录下直接为 `data/` 与 `meta/`。

### HF dataset 必须有版本 tag（避免 `RevisionNotFoundError`）
LeRobot 的加载机制要求 dataset 有代码版本 tag，否则会报：
`huggingface_hub.errors.RevisionNotFoundError: Your dataset must be tagged with a codebase version.`

在 Colab / shell 中为 dataset 增加 tag（示例）：

```bash
# 登录（若尚未登录）
huggingface-cli login

# 创建 tag（repo-type = dataset）
hf repo tag create <USER>/<DATASET_NAME> v1 --repo-type dataset
# 例如：
hf repo tag create mo0821/aloha_training_pick_tissue_2 v1 --repo-type dataset
```

或者用 Python API：
```python
from huggingface_hub import HfApi
hub_api = HfApi()
hub_api.create_tag("mo0821/aloha_training_pick_tissue_2", tag="_version_", repo_type="dataset")
```

### 如果自动加载失败：手动下载 dataset 到本地缓存目录
有时 compute_norm_stats 或数据加载会提示缺少 `meta/info.json`（或 dataset 未被自动拉取），可手动下载到 Hugging Face 本地缓存路径：

```bash
# 创建目标目录
mkdir -p /root/.cache/huggingface/lerobot/mo0821/aloha_test

# 下载 dataset 到指定目录（两种命令任选其一）
huggingface-cli download mo0821/aloha_test --repo-type dataset --local-dir /root/.cache/huggingface/lerobot/mo0821/aloha_test

# 或者（新工具）
hf download mo0821/aloha_test --repo-type dataset --local-dir /root/.cache/huggingface/lerobot/mo0821/aloha_test
```
---

## 模型配置与归一化（TrainConfig / 归一化统计）

进入 `openpi/src/openpi/training/`，在 `config` 的 `TrainConfig` 中添加/修改对应任务配置。下面给出一个 **LoRA 微调（pi0.5）** 的示例配置（**注意显存要求：22.5GB+**）：

```python
# 示例：TrainConfig（放在相应的 config 文件中）
TrainConfig(
    name="pi05_aloha_pick_tissue_finetune",
    model=pi0_config.Pi0Config(
        paligemma_variant="gemma_2b_lora", 
        action_expert_variant="gemma_300m_lora",
        pi05=True
    ),
    data=LeRobotAlohaDataConfig(
        repo_id="mo0821/aloha_test",
        assets=AssetsConfig(
            assets_dir="/root/.cache/pi05_base/assets",
            asset_id="trossen",
        ),
        default_prompt="pick up the tissue and put it into box",
        repack_transforms=_transforms.Group(
            inputs=[
                _transforms.RepackTransform(
                    {
                        "images": {
                            "cam_high": "observation.images.camera_high",
                            "cam_left_wrist": "observation.images.camera_wrist_left",
                            "cam_right_wrist": "observation.images.camera_wrist_right",
                        },
                        "state": "observation.state",
                        "actions": "action",
                    }
                )
            ]
        ),
    ),
    weight_loader=weight_loaders.CheckpointWeightLoader("/root/.cache/pi05_base/params"),
    num_train_steps=20_000,
    freeze_filter=pi0_config.Pi0Config(
        paligemma_variant="gemma_2b_lora", 
        action_expert_variant="gemma_300m_lora",
        pi05=True
    ).get_freeze_filter(),
    ema_decay=None,  # LoRA微调时关闭EMA
),
```

> **重点**：
> - `paligemma_variant="gemma_2b_lora"` 与 `action_expert_variant="gemma_300m_lora"`、`pi05=True` 等字段需确保一致且正确。  
> - `assets_dir` 和 `weight_loader` 路径需要指向你已下载/准备好的 `pi05_base` 资料。部署/serve 时建议把 `assets` 放在非 root、可访问的目录（在 Host/Client 中会提到）。

### 生成归一化统计（compute_norm_stats）
在项目根目录下运行：

```bash
uv run scripts/compute_norm_stats.py --config-name pi05_aloha_pick_tissue_finetune
```

**如果出现数据加载错误**（如 `FileNotFoundError: ... meta/info.json` 或 `RevisionNotFoundError`），请先按上节手动下载 dataset 并创建 tag。更多错误见 FAQ。

---

## 模型训练

在 Colab（或已配置好 JAX/XLA 的环境）中运行训练：

```bash
# 例如设置 XLA 内存分配，然后运行训练
XLA_PYTHON_CLIENT_MEM_FRACTION=0.99 uv run scripts/train.py pi05_aloha_pick_tissue_finetune --exp-name=my_experiment --overwrite
```

- `--exp-name` 用于 checkpoint 命名空间。  
- `--overwrite` 可覆盖已存在的同名实验。  
- 根据任务复杂度与显存，适当调整 `num_train_steps`、batch size 等。

---

## Colab 保活与自动备份脚本（示例）

> **说明**：Colab 容易断开。下面给出两个脚本示例：一个用于定时把 checkpoints 同步到 Google Drive 的备份脚本；另一个是简单的“保活”线程，定期输出信息防止空闲断开（不保证 100% 有效，需配合浏览器端长期保持活动）。需要保证你的 Google Drive 有足够空间。

### 1) 定时备份（Python）
```python
# Colab: 定时备份 checkpoint 到 Google Drive
import time
from datetime import datetime
import shutil
import os

source_folder = "/content/openpi/checkpoints/pi05_aloha_pick_tissue_finetune"
backup_folder = "/content/drive/MyDrive/openpi_checkpoints_backup"

os.makedirs(backup_folder, exist_ok=True)

while True:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[Heartbeat] Colab active at {now}", flush=True)
    
    # 每隔30分钟备份一次（用时间戳简单控制）
    if int(time.time()) % (30 * 60) < 10:
        backup_path = os.path.join(backup_folder, f"backup_{now.replace(':','-')}")
        shutil.copytree(source_folder, backup_path, dirs_exist_ok=True)
        print(f"[Backup] Saved checkpoint to {backup_path}", flush=True)
    
    time.sleep(600)  # 每10分钟打印一次
```

### 2) Python 保活（后台线程）
```python
# Colab: 保活线程（输出消息以保持 notebook 活动）
import threading
import time
import random

def keep_alive_python():
    messages = [
        "🔄 Colab 保持活跃中...",
        "📊 正在处理数据...",
        "🤖 AI 训练进行中...",
        "⚡ 计算中，请勿断开...",
        "🔬 实验运行中..."
    ]
    while True:
        print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {random.choice(messages)}")
        time.sleep(55)  # 小于60秒以免超时

thread = threading.Thread(target=keep_alive_python, daemon=True)
thread.start()
print("Python 保持活跃线程已启动")
```

> **注意**：长期依赖此类脚本并非官方保证方法；务必经常把重要 checkpoint 备份到 Drive 或外部存储。

---

## 模型打包与下载（谷歌云盘 / gdown / gsutil）

### 在 Colab 中压缩最终 checkpoint（示例）
建议在 Colab 中把目标 checkpoint 压缩成一个 zip 文件再同步到 Google Drive，避免下载不完整或被切割成多个包。

```bash
# Colab 示例：将某个 step 的 checkpoint 压缩
!zip -r /content/checkpoint/pi05_aloha_pick_tissue_finetune_19999.zip       /content/drive/MyDrive/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999
```

### 在本地使用 gdown 下载（当你把 zip 放到 Google Drive 并公开可见）
1. 在 Google Drive 中把对应文件/文件夹设置为“任何人有链接可见”（注意隐私风险）。  
2. 从分享链接提取 `id`（share url 中 `drive/folders/<ID>` 或 `id` 参数）。  
3. 使用 `gdown`（安装：`pip install gdown`）下载：

```bash
# 示例（id 为分享链接里的 ID）
gdown https://drive.google.com/uc?id=1812aDQgMYlkjo7cyLWaT0Lxao4c0dYp8 -O /home/you/aloha_data/checkpoint/
```

### 如果使用 Google Cloud Storage（gsutil）
部分 checkpoint 存储在 GCS（例如 `gs://openpi-assets/checkpoints/pi05_base`），若 `pi05_base` 文件夹为空/下载失败，尝试：

```bash
# 安装 Google Cloud SDK（示例）
curl https://sdk.cloud.google.com | bash
# 安装 crcmod（避免下载失败）
sudo apt-get install python3-dev gcc -y
pip install -U crcmod

# 使用 gsutil 下载（示例）
cd ~/.cache
gsutil -m cp -r gs://openpi-assets/checkpoints/pi05_base ./
```

> **注意**：若没有权限或文件不存在，gsutil 会报错；确认路径与权限。

---

## 实机策略部署（Host：远程推理 / Client：实物控制）

整体设计：将**推理端（Host）**与**实机控制端（Client）**分离。Host 承载模型推理（需较大显存，例如 ≥12GB），Client 负责与机械臂 / 相机等硬件通信并接收 Host 的动作指令。

---

### Host（远程推理） — 环境搭建与运行

1. 克隆仓库并进入：
    ```bash
    git clone https://github.com/Physical-Intelligence/openpi.git
    cd openpi
    ```

2. 创建 Python 3.11 虚拟环境（示例）：
    ```bash
    python3.11 -m venv .venv
    source .venv/bin/activate
    ```

3. 安装依赖：
    ```bash
    uv pip install -e .
    ```

4. 修改 `TrainConfig` 中的 `assets` 字段（将 `assets_dir` 指向 Host 上实际可读的路径）：
    ```python
    assets=AssetsConfig(
        assets_dir="/home/you/.cache/pi05_base/assets",  # 推荐非 root 路径
        asset_id="trossen",
    )
    ```
    并把 `checkpoints/.../assets/trossen` 复制到 `assets_dir` 指定位置，保证 `norm stats` 可读。

5. 运行 `serve_policy.py`（示例）：
    ```bash
    cd openpi
    python scripts/serve_policy.py --env ALOHA       policy:checkpoint       --policy.config "pi05_aloha_pick_tissue_finetune"       --policy.dir /home/you/serve_train/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999
    ```
    成功输出示例（关键日志）：
    ```
    INFO:absl:Restoring checkpoint from /home/you/serve_train/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999/params.
    INFO:root:Loaded norm stats from /home/you/.cache/pi05_base/assets/trossen
    INFO:root:Creating server (host: your-host, ip: 127.0.1.1)
    INFO:websockets.server:server listening on 0.0.0.0:8000
    ```
    表示推理服务已启动并监听端口（默认 8000）。

---

### Client（实物控制） — Docker 启动与调整

OpenPI 官方提供 `examples/aloha_real` 下的 `compose.yml` 使用 Docker Compose 启动实物控制环境。我们按需**移除 openpi-server 镜像（因为推理走远端 Host）**，并对 Dockerfile / compose 做若干修复。

1. 进入 `openpi` 根目录：
    ```bash
    docker compose -f examples/aloha_real/compose.yml up --build
    ```
    - **注意**：如果你要把 Host 与 Client 分离（Host 在远端），在 `compose.yml` 中**删除 `openpi-server` 相关服务 / depends_on**。

2. Dockerfile 中的 `xsarm_amd64_install.sh` 拉取脚本里含 `sudo`，会导致 `docker build` 失败（容器内不应使用 sudo）。**修复方法：在 Dockerfile 中用 sed 删除 sudo。**

```dockerfile
# 在 Dockerfile 中添加（或在 build 前 patch 脚本）
RUN sed -i 's/sudo //g' xsarm_amd64_install.sh
```

3. 为稳定识别机械臂 USB 设备，添加 udev 规则（示例）到 Dockerfile：

```dockerfile
# 固定 Interbotix X-Series 四个机械臂的 USB 设备名称
RUN echo "# Interbotix Arm UDEV Rules" >> /etc/udev/rules.d/99-interbotix-arms.rules &&     echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN4B", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_master_right"' >> /etc/udev/rules.d/99-interbotix-arms.rules &&     echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMMSJ", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_master_left"' >> /etc/udev/rules.d/99-interbotix-arms.rules &&     echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN3J", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_puppet_left"' >> /etc/udev/rules.d/99-interbotix-arms.rules &&     echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTA9DPY2", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_puppet_right"' >> /etc/udev/rules.d/99-interbotix-arms.rules
```

4. 修改 `robot_utils.py` 中夹爪参数：
```dockerfile
RUN sed -i 's/LEADER_GRIPPER_CLOSE_THRESH = 0.0/LEADER_GRIPPER_CLOSE_THRESH = -1.4/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py &&     sed -i 's/LEADER_GRIPPER_POSITION_OPEN = 0.0323/LEADER_GRIPPER_POSITION_OPEN = 0.02417/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py &&     sed -i 's/LEADER_GRIPPER_POSITION_CLOSE = 0.0185/LEADER_GRIPPER_POSITION_CLOSE = 0.01244/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py &&     sed -i 's/FOLLOWER_GRIPPER_POSITION_OPEN = 0.0579/FOLLOWER_GRIPPER_POSITION_OPEN = 0.05800/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py &&     sed -i 's/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.0440/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.01844/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py
```

5. 修改 `realsense_publisher.py` 中相机序列号：
```python
camera_names = ['cam_left_wrist', 'cam_high', 'cam_low', 'cam_right_wrist']
camera_sns = ['427622271497', '427622272971', '427622271439', '427622270353']
```

6. 构建并运行：
```bash
docker compose -f examples/aloha_real/compose.yml up --build
```

---

## 标定夹爪位置（ROS）

```bash
roslaunch interbotix_xsarm_control xsarm_control.launch   robot_model:=vx300s   robot_name:=puppet_right   port:=/dev/ttyDXL_puppet_right   use_rviz:=false   use_joint_pub_gui:=false

# 获取关节状态
rosservice call /puppet_right/get_joint_states

# 限速话题（减频）
rosrun topic_tools throttle messages /puppet_right/joint_states 1.0 /puppet_right/joint_states_slow

# 观察关节值（用于手动标定）
rostopic echo /puppet_right/joint_states_slow | grep position
```

---

## 常见问题（FAQ）

**Q1 — `pi05_base` 目录为空，无法下载基础参数**  
**解法**：使用 Google Cloud SDK + `gsutil` 下载（先安装 `crcmod`）：
```bash
curl https://sdk.cloud.google.com | bash
sudo apt-get install python3-dev gcc -y
pip install -U crcmod
gsutil -m cp -r gs://openpi-assets/checkpoints/pi05_base ./
```

**Q2 — `RevisionNotFoundError: Your dataset must be tagged with a codebase version.`**  
**解法**：为 dataset 创建 tag：
```bash
hf repo tag create <user>/<dataset> v1 --repo-type dataset
```

**Q3 — `compute_norm_stats.py` 报 FileNotFoundError / info.json 缺失**  
**解法**：手动下载 dataset 到 `/root/.cache/huggingface/lerobot/<user>/<dataset>`。

**Q4 — 训练需要 2.0 数据格式，但现有是 1.0，转换时进程被终止**  
**解法**：检查日志、内存、磁盘空间或使用分步转换脚本。

**Q5 — uv 警告：`tool.uv.dev-dependencies` 已弃用**  
**解法**：暂可忽略或迁移到 `dependency-groups.dev`。

**Q6 — Docker build 报错（网络/ sudo ）**  
**解法**：用 sed 删除 sudo 并检查 apt 源。

---

## 最后检查清单

- [ ] Hugging Face token 已登录  
- [ ] Dataset repo 结构正确（根目录直接包含 `data/` 与 `meta/`）  
- [ ] 已添加 dataset tag  
- [ ] assets 与 params 路径在 Host / Client 可读写  
- [ ] Colab checkpoint 已备份  
- [ ] Host 显存 ≥ 12GB  
- [ ] Client Dockerfile 已修复 sudo 与添加 udev  
- [ ] 若使用 GCS 下载，确保已安装 crcmod

---
