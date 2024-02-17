# https://github.com/gliderlabs/docker-alpine
FROM alpine:latest

# http://jumanjiman.github.io/
LABEL authors="Paul Morgan <jumanjiman@gmail.com>,Rich Siegel <rsiegel@thirdpoint.com>"

ENV VERSION 0.1.1
ENV HOME "/tmp"
# RUN apk update && apk add ca-certificates

# COPY ssl/*.crt /usr/local/share/ca-certificates/

# RUN update-ca-certificates

COPY /src/puppet-autostager-0.1.1.gem .

RUN apk add --no-cache ruby git perl && \
    apk add --no-cache -t DEV alpine-sdk ruby-dev && \
    gem install --local puppet-autostager-0.1.1.gem && \
    gem install json && \
    gem install rest-client && \
    gem install rexml && \
    gem install puppet && \
    gem install net-ftp && \
    apk del DEV

RUN adduser -D puppet

RUN mkdir -p  /etc/puppetlabs/puppet
RUN mkdir -p /etc/puppetlabs/code/environments
RUN touch  /etc/puppetlabs/puppet/puppet.conf
USER 999
RUN mkdir -p /tmp/.puppetlabs/etc/code && \
    ln -s /etc/puppetlabs/code/environments /tmp/.puppetlabs/etc/code/environments

ENTRYPOINT ["autostager"]

