### Config map rollout

Automatically trigger new rollouts for your Deployment in every ConfigMap update!
PoC for https://github.com/kubernetes/kubernetes/pull/31701.

Create the custom controller that will update Deployments on ConfigMap updates:
```sh
$ kubectl create -f observer.yaml -n kube-system
configmap "trigger" created
deployment "observer" created
```

`observer.yaml` includes:
* The script that runs every time a ConfigMap is created or updated (trigger.sh) mounted in the Deployment.
* A Deployment that is running the controller loop responsible for updating Deployments every time something
changes in a ConfigMap (uses [oc observe](https://github.com/openshift/origin/blob/master/images/observe/Dockerfile) under the covers).


### Example

```sh
$ kubectl create -f /example
configmap "alpine" created
deployment "alpine" created
```

At this point, you should have one Pod running and a ConfigMap:
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

You should be able to inspect our custom configuration in the alpine Pod with the following command:
```sh
$ kubectl exec alpine-928338976-59vhm -i -t -- cat /etc/my-key
Hello there!
```

To enable automatic rollouts of Deployment "alpine" in case ConfigMap "alpine" is updated, all you need
to do is add a `deployment.kubernetes.io/triggered-by: configmap/alpine` annotation in your Deployment:
```sh
$ kubectl annotate deploy/alpine deployment.kubernetes.io/triggered-by=configmap/alpine
deployment "alpine" annotated
```

Note the structure of the annotation - it needs to be `{controller}.kubernetes.io/triggered-by: {conf}/{name}`
where `{controller}` is the type of controller you are using (only Deployments supported for now), `{conf}` is
the type of configuration resource (only ConfigMaps supported for now), and `{name}` is the name of the
configuration resource for which you want to trigger on update. Also note that the resource with the provided
name needs to be mounted in your controller's PodTemplate in order for this to work.

Now update the alpine ConfigMap and change the message that will be echoed:
```sh
$ kubectl edit cm/alpine
configmap "alpine" edited
$ kubectl get cm/alpine -o jsonpath='{.data}'
map[my-key:Bye there!]
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
Bye there!
```