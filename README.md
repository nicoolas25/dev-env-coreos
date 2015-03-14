# CoreOS and fleet to build a dev environment

## Create a CoreOS guest

You'll need to download and install [Vagrant][vagrant] before everything else.

Create a cluster of 3 virtual machines with [CoreOS][coreos] with the following
command:

    $ vagrant up

It'll fetch the latest CoreOS image that includes [Docker][docker],
[Fleet][fleet] and [Etcd][etcd]. This command will also update your
`./user-data` file with an unique `etcd` token.

## Using fleet to control your services

Fleet is like systemd for clusters. We'll use fleet to orchestrate our
containers inside the VM. At the end of this section, you'll know how to
use `fleetctl` to manage services running inside the VM, from your host.

### Getting started with fleetctl

[Fleetctl][fleet-client] helps us control the `fleetd` instance that runs
in your virtual machines. In order to continue, you'll need the `fleetctl`
binary in your _host_ `$PATH`, you can get it [here][fleet-dl].

Since CoreOS is running in a virtual machines, we need to tunnel the `fleetctl`
commands into our running `fleetd`. We'll do this via SSH from the host.

Vagrant will provide you the informations about the ssh config to your VMs with
the following command:

    $ vagrant ssh-config
    > Host core-01
        HostName 127.0.0.1
        User core
        Port 2222
        UserKnownHostsFile /dev/null
        StrictHostKeyChecking no
        PasswordAuthentication no
        IdentityFile /path/to/.vagrant.d/insecure_private_key
        IdentitiesOnly yes
        LogLevel FATAL

      Host core-02
        ...

You can now add this ssh key, that is global to all your vagrant machines to
your ssh-agent:

    $ ssh-add /path/to/.vagrant.d/insecure_private_key
    > Identity added: /path/to/.vagrant.d/insecure_private_key (/path/to/.vagrant.d/insecure_private_key)

After that you can export a `FLEETCTL_TUNNEL` enviroment variable set to the
hostname and port of your `core-01` machine:

    $ export FLEETCTL_TUNNEL=127.0.0.1:2222

Congratulations, you're now able to use `fleetctl` from your host to control
the services that are running inside your VM:

    $ fleetctl list-machines
    > MACHINE         IP              METADATA
      353a1ca7...     172.17.8.102    -
      70da50d0...     172.17.8.103    -
      a355495f...     172.17.8.101    -

### Starting containers with fleetctl

To start services or commands inside the cluster, you need to _load_ the service
definition (also called units):

    $ fleetctl load services/redis.2.8.service
    > Unit redis.2.8.service loaded on 353a1ca7.../172.17.8.102

Now, fleet knows about your redis service. You can list the services available:

    $ fleetctl list-units
    > UNIT                    MACHINE                         ACTIVE          SUB
      redis.2.8.service       353a1ca7.../172.17.8.102        inactive       dead
      registrator.service     353a1ca7.../172.17.8.102        active      running
      registrator.service     70da50d0.../172.17.8.103        active      running
      registrator.service     a355495f.../172.17.8.101        active      running
      skydns.service          353a1ca7.../172.17.8.102        active      running
      skydns.service          70da50d0.../172.17.8.103        active      running
      skydns.service          a355495f.../172.17.8.101        active      running

There is services that are already running on each machine: `skydns` and
`registrator`. We'll talk about them later.

Fleet can tell you the status of a service too:

    $ fleetctl status redis.2.8.service
    > ● redis.4.8.service - Redis 2.8 server
         Loaded: loaded (/run/fleet/units/redis.2.8.service; linked-runtime; vendor preset: disabled)
         Active: inactive (dead)

Of course, fleet lets you start your service (this is the whole point here):

    $ fleetctl start redis.2.8.service
    > Unit redis.2.8.service launched on 353a1ca7.../172.17.8.102

    $ fleetctl status redis.2.8.service
    > ● redis.2.8.service - Redis 2.8 server
         Loaded: loaded (/run/fleet/units/redis.2.8.service; linked-runtime; vendor preset: disabled)
         Active: active (running) since Sat 2015-03-14 12:27:36 UTC; 8s ago
        Process: 1770 ExecStartPre=/usr/bin/docker rm redis (code=exited, status=1/FAILURE)
       Main PID: 1777 (docker)
         CGroup: /system.slice/redis.2.8.service
                 └─1777 /usr/bin/docker run --rm --name redis -p 6379:6379 -e SERVICE_ID=core-02 redis:2.8

Since it is the first time we're running `redis:2.8`, docker will start by
pulling the image from the repository. Your redis service will be available
after that download. Try using `fleetctl journal -f redis.2.8.service` see
when your server is ready.

### Accessing your services directly

You can always access services using the virtual machine IP:

    $ redis-cli -h 172.17.8.102

To get the address of the machine hosting the redis.2.8.service you can use
this command:

    $ fleetctl list-units | grep redis.2.8.service | awk -F'[[:space:]/]' '{ print $3 }'
    > 172.17.8.102

