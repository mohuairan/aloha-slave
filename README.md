# Pi0.5 在线训练及实物策略部署指南

> 本文档详细介绍了如何基于 Google Colab 使用单张 A100 (40GB) GPU 进行 Pi0.5 模型的训练与实物策略部署流程。

---

## 目录

- [环境准备](#环境准备)
- [训练流程](#训练流程)
- [常见问题](#常见问题)
- [Colab 保活与备份](#colab-保活与备份)
- [模型下载与部署](#模型下载与部署)
- [远程推理 (Host 端)](#远程推理-host-端)
- [实物控制 (Client 端)](#实物控制-client-端)
- [附录：夹爪标定](#附录夹爪标定)

---
pi0.5在线训练及实物策略部署指南

基于谷歌colab（10美元会员版）单张A100（40G）训练

##先注册好你的huggingface帐号，创建好仓库
保存好huggingface密钥！这个很重要
如果是本地保存的文件，使用写好的push_to_huggingface.py来上传数据集到仓库
！！注意仓库结构：进仓库之后直接就是data文件夹与meta文件夹，不可以是其他结构


git clone --recurse-submodules https://github.com/Physical-Intelligence/openpi.git
cd openpi

## 如果已经克隆了仓库，更新子模块：
git submodule update --init --recursive

###### 安装uv包管理器

OpenPI使用[uv](https://docs.astral.sh/uv/)管理Python依赖项：


```bash
## 安装uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.cargo/env

## 验证安装
uv --version
```

###### 安装OpenPI依赖


```bash
## 设置环境并安装依赖
GIT_LFS_SKIP_SMUDGE=1 uv sync
GIT_LFS_SKIP_SMUDGE=1 uv pip install -e .
```

**注意**：`GIT_LFS_SKIP_SMUDGE=1`是拉取LeRobot依赖所必需的。

此时运行归一化发现huggingface的dataset未生成tag
LeRobot 要求 dataset repo 必须有一个“版本 tag”，否则会报：
RevisionNotFoundError: Your dataset must be tagged with a codebase version.

##为dataset加上tag
在colab上运行
huggingface-cli login

##检查
huggingface-cli whoami
##再运行
hf repo tag create mo0821/aloha_training_pick_tissue_2 v1 --repo-type dataset
##成功添加tag到dataset

进入/content/openpi/src/openpi/training/
在config文件TrainConfig中添加以下字段

###### LoRA微调配置
**显存要求**：22.5GB+

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
        ema_decay=None,  ## LoRA微调时关闭EMA
    ),

##运行归一化程序
uv run scripts/compute_norm_stats.py --config-name pi05_aloha_pick_tissue_finetune

##报错数据集不加载
手动下载数据到
mkdir -p /root/.cache/huggingface/lerobot/mo0821/aloha_test

huggingface-cli download mo0821/aloha_test --repo-type dataset --local-dir /root/.cache/huggingface/lerobot/mo0821/aloha_test
（或者hf download）

##运行训练程序
XLA_PYTHON_CLIENT_MEM_FRACTION=0.99 uv run scripts/train.py pi05_aloha_pick_tissue_finetune --exp-name=my_experiment --overwrite


##目前出现的问题
1、运行下面命令时
aws s3 sync s3://openpi-assets/checkpoints/pi05_base ./pi05_base/ --no-sign-request
发现pi05base是个空文件夹

解决方法：
安装 Google Cloud SDK：
curl https://sdk.cloud.google.com | bash

##安装crcmod包，不然会下不下来
sudo apt-get install python3-dev gcc -y

pip install -U crcmod

直接下载
cd ~/.cache

gsutil -m cp -r gs://openpi-assets/checkpoints/pi05_base ./

2、现在的数据格式是1.0,训练需要2.0格式，转换时电脑出现进程终止。

3、报错
/content/openpi## uv run scripts/compute_norm_stats.py --config-name pi0.5_aloha_pick_tissue_finetune
warning: The `tool.uv.dev-dependencies` field (used in `packages/openpi-client/pyproject.toml`) is deprecated and will be removed in a future release; use `dependency-groups.dev` instead
100%|███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| 4.07M/4.07M [00:05<00:00, 852kiB/s]
Traceback (most recent call last):
  File "/content/openpi/.venv/lib/python3.11/site-packages/lerobot/common/datasets/lerobot_dataset.py", line 95, in __init__
    self.load_metadata()
  File "/content/openpi/.venv/lib/python3.11/site-packages/lerobot/common/datasets/lerobot_dataset.py", line 105, in load_metadata
    self.info = load_info(self.root)
                ^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/.venv/lib/python3.11/site-packages/lerobot/common/datasets/utils.py", line 178, in load_info
    info = load_json(local_dir / INFO_PATH)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/.venv/lib/python3.11/site-packages/lerobot/common/datasets/utils.py", line 146, in load_json
    with open(fpath) as f:
         ^^^^^^^^^^^
FileNotFoundError: [Errno 2] No such file or directory: '/root/.cache/huggingface/lerobot/mo0821/aloha_training_pick_tissue_2/meta/info.json'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/content/openpi/scripts/compute_norm_stats.py", line 117, in <module>
    tyro.cli(main)
  File "/content/openpi/.venv/lib/python3.11/site-packages/tyro/_cli.py", line 229, in cli
    return run_with_args_from_cli()
           ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/scripts/compute_norm_stats.py", line 98, in main
    data_loader, num_batches = create_torch_dataloader(
                               ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/scripts/compute_norm_stats.py", line 34, in create_torch_dataloader
    dataset = _data_loader.create_torch_dataset(data_config, action_horizon, model_config)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/src/openpi/training/data_loader.py", line 140, in create_torch_dataset
    dataset_meta = lerobot_dataset.LeRobotDatasetMetadata(repo_id)
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/.venv/lib/python3.11/site-packages/lerobot/common/datasets/lerobot_dataset.py", line 98, in __init__
    self.revision = get_safe_version(self.repo_id, self.revision)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/content/openpi/.venv/lib/python3.11/site-packages/lerobot/common/datasets/utils.py", line 330, in get_safe_version
    raise RevisionNotFoundError(
huggingface_hub.errors.RevisionNotFoundError: Your dataset must be tagged with a codebase version.
            Assuming _version_ is the codebase_version value in the info.json, you can run this:
            ```python
            from huggingface_hub import HfApi

            hub_api = HfApi()
            hub_api.create_tag("mo0821/aloha_training_pick_tissue_2", tag="_version_", repo_type="dataset")
            ```
解决一部分，huggingface的dataset未生成tag

##huggingface_hub.errors.RevisionNotFoundError: Your dataset must be tagged with a codebase version.
在colab上运行
huggingface-cli login
检查
huggingface-cli whoami
再运行
hf repo tag create mo0821/aloha_training_pick_tissue_2 v1 --repo-type dataset
成功添加tag到dataset



报错数据集不加载
手动下载数据到
mkdir -p /root/.cache/huggingface/lerobot/mo0821/aloha_test

huggingface-cli download mo0821/aloha_test --repo-type dataset --local-dir /root/.cache/huggingface/lerobot/mo0821/aloha_test
（或者hf download）



文件被写入：Writing stats to: /content/openpi/assets/pi05_aloha_pick_tissue_finetune/mo0821/aloha_test

开始训练
XLA_PYTHON_CLIENT_MEM_FRACTION=0.99 uv run scripts/train.py pi05_aloha_pick_tissue_finetune --exp-name=my_experiment --overwrite


记得经常在云盘里面保存数据
!cp -r /content/openpi/checkpoints/pi05_aloha_pick_tissue_finetune /content/drive/MyDrive/


##colab保活+云盘自动备份
PS：需要比较大的云盘空间
## =============================
## 🌟 Colab 保活 + 自动备份脚本
import time
from datetime import datetime
import shutil
import os
import sys

## === 设置路径 ===
source_folder = "/content/openpi/checkpoints/pi05_aloha_pick_tissue_finetune"
backup_folder = "/content/drive/MyDrive/openpi_checkpoints_backup"

os.makedirs(backup_folder, exist_ok=True)

## === 持续保持活跃 + 备份 ===
while True:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[Heartbeat] Colab active at {now}", flush=True)
    
    ## 每隔30分钟备份一次
    if int(time.time()) % (30 * 60) < 10:  ## 避免重复触发
        backup_path = os.path.join(backup_folder, f"backup_{now.replace(':','-')}")
        shutil.copytree(source_folder, backup_path, dirs_exist_ok=True)
        print(f"[Backup] Saved checkpoint to {backup_path}", flush=True)
    
    time.sleep(600)  ## 每10分钟输出一次
    
##自动备份线程2

import threading
import time
import random

def keep_alive_python():
    """使用 Python 定时输出保持活跃"""
    messages = [
        "🔄 Colab 保持活跃中...",
        "📊 正在处理数据...",
        "🤖 AI 训练进行中...",
        "⚡ 计算中，请勿断开...",
        "🔬 实验运行中..."
    ]
    
    while True:
        ## 随机选择一条消息输出
        message = random.choice(messages)
        print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}")
        
        ## 每 55 秒输出一次（小于60秒避免超时）
        time.sleep(55)

def start_keep_alive():
    """启动后台保持活跃线程"""
    thread = threading.Thread(target=keep_alive_python, daemon=True)
    thread.start()
    print("Python 保持活跃线程已启动")
    return thread

## 启动 Python 保持活跃
keep_alive_thread = start_keep_alive()


##下载文件
只需要下载最后一次的checkpoint
建议是先在colab中运行下面指令压缩文件
!zip -r /content/checkpoint/pi05_aloha_pick_tissue_finetune_19999.zip \
      /content/drive/MyDrive/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999
再同步到谷歌云盘再进行下载，不然直接下载文件夹会下成三四个压缩包，文件完整性无法保证

##谷歌云盘完整文件下载
在本地电脑上
pip install gdown
在谷歌云盘上复制对应文件夹（在共享选项中把所有人可见打开）
https://drive.google.com/drive/folders/1812aDQgMYlkjo7cyLWaT0Lxao4c0dYp8?usp=drive_link
如下界面下，在网址的drive/folders后面的两个下划线之间的就是id，比如这里分享的链接是https://drive.google.com/drive/folders/1812aDQgMYlkjo7cyLWaT0Lxao4c0dYp8?usp=drive_link，那么id就是1812aDQgMYlkjo7cyLWaT0Lxao4c0dYp8


gdown https://drive.google.com/uc?id=1812aDQgMYlkjo7cyLWaT0Lxao4c0dYp8 -O  /home/slwang/aloha_data/checkpoint/

-O OUTPUT, --output OUTPUT
                        output file name/path; end with "/"to create a new
                        directory (default: None)
                        
                        
##关于实机策略部署问题
openpi这边采用了远程通讯，可以将策略的远程推理（高性能电脑，显存大于等于12G）（host端）与实物机械臂控制（client端）分开

##远程推理（host端）环境搭建及运行
克隆openpi仓库
git clone 
cd openpi
python -m venv .venv（这里应该要创建python3.11的虚拟环境）
source .venv/bin/bash/activate

uv pip install -e .
进入openpi/src/openpi/training/config.py
修改TrainConfig
主要是assets字段
assets=AssetsConfig(
                assets_dir="/root/.cache/pi05_base/assets",
                asset_id="trossen",
            ),
把assets_dir改为主文件夹下的.catch文件夹而不是root下的，然后把checkpoints下的assets文件夹复制过去，保存
运行
cd openpi
python scripts/serve_policy.py --env ALOHA \ ##选择ALOHA
  policy:checkpoint \
  --policy.config "pi05_aloha_pick_tissue_finetune" \ ##TrainConfig里面的任务名
  --policy.dir /home/jodell/serve_train/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999  ##自己的文件夹
  
输出如下：
INFO:absl:Restoring checkpoint from /home/jodell/serve_train/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999/params.
INFO:absl:[thread=MainThread] Failed to get flag value for EXPERIMENTAL_ORBAX_USE_DISTRIBUTED_PROCESS_ID.
INFO:absl:[process=0] /jax/checkpoint/read/bytes_per_sec: 1.5 GiB/s (total bytes: 6.3 GiB) (time elapsed: 4 seconds) (per-host)
INFO:absl:Finished restoring checkpoint in 4.26 seconds from /home/jodell/serve_train/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999/params.
INFO:root:Loaded norm stats from /home/jodell/.cache/pi05_base/assets/trossen
INFO:root:Loaded norm stats from /home/jodell/serve_train/openpi/checkpoints/pi05_aloha_pick_tissue_finetune/my_experiment/19999/assets/trossen
INFO:root:Creating server (host: jodell, ip: 127.0.1.1)
INFO:websockets.server:server listening on 0.0.0.0:8000

验证推理端搭建成功！

##实物控制（Client端）环境搭建
openpi文档中建议采用docker进行环境搭建，详见examples/aloha_real文件夹下readme文件

openpi官方给出的的docker启动方式是docker—compose，在openpi文件夹下运行
docker compose -f examples/aloha_real/compose.yml up 
以启动实物

这里有一些注意事项：
我们选择将推理与实机操控分开，因此在实机上不需要运行openpi—server镜像，所以在docker-compose文件中删去openpi-server相关内容，包括runtime配置中的depends—on：openpi-server

编译时遇到报错

********************************************** Starting installation! This process may take around 15 Minutes! ********************************************** 
Err:1 http://mirrors.ustc.edu.cn/ubuntu focal InRelease Temporary failure resolving 'mirrors.ustc.edu.cn'
Err:2 http://snapshots.ros.org/noetic/final/ubuntu focal InRelease Temporary failure resolving 'snapshots.ros.org'

经查，问题出在
RUN curl 'https://raw.githubusercontent.com/Interbotix/interbotix_ros_manipulators/main/interbotix_ros_xsarms/install/amd64/xsarm_amd64_install.sh' > xsarm_amd64_install.sh
这里拉取的sh文件中包含有sudo指令，sudo指令在dockerfile运行时会导致错误，因此需要在build时删除sh文件中的所有指令前面的sudo
因此在后面添加
RUN sed -i 's/sudo //g' xsarm_amd64_install.sh


##机械臂与realsense的配置修改
dockerfile把机器人的配置文件挂载到了宿主机的openpi工作文件夹下的/openpi_new/openpi/third_party/aloha/aloha_scripts/robot_utils.py文件中

在dockerfile中添加以下内容
## 固定 Interbotix X-Series 四个机械臂的 USB 设备名称
RUN echo "## Interbotix Arm UDEV Rules" >> /etc/udev/rules.d/99-interbotix-arms.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN4B", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_master_right"' >> /etc/udev/rules.d/99-interbotix-arms.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMMSJ", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_master_left"' >> /etc/udev/rules.d/99-interbotix-arms.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN3J", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_puppet_left"' >> /etc/udev/rules.d/99-interbotix-arms.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTA9DPY2", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="ttyDXL_puppet_right"' >> /etc/udev/rules.d/99-interbotix-arms.rules

## 使用 sed 命令修改指定内容 - the gripper
RUN sed -i 's/LEADER_GRIPPER_CLOSE_THRESH = 0.0/LEADER_GRIPPER_CLOSE_THRESH = -1.4/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_POSITION_OPEN = 0.0323/LEADER_GRIPPER_POSITION_OPEN = 0.02417/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_POSITION_CLOSE = 0.0185/LEADER_GRIPPER_POSITION_CLOSE = 0.01244/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_POSITION_OPEN = 0.0579/FOLLOWER_GRIPPER_POSITION_OPEN = 0.05800/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.0440/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.01844/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_JOINT_OPEN = 0.8298/LEADER_GRIPPER_JOINT_OPEN = -0.8/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_JOINT_CLOSE = -0.0552/LEADER_GRIPPER_JOINT_CLOSE = -1.65/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_JOINT_OPEN = 1.6214/FOLLOWER_GRIPPER_JOINT_OPEN = 1.4910/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_JOINT_CLOSE = 0.6197/FOLLOWER_GRIPPER_JOINT_CLOSE = 0.0/' /root/interbotix_ws/src/aloha/aloha_scripts/robot_utils.py

修改source /opt/ros/noetic/setup.sh && source /root/interbotix_ws/devel/setup.sh && "$@"
为
set -e
/lib/systemd/systemd-udevd --daemon
udevadm control --reload && udevadm trigger
source /opt/ros/noetic/setup.sh && source /root/interbotix_ws/devel/setup.sh
exec "$@"

dockerfile把相机的配置文件挂载到了宿主机的openpi工作文件夹下的/openpi_new/openpi/third_party/aloha/aloha_scripts/realsense_publisher.py文件，在此处修改realsenseD405的序列号
camera_names = ['cam_left_wrist', 'cam_high', 'cam_low', 'cam_right_wrist']
camera_sns = ['427622271497', '427622272971', '427622271439', '427622270353']


修改完成之后，运行
docker compose -f examples/aloha_real/compose.yml up --build 
进行编译

##推理




##标定夹爪位置
roslaunch interbotix_xsarm_control xsarm_control.launch \
  robot_model:=vx300s \
  robot_name:=puppet_right \
  port:=/dev/ttyDXL_puppet_right \
  use_rviz:=false \
  use_joint_pub_gui:=false

rosservice call /puppet_right/get_joint_states



rosrun topic_tools throttle messages /puppet_right/joint_states 1.0 /puppet_right/joint_states_slow

rostopic echo /puppet_right/joint_states_slow | grep position




