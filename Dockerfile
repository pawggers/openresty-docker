# Dockerfile - novae-base
# https://github.com/pawggers/docker-openresty

ARG RESTY_VERSION="1.19.3.1"

FROM openresty/openresty:${RESTY_VERSION}-alpine-fat

ARG GEO_DB_RELEASE=2021-03
ARG MODSEC_BRANCH=v3.0.4
ARG OWASP_BRANCH=v3.3/master
ARG NGINX_VERSION="1.19.3"
ARG RESTY_VERSION

LABEL maintainer="Alyx Wolcott <alyx@sourcenova.net>"

# Compile-time arguments borrowed from docker-openresty
ARG RESTY_CONFIG_OPTIONS="\
    --with-compat \
    --with-file-aio \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_geoip_module=dynamic \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module=dynamic \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_xslt_module=dynamic \
    --with-ipv6 \
    --with-mail \
    --with-mail_ssl_module \
    --with-md5-asm \
    --with-pcre-jit \
    --with-sha1-asm \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \
    "
ARG RESTY_CONFIG_OPTIONS_MORE=""
ARG RESTY_LUAJIT_OPTIONS="--with-luajit-xcflags='-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'"

ARG RESTY_ADD_PACKAGE_BUILDDEPS=""
ARG RESTY_ADD_PACKAGE_RUNDEPS=""
ARG RESTY_EVAL_PRE_CONFIGURE=""
ARG RESTY_EVAL_POST_MAKE=""

# These are not intended to be user-specified
ARG _RESTY_CONFIG_DEPS="--with-pcre \
    --with-cc-opt='-DNGX_LUA_ABORT_AT_PANIC -I/usr/local/openresty/pcre/include -I/usr/local/openresty/openssl/include' \
    --with-ld-opt='-L/usr/local/openresty/pcre/lib -L/usr/local/openresty/openssl/lib -Wl,-rpath,/usr/local/openresty/pcre/lib:/usr/local/openresty/openssl/lib' \
    "

