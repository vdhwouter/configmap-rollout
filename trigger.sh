#!/bin/bash

set -e

# Get the list of all deployments in the same namespace. If we ever move this into a controller
# we should use a ConfigMapRefIndex to index the cache so we won't end up requeueing configs that
# are copies.
deployments=$(oc get deployment -n $1 | awk '{print $1}')


triggered=()
for d in $deployments
do
	if [ "$d" == "NAME" ]
	then
	    continue
	fi

	triggeredby="$(oc get deployment "${d}" -n $1 -o go-template='{{index .metadata.annotations "deployment.kubernetes.io/triggered-by"}}')"
	IFS='/' read resource name <<< "$triggeredby"
	if [ "$2" == "$name" ]
	then
		triggered+=($d)
	fi
done

# If nothing is triggered then exit.
if [ ${#triggered[@]} == 0 ]
then
    exit 0
fi


# Create a copy of configmap/$2. This should be mounted on every deployment that has a
# configmap triggered-by annotation. For now we just copy the first key since there is
# no clean way currently to copy a configmap to another configmap.
# Watch out for the outcome of https://github.com/kubernetes/kubernetes/pull/32367
# The deployment controller should add owner references to the copies of the configmap
# in the replica sets it creates so that garbage collection can be facilitated.
oc get configmap $2 -n $1 -o go-template='{{range $key, $value := .data}}{{$key}}={{$value}}{{end}}' > /tmp/$2.data
cmName=$2-$(md5sum /tmp/$2.data | head -c8)
echo "Creating a copy for configmap \""${2}"\": "${cmName}""
IFS='=' read key value <<< $(cat /tmp/$2.data)
oc create configmap $cmName -n $1 --from-literal=$key=$value


for d in $triggered
do
	echo "Triggering a new rollout for deployment \""${d}"\" based on configmap \""${2}"\" update..."
	# The controller will need to identify which volume has to be updated. It should
	# be given a list of container names[0], look into those containers and identify which
	# one is using the volume we are interested in.	
	#
	# [0] Maybe via another annotation? It seems we need a generic trigger object that would
	# hold an object reference, a slice of container names, and maybe a way to disable the
	# trigger, similar to DeploymentTriggerImageChangeParams in OpenShift.
	# https://github.com/openshift/origin/blob/master/pkg/deploy/api/types.go#L378
	volumeName=$(oc get deployment/$d -n $1 -o jsonpath='{.spec.template.spec.volumes[0].name}')
	oc set volume deployment/$d -n $1 --add --overwrite --name=$volumeName -t configmap --configmap-name=$cmName
done