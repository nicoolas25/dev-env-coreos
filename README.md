# CoreOS and fleet to build a dev environment

## Create a CoreOS guest

You'll need to download and install [Vagrant][vagrant] before everything else.

Create a cluster of 3 virtual machines with [CoreOS][core-os] with the following
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
      55957c73...     172.17.8.103    purpose=services
      7741dbbb...     172.17.8.101    purpose=app
      ffca3354...     172.17.8.102    purpose=services

### Starting containers with fleetctl

To start services or commands inside the cluster, you need to _submit_
an _instance_ of the service definition (also called units):

    $ fleetctl submit services/redis@1.service

Here the instance name is `1`. Once the service file is submited, it is visible
from your fleet:

    $ fleetctl list-unit-files
    > UNIT                    HASH    DSTATE          STATE           TARGET
      redis@1.service         1226b31 inactive        inactive        -
      registrator.service     14bd412 launched        -               -
      skydns.service          f7b1505 launched        -               -

Now, fleet knows about your redis service. It is possible to start this _instance_
of our redis service:

    $ fleetctl start redis@1.service
    > Unit redis@1.service launched on 55957c73.../172.17.8.103

Now, you can list the units and see the service:

    $ fleetctl list-units
    > UNIT                    MACHINE                         ACTIVE  SUB
      redis@1.service         55957c73.../172.17.8.103        active  running
      registrator.service     55957c73.../172.17.8.103        active  running
      registrator.service     7741dbbb.../172.17.8.101        active  running
      registrator.service     ffca3354.../172.17.8.102        active  running
      skydns.service          55957c73.../172.17.8.103        active  running
      skydns.service          7741dbbb.../172.17.8.101        active  running
      skydns.service          ffca3354.../172.17.8.102        active  running

There is services that are already running on each machine: `skydns` and
`registrator`. We'll talk about them later.

Fleet can tell you the status of a service, and stop them too:

    $ fleetctl status redis@1.service
    > ● redis@1.service - A Redis 2.8 server
         Loaded: loaded (/run/fleet/units/redis@1.service; linked-runtime; vendor preset: disabled)
            Active: active (running) since Sun 2015-03-29 15:51:19 UTC; 1min 2s ago
              Process: 1730 ExecStartPre=/usr/bin/docker rm redis (code=exited, status=1/FAILURE)
       Main PID: 1737 (docker)
         CGroup: /system.slice/system-redis.slice/redis@1.service
                    └─1737 /usr/bin/docker run --rm --name redis -p 6379:6379 -e SERVICE_ID=redis-1 redis:2.8

Since it is the first time we're running Redis, docker will start by pulling
the image from the repository. Your redis service will be available after that
download. Try using `fleetctl journal -f redis@1.service` see when your server
is ready. Redis will be ready, you'll see the usual messages of Redis.

### Accessing your services directly

You can always access services using the virtual machine IP:

    $ redis-cli -h 172.17.8.103

To get the address of the machine hosting the redis.2.8.service you can use
this command:

    $ fleetctl list-units | grep redis@1.service | awk -F'[[:space:]/]' '{ print $4 }'
    > 172.17.8.103

### Accessing your services using Skydns

As we've seen before, there is `skydns` and `registrator` that are already
configured and running on each virtual machine. SkyDNS provides a DNS server
based on `etcd` and Registrator register an entry in SkyDNS everytime a docker
container is launched.

Any machine in the cluster is hosting a SkyDNS conainer. Any machine can be used
as a DNS server. SkyDNS is configured to handle the `webapp.dev` domain by
itself then use Google's DNS.

Then I can `dig`, from the host, for the services I want using Skydns:

    $ dig @172.17.8.101 redis.webapp.dev

    > ; <<>> DiG 9.9.5-3ubuntu0.2-Ubuntu <<>> redis.webapp.dev
      ;; global options: +cmd
      ;; Got answer:
      ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 59737
      ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

      ;; QUESTION SECTION:
      ;redis.webapp.dev.              IN      A

      ;; ANSWER SECTION:
      redis.webapp.dev.       3600    IN      A       172.17.8.103

      ;; Query time: 2 msec
      ;; SERVER: 172.17.8.101#53(172.17.8.101)
      ;; WHEN: Sat Mar 14 14:09:26 CET 2015
      ;; MSG SIZE  rcvd: 50

