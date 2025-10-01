# Shared cluster.id (KRaft)
############################################
resource "random_uuid" "cluster_id" {}

############################################
# Timestamps for tagging + Cluster layout
############################################
locals {
  creation_timestamp_raw = timestamp()
  est_timestamp          = timeadd(local.creation_timestamp_raw, "-4h")
  creation_date_time     = formatdate("YYYY-MM-DD hh:mm:ss", local.est_timestamp)

  # 3 controllers + 1 broker
  instance_configs = {    kraft-1  = { type = "kraft",  node_id = 1, autostart = true }
    kraft-2  = { type = "kraft",  node_id = 2, autostart = true }
    kraft-3  = { type = "kraft",  node_id = 3, autostart = true }
    broker-1 = { type = "broker", node_id = 101 }
    kraft-4  = { type = "kraft",  node_id = 4, autostart = false }
    kraft-5  = { type = "kraft",  node_id = 5, autostart = false }
  }
}

############################################
# Choose subnets for instances (round-robin)
############################################
locals {
  # deterministic ordering of our three public subnets
  cp_kraft_public_subnet_ids = [
    for k in sort(keys(aws_subnet.cp_kraft_test_public)) :
    aws_subnet.cp_kraft_test_public[k].id
  ]

  # Map each instance name to one of the 3 subnets:
  #   kraft-1 -> subnet[0]
  #   kraft-2 -> subnet[1]
  #   everything else (kraft-3, broker-1, etc.) -> subnet[2]
  instance_subnet_map = {
    for name, cfg in local.instance_configs :
    name => local.cp_kraft_public_subnet_ids[
      length(regexall("kraft-1", name)) > 0 ? 0 :
      length(regexall("kraft-2", name)) > 0 ? 1 : 2
    ]
  }
}

############################################
# Compose controller.quorum.bootstrap.servers
############################################
locals {
  controller_listener_port = 9093

  # Pick only the KRaft controller instances by name prefix (kraft-1..N)
  kraft_controller_instances = {
    for name, inst in aws_instance.app_instance :
    name => inst
    if startswith(name, "kraft-")
  }

  # Deterministic order by instance key; extract public DNS hostnames
  kraft_controller_public_dns = [
    for name in sort(keys(local.kraft_controller_instances)) :
    local.kraft_controller_instances[name].public_dns
  ]

  # <public_dns>:9093, <public_dns>:9093, <public_dns>:9093  (comma + space)
  controller_quorum_bootstrap_servers = join(
  ", ",
  [
    for name, inst in local.kraft_controller_instances :
    "${inst.public_dns}:${local.controller_listener_port}"
    if (name == "kraft-1" || name == "kraft-2" || name == "kraft-3")
  ]
)
}

resource "aws_instance" "app_instance" {
  for_each = local.instance_configs

  ami           = var.aws_ami
  instance_type = var.aws_instancesize
  key_name      = var.existing_key_pair_name

  # >>> NEW: place instances in the new cp-kraft-test VPC
  subnet_id                   = local.instance_subnet_map[each.key]
  vpc_security_group_ids      = [aws_security_group.cp_kraft_test_allow_all.id]
  associate_public_ip_address = true

  tags = {
    Name              = each.key
    Role              = each.value.type
    cflt_managed_by   = var.cflt_managed_by
    cflt_managed_id   = var.cflt_managed_id
    cflt_keep_until   = var.cflt_keep_until
    cflt_create_time  = local.creation_date_time
  }
}

############################################
# Build controller.quorum.voters string
#   id@<public_dns>:9093 for each controller
############################################
locals {
  controller_quorum_voters = join(",",
    [
      for name, cfg in local.instance_configs :
      "${cfg.node_id}@${aws_instance.app_instance[name].public_dns}:9093"
      if (cfg.type == "kraft" && (name == "kraft-1" || name == "kraft-2" || name == "kraft-3"))
    ]
  )
}

############################################
# Install Confluent Platform on controllers
############################################
resource "null_resource" "install_confluent_on_kraft" {
  for_each = { for k, v in local.instance_configs : k => v if v.type == "kraft" }

  depends_on = [aws_instance.app_instance]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      # Confluent repo
      "sudo tee /etc/yum.repos.d/confluent.repo >/dev/null <<'EOF'",
      "[Confluent]",
      "name=Confluent repository",
      "baseurl=https://packages.confluent.io/rpm/8.0",
      "gpgcheck=1",
      "gpgkey=https://packages.confluent.io/rpm/8.0/archive.key",
      "enabled=1",
      "EOF",
      "sudo yum clean all -y || true",
      "sudo yum makecache -y || true",
      # Java + Confluent
      "sudo yum install -y java-17-amazon-corretto-devel",
      "sudo yum install -y confluent-platform",
      "echo 'Confluent Platform installed on ${each.key}'"
    ]
  }
}

