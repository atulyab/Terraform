

Quorum status
kafka-metadata-quorum --bootstrap-controller ec2-3-17-110-97.us-east-2.compute.amazonaws.com:9093 describe --replication
kafka-metadata-quorum --bootstrap-controller ec2-3-17-110-97.us-east-2.compute.amazonaws.com:9093 describe --status

Get Cluster ID
sudo cat  /var/lib/kafka/kraft-controller-log/meta.properties

Update the controller properties file of kraft-4
sudo vi /etc/kafka/kraft/controller.properties
add --> 4@

Format storage
Update the controller.properties and add the new node to the controller.quorum.voters config. 
sudo /usr/bin/kafka-storage format -t ee4fed89-c362-4e63-8bb6-53ee159c2635 -c /etc/kafka/kraft/controller.properties
sudo chown -R cp-kafka:confluent /var/lib/kafka/kraft-controller-log

Start kraft-4 controller
sudo systemctl start confluent-kraft-controller
sudo journalctl -f -u confluent-kraft-controller

Check & Upgrade kraft version to 1 on kraft-1
kafka-features --bootstrap-controller ec2-3-17-110-97.us-east-2.compute.amazonaws.com:9093 describe
kafka-features --bootstrap-controller ec2-18-226-88-121.us-east-2.compute.amazonaws.com:9093 upgrade --feature kraft.version=1

Add controller (on kraft-4)
sudo kafka-metadata-quorum --bootstrap-controller ec2-3-17-110-97.us-east-2.compute.amazonaws.com:9093 --command-config /etc/kafka/kraft/controller.properties add-controller
[controller.properties should the properties file of the controller that is being added to the quorum]

Remove controller
kafka-metadata-quorum  --bootstrap-controller ec2-3-17-110-97.us-east-2.compute.amazonaws.com:9093  remove-controller  --controller-id 3 --controller-directory-id 3TC54JNoijLMvTxQRhJS8Q

Stop kraft-2 controller
sudo systemctl stop confluent-kraft-controller


while true; do MSG="Test message at $(date +"%Y-%m-%d %H:%M:%S")"; echo "$MSG" | kafka-console-producer --bootstrap-server ec2-18-116-163-37.us-east-2.compute.amazonaws.com:9092 --topic test-data-topic > /dev/null; echo "Sent: $MSG"; sleep 2; done

[ec2-user@ip-10-90-4-7 ~]$ kafka-features --bootstrap-controller ec2-3-15-229-214.us-east-2.compute.amazonaws.com:9093 describe
Feature: kraft.version	SupportedMinVersion: 0	SupportedMaxVersion: 1	FinalizedVersionLevel: 1	Epoch: 5