# [WORKDIR /tmp]
RUN cd /tmp; \
    # Add Novae repo for ModSecurity
    curl https://distfiles.novae.tel/apk/alyx-605e73f3.rsa.pub > /etc/apk/keys/alyx-605e73f3.rsa.pub; \
    echo "https://distfiles.novae.tel/apk/v3.13/main" >> /etc/apk/repositories; \
    apk update; \
    # Update base system
    apk upgrade; \
    # Install dependencies
    ## Add runtime dependencies
    apk add --no-cache \
    gd \
    geoip \
    libmaxminddb \
    libmodsecurity \
    libstdc++ \
    libxml2 \
    libxslt \
    lmdb \
    openssl \
    pcre \
    yajl \
    zlib; \
    ## Add build dependencies
    apk add --no-cache --virtual .build-deps \
    autoconf \
    automake \
    byacc \
    curl-dev \
    flex \
    g++ \
    gcc \
    gd-dev \
    geoip-dev \
    git \
    libc-dev \
    libmaxminddb-dev \
    libmodsecurity-dev \
    libstdc++ \
    libtool \
    libxml2-dev \
    libxslt-dev \
    linux-headers \
    lmdb-dev \
    make \
    openssl-dev \
    pcre-dev \
    yajl-dev \
    zlib-dev; \
    # Pull in sources
    ## ModSecurity nginx connector
    git clone -b master --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git; \
    ## GeoIP2
    git clone -b master --depth 1 https://github.com/leev/ngx_http_geoip2_module.git; \
    ## Brotli
    git clone -b master --depth 1 https://github.com/google/ngx_brotli.git; \
    curl -fSL https://openresty.org/download/openresty-${RESTY_VERSION}.tar.gz -o openresty-${RESTY_VERSION}.tar.gz && \
    tar xzf openresty-${RESTY_VERSION}.tar.gz; \
    # Pull in and prepare data
    ## OWASP CRS
    git clone -b ${OWASP_BRANCH} --depth 1 https://github.com/coreruleset/coreruleset.git /usr/local/owasp-modsecurity-crs; \
    ## MaxMind GEOIP
    mkdir -p /etc/nginx/geoip/; \
    curl https://download.db-ip.com/free/dbip-city-lite-${GEO_DB_RELEASE}.mmdb.gz | gzip -d > /etc/nginx/geoip/dbip-city-lite.mmdb; \
    curl https://download.db-ip.com/free/dbip-country-lite-${GEO_DB_RELEASE}.mmdb.gz | gzip -d > /etc/nginx/geoip/dbip-country-lite.mmdb; \
    # Build modules
    # [WORKDIR /tmp/openresty-${RESTY_VERSION}]
    cd /tmp/openresty-${RESTY_VERSION}; \
    eval ./configure \
            ${_RESTY_CONFIG_DEPS} ${RESTY_CONFIG_OPTIONS} ${RESTY_CONFIG_OPTIONS_MORE} ${RESTY_LUAJIT_OPTIONS} \
            --with-compat \
            --add-dynamic-module=../ModSecurity-nginx \
            --add-dynamic-module=../ngx_http_geoip2_module \
            --add-dynamic-module=../ngx_brotli; \
    make; \
    # build/nginx-1.19.3/objs
    # Install modules
    # [WORKDIR /tmp/openresty-${RESTY_VERSION}/build/nginx-${NGINX_VERSION}]
    cd /tmp/openresty-${RESTY_VERSION}/build/nginx-${NGINX_VERSION}; \
    cp ./objs/ngx_http_modsecurity_module.so \
       ./objs/ngx_http_geoip2_module.so \
       ./objs/ngx_http_brotli_filter_module.so \
       ./objs/ngx_http_brotli_static_module.so \
       /usr/local/openresty/nginx/modules/; \
    # Cleanup
    # [WORKDIR /tmp]
    cd /tmp; \
    rm -fr /tmp/*; \
    apk del .build-deps; \
    # Setup logging redirections
    # (moved to later) mkdir -p /var/run/openresty; \
    ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log; \
    ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log; \
    # Copy default configuration files
    ## Create directories
    mkdir -p /etc/nginx/modsec; \
    mkdir -p /etc/nginx/conf.d; \
    tar zcvf nginx.tar.gz /etc/nginx; \
    tar zcvf openresty.tar.gz /usr/local/openresty;

FROM alpine:3.13

RUN apk add --no-cache curl; \
    # Add Novae repo for ModSecurity
    curl https://distfiles.novae.tel/apk/alyx-605e73f3.rsa.pub > /etc/apk/keys/alyx-605e73f3.rsa.pub; \
    echo "https://distfiles.novae.tel/apk/v3.13/main" >> /etc/apk/repositories; \
    apk upgrade --no-cache; \
    ## Add runtime dependencies
    apk add --no-cache \
    gd \
    geoip \
    libmaxminddb \
    libmodsecurity \
    libstdc++ \
    libxml2 \
    libxslt \
    lmdb \
    openssl \
    pcre \
    yajl \
    zlib;

# Copy program (compressed)
COPY --from=0 /tmp/nginx.tar.gz /
COPY --from=0 /tmp/openresty.tar.gz /

# Uncompress program
RUN tar xvf nginx.tar.gz; rm nginx.tar.gz;\
    tar xvf openresty.tar.gz; rm openresty.tar.gz; \
    mkdir -p /var/run/openresty;

## Copy nginx configuration files
COPY ./conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./conf/nginx.vh.default.conf /etc/nginx/conf.d/default.conf
## Copy modsecurity defaults
COPY ./conf/modsec/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
COPY ./conf/modsec/unicode.mapping /etc/nginx/modsec/unicode.mapping

WORKDIR /

EXPOSE 80 443

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT