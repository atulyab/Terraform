locals {
  creation_timestamp_raw = timestamp()
  est_timestamp          = timeadd(local.creation_timestamp_raw, "-4h")
  creation_date_time     = formatdate("YYYY-MM-DD hh:mm:ss", local.est_timestamp)

  # Define a map for each instance, allowing for unique properties if needed
  instance_configs = {
    "kafka-1"    = { type = "kafka", public_dns_kafka_var = "brk_host", brk_port = "9092", public_dns_zk_var = "zk_hostname", zk_port = "2181" },
    "zookeeper-1" = { type = "zookeeper" }
  }
}

resource "aws_instance" "app_instance" {
  for_each      = local.instance_configs # Iterate over the instance_configs map
  ami           = var.aws_ami
  instance_type = var.aws_instancesize
  key_name      = var.existing_key_pair_name
  subnet_id = "subnet-0e7f56f7680194d8e"
  vpc_security_group_ids = ["sg-0b994f587c645ed6b"]
  #user_data = local.user_data_script

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem") # Path to your private key
    host        = self.public_ip
    timeout     = "5m" # Increase if needed for slow connections
  }

  # --- Provisioner 1: remote-exec for initial setup & directory creation ---
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/kafka",
      "sudo chown ec2-user:ec2-user /etc/kafka",
      "sudo mkdir -p /etc/yum.repos.d",
    ]
  }

  # --- Provisioner 2: file to copy properties files ---
  # Note: You might want to have different property files for Kafka vs Zookeeper
  # For simplicity, this example copies both to both instances.
  # In a real setup, you'd likely conditionally copy or have distinct configurations.
  provisioner "file" {
    source      = "server.properties"
    destination = "/etc/kafka/server.properties"
  }

  provisioner "file" {
    source      = "zookeeper.properties"
    destination = "/etc/kafka/zookeeper.properties"
  }

  # --- Provisioner 3: remote-exec for Confluent repo & software installation ---
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

      # Use each.value.public_dns_var and each.value.port for dynamic substitution
      #"sudo sed -i 's|${each.value.public_dns_var}:${each.value.port}|${aws_instance.app_instance[each.key].public_dns}:${each.value.port}|g' /etc/kafka/server.properties"
    ]
  }

  tags = {
    Name              = each.key # Set the Name tag to "kafka-1" or "zookeeper-1"
    cflt_managed_by   = "user"
    cflt_managed_id   = "abhimarasetty"
    cflt_service      = "Cigna"
    cflt_environment  = "dev"
    cflt_keep_until   = "2025-08-01"
    cflt_create_time  = local.creation_date_time
  }
}

resource "null_resource" "post_install_config" {
  for_each = local.instance_configs # Iterate over the same map

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem")
    host        = aws_instance.app_instance[each.key].public_ip # Reference the specific instance by its key
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = concat(
      # Always include at least one command to avoid empty scripts error
      ["echo 'Running post-install configuration for ${each.key}...'"],

      # Conditional sed commands
      each.key == "kafka-1" ? [
        "echo 'Applying sed modifications to server.properties for kafka-1...'",
        "sudo sed -i 's|${local.instance_configs["kafka-1"].public_dns_kafka_var}:${local.instance_configs["kafka-1"].brk_port}|${aws_instance.app_instance["kafka-1"].public_dns}:${local.instance_configs["kafka-1"].brk_port}|g' /etc/kafka/server.properties",

        "sudo sed -i 's|${local.instance_configs["kafka-1"].public_dns_zk_var}:${local.instance_configs["kafka-1"].zk_port}|${aws_instance.app_instance["zookeeper-1"].public_dns}:${local.instance_configs["kafka-1"].zk_port}|g' /etc/kafka/server.properties",
        "sudo cat /etc/kafka/server.properties"
      ] : [] # If not kafka-1, provide an empty list for this part
    )
  }
}

resource "null_resource" "start_zookeeper" {
  # This resource specifically targets the zookeeper instance
  triggers = {
    # This trigger ensures the resource runs when the zookeeper instance is ready
    instance_id = aws_instance.app_instance["zookeeper-1"].id
    public_ip   = aws_instance.app_instance["zookeeper-1"].public_ip
    # Also depend on the post-install config for zookeeper being complete
    post_config_completed = null_resource.post_install_config["zookeeper-1"].id
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem")
    host        = aws_instance.app_instance["zookeeper-1"].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Starting Confluent Zookeeper on zookeeper-1...'",
      "sudo systemctl start confluent-zookeeper",
      "sudo systemctl enable confluent-zookeeper" # Enable on boot
    ]
  }
}

resource "null_resource" "start_kafka" {
  # This resource specifically targets the kafka instance
  triggers = {
    # This trigger ensures the resource runs when the kafka instance is ready
    instance_id = aws_instance.app_instance["kafka-1"].id
    public_ip   = aws_instance.app_instance["kafka-1"].public_ip
    # Also depend on the post-install config for kafka being complete
    post_config_completed = null_resource.post_install_config["kafka-1"].id
  }
  

  # Explicitly depend on Zookeeper starting first
  depends_on = [
    null_resource.start_zookeeper
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/Users/atulyabhimarasetty/aws/atulyab_ohio.pem")
    host        = aws_instance.app_instance["kafka-1"].public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Starting Confluent Server on kafka-1...'",
      "sudo systemctl start confluent-server",
      "sudo systemctl enable confluent-server" # Enable on boot
    ]
  }

  provisioner "file" {
    source      = "client-jaas.properties"
    destination = "/home/ec2-user/client-jaas.properties"
  }
}
