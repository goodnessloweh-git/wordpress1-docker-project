FROM wordpress:php8.2-apache

# Copy WordPress files into container
COPY . /var/www/html/

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html
