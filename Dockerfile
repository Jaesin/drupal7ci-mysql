# This Dockerfile is a modified version of https://github.com/Lullabot/drupal7ci/blob/master/Dockerfile
# A Mysql 5.7 package does not exist for Debian 11 (bullseye).
FROM php:8.1-apache-buster

COPY --from=composer:2.5.8 /usr/bin/composer /usr/bin/composer

RUN a2enmod rewrite

# Add requirements
RUN apt update && apt install -y \
    git \
    imagemagick \
    libjpeg-dev \
    libmagickwand-dev \
    libpq-dev \
    libonig-dev \
    mariadb-client \
    rsync \
    sudo \
    gosu \
    unzip \
    vim \
    wget \
    libxml2-utils

# Install the PHP extensions we need
RUN docker-php-ext-configure gd --with-jpeg \
	&& docker-php-ext-install bcmath gd mbstring mysqli pdo pdo_mysql pdo_pgsql \
    && pecl install redis apcu \
    && docker-php-ext-enable redis apcu \
	&& rm -rf /tmp/pear /var/lib/apt/lists/* 

# Remove the memory limit for the CLI only.
RUN echo 'memory_limit = -1' > /usr/local/etc/php/php-cli.ini

# Change docroot.
WORKDIR /var/www/html/docroot
RUN mkdir -p /var/www/html/docroot && touch /var/www/html/docroot/index.html
# Make sure www-data owns the /var/www directory.
RUN chown -R www-data:www-data /var/www

RUN sed -ri -e 's!/var/www/html!/var/www/html/docroot!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www!/var/www/html/docroot!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Install XDebug.
RUN pecl install xdebug-3.2.2 \
    && docker-php-ext-enable xdebug

# Install Dockerize.
ENV DOCKERIZE_VERSION v0.6.0
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# Install mysql 5.7.
RUN apt update && apt install -y lsb-release gnupg wget debconf-utils \
    && echo 'ade43b291d4b8db2a00e292de7307745  mysql-apt-config_0.8.22-1_all.deb' > mysql-apt-config_0.8.22-1_all.deb.md5 \
    && wget https://dev.mysql.com/get/mysql-apt-config_0.8.22-1_all.deb \
    && md5sum -c mysql-apt-config_0.8.22-1_all.deb.md5 \
    && echo 'mysql-apt-config mysql-apt-config/repo-distro select debian'      | debconf-set-selections \
    && echo 'mysql-apt-config mysql-apt-config/select-server select mysql-5.7' | debconf-set-selections \
    && DEBIAN_FRONTEND=noninteractive dpkg -i mysql-apt-config_0.8.22-1_all.deb \
    && apt update \
    && DEBIAN_FRONTEND=noninteractive apt install -y mysql-community-client mysql-client mysql-community-server mysql-server

# Create the default user and database.
RUN service mysql start \
    && echo "CREATE DATABASE IF NOT EXISTS drupal CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci ;"   | mysql -uroot \
    && echo "CREATE USER 'drupal'@'%' IDENTIFIED BY 'drupal' ;"                                         | mysql -uroot \
    && echo "GRANT ALL ON drupal.* TO 'drupal'@'%' WITH GRANT OPTION ;"                                 | mysql -uroot \
    && echo "FLUSH PRIVILEGES ;"                                                                        | mysql -uroot \
    && service mysql stop

# Install additional dependencies.
RUN printf "#### Install PHP Extensions ####\n" \
    && apt update \
    && apt install -y libzip-dev tini \
    && docker-php-ext-install gettext zip

# Copy the init file.
COPY docker-init /usr/local/bin/

USER www-data

RUN printf "\n#### Install Drush 8 ####\n" \
    && composer global require drush/drush:"8.4.11" \
        \
    && printf "\n#### Install PHPUnit ####\n" \
    && composer global require phpunit/phpunit:"^9.0" \
    && composer clearcache

USER root

# Create symbolic links.
RUN printf "\n#### Creating links for drush and phpunit ####\n" \
    && ln -s /var/www/.composer/vendor/bin/drush /usr/local/bin/drush \
    && ln -s /var/www/.composer/vendor/bin/phpunit /usr/local/bin/phpunit \
    && printf "\n#### Disabling XDebug ####\n" \
    && sed -i -e 's/zend_extension/\;zend_extension/g' $(php --info | grep xdebug.ini | sed 's/,*$//g')

# Expose the default apace2 and mysql ports.
EXPOSE 80 3306

# Setup the healthcheck command
HEALTHCHECK CMD /usr/bin/mysqladmin ping && /usr/bin/curl --fail http://localhost || exit 1

# Let tini manage daemons.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/docker-init"]
