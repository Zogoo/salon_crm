ARG RUBY_VERSION=3.4.10

# Stage 1: Build the Angular frontend
FROM node:22-slim AS frontend-build
WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ .
RUN npm run build -- --configuration=production

# Stage 2: Build the Rails backend
FROM ruby:${RUBY_VERSION}-slim AS production

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential libsqlite3-dev curl \
      libjemalloc2 && \
    rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/lib/$(dpkg --print-architecture | sed 's/amd64/x86_64-linux-gnu/;s/arm64/aarch64-linux-gnu/')/libjemalloc.so.2 /usr/local/lib/libjemalloc.so.2

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so.2 \
    MALLOC_CONF="dirty_decay_ms:1000,narenas:2,background_thread:true"

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

COPY . .

RUN rm -rf frontend/

COPY --from=frontend-build /frontend/dist/frontend/browser ./public/

ENV RAILS_ENV=production \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true

RUN mkdir -p tmp/pids tmp/cache log

RUN SECRET_KEY_BASE_DUMMY=1 bundle exec bootsnap precompile --gemfile app/ lib/

EXPOSE 3000
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
