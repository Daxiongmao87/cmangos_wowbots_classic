# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Set environment variables to non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages
RUN apt-get update && apt-get install -y \
    sudo \
    build-essential \
    clang-12 clang++-12 \
    automake \
    git-core \
    autoconf \
    make \
    patch \
    libmariadb-dev-compat \
    mariadb-server \
    libtool \
    libssl-dev \
    grep \
    binutils \
    zlib1g-dev \
    libbz2-dev \
    cmake \
    libboost-all-dev \
    screen \
    nginx \
    php-fpm \
    php-mysql \
    php \
    php-cli \
    php-curl \
    php-gd \
    php-gmp \
    php-mbstring \
    php-soap \
    php-xml \
    php-json \
    php-opcache \
    python3-srp \
    curl \
    nano \
    gridsite-clients \
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 100 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-12 100 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Clang as the default C and C++ compiler
ENV CC=clang
ENV CXX=clang++

# Create the mangos user and add to sudoers
RUN useradd -m -d /home/mangos -s /bin/bash mangos && \
    echo "mangos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create the /run/mysqld directory and give mangos ownership
RUN mkdir -p /run/mysqld && chown mangos:mangos /run/mysqld

# Switch to the mangos user
USER mangos
RUN mkdir /home/mangos/server
WORKDIR /home/mangos/server


# Clone the CMaNGOS Classic core, database, and website repositories
RUN git clone --single-branch  https://github.com/cmangos/mangos-classic.git mangos && \
    git -C mangos checkout 8a569a946ce367efa29b0cef098f7af6c45d27d6 && \
    git clone --single-branch https://github.com/cmangos/classic-db.git database && \
    git -C database checkout 51c1a1075c9cca63b1d0c0e078407948de227258 && \
    mkdir -p mangos/src/modules && \
##    git clone https://github.com/cmangos/playerbots.git mangos/src/modules/Bots && \
    git clone https://github.com/daxiongmao87/cmangos-website.git website

# Make/compile the CMaNGOS Classic core
WORKDIR /home/mangos/server/mangos
# Configure and build the CMaNGOS project
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/home/mangos/server/run -DPCH=1 -DDEBUG=0 -DBUILD_PLAYERBOTS=ON -DBUILD_AHBOT=ON -DBUILD_EXTRACTORS=ON -DBUILD_GAME_SERVER=ON -DBUILD_LOGIN_SERVER=ON && \
    make -j $(nproc) && make install


COPY --chown=mangos entrypoint.sh /home/mangos/entrypoint.sh
RUN chmod +x /home/mangos/entrypoint.sh

# Expose necessary ports (Assuming standard ports, adjust if needed)
EXPOSE 8085 3724 8080
WORKDIR /home/mangos
# Set the entrypoint script to run when the container starts
ENTRYPOINT ["/home/mangos/entrypoint.sh"]
