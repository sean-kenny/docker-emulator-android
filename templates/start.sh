#!/usr/bin/env bash
console_port=$CONSOLE_PORT
adb_port=$ADB_PORT
adb_server_port=$ADB_SERVER_PORT
emulator_opts=$EMULATOR_OPTS

if [ -z "$console_port" ]
then
  console_port="5554"
fi
if [ -z "$adb_port" ]
then
  adb_port="5555"
fi
if [ -z "$adb_server_port" ]
then
  adb_server_port="5037"
fi
if [ -z "$emulator_opts" ]
then
  emulator_opts="-wipe-data -no-boot-anim -gpu off -netdelay none -netspeed full -skip-adb-auth -camera-back none -camera-front none -verbose"
fi

# Detect ip and forward ADB ports outside to outside interface
ip=$(ip addr list eth0|grep "inet "|cut -d' ' -f6|cut -d/ -f1)
redir --laddr=$ip --lport=$adb_server_port --caddr=127.0.0.1 --cport=$adb_server_port &
redir --laddr=$ip --lport=$console_port --caddr=127.0.0.1 --cport=$console_port &
redir --laddr=$ip --lport=$adb_port --caddr=127.0.0.1 --cport=$adb_port &

# Moving adb binary away so that stopping adb server with delay will release the emulator and will make it available for external connections
mv /opt/android-sdk-linux/platform-tools/adb /opt/android-sdk-linux/platform-tools/_adb
sleep 30 && _adb kill-server &

export DISPLAY=:1
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/android-sdk-linux/emulator/lib64/qt/lib:/opt/android-sdk-linux/emulator/lib64/libstdc++:/opt/android-sdk-linux/emulator/lib64:/opt/android-sdk-linux/emulator/lib64/gles_swiftshader
Xvfb :1 +extension GLX +extension RANDR +extension RENDER +extension XFIXES -screen 0 1024x768x24 &
fluxbox -display ":1.0" &
x11vnc -display :1 -nopw -forever &

# Set up and run emulator
# qemu references bios by relative path
cd /opt/android-sdk-linux/emulator

tar -xvf /opt/android-sdk-linux/system-images/{{ platform }}/google_apis/x86/userdata.img.tar.gz --directory /
tar -xvf /opt/android-sdk-linux/system-images/{{ platform }}/google_apis/x86/system.img.tar.gz --directory /

CONFIG="/root/.android/avd/x86.avd/config.ini"
CONFIGTMP=${CONFIG}.tmp

if [ -n "$ANDROID_CONFIG" ];
then
  IFS=';' read -ra OPTS <<< "$ANDROID_CONFIG"
  for OPT in "${OPTS[@]}"; do
    IFS='=' read -ra KV <<< "$OPT"
    KEY=${KV[0]}
    VALUE=${KV[1]}
    mv ${CONFIG} ${CONFIGTMP}
    cat ${CONFIGTMP} | grep -v ${KEY}= > ${CONFIG}
    echo ${OPT} >> ${CONFIG}
  done
fi

LIBGL_DEBUG=verbose ./qemu/linux-x86_64/qemu-system-i386 -avd x86 -ports $console_port,$adb_port $emulator_opts -qemu -m 2047 -enable-kvm $QEMU_OPTS
