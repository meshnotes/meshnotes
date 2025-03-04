Compile on Linux
================

1\. Install basic dependencies
------------------------------

### 1.1 Update the system and install necessary dependencies

Test on Ubuntu 24.04.02.

First, ensure that the system packages are up to date and install the dependencies required for Flutter development and Linux desktop support. Open the terminal and execute:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install git curl unzip xz-utils libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev
```
### 1.2 Install Chrome

To run in Linux, you need to install Chrome
```bash
cd ~/Downloads
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb
sudo apt install -f
```

### 1.3 Install Android Toolchain

Install OpenJDK, it is recommended to use version 17

Install Android Studio

Install Android SDK

Install cmdline-tools

2\. Download and switch to Flutter 3.24.0
-----------------------------------------

Officially, it is recommended to manage the Flutter SDK through a Git repository to easily switch between different versions.

First, clone the Flutter repository to your home directory:

```bash
cd ~
git clone https://github.com/flutter/flutter.git
```

Enter the Flutter directory and switch to tag 3.24.0 (ensure that the tag exists, and use `git tag` to check all available versions if in doubt):


```bash
cd flutter
git fetch --tags
git checkout 3.24.0
```
3\. Configure Flutter environment variables
-------------------------------------------

To use the `flutter` command in any terminal window, you need to add the `bin` directory of the Flutter SDK to the PATH. Execute:

bash
```bash
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

If you are using a different shell (such as zsh), please append the above configuration to the corresponding configuration file (for example `~/.zshrc` ).

4\. Check Flutter installation
------------------------------

Next, run the following command to check the Flutter environment configuration and missing items:
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

5\. Download and compile
------------------------
```bash
git clone https://github.com/meshnotes/meshnotes.git
cd meshnotes
```

### 5.1 Compile Linux Desktop Edition
```bash
flutter build linux --release
```

Path of the executable file after compilation
```bash
build/linux/x64/release/bundle/MeshNotes
```

### 5.2 Compile apk

```bash
flutter build apk --debug
```

Note that you need to change the Gradle JDK to version 17 in Android Studio's Settings > Build > Build Tools > Gradle

| **Component** | version         |
| ----------- | ------------ |
| CMake       | 3.18.1       |
| NDK         | 21.1.6352462 |
| AndroidSDK  | 31,33,34,35  |
| Build Tools | 30.0.3       |
