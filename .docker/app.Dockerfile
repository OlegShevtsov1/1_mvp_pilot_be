FROM ruby:3.3.6

RUN apt-get update -qq && \
    apt-get install -y nodejs postgresql-client&& \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /code
COPY . /code

RUN bundle install && \
    cp .docker/app.entrypoint.sh /usr/bin/entrypoint.sh && \
    chmod +x /usr/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000