### Accessing your services using Skydns

> Until now we were using only the host to run programs in the guest CoreOS
> system. From now we'll use both host (`$`) and the guest (`~`) commands.

As we've seen before, there is `skydns` and `registrator` that are already
configured and running on each virtual machine. SkyDNS provides a DNS server
based on `etcd` and Registrator register an entry in SkyDNS everytime a docker
container is launched.

Any machine in the cluster is hosting a SkyDNS conainer. Any machine can be used
as a DNS server. SkyDNS is configured to handle the `webapp.dev` domain by
itself then use Google's DNS.

In order to allow our host to enjoy the DNS server of the cluster, I prefix my
`/etc/resolv.conf` file with those lines:

    nameserver 172.17.8.101
    nameserver 172.17.8.102

Then I can `dig`, from the host, for the services I want:

    $ dig redis.webapp.dev

    > ; <<>> DiG 9.9.5-3ubuntu0.2-Ubuntu <<>> redis.webapp.dev
      ;; global options: +cmd
      ;; Got answer:
      ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 59737
      ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

      ;; QUESTION SECTION:
      ;redis.webapp.dev.              IN      A

      ;; ANSWER SECTION:
      redis.webapp.dev.       3600    IN      A       172.17.8.102

      ;; Query time: 2 msec
      ;; SERVER: 172.17.8.101#53(172.17.8.101)
      ;; WHEN: Sat Mar 14 14:09:26 CET 2015
      ;; MSG SIZE  rcvd: 50

We can see that the DNS used is SkyDNS from `172.17.8.101`. The format of the
SkyDNS host given a docker's container is:

    <service's ID>.<container's name>.<skydns's domain>
    core-02       .redis             .webapp.dev

The service's ID is given via the `SERVICE_ID` environment variable of the
container. The service's ID part is optional: it is possible to call either
`redis.webapp.dev` or `core-02.redis.webapp.dev`.

The service's ID is the hostname in the examples, see the services file for
more information.

Now you can do: `redis-cli -h redis.webapp.dev`.

## Preparing custom containers

With the redis example, we were working on a publicly available container. The
pattern we use to start services with fleet work as long as ou can provide a
docker image.

The following instruction implies that your application already have a
Dockerfile based on a publicly available image.

### Build an image that can run your app

We'll [build our Docker image][docker-build] from CoreOS since it already have
docker installed:

    $ vagrant ssh core-01
    ~ cd /code/webapp
    ~ sudo docker build -t nicoolas25/webapp ./Dockerfile

This command could take a while (depending on your connection). It'll build the
image described in the Dockerfile as `nicoolas25/webapp`. Here is the content
of the Dockerfile:

    FROM ruby:2.2
    RUN gem install rack
    VOLUME /app
    WORKDIR /app
    EXPOSE 3000
    CMD rackup -p 3000 -o 0.0.0.0

This will build a simple image from the `ruby:2.2` image, with `rack` installed,
expecting an application to be present in the `/app` directory and running on
port 3000.

After that you can ensure that the image is available with:

    ~ docker images | grep webapp

If you update your Dockerfile, you will need to repeat those steps to update the
docker image.

### Create a service from that image

Now that we've got an image, we have to create a fleet service to manage that
service. There is an example of such a service in `./services/webapp.service`:

    [Unit]
    Description=A web application example
    Requires=docker.service
    After=docker.service

    [Service]
    ExecStartPre=-/usr/bin/docker rm webapp
    ExecStart=/usr/bin/docker run --rm --name webapp -p 3000:3000 -v /code/webapp:/app nicoolas25/webapp
    ExecStop=/usr/bin/docker stop webapp

In this example, the `/code/webapp` is mounted in the container as `/app` in
order to share the application files.

Now you can, from the host, load and start the webapp service:

    $ fleetctl load services/webapp.service 
    > Unit webapp.service loaded on d33fcb2c.../172.17.8.101
    $ fleetctl start webapp.service
    > Unit webapp.service launched on d33fcb2c.../172.17.8.101

Once the service is started, you can access it from your host at:
`http://172.17.8.101:3000/`.

## Notes

### Binding port manually

About binding ports, it isn't suitable for production. Service discovery is a
better approach to solve the problem of getting the URL and port of a given
service on a cluster.


[consul]: https://consul.io/
[core-os]: https://coreos.com/
[docker]: https://www.docker.com/
[docker-build]: https://docs.docker.com/userguide/dockerimages/#building-an-image-from-a-dockerfile
[etcd]: https://github.com/coreos/etcd
[fleet]: https://github.com/coreos/fleet
[fleet-client]: https://github.com/coreos/fleet/blob/master/Documentation/using-the-client.md
[fleet-dl]: https://github.com/coreos/fleet/releases
[skydns]: https://github.com/skynetservices/skydns
[vagrant]: https://www.vagrantup.com/
[vulcand]: https://vulcand.io/

