ARG OPEN5GS_BASE_IMAGE=ghcr.io/herlesupreeth/docker_open5gs:master

FROM ubuntu:jammy AS builder

ENV DEBIAN_FRONTEND=noninteractive
ARG OPEN5GS_COMMIT=782a97efe9e3acb1251e318bd3738ced4044dac8
ARG AMF_T3513_DURATION=5
ARG AMF_T3513_MAX_COUNT=6

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    meson \
    ninja-build \
    flex \
    bison \
    libsctp-dev \
    libgnutls28-dev \
    libgcrypt-dev \
    libssl-dev \
    libidn11-dev \
    libmongoc-dev \
    libbson-dev \
    libyaml-dev \
    libmicrohttpd-dev \
    libcurl4-gnutls-dev \
    libnghttp2-dev \
    libtins-dev \
    libtalloc-dev \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --recursive https://github.com/open5gs/open5gs /open5gs-src && \
    cd /open5gs-src && \
    git checkout ${OPEN5GS_COMMIT}

RUN python3 - <<PY
from pathlib import Path

duration = int("${AMF_T3513_DURATION}")
max_count = int("${AMF_T3513_MAX_COUNT}")
p = Path('/open5gs-src/src/amf/timer.c')
text = p.read_text()
old = """    /* Paging procedure for EPS services initiated */
    [AMF_TIMER_T3513] =
        { .have = true, .max_count = 2, .duration = ogs_time_from_sec(2) },
"""
new = f"""    /* Paging procedure for EPS services initiated */
    [AMF_TIMER_T3513] =
        {{ .have = true, .max_count = {max_count}, .duration = ogs_time_from_sec({duration}) }},
"""
if old not in text:
    raise SystemExit('AMF_TIMER_T3513 patch target not found')
p.write_text(text.replace(old, new, 1))
PY

RUN cd /open5gs-src && \
    meson build --prefix=$(pwd)/install && \
    ninja -C build open5gs-amfd

FROM ${OPEN5GS_BASE_IMAGE}
COPY --from=builder /open5gs-src/build/src/amf/open5gs-amfd /open5gs/install/bin/open5gs-amfd
