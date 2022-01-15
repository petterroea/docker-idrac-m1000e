FROM jlesage/baseimage-gui:alpine-3.7

ENV APP_NAME="iDRAC M1000e"

RUN apk add --no-cache curl
RUN apk add --no-cache wget
RUN apk add --no-cache openjdk7

COPY keycode-hack.c /keycode-hack.c
RUN apk add --no-cache gcc musl-dev libx11-dev && cc -o /keycode-hack.so /keycode-hack.c -shared -s -ldl -fPIC && rm /keycode-hack.c

RUN mkdir /app && \
    chown ${USER_ID}:${GROUP_ID} /app

COPY startapp.sh /startapp.sh

WORKDIR /app
