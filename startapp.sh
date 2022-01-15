#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

download() {
  jar=$1
  path=$2
  if [ ! -f "${path}/${jar}" ]; then
    URI="Applications/dellUI/Java/release"
    wget --load-cookies=cookies -O "${path}/${jar}" https://${IDRAC_HOST}/${URI}/${jar} --no-check-certificate
    if [ ! $? -eq 0 ]; then
      echo -e "${RED}Failed to download ${jar}, please check your settings${NC}"
      sleep 2
      exit 2
    fi
  fi
}

echo "Starting"


if [ -f "/run/secrets/cmc_host" ]; then
    echo "Using Docker secret for CMC_HOST"
    CMC_HOST="$(cat /run/secrets/cmc_host)"
fi

if [ -f "/run/secrets/cmc_user" ]; then
    echo "Using Docker secret for CMC_USER"
    CMC_USER="$(cat /run/secrets/cmc_user)"
fi

if [ -f "/run/secrets/cmc_password" ]; then
    echo "Using Docker secret for CMC_PASSWORD"
    CMC_PASSWORD="$(cat /run/secrets/cmc_password)"
fi


if [ -z "${CMC_HOST}" ]; then
    echo -e "${RED}Please set a proper cmc host with CMC_HOST${NC}"
    sleep 2
    exit 1
fi

if [ -z "${CHASSIS_ID}" ]; then
    echo -e "${RED}Please set a proper chassis id with CHASSIS_ID${NC}"
    sleep 2
    exit 1
fi

if [ -z "${CMC_USER}" ]; then
    echo -e "${RED}Please set a proper cmc user with CMC_USER${NC}"
    sleep 2
    exit 1
fi

if [ -z "${CMC_PASSWORD}" ]; then
    echo -e "${RED}Please set a proper cmc password with CMC_PASSWORD${NC}"
    sleep 2
    exit 1
fi

echo "Environment ok"

echo "Creating library folder"

cd /app
mkdir -p lib

touch cookies

SID=$(curl --verbose -k --data "user=${CMC_USER}&user_id=${CMC_USER}&password=${CMC_PASSWORD}&ST2=NOTSET&WEBSERVER_timeout=1800&WEBSERVER_timeout_select=1800" https://${CMC_HOST}/cgi-bin/webcgi/login 2>&1 | grep "set-cookie" | cut -d = -f 2 | cut -d \; -f 1)
ST2=$(curl --verbose -k -H "Cookie: sid=${SID}" https://${CMC_HOST}/cgi-bin/webcgi/health2\?cat\=C00\&tab\=T01\&id\=P02 2> /dev/null | grep "ST2" | cut -d \" -f 6)

iDRAC_URL=$(curl --verbose -k -H "Cookie: sid=${SID}" -H "User-Agent: Foo" https://${CMC_HOST}/cgi-bin/webcgi/blade_iDRAC_url\?serverSlot\=${CHASSIS_ID}\&ST2\=${ST2}\&serverAction\=-1\&vKVM=1 2> /dev/null | grep "The document has moved" | cut -d \" -f 2)

IDRAC_HOST=$(echo $iDRAC_URL | cut -d / -f 3 | cut -d : -f 1)
CMC_SESS_ID=$(echo $iDRAC_URL | cut -d = -f 2 | cut -d "&" -f 1)

SESSION_COOKIE=$(curl -k --data "WEBVAR_USERNAME=cmc&WEBVAR_PASSWORD=${CMC_SESS_ID}&WEBVAR_ISCMCLOGIN=1" https://${IDRAC_HOST}/Applications/dellUI/RPC/WEBSES/create.asp | grep "SESSION_COOKIE" | cut -d \' -f 4)
KVM_ARGS=$(curl -k -H "Cookie: SessionLang=EN; test=1; SessionCookie=${SESSION_COOKIE}; SessionCookieUser=cmc_root; IPMIPriv=4; ExtPriv=2147484159; SystemModel=PowerEdge M610" https://${IDRAC_HOST}/Applications/dellUI/Java/jviewer.jnlp | grep "argument"  | cut -d ">" -f 2 | cut -d "<" -f 1 | tr '\n' ' ')

# Create

echo "Extracted iDRAC host ${IDRAC_HOST}, cmc_sess_id ${CMC_SESS_ID} and cookie ${SESSION_COOKIE}"
echo "KVM Arguments: ${KVM_ARGS}"

echo "Downloading required files"

cd lib

if [ ! -f JViewer.jar ]; then
    download JViewer.jar .
fi
if [ ! -f Linux_x86_64.jar ]; then
    download Linux_x86_64.jar .
fi


if [ ! -f libjavacdromwrapper.so ] || [ ! -f libjavafloppywrapper.so ]; then
    echo "Extracting Linux_x86_64"

    /usr/lib/jvm/java-1.7-openjdk/bin/jar -xf Linux_x86_64.jar

    echo "Done extracting"
fi

cd ..

echo "${GREEN}Initialization complete, starting virtual console${NC}"

if [ -n "$IDRAC_KEYCODE_HACK" ]; then
    echo "Enabling keycode hack"

    export LD_PRELOAD=/keycode-hack.so
fi

# Aruments, RE'd from the JAR file
# 0    1    2             3   4           5         6             7               8        9          10
# Host port sessioncookie ssl vmedia_ssl  vmedia_cd cmedia_floppy user_privileges hid_port kvmEnabled languageId

exec java -cp 'lib/*' -Djava.library.path="/app/lib" com.ami.kvm.jviewer.JViewer $KVM_ARGS
