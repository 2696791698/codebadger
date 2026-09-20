# Dockerfile for Joern Server Container
# Contains Joern CLI for CPG generation and caching

FROM eclipse-temurin:21-jdk-jammy

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Set Joern version
ENV JOERN_VERSION=4.0.627
ENV JOERN_HOME=/opt/joern

# Download and install Joern CLI from joernio/joern GitHub releases
# 说明: 不走官方 joern-install.sh —— 该脚本不读 ENV JOERN_VERSION, 非交互模式下版本号
#       为空, 会去下 releases/latest; 而新版 release 改了 asset 命名 (joern-cli.zip ->
#       joern-cli-linux-x86_64.zip), 于是下到 9 字节的 "Not Found" 文本, unzip 失败导致
#       构建中断。这里按版本号直接下载, 依次尝试新旧两种命名, 并沿用 CodeQL 那段的
#       HTTP/1.1 + 断点续传 + 重试 (这个包约 1.8 GB, 直连容易中断)。
#       两种命名的包解压后顶层都是 joern-cli/, 与下面的 PATH 一致。
RUN set -eux; \
    mkdir -p ${JOERN_HOME}; \
    base="https://github.com/joernio/joern/releases/download/v${JOERN_VERSION}"; \
    ok=0; \
    for name in joern-cli-linux-x86_64.zip joern-cli.zip; do \
        echo "==> 尝试下载 Joern: ${name}"; \
        for attempt in $(seq 1 5); do \
            size_before=$(stat -c %s /tmp/joern-cli.zip 2>/dev/null || echo 0); \
            timeout 1800 curl -fL --http1.1 --connect-timeout 30 \
                -C - -o /tmp/joern-cli.zip "$base/$name" || true; \
            if unzip -tq /tmp/joern-cli.zip > /dev/null 2>&1; then \
                echo "==> ${name} 下载完成并通过完整性校验"; \
                ok=1; \
                break; \
            fi; \
            size_after=$(stat -c %s /tmp/joern-cli.zip 2>/dev/null || echo 0); \
            if [ "$size_after" -eq "$size_before" ]; then \
                echo "==> 本次尝试无进展, 清除残留文件后重试"; \
                rm -f /tmp/joern-cli.zip; \
            fi; \
            sleep 5; \
        done; \
        if [ "$ok" -eq 1 ]; then break; fi; \
        rm -f /tmp/joern-cli.zip; \
    done; \
    if [ "$ok" -ne 1 ]; then echo "!! Joern 下载失败" >&2; exit 1; fi; \
    unzip -q /tmp/joern-cli.zip -d ${JOERN_HOME}; \
    rm -f /tmp/joern-cli.zip; \
    chmod -R a+rX ${JOERN_HOME}

# Add Joern CLI tools to PATH
ENV PATH="${JOERN_HOME}/joern-cli:${JOERN_HOME}/joern-cli/bin:${PATH}"

# Create playground directory for CPG storage
RUN mkdir -p /playground

# Verify Joern installation
RUN joern --help

# Create entrypoint script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Keep container running\n\
tail -f /dev/null\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

# Run entrypoint script
CMD ["/entrypoint.sh"]
