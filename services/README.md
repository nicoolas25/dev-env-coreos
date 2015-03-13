## Redis

    $ redis-cli -h 172.17.8.101

See the [Dockerfile](https://github.com/docker-library/redis/blob/master/2.8/Dockerfile) for more infos.

## Postgres

The default password is `postgres`, you can update it via the service file.

    $ psql -h 172.17.8.101 -p 5432 -U postgres

See the [Dockerfile](https://github.com/docker-library/postgres/blob/master/9.4/Dockerfile) for more infos.

