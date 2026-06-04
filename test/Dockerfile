FROM php:8.5-fpm

RUN <<EOT
    #!/bin/bash -e -u -x -o pipefail
    apt-get update
    apt-get install --no-install-recommends --no-install-suggests --yes \
		libfreetype6-dev \
		libjpeg62-turbo-dev \
		libpng-dev
    docker-php-ext-configure gd --with-freetype --with-jpeg
    docker-php-ext-install -j$(nproc) gd
EOT
