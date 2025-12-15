FROM ubuntu:22.04
SHELL ["/bin/bash", "-c"]

# 设置代理
ENV http_proxy=http://192.168.1.28:2080
ENV https_proxy=http://192.168.1.28:2080
ENV no_proxy=localhost,127.0.0.1

# 禁止所有交互提示，安装时自动接受默认选项。
ENV DEBIAN_FRONTEND=noninteractive

# 替换系统源为清华
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

# 创建 keyrings 目录，下载并保存 ROS 2 的 GPG key
RUN mkdir -p /etc/apt/keyrings
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /etc/apt/keyrings/ros-archive-keyring.gpg
# 删除所有 ros2 源文件，避免残留。 写入清华 ROS2 源    
RUN \
    # 1. Clean up ALL potential old ROS sources, including the .sources file
    rm -f /etc/apt/sources.list.d/ros*.list /etc/apt/sources.list.d/ros*.sources && \
    sed -i '/packages\.ros\.org/d' /etc/apt/sources.list && \
    \
    # 2. Add the desired Tsinghua mirror source (as a standard .list file)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ros2.list
RUN apt-get update
    
RUN mkdir -p /root/.pip && \
    printf "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\ntrusted-host = pypi.tuna.tsinghua.edu.cn\n" > ~/.pip/pip.conf
    
# Interbotix X-Series Arms机械臂基于 Dynamixel 智能舵机，支持 4~6 自由度。
WORKDIR /root
RUN curl 'https://raw.githubusercontent.com/Interbotix/interbotix_ros_manipulators/main/interbotix_ros_xsarms/install/amd64/xsarm_amd64_install.sh' > xsarm_amd64_install.sh
RUN sed -i '/sudo add-apt-repository/,/sudo apt-get update/{/sudo apt-get update/!d}' xsarm_amd64_install.sh
RUN sed -i '/sudo apt-get update/d' xsarm_amd64_install.sh
RUN sed -i 's/sudo //g' xsarm_amd64_install.sh
RUN chmod +x xsarm_amd64_install.sh
RUN export TZ='Asia/Shanghai' && ./xsarm_amd64_install.sh -d humble -n
# 删除 ~/.bashrc 中 # Interbotix Configurations 之后的内容
RUN sed -i '/^# Interbotix Configurations/,$d' /root/.bashrc

RUN rm -rf /var/lib/apt/lists/*


WORKDIR /root/interbotix_ws/src
RUN git clone https://github.com/Interbotix/aloha.git -b 2.0

#安装aloha相关依赖项
WORKDIR /root/interbotix_ws/src/aloha
RUN pip install -r requirements.txt

WORKDIR /root/interbotix_ws
RUN rosdep install --from-paths src --ignore-src -r -y
# 使用 sed 修改 arm.py 文件中的迭代更新设置
RUN sed -i 's/iterative_update_fk: bool = True,/iterative_update_fk: bool = False,/g' ~/interbotix_ws/src/interbotix_ros_toolboxes/interbotix_xs_toolbox/interbotix_xs_modules/interbotix_xs_modules/xs_robot/arm.py
RUN colcon build

# 使用 sed 替换 serial_no 值 - the cameras
RUN sed -i \
  -e '0,/serial_no: ""/s//serial_no: "427622272971"/' \
  -e '0,/serial_no: ""/s//serial_no: "427622271439"/' \
  -e '0,/serial_no: ""/s//serial_no: "427622270353"/' \
  -e '0,/serial_no: ""/s//serial_no: "427622271497"/' \
  ~/interbotix_ws/src/aloha/config/robot/aloha_stationary.yaml

# 追加 udev 规则到文件末尾 - the arms
RUN echo "# the arms" >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN4B", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_leader_right"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMMSJ", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_leader_left"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTAAMN3J", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_follower_left"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{serial}=="FTA9DPY2", ENV{ID_MM_DEVICE_IGNORE}="1", ATTR{device/latency_timer}="1", SYMLINK+="ttyDXL_follower_right"' >> /etc/udev/rules.d/99-fixed-interbotix-udev.rules
#RUN /lib/systemd/systemd-udevd --daemon
#RUN udevadm control --reload && udevadm trigger

# 使用 sed 命令修改指定内容 - the gripper
RUN sed -i 's/LEADER_GRIPPER_CLOSE_THRESH = 0.0/LEADER_GRIPPER_CLOSE_THRESH = -1.4/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_POSITION_OPEN = 0.0323/LEADER_GRIPPER_POSITION_OPEN = 0.02417/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_POSITION_CLOSE = 0.0185/LEADER_GRIPPER_POSITION_CLOSE = 0.01244/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_POSITION_OPEN = 0.0579/FOLLOWER_GRIPPER_POSITION_OPEN = 0.05800/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.0440/FOLLOWER_GRIPPER_POSITION_CLOSE = 0.01844/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_JOINT_OPEN = 0.8298/LEADER_GRIPPER_JOINT_OPEN = -0.8/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/LEADER_GRIPPER_JOINT_CLOSE = -0.0552/LEADER_GRIPPER_JOINT_CLOSE = -1.65/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_JOINT_OPEN = 1.6214/FOLLOWER_GRIPPER_JOINT_OPEN = 1.4910/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py && \
    sed -i 's/FOLLOWER_GRIPPER_JOINT_CLOSE = 0.6197/FOLLOWER_GRIPPER_JOINT_CLOSE = 0.0/' ~/interbotix_ws/src/aloha/aloha/robot_utils.py
#WORKDIR /root/interbotix_ws
#RUN colcon build


RUN echo 'source /opt/ros/humble/setup.sh' >> /root/.bashrc && \
    echo 'source /root/interbotix_ws/install/setup.sh' >> /root/.bashrc && \
    echo "WANDB_MODE=disabled" >> ~/.bashrc    

# Create an entrypoint script to run the setup commands, followed by the command passed in. ——指令/lib/systemd/systemd-udevd --daemon需要在启动后运行
RUN printf '#!/bin/bash\n\
set -e\n\
/lib/systemd/systemd-udevd --daemon\n\
udevadm control --reload && udevadm trigger\n\
cd ~/interbotix_ws && colcon build && cd\n\
exec "$@"\n' > /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]

 
