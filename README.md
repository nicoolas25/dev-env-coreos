# Using CoreOS and fleet as a development environment

## Create a CoreOS guest

You'll need to download and install [Vagrant][vagrant] before everything else.

Create a virtual machine with [CoreOS][coreos] with the following command:

    $ vagrant up

It'll fetch the latest CoreOS image that includes [Docker][docker],
[Fleet][fleet] and [Etcd][etcd]. This command will also update your
`./user-data` file with an unique `etcd` token.

## Using fleet to control your services

Fleet is like systemd for clusters. We'll use fleet to orchestrate our
containers inside the VM. At the end of this section, you'll know how to
use `fleetctl` to manage services running inside the VM, from your host.

### Getting started with fleetctl

[Fleet client usage documentation][fleet-client] helps us control the fleet
instance that runs in your virtual machine. In order to continue, you'll need
the `fleetctl` binary in your host `$PATH`, you can get it [here][fleet-dl].

Since CoreOS is running in a virtual machine, we need to tunnel the `fleetctl`
commands into our CoreOS `fleetd`. We'll do this via SSH from the host.

Vagrant will provide you the informations about the ssh config to your VM with
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
    > MACHINE     IP            METADATA
      d33fcb2c... 172.17.8.101  -

### Starting containers with fleetctl

To start services or commands inside the VM, you need to _load_ the service
definition (also called units):

    $ fleetctl load services/redis.2.8.service

Now, fleet knows about your service. You can list the services available:

    $ fleetctl list-units
    > UNIT                    MACHINE                         ACTIVE          SUB
      redis.2.8.service       d33fcb2c.../172.17.8.101        inactive        dead

Fleet can tell you the status of a service too:

    $ fleetctl status redis.2.8.service
    > ● redis.4.8.service - Redis 2.8 server
         Loaded: loaded (/run/fleet/units/redis.2.8.service; linked-runtime; vendor preset: disabled)
         Active: inactive (dead)

Of course, fleet lets you start your service (this is the whole point here):

    $ fleetctl start redis.2.8.service
    > Unit redis.2.8.service launched on d33fcb2c.../172.17.8.101

    $ fleetctl status redis.2.8.service
    > ● redis.2.8.service - Redis 2.8 server
         Loaded: loaded (/run/fleet/units/redis.2.8.service; linked-runtime; vendor preset: disabled)
         Active: active (running) since Fri 2015-03-13 10:04:20 UTC; 9s ago
       Main PID: 2673 (docker)
         CGroup: /system.slice/redis.2.8.service
                 └─2673 /usr/bin/docker run --rm --name redis -p 6379:6379 redis:2.8

### Accessing your services

You can always access services using the virtual machine IP:

    $ redis-cli -h 172.17.8.101

To get the address of the machine hosting the redis.2.8.service you can use
this command:

    $ fleetctl list-units | grep redis.2.8.service | awk -F'[[:space:]/]' '{ print $3 }'
    > 172.17.8.101

There is a lot of service discovery techniques out there, for instance:

* [SkyDNS][skydns]
* [Vulcand][vulcand]
* [Consul][consul]

Since we're looking for a development environment, we'll assume that everything
is running on the same machine: `172.17.8.101`.

## Preparing custom containers

With the redis example, we were working on a publicly available container. The
pattern we use to start services with fleet work as long as ou can provide a
docker image.

The following instruction implies that your application already have a
Dockerfile based on a publicly available image.

### Build an image that can run your app

> Until now we were using only the host to run programs in the guest CoreOS
> system. From now we'll use both host (`$`) and the guest (`~`) commands.

We'll [build our Docker image][docker-build] from CoreOS since it already have
docker installed:

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
    Requires=redis.2.8.service
    After=docker.service
    After=redis.2.8.service

    [Service]
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

