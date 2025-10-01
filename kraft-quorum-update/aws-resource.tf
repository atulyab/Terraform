############################################
# Networking for cp-kraft-test
############################################

# 1) VPC that allows public IPs (via public subnets + IGW route)
resource "aws_vpc" "cp_kraft_test" {
  cidr_block           = "10.90.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cp-kraft-test"
  }
}

# 2) Get three AZs in the chosen region
data "aws_availability_zones" "available" {
  state = "available"
}

# 3) Three public subnets (map_public_ip_on_launch = true)
#    CIDRs are spaced /20 blocks; adjust as desired.
locals {
  public_subnet_defs = {
    "public-az-1" = { az_index = 0, cidr = "10.90.0.0/20"  }
    "public-az-2" = { az_index = 1, cidr = "10.90.16.0/20" }
    "public-az-3" = { az_index = 2, cidr = "10.90.32.0/20" }
  }
}

resource "aws_subnet" "cp_kraft_test_public" {
  for_each                = local.public_subnet_defs
  vpc_id                  = aws_vpc.cp_kraft_test.id
  cidr_block              = each.value.cidr
  availability_zone       = data.aws_availability_zones.available.names[each.value.az_index]
  map_public_ip_on_launch = true

  tags = {
    Name = "cp-kraft-test-${each.key}"
  }
}

# 4) Internet Gateway
resource "aws_internet_gateway" "cp_kraft_test" {
  vpc_id = aws_vpc.cp_kraft_test.id

  tags = {
    Name = "cp-kraft-test-igw"
  }
}

# 5) Route table for public subnets
resource "aws_route_table" "cp_kraft_test_public" {
  vpc_id = aws_vpc.cp_kraft_test.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cp_kraft_test.id
  }

  # (Optional IPv6 route if you enable IPv6 on the VPC)
  # route {
  #   ipv6_cidr_block = "::/0"
  #   gateway_id      = aws_internet_gateway.cp_kraft_test.id
  # }

  tags = {
    Name = "cp-kraft-test-public-rt"
  }
}

# 6) Associate all public subnets with the public route table
resource "aws_route_table_association" "cp_kraft_test_public_assoc" {
  for_each       = aws_subnet.cp_kraft_test_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.cp_kraft_test_public.id
}

# 7) Security group that allows ALL inbound and ALL outbound (internet-open)
resource "aws_security_group" "cp_kraft_test_allow_all" {
  name        = "cp-kraft-test-allow-all"
  description = "Allow all inbound and outbound"
  vpc_id      = aws_vpc.cp_kraft_test.id

  # Inbound: everything from everywhere (IPv4 + IPv6)
  ingress {
    description = "Allow all inbound (IPv4)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow all inbound (IPv6)"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  # Outbound: everything to everywhere (IPv4 + IPv6)
  egress {
    description = "Allow all outbound (IPv4)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "Allow all outbound (IPv6)"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "cp-kraft-test-allow-all"
  }
}