#!/bin/bash

# Nexmon CSI Installer with crontab resume support
# For Raspberry Pi 3B+/4 (kernel 4.19 or 5.4)
# Save this as: setup.sh
# Run with: sudo bash setup.sh

set -e
INSTALL_FLAG="/home/pi/.nexmon_csi_step"

function add_cron_restart() {
    echo "📌 Setting up crontab for auto-resume after reboot..."
    (crontab -l 2>/dev/null; echo "@reboot /bin/bash /home/pi/setup.sh >> /home/pi/nexmon_install.log 2>&1") | crontab -
}

function remove_cron_restart() {
    echo "🧹 Removing crontab entry..."
    crontab -l | grep -v 'setup.sh' | crontab -
}

# 단계별 설치 진행

# Step 0: 패키지 설치 후 재부팅
if [ ! -f "$INSTALL_FLAG" ]; then
    echo "🔧 Step 0: System update and dependencies install..."
    touch "$INSTALL_FLAG"
    apt-get update && apt-get upgrade -y
    apt-get install -y raspberrypi-kernel-headers git libgmp3-dev gawk qpdf bison flex make \
                       automake autoconf libtool texinfo
    echo "REBOOT1" > "$INSTALL_FLAG"
    add_cron_restart
    echo "🔁 Rebooting now to apply kernel headers..."
    sleep 3
    reboot
fi

# Step 1: Nexmon 설치
if grep -q "REBOOT1" "$INSTALL_FLAG"; then
    echo "🔧 Step 1: Cloning and setting up Nexmon..."
    cd /home/pi
    git clone https://github.com/seemoo-lab/nexmon.git
    cd nexmon

    # libisl check
    if [ ! -f /usr/lib/arm-linux-gnueabihf/libisl.so.10 ]; then
        cd buildtools/isl-0.10
        ./configure
        make -j$(nproc)
        make install
        ln -s /usr/local/lib/libisl.so /usr/lib/arm-linux-gnueabihf/libisl.so.10
        cd ../../
    fi

    # libmpfr check
    if [ ! -f /usr/lib/arm-linux-gnueabihf/libmpfr.so.4 ]; then
        cd buildtools/mpfr-3.1.4
        autoreconf -f -i
        ./configure
        make -j$(nproc)
        make install
        ln -s /usr/local/lib/libmpfr.so /usr/lib/arm-linux-gnueabihf/libmpfr.so.4
        cd ../../
    fi

    echo "REBOOT2" > "$INSTALL_FLAG"
    echo "🔁 Rebooting now before firmware patch..."
    sleep 3
    reboot
fi

# Step 2: 펌웨어 패치 및 nexutil 설치
if grep -q "REBOOT2" "$INSTALL_FLAG"; then
    echo "🔧 Step 2: Applying CSI patch and installing nexutil..."
    cd /home/pi/nexmon
    source setup_env.sh
    make

    cd patches/bcm43455c0/7_45_189/
    git clone https://github.com/seemoo-lab/nexmon_csi.git
    cd nexmon_csi
    make install-firmware

    cd /home/pi/nexmon/utilities/nexutil
    make && make install

    echo "REBOOT3" > "$INSTALL_FLAG"
    echo "🔁 Final reboot after firmware patch..."
    sleep 3
    reboot
fi

# Step 3: 마무리 작업
if grep -q "REBOOT3" "$INSTALL_FLAG"; then
    echo "✅ Nexmon CSI installation complete!"
    remove_cron_restart
    rm "$INSTALL_FLAG"
    echo "🔁 One last reboot (optional)..."
    reboot
fi

