### Config map rollout

A Kubernetes custom controller for facilitating ConfigMap rollouts. This is a proof-of-concept for https://github.com/kubernetes/kubernetes/pull/31701.

Supposing you are running a local Kubernetes cluster via `hack/local-cluster-up.sh`, clone this repository under /tmp:
```sh
$ git clone https://github.com/kargakis/configmap-rollout /tmp/configmap-rollout
$ cd /tmp/configmap-rollout
```

`observer.yaml` includes:

1) The observer Deployment that is running [oc observe](https://github.com/openshift/origin/blob/master/images/observe/Dockerfile) inside a Pod (see https://github.com/kubernetes/kubernetes/issues/5164 for background) and uses a hostPort in order for the command to be able to contact the api server.

2) The script that runs every time a config map is created or updated (trigger.sh) mounted in the Deployment as a ConfigMap.

3) A kubeconfig that works ootb with `local-cluster-up.sh` mounted in the Deployment as a ConfigMap. If you need a different kubeconfig, delete the existing one and add yours.

Create the custom controller that will update Deployments on ConfigMap updates:
```sh
$ kubectl create -f observer.yaml
configmap "kubeconfig" created
configmap "trigger" created
deployment "observer" created
```


### Example

Create a `demo` namespace and follow the example:

```sh
$ kubectl create -f example/example.yaml -n demo
configmap "alpine" created
deployment "alpine" created
```

At this point, you should have the following pods and config maps in the `demo` namespace:
```sh
$ kubectl get po -n demo
NAME                        READY     STATUS    RESTARTS   AGE
alpine-928338976-59vhm      1/1       Running   0          17s
```
```sh
$ kubectl get cm -n demo
NAME         DATA      AGE
alpine       1         19s
```

You should be able to inspect our custom configuration in the alpine pod with the following command:
```sh
$ kubectl exec -n demo alpine-928338976-59vhm -i -t -- cat /etc/my-key
Hello there!
```

Currently, there is no relation between the two resources other than the one (ConfigMap) being mounted in the other (Deployment). All you need in order to enable automatic rollouts in case of config map updates is to add a `deployment.kubernetes.io/triggered-by: configmap/alpine` annotation in the Deployment. This should be done by `kubectl set trigger` which is proposed in https://github.com/kubernetes/kubernetes/pull/31701 - for now we will add it via `kubectl annotate`:
```sh
$ kubectl annotate deploy/alpine deployment.kubernetes.io/triggered-by=configmap/alpine -n demo
deployment "alpine" annotated
```

Now update the alpine config map and change the message that will be echoed:
```sh
$ kubectl edit cm/alpine -n demo
configmap "alpine" edited
$ kubectl get cm/alpine -o jsonpath='{.data}' -n demo
map[my-key:Updated!]
```

You should see a new rollout underway:
```sh
$ kubectl get po -n demo
NAME                        READY     STATUS              RESTARTS   AGE
alpine-1077172096-zg3h2     0/1       ContainerCreating   0          3s
alpine-928338976-59vhm      1/1       Terminating         0          4m
```

Inspect our configuration inside the new pod:
```sh
$ kubectl exec -n demo alpine-1077172096-zg3h2 -i -t -- cat /etc/my-key
Updated!
```