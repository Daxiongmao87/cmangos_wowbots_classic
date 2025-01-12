# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Set environment variables to non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# controlled in .env file
ARG WOW_EXPANSION
ARG MANGOS_COMMIT_SHA
ARG DB_COMMIT_SHA
ARG WEBSITE_COMMIT_SHA

ENV DOCKER_CLIENT_TIMEOUT=300

# Install necessary packages
RUN apt-get update && apt-get install -y \
    sudo \
    build-essential \
    gcc-12 g++-12 \
    clang \
    automake \
    unzip \
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
    git \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Boost manually to match the GitHub Action Boost version
ARG BOOST_VERSION=1.83.0
ARG BOOST_VERSION_USCORE="${BOOST_VERSION//./_}"
RUN apt-get update && apt-get install -y bash

RUN wget https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_USCORE}.tar.gz && \
    tar xfz boost_${BOOST_VERSION_USCORE}.tar.gz && \
    cd boost_${BOOST_VERSION_USCORE} && \
    ./bootstrap.sh --prefix=/usr/local && ./b2 install && \
    cd .. && rm -rf boost_${BOOST_VERSION_USCORE}*

# Set default compiler to GCC-12 and G++
ENV CC=gcc-12
ENV CXX=g++-12

# Create the mangos user and add to sudoers
RUN useradd -m -d /home/mangos -s /bin/bash mangos && \
    echo "mangos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create the /run/mysqld directory and give mangos ownership
RUN mkdir -p /run/mysqld && chown mangos:mangos /run/mysqld

# Switch to the mangos user
USER mangos
RUN mkdir /home/mangos/server
WORKDIR /home/mangos/server

# Download and extract repositories using provided commit hashes
RUN wget -O mangos.zip https://github.com/cmangos/mangos-${WOW_EXPANSION}/archive/${MANGOS_COMMIT_SHA}.zip && \
    wget -O database.zip https://github.com/cmangos/${WOW_EXPANSION}-db/archive/${DB_COMMIT_SHA}.zip && \
    wget -O website.zip https://github.com/Daxiongmao87/cmangos-website/archive/${WEBSITE_COMMIT_SHA}.zip && \
    unzip mangos.zip && mv mangos-${WOW_EXPANSION}-${MANGOS_COMMIT_SHA} mangos && \
    unzip database.zip && mv ${WOW_EXPANSION}-db-${DB_COMMIT_SHA} database && \
    unzip website.zip && mv cmangos-website-${WEBSITE_COMMIT_SHA} website

# Make/compile the CMaNGOS Classic core
WORKDIR /home/mangos/server/mangos

# Set dynamic build options to match GitHub Actions flexibility
ARG USE_PCH="ON"
ARG EXTRA_BUILD_OPTIONS="-DBUILD_PLAYERBOTS=ON -DBUILD_AHBOT=ON -DBUILD_EXTRACTORS=ON"

RUN mkdir build && cd build && \
    cmake .. -DBoost_ARCHITECTURE=-x64 -DCMAKE_INSTALL_PREFIX=/home/mangos/server/run -DPCH=${USE_PCH} -DDEBUG=0 ${EXTRA_BUILD_OPTIONS} && \
    make -j $(nproc) && make install

# Copy monitor script and set permissions
USER root
COPY monitor /usr/bin/monitor
RUN chmod +x /usr/bin/monitor

# Copy entrypoint script and set permissions
USER mangos
COPY --chown=mangos entrypoint.sh /home/mangos/entrypoint.sh
RUN chmod +x /home/mangos/entrypoint.sh

# Expose necessary ports (Assuming standard ports, adjust if needed)
EXPOSE 8085 3724 8080

# Set the entrypoint script to run when the container starts
ENTRYPOINT ["/home/mangos/entrypoint.sh"]