############################################
# Install Confluent Platform on broker(s)
############################################
resource "null_resource" "install_confluent_on_broker" {
  for_each = { for k, v in local.instance_configs : k => v if v.type == "broker" }

  depends_on = [aws_instance.app_instance]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      # Confluent repo
      "sudo tee /etc/yum.repos.d/confluent.repo >/dev/null <<'EOF'",
      "[Confluent]",
      "name=Confluent repository",
      "baseurl=https://packages.confluent.io/rpm/8.0",
      "gpgcheck=1",
      "gpgkey=https://packages.confluent.io/rpm/8.0/archive.key",
      "enabled=1",
      "EOF",
      "sudo yum clean all -y || true",
      "sudo yum makecache -y || true",
      # Java + Confluent
      "sudo yum install -y java-17-amazon-corretto-devel",
      "sudo yum install -y confluent-platform",
      "echo 'Confluent Platform installed on ${each.key}'"
    ]
  }
}

############################################
# Push controller.properties to KRaft nodes
############################################
resource "null_resource" "push_controller_props" {
  for_each = { for k, v in local.instance_configs : k => v if v.type == "kraft" }

  depends_on = [
    aws_instance.app_instance,
    null_resource.install_confluent_on_kraft
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/controller.properties.tpl", {
      node_id         = each.value.node_id
      quorum_voters   = local.controller_quorum_voters
      advertised_host = aws_instance.app_instance[each.key].public_dns

      # NEW: exactly the CSV you want, with comma + space
      controller_quorum_bootstrap_servers  = local.controller_quorum_bootstrap_servers
    })
    destination = "/tmp/controller.properties"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "sudo mkdir -p /etc/kafka/kraft /var/lib/kafka/kraft-controller-log",
      "sudo mv /tmp/controller.properties /etc/kafka/kraft/controller.properties",
      "sudo chown root:root /etc/kafka/kraft/controller.properties",
      "sudo chmod 0644 /etc/kafka/kraft/controller.properties",
      "echo 'controller.properties installed on ${each.key}'"
    ]
  }
}

############################################
# Push server.properties to broker node(s)
############################################
resource "null_resource" "push_broker_props" {
  for_each = { for k, v in local.instance_configs : k => v if v.type == "broker" }

  depends_on = [
    aws_instance.app_instance,
    null_resource.install_confluent_on_broker
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/server.properties.tpl", {
      node_id         = each.value.node_id
      quorum_voters   = local.controller_quorum_voters
      advertised_host = aws_instance.app_instance[each.key].public_dns

      # NEW: exactly the CSV you want, with comma + space
      controller_quorum_bootstrap_servers  = local.controller_quorum_bootstrap_servers
    })
    destination = "/tmp/server.properties"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "sudo mkdir -p /etc/kafka /var/lib/kafka-logs",
      "sudo mv /tmp/server.properties /etc/kafka/server.properties",
      "sudo chown root:root /etc/kafka/server.properties",
      "sudo chmod 0644 /etc/kafka/server.properties",
      "echo 'server.properties installed on ${each.key}'"
    ]
  }
}

############################################
# Format storage on all nodes (except kraft-4, kraft-5)
############################################

