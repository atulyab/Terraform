# Generate a single, random UUID for the entire Kafka cluster
resource "random_uuid" "cluster_id" {}

locals {
  creation_timestamp_raw = timestamp()
  est_timestamp          = timeadd(local.creation_timestamp_raw, "-4h")
  creation_date_time     = formatdate("YYYY-MM-DD hh:mm:ss", local.est_timestamp)

  # Define a map for each instance, allowing for unique properties if needed
  instance_configs = {
    "kafka-1" = {
      type               = "kafka"
      public_dns_kafka_var = "brk_host"
      brk_port           = "9092"
      public_dns_kraft_var = "kraft_host"
    },
    "kraft-1" = {
      type               = "kraft"
      public_dns_kraft_var = "kraft_host"
      kraft_port         = "9097"
    }
  }
}

resource "aws_instance" "app_instance" {
  for_each      = local.instance_configs
  ami           = var.aws_ami
  instance_type = var.aws_instancesize
  key_name      = var.existing_key_pair_name

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem")
    host        = self.public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/kafka",
      "sudo chown ec2-user:ec2-user /etc/kafka",
      "sudo mkdir -p /etc/yum.repos.d",
    ]
  }

  provisioner "file" {
    source      = "server.properties"
    destination = "/etc/kafka/server.properties"
  }

  provisioner "file" {
    source      = "controller.properties"
    destination = "/etc/kafka/controller.properties"
  }

  provisioner "remote-exec" {
    inline = [
      "TARGET_FILE=/etc/yum.repos.d/confluent.repo",

      "cat <<EOT_BLOCK1 | sudo tee -a $${TARGET_FILE}",
      "[Confluent]",
      "name=Confluent repository",
      "baseurl=https://packages.confluent.io/rpm/7.9",
      "gpgcheck=1",
      "gpgkey=https://packages.confluent.io/rpm/7.9/archive.key",
      "enabled=1",
      "EOT_BLOCK1",

      "echo 'Cleaning yum cache...'",
      "sudo yum clean all",
      "echo 'Installing Confluent Platform...'",
      "sudo yum install -y java-1.8.0-amazon-corretto-devel",
      "sudo yum install -y confluent-platform",
    ]
  }

  tags = {
    Name              = each.key
    cflt_managed_by   = "user"
    cflt_managed_id   = "abhimarasetty"
    cflt_service      = "Cigna"
    cflt_environment  = "dev"
    cflt_keep_until   = "2025-08-01"
    cflt_create_time  = local.creation_date_time
  }
}

resource "null_resource" "post_install_config" {
  for_each = local.instance_configs

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem")
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = concat(
      ["echo 'Running post-install configuration for ${each.key}...'"],

      each.key == "kraft-1" ? [
        "echo 'Applying sed modifications to controller.properties for kraft-1...'",
        "sudo sed -i 's|${local.instance_configs["kraft-1"].public_dns_kraft_var}|${aws_instance.app_instance["kraft-1"].public_dns}|g' /etc/kafka/controller.properties",
        "sudo cat /etc/kafka/controller.properties",
      ] : [],

      each.key == "kafka-1" ? [
        "echo 'Applying sed modifications to server.properties for kafka-1...'",
        "sudo sed -i 's|${local.instance_configs["kafka-1"].public_dns_kafka_var}|${aws_instance.app_instance["kafka-1"].public_dns}|g' /etc/kafka/server.properties",
        "sudo sed -i 's|${local.instance_configs["kafka-1"].public_dns_kraft_var}|${aws_instance.app_instance["kraft-1"].public_dns}|g' /etc/kafka/server.properties",
        "sudo cat /etc/kafka/server.properties"
      ] : []
    )
  }
}

resource "null_resource" "format_kafka_storage" {
  # This resource runs the kafka-storage.sh format command on both instances
  for_each = local.instance_configs

  # Ensure the post-install configuration is complete before formatting storage
  depends_on = [
    null_resource.post_install_config
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem")
    host        = aws_instance.app_instance[each.key].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Formatting Kafka storage on ${each.key} with CLUSTER_ID: ${random_uuid.cluster_id.result} ...'",
      
      # Use a conditional to select the correct properties file for each instance
      each.key == "kraft-1" ? 
        "sudo /usr/bin/kafka-storage format -t ${random_uuid.cluster_id.result} -c /etc/kafka/controller.properties --ignore-formatted --standalone" :
        "sudo /usr/bin/kafka-storage format -t ${random_uuid.cluster_id.result} -c /etc/kafka/server.properties"
    ]
  }
}
