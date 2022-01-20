FROM debian

# Install utilities
RUN apt-get update
RUN apt-get install -y curl xz-utils git build-essential manpages-dev gdb

# Install zig
WORKDIR /home/zig
RUN curl -L https://ziglang.org/download/0.9.0/zig-linux-x86_64-0.9.0.tar.xz | tar -xJ --strip-components=1 -C .
RUN ln -s /home/zig/zig /usr/bin/zig

# Install zls
WORKDIR /home/zls
RUN curl -L https://github.com/zigtools/zls/releases/download/0.9.0/x86_64-linux.tar.xz | tar -xJ --strip-components=1 -C .
RUN chmod +x zls
RUN ln -s /home/zls/zls /usr/bin/zls