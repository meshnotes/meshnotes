

# Linux下编译

## 1.安装基础依赖

### 1.1 更新系统并安装必要依赖

在Ubuntu 24.04.02进行测试。

首先，确保系统包是最新的，同时安装 Flutter 开发和 Linux 桌面支持所需的依赖项。打开终端后执行：

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install git curl unzip xz-utils libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev
```

解释：

- **git、curl、unzip、xz-utils**：用于下载和解压 Flutter SDK。
- **libglu1-mesa**：Flutter 的一些图形工具可能需要。
- **clang、cmake、ninja-build、pkg-config、libgtk-3-dev**：如果你打算编译 Linux 桌面版应用，这些库必不可少。

### 1.2 安装Chrome

要在linux下运行，需要安装Chrome

```bash
cd ~/Downloads
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb
sudo apt install -f
```

### 1.3 安装android工具链

安装OpenJDK，建议使用17

安装Android Studio

安装android SDK

安装cmdline-tools

## 2. 下载并切换到 Flutter 3.24.0

官方推荐通过 Git 仓库来管理 Flutter SDK，这样可以轻松切换不同版本。

首先，将 Flutter 仓库克隆到你的主目录中：

bash

```bash
cd ~
git clone https://github.com/flutter/flutter.git
```

进入 Flutter 目录并切换到标签 3.24.0（确保该标签存在，如有疑问可使用 `git tag` 检查所有可用版本）：

bash

```bash
cd flutter
git fetch --tags
git checkout 3.24.0
```

*提示：* 如果你打算以后持续更新，也可以选择某个分支（如 stable），但这里你要求的是 3.24.0，所以明确切换到此版本。

## 3. 配置 Flutter 环境变量

为了在任何终端窗口都能使用 `flutter` 命令，需要将 Flutter SDK 的 `bin` 目录添加到 PATH 中。执行：

bash

```bash
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

如果你使用的是其他 shell（如 zsh），请将上面的配置追加到相应的配置文件中（例如 `~/.zshrc`）。

## 4. 检查 Flutter 安装情况

接下来，运行以下命令检查 Flutter 环境配置情况及缺失项：

```bash
flutter doctor
```

此命令会检测：

- **Flutter SDK** 状态
- **设备（如 Linux 桌面、Android 模拟器）** 配置情况
- 如果你未来打算编译 Android 应用，还有 Android Toolchain 的配置情况

根据 `flutter doctor` 的提示，安装或配置其它工具（例如 同意Android license）以满足开发需求。

```bash
flutter doctor
Doctor summary (to see all details, run flutter doctor -v):
[!] Flutter (Channel [user-branch], 3.24.0, on Ubuntu 24.04.2 LTS 6.11.0-17-generic, locale en_US.UTF-8)
    ! Flutter version 3.24.0 on channel [user-branch] at /home/kali/github/flutter
      Currently on an unknown channel. Run `flutter channel` to switch to an official channel.
      If that doesn't fix the issue, reinstall Flutter by following instructions at https://flutter.dev/setup.
    ! Upstream repository unknown source is not a standard remote.
      Set environment variable "FLUTTER_GIT_URL" to unknown source to dismiss this error.
[✓] Android toolchain - develop for Android devices (Android SDK version 35.0.1)
[✓] Chrome - develop for the web
[✓] Linux toolchain - develop for Linux desktop
[✓] Android Studio (version 2024.2)
[✓] Connected device (2 available)
[✓] Network resources
```

## 5.下载并编译

```
git clone https://github.com/meshnotes/meshnotes.git
cd meshnotes
```

### 5.1 编译Linux桌面版

```
flutter build linux --release
```

编译成功后的可执行文件路径

```
build/linux/x64/release/bundle/MeshNotes
```

### 5.2 编译apk

```
flutter build apk --debug
```

注意需要在Android Studio的Settings-Build-Build Tools-Gradle中Gradle JDK改到17

| 组件        | 版本         |
| ----------- | ------------ |
| CMake       | 3.18.1       |
| NDK         | 21.1.6352462 |
| AndroidSDK  | 31,33,34,35  |
| Build Tools | 30.0.3       |

