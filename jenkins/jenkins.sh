#!/bin/bash 

SPARKMASTER=sparkmaster

cat << EOF > perfjob.json
apiVersion: extensions/v1beta1
kind: Job
metadata:
  name: sparkperfjobname
spec:
  activeDeadlineSeconds: 600
  selector:
    matchLabels:
      app: sparkperfjob
  parallelism: 1
  completions: 1
  template:
    metadata:
      name: sparkperfjob
      labels:
        app: sparkperfjob
    spec:
      containers:
      - name: sparkperfjob
        image: jayunit100/spark-perf
        env:
        - name: "SPARK_MASTER_URL"
          value: "spark://$SPARKMASTER:7077"
        - name: "HOME"
          value: "/opt"
        command: ["/bin/sh","-c","SPARK_USER=jayunit100 /opt/driver-script.sh || find results/ -exec cat {} +"]
      restartPolicy: Never
    imagePullPolicy: Always
    restartPolicy: Never
EOF

oc delete project sparkperftest || echo "sparkperftest project deletion failed"
echo "Waiting for ns delete . . . "
until oc new-project sparkperftest ; do
	echo "failed creating new project... trying again"
	sleep 1
done

# Todo use xpass-spark production yaml
wget https://gist.githubusercontent.com/jayunit100/3fad23e42a22e473fff7a45947bd3102/raw/a05491639887cc716c8ede41f603d45c786bf5ee/xpass-spark -O xpass-spark

# create and process the template
oc create -f xpass-spark

IMAGE="ce-registry.usersys.redhat.com/apache-spark-2/spark20-hadoop27-openshift:2.0"

oc process -v SPARK_IMAGE=$IMAGE -v MASTER_NAME=$SPARKMASTER spark | oc create -f -

# wait till master running...
until oc get pods | grep master | grep -v deploy | grep Running ; do
	oc get pods
	sleep 2
done

echo "master was found :)"

# Now run the job 
oc create -f perfjob.json
jobpod=`oc get pods | grep sparkperfjob | cut -d' ' -f 1`

# tail the logs until the perf test is done... 

until oc logs -f $jobpod ; do 
	echo "trying again..."
	sleep 1
done

# Try to find error
oc get pods | grep $jobpod | grep -i ERROR

if [ $? -eq 0 ]; then
	echo "perf test failed, see logs above"
	exit 1
fi

echo "per test succeeded `oc get pods | grep $jobpod`. "


