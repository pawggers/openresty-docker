# Dockerfile - novae-base
# https://github.com/pawggers/docker-openresty

ARG RESTY_VERSION="1.19.3.1"

FROM openresty/openresty:${RESTY_VERSION}-alpine-fat

ARG GEO_DB_RELEASE=2021-03
ARG MODSEC_BRANCH=v3.0.4
ARG OWASP_BRANCH=v3.3/master
ARG RESTY_VERSION

LABEL maintainer="Alyx Wolcott <alyx@sourcenova.net>"

WORKDIR /tmp

# Add build dependencies
RUN apk add --no-cache --virtual .build-deps \
    autoconf \
    automake \
    byacc \
    curl-dev \
    flex \
    g++ \
    gcc \
    geoip-dev \
    git \
    libc-dev \
    libmaxminddb-dev \
    libstdc++ \
    libtool \
    libxml2-dev \
    linux-headers \
    lmdb-dev \
    make \
    openssl-dev \
    pcre-dev \
    yajl-dev \
    zlib-dev
# Clone ModSecurity nginx connector, GeoIP2, Brotli.
RUN git clone -b master --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git && \
    git clone -b master --depth 1 https://github.com/leev/ngx_http_geoip2_module.git && \
    git clone -b master --depth 1 https://github.com/google/ngx_brotli.git && \
    git clone -b ${OWASP_BRANCH} --depth 1 https://github.com/coreruleset/coreruleset.git /usr/local/owasp-modsecurity-crs && \
    curl -fSL https://openresty.org/download/openresty-${RESTY_VERSION}.tar.gz -o openresty-${RESTY_VERSION}.tar.gz && \
    tar xzf openresty-${RESTY_VERSION}.tar.gz && \
    mkdir -p /etc/nginx/geoip && \
    curl https://download.db-ip.com/free/dbip-city-lite-${GEO_DB_RELEASE}.mmdb.gz | gzip -d > /etc/nginx/geoip/dbip-city-lite.mmdb && \
    curl https://download.db-ip.com/free/dbip-country-lite-${GEO_DB_RELEASE}.mmdb.gz | gzip -d > /etc/nginx/geoip/dbip-country-lite.mmdb

# Clone and compile ModSecurity
RUN git clone -b ${MODSEC_BRANCH} --depth 1 https://github.com/SpiderLabs/ModSecurity && \
    git -C /tmp/ModSecurity submodule update --init --recursive && \
    (cd "/tmp/ModSecurity" && \
        ./build.sh && \
        ./configure --with-lmdb && \
        make && \
        make install \
    ) && \
    rm -rf /tmp/ModSecurity \
        /usr/local/modsecurity/lib/libmodsecurity.a \
        /usr/local/modsecurity/lib/libmodsecurity.la

# Install the modules and clean up
RUN (cd /tmp/openresty-${RESTY_VERSION} && \
        ./configure --with-compat \
            --add-dynamic-module=../ModSecurity-nginx \
            --add-dynamic-module=../ngx_http_geoip2_module \
            --add-dynamic-module=../ngx_brotli && \
        make modules \
    ) && \
    cp /tmp/openresty-${RESTY_VERSION}/objs/ngx_http_modsecurity_module.so \
       /tmp/openresty-${RESTY_VERSION}/objs/ngx_http_geoip2_module.so \
       /tmp/openresty-${RESTY_VERSION}/objs/ngx_http_brotli_filter_module.so \
       /tmp/openresty-${RESTY_VERSION}/objs/ngx_http_brotli_static_module.so \
       /usr/local/openresty/nginx/modules/ && \
    rm -fr /tmp/* && \
    apk del .build-deps

# Set up some redirections for logging
RUN mkdir -p /var/run/openresty && \
    ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log && \
    ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log

RUN mkdir -p /etc/nginx/modsec && \
    mkdir -p /etc/nginx/conf.d

# Copy nginx configuration files
COPY ./conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./conf/nginx.vh.default.conf /etc/nginx/conf.d/default.conf

# Copy modsecurity defaults
COPY ./conf/modsec/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
COPY ./conf/modsec/unicode.mapping /etc/nginx/modsec/unicode.mapping

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT