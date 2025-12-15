# 🦾 ALOHA 项目全流程说明文档（数据采集 → 训练 → 部署）

> 本 README 旨在提供从 **实物数据采集（Docker 环境）** 到 **pi0.5 模型在线训练与实机部署** 的完整闭环流程。  
> 包含：环境构建、数据采集、数据格式转换、模型微调、推理部署与常见问题排查。

---

## 文档结构

1. [实物数据采集与格式转换（Docker）](#实物数据采集与格式转换docker)  
   - 环境构建  
   - 容器内部配置修改  
   - 数据采集流程  
   - HDF5 → LeRobot v2.0 数据格式转换  
   - 常见问题（FAQ）

2. [pi0.5 在线训练与实机部署](#pi05-在线训练与实机部署)  
   - Colab 环境搭建  
   - 数据集上传与版本标记  
   - 模型训练与归一化统计  
   - 远程推理 Host / Client 实机部署  
   - 常见问题（FAQ）
  
3. **Dockerfile:**用于构建与运行 Aloha 实机环境镜像的指令。
    
4. **容器内常用指令.txt：**容器内常用运行指令参考。


---

## 实物数据采集与格式转换（Docker）


### 1. 环境准备与镜像构建

- 系统要求：Ubuntu 22.04 + ROS2 Humble + Interbotix X-Series  
- 推荐：拥有 ≥6 个 USB3.2 接口、足够硬盘空间（单任务约 10–30GB）

#### 构建 Docker 镜像
```bash
docker build . -t aloha_real_datarecord
```

#### 启动容器
```bash
docker run -it --name aloha_env_stable     --privileged -v /dev:/dev -v ~/aloha_data:/app/aloha_data     aloha_real_datarecord /bin/bash
```

### 2. 容器内部关键配置修改

#### sleep 位姿修正
在 `robot_utils.py` 中添加 `sleep_arms_local()`，调整默认睡眠姿态，防止腕关节堵转。

#### Realsense 分辨率修复
在 `aloha_stationary.yaml` 中将相机参数改为：
```yaml
depth_module:
  depth_profile: '640,480,60'
  color_profile: '640,480,60'
```

#### 任务配置
修改 `tasks_config.yaml`：
```yaml
dataset_dir: "/app/aloha_data/aloha_stationary_dummy"
episode_len: 1200
```

#### 夹爪映射与归一化修正
- 将 `follower_modes_*.yaml` 中 `operating_mode` 改为 `position`
- 修改 `real_env.py` 中：
  ```python
  gripper_qpos = [FOLLOWER_GRIPPER_JOINT_NORMALIZE_FN(bot.gripper.get_gripper_position())]
  ```

> 修复从臂夹爪状态值与命令值不匹配（0–40 vs 0–1）的严重问题。

### 3. 标准数据采集流程

```bash
# 启动容器
docker start -ai aloha_env_stable

# 启动 ROS2 通信
ros2 launch aloha aloha_bringup.launch.py robot:=aloha_stationary

# 启动采集脚本
bash auto_record.sh aloha_stationary_dummy 5 aloha_stationary

# 机械臂复位
python3 sleep.py -r aloha_stationary
```

### 4. 数据格式转换（HDF5 → LeRobot v2.0）

```bash
python3 convert_aloha_data_to_lerobot.py   --raw-dir /app/aloha_data/aloha_stationary_dummy   --repo-id mo0821/aloha_test
```

> ⚠️ 若出现“颜色反转”问题，请检查脚本中：
> ```python
> cv2.cvtColor(cv2.imdecode(data, 1), cv2.COLOR_BGR2RGB)
> ```
> 确保 `BGR → RGB` 转换仅执行一次。

---

## pi0.5 在线训练与实机部署


### 1. Colab 环境与仓库初始化

```bash
git clone --recurse-submodules https://github.com/Physical-Intelligence/openpi.git
cd openpi
```

#### 安装依赖
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.cargo/env
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

### 2. 数据集准备（Hugging Face）

#### 登录与上传
```bash
huggingface-cli login
huggingface-cli whoami
```

上传数据集：
```python
from huggingface_hub import HfApi
api = HfApi()
api.upload_folder(
    folder_path="/app/aloha_data/aloha_stationary_dummy",
    repo_id="mo0821/aloha_test",
    repo_type="dataset"
)
```

#### 增加版本 tag
```bash
hf repo tag create mo0821/aloha_test v1 --repo-type dataset
```

### 3. 模型配置与训练

示例：`TrainConfig`（LoRA 微调）
```python
TrainConfig(
    name="pi05_aloha_pick_tissue_finetune",
    model=pi0_config.Pi0Config(pi05=True),
    data=LeRobotAlohaDataConfig(repo_id="mo0821/aloha_test"),
    num_train_steps=20000,
)
```

#### 归一化统计
```bash
uv run scripts/compute_norm_stats.py --config-name pi05_aloha_pick_tissue_finetune
```

#### 启动训练
```bash
XLA_PYTHON_CLIENT_MEM_FRACTION=0.99 uv run scripts/train.py pi05_aloha_pick_tissue_finetune --overwrite
```

### 4. 模型备份与保活（Colab）

**定时备份示例：**
```python
import time, shutil, os
while True:
    shutil.copytree("/content/openpi/checkpoints", "/content/drive/MyDrive/openpi_backup", dirs_exist_ok=True)
    time.sleep(1800)
```

---

## 实机部署（Host / Client 分布式）

| 角色 | 功能 | 环境 |
|------|------|------|
| **Host** | 模型推理服务器 | 高显存主机 (≥12GB) |
| **Client** | ROS2 + Docker 控制端 | ALOHA 硬件节点 |

### Host 运行推理服务

```bash
python scripts/serve_policy.py   --env ALOHA   --policy.config pi05_aloha_pick_tissue_finetune   --policy.dir /path/to/checkpoint
```

输出示例：
```
INFO:server listening on 192.168.1.39:8000
```

### Client（实机控制）

编辑 `compose.yml`：
```yaml
environment:
  - SERVER_IP=192.168.1.39
  - SERVER_PORT=8000
```

启动：
```bash
docker compose -f examples/aloha_real/compose.yml up --build
```

---

## 常见问题（FAQ）

### 数据采集部分
| 问题 | 解决方案 |
|------|-----------|
| 颜色通道错误（蓝红反转） | 确保仅执行一次 `cv2.cvtColor(..., cv2.COLOR_BGR2RGB)` |
| 夹爪角度范围异常 | 修改 `follower_modes_*.yaml` 为 `position` 模式 |
| `AttributeError: 'NoneType' object` | 检查 `tasks_config.yaml` 的 `dataset_dir` 是否存在 |
| realsense 启动分辨率不符 | 检查 `depth_profile` 与 `color_profile` 格式 `'640,480,60'` |

### 训练与部署部分
| 问题 | 解决方案 |
|------|-----------|
| `RevisionNotFoundError` | 为 dataset 添加 tag：`hf repo tag create ...` |
| `info.json` 缺失 | 手动下载到 `/root/.cache/huggingface/lerobot/...` |
| `pi05_base` 缺少参数 | 使用 `gsutil` 从 GCS 下载 |
| `docker build` 失败 | 删除安装脚本中的 `sudo` 命令 |
| Host 无法连通 | 检查 IP 与端口；Client 中 `SERVER_IP` 是否匹配 |

---

## 最后检查清单

- [ ] Docker 容器构建成功并能控制机械臂  
- [ ] 成功采集多轮 HDF5 数据  
- [ ] 数据转换为 LeRobot v2.0 格式  
- [ ] Hugging Face 数据集已上传并打 tag  
- [ ] 模型成功训练与导出 checkpoint  
- [ ] Host / Client 通讯正常，能执行策略推理  
- [ ] 所有修改（gripper / yaml / sleep 位姿）已重新构建  