We can see that the DNS used is SkyDNS from `172.17.8.101`. The format of the
SkyDNS host given a docker's container is:

    <service's ID>.<container's name>.<skydns's domain>
    redis-1       .redis             .webapp.dev

The service's ID is given via the `SERVICE_ID` environment variable of the
container. The service's ID part is optional: it is possible to call either
`redis.webapp.dev` or `redis-1.redis.webapp.dev`.

The service's ID is the container's name followed by the instance name in the
examples, see the services file for more information.

You can use those DNS from your host machine by editing your `/etc/resolv.conf`
file.

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

    $ vagrant ssh core-01
    ~ cd /code/webapp
    ~ sudo docker build -t nicoolas25/rack-webapp .

This command could take a while (depending on your connection). It'll build the
image described in the Dockerfile as `nicoolas25/rack-webapp`. Here is the
content of the Dockerfile:

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

    ~ docker images | grep rack-webapp
    > nicoolas25/rack-webapp        latest              f4512accbbbd        About an hour ago   776.4 MB

If you update your Dockerfile, you will need to repeat those steps to update the
docker image.

### Share your image

If you want to run your webapp on a different machine, you'll need to redo make
the image available to docker one way or another. We'll be using [quay.io][quay]
as a docker's images repository.

Create an account on Quay then [create a new repository][quay-new]. Once you
have its URL, you can do the following:

    ~ docker login quay.io
    > Username: myusername
      Password: mypassword
      Email: myemail@example.com
      Login Succeeded
    ~ docker tag f4512accbbbd quay.io/nicoolas25/rack-webapp
    ~ docker push quay.io/nicoolas25/rack-webapp
    > The push refers to a repository [quay.io/nicoolas25/rack-webapp] (len: 1)
      Sending image list
          Pushing repository quay.io/nicoolas25/rack-webapp (1 tags)
      ...
      Pushing tag for rev [f4512accbbbd] on {https://quay.io/v1/repositories/nicoolas25/rack-webapp/tags/latest}

### Create a service from that image

Now that we've got an image, we have to create a fleet service to manage that
service. There is an example of such a service in `./services/webapp@.service`:

    [Unit]
    Description=A web application example
    Requires=docker.service
    After=docker.service

    [Service]
    ExecStartPre=-/usr/bin/docker rm webapp
    ExecStart=/usr/bin/docker run --rm --name webapp -p 3000:3000 -v /code/webapp:/app -e SERVICE_NAME=app -e SERVICE_ID=%i quay.io/nicoolas25/rack-webapp:latest
    ExecStop=/usr/bin/docker stop webapp

    [X-Fleet]
    MachineMetadata=purpose=app
    Conflicts=webapp@*.service

In this example, the `/code/webapp` is mounted in the container as `/app` in
order to share the application files.

Now you can, from the host, load and start the webapp service:

    $ fleetctl submit services/webapp@test.service
    $ fleetctl start webapp@test.service
    > Unit webapp@test.service launched on 4509883a.../172.17.8.101

See that we used another instance name here: `test`.

Once the service is started, you can access it from your host at:
`http://app.webapp.dev:3000/` or `http://172.17.8.101:3000/` depending on
if you've update your host's network configuration to use SkyDNS or not.

## Controlling the target machines

We've set 3 machines and we've lauched redis in one of these machine. Fleet is
managing your services and hide the cluster from you. To manage where thing
should and should not run, there is a `X-Fleet` section in the service file we
use. Take for instance the `redis@.service`:

    [X-Fleet]
    MachineMetadata=purpose=services
    Conflicts=redis@*.service

This is telling Fleet to put this service only on machines that have this
metadata: `purpose=services`. It is also telling Fleet to not run this service
on another machine that is already running it.

This kind of control is useful to have a coherent repartition of the services
over the cluster. If you setup a backup server for a given service, you should
avoid to put it on the same physical machine, or even in the same datacenter.

You can have more informations about the [fleet unit files][fleet-unit] on the
official website.

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
[fleet-unit]: https://coreos.com/docs/launching-containers/launching/fleet-unit-files/
[quay]: http://quary.io/
[quay-new]: https://quay.io/new/
[skydns]: https://github.com/skynetservices/skydns
[vagrant]: https://www.vagrantup.com/
[vulcand]: https://vulcand.io/
