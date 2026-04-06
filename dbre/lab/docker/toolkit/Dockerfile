FROM percona/percona-toolkit:3.5

USER root

# Install Percona XtraBackup 8.0 and mydumper
RUN set -ex && \
    ARCH=$(uname -m) && \
    # XtraBackup
    yum install -y \
        https://repo.percona.com/yum/percona-release-latest.noarch.rpm 2>/dev/null || true && \
    percona-release setup pdps-8.0 -y 2>/dev/null || true && \
    yum install -y percona-xtrabackup-80 mydumper 2>/dev/null || \
    yum install -y percona-xtrabackup-80 2>/dev/null || true && \
    xtrabackup --version 2>&1 | head -1

# Install gh-ost — fetch latest release URL from GitHub API at build time
RUN set -ex && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64)  ARCH_TAG="amd64" ;; \
        aarch64) ARCH_TAG="arm64" ;; \
        *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    URL=$(curl -s https://api.github.com/repos/github/gh-ost/releases/latest \
        | grep "browser_download_url" \
        | grep "linux-${ARCH_TAG}" \
        | grep -v sha256 \
        | head -1 \
        | sed 's/.*"\(https[^"]*\)".*/\1/') && \
    echo "Downloading gh-ost from: $URL" && \
    curl -sL "$URL" | tar xz -C /tmp/ && \
    install -m 755 /tmp/gh-ost /usr/local/bin/gh-ost && \
    rm -f /tmp/gh-ost && \
    gh-ost --version
