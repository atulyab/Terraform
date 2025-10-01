confluent.license=eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJjb250cm9sLWNlbnRlciIsIm5iNCI6IjE2ODc1NDI2NzQiLCJtb25pdG9yaW5nIjp0cnVlLCJsaWNlbnNlVHlwZSI6IkVudGVycHJpc2UiLCJpc3MiOiJDb25mbHVlbnQiLCJpYXQiOjE2ODc1MDM2MDAsImV4cCI6MTc1MzE2NzYwMCwiYXVkIjoiMDA2NFUwMDAwMHJXQ054UUFPIn0=.GWS0UtnoLajxaULN5P5-JjqZq-b7szam9HqQ5d4oWmz1KcQU9wev5ir6XFxCUK9zds9XjYaPt8Om7BnYd-W1b-RxKareziFiLD_s_wD1wifrOUMDQId7Y9odXXgwhEDRUwMV12x57sGxsB2rOZ3U9ZGTrRNxNIMHwz-6agwNWvQYnMlwMDW2iJONd-NxEkvEIjyjA5-G6n0w34RSxLl1_23jG50Qlq4H1_FtpX3Y7AlKwR-sYNCGW5k9vg6YCyWZIyjuM3-WzF3_x5PPGmPsFOARS3f2YPp4t2y2X_wkPTyV-raffrbn18rlbe__LqUncqomcUfBBlU-LRiwE76qDQ

process.roles=broker
node.id=${node_id}

controller.quorum.voters=${quorum_voters}

controller.quorum.bootstrap.servers=${controller_quorum_bootstrap_servers}

controller.listener.names=CONTROLLER
inter.broker.listener.name=BROKER   

# Bind on all interfaces, advertise the hostname
listeners=BROKER://0.0.0.0:9092
advertised.listeners=BROKER://${advertised_host}:9092
confluent.http.server.listeners=http://${advertised_host}:8090

listener.security.protocol.map=BROKER:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.listener.name=BROKER
log.dirs=/var/lib/kafka-logs/

default.replication.factor=1
offsets.topic.replication.factor=1
confluent.metrics.reporter.topic.replicas=1
confluent.license.topic.replication.factor=1
confluent.metadata.topic.replication.factor=1
confluent.security.event.logger.exporter.kafka.topic.replicas=1
confluent.balancer.enable=false
transaction.state.log.min.isr=1
group.initial.rebalance.delay.ms=0
transaction.state.log.replication.factor=1
confluent.telemetry.enabled=false
#confluent.cluster.link.enable=true
#password.encoder.secret=encoder-secret
#confluent.http.server.listeners=

