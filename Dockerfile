FROM google/dart:2.9-dev as build

WORKDIR /app
ADD pubspec.* /app/
RUN pub get

ADD ./bin /app/bin
RUN dart2native bin/telehouse.dart -o ./telehouse

FROM telegraf:1.14.4
COPY --from=build /app/telehouse .