resource "null_resource" "format_kafka_storage" {
  for_each = { for k, v in local.instance_configs : k => v if !(k == "kraft-4" || k == "kraft-5") }

  depends_on = [
    null_resource.push_controller_props,
    null_resource.push_broker_props
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "CONFIG_FILE=$([[ \"${each.value.type}\" == \"kraft\" ]] && echo \"/etc/kafka/kraft/controller.properties\" || echo \"/etc/kafka/server.properties\")",
      "echo \"==> Formatting ${each.key} (${each.value.type}) with CLUSTER_ID=${random_uuid.cluster_id.result}\"",
      "sudo /usr/bin/kafka-storage format -t ${random_uuid.cluster_id.result} -c $CONFIG_FILE",
      "if [[ \"${each.value.type}\" == \"kraft\" ]]; then sudo chown -R cp-kafka:confluent /var/lib/kafka/kraft-controller-log; fi",
      "if [[ \"${each.value.type}\" == \"broker\" ]]; then sudo chown -R cp-kafka:confluent /var/lib/kafka-logs; fi",
      "echo '==> Format complete on ${each.key}'"
    ]
  }
}
############################################
# Systemd: start controllers
############################################
resource "null_resource" "kraft_systemd_service" {
  for_each = { for k, v in local.instance_configs : k => v if (v.type == "kraft" && (k == "kraft-1" || k == "kraft-2" || k == "kraft-3")) }

  depends_on = [null_resource.format_kafka_storage]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "sudo tee /lib/systemd/system/confluent-kraft-controller.service >/dev/null <<'UNIT'",
      "[Unit]",
      "Description=Apache Kafka - KRaft Controller",
      "After=network.target",
      "Requires=network.target",
      "[Service]",
      "Type=simple",
      "ExecStart=/usr/bin/kafka-server-start /etc/kafka/kraft/controller.properties",
      "ExecStop=/usr/bin/kafka-server-stop",
      "Restart=on-failure",
      "User=cp-kafka",
      "Group=confluent",
      "LimitNOFILE=100000",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now confluent-kraft-controller.service",
      "sudo systemctl status confluent-kraft-controller --no-pager || true",
      "echo 'Controller started on ${each.key}'"
    ]
  }
}

############################################
# Upgrade KRaft version to support adding voters
############################################
resource "null_resource" "upgrade_kraft_version" {
  depends_on = [null_resource.kraft_systemd_service]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    # Connect to the first controller to run the cluster-wide command
    host        = aws_instance.app_instance["kraft-1"].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "echo 'Waiting for cluster to stabilize before upgrading features...'",
      "sleep 15",
      "echo 'Upgrading kraft.version to 1 to allow dynamic voter changes.'",
      # Using the public DNS of kraft-1 as the bootstrap
      "/usr/bin/kafka-features --bootstrap-controller ${aws_instance.app_instance["kraft-1"].public_dns}:9093 upgrade --feature kraft.version=1 ",
      "echo 'Feature upgrade command executed.'"
    ]
  }
}

############################################
# Systemd: enable controllers (no-start)
############################################
resource "null_resource" "kraft_systemd_service_enable_only" {
  for_each = { for k, v in local.instance_configs : k => v if (v.type == "kraft" && (k == "kraft-4" || k == "kraft-5")) }

  depends_on = [null_resource.push_controller_props]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "sudo tee /lib/systemd/system/confluent-kraft-controller.service >/dev/null <<'UNIT'",
      "[Unit]",
      "Description=Apache Kafka - KRaft Controller",
      "After=network.target",
      "Requires=network.target",
      "[Service]",
      "Type=simple",
      "ExecStart=/usr/bin/kafka-server-start /etc/kafka/kraft/controller.properties",
      "ExecStop=/usr/bin/kafka-server-stop",
      "Restart=on-failure",
      "User=cp-kafka",
      "Group=confluent",
      "LimitNOFILE=100000",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable confluent-kraft-controller.service",
      "sudo systemctl status confluent-kraft-controller --no-pager || true",
      "echo 'Controller service enabled on ${each.key}'"
    ]
  }
}

############################################
# Systemd: start broker
############################################
resource "null_resource" "broker_systemd_service" {
  for_each = { for k, v in local.instance_configs : k => v if v.type == "broker" }

  depends_on = [
    null_resource.upgrade_kraft_version
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "sudo tee /lib/systemd/system/confluent-server.service >/dev/null <<'UNIT'",
      "[Unit]",
      "Description=Apache Kafka - KRaft Broker",
      "After=network.target",
      "Requires=network.target",
      "[Service]",
      "Type=simple",
      "ExecStart=/usr/bin/kafka-server-start /etc/kafka/server.properties",
      "ExecStop=/usr/bin/kafka-server-stop",
      "Restart=on-failure",
      "User=cp-kafka",
      "Group=confluent",
      "LimitNOFILE=100000",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now confluent-server.service",
      "sudo systemctl status confluent-server --no-pager || true",
      "echo 'Broker started on ${each.key}'"
    ]
  }
}

############################################
# Output public DNS names
############################################
output "instance_public_dns" {
  description = "Public DNS names of all instances"
  value = join("\n", [
    for name in sort(keys(aws_instance.app_instance)) :
    "${name} is ${aws_instance.app_instance[name].public_dns}"
  ])
}