### Config map rollout

A Kubernetes custom controller for facilitating ConfigMap rollouts. This is a proof-of-concept for https://github.com/kubernetes/kubernetes/pull/31701. The following example assumes you are running a Kubernetes cluster locally via `hack/local-cluster-up.sh`.

`observer.yaml` includes:

1) The observer Deployment that is running [oc observe](https://github.com/openshift/origin/blob/master/images/observe/Dockerfile) inside a Pod (see https://github.com/kubernetes/kubernetes/issues/5164 for background) and uses a hostPort in order for the command to be able to contact the api server.

2) The script that runs every time a config map is created or updated (trigger.sh) mounted in the Deployment as a ConfigMap.

3) A kubeconfig that works ootb with `local-cluster-up.sh` mounted in the Deployment as a ConfigMap. If you need a different kubeconfig, delete the existing one and add yours.

Create the custom controller that will update Deployments on ConfigMap updates:
```sh
$ kubectl create -f https://raw.githubusercontent.com/kargakis/configmap-rollout/master/observer.yaml -n kube-system
configmap "kubeconfig" created
configmap "trigger" created
deployment "observer" created
```


### Example

In the current namespace:

```sh
$ kubectl create -f https://raw.githubusercontent.com/kargakis/configmap-rollout/master/example/example.yaml
configmap "alpine" created
deployment "alpine" created
```

At this point, you should have one pod and config map:
```sh
$ kubectl get po
NAME                        READY     STATUS    RESTARTS   AGE
alpine-928338976-59vhm      1/1       Running   0          17s
```
```sh
$ kubectl get cm
NAME         DATA      AGE
alpine       1         19s
```

You should be able to inspect our custom configuration in the alpine pod with the following command:
```sh
$ kubectl exec alpine-928338976-59vhm -i -t -- cat /etc/my-key
Hello there!
```

Currently, there is no relation between the two resources other than the one (ConfigMap) being mounted in the other (Deployment). All you need in order to enable automatic rollouts in case of config map updates is to add a `deployment.kubernetes.io/triggered-by: configmap/alpine` annotation in the Deployment. This should be done by `kubectl set trigger` which is proposed in https://github.com/kubernetes/kubernetes/pull/31701 - for now we will add it via `kubectl annotate`:
```sh
$ kubectl annotate deploy/alpine deployment.kubernetes.io/triggered-by=configmap/alpine
deployment "alpine" annotated
```

Now update the alpine config map and change the message that will be echoed:
```sh
$ kubectl edit cm/alpine
configmap "alpine" edited
$ kubectl get cm/alpine -o jsonpath='{.data}'
map[my-key:Updated!]
```

You should see a new rollout underway:
```sh
$ kubectl get po
NAME                        READY     STATUS              RESTARTS   AGE
alpine-1077172096-zg3h2     0/1       ContainerCreating   0          3s
alpine-928338976-59vhm      1/1       Terminating         0          4m
```

Inspect our configuration inside the new pod:
```sh
$ kubectl exec alpine-1077172096-zg3h2 -i -t -- cat /etc/my-key
Updated!
```