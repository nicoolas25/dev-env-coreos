FROM ruby:2.2
RUN gem install rack
VOLUME /app
WORKDIR /app
EXPOSE 3000
CMD rackup -p 3000 -o 0.0.0.0
