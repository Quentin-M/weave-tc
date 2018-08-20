## weave-tc

![Docker Pulls](https://img.shields.io/docker/pulls/qmachu/weave-tc.svg)

weave-tc is a straightforward workaround for the conntrack race inducing high DNS latency on Kubernetes. 
Are you affected will you ask? Most likely, without your knowledge, just like everyone else. 

With merely 10 lines of bash, weave-tc represents the simplest solution available to cope with the multiple kernel race
conditions that affect DNS dramatically on Kubernetes, and work across the board regardless of your Kubernetes provider
or provisioning tool. Other suggested solutions involve running a DNS server on every nodes (and configuring Kubelet
for it), patching musl or setting glibc options on every single container running on Kubernetes.

For more details about the race condition itself, take a look to the technical references below.
To learn about about that workaround specifically, read [weave-tc.sh](weave-tc.sh) directly.

### Technical references

- [5 – 15s DNS lookups on Kubernetes?](https://blog.quentin-machu.fr/2018/06/24/5-15s-dns-lookups-on-kubernetes/)
- [Racy conntrack and DNS lookup timeouts](https://www.weave.works/blog/racy-conntrack-and-dns-lookup-timeouts)
- [A reason for unexplained connection timeouts on Kubernetes/Docker](https://tech.xing.com/a-reason-for-unexplained-connection-timeouts-on-kubernetes-docker-abd041cf7e02)

### Issues

- [DNS lookup timeouts due to races in conntrack](https://github.com/weaveworks/weave/issues/3287)
- [DNS latency of 5s when uses iptables forward in pods network traffic](https://github.com/kubernetes/kubernetes/issues/62628)
- [DNS intermittent delays of 5s](https://github.com/kubernetes/kubernetes/issues/56903)
- And many, many more...

### How to run it?

Simply add the following snippet to any DaemonSet you run. Your network overlay's one is probably
the best suited.

```
        - name: weave-tc
          image: 'qmachu/weave-tc:bd94b89'
          securityContext:
            privileged: true
          volumeMounts:
            - name: xtables-lock
              mountPath: /run/xtables.lock
            - name: lib-tc
              mountPath: /lib/tc
```

If your DNS server listens on a different port, set the `DNSMASQ_PORT` environment variable.

If your network overlay is not weave, set the `NET_OVERLAY_IF` environment variable to be the appropriate network
interface.

Your operating system must have the `iproute2` package installed, which is generally the case by default.
Depending on the package, the appropriate mount may not be `/lib/tc`, the `tc` binary as well as the `pareto.dist` file
are required.