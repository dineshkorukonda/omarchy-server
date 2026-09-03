FROM alpine:3.20

RUN apk add --no-cache openssh bash procps coreutils util-linux shadow

# Generate host keys and configure sshd
RUN ssh-keygen -A && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Create test user with unlocked password and authorized_keys
RUN useradd -m -s /bin/bash testuser && \
    echo 'testuser:*' | chpasswd -e && \
    mkdir -p /home/testuser/.ssh && \
    chmod 700 /home/testuser/.ssh

COPY id_ed25519.pub /home/testuser/.ssh/authorized_keys
RUN chmod 600 /home/testuser/.ssh/authorized_keys && \
    chown -R testuser:testuser /home/testuser/.ssh

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
