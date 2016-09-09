#!/bin/sh

# Get the list of all deployments in the same namespace. If we ever move this into a controller
# we should use a ConfigMapRefIndex to index the cache so we won't end up requeueing configs that
# are copies.
deployments=($(oc get deployment | awk '{print $1}'))
# Remove NAME header
unset deployments[0]

# Create a copy of configmap/$1. This should be mounted on every deployment that has a
# configmap triggered-by annotation.
oc get configmap $1 -o jsonpath='{.data}' > /tmp/$1.data
cmName=$1-$(md5sum /tmp/$1.data | head -c8)
# TODO: In case the same configmap already exists, we should reuse that
oc create configmap $cmName --from-file /tmp/$1.data

for d in $deployments
do
	triggeredby="$(oc get deployment "${d}" -o go-template='{{index .metadata.annotations "deployment.kubernetes.io/triggered-by"}}')"
	IFS='/' read resource name <<< "$triggeredby"
	if [ "$1" == "$name" ]
	then
		echo "Triggering a new rollout for deployment \""${d}"\" based on "${resource}" \""${name}"\" update..."
		# The controller will need to identify which volume has to be updated. It should
		# go over all volumes in the deployment of $resource type and examine which one
		# of those is the one it needs to update.
		volumeName=$(oc get deployment/$d -o jsonpath='{.spec.template.spec.volumes[0].name}')
		oc set volume deployment/$d --add --overwrite --name=$volumeName -t $resource --configmap-name=$cmName
	fi
done