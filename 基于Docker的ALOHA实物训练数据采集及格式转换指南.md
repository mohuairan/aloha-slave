# 基于Docker的ALOHA实物训练数据采集及格式转换指南

> 简介：本项目旨在说明如何在任意一台电脑上通过**强大的docker**实现快速的镜像构建实现对aloha机械臂的控制，仓库内附dockerfile
> 比较适用于有大容量机械硬盘（采30次数据大约需要10-30个g）及多个（至少6个）高速UBS3.2口的电脑
>
## 目录
- [基于Docker的ALOHA实物训练数据采集及格式转换指南]
  - [目录](#目录)
  - [前置准备](#前置准备)
  - [Dockerfile的构建](#dockerfile的构建)
  - [容器内部文件的修改](#容器内部文件的修改)

## 前置准备

-**下载并安装docker及docker compose**

## Dockerfile的构建

> 本节旨在详细解析**Ubuntu 22.04 + ROS2 Humble + Interbotix ALOHA 环境** Dockerfile。  
> 适用于理解环境搭建流程、镜像构建逻辑和系统依赖关系。
- 包括以下内容
  - [基础配置](#基础配置)
  - [网络代理与非交互安装](#网络代理与非交互安装)
  - [替换系统源为清华镜像并安装基础工具](#替换系统源为清华镜像并安装基础工具)
  - [添加 ROS2 Key 与镜像源](#添加-ros2-key-与镜像源)
  - [配置 Python 清华镜像](#配置-python-清华镜像)
  - [Interbotix X-Series 驱动安装](#interbotix-x-series-驱动安装)
  - [清理系统缓存](#清理系统缓存)
  - [克隆 ALOHA 仓库与构建环境](#克隆-aloha-仓库与构建环境)
  - [相机序列号配置](#相机序列号配置)
  - [机械臂 USB 设备规则](#机械臂-usb-设备规则)
  - [夹爪参数标定](#夹爪参数标定)
  - [环境变量与入口脚本](#环境变量与入口脚本)
  - [构建与运行及日常维护](#构建与运行及日常维护)
---

1. ### 基础配置

```dockerfile
FROM ubuntu:22.04
SHELL ["/bin/bash", "-c"]
```

**说明：**
- 使用 Ubuntu 22.04 作为基础镜像。
- 修改默认 shell 为 Bash，使后续命令可使用 Bash 特性（如变量、管道、条件执行）。

---

2. ### 网络代理与非交互安装

```dockerfile
ENV http_proxy=http://192.168.1.28:2080
ENV https_proxy=http://192.168.1.28:2080
ENV no_proxy=localhost,127.0.0.1
ENV DEBIAN_FRONTEND=noninteractive
```

**说明：**
- 配置代理服务器，便于构建时访问外网。
- `no_proxy` 允许本地地址跳过代理。
- 设置 `DEBIAN_FRONTEND=noninteractive` 防止 `apt-get` 过程中出现交互提示（自动选择默认选项）。

---

3. ### 替换系统源为清华镜像并安装基础工具

```dockerfile
RUN sed -i 's@http://.*archive.ubuntu.com@http://mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list && \
    sed -i 's@http://.*security.ubuntu.com@http://mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list    
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
	    curl \
	    ca-certificates \
	    gnupg \
	    lsb-release \
	    python3-pip \
	    wget \
	    git \
	    vim \
	    nano    
```

**说明：**
- 将 Ubuntu 官方源替换为清华镜像源，加快 apt 下载速度。
- 安装常用工具（curl、git、vim、pip 等）。
- `--no-install-recommends` 防止自动安装推荐依赖，减少镜像体积。
---

4. ### 添加 ROS2 Key 与镜像源

```dockerfile
RUN mkdir -p /etc/apt/keyrings
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /etc/apt/keyrings/ros-archive-keyring.gpg

RUN \
    rm -f /etc/apt/sources.list.d/ros*.list /etc/apt/sources.list.d/ros*.sources && \
    sed -i '/packages\.ros\.org/d' /etc/apt/sources.list && \
    \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ros2.list
RUN apt-get update
```
**说明：**
- 创建 ROS keyring 目录并下载 ROS 官方key。
- 移除旧ROS2源，添加清华镜像版ROS2 apt 源。
- 更新 apt 缓存，准备安装 ROS2 软件包。
---

5. ### 配置 Python 清华镜像

```dockerfile
RUN mkdir -p /root/.pip && \
    printf "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\ntrusted-host = pypi.tuna.tsinghua.edu.cn\n" > ~/.pip/pip.conf
```

**说明：**
- 将 pip 默认源配置为清华 PyPI 镜像，加速 Python 包安装。
---
6. ### Interbotix X-Series 驱动安装

```dockerfile
WORKDIR /root
RUN curl 'https://raw.githubusercontent.com/Interbotix/interbotix_ros_manipulators/main/interbotix_ros_xsarms/install/amd64/xsarm_amd64_install.sh' > xsarm_amd64_install.sh
RUN sed -i '/sudo add-apt-repository/,/sudo apt-get update/{/sudo apt-get update/!d}' xsarm_amd64_install.sh
RUN sed -i '/sudo apt-get update/d' xsarm_amd64_install.sh
RUN sed -i 's/sudo //g' xsarm_amd64_install.sh
RUN chmod +x xsarm_amd64_install.sh
RUN export TZ='Asia/Shanghai' && ./xsarm_amd64_install.sh -d humble -n
RUN sed -i '/^# Interbotix Configurations/,$d' /root/.bashrc
```

**说明：**
- 下载官方安装脚本 `xsarm_amd64_install.sh`。
- 用 `sed` 去除 `sudo` 命令以便在容器中运行。
- 执行脚本，安装 Interbotix X-Series 驱动（ROS2 Humble 版）。
- 清理 `.bashrc` 中的自动配置段。
---

7. ### 清理系统缓存

```dockerfile
RUN rm -rf /var/lib/apt/lists/*
```

**说明：**
- 删除 apt 缓存文件，减少镜像体积。
---

8. ### 克隆 ALOHA 仓库与构建环境

```dockerfile
WORKDIR /root/interbotix_ws/src
RUN git clone https://github.com/Interbotix/aloha.git -b 2.0

WORKDIR /root/interbotix_ws/src/aloha
RUN pip install -r requirements.txt

WORKDIR /root/interbotix_ws
RUN rosdep install --from-paths src --ignore-src -r -y
RUN sed -i 's/iterative_update_fk: bool = True,/iterative_update_fk: bool = False,/g' ~/interbotix_ws/src/interbotix_ros_toolboxes/interbotix_xs_toolbox/interbotix_xs_modules/interbotix_xs_modules/xs_robot/arm.py
RUN colcon build
```

**说明：**
- 克隆 ALOHA ROS2 项目（2.0 分支）。
- 安装 Python 依赖与 ROS2 依赖。
- 修改 `arm.py` 配置文件禁用迭代式 FK 更新。
- 使用 `colcon build` 构建整个工作区。
---

9. ### 相机序列号配置

```dockerfile
RUN sed -i \
  -e '0,/serial_no: ""/s//serial_no: "427622272971"/' \
  -e '0,/serial_no: ""/s//serial_no: "427622271439"/' \
  -e '0,/serial_no: ""/s//serial_no: "427622270353"/' \
  -e '0,/serial_no: ""/s//serial_no: "427622271497"/' \
  ~/interbotix_ws/src/aloha/config/robot/aloha_stationary.yaml
```

**说明：**
- 依次替换 YAML 文件中的空相机序列号为真实设备序列号。
- 顺序需与相机安装顺序匹配。
---

10. ### 机械臂 USB 设备规则

```dockerfile
RUN echo "# the arms" >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN4B", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_leader_right"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMMSJ", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_leader_left"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN3J", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_follower_left"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTA9DPY2", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_follower_right"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules
```

**说明：**
- 添加固定的 udev 规则，为各机械臂串口分配稳定命名（如 `/dev/ttyDXL_leader_left`）。
- 确保 ROS 可稳定识别设备端口。

---

11. ### 夹爪参数标定

```dockerfile
RUN sed -i 's/LEADER_GRIPPER_CLOSE_THRESH = 0.0/LEADER_GRIPPER_CLOSE_THRESH = -1.4/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_POSITION_OPEN = 0.0323/LEADER_GRIPPER_POSITION_OPEN = 0.02417/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_POSITION_CLOSE = 0.0185/LEADER_GRIPPER_POSITION_CLOSE = 0.01244/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_POSITION_OPEN = 0.0579/FOLLOWER_GRIPPER_POSITION_OPEN = 0.05800/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.0440/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.01844/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_JOINT_OPEN = 0.8298/LEADER_GRIPPER_JOINT_OPEN = -0.8/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_JOINT_CLOSE = -0.0552/LEADER_GRIPPER_JOINT_CLOSE = -1.65/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_JOINT_OPEN = 1.6214/FOLLOWER_GRIPPER_JOINT_OPEN = 1.4910/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_JOINT_CLOSE = 0.6197/FOLLOWER_GRIPPER_JOINT_CLOSE = 0.0/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py
```

**说明：**
- 修改夹爪张合参数，确保主从机械臂同步动作。
- 所有数值基于实际实验标定。

---

12. ### 环境变量与入口脚本

```dockerfile
RUN echo 'source /opt/ros/humble/setup.sh' >> /root/.bashrc && \
    echo 'source /root/interbotix_ws/install/setup.sh' >> /root/.bashrc && \
    echo "WANDB_MODE=disabled" >> ~/.bashrc    

RUN printf '#!/bin/bash\n\
set -e\n\
/lib/systemd/systemd-udevd --daemon\n\
udevadm control --reload && udevadm trigger\n\
cd ~/interbotix_ws && colcon build && cd\n\
exec "$@"\n' > /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
```

**说明：**
- 自动加载 ROS2 和 ALOHA 环境。
- 创建 `entrypoint.sh`：
  - 启动 udev 服务；
  - 触发设备规则；
  - 构建 ROS2 环境；
  - 执行传入命令。
- 设置容器启动时默认执行 `/bin/bash`。

---

13. ### 构建与运行及日常维护

**构建命令：**
```bash
docker build . -t aloha_real_datarecord
```
**说明：**
- `-t` 为创建的镜像打上tag
- 构建镜像，在环境修改/添加其他依赖后需要重新build

**运行容器：**
```bash
docker run -it --name aloha_env_stable -v /dev:/dev -v .:/app -v ~/aloha_data:/app/aloha_data --privileged aloha_real_datarecord /bin/bash
```

**说明：**
- `-it` 同时启用交互模式 + 分配伪终端。
- `--privileged` 允许访问真实硬件设备。
- `-v` 用于挂载宿主机与容器中的对应文件夹。
---

## 容器内部文件的修改
> 本节旨在针对开发时遇到的一系列问题及相应针对性配置，对docker容器中相关代码进行统一修改
- **包括以下内容:**
  - [前置准备](#前置准备-1)
  - [`sleep.py`时机械臂默认sleep位姿不对](#sleep位姿修改)
  - [`realsenseD405`驱动版本问题导致的视频文件长宽比例及分辨率问题](#视频分辨率修改)
  - [`task_config.yaml`文件修改](#任务配置修改)

1. ### 前置准备
- 在宿主机的**vscode**中安装`Dev Containers`插件
- 启动容器
- 通过宿主机`Dev Containers`插件访问容器内部文件
---

2. ### sleep位姿修改
   在`src/aloha/aloha/robot_utils.py`文件`sleep_arms`函数后（大约157行后）添加函数
   ```python
    def sleep_arms_local(
        bot_list: Sequence[InterbotixManipulatorXS],
        dt: float,
        moving_time: float = 5.0,
        home_first: bool = True,
    ) -> None:
        """Command given list of arms to their sleep poses, optionally to their home poses first.

        :param bot_list: List of bots to command to their sleep poses
        :param moving_time: Duration in seconds the movements should take, defaults to 5.0
        :param home_first: True to command the arms to their home poses first, defaults to True
        """
        local_sleep_pos = [[0.0, -2.049999952316284, 1.7000000476837158, 0.0, 1.0, 0.0]] * len(bot_list)
        print("=== 各机械臂睡眠位置 ===")
        for i, bot in enumerate(bot_list):
            sleep_pos = local_sleep_pos
        print(f"机械臂 {i} ({bot.robot_name}): {sleep_pos}")
        if home_first:
            move_arms(
                bot_list=bot_list,
                dt=dt,
                target_pose_list=[
                    [0.0, -0.96, 1.16, 0.0, -0.3, 0.0]] * len(bot_list),
                moving_time=moving_time
            )
        move_arms(
            bot_list=bot_list,
            target_pose_list=local_sleep_pos,
            moving_time=moving_time,
            dt=dt,
        )
    ```

**说明：**
- 原始`sleep_arms`函数关节默认的腕关节位姿是向上翻的一个姿态，电机容易堵转，通过本地自定义参数优化位姿

    在`src/aloha/scripts/sleep.py`下作如下修改（在import中添加`sleep_arms_local`函数）
    ```python
    from aloha.robot_utils import (
        sleep_arms,
        sleep_arms_local,
        torque_on,
        disable_gravity_compensation,
        load_yaml_file,
    )
    ```
    修改约第99行处关于`sleep_arms`函数的调用
    ```python
    sleep_arms_local(bots_to_sleep, home_first=True, dt=dt)
    ```
    
---

3. ### 视频分辨率修改




4. ### 任务配置修